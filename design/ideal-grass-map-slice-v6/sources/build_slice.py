from pathlib import Path
import ast,asyncio,base64,json
from playwright.async_api import async_playwright
R=Path(__file__).resolve().parents[1]
metadata=json.loads((R/'module-manifest.json').read_text())
# Read literal CSS/JS only; never run the previous builder or write a prior version.
tree=ast.parse((R/'sources/v5-builder-reference.py.txt').read_text())
for node in tree.body:
    if isinstance(node,ast.Assign):
        names=[x.id for x in node.targets if isinstance(x,ast.Name)]
        if 'css' in names:css=ast.literal_eval(node.value)
        if 'js' in names:js=ast.literal_eval(node.value.func.value)
palette={'grass':dict(ground='#829444',edge='#695d36',road='#c6a56d',highlight='#e3cb90',rut='#927947',specks=['#d5ba86','#b89c6b','#ab905e'])}
js=js.replace('TOKENS',json.dumps(palette))
js=js.replace("const paths={};for(const biome of ['grass','snow','volcano'])paths[biome]='../assets/atlases/'+biome+'_modules.png';for(const k of ['adventurer','ranger','spellblade','dragon_knight'])paths[k]='../assets/characters/class_'+k+'_portrait.png';", "const MODULES="+json.dumps(metadata)+";const paths={terrain:'../assets/terrain_atlas.png',scenery:'../assets/scenery_atlas.png',landmark:'../assets/landmark_atlas.png',hero:'../assets/adventurer_sheet.png',ranger:'../assets/class_ranger_portrait.png',spellblade:'../assets/class_spellblade_portrait.png'};")
js=js.replace("biome=q.get('biome')||'grass'","biome='grass'")
js=js.replace("progress=.55,zoom=1", "progress=.55,zoom=1,walking=false,frameIndex=7,terrainCache=null,terrainKey=null")
def replace_function(start,end,body):
    global js
    a=js.index(start);b=js.index(end,a);js=js[:a]+body+'\n'+js[b:]
replace_function('function texture(){','function drawRoad(',r'''
function texture(){const key=[canvas.width,canvas.height,seed,zoom,layoutName].join(':');if(key===terrainKey&&terrainCache){ctx.drawImage(terrainCache,0,0);return}const basis=projection({x:0,y:0}),scale=basis.scale/1138,tile=264*scale,step=152*scale;
 const off=document.createElement('canvas');off.width=canvas.width;off.height=canvas.height;const c=off.getContext('2d');c.imageSmoothingEnabled=false;c.fillStyle='#849846';c.fillRect(0,0,off.width,off.height);
 for(let row=Math.floor(-basis.y/step)-1;row<(canvas.height-basis.y)/step+1;row++)for(let col=Math.floor(-basis.x/step)-1;col<(canvas.width-basis.x)/step+1;col++){
 const rand=rng(seed+31+Math.imul(row,73856093)+Math.imul(col,19349663)),material=rand()>.81?3:0,rect=MODULES.terrain[material].sourceRect,patch=document.createElement('canvas');patch.width=256;patch.height=256;const p=patch.getContext('2d');p.imageSmoothingEnabled=false;const sx=rect[0]+20+rand()*100,sy=rect[1]+20+rand()*100;p.drawImage(images.terrain,sx,sy,490,490,0,0,256,256);
 p.globalCompositeOperation='destination-in';const mask=p.createRadialGradient(128,128,52,128,128,128);mask.addColorStop(0,'#000');mask.addColorStop(.45,'#000d');mask.addColorStop(.85,'#0007');mask.addColorStop(1,'#0000');p.fillStyle=mask;p.fillRect(0,0,256,256);c.drawImage(patch,basis.x+col*step+(rand()-.5)*30*scale,basis.y+row*step+(rand()-.5)*30*scale,tile,tile)}
 // A quiet cool-to-warm environment gradient remains below entities and HUD.
 const light=c.createLinearGradient(0,0,off.width,off.height);light.addColorStop(0,'#fff0a916');light.addColorStop(.5,'#ffffff00');light.addColorStop(1,'#163e5327');c.fillStyle=light;c.fillRect(0,0,off.width,off.height);terrainCache=off;terrainKey=key;ctx.drawImage(off,0,0)}
''')
replace_function('function drawRoad(','function distance(',r'''
function corridor(c,width,jitter){const sides=[[],[]];for(let i=0;i<=140;i++){const t=i/140,a=at(c,t),before=at(c,Math.max(0,t-.003)),after=at(c,Math.min(1,t+.003)),angle=Math.atan2(after.y-before.y,after.x-before.x),r=width/2+(Math.sin(i*1.7)*1.1+Math.sin(i*.41)*1.5)*jitter*zoom;for(const [k,s]of [-1,1].entries())sides[k].push([Math.round(a.x-Math.sin(angle)*s*r),Math.round(a.y+Math.cos(angle)*s*r)])}const p=new Path2D();sides[0].concat(sides[1].reverse()).forEach(([x,y],i)=>i?p.lineTo(x,y):p.moveTo(x,y));p.closePath();return p}
function drawRoad(c,index){const p=PALETTES.grass;trace(c);ctx.strokeStyle='#8e75433b';ctx.lineWidth=37*zoom;ctx.stroke();const border=corridor(c,30*zoom,1),core=corridor(c,25*zoom,.8);ctx.fillStyle='#b0956170';ctx.fill(border);ctx.save();ctx.clip(core);
 const tex=document.createElement('canvas');tex.width=96;tex.height=96;const t=tex.getContext('2d');t.imageSmoothingEnabled=false;const r=MODULES.terrain[2].sourceRect;t.drawImage(images.terrain,r[0]+32,r[1]+32,512,512,0,0,96,96);const pattern=ctx.createPattern(tex,'repeat'),basis=projection({x:0,y:0});pattern.setTransform(new DOMMatrix().translate(basis.x,basis.y).scale(basis.scale/1138));ctx.fillStyle=pattern;ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle='#e7c88821';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.restore();
 const rand=rng(seed+index*89+50);for(let i=0;i<130;i++){const u=rand(),a=at(c,u),b=at(c,Math.min(1,u+.003)),angle=Math.atan2(b.y-a.y,b.x-a.x),side=rand()>.5?1:-1,n=side*(13+rand()*4)*zoom;ctx.globalAlpha=.25+rand()*.35;ctx.fillStyle=i%3?'#758b41':'#b4a465';ctx.fillRect(Math.round(a.x-Math.sin(angle)*n),Math.round(a.y+Math.cos(angle)*n),2+rand()*3,2+rand()*3)}ctx.globalAlpha=1}
''')
replace_function('function sprite(','let placements=',r'''
function sprite(cell,x,y,size,alpha=1,kind='scenery'){const m=MODULES.sceneryAndLandmarks.find(m=>m.kind===kind&&m.cell===cell),r=m.sourceRect,s=size/r[2];ctx.globalAlpha=alpha;if(kind==='landmark'||cell<3){ctx.save();ctx.translate(x+size*.09,y+size*.02);ctx.scale(1,.35);const g=ctx.createRadialGradient(0,0,0,0,0,size*.44);g.addColorStop(0,'#102c4634');g.addColorStop(.6,'#102c461b');g.addColorStop(1,'#102c4600');ctx.fillStyle=g;ctx.fillRect(-size*.44,-size*.44,size*.88,size*.88);ctx.restore()}ctx.imageSmoothingEnabled=false;ctx.drawImage(images[kind],...r,x-m.anchorPx[0]*s,y-m.anchorPx[1]*s,r[2]*s,r[3]*s);ctx.globalAlpha=1}
''')
replace_function('function decorations(','function shadow(',r'''
function decorations(nodes,roads){const rand=rng(seed);placements=[];function blocked(p,large){if(nodes.some(n=>distance(p,n)<(large?108:45)*zoom))return true;if(large&&nodes.some(n=>n.x>p.x-p.size*.5-20&&n.x<p.x+p.size*.5+20&&n.y>p.y-p.size*1.25-20&&n.y<p.y+p.size*.18+20))return true;if(roads.some(r=>Array.from({length:65},(_,j)=>at(r.c,j/64)).some(a=>large?(a.x>p.x-p.size*.5-15&&a.x<p.x+p.size*.5+15&&a.y>p.y-p.size*1.25-15&&a.y<p.y+p.size*.18+15):distance(p,a)<25*zoom)))return true;return false}
 for(let i=0;i<58;i++){const n={x:-.18+rand()*1.38,y:.02+rand()*1.08},screen=projection(n),cell=[0,1,0,2,1,3][i%6],size=(cell===3?120:cell===2?205:186)*(0.83+rand()*.30)*zoom,p={cell,x:screen.x,y:screen.y,size,id:i};if(blocked(p,true)||placements.some(d=>distance(p,d)<(p.size+d.size)*.3))continue;placements.push(p);
 for(let j=0;j<2;j++){const angle=rand()*Math.PI*2,k={cell:[3,4,5][(i+j)%3],x:p.x+Math.cos(angle)*95*zoom,y:p.y+Math.sin(angle)*45*zoom,size:(65+rand()*33)*zoom,id:100+i*2+j};if(!blocked(k,false))placements.push(k)}}
 // Small edge-side flowers soften the road shoulders without hiding feet.
 for(const [ri,r]of roads.entries())for(let i=1;i<6;i++){const a=at(r.c,i/6),b=at(r.c,Math.min(1,i/6+.003)),angle=Math.atan2(b.y-a.y,b.x-a.x),side=(i+ri)%2?1:-1,p={cell:i%3===0?4:5,x:a.x-Math.sin(angle)*side*48*zoom,y:a.y+Math.cos(angle)*side*48*zoom,size:60*zoom,id:300+ri*10+i};if(!blocked(p,false))placements.push(p)}return placements}
''')
replace_function('function unit(','function landmark(',r'''
function unit(template,id,x,y,active=false){shadow(x,y-3,18*zoom,5*zoom);if(active){ctx.strokeStyle='#fff1aa';ctx.lineWidth=2;ctx.beginPath();ctx.ellipse(x,y-1,22*zoom,7*zoom,0,0,Math.PI*2);ctx.stroke()}
 if(template==='adventurer'){const f=MODULES.adventurerFrames[walking?frameIndex:7],r=f.sourceRect,s=.22*zoom;ctx.imageSmoothingEnabled=false;ctx.drawImage(images.hero,...r,x-f.anchorPx[0]*s,y-f.anchorPx[1]*s,r[2]*s,r[3]*s)}else{ctx.imageSmoothingEnabled=false;ctx.drawImage(images[template],x-38*zoom,y-76*zoom,76*zoom,76*zoom)}ctx.fillStyle='#24464ee0';ctx.beginPath();ctx.roundRect(x-15,y+4,30,22,5);ctx.fill();ctx.fillStyle='#fff';ctx.textAlign='center';ctx.font='16px sans-serif';ctx.fillText(id,x,y+20)}
''')
js=js.replace("const size=174*zoom,candidates=", "const size=(n.id===1?190:143)*zoom,candidates=")
js=js.replace("cell:n.id===1?3:4", "cell:n.id===1?(seed%2?0:3):(seed%2?1:4)")
js=js.replace("sprite(o.cell,o.x,o.y,o.size)", "sprite(o.cell,o.x,o.y,o.size,1,o.type==='landmark'?'landmark':'scenery')")
js=js.replace("template:'spellblade',id:'P3',x:nodes[1].x,y:nodes[1].y", "template:'spellblade',id:'P3',x:nodes[1].x+34*zoom,y:nodes[1].y+18*zoom")
js=js.replace("sprite(1,65,canvas.height+48,240,.96);sprite(2,canvas.width-90,canvas.height+56,270,.96);", r'''
 ctx.save();ctx.filter='blur(2.5px)';sprite(2,45,canvas.height+35,265,.90);sprite(0,canvas.width-55,canvas.height+28,235,.92);ctx.restore();
 const vignette=ctx.createRadialGradient(canvas.width*.48,canvas.height*.48,canvas.height*.28,canvas.width*.5,canvas.height*.5,canvas.width*.62);vignette.addColorStop(0,'#18394000');vignette.addColorStop(.68,'#102e3920');vignette.addColorStop(1,'#102b4c6b');ctx.fillStyle=vignette;ctx.fillRect(0,0,canvas.width,canvas.height);
 ctx.save();ctx.filter='blur(7px)';ctx.fillStyle='#fff1ab0a';for(const shift of [0,220]){ctx.beginPath();ctx.moveTo(-70+shift,-20);ctx.lineTo(70+shift,-20);ctx.lineTo(670+shift,canvas.height*.68);ctx.lineTo(400+shift,canvas.height*.68);ctx.closePath();ctx.fill()}ctx.restore();
 const sun=ctx.createRadialGradient(70,0,0,70,0,canvas.width*.58);sun.addColorStop(0,'#fff1aa43');sun.addColorStop(.45,'#ffe9a014');sun.addColorStop(1,'#ffe9a000');ctx.fillStyle=sun;ctx.fillRect(0,0,canvas.width,canvas.height);
''')
js=js.replace("playing=true;const reduced", "playing=true;walking=true;const reduced")
js=js.replace("progress=Math.min(1,(t-start)/1800);render();", "progress=Math.min(1,(t-start)/1800);frameIndex=Math.floor((t-start)/150)%4;render();")
js=js.replace("progress=Math.min(1,(t-start)/1800);frameIndex=Math.floor((t-start)/150)%4;render();","const age=Math.max(0,t-start);progress=Math.min(1,age/1800);frameIndex=Math.floor(age/150)%4;render();")
js=js.replace("playing=false}};", "playing=false;walking=false;frameIndex=7;render()}};")
js=js.replace("groundMethod:'overlap feather; not seamless butt join'", "groundMethod:'cached world-space radial blend of measured material rectangles',spriteFrame:walking?frameIndex:7,idealReference:'reference/ideal-effect-user.jpg',nativeImplemented:false")
doc='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>理想效果基准 · 草地小样v6</title><link rel="stylesheet" href="../sources/slice.css"><body><canvas aria-label="理想效果基准草地模块组装与人物移动示意"></canvas><div class="name">安然</div><div class="controls"><button data-action="play" aria-label="播放已提交移动的显示样例">▷</button><button data-action="seed" aria-label="更换装饰种子">⟳</button><button data-action="zoom" aria-label="缩放显示">＋</button></div><script src="../sources/slice.js"></script></body></html>'
(R/'sources/slice.css').write_text(css+'\n');(R/'sources/slice.js').write_text('\n'.join(line.rstrip() for line in js.strip().splitlines())+'\n');(R/'previews/index.html').write_text(doc+'\n')

async def export():
    embedded=doc.replace('<link rel="stylesheet" href="../sources/slice.css">','<style>'+css+'</style>').replace('<script src="../sources/slice.js"></script>','<script>'+js+'</script>')
    files={'terrain':'terrain_atlas','scenery':'scenery_atlas','landmark':'landmark_atlas','hero':'adventurer_sheet','ranger':'class_ranger_portrait','spellblade':'class_spellblade_portrait'}
    lookup={k:'data:image/png;base64,'+base64.b64encode((R/'assets'/f'{v}.png').read_bytes()).decode() for k,v in files.items()}
    start=embedded.index("const paths={terrain:");end=embedded.index(';',start);embedded=embedded[:start]+'const paths='+json.dumps(lookup)+embedded[end:]
    report=[]
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        for ratio,w,h in [('16x9',1920,1080),('4x3',1440,1080)]:
            page=await b.new_page(viewport={'width':w,'height':h});await page.route('http**/*',lambda r:r.abort());await page.set_content(embedded);await page.evaluate('sample.ready');await page.evaluate('document.fonts.ready')
            for seed in [17,30]:
                await page.evaluate('(s)=>sample.set("grass",s,"A")',seed);await page.screenshot(path=str(R/'previews'/f'grass_seed{seed}_{ratio}.png'));state=await page.evaluate('sample.state');assert state['publicRoads']==[[1,2],[2,3]] and state['decorCount']>8,state;report.append({'aspect':ratio,**state})
            await page.evaluate('sample.set("grass",17,"A");sample.setProgress(0)');await page.screenshot(path=str(R/'previews'/f'move_start_{ratio}.png'))
            await asyncio.wait_for(page.evaluate('sample.play()'),timeout=30);await page.screenshot(path=str(R/'previews'/f'move_arrival_{ratio}.png'));state=await page.evaluate('sample.state');assert state['movingCurveParameter']==1;target=next(n['nodeAnchor'] for n in state['landmarks'] if n['nodeID']==2);assert all(abs(a-b)<.01 for a,b in zip(state['movingFoot'],target));await page.emulate_media(reduced_motion='reduce');await page.evaluate('sample.setProgress(0)');await asyncio.wait_for(page.evaluate('sample.play()'),timeout=5);assert (await page.evaluate('sample.state'))['movingCurveParameter']==1;await page.emulate_media(reduced_motion='no-preference')
            await page.close()
        context=await b.new_context(viewport={'width':1920,'height':1080},record_video_dir=str(R/'evidence/video-temp'),record_video_size={'width':1280,'height':720})
        page=await context.new_page();await page.route('http**/*',lambda r:r.abort());await page.set_content(embedded);await page.evaluate('sample.ready');await page.evaluate('sample.setProgress(0)');await page.wait_for_timeout(300);await asyncio.wait_for(page.evaluate('sample.play()'),timeout=30);await page.wait_for_timeout(600);video=page.video;await context.close();await video.save_as(str(R/'previews/grass_move_16x9.webm'));await video.delete()
        import shutil
        shutil.rmtree(R/'evidence/video-temp');await b.close()
    (R/'evidence/browser-checks.json').write_text(json.dumps(dict(status='pass',runs=report,movementArrival='pass',arrivalEqualsTargetNode='pass',reducedMotionTerminal='pass',offline=True,engineCalls=0,nativeVerified=False,artApproved=False),ensure_ascii=False,indent=2)+'\n')
asyncio.run(export())
