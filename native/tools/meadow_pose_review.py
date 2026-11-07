"""Render review GIFs from the same JSON clips and layer names as the app."""
from pathlib import Path
from PIL import Image
import json, math
# Pose math ported from experiment 175c7dfc; same registered parts and JSON.
ART=Path(__file__).resolve().parents[1]/'ClassroomProbe/Resources/MeadowArt'
config=json.loads((ART/'configuration.json').read_text())
lib=json.loads((ART/'animation.json').read_text())
LAYERS={n:Image.open(ART/(n+'.png')).convert('RGBA') for n in config['layers']}

def ordered_layers(clip):
 names=list(config['layers'])
 if clip=='idle': return names
 animated=['MeadowBattleHeroJointUnderlay','MeadowBattleHeroBodyCore',
  'MeadowBattleHeroLegFarThighBody','MeadowBattleHeroLegFarShinBody','MeadowBattleHeroLegNearThighBody','MeadowBattleHeroLegNearShinBody',
  'MeadowBattleHeroArmNearUpperBody','MeadowBattleHeroArmNearForearmBody','MeadowBattleHeroWardrobeCore',
  'MeadowBattleHeroLegFarThighWardrobe','MeadowBattleHeroLegFarShinWardrobe','MeadowBattleHeroLegNearThighWardrobe','MeadowBattleHeroLegNearShinWardrobe',
  'MeadowBattleHeroArmNearUpperWardrobe','MeadowBattleHeroArmNearForearmWardrobe','MeadowBattleHeroWeapon',
  'MeadowBattleHeroHair','MeadowBattleHeroFace','MeadowBattleHeroNearHand','MeadowBattleHeroFarHand']
 return [n for n in animated if n in names]

def lerp(x,y,f): return x+(y-x)*f
def mixpoint(a,b,f): return (lerp(a[0],b[0],f),lerp(a[1],b[1],f))
def rotate(p,pivot,angle):
 x,y=p[0]-pivot[0],p[1]-pivot[1]; c,s=math.cos(angle),math.sin(angle)
 return (pivot[0]+x*c-y*s,pivot[1]+x*s+y*c)
def sample(clip,p):
 seq=lib['clips'][clip]['keys']; u=next((i for i,k in enumerate(seq) if k['t']>=p),len(seq)-1); a,b=seq[max(0,u-1)],seq[u]; f=0 if b['t']==a['t'] else (p-a['t'])/(b['t']-a['t'])
 vals={k:lerp(a[k],b[k],f) for k in ['lean','crouch','shoulder','elbow','wrist','nearHip','nearKnee','farHip','farKnee','flash','recoil']}; root=mixpoint(a['root'],b['root'],f)
 lean=vals['lean']; crouch=vals['crouch']
 def bp(q):
  dx,dy=q[0]-132,q[1]-167;c,s=math.cos(lean),math.sin(lean);return (132+dx*c-dy*s,167+dx*s+dy*c+crouch)
 def pose(pivot,moved,angle): return (pivot,(moved[0]-pivot[0],moved[1]-pivot[1]),angle)
 torso=((132,167),(0,crouch),lean)
 sh=(117,141);el=(128,158);grip=(145.6,163.7)
 ush=bp(sh); uel=bp(rotate(el,sh,vals['shoulder']))
 egrip=bp(rotate(rotate(grip,el,vals['elbow']),sh,vals['shoulder']))
 upper=pose(sh,ush,lean+vals['shoulder']);fore=pose(el,uel,lean+vals['shoulder']+vals['elbow'])
 hand=pose(grip,egrip,lean+vals['shoulder']+vals['elbow']+vals['wrist'])
 hipN=(134,175); kneeN=(141,187); hipF=(115,176); kneeF=(104,192)
 nhip=bp(hipN); nknee=bp(rotate(kneeN,hipN,vals['nearHip'])); fhip=bp(hipF); fknee=bp(rotate(kneeF,hipF,vals['farHip']))
 nth=pose(hipN,nhip,lean+vals['nearHip']); nsh=pose(kneeN,nknee,lean+vals['nearHip']+vals['nearKnee'])
 fth=pose(hipF,fhip,lean+vals['farHip']); fsh=pose(kneeF,fknee,lean+vals['farHip']+vals['farKnee'])
 transforms={
 'MeadowBattleHeroBodyCore':torso,'MeadowBattleHeroWardrobeCore':torso,'MeadowBattleHeroJointUnderlay':torso,'MeadowBattleHeroHair':torso,'MeadowBattleHeroFace':torso,'MeadowBattleHeroFarHand':torso,
 'MeadowBattleHeroArmNearUpperBody':upper,'MeadowBattleHeroArmNearUpperWardrobe':upper,'MeadowBattleHeroArmNearForearmBody':fore,'MeadowBattleHeroArmNearForearmWardrobe':fore,
 'MeadowBattleHeroLegNearThighBody':nth,'MeadowBattleHeroLegNearThighWardrobe':nth,'MeadowBattleHeroLegNearShinBody':nsh,'MeadowBattleHeroLegNearShinWardrobe':nsh,
 'MeadowBattleHeroLegFarThighBody':fth,'MeadowBattleHeroLegFarThighWardrobe':fth,'MeadowBattleHeroLegFarShinBody':fsh,'MeadowBattleHeroLegFarShinWardrobe':fsh,
 'MeadowBattleHeroNearHand':hand,'MeadowBattleHeroWeapon':hand
 }
 # Follow the same three-point sole sampling and support correction as Swift.
 def legpoint(q,hip,knee,ha,ka): return bp(rotate(rotate(q,knee,ka),hip,ha))
 farSoles=[legpoint((x,214),hipF,kneeF,vals['farHip'],vals['farKnee']) for x in (90,98,105)]
 nearSoles=[legpoint((x,214),hipN,kneeN,vals['nearHip'],vals['nearKnee']) for x in (145,150,156)]
 soles=farSoles+nearSoles; ground=max(q[1] for q in soles)
 planted=[]
 for boot in (farSoles,nearSoles):
  points=[q for q in boot if ground-q[1] <= 1]
  if points: planted.append((sum(q[0] for q in points)/len(points),sum(q[1] for q in points)/len(points)))
 root=(root[0],root[1]+214-ground)
 return transforms,root,vals,ground,planted

def render(clip,p):
 transforms,root,vals,ground,planted=sample(clip,p);out=Image.new('RGBA',(256,256),(0,0,0,0))
 for n in ordered_layers(clip):
  if clip=='idle' and n=='MeadowBattleHeroJointUnderlay': continue
  image=LAYERS[n];pivot,offset,angle=transforms.get(n,((0,0),(0,0),0))
  image=image.rotate(-math.degrees(angle),resample=Image.Resampling.NEAREST,center=pivot)
  moved=Image.new('RGBA',(256,256),(0,0,0,0));moved.alpha_composite(image,(round(offset[0]+root[0]),round(offset[1]+root[1])))
  out.alpha_composite(moved)
 return out

