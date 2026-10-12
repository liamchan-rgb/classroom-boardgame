"""Design-only recoverable ZIP. Does not build IPA or touch main/workflows."""
from pathlib import Path
import json,hashlib,zipfile,subprocess,sys,shutil

ROOT=Path(__file__).resolve().parents[1];phase=sys.argv[1]
assert phase in ['b-static-assets-v1','b-art-motion-v1']
for p in ROOT.rglob('__pycache__'):shutil.rmtree(p)
files=[{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(ROOT.rglob('*')) if p.is_file() and p.name!='FILE_CHECKSUMS.json']
(ROOT/'FILE_CHECKSUMS.json').write_text(json.dumps({'formatVersion':1,'scope':'design-only','version':phase,'selfExcluded':True,'files':files},ensure_ascii=False,indent=2)+'\n')
print(f'Prepared {phase} checksum manifest with {len(files)} payloads; commit this before --zip')
if '--zip' not in sys.argv:raise SystemExit(0)
source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
archive=ROOT.parent/'archives'/f'classroom-{phase}-20261012.zip'
assert not archive.exists(),archive
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(ROOT.rglob('*')):
  if p.is_file():z.write(p,str(Path(ROOT.name)/p.relative_to(ROOT)))
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for f in files:assert hashlib.sha256(z.read(ROOT.name+'/'+f['path'])).hexdigest()==f['sha256']
h=hashlib.sha256(archive.read_bytes()).hexdigest()
Path(str(archive)+'.sha256').write_text(h+'  '+archive.name+'\n')
meta={'version':phase,'repository':'liamchan-rgb/classroom-boardgame','branch':'design/ui-art-round1-20261012','snapshotCommit':source,'tag':f'archive-design-{phase}-20261012','zip':'design/archives/'+archive.name,'bytes':archive.stat().st_size,'sha256':h,'files':len(files)+1,'payloadsVerified':len(files),'selectedStyle':'b','classes':4,'monsters':6,'items':18,'appSourcesChanged':False,'gameCoreChanged':False,'workflowsChanged':False,'mainRefChanged':False,'ipaBuilt':False,'nativeTested':False,'artReviewPassed':False}
if phase=='b-art-motion-v1':meta.update(characterMotionStates=6,characterProfiles=10,effectSheets=12,effectFrames=96,skeletalAnimationMade=False,nativeAnimationTested=False,offlinePreviewChecksPassed=True)
(archive.parent/f'{phase}-manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
index=ROOT.parent/'ARCHIVE_INDEX.md'
index.write_text(index.read_text()+f'\n## B美术制作批次 {phase} · 2026-10-12\n\n- 目录：[art-production-b-v1/README.md](art-production-b-v1/README.md)\n- 静态实体：4职业、6怪物、18物品，2张沿用原B样稿、26张新增标准导出；新稿待最终审美确认。\n- 快照：{source}\n- 标签：{meta["tag"]}\n- 完整ZIP：[{archive.name}](archives/{archive.name})\n- 大小：{meta["bytes"]}字节；SHA256：{h}\n- 文件：{len(files)+1}；逐文件载荷：{len(files)}，ZIP CRC与SHA通过。\n- 远端状态：等待新克隆回读；回执见archives/{phase}-upload-receipt.json。\n- 原App、GameCore、main和工作流不改，无IPA；系统原生/真机及逐图审美未验证。旧版本/ZIP/标签保留。\n')
print(json.dumps(meta,ensure_ascii=False,indent=2))
