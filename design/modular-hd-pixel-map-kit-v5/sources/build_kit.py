from pathlib import Path
import asyncio,base64,json,math,hashlib
from playwright.async_api import async_playwright
R=Path(__file__).resolve().parents[1]
palettes={
 'grass':dict(ground='#8daa48',edge='#655338',road='#c8ae78',highlight='#e4cd97',rut='#96834d',specks=['#dfc795','#b09866','#a38c57']),
 'snow':dict(ground='#e3e9ee',edge='#91a9bc',road='#c4d2db',highlight='#edf1ed',rut='#9badbd',specks=['#e9edef','#afc3d2','#d7e2e8']),
 'volcano':dict(ground='#524d4b',edge='#302d2c',road='#807267',highlight='#a4917b',rut='#665c55',specks=['#a1907c','#71665c','#968571'])}
(R/'road-style-tokens.json').write_text(json.dumps(dict(palettes=palettes,widthDesignPx=24,referenceWorldScale=1138,edgeFeatherDesignPx=5,rutOffsetDesignPx=4,curveBendLimit=.12,texture='seeded small pixel clusters; visual seed only',movement='same cubic centreline as road',cost='original graph edge count, never visual spline length'),indent=2)+'\n')
for biome,p in palettes.items():
    for shape,path in [('straight','M16 128L368 128'),('curve','M16 210C116 210 268 46 368 46'),('junction','M20 220Q190 146 190 126M190 126Q196 66 348 28M190 126Q260 168 364 210')]:
        specks=''.join(f'<rect x="{12+(i*73)%360}" y="{8+(i*41)%240}" width="{2+i%4}" height="{2+i%3}" fill="{p["specks"][i%3]}" opacity=".7"/>' for i in range(170))
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="384" height="256" viewBox="0 0 384 256"><defs><mask id="road" maskUnits="userSpaceOnUse" x="0" y="0" width="384" height="256"><rect width="384" height="256" fill="black"/><path d="{path}" fill="none" stroke="white" stroke-width="24" stroke-linecap="round"/></mask></defs><path d="{path}" fill="none" stroke="{p["edge"]}" stroke-width="34" opacity=".12" stroke-linecap="round"/><path d="{path}" fill="none" stroke="{p["edge"]}" stroke-width="29" opacity=".25" stroke-linecap="round"/><path d="{path}" fill="none" stroke="{p["road"]}" stroke-width="24" stroke-linecap="round"/><path d="{path}" fill="none" stroke="{p["highlight"]}" stroke-width="15" opacity=".27" stroke-linecap="round"/><g mask="url(#road)">{specks}</g></svg>'
        (R/'assets/roads'/f'{biome}_{shape}.svg').write_text(svg+'\n')

css='''*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#87a448;font-family:"Noto Sans CJK SC",sans-serif;color:#244e5d}canvas{width:100%;height:100%;display:block;image-rendering:pixelated}.name{position:fixed;top:32px;left:42px;padding:12px 23px;border:1px solid #ffffffb0;border-radius:18px;background:#f5faf3b5;backdrop-filter:blur(20px);font-size:25px;font-weight:600;box-shadow:inset 0 1px 1px #fff9,0 8px 22px #16374224}.controls{position:fixed;top:32px;right:42px;display:flex;gap:10px}.controls button{width:50px;height:50px;border:1px solid #fff9;border-radius:16px;background:linear-gradient(140deg,#ffffffc9,#e4eff375);backdrop-filter:blur(16px);font-size:25px;color:#285564;box-shadow:inset 0 2px 2px #fffc,0 5px 18px #1a384324;cursor:pointer}.controls button:focus-visible{outline:3px solid #fff0ad;outline-offset:3px}'''
js=r'''
const PALETTES=TOKENS;
const paths={};for(const biome of ['grass','snow','volcano'])paths[biome]='../assets/atlases/'+biome+'_modules.png';for(const k of ['adventurer','ranger','spellblade','dragon_knight'])paths[k]='../assets/characters/class_'+k+'_portrait.png';
const q=new URLSearchParams(location.search);let biome=q.get('biome')||'grass',seed=Number(q.get('seed')||17),layoutName=q.get('layout')||'A',progress=.55,zoom=1;let rendered=false,playing=false;const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d'),images={};
function rng(v){let x=v>>>0;return ()=>{x=(Math.imul(x,1664525)+1013904223)>>>0;return x/4294967296}}
const layouts={A:[[.10,.55],[.36,.55],[.62,.26],[.62,.78],[.90,.55]],B:[[.13,.63],[.39,.44],[.66,.20],[.68,.77],[.91,.49]],C:[[.11,.39],[.40,.59],[.66,.27],[.67,.78],[.90,.53]]};
// Only public revealed edges are passed to the composer; hidden edges are not reserved or drawn.
const visibleEdges=[[1,2],[2,3]];
function world(){return layouts[layoutName].map(([x,y],i)=>({id:i+1,x,y,revealed:i<3,kind:i===0?'camp':'watchtower'}))}
function projection(n){const w=canvas.width,h=canvas.height,s=Math.min(w-260,(h-340)/.65)*zoom;const ys=layouts[layoutName].map(p=>p[1]),cy=(Math.min(...ys)+Math.max(...ys))/2;return {x:w*.5+(n.x-.50)*s,y:h*.55+(n.y-cy)*s,scale:s}}
function bezier(a,b,bend){const dx=b.x-a.x,dy=b.y-a.y,len=Math.hypot(dx,dy),nx=-dy/len,ny=dx/len;return [a,{x:a.x+dx*.33+nx*bend,y:a.y+dy*.33+ny*bend},{x:a.x+dx*.67-nx*bend*.45,y:a.y+dy*.67-ny*bend*.45},b]}
function at(c,t){const s=1-t;return {x:s*s*s*c[0].x+3*s*s*t*c[1].x+3*s*t*t*c[2].x+t*t*t*c[3].x,y:s*s*s*c[0].y+3*s*s*t*c[1].y+3*s*t*t*c[2].y+t*t*t*c[3].y}}
function trace(c){ctx.beginPath();ctx.moveTo(c[0].x,c[0].y);ctx.bezierCurveTo(c[1].x,c[1].y,c[2].x,c[2].y,c[3].x,c[3].y)}
function curves(){const nodes=world().map(n=>({...n,...projection(n)}));return visibleEdges.map(([a,b],i)=>{const na=nodes[a-1],nb=nodes[b-1];return {ids:[a,b],c:bezier(na,nb,Math.min(48,Math.hypot(nb.x-na.x,nb.y-na.y)*.10)*(i?-.7:1))}})}
function texture(){ctx.fillStyle=PALETTES[biome].ground;ctx.fillRect(0,0,canvas.width,canvas.height);const basis=projection({x:0,y:0}),tile=256*basis.scale/1138,step=224*basis.scale/1138;
 for(let row=Math.floor(-basis.y/step)-1;row<(canvas.height-basis.y)/step+1;row++)for(let col=Math.floor(-basis.x/step)-1;col<(canvas.width-basis.x)/step+1;col++){const x=basis.x+col*step,y=basis.y+row*step,rand=rng(seed+11+Math.imul(row,73856093)+Math.imul(col,19349663));const off=document.createElement('canvas');off.width=256;off.height=256;const t=off.getContext('2d');t.imageSmoothingEnabled=false;const sx=90+Math.floor(rand()*40),sy=90+Math.floor(rand()*40);t.drawImage(images[biome],sx,sy,280,280,0,0,256,256);t.globalCompositeOperation='destination-in';for(const axis of ['x','y']){const g=axis==='x'?t.createLinearGradient(0,0,256,0):t.createLinearGradient(0,0,0,256);g.addColorStop(0,'#0000');g.addColorStop(.07,'#000');g.addColorStop(.93,'#000');g.addColorStop(1,'#0000');t.fillStyle=g;t.fillRect(0,0,256,256)}ctx.drawImage(off,x,y,tile,tile)}
 const light=ctx.createLinearGradient(0,0,canvas.width,canvas.height);light.addColorStop(0,'#fff5c81a');light.addColorStop(.5,'#ffffff00');light.addColorStop(1,'#0e2d451c');ctx.fillStyle=light;ctx.fillRect(0,0,canvas.width,canvas.height)}
function drawRoad(c,index){const p=PALETTES[biome],width=24*zoom;ctx.lineCap='round';for(const [size,alpha,col]of [[36,.08,p.edge],[31,.16,p.edge],[27,.33,p.edge],[24,1,p.road],[17,.2,p.highlight]]){trace(c);ctx.lineWidth=size*zoom;ctx.globalAlpha=alpha;ctx.strokeStyle=col;ctx.stroke()}ctx.globalAlpha=1;const rand=rng(seed+index*89+50);
 for(let i=0;i<150;i++){let t=rand(),a=at(c,t),b=at(c,Math.min(1,t+.003)),ang=Math.atan2(b.y-a.y,b.x-a.x),n=(rand()-.5)*21*zoom,x=a.x-Math.sin(ang)*n,y=a.y+Math.cos(ang)*n;ctx.fillStyle=p.specks[i%3];ctx.globalAlpha=.35+rand()*.3;ctx.fillRect(Math.round(x),Math.round(y),2+Math.floor(rand()*4),2+Math.floor(rand()*3))}ctx.globalAlpha=1;
 for(const side of [-1,1]){ctx.beginPath();for(let i=0;i<=90;i++){let t=i/90,a=at(c,t),b=at(c,Math.min(1,t+.003)),ang=Math.atan2(b.y-a.y,b.x-a.x),x=a.x-Math.sin(ang)*side*4*zoom,y=a.y+Math.cos(ang)*side*4*zoom;i?ctx.lineTo(x,y):ctx.moveTo(x,y)}ctx.strokeStyle=p.rut;ctx.lineWidth=1.5;ctx.globalAlpha=.16;ctx.stroke()}ctx.globalAlpha=1}
function distance(a,b){return Math.hypot(a.x-b.x,a.y-b.y)}
function sprite(cell,x,y,size,alpha=1){ctx.globalAlpha=alpha;ctx.imageSmoothingEnabled=false;ctx.drawImage(images[biome],(cell%3)*512,Math.floor(cell/3)*512,512,512,x-size*.5,y-size*448/512,size,size);ctx.globalAlpha=1}
let placements=[];
function decorations(nodes,roads){const rand=rng(seed);placements=[];for(let i=0;i<60;i++){const n={x:-.22+rand()*1.47,y:-.03+rand()*1.08},s=projection(n),size=(i%3?150:185)*(1+Math.max(0,n.y-.5)*.16)*zoom,groundR=size*.28;let allowed=true;
 if(nodes.some(a=>distance(s,a)<groundR+118))allowed=false;
 if(roads.some(r=>Array.from({length:45},(_,j)=>at(r.c,j/44)).some(a=>distance(s,a)<groundR+64)))allowed=false;
 if(roads.some(r=>Array.from({length:65},(_,j)=>at(r.c,j/64)).some(a=>a.x>s.x-size*.5-20&&a.x<s.x+size*.5+20&&a.y>s.y-size*.875-20&&a.y<s.y+size*.125+20)))allowed=false;if(placements.some(p=>distance(s,p)<(size+p.size)*.34))allowed=false;
 if(!allowed)continue;const p={cell:rand()>.45?1:2,x:s.x,y:s.y,size,id:i};placements.push(p)}return placements}
function shadow(x,y,w,h){ctx.save();ctx.fillStyle='#18354145';ctx.beginPath();ctx.ellipse(x,y,w,h,-.12,0,Math.PI*2);ctx.fill();ctx.restore()}
function unit(template,id,x,y,active=false){shadow(x,y-3,19*zoom,6*zoom);if(active){ctx.strokeStyle=biome==='snow'?'#a58032':'#fff1a5';ctx.lineWidth=2;ctx.beginPath();ctx.ellipse(x,y-1,25,9,0,0,Math.PI*2);ctx.stroke()}ctx.imageSmoothingEnabled=false;const im=images[template],h=82*zoom,w=82*zoom;ctx.drawImage(im,x-w*.5,y-h,w,h);ctx.fillStyle='#204755d9';ctx.beginPath();ctx.roundRect(x-15,y+4,30,22,6);ctx.fill();ctx.fillStyle='#fff';ctx.textAlign='center';ctx.font='16px sans-serif';ctx.fillText(id,x,y+20)}
function landmark(n,roads){const size=174*zoom,candidates=[[0,-45],[-100,-45],[100,-45],[-125,0],[125,0]];for(const [dx,dy]of candidates){const x=n.x+dx*zoom,y=n.y+dy*zoom;const bad=roads.some(r=>Array.from({length:100},(_,j)=>at(r.c,j/99)).some(p=>p.x>x-size*.5-8&&p.x<x+size*.5+8&&p.y>y-size*.875-8&&p.y<y+size*.125+8));if(!bad)return {type:'landmark',nodeID:n.id,cell:n.id===1?3:4,x,y,size}}return {type:'landmark',nodeID:n.id,cell:n.id===1?3:4,x:n.x-125*zoom,y:n.y-45*zoom,size};}
function render(){if(!rendered)return;canvas.width=innerWidth;canvas.height=innerHeight;ctx.imageSmoothingEnabled=false;texture();const nodes=world().map(n=>({...n,...projection(n)})),roads=curves();for(const [i,r]of roads.entries())drawRoad(r.c,i);const decor=decorations(nodes,roads);
 for(const n of nodes){ctx.fillStyle=n.revealed?(biome==='snow'?'#c7b078':'#d3ba78'):'#466373';ctx.strokeStyle=n.revealed?'#6e6338':'#d9e5e5';ctx.lineWidth=2;ctx.beginPath();ctx.arc(n.x,n.y,n.revealed?13:18,0,Math.PI*2);ctx.fill();ctx.stroke();if(!n.revealed){ctx.fillStyle='#fff';ctx.font='20px sans-serif';ctx.textAlign='center';ctx.fillText('?',n.x,n.y+7)}}
 const moving=at(roads[0].c,progress);const objects=[...decor.map(d=>({...d,type:'decor'})),...nodes.filter(n=>n.revealed).map(n=>landmark(n,roads)),{type:'unit',template:'adventurer',id:'P1',x:moving.x,y:moving.y,active:true},{type:'unit',template:'spellblade',id:'P3',x:nodes[1].x,y:nodes[1].y},{type:'unit',template:'ranger',id:'P2',x:nodes[2].x,y:nodes[2].y}];objects.sort((a,b)=>a.y-b.y);for(const o of objects){if(o.type==='unit')unit(o.template,o.id,o.x,o.y,o.active);else sprite(o.cell,o.x,o.y,o.size)}
 // Front-edge framing uses the same cutout modules, not a full panorama. No UI text is baked into art.
 sprite(1,65,canvas.height+48,240,.96);sprite(2,canvas.width-90,canvas.height+56,270,.96);
 window.lastRender={biome,seed,layout:layoutName,publicRoads:visibleEdges,landmarks:nodes.filter(n=>n.revealed).map(n=>({nodeID:n.id,nodeAnchor:[n.x,n.y],landmarkGround:[landmark(n,roads).x,landmark(n,roads).y]})),movingFoot:[moving.x,moving.y],movingCurveParameter:progress,decorCount:decor.length,topologyUnchanged:true,groundMethod:'overlap feather; not seamless butt join'};
}
async function load(){await Promise.all(Object.entries(paths).map(([k,v])=>new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>{images[k]=im;resolve()};im.onerror=()=>reject(new Error('asset '+k));im.src=v})));rendered=true;render()}
window.sample={ready:load(),set(b,s,l){biome=b;seed=s;layoutName=l;progress=.55;render()},setProgress(t){progress=t;render()},get state(){return window.lastRender},engineCalls:0,async play(){if(playing)return;playing=true;const reduced=matchMedia('(prefers-reduced-motion:reduce)').matches;if(reduced){progress=1;render()}else{const start=performance.now();await new Promise(resolve=>{function tick(t){progress=Math.min(1,(t-start)/1800);render();if(progress<1)requestAnimationFrame(tick);else resolve()}requestAnimationFrame(tick)})}playing=false}};
document.querySelector('[data-action=play]').onclick=()=>sample.play();document.querySelector('[data-action=seed]').onclick=()=>{seed+=13;render()};document.querySelector('[data-action=zoom]').onclick=()=>{zoom=zoom===1?1.2:1;render()};window.onresize=render;
'''.replace('TOKENS',json.dumps(palettes))
doc='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>HD像素模块组装与环境道路样板</title><link rel="stylesheet" href="../sources/map.css"><body><canvas aria-label="模块组装地图，地点旁节点与人物道路锚点"></canvas><div class="name">安然</div><div class="controls"><button data-action="play" aria-label="播放显示层移动示意">▷</button><button data-action="seed" aria-label="切换装饰种子，不改变节点道路">⟳</button><button data-action="zoom" aria-label="缩放地图视图">＋</button></div><script src="../sources/map.js"></script></body></html>'
(R/'sources/map.css').write_text(css+'\n');(R/'sources/map.js').write_text(js.strip()+'\n');(R/'previews/index.html').write_text(doc+'\n')

async def export():
    reports=[]
    embedded=doc.replace('<link rel="stylesheet" href="../sources/map.css">','<style>'+css+'</style>').replace('<script src="../sources/map.js"></script>','<script>'+js+'</script>')
    for p in (R/'assets').rglob('*.png'):
        name='../'+str(p.relative_to(R));embedded=embedded.replace(name,'data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode())
    # JS resolves filenames dynamically; replace the complete paths dictionary with offline data URLs.
    lookup={b:'data:image/png;base64,'+base64.b64encode((R/'assets/atlases'/f'{b}_modules.png').read_bytes()).decode() for b in palettes}
    for k in ['adventurer','ranger','spellblade','dragon_knight']:lookup[k]='data:image/png;base64,'+base64.b64encode((R/'assets/characters'/f'class_{k}_portrait.png').read_bytes()).decode()
    embedded=embedded.replace("const paths={};for(const biome of ['grass','snow','volcano'])paths[biome]='../assets/atlases/'+biome+'_modules.png';for(const k of ['adventurer','ranger','spellblade','dragon_knight'])paths[k]='../assets/characters/class_'+k+'_portrait.png';",'const paths='+json.dumps(lookup)+';')
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        for svg in (R/'assets/roads').glob('*.svg'):
            page=await b.new_page(viewport={'width':384,'height':256});await page.set_content('<html><style>html,body{margin:0;background:transparent}</style>'+svg.read_text()+'</html>');await page.screenshot(path=str(svg.with_suffix('.png')),omit_background=True);await page.close()
        for ratio,w,h in [('16x9',1920,1080),('4x3',1440,1080)]:
            page=await b.new_page(viewport={'width':w,'height':h},device_scale_factor=1);await page.route('http**/*',lambda r:r.abort())
            await page.set_content(embedded);await page.evaluate('sample.ready');await page.evaluate('document.fonts.ready')
            for biome,seed,layout in [('grass',17,'A'),('snow',43,'B'),('volcano',91,'C'),('grass',30,'A')]:
                await page.evaluate('(x)=>sample.set(...x)',[biome,seed,layout]);await page.screenshot(path=str(R/'previews'/f'{biome}_seed{seed}_{ratio}.png'))
                r=await page.evaluate('sample.state');assert r['publicRoads']==[[1,2],[2,3]] and r['decorCount']>3,r
                r['aspect']=ratio;reports.append(r)
            await page.evaluate('sample.set("grass",17,"A")');await page.evaluate('sample.play()');state=await page.evaluate('sample.state');assert state['movingCurveParameter']==1
            await page.close()
        await b.close()
    (R/'evidence/assembly-checks.json').write_text(json.dumps(dict(status='pass',runs=reports,roadEndpoints='node anchors shared with movement cubic',privateRoadsRendered=False,offline=True,engineCalls=0,limits='display fixtures, not native map generator validation'),ensure_ascii=False,indent=2)+'\n')
asyncio.run(export())
