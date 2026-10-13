#!/usr/bin/env python3
"""Lossless transport for milestone ZIPs exceeding GitHub's 100MB file limit."""
import argparse, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('archive',type=Path);p.add_argument('destination',type=Path);args=p.parse_args()
assert not args.destination.exists(),'Never overwrite a previous milestone transport'
args.destination.mkdir(parents=True)
chunk_bytes=48*1024*1024
rows=[];digest=hashlib.sha256();size=0
with args.archive.open('rb') as source:
 while data:=source.read(chunk_bytes):
  name=args.archive.name+f'.part{len(rows):03d}'
  (args.destination/name).write_bytes(data);digest.update(data);size+=len(data)
  rows.append(dict(file=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
manifest=dict(formatVersion=1,logicalZIP=args.archive.name,bytes=size,sha256=digest.hexdigest(),parts=rows,reason='Lossless split; GitHub normal Git rejects files over 100MB')
(args.destination/'transport.json').write_text(json.dumps(manifest,indent=2)+'\n')
(args.destination/'restore_zip.py').write_text('''import hashlib,json
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
''')
print(json.dumps(dict(parts=len(rows),bytes=size,sha256=digest.hexdigest())))
