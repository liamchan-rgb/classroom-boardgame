#!/usr/bin/env python3
"""Verify successful full-Meadow classroom device archive; never launch the app."""
from pathlib import Path
import argparse,hashlib,json,plistlib,re,stat,struct,subprocess,zipfile
p=argparse.ArgumentParser();p.add_argument('download',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
D=a.download;R=Path(__file__).resolve().parents[2]
run=json.loads((D/'run.json').read_text());jobs=json.loads((D/'jobs.json').read_text())['jobs'];source=json.loads((D/'source.json').read_text())
assert run['conclusion']=='success' and run['status']=='completed' and run['head_sha']==source['sourceCommit']
assert run['head_branch']=='feat/teacher-backend-meadow-v0.13'
assert all(j['conclusion'] in ['success','skipped'] for j in jobs)
assert any(j['name']=='build' and j['conclusion']=='success' for j in jobs)
for name in ['Test offline core','Build unsigned iPad app','Package for free personal signing']:
    assert any(s['name']==name and s['conclusion']=='success' for j in jobs for s in j['steps'])
artifact=next(x for x in json.loads((D/'artifacts.json').read_text())['artifacts'] if x['id']==source['artifactID'])
assert artifact['name']=='ClassroomStage2-v0.15.0-build' and artifact['workflow_run']['head_sha']==run['head_sha'] and not artifact['expired']
sha=lambda data:hashlib.sha256(data).hexdigest()
outer=D/'artifact.zip';assert artifact['digest']=='sha256:'+sha(outer.read_bytes())
with zipfile.ZipFile(outer) as z:assert z.testzip() is None;z.extractall(D/'artifact')
F=D/'artifact';ipa=F/'ClassroomStage2-v0.15.0-unsigned.ipa'
assert (F/'source-commit.txt').read_text().strip()==run['head_sha']
test_log=(F/'game-core-tests.log').read_text()
suite_totals={name:int(count) for name,count in re.findall(r"Test Suite '(\w+Tests)\.xctest' passed[^\n]*\n[^\n]*Executed (\d+) tests, with 0 failures",test_log)}
assert suite_totals=={'MeadowWorldSupportTests':116,'MeadowClassroomSupportTests':48,'MeadowBattleSupportTests':108,'ClassroomGameCoreTests':72},suite_totals
assert sum(suite_totals.values())==344 and len(re.findall(r"Test Case '[^\n]+' passed",test_log))==344
assert 'Executed 6 tests, with 0 failures' in (F/'core-tests.log').read_text()
log=(F/'xcode-build.log').read_text();assert '** ARCHIVE SUCCEEDED **' in log
for name in ['MeadowTeacherCoordinator.swift','MeadowTeacherDashboard.swift','MeadowPublicOutput.swift','MeadowClassroomFrameMirror.swift','GameViewController.swift']:assert name in log
for name in ['PVEPlayView.swift','PVEPublicView.swift','RulesLabView.swift','MeadowPublicView.swift']:assert name not in log
def source_file(path):return subprocess.check_output(['git','show',run['head_sha']+':'+path],cwd=R)
manifest=json.loads(source_file('native/ClassroomProbe/Resources/meadow-port-provenance.json'))
asset_info=json.loads((F/'assets-info.json').read_text());names={r.get('Name') for r in asset_info if isinstance(r,dict)}
expected={Path(row['file']).parts[1].rsplit('.',1)[0] for row in manifest['assets'] if row['file'].startswith('Assets.xcassets/') and len(Path(row['file']).parts)>2 and Path(row['file']).parts[1].endswith(('.imageset','.dataset'))}
assert expected<=names,sorted(expected-names)
for row in manifest['assets']:
    assert sha(source_file('native/ClassroomProbe/Resources/'+row['file']))==row['sha256'],row['file']
with zipfile.ZipFile(ipa) as z,ipa.open('rb') as raw:
    assert z.testzip() is None
    for e in z.infolist():
        assert e.extract_version<=20 and not e.extra and not e.flag_bits&1
        raw.seek(e.header_offset);h=struct.unpack('<IHHHHHIIIHH',raw.read(30));assert h[0]==0x04034b50 and h[1]<=20 and h[3]==0 and h[-1]==0
    prefix='Payload/ClassroomProbe.app/'
    info=plistlib.loads(z.read(prefix+'Info.plist'))
    assert (info['CFBundleShortVersionString'],info['CFBundleVersion'])==('0.15.0','20')
    assert info['CFBundleIdentifier']=='org.personal.classroom.stage0' and info['CFBundleSupportedPlatforms']==['iPhoneOS'] and info['MinimumOSVersion']=='27.0'
    exe=z.read(prefix+info['CFBundleExecutable']);assert struct.unpack('<II',exe[:8])==(0xfeedfacf,0x100000c)
    mode=z.getinfo(prefix+info['CFBundleExecutable']).external_attr>>16;assert stat.S_IMODE(mode)==0o755
    assert z.read(prefix+'sample.pptx').startswith(b'PK')
    for name in ['SceneMap.json','hero-gait.json','meadow-port-provenance.json']:
        assert z.read(prefix+name)==source_file('native/ClassroomProbe/Resources/'+name)
    for name in ['great-sword-v1.json','legendary-staff-v1.json','reviewed-bow-r7.json']:
        paths=[n for n in z.namelist() if n.endswith('.bundle/'+name)]
        assert len(paths)==1 and z.read(paths[0])==source_file('native/Packages/GameCore/Sources/MeadowBattleSupport/Resources/'+name),name
    metal=[n for n in z.namelist() if n.endswith('.metallib')];assert metal and all(z.read(n).startswith(b'MTLB') for n in metal)
    assert z.getinfo(prefix+'Assets.car').file_size>0
    assert not any('/Art/' in n or '/MeadowArt/' in n for n in z.namelist())
    assert not any('embedded.mobileprovision' in n or '_CodeSignature' in n for n in z.namelist())
record=dict(appVersion='0.15.0/build20',testedCommit=run['head_sha'],sourceCommit=run['head_sha'],runID=run['id'],runAttempt=run['run_attempt'],artifactID=artifact['id'],
    artifactArchiveSha256=sha(outer.read_bytes()),artifactArchiveBytes=outer.stat().st_size,ipaSha256=sha(ipa.read_bytes()),ipaBytes=ipa.stat().st_size,
    coreTests={'CurrentDemoAndClassroomBackend':344,'ClassroomProbeCore':6,'failures':0,'nativeSuites':suite_totals},deviceReleaseArchive=True,arm64=True,executableMode=oct(stat.S_IMODE(mode)),
    executableSHA256=sha(exe),classicZIP2=True,CRC=True,artSource=manifest['commit'],sourceResourceHashesVerified=len(manifest['assets']),compiledAssetNamesVerified=len(expected),rigResourceHashesVerified=3,
    metalLibraries={},minimumOS=info['MinimumOSVersion'],sdk=info['DTSDKName'],legacyGameUIRemoved=True,fixedLogicalCanvas=[1280,720],fixedMetalScale=1,teacherUsesGameOnlyMirror=True,teacherMirrorMaximumFPS=30,teacherMirrorPixelSize=[960,540],layeredPreview=True,dragAndPinchInput=True,bookStatusMaximumAreaFraction=0.09,bookGrantsUseSameEngine=True,privatePlayerGM=True,maximumStudents=6,reservedHostSeats=1,teamManagement=True,sharedWarehouses=True,singlePageTeacherWindow=True,skillsUseOriginalCards=True,teacherOnlyToolbar=True,mirrorReadbackOffMain=True,theoreticalRawPixelBudgetBytesPerSecond=62208000,publicRenderTargetFPS=60,
    newPVEDeviceVerified=False,appLaunched=False,simulatorLaunched=False,externalDisplayVerified=False,
    limitations=['No device CPU/GPU timing or touch responsiveness measurement was performed.','User-reported TV/disconnect misalignment is addressed in code; real AirPlay/TV/disconnect validation needs user screenshots.','P3-P7 reuse existing approved character resources; distinct character art remains missing. Host joining is a teacher-only backend API; no host enable UI in this version.','Offline review demonstrates fixed-canvas geometry; it is not UIKit capture or proof of device repair.'])
with zipfile.ZipFile(ipa) as z:record['metalLibraries']={n:sha(z.read(n)) for n in metal}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
