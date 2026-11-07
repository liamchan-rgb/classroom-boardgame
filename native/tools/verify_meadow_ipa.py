#!/usr/bin/env python3
"""Verify actual successful-run diagnostics and IPA without launching the app."""
from pathlib import Path
import argparse,hashlib,json,plistlib,re,stat,struct,subprocess,zipfile
p=argparse.ArgumentParser();p.add_argument('download',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
D=a.download;repo='repos/liamchan-rgb/classroom-boardgame'
run=json.loads((D/'run.json').read_text());arts=json.loads((D/'artifacts.json').read_text())['artifacts'];jobs=json.loads((D/'jobs.json').read_text())['jobs']
assert run['status']=='completed' and run['conclusion']=='success'
source=run['head_sha'];artifact=next(x for x in arts if x['name']=='ClassroomStage2-v0.12.1-build')
assert artifact['workflow_run']['head_sha']==source and not artifact['expired']
assert all(j['conclusion']=='success' for j in jobs)
for name in ['Select compatible Xcode and confirm SDKs','Test offline core','Build unsigned iPad app','Package for free personal signing']:
    assert any(s['name']==name and s['conclusion']=='success' for j in jobs for s in j['steps'])
sha=lambda b:hashlib.sha256(b).hexdigest()
outer=D/'artifact.zip';assert artifact['digest']=='sha256:'+sha(outer.read_bytes())
with zipfile.ZipFile(outer) as z:
    assert z.testzip() is None;z.extractall(D/'artifact')
F=D/'artifact';ipa=F/'ClassroomStage2-v0.12.1-unsigned.ipa'
assert (F/'source-commit.txt').read_text().strip()==source
assert 'Executed 79 tests, with 0 failures' in (F/'game-core-tests.log').read_text()
assert 'Executed 6 tests, with 0 failures' in (F/'core-tests.log').read_text()
assert '** ARCHIVE SUCCEEDED **' in (F/'xcode-build.log').read_text()
assert 'MeadowPublicView.swift' in (F/'xcode-build.log').read_text()
R=Path(__file__).resolve().parents[2]
manifest=json.loads(subprocess.check_output(['git','show',source+':native/ClassroomProbe/Resources/MeadowArt/provenance.json'],cwd=R))
with zipfile.ZipFile(ipa) as z,ipa.open('rb') as raw:
    assert z.testzip() is None
    for e in z.infolist():
        assert e.extract_version<=20 and not e.extra and not e.flag_bits&1
        raw.seek(e.header_offset);h=struct.unpack('<IHHHHHIIIHH',raw.read(30));assert h[0]==0x04034b50 and h[1]<=20 and h[3]==0 and h[-1]==0
    prefix='Payload/ClassroomProbe.app/'
    info=plistlib.loads(z.read(prefix+'Info.plist'))
    assert info['CFBundleIdentifier']=='org.personal.classroom.stage0'
    assert (info['CFBundleShortVersionString'],info['CFBundleVersion'])==('0.12.1','13')
    assert info['CFBundleSupportedPlatforms']==['iPhoneOS'] and info['MinimumOSVersion']=='27.0'
    exe=z.read(prefix+info['CFBundleExecutable']);assert struct.unpack('<II',exe[:8])==(0xfeedfacf,0x100000c)
    mode=z.getinfo(prefix+info['CFBundleExecutable']).external_attr>>16;assert stat.S_IMODE(mode)==0o755
    assert z.read(prefix+'sample.pptx').startswith(b'PK')
    assert z.read(prefix+'MeadowArt/provenance.json')==subprocess.check_output(['git','show',source+':native/ClassroomProbe/Resources/MeadowArt/provenance.json'],cwd=R)
    for row in manifest['files']:assert sha(z.read(prefix+'MeadowArt/'+row['name']))==row['sha256'],row['name']
    for name in z.namelist():assert 'embedded.mobileprovision' not in name and '_CodeSignature' not in name
record=dict(appVersion='0.12.1/build13',testedCommit=source,sourceCommit=source,runID=run['id'],runAttempt=run['run_attempt'],artifactID=artifact['id'],
    artifactArchiveSha256=sha(outer.read_bytes()),artifactArchiveBytes=outer.stat().st_size,ipaSha256=sha(ipa.read_bytes()),ipaBytes=ipa.stat().st_size,
    coreTests={'ClassroomGameCore':79,'ClassroomProbeCore':6,'failures':0},deviceReleaseArchive=True,arm64=True,executableMode=oct(stat.S_IMODE(mode)),
    classicZIP2=True,CRC=True,artSource=manifest['commit'],artFilesVerified=len(manifest['files']),minimumOS=info['MinimumOSVersion'],sdk=info['DTSDKName'],
    customMetalLibraryExpected=False,newPVEDeviceVerified=False,appLaunched=False,simulatorLaunched=False,externalDisplayVerified=False,
    limitations=['External display, teacher/private notes and PPT behavior need user device verification.','Generic melee rig bound for adventurer/spellblade; other classes retain original art.'])
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
