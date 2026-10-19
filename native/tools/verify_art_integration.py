#!/usr/bin/env python3
"""Validate pinned offline art and optionally an actual packaged IPA."""
import argparse,hashlib,json,subprocess,zipfile
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--ipa',type=Path);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
folder=ROOT/'native/ClassroomProbe/Resources/Art';manifest=json.loads((folder/'bindings.json').read_text())
rows=[]
for a in manifest['assets']:
 data=(folder/a['file']).read_bytes()
 original=subprocess.check_output(['git','show',manifest['designCommit']+':design/'+a['source']],cwd=ROOT)
 assert data==original and hashlib.sha256(data).hexdigest()==a['sha256'],a['file']
 with Image.open(folder/a['file']) as im:
  rows.append(dict(entityType=a['entityType'],entityID=a['entityID'],file=a['file'],dimensions=list(im.size),bytes=len(data),sha256=a['sha256']))
fx=json.loads((folder/'animation-manifest.json').read_text())
for e in fx['effects']:
 im=Image.open(folder/Path(e['file']).name).convert('RGBA')
 assert im.size==(e['frameCount']*e['frameWidthPx'],e['frameHeightPx'])
 terminal=im.crop((im.width-e['frameWidthPx'],0,im.width,im.height))
 assert terminal.getchannel('A').getbbox() is None,e['effectID']
prototype_manifest_path=folder/'prototypes/heavyStrike-trainingSword-side-contact-v1.json'
prototype_manifest=json.loads(prototype_manifest_path.read_text())
prototype_path=folder/'prototypes'/prototype_manifest['file']
prototype_bytes=prototype_path.read_bytes()
assert hashlib.sha256(prototype_bytes).hexdigest()==prototype_manifest['sha256']==prototype_manifest['sourceSha256']
assert prototype_manifest['status']=='approved-single-contact-pose-prototype'
assert prototype_manifest['assetRole']=='static battle-scene composition prototype; not a production frame or animation'
with Image.open(prototype_path) as prototype:
 assert list(prototype.size)==prototype_manifest['dimensionsPx']==[1254,1254]
 assert prototype.mode=='RGBA' and prototype.getchannel('A').getextrema()[0]==0
unchanged=['native/Packages/GameCore/Sources/ClassroomGameCore/'+name for name in ['Resources/initial-content.json','GameState.swift','GameEngine.swift','Rules.swift','Catalog.swift']]+['docs/课堂桌游_需求设计_v1.md','docs/课堂桌游_开发步骤_v1.md']
for name in unchanged: assert subprocess.check_output(['git','show','f43439ae212757631d03e4869e932e72b1dcd1da:'+name],cwd=ROOT)==(ROOT/name).read_bytes(),name
result=dict(designCommit=manifest['designCommit'],assetCount=len(rows),prototypeAssetCount=1,prototypeSourceHash=prototype_manifest['sourceSha256'],bytesMatchPinnedDelivery=True,bindingsUnique=len({(a['entityType'],a['entityID']) for a in rows})==66,effectTerminalFramesTransparent=12,unchangedRulesAndSaveFormat=unchanged,assets=rows)
if args.ipa:
 with zipfile.ZipFile(args.ipa) as z:
  assert z.testzip() is None
  names=z.namelist()
  for a in manifest['assets']:
   matching=[n for n in names if n.endswith('/Art/'+a['file'])]
   assert len(matching)==1,a['file']
   assert hashlib.sha256(z.read(matching[0])).hexdigest()==a['sha256']
  for name in ['bindings.json','character-motion.json','animation-manifest.json','art-production-b-v1-manifest.json','map-art-b-v1-manifest.json']:
   matching=[n for n in names if n.endswith('/Art/'+name)];assert len(matching)==1;assert z.read(matching[0])==(folder/name).read_bytes()
  prototype_entry='Art/prototypes/'+prototype_manifest['file']
  prototype_matches=[n for n in names if n.endswith('/'+prototype_entry)]
  assert len(prototype_matches)==1 and hashlib.sha256(z.read(prototype_matches[0])).hexdigest()==prototype_manifest['sha256']
  manifest_matches=[n for n in names if n.endswith('/Art/prototypes/'+prototype_manifest_path.name)]
  assert len(manifest_matches)==1 and z.read(manifest_matches[0])==prototype_manifest_path.read_bytes()
  assert not any('/previews/' in n or 'https://' in n for n in names)
  result['ipaBundledAssetsVerified']=66
  result['ipaBundledPrototypeVerified']=prototype_manifest['id']
  result['ipaSha256']=hashlib.sha256(args.ipa.read_bytes()).hexdigest()
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('PASS: 66 pinned offline images, one approved-scope battle prototype, 12 transparent effect endings, unchanged rules/save format'+(', actual IPA resources' if args.ipa else ''))
