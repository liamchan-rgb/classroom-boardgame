#!/usr/bin/env python3
"""Archive the verified bridge build and publish selected files on archive-assets.

Run in CI with a full source history and explicit contents-write authorization.
Never checks out, merges, or archives the binary backup branch into source.
"""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,tempfile,urllib.request,zipfile

R=Path(__file__).resolve().parents[1];os.chdir(R)
milestone='archive-browser-meadow-v0.18.0-20261107'
record_path='docs/integration/archive-browser-v0.18.0-build.json'
record=json.loads((R/record_path).read_text());repo='liamchan-rgb/classroom-boardgame'
T=Path(os.environ['RUNNER_TEMP'])/'meadow-milestone';T.mkdir(exist_ok=False)
D=T/'deliveries';D.mkdir()
def run(*args,**kwargs):return subprocess.check_output(args,text=True,**kwargs).strip()
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        while b:=f.read(1024*1024):h.update(b)
    return h.hexdigest()
def gh(path):return json.loads(run('gh','api',path))
current=run('git','rev-parse','HEAD')
run('git','merge-base','--is-ancestor',record['testedCommit'],current)
assert run('git','rev-parse','--is-shallow-repository')=='false'
assert not run('git','status','--porcelain','--untracked-files=no')
action=gh(f'repos/{repo}/actions/runs/{record["runID"]}')
assert action['conclusion']=='success' and action['head_sha']==record['testedCommit']
artifact=gh(f'repos/{repo}/actions/artifacts/{record["artifactID"]}')
assert artifact['workflow_run']['head_sha']==record['testedCommit'] and not artifact['expired']
archive=D/'ClassroomStage2-v0.18.0-build.zip'
subprocess.run(['curl','-fLsS','--retry','3','-H','Authorization: Bearer '+os.environ['GH_TOKEN'],
    f'https://api.github.com/repos/{repo}/actions/artifacts/{record["artifactID"]}/zip','-o',str(archive)],check=True)
assert sha(archive)==record['artifactArchiveSha256'] and artifact['digest']=='sha256:'+sha(archive)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    ipa='ClassroomStage2-v0.18.0-unsigned.ipa';(D/ipa).write_bytes(z.read(ipa))
assert sha(D/ipa)==record['ipaSha256']
for name in ['archive-browser-normal.gif','archive-browser-contact-sheet.png','archive-browser-review-input.json']:
    shutil.copy2(R/'docs/integration/archive-browser-review-v0.18.0'/name,D/name)
(D/'verification.json').write_text(json.dumps(record,indent=2)+'\n')
selected=[p.name for p in D.iterdir()];selection=T/'selected.json';selection.write_text(json.dumps(selected))
run('git','config','user.name','github-actions[bot]');run('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
try:
    tag=run('git','rev-parse','refs/tags/'+milestone)
except subprocess.CalledProcessError:
    run('git','tag',milestone,current);tag=current
assert tag==current,'Never replace an existing milestone tag'
output=T/(milestone+'.zip')
result=run('python3','tools/archive_milestone.py','--milestone',milestone,'--snapshot',current,'--build-record',record_path,
    '--deliveries-root',str(D),'--delivery-list',str(selection),'--output',str(output))
print(result,flush=True)
# The archive tool verifies every payload hash. Also prove the Git bundle can
# restore the source commit without prerequisites or the original repository.
with zipfile.ZipFile(output) as z:
    bundle=T/'git-history.bundle';bundle.write_bytes(z.read('git-history.bundle'))
    with bundle.open('rb') as f:
        while line:=f.readline():
            if line==b'\n':break
            assert not line.startswith(b'-'),'Bundle has unavailable prerequisites'
    restored=T/'restored'
    run('git','clone','--no-checkout',str(bundle),str(restored))
    assert run('git','-C',str(restored),'rev-parse',milestone)==current
    run('git','-C',str(restored),'fsck','--full','--no-dangling')
    assert run('git','-C',str(restored),'show',current+':'+record_path)==(R/record_path).read_text().strip()
    shutil.rmtree(restored);bundle.unlink()
transport=T/milestone
print(run('python3','tools/split_milestone.py',str(output),str(transport)),flush=True)
for suffix in ['.manifest.json','.zip.sha256','.恢复说明.md']:
    source=output.with_suffix(suffix) if suffix!='.zip.sha256' else output.with_suffix('.zip.sha256')
    shutil.copy2(source,transport/source.name)
for p in D.iterdir():shutil.copy2(p,transport/p.name)
(transport/'README.md').write_text(f'''# Meadow archive search, history categories and art integration contract v0.18.0

Source snapshot/tag: `{current}` / `{milestone}`.
Actual device Release compiled commit: `{record['testedCommit']}`.
Build run: https://github.com/{repo}/actions/runs/{record['runID']}
IPA: `{ipa}`, SHA256 `{record['ipaSha256']}`, {record['ipaBytes']} bytes.
403 GameCore/backend + 6 ProbeCore tests passed. No app, simulator or device was launched.
GIF is an offline fixed-canvas layout demonstration, not a runtime screenshot or confirmation of device repair.
Teacher owns the current demo rules, map generation and private controls. Public output uses the full existing Meadow map/battle renderer and read-only player panels; no old game fallback.
Download all .part files, transport.json and restore_zip.py to restore the archive ZIP; follow its recovery guide.
''')
# Preserve the current remote tree using an isolated index. No source checkout
# or old archive content is added to the source branch or downloaded here.
run('git','fetch','--depth=1','--filter=blob:none','origin','archive-assets:refs/remotes/origin/archive-assets')
parent=run('git','rev-parse','refs/remotes/origin/archive-assets')
env=dict(os.environ,GIT_INDEX_FILE=str(T/'archive-index'))
run('git','read-tree',parent,env=env)
existing=run('git','ls-tree',parent,'--',milestone)
assert not existing,'Milestone folder already exists; never overwrite it'
rows=[]
for file in sorted(transport.iterdir()):
    blob=run('git','hash-object','-w',str(file))
    run('git','update-index','--add','--cacheinfo','100644',blob,milestone+'/'+file.name,env=env)
    rows.append(dict(file=file.name,bytes=file.stat().st_size,sha256=sha(file)))
tree=run('git','write-tree',env=env)
commit=run('git','commit-tree',tree,'-p',parent,'-m','Archive verified archive search, history categories and art integration contract v0.18.0')
run('git','push','origin',commit+':refs/heads/archive-assets')
run('git','push','origin','refs/tags/'+milestone)
# Verify all public bytes with a full, unauthenticated GET, including every part.
base=f'https://raw.githubusercontent.com/{repo}/{commit}/{milestone}/'
for row in rows:
    target=T/'public-get'
    subprocess.run(['curl','-fLsS','--retry','4',base+row['file'],'-o',str(target)],check=True)
    assert target.stat().st_size==row['bytes'] and sha(target)==row['sha256'],row['file']
    target.unlink()
receipt=dict(milestone=milestone,sourceSnapshotCommit=current,compiledCommit=record['testedCommit'],archiveCommit=commit,
    archiveSHA256=sha(output),archiveBytes=output.stat().st_size,bundleRestoreVerified=True,allPublicGETVerified=True,
    ipaURL=base+ipa,gifURL=base+'archive-browser-normal.gif',archiveURL=base+'README.md',files=rows)
(T/'archive_publish_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2),flush=True)
