"""Unique design-only recovery package; never overwrite any existing ZIP/tag."""
from pathlib import Path
import hashlib,json,zipfile,sys,subprocess
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def payload():return sorted(p for p in ROOT.rglob('*') if p.is_file() and 'archives' not in p.relative_to(ROOT).parts and p.name not in ['FILE_CHECKSUMS.json','ARCHIVE_INDEX.md'] and '__pycache__' not in p.parts)
def checks():
    rows={str(p.relative_to(ROOT)):dict(sha256=sha(p),bytes=p.stat().st_size) for p in payload()}
    (ROOT/'FILE_CHECKSUMS.json').write_text(json.dumps(dict(formatVersion=1,root=ROOT.name,files=rows),ensure_ascii=False,indent=2)+'\n');print('Payload checksums',len(rows))
def package():
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    tag='archive-design-map-battle-ui-b-v4-20261013'
    target=ROOT/'archives/classroom-map-battle-ui-b-v4-20261013.zip'
    if target.exists():raise RuntimeError('Refuse to replace an existing ZIP')
    manifest=json.loads((ROOT/'FILE_CHECKSUMS.json').read_text())
    for name,row in manifest['files'].items():assert sha(ROOT/name)==row['sha256'],name
    target.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in payload()+[ROOT/'FILE_CHECKSUMS.json']:z.write(p,ROOT.name+'/'+str(p.relative_to(ROOT)))
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        for name,row in manifest['files'].items():assert hashlib.sha256(z.read(ROOT.name+'/'+name)).hexdigest()==row['sha256']
    digest=sha(target)
    target.with_suffix('.zip.sha256').write_text(digest+'  '+target.name+'\n')
    meta=dict(snapshotCommit=head,tag=tag,branch='design/map-battle-ui-round4-20261013',zip=target.name,bytes=target.stat().st_size,sha256=digest,payloadFiles=len(manifest['files']),zipEntries=len(manifest['files'])+1,designStatus='awaiting-review',nativeAppChanged=False,crcChecked=True,payloadHashesChecked=True)
    target.with_suffix('.manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(meta,ensure_ascii=False))
checks() if '--checks' in sys.argv else package()
