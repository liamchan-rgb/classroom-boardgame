from pathlib import Path
import base64,json
ROOT=Path(__file__).resolve().parents[1]
def data(p):return 'data:image/png;base64,'+base64.b64encode((ROOT/p).read_bytes()).decode()
allowed={'map_adventurer_sheet','map_slime_sheet','class_dragon_knight_portrait','node_start','node_combat','node_unknown','battle_back','battle_mid','battle_ground','battle_front'}
images={p.stem:data(p.relative_to(ROOT)) for p in (ROOT/'assets').rglob('*.png') if p.stem in allowed}
template='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>晴空学园 · 离线显示设计演示</title>
<style>body{margin:24px;background:#eff5f3;color:#173f50;font:18px system-ui}h1{font-size:28px}button,label{padding:12px;margin:4px;border:1px solid #adc8ce;border-radius:12px;background:#fffcf2;color:#173f50;font:18px system-ui;min-height:48px}button:focus{outline:3px solid #176a86}.stage{display:flex;max-width:1300px;height:520px;border-radius:20px;overflow:hidden;background:#eaf3e8;margin-top:20px}.map{flex:1;min-width:0}canvas{width:100%;height:100%;display:block}#fight{width:0;overflow:hidden;transition:width 220ms ease;background:#dbeccf}#fight.open{width:390px;flex-shrink:0}#fight canvas{width:390px}.reduced #fight{transition:none}#status{max-width:1260px;padding:18px;background:#fffcf2;border-radius:16px;line-height:1.6}.samples{display:flex;gap:24px;flex-wrap:wrap}.sample{background:#fffcf2;padding:16px;border-radius:16px}.sample canvas{width:192px;height:192px;image-rendering:pixelated}.dim{color:#496977}a{color:#176a86}</style>
<h1>晴空学园 · 镜头与分层2D动作设计演示（待审）</h1>
<p class="dim">教师等价控件。公开端只读；此页使用已定义显示样例，没有规则计算、掷骰或资源写入。</p>
<div><button id="play">播放已提交移动样例</button><button id="attack">播放已提交攻击样例</button><button id="restore">恢复终态（不补播）</button><button id="overview">地图总览</button><button id="follow">回到行动者</button><button id="zoomIn">放大 +</button><button id="zoomOut">缩小 −</button><button id="offscreen">定位 P7</button><label><input id="reduce" type="checkbox">减少动态</label></div>
<div class="stage" id="stage"><div class="map"><canvas id="map"></canvas></div><div id="fight"><canvas id="battle" width="390" height="520"></canvas></div></div>
<p id="status" aria-live="polite"></p>
<h2>像素全身动作小样 · 64px格 / 3倍检查</h2><p>先验证冒险者和史莱姆。其余8模板为完整静态复用，方向肢体帧待制作。</p>
<div><label>方向 <select id="direction"><option value="0">南</option><option value="1">东</option><option value="2">北</option><option value="3">西</option></select></label><label>状态 <select id="motion"><option>idle</option><option>walk</option><option>attack</option><option>cast</option><option>hurt</option><option>down</option><option>revive</option></select></label><button id="samplePlay">播放动作小样</button></div>
<div class="samples"><div class="sample">冒险者<canvas id="a" width="64" height="64"></canvas></div><div class="sample">史莱姆<canvas id="s" width="64" height="64"></canvas></div></div>
<p><a href="index.html">六张整屏预览与压力稿</a></p>
<script>
const sources=IMAGES_PLACEHOLDER;const art={};
const ready=Promise.all(Object.entries(sources).map(([k,v])=>new Promise(ok=>{let i=new Image();i.onload=()=>{art[k]=i;ok()};i.src=v}))); 
const nodes=[{id:1,x:.1,y:.55,name:'营地',kind:'start'},{id:2,x:.36,y:.55,name:'森林路口',kind:'combat'},{id:3,x:.62,y:.26,name:'弓手哨点',kind:'combat'},{id:4,x:.62,y:.78,name:'未探索地点4',kind:'unknown'},{id:5,x:.9,y:.55,name:'未探索地点5',kind:'unknown'}];
const roads=[[1,2],[2,3],[2,4],[3,5]];
const map=document.querySelector('#map'),battle=document.querySelector('#battle');
const state={camera:{x:.36,y:.55,scale:1250},actor:{x:.1,y:.55},phase:'exploration',moving:false,attack:false,down:false,reduced:false,manual:false,plays:0,attackPlays:0,suppressed:0,transitionOrder:[]};
const consumed=new Set();let reducedFromOS=matchMedia('(prefers-reduced-motion: reduce)').matches;
state.reduced=reducedFromOS;document.querySelector('#reduce').checked=state.reduced;
let moveStart=0,attackStart=0;
function sprite(ctx,key,frame,row,x,y,size=72){ctx.imageSmoothingEnabled=false;ctx.drawImage(art[key],frame*64,row*64,64,64,x-size/2,y-size*.89,size,size);ctx.imageSmoothingEnabled=true}
function image(ctx,key,x,y,w,h){if(art[key])ctx.drawImage(art[key],x,y,w,h)}
function point(n,w,h){return [w*.47+(n.x-state.camera.x)*state.camera.scale,h*.5+(n.y-state.camera.y)*state.camera.scale]}
function setPhase(phase){state.phase=phase;document.querySelector('#fight').classList.toggle('open',phase==='battle')}
function openBattle(){state.transitionOrder.push('arrival');state.moving=false;state.actor={x:.36,y:.55};setPhase('battle');state.transitionOrder.push('panel-open')}
function drawMap(t){let w=map.clientWidth,h=520;map.width=w;map.height=h;let c=map.getContext('2d');c.fillStyle='#eaf3e8';c.fillRect(0,0,w,h);c.strokeStyle='#faf6e6';c.lineWidth=12;
 for(let [a,b] of roads){let A=point(nodes[a-1],w,h),B=point(nodes[b-1],w,h);c.beginPath();c.moveTo(...A);c.lineTo(...B);c.stroke()}
 c.font='18px system-ui';c.textAlign='center';c.fillStyle='#173f50';for(let n of nodes){let [x,y]=point(n,w,h);if(x<65||x>w-65||y<85||y>h-85)continue;image(c,'node_'+n.kind,x-60,y-90,120,120);c.fillText(n.kind==='unknown'?'?':n.id+' · '+n.name,x,y+58)}
 let pos=state.actor;if(state.moving){let k=Math.min(1,(t-moveStart)/900);pos={x:.1+.26*k,y:.55};if(k===1){openBattle();pos=state.actor}}
 let [x,y]=point(pos,w,h);c.fillStyle='#173f5033';c.beginPath();c.ellipse(x,y,24,6,0,0,Math.PI*2);c.fill();sprite(c,'map_adventurer_sheet',state.moving?2+Math.floor((t-moveStart)/110)%4:0,1,x,y,84);c.fillStyle='#176a86';c.fillText('P1',x,y+27);
 // P7 is a public player at its actual unknown node. No unknown monster artwork exists here.
 let [px,py]=point(nodes[4],w,h);if(px>60&&px<w-60&&py>60&&py<h-60){image(c,'class_dragon_knight_portrait',px-42,py-72,84,84);c.fillText('P7',px,py+28)}else{let dx=px-w/2,dy=py-h/2;let q=Math.min((w/2-46)/Math.max(.001,Math.abs(dx)),(h/2-46)/Math.max(.001,Math.abs(dy)));px=w/2+dx*q;py=h/2+dy*q;c.fillStyle='#fffcf2';c.beginPath();c.arc(px,py,28,0,Math.PI*2);c.fill();image(c,'class_dragon_knight_portrait',px-24,py-24,48,48);c.save();c.translate(px,py);c.rotate(Math.atan2(dy,dx));c.fillStyle='#176a86';c.beginPath();c.moveTo(32,-8);c.lineTo(45,0);c.lineTo(32,8);c.fill();c.restore();c.fillStyle='#173f50';c.fillText('P7',px,py+42)}
 c.textAlign='left';c.fillText(state.manual?'镜头：手动查看':'镜头：行动者附近',18,32)
}
function drawBattle(t){let c=battle.getContext('2d');c.clearRect(0,0,390,520);for(let k of ['back','mid','ground'])image(c,'battle_'+k,0,0,390,520);let ax=100,ay=290,sx=292,sy=310;
 let elapsed=t-attackStart,f=0,sl=0;if(state.attack){f=6+Math.min(2,Math.floor(elapsed/120));sl=elapsed>160?12+Math.min(1,Math.floor((elapsed-160)/90)):0;if(elapsed>=360){state.attack=false;state.down=true;f=0;sl=14}}
 if(state.down)sl=14;c.fillStyle='#173f5033';for(let [x,y] of [[ax,ay],[sx,sy]]){c.beginPath();c.ellipse(x,y,34,9,0,0,Math.PI*2);c.fill()}
 sprite(c,'map_adventurer_sheet',f,1,ax+(state.attack&&!state.reduced?12*Math.sin(elapsed/360*Math.PI):0),ay,144);sprite(c,'map_slime_sheet',sl,3,sx,sy,128);image(c,'battle_front',0,0,390,520);
 c.fillStyle='#fffcf2';c.fillRect(16,14,358,64);c.fillRect(32,340,130,78);c.fillRect(220,360,150,78);c.fillStyle='#173f50';c.font='22px system-ui';c.fillText('森林路口 · 分层2D小样',30,54);c.font='20px system-ui';c.fillText('P1 · 12/12',45,372);c.fillText('护盾 0',45,402);c.fillText('M1 · '+(state.down?'0/8 ×':'8/8'),232,390);c.fillText('护盾 0',232,422)
}
function status(){document.querySelector('#status').textContent='移动样例播放 '+state.plays+' 次；攻击样例播放 '+state.attackPlays+' 次；同ID拦截 '+state.suppressed+' 次。'+(state.reduced?'减少动态：立即终态。':'到达完成后展开右侧；动作不推进回合。')}
function playMove(){let key='design-session:committed-move-001';if(consumed.has(key)){state.suppressed++;status();return}consumed.add(key);state.plays++;state.transitionOrder.push('committed');if(state.reduced){openBattle()}else{state.moving=true;moveStart=performance.now();state.transitionOrder.push('path')};status()}
function playAttack(){if(state.phase!=='battle')return;let key='design-session:committed-attack-001';if(consumed.has(key)){state.suppressed++;status();return}consumed.add(key);state.attackPlays++;if(state.reduced){state.down=true}else{state.attack=true;attackStart=performance.now()};status()}
function restore(){consumed.add('design-session:committed-move-001');consumed.add('design-session:committed-attack-001');state.moving=false;state.attack=false;state.actor={x:.36,y:.55};state.down=true;setPhase('battle');state.transitionOrder.push('restore-terminal-no-play');status()}
document.querySelector('#play').onclick=playMove;document.querySelector('#attack').onclick=playAttack;document.querySelector('#restore').onclick=restore;
document.querySelector('#overview').onclick=()=>{state.manual=true;state.camera={x:.5,y:.52,scale:Math.min(map.clientWidth/1.08,520/.95)}};
document.querySelector('#follow').onclick=()=>{state.manual=false;state.camera={x:state.actor.x,y:state.actor.y,scale:1000}};
document.querySelector('#offscreen').onclick=()=>{state.manual=true;state.camera={x:.9,y:.55,scale:1000}};
document.querySelector('#zoomIn').onclick=()=>state.camera.scale=Math.min(1800,state.camera.scale*1.25);
document.querySelector('#zoomOut').onclick=()=>state.camera.scale=Math.max(400,state.camera.scale/1.25);
document.querySelector('#reduce').onchange=e=>{state.reduced=e.target.checked;document.body.classList.toggle('reduced',state.reduced);if(state.reduced&&state.moving)openBattle();if(state.reduced&&state.attack){state.attack=false;state.down=true}status()};
const rows={idle:[0,2,800],walk:[2,4,440],attack:[6,3,360],cast:[9,3,480],hurt:[12,2,180],down:[14,1,0],revive:[15,1,0]};let sampleStart=0,sampleActive=false;
function samples(t){let row=Number(document.querySelector('#direction').value),stateName=document.querySelector('#motion').value;let [first,count,dur]=rows[stateName],f=0;if(sampleActive&&!state.reduced){f=Math.min(count-1,Math.floor((t-sampleStart)/(dur/count||1)));if(t-sampleStart>=dur&&stateName!=='down'){sampleActive=false;f=0;first=0}}for(let [id,key] of [['a','map_adventurer_sheet'],['s','map_slime_sheet']]){let c=document.querySelector('#'+id).getContext('2d');c.clearRect(0,0,64,64);c.imageSmoothingEnabled=false;c.drawImage(art[key],(first+f)*64,row*64,64,64,0,0,64,64)}}
document.querySelector('#samplePlay').onclick=()=>{sampleStart=performance.now();sampleActive=true};
window.demo={state,playMove,playAttack,restore,consumed,assetCount:Object.keys(sources).length,report:()=>({plays:state.plays,attackPlays:state.attackPlays,suppressed:state.suppressed,phase:state.phase,order:state.transitionOrder,down:state.down,camera:state.camera})};
ready.then(()=>{window.demo.ready=true;status();document.body.classList.toggle('reduced',state.reduced);function frame(t){drawMap(t);drawBattle(t);samples(t);requestAnimationFrame(frame)}requestAnimationFrame(frame)});
</script></html>'''
(ROOT/'previews/camera_transition_demo.html').write_text(template.replace('IMAGES_PLACEHOLDER',json.dumps(images)),encoding='utf-8')
print('Offline embedded images:',len(images))
