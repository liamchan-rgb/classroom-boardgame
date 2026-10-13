from pathlib import Path
import asyncio,base64,json
from playwright.async_api import async_playwright
R=Path(__file__).resolve().parents[1]
js=(R/'previews/design-base.js').read_text().replace("let rendered=false", "let reviewLighting=true;let rendered=false")
js=js.replace('../assets/','../Native/Resources/Art/')
# The browser companion illustrates the same 2D projection principle. It is not SpriteKit output.
helper=r'''
const maskCache=new Map();
function projectedMask(kind,r,anchor,x,y,scale,opacity=.24){if(!reviewLighting)return;const key=kind+':'+r.join(','),source=kind==='hero'?images.hero:images[kind];let mask=maskCache.get(key);if(!mask){mask=document.createElement('canvas');mask.width=r[2];mask.height=r[3];const c=mask.getContext('2d');c.drawImage(source,...r,0,0,r[2],r[3]);c.globalCompositeOperation='source-in';c.fillStyle='#0c2538';c.fillRect(0,0,r[2],r[3]);maskCache.set(key,mask)}ctx.save();ctx.globalAlpha=opacity;ctx.filter='blur(1.3px)';ctx.transform(scale,0,-.85*scale,-.40*scale,x-anchor[0]*scale+.85*anchor[1]*scale,y+.40*anchor[1]*scale);ctx.drawImage(mask,0,0);ctx.restore()}
function entityProjection(o){const kind=o.type==='landmark'?'landmark':'scenery';if(kind==='scenery'&&o.cell>=3)return;const m=MODULES.sceneryAndLandmarks.find(m=>m.kind===kind&&m.cell===o.cell);projectedMask(kind,m.sourceRect,m.anchorPx,o.x,o.y,o.size/m.sourceRect[2],.25)}
'''
js=js.replace('function sprite(',helper+'\nfunction sprite(')
js=js.replace("if(kind==='landmark'||cell<3)","if(reviewLighting&&(kind==='landmark'||cell<3))")
js=js.replace("function shadow(x,y,w,h){ctx.save();", "function shadow(x,y,w,h){if(!reviewLighting)return;ctx.save();")
js=js.replace("if(template==='adventurer'){const f=", "if(template==='adventurer'){const f=")
js=js.replace("r=f.sourceRect,s=.22*zoom;ctx.imageSmoothingEnabled", "r=f.sourceRect,s=.22*zoom;projectedMask('hero',r,f.anchorPx,x,y,s,.23);ctx.imageSmoothingEnabled")
js=js.replace("objects.sort((a,b)=>a.y-b.y);", "for(const o of objects)if(o.type!=='unit')entityProjection(o);objects.sort((a,b)=>a.y-b.y);")
start=js.index(' const vignette=');end=js.index(' window.lastRender=',start)
js=js[:start]+' if(reviewLighting){'+js[start:end]+'}\n'+js[end:]
js=js.replace("idealReference:'reference/ideal-effect-user.jpg'", "idealReference:'reference/ideal-effect-user.jpg',designCompanion:true,projectedLighting:reviewLighting")
js+="\nwindow.review={setLighting(on){reviewLighting=on;render()},get lighting(){return reviewLighting}};document.querySelector('[data-action=light]').onclick=()=>review.setLighting(!reviewLighting);\n"
css=(R/'previews/design-base.css').read_text()
doc='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>草地投影设计参考 · 非SpriteKit实测</title><link rel="stylesheet" href="design-base.css"><body><canvas></canvas><div class="name">安然</div><div class="controls"><button data-action="play" aria-label="移动显示示例">▷</button><button data-action="light" aria-label="比较新增投影">☀</button><button data-action="seed" aria-label="更换装饰">⟳</button><button data-action="zoom" aria-label="缩放">＋</button></div><script src="design-preview.js"></script></body></html>'
(R/'previews/design-preview.js').write_text('\n'.join(line.rstrip() for line in js.splitlines())+'\n');(R/'previews/design-preview.html').write_text(doc+'\n')
async def export():
    embedded=doc.replace('<link rel="stylesheet" href="design-base.css">','<style>'+css+'</style>').replace('<script src="design-preview.js"></script>','<script>'+js+'</script>')
    files={'terrain':'terrain_atlas','scenery':'scenery_atlas','landmark':'landmark_atlas','hero':'adventurer_sheet','ranger':'class_ranger_portrait','spellblade':'class_spellblade_portrait'}
    lookup={k:'data:image/png;base64,'+base64.b64encode((R/'Native/Resources/Art'/f'{v}.png').read_bytes()).decode() for k,v in files.items()}
    start=embedded.index("const paths={terrain:");end=embedded.index(';',start);embedded=embedded[:start]+'const paths='+json.dumps(lookup)+embedded[end:]
    evidence=[]
    async with async_playwright() as p:
        browser=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        for aspect,w,h in [('16x9',1920,1080),('4x3',1440,1080)]:
            page=await browser.new_page(viewport={'width':w,'height':h});await page.route('http**/*',lambda r:r.abort());await page.set_content(embedded);await page.evaluate('sample.ready');await page.evaluate('document.fonts.ready')
            for lighting,name in [(False,'base'),(True,'sun')]:
                await page.evaluate('(on)=>review.setLighting(on)',lighting);await page.screenshot(path=str(R/'previews'/f'design_{name}_{aspect}.png'));state=await page.evaluate('sample.state');assert state['publicRoads']==[[1,2],[2,3]];assert state['projectedLighting']==lighting;evidence.append({'aspect':aspect,'mode':name,'publicRoads':state['publicRoads'],'native':False})
            await asyncio.wait_for(page.evaluate('sample.play()'),timeout=30);assert (await page.evaluate('sample.state'))['movingCurveParameter']==1
            await page.close()
        await browser.close()
    (R/'evidence/browser-design-checks.json').write_text(json.dumps({'status':'pass','runs':evidence,'movementArrival':'pass','offline':True,'nativeVerified':False,'note':'Browser design companion only; no SpriteKit runtime or performance claim'},indent=2)+'\n')
asyncio.run(export())
