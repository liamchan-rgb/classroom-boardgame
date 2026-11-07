#!/usr/bin/env python3
"""Read-only experiment -> classroom visual-update inventory. Never applies files."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path,PurePosixPath


def git(repo,*args,optional=False):
    p=subprocess.run(['git','-C',str(repo),*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if p.returncode:
        if optional:return None
        raise ValueError(p.stderr.decode(errors='replace').strip())
    return p.stdout


def pinned(repo,value):
    if not re.fullmatch(r'[0-9a-fA-F]{40}',value):raise ValueError('Use an explicit full 40-character commit SHA.')
    return git(repo,'rev-parse','--verify',value+'^{commit}').decode().strip()


def mapping(path):
    parts=PurePosixPath(path).parts
    if '..' in parts or path.startswith('/'):raise ValueError('Unsafe source path')
    root='native/ClassroomProbe/'
    if path=='Sources/Resources/Info.plist' or path.startswith('Sources/Resources/Assets.xcassets/AppIcon.appiconset/'):
        return None,'app-identity-review'
    if path.startswith('Sources/Resources/'):
        return root+'Resources/'+path.removeprefix('Sources/Resources/'),'resource-and-metadata-review'
    if path.startswith(('Sources/Game/','Sources/UI/','Sources/ShadowLab/')):
        return root+'Meadow/'+path.removeprefix('Sources/'),'adapt-renderer-code'
    if path=='Sources/GameViewController.swift':return root+'Meadow/GameViewController.swift','adapt-renderer-code'
    prefix='Vendor/ClassroomGameCore/Sources/MeadowBattleSupport/'
    if path.startswith(prefix):return 'native/Packages/GameCore/Sources/MeadowBattleSupport/'+path.removeprefix(prefix),'battle-presentation-review'
    if path.startswith('Vendor/ClassroomGameCore/'):return None,'protect-classroom-rules-and-saves'
    if path.startswith(('Art/','Media/')):return None,'offline-reference-only'
    return None,'app-shell-or-unmapped-review'


def digest(data):return hashlib.sha256(data).hexdigest() if data is not None else None


def plan(source,destination,base,target):
    base=pinned(source,base);target=pinned(source,target)
    raw=git(source,'diff','--name-status','-z','--no-renames',base,target,'--','Sources','Vendor/ClassroomGameCore','Art','Media').decode().split('\0')
    rows=[]
    for i in range(0,len(raw)-1,2):
        status,path=raw[i:i+2];dest,policy=mapping(path)
        before=git(source,'show',base+':'+path,optional=True);after=git(source,'show',target+':'+path,optional=True)
        local=(destination/dest).read_bytes() if dest and (destination/dest).is_file() else None
        rows.append(dict(change=status,source=path,destination=dest,policy=policy,baseSHA256=digest(before),sourceSHA256=digest(after),destinationSHA256=digest(local),
            destinationDiffersFromBase=local is not None and digest(local)!=digest(before),alreadyMatchesTarget=after is not None and digest(local)==digest(after)))
    return dict(format='experiment-art-update-plan',version=1,sourceRepository='liamchan-rgb/experiment',baseCommit=base,sourceCommit=target,
        destinationCommit=git(destination,'rev-parse','HEAD').decode().strip(),destinationWorktreeHasChanges=bool(git(destination,'status','--porcelain').strip()),notApplied=True,
        sourceWorktreeHasChanges=bool(git(source,'status','--porcelain').strip()),rows=rows,
        note='Source from committed trees; destination hashes from its current worktree (HEAD recorded separately). No copying, deleting, merging, provenance editing, build or App launch. Review paired images/rigs/timing, keep teacher controls and multi-player adaptations.')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--experiment',type=Path,required=True);p.add_argument('--classroom',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--from-commit');p.add_argument('--to-commit',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    base=a.from_commit or json.loads((a.classroom/'native/ClassroomProbe/Resources/meadow-port-provenance.json').read_text())['commit']
    report=plan(a.experiment,a.classroom,base,a.to_commit)
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(base=report['baseCommit'],target=report['sourceCommit'],changed=len(report['rows']),notApplied=True)))

if __name__=='__main__':main()
