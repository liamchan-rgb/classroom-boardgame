"""Validate actual payload and browser behavior; no engine test or App mutation."""
from pathlib import Path
from PIL import Image
import json,hashlib,re,asyncio,subprocess
from playwright.async_api import async_playwright
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def js(p,d): (ROOT/p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
manifest=[];errors=[]
reuse=json.loads((ROOT/'sources/reuse-manifest.json').read_text())
reuses={a['file']:a for a in reuse}
effects=json.loads((ROOT/'reused-effects-manifest.json').read_text())
effectmap={a['file']:a for a in effects['effects']}
for p in sorted((ROOT/'assets').rglob('*.png')):
    relative=str(p.relative_to(ROOT));im=Image.open(p);im.load();alpha=im.convert('RGBA').getchannel('A');b=alpha.getbbox();amin,amax=alpha.getextrema()
    row=dict(id=p.stem,file=relative,widthPx=im.width,heightPx=im.height,mode=im.mode,colorSpace='sRGB',hasTransparentPixels=amin==0,alphaBoundsPx=b,sha256=sha(p),decodedBytesRGBA=im.width*im.height*4,status='candidate-awaiting-art-review',bakedDynamicText=False,semanticFit='aspectFit full canvas')
    if relative in reuses:
        r=reuses[relative];row.update(templateBinding=r['binding'],source=r['source'],sourceSHA256=r['sourceSHA256'],anchorPx=r['anchorPx'],reuseMethod=r['method'],animation=r['animation'])
        if sha(REPO/r['source'])!=r['sourceSHA256']:errors.append('Changed original: '+r['source'])
    elif relative in effectmap:
        e=effectmap[relative];row.update(effectID=e['effectID'],source='native/ClassroomProbe/Resources/Art/'+p.name,frames=[8,256,256],durationMs=e['durationMs'],stop='transparent terminal frame',reducedMotion=e['reducedMotion'])
        if sha(REPO/row['source'])!=sha(p):errors.append('Effect byte mismatch '+relative)
    else:
        row['source']=str(p.with_suffix('.svg').relative_to(ROOT))
        if p.parent.name=='sprites':
            row['anchorPx']=[32,57];row['directions']=['south','east','north','west'] if '_sheet' in p.stem else ['east' if 'adventurer' in p.stem else 'west'];row['animationManifest']='animation-manifest.json'
        elif p.parent.name=='layers':
            row['sceneManifest']='scene-manifest.json'
            if p.stem.startswith('battle_') or p.stem=='ground_module':row['semanticFit']='nonsemantic environment may crop'
        else:row['anchorPx']=[32,32];row['direction']='east base arrow, rotate to world ray if arrow; otherwise neutral';row['stop']='static';row['reducedMotion']='same static glyph'
        if re.search(r'<text\b',p.with_suffix('.svg').read_text()):errors.append('Asset bakes text '+relative)
    manifest.append(row)
js('asset-manifest.json',dict(version=4,status='awaiting-art-review',assets=manifest,counts=dict(runtimeReuse=len(reuse),bytePreservedEffects=len(effectmap),newPNG=len(manifest)-len(reuse)-len(effectmap)),noAppOrRuleWrites=True,manifestDirectionsAreNot16Way=True))
for ratio,W in [('16x9',1920),('4x3',1440)]:
    for phase in ['exploration','player','monster']:
        im=Image.open(ROOT/f'previews/public_{phase}_{ratio}.png');assert im.size==(W,1080)
textchecks=json.loads((ROOT/'evidence/text-bounds.json').read_text())
for r in textchecks:
    if r['outsideCanvas']:errors.append('Text overflow '+r['file'])
for p in (ROOT/'assets').rglob('*'):
    if p.is_file() and not p.name.isascii():errors.append('Non-ASCII asset '+str(p))
for source in (ROOT/'sources').glob('public_*.svg'):
    if re.search('node_boss|node_reward',source.read_text()):errors.append('Unknown secret image reference '+source.name)
pilotchecks=[]
for id in ['adventurer','slime']:
    im=Image.open(ROOT/f'assets/sprites/map_{id}_sheet.png').convert('RGBA');assert im.size==(1024,256)
    cells=[]
    for row in range(4):
        for col in range(16):
            cell=im.crop((col*64,row*64,(col+1)*64,(row+1)*64));bb=cell.getchannel('A').getbbox()
            if not bb or bb[0]<4 or bb[1]<4 or bb[2]>60 or bb[3]>60:errors.append(f'Pilot clipped {id}:{row}:{col}:{bb}')
            cells.append(dict(row=row,col=col,alphaBounds=bb))
    pilotchecks.append(dict(templateID=id,cells=cells,frames=64))
js('evidence/sprite-cell-bounds.json',pilotchecks)
mainsha=subprocess.check_output(['git','rev-parse','origin/main'],cwd=REPO,text=True).strip()
changed=subprocess.check_output(['git','diff','--name-only',mainsha],cwd=REPO,text=True).splitlines()
if any(not n.startswith('design/map-battle-ui-b-v4/') for n in changed):errors.append('Scope escaped new directory')
book=[dict(file=f'stage2/ui-integration/evidence/native-previews/public-book-{r}.png',sha256=sha(REPO/f'stage2/ui-integration/evidence/native-previews/public-book-{r}.png'),modified=False) for r in ['16x9','4x3']]
js('evidence/storybook-baseline.json',book)
async def browser_check():
    results={}
    async with async_playwright() as p:
        browser=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        page=await browser.new_page(viewport={'width':1440,'height':1080})
        await page.route('**/*',lambda route:route.abort())
        code=(ROOT/'previews/camera_transition_demo.html').read_text();await page.set_content(code)
        await page.wait_for_function('window.demo?.ready===true')
        assert await page.evaluate('demo.assetCount')==10
        await page.click('#play');await page.wait_for_function('demo.state.phase==="battle"')
        first=await page.evaluate('demo.report()');assert first['order']==['committed','path','arrival','panel-open'];assert first['plays']==1
        await page.click('#play');assert await page.evaluate('demo.state.plays')==1
        await page.click('#attack');await page.wait_for_function('demo.state.down===true')
        await page.click('#attack');assert await page.evaluate('demo.state.attackPlays')==1
        before=await page.evaluate('demo.report()');await page.click('#restore');after=await page.evaluate('demo.report()');assert before['plays']==after['plays'] and before['attackPlays']==after['attackPlays']
        await page.click('#offscreen');assert await page.evaluate('demo.state.camera.x')==.9
        await page.click('#follow');assert await page.evaluate('demo.state.camera.x')==.36
        await page.screenshot(path=str(ROOT/'evidence/demo-terminal-browser.png'),full_page=True)
        results['normal']=after;results['offlineExternalRequestsBlocked']=True;results['publicImageWhitelistCount']=10
        await page.close();page=await browser.new_page(viewport={'width':1440,'height':1080});await page.route('**/*',lambda route:route.abort())
        await page.set_content(code);await page.wait_for_function('window.demo?.ready===true');await page.check('#reduce');await page.click('#play');await page.wait_for_function('demo.state.phase==="battle"');await page.click('#attack')
        reduced=await page.evaluate('demo.report()');assert reduced['down'] and reduced['plays']==1 and reduced['order']==['committed','arrival','panel-open'];results['reducedMotion']=reduced
        # Restore before playback must seed consumed IDs, not restart either channel.
        await page.close();page=await browser.new_page(viewport={'width':1440,'height':1080});await page.route('**/*',lambda route:route.abort())
        await page.set_content(code);await page.wait_for_function('window.demo?.ready===true');await page.click('#restore');await page.click('#play');await page.click('#attack');restored=await page.evaluate('demo.report()');assert restored['plays']==0 and restored['attackPlays']==0;results['restoreBeforePlay']=restored
        await browser.close()
    return results
browser=asyncio.run(browser_check());js('evidence/browser-check.json',browser)
decoded=sum(r['decodedBytesRGBA'] for r in manifest);runtime=sum(r['decodedBytesRGBA'] for r in manifest if r['file'] in reuses)
js('evidence/validation.json',dict(status='pass' if not errors else 'fail',errors=errors,mainBaseline=mainsha,assetsDecoded=len(manifest),previewCount=len(list((ROOT/'previews').glob('*.png'))),corePreviewCount=6,textOutsideCanvas=0 if not any(r['outsideCanvas'] for r in textchecks) else 'see report',pilotCellsChecked=128,runtimeReuseRGBABytes=runtime,allAssetsRGBABytes=decoded,payloadBytes=sum(p.stat().st_size for p in (ROOT/'assets').rglob('*.png')),sourceScope='new design/map-battle-ui-b-v4 only',storyBookBaselineUnchanged=True,appTests=False,nativeTests=False,physicalDeviceVerified=False,artApproved=False,notes=['RGBA sums are an estimate if every asset were decoded, not measured live memory.','Text bbox report is canvas bounds; visual safe regions/HUD require review.','No IPA build; browser checks are offline display design only.']))
assert not errors,errors
print('PASS',len(manifest),'PNG assets; 6 main previews; 128 pilot cells; offline one-shot/restore/reduced-motion checks')
