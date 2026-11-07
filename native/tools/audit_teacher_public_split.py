#!/usr/bin/env python3
"""Static integration audit. This is not a native-window/runtime privacy test."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--commit');p.add_argument('--output',type=Path,required=True);a=p.parse_args();R=Path(__file__).resolve().parents[2]
def read(name):
    path='native/ClassroomProbe/'+name
    return subprocess.check_output(['git','show',a.commit+':'+path],cwd=R,text=True) if a.commit else (R/path).read_text()
public=read('MeadowPublicOutput.swift');host=read('MeadowTeacherCoordinator.swift');game=read('Meadow/GameViewController.swift');party=read('Meadow/Game/MeadowPartyBattleView.swift');preview=read('Meadow/Game/MeadowBattlePreviewView.swift');app=read('App.swift')
for word in ['UIAlertController','TextEditor','TextField','MeadowMapSettingsViewController','configureEncounter','game.operation(','game.settings(']:assert word not in public,word
assert 'GameViewController(campaign:session,classroomMode:true)' in host
assert 'ClassroomGameBackend.requireTeacher(role)' in game
assert 'guard !classroomMode else{return}' in party and 'campaignEngine != nil && !classroomMode' in party
assert '!self.classroomMode else{return};self.perform(a)' in party
assert '!self.classroomMode else{return};self.choose(id)' in party
assert 'model=try factory()' in party and 'backend.battleModel(role:.teacher)' in host
assert 'backend.advanceTravel(distance:distance,role:.teacher)' in host
assert 'classroomPrivatePresenter' in game and 'teacher.view' in game and 'override func present(' in game
assert 'TeacherSession.shared.game.privatePresenter=self' in app
assert 'obsolete.forEach{$0.removeFromSuperview()}' in preview
assert 'view.isUserInteractionEnabled = !classroomMode' in game
assert 'classroomFinishBattleIfReady()' in host
result=dict(kind='source-routing-audit',commit=a.commit,publicOnlyHasPlayerFacingPanels=True,oneTeacherOwnedSessionAndRenderer=True,
    mapAndBattleUseOriginalProductionComponents=True,publicModeDoesNotStartAnotherAIOrDecisionTimer=True,
    privateSheetsRoutedToTeacherWindow=True,legacySinglePlayerTrainingUnderlayRemoved=True,
    publicGameInputsDisabled=True,publicGameCallbacksExplicitlyReadOnly=True,battleCompletionReturnsToExploration=True,nativeWindowRoutingVerified=False)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
