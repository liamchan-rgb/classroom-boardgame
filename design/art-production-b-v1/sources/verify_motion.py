from pathlib import Path
import json,itertools
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
m=json.loads((ROOT/'animations/character-motion.json').read_text())
a=json.loads((ROOT/'animation-manifest.json').read_text())
assert len(m['entityProfiles'])==10 and len(m['motions'])==6
assert len({p['entityID'] for p in m['entityProfiles']})==10
for name,clip in m['motions'].items():
 times=[k['t'] for k in clip['keyframes']];assert times[0]==0 and times[-1]==1 and times==sorted(times)
 assert clip['loop']==(name=='idle')
 assert clip['durationMs']>0
 assert all(-.1<=k.get('x',0)<=.1 and -.1<=k.get('y',0)<=.1 and abs(k.get('rotationDeg',0))<=8 for k in clip['keyframes'])
for p in m['entityProfiles']:assert (ROOT/p['image']).is_file()
report=[]
for fx in a['effects']:
 im=Image.open(ROOT/fx['file']);assert im.size==(2048,256) and im.mode=='RGBA'
 alpha=im.getchannel('A');assert alpha.getextrema()[0]==0
 for i in range(8):
  # Read-only inspection, not rewriting PNG frames.
  frame=alpha.crop((i*256,0,(i+1)*256,256));b=frame.getbbox()
  if i==7:assert b is None,fx['effectID']
  else:assert b and min(b[0],b[1],256-b[2],256-b[3])>=20,(fx['effectID'],i,b)
 if fx['effectID'] in ['heal','revive']:
  assert alpha.getpixel((3*256+128,128))>0,(fx['effectID'],'missing central glyph')
 assert fx['playsPerCommittedResult']==1 and not fx['loop'] and fx['noBakedNumbers']
 report.append({'effectID':fx['effectID'],'size':im.size,'frames':8,'transparentTerminalFrame':True,'minimumFrameMarginPx':20})
assert m['eventPolicy']['mayCallRulesEngine'] is False and m['eventPolicy']['mayRollDice'] is False
assert m['eventPolicy']['resourceCountersTween'] is False
(ROOT/'sources/motion-static-validation.json').write_text(json.dumps({'status':'passed','scope':'resource-structure-only','entityCount':10,'characterMotionStates':6,'effects':report,'nativeRuntimeVerified':False,'skeletalAnimationMade':False},ensure_ascii=False,indent=2)+'\n')
print('PASS: ten entity bindings, six bounded states, twelve transparent eight-frame effect sheets')
