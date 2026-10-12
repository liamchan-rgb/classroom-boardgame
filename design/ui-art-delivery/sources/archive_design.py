"""Design-only recoverable checkpoint; no IPA/build record, no app mutation."""
from pathlib import Path
import hashlib,json,zipfile
R=Path(__file__).resolve().parents[1]
OUT=R.parent/'archives';OUT.mkdir(exist_ok=True)
NAME='classroom-ui-art-round1-20261012'
rows=[]
for p in sorted(R.rglob('*')):
 if not p.is_file() or p.name=='FILE_CHECKSUMS.json' or '__pycache__' in p.parts:continue
 b=p.read_bytes();rows.append({'path':p.relative_to(R).as_posix(),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
manifest={'formatVersion':1,'version':'2026-10-12-round1','scope':'design-only','selfExcluded':True,'files':rows}
(R/'FILE_CHECKSUMS.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
z=OUT/(NAME+'.zip')
if z.exists():raise FileExistsError('Checkpoint exists; use a new version rather than overwrite')
with zipfile.ZipFile(z,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as f:
 for p in sorted(R.rglob('*')):
  if p.is_file() and '__pycache__' not in p.parts:f.write(p,'ui-art-delivery/'+p.relative_to(R).as_posix())
with zipfile.ZipFile(z) as f:
 assert f.testzip() is None
 for row in rows:
  b=f.read('ui-art-delivery/'+row['path']);assert len(b)==row['bytes'] and hashlib.sha256(b).hexdigest()==row['sha256']
sha=hashlib.sha256(z.read_bytes()).hexdigest()
(OUT/(NAME+'.zip.sha256')).write_text(sha+'  '+z.name+'\n')
record={'formatVersion':1,'version':NAME,'branch':'design/ui-art-round1-20261012','tag':'archive-design-ui-art-round1-20261012','repository':'liamchan-rgb/classroom-boardgame','baseMainCommit':'f43439ae212757631d03e4869e932e72b1dcd1da','zipFile':z.name,'bytes':z.stat().st_size,'sha256':sha,'payloadFiles':len(rows)+1,'checks':['ZIP CRC passed','Every archived payload SHA256 passed'],'compiledCommit':None,'ipa':None,'notes':'仅设计交付，不改main或App。远端上传验证见design/ARCHIVE_INDEX.md；此清单不是资料库上传回执。'}
(OUT/(NAME+'.manifest.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(record,ensure_ascii=False,indent=2))
