from pathlib import Path
import hashlib,json,zipfile,subprocess,sys
R=Path(__file__).resolve().parents[1]
files=sorted(p for p in R.rglob('*') if p.is_file() and 'archives' not in p.relative_to(R).parts and p.name not in ['ARCHIVE_INDEX.md','FILE_CHECKSUMS.json'])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
if '--checks' in sys.argv:
    (R/'FILE_CHECKSUMS.json').write_text(json.dumps({str(p.relative_to(R)):sha(p) for p in files},ensure_ascii=False,indent=2)+'\n');print('Payload',len(files));sys.exit()
checks=json.loads((R/'FILE_CHECKSUMS.json').read_text())
for n,h in checks.items():assert sha(R/n)==h
z=R/'archives/image-communication-guide-v1-20261013.zip';assert not z.exists(),'Never overwrite prior ZIP'
with zipfile.ZipFile(z,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as out:
    for p in files+[R/'FILE_CHECKSUMS.json']:out.write(p,R.name+'/'+str(p.relative_to(R)))
with zipfile.ZipFile(z) as out:
    assert out.testzip() is None
    for n,h in checks.items():assert hashlib.sha256(out.read(R.name+'/'+n)).hexdigest()==h
m=dict(snapshotCommit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),tag='archive-design-image-communication-guide-v1-20261013',zip=z.name,sha256=sha(z),bytes=z.stat().st_size,payloadFiles=len(files),zipEntries=len(files)+1,status='communication-policy-recorded')
z.with_suffix('.zip.sha256').write_text(m['sha256']+'  '+z.name+'\n');z.with_suffix('.manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n');print(json.dumps(m))
