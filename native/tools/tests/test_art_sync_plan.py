import importlib.util,subprocess,tempfile,unittest
from pathlib import Path

P=Path(__file__).resolve().parents[3]/'tools/plan_experiment_art_update.py'
spec=importlib.util.spec_from_file_location('art_plan',P);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class ArtSyncPlanTests(unittest.TestCase):
    def repo(self,path):
        path.mkdir();subprocess.run(['git','init','-q',str(path)],check=True);self.run_git(path,'config','user.name','Test');self.run_git(path,'config','user.email','test@example.invalid')
    def run_git(self,path,*args):return subprocess.check_output(['git','-C',str(path),*args],stderr=subprocess.DEVNULL).decode().strip()
    def write(self,root,path,value):p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(value)
    def commit(self,p):self.run_git(p,'add','.');self.run_git(p,'commit','-qm','fixture');return self.run_git(p,'rev-parse','HEAD')
    def testMappingSeparatesPresentationFromRulesAndPrivateShell(self):
        self.assertEqual(mod.mapping('Sources/Game/HeroFrames.swift')[0],'native/ClassroomProbe/Meadow/Game/HeroFrames.swift')
        self.assertEqual(mod.mapping('Vendor/ClassroomGameCore/Sources/MeadowBattleSupport/Resources/reviewed-bow-r7.json')[1],'battle-presentation-review')
        for path in ['Sources/AppDelegate.swift','Vendor/ClassroomGameCore/Sources/ClassroomGameCore/GameState.swift','Sources/Resources/Info.plist','Art/Review/a.gif']:self.assertIsNone(mod.mapping(path)[0])
    def testCommittedAddModifyDeleteAndAdaptationAreReportedWithoutWriting(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);source=root/'source';dest=root/'dest';self.repo(source);self.repo(dest)
            self.write(source,'Sources/Game/HeroFrames.swift','base');self.write(source,'Sources/Resources/old.json','old');base=self.commit(source)
            self.write(dest,'native/ClassroomProbe/Meadow/Game/HeroFrames.swift','classroom-adapted');self.commit(dest)
            self.write(source,'Sources/Game/HeroFrames.swift','new');self.write(source,'Sources/Resources/new.json','new');(source/'Sources/Resources/old.json').unlink();target=self.commit(source)
            report=mod.plan(source,dest,base,target);rows={r['source']:r for r in report['rows']}
            self.assertTrue(rows['Sources/Game/HeroFrames.swift']['destinationDiffersFromBase']);self.assertEqual(rows['Sources/Resources/new.json']['change'],'A');self.assertEqual(rows['Sources/Resources/old.json']['change'],'D');self.assertTrue(report['notApplied'])
            self.assertEqual((dest/'native/ClassroomProbe/Meadow/Game/HeroFrames.swift').read_text(),'classroom-adapted');self.assertFalse((dest/'native/ClassroomProbe/Resources/new.json').exists())
    def testDirtyWorktreeDoesNotBecomeAnUpdate(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);source=root/'source';dest=root/'dest';self.repo(source);self.repo(dest);self.write(source,'Sources/Game/a.swift','same');sha=self.commit(source);self.write(dest,'README.md','x');self.commit(dest);self.write(source,'Sources/Game/a.swift','uncommitted')
            report=mod.plan(source,dest,sha,sha);self.assertTrue(report['sourceWorktreeHasChanges']);self.assertEqual(report['rows'],[])
    def testRequiresPinnedSHAAndRejectsUnsafePaths(self):
        with self.assertRaises(ValueError):mod.pinned(Path('.'),'HEAD')
        with self.assertRaises(ValueError):mod.mapping('../secret')
        with self.assertRaises(ValueError):mod.mapping('/secret')
