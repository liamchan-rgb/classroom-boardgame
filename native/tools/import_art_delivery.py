#!/usr/bin/env python3
"""Import runtime files only from an explicit immutable design commit."""
import hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SHA='f43db0502bf3a9df9fef8bb7c699b6dce86c3425'
def blob(p): return subprocess.check_output(['git','show',f'{SHA}:design/{p}'],cwd=ROOT)
def sha(b): return hashlib.sha256(b).hexdigest()
out=ROOT/'native/ClassroomProbe/Resources/Art'; out.mkdir(parents=True,exist_ok=True)
rows=[]
for folder in ['art-production-b-v1','map-art-b-v1']:
 data=blob(folder+'/asset-manifest.json'); (out/(folder+'-manifest.json')).write_bytes(data)
 for a in json.loads(data)['assets']:
  if a['status']=='planned': continue
  data=blob(folder+'/'+a['file'])
  if a.get('sha256'): assert sha(data)==a['sha256'],a['file']
  name=Path(a['file']).name
  (out/name).write_bytes(data)
  rows.append(dict(entityType=a['entityType'],entityID=a['entityID'],assetName=a['assetName'],file=name,sha256=sha(data),status=a['status'],source=folder+'/'+a['file']))
motion=json.loads(blob('art-production-b-v1/animation-manifest.json'))
(out/'animation-manifest.json').write_bytes(blob('art-production-b-v1/animation-manifest.json'))
(out/'character-motion.json').write_bytes(blob('art-production-b-v1/animations/character-motion.json'))
for a in motion['effects']:
 data=blob('art-production-b-v1/'+a['file']); name=Path(a['file']).name; (out/name).write_bytes(data)
 rows.append(dict(entityType='effect',entityID=a['effectID'],assetName=Path(name).stem,file=name,sha256=sha(data),status='production-candidate',source='art-production-b-v1/'+a['file']))
assert len(rows)==66 and len({(a['entityType'],a['entityID']) for a in rows})==66
(out/'bindings.json').write_text(json.dumps(dict(designCommit=SHA,assets=rows),ensure_ascii=False,indent=2)+'\n')
(ROOT/'native/ClassroomProbe/Resources/design-tokens.json').write_bytes(blob('ui-art-delivery-round3/design-tokens.json'))
# Preserve read specifications separately. No design App code, whole-page preview or old ZIP is imported.
ref=ROOT/'stage2/ui-integration/design-reference'
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',SHA,'design'],cwd=ROOT,text=True).splitlines()
for p in paths:
 q=p.removeprefix('design/')
 if q in ['AGENTS.md','ARCHIVE_INDEX.md'] or q.startswith('reviews/') or (q.startswith(('ui-art-delivery-round2/','ui-art-delivery-round3/','art-production-b-v1/','map-art-b-v1/')) and ('/annotations/' in q or Path(q).name in ['README.md','design-tokens.json','asset-manifest.json','animation-manifest.json','character-motion.json'])):
  dest=ref/q; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(blob(q))
print(f'Imported {len(rows)} exact-byte local PNGs from {SHA}; map manifest supersedes planned nodes.')
