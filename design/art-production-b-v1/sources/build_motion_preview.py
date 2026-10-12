from pathlib import Path
import json,html

ROOT=Path(__file__).resolve().parents[1]
assets=json.loads((ROOT/'asset-manifest.json').read_text())
motion=json.loads((ROOT/'animations/character-motion.json').read_text())
effects=json.loads((ROOT/'animation-manifest.json').read_text())['effects']
names={a['entityID']:a['label'] for a in assets['assets']}
doc=['<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>B基础动画资源 · 离线设计预览</title><style>body{font-family:system-ui;background:#eff7fb;color:#173f50;margin:24px}button{font:inherit;padding:12px;border:1px solid #b7cedb;border-radius:10px;background:white;color:#173f50;margin:4px}#actors{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:16px}.card{background:white;border-radius:16px;padding:14px;overflow:visible}.sprite{width:220px;height:220px;display:block;transform-origin:50% 82%;object-fit:contain}.label{font-size:18px}.fx{display:flex;flex-wrap:wrap;gap:16px}.fx-tile{width:128px;height:128px;background-size:1024px 128px;border:1px solid #d1e1eb;border-radius:12px}a{color:#176a86}</style><h1>B晴空学园 · 基础动画资源</h1><p>离线设计演示；变换型动作，不是逐帧肢体或骨骼动画，不运行App或GameCore。</p><div>']
for key,label in [('idle','待机'),('move','移动'),('attack','出击'),('hurt','受击'),('down','倒地'),('revive','救援')]:doc.append(f'<button data-motion="{key}">{label}</button>')
doc.append('<button id="reduced">减少动态效果：关</button></div><section id="actors">')
for p in motion['entityProfiles']:doc.append(f'<article class="card"><img class="sprite" id="{p["entityID"]}" src="../{p["image"]}" alt="{html.escape(names[p["entityID"]])}"><div class="label">{html.escape(names[p["entityID"]])}</div></article>')
doc.append('</section><h2>独立八帧表现贴图</h2><div class="fx">')
for e in effects:doc.append(f'<article><div class="fx-tile" data-effect="{e["effectID"]}" style="background-image:url(../{e["file"]})"></div><div>{e["effectID"]}</div></article>')
doc.append('</div><p>截图和预览控件只用于资源检查；运行数字与姓名由App绘制，动作不会修改任何规则或资源。</p>')
doc.append('<script>const config='+json.dumps(motion,ensure_ascii=False)+';const effects='+json.dumps(effects,ensure_ascii=False)+';'+'''
const consumed=new Set(),effectConsumed=new Set();let played=0,reduced=false,serial=0;
function playResult(resultID,state){
 if(consumed.has(resultID))return false;consumed.add(resultID);played++;
 for(const p of config.entityProfiles){
  const el=document.getElementById(p.entityID);el.getAnimations().forEach(a=>a.cancel());const m=config.motions[state];
  const frames=m.keyframes.map(k=>({offset:k.t,transform:`translate(${(k.x||0)*220*p.amplitudeMultiplier*p.facingDirection}px,${(k.y||0)*220*p.amplitudeMultiplier}px) rotate(${k.rotationDeg||0}deg) scale(${k.scaleX||1},${k.scaleY||1})`,opacity:k.opacity===undefined?1:k.opacity,filter:`saturate(${k.saturation===undefined?1:k.saturation})`}));
  if(reduced){const last=frames[frames.length-1];el.style.transform=last.transform;el.style.opacity=last.opacity;el.style.filter=last.filter;continue;}
  el.style.transform='';el.style.opacity='';el.style.filter='';
  el.animate(frames,{duration:m.durationMs,iterations:m.loop?Infinity:1,fill:m.holdFinalFrame?'forwards':'none',easing:'ease-in-out'});
 }
 return true;
}
document.querySelectorAll('[data-motion]').forEach(b=>b.onclick=()=>playResult('review-event-'+(++serial),b.dataset.motion));
document.querySelector('#reduced').onclick=()=>{reduced=!reduced;document.querySelector('#reduced').textContent='减少动态效果：'+(reduced?'开':'关');};
function playEffects(resultID){
 if(effectConsumed.has(resultID))return false;effectConsumed.add(resultID);
 document.querySelectorAll('[data-effect]').forEach(el=>{
  const fx=effects.find(f=>f.effectID===el.dataset.effect);el.getAnimations().forEach(a=>a.cancel());
  if(reduced){el.style.backgroundPosition='-384px 0px';setTimeout(()=>el.style.backgroundPosition='-896px 0px',200);return;}
  el.animate([{backgroundPosition:'0px 0px'},{backgroundPosition:'-896px 0px'}],{duration:fx.durationMs,easing:'steps(7,end)',iterations:1,fill:'forwards'});
 });return true;
}
window.motionReview={playResult,playEffects,get played(){return played},setReduced(v){reduced=v},get reduced(){return reduced}};
// Review starts stationary. No autoplay of previously committed operations.
</script></html>''')
(ROOT/'previews/motion_preview.html').write_text(''.join(doc))
print('Built offline ten-entity motion preview')
