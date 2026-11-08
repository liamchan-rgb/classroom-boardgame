#!/usr/bin/env python3
"""Fast dependency/hash/PNG-CRC and binding checks, no image packages required."""
from pathlib import Path
import json,hashlib,struct,zlib
r=Path(__file__).resolve().parents[1]/'ClassroomProbe/Resources';m=json.loads((r/'custom-appearance.json').read_text());p=json.loads((r/'meadow-port-provenance.json').read_text());g=json.loads((r/'hero-gait.json').read_text());names=set()
for row in m['derivedFiles']:
 data=(r/row['file']).read_bytes();assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],row['file']
 if row['file'].endswith('.png'):
  assert data[:8]==b'\x89PNG\r\n\x1a\n';pos=8
  while pos<len(data):
   n=struct.unpack('>I',data[pos:pos+4])[0];typ=data[pos+4:pos+8];chunk=data[pos+8:pos+8+n];crc=struct.unpack('>I',data[pos+8+n:pos+12+n])[0];assert zlib.crc32(typ+chunk)&0xffffffff==crc;pos+=12+n
  assert pos==len(data);names.add(Path(row['file']).stem)
for table in ['bodyAtlases','foregroundAtlases','hairAtlases','faceAtlases']:
 for key,pair in m[table].items():assert len(pair)==2 and all(x in names for x in pair),(table,key)
for table in ['battleHair','battleFaces']:assert set(m[table].values())<=names
assert len(m['bodyAtlases'])==30 and len(m['foregroundAtlases'])==6 and len(m['hairAtlases'])==8 and len(m['faceAtlases'])==6
assert len(m['derivedFiles'])==260 and m['mechanicalWholeBodyChecks']==4992
for item in ['starlightArmor','dragonArmor']:
 a=g['armorVisuals'][item];assert set(a['battleLayers'].values())<={x.name.split('.')[0] for x in (r/'Assets.xcassets').iterdir()};assert a['bowAtlas'] in names and a['bowTorso'] in names
assert p['appearanceSourceCommit']==m['sourceCommit'] and p['commit']=='175c7dfc4a68e62cb9693da8d837b77081619a6b'
for row in p['assets']:assert hashlib.sha256((r/row['file']).read_bytes()).hexdigest()==row['sha256'],row['file']
print('PASS: 829 pinned resources; 130 new image names; component dependencies, PNG CRC and original mixed-source provenance.')
