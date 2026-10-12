"""Static design verification, not App or gameplay tests."""
from pathlib import Path
import json, hashlib, re, itertools
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT.parent/'ui-art-delivery'
report={'scope':'static-design-only','version':'2026-10-12-round3','pages':[],
        'unverified':['native-materials','touch-efficiency','TV-distance','runtime-privacy','actual-PPTX','animations']}
index=json.loads((ROOT/'sources/preview-index.json').read_text())
metrics={p['name']:p for p in json.loads((ROOT/'sources/text-measurements.json').read_text())}
assert len(index)==14
players=json.loads((ROOT/'sources/demo-scenarios.json').read_text())['baseBattle']['players']
assert len(players)==7 and sum(p['host'] for p in players)==1
for p in index:
 name=p['name'];im=Image.open(ROOT/'previews'/f'{name}.png')
 assert im.size==(p['width']*p['scale'],p['height']*p['scale']),name
 boxes=metrics[name]['inkBoxes'];public=name.startswith('public_')
 for b in boxes:
  assert b['x']>=-.5 and b['y']>=-.5 and b['x']+b['w']<=p['width']+.5 and b['y']+b['h']<=p['height']+.5,(name,b)
  if public:
   assert b['fontSize']>=24,(name,b)
   assert b['x']>=p['width']*.05-.5 and b['x']+b['w']<=p['width']*.95+.5 and b['y']>=53.5 and b['y']+b['h']<=1026.5,(name,'safe zone',b)
 for a,b in itertools.combinations(boxes,2):
  dx=min(a['x']+a['w'],b['x']+b['w'])-max(a['x'],b['x'])
  dy=min(a['y']+a['h'],b['y']+b['h'])-max(a['y'],b['y'])
  assert dx<=1 or dy<=1,(name,'ink overlap',a['text'],b['text'])
 text=''.join(b['text'] for b in boxes)
 if public:
  for player in players:assert player['name'] in text,(name,player['name'])
  assert '奖励对象' not in text and '备注' not in text and '史莱姆乙 · 同节点' not in text,name
  if 'storybook' in name:
   assert 'AP' not in text and '行动点' not in text,name
   assert ('保留17秒' in text)==name.endswith('_timer_enabled'),name
  else:assert sum(bool(re.fullmatch(r'AP \d+',b['text'])) for b in boxes)==7,name
 report['pages'].append({'name':name,'PNGSize':im.size,'textInkWithinCanvas':True,'noTextInkOverlap':True,'publicSafeZone':True if public else None})

# Hash all independent runtime assets and original generation/export files.
preserved=[]
for path in itertools.chain((ROOT/'assets').rglob('*'),(ROOT/'sources').glob('original_*.png'),(ROOT/'sources').glob('export_*.svg')):
 if not path.is_file():continue
 rel=path.relative_to(ROOT);h=hashlib.sha256(path.read_bytes()).hexdigest()
 if OLD.exists():assert h==hashlib.sha256((OLD/rel).read_bytes()).hexdigest(),str(rel)
 if path.suffix=='.png' and str(rel).startswith('assets/'):
  im=Image.open(path);assert im.mode=='RGBA' and im.getextrema()[-1][0]==0,str(rel)
 preserved.append({'path':str(rel),'sha256':h})
report['unchangedAssets']=preserved

def luminance(hexcolor):
 vals=[int(hexcolor[i:i+2],16)/255 for i in (1,3,5)]
 vals=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in vals]
 return sum(v*w for v,w in zip(vals,[.2126,.7152,.0722]))
def contrast(a,b):
 x,y=sorted([luminance(a),luminance(b)]);return (y+.05)/(x+.05)
tokens=json.loads((ROOT/'design-tokens.json').read_text())
checks=[]
for role in ['ink','muted','primary','accent','danger','shield','action']:
 for bg in ['#FFFFFF','#F5FAFC','#E4F1F6']:
  ratio=contrast(tokens['colors'][role],bg);assert ratio>=4.5,(role,bg,ratio)
  checks.append({'color':role,'background':bg,'ratio':round(ratio,2)})
assert contrast(tokens['colors']['primary'],'#FFFFFF')>=4.5
report['staticColorContrast']=checks
for p in index:
 if p['name'].startswith(('public_battle_','public_exploration_')):
  svg=(ROOT/'sources'/f"{p['name']}.svg").read_text()
  queue=re.findall(r'data-queue-unit="([^"]+)"',svg)
  demo=json.loads((ROOT/'sources/demo-scenarios.json').read_text())['baseBattle']
  assert queue==demo['queue'],(p['name'],'mixed queue order')
  assert svg.count('id="committed-feedback"')==(1 if p['name'].endswith('_feedback') else 0)
  text=''.join(b['text'] for b in metrics[p['name']]['inkBoxes'])
  assert '→' not in text and '最近一次结算' not in text and '已结算' not in text,p['name']
  if p['name'].startswith('public_battle_'):
   for label in ['强击','喘息','简易防护']:assert label in text
new_teacher=ROOT/'previews/teacher_battle_b.png'
prev_teacher=ROOT.parent/'ui-art-delivery-round2/previews/teacher_battle_b.png'
assert new_teacher.read_bytes()==prev_teacher.read_bytes(),'approved teacher image changed'
assert (ROOT/'sources/reference_initial-content.json').read_bytes()==(ROOT.parents[1]/'native/Packages/GameCore/Sources/ClassroomGameCore/Resources/initial-content.json').read_bytes()
report['mixedQueueVerified']=True
report['teacherImageUnchanged']=True
report['catalogSourceUnchanged']=True
report['status']='passed' 
(ROOT/'sources/validation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('PASS: 14 PNGs, actual text ink, 5% public safety, full names, 7 AP / no AP, preserved artwork, contrast')
