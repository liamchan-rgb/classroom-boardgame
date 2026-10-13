import hashlib,json
from pathlib import Path
base=Path(__file__).resolve().parent
manifest=json.loads((base/'transport.json').read_text())
out=base/manifest['logicalZIP']
if out.exists():raise FileExistsError('Do not overwrite an existing ZIP')
h=hashlib.sha256()
with out.open('xb') as target:
 for part in manifest['parts']:
  data=(base/part['file']).read_bytes()
  assert len(data)==part['bytes'] and hashlib.sha256(data).hexdigest()==part['sha256'],part['file']
  h.update(data);target.write(data)
assert out.stat().st_size==manifest['bytes'] and h.hexdigest()==manifest['sha256']
print('ZIP restored and verified:',out.name)
