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
dashboard=read('MeadowTeacherDashboard.swift');mirror=read('MeadowClassroomFrameMirror.swift');metal=read('Meadow/Game/MeadowShadowRenderer.swift')
assert 'TeacherControlMap' not in dashboard and 'Canvas{' not in dashboard
assert 'TeacherGamePreview' in dashboard and 'game.canvasTap(point,selectingNode:selectingNode)' in dashboard
assert 'ClassroomCanvas.size' in host and 'controller.view.frame=view.bounds' not in host
assert 'ground.autoResizeDrawable = !classroomMode' in game and 'classroomMode ? .aspectFit:.resizeFill' in game
assert 'ground.drawableSize=pixels' in game
assert 'encodeClassroomMirror(command:command,texture:drawable.texture)' in metal and '!mirrorBusy' in metal
assert 'waitUntilCompleted' not in metal[metal.index('private struct MirrorCopy'):metal.index('/// The offscreen repeated probe')]
assert 'for subview in view.subviews where subview !== groundView' in game and 'classroomCaptureFrame' in host
assert 'teacherPreview && game.externalConnected' in public and 'MeadowTeacherMirror(mirror:game.frameMirror)' in public
assert 'UIWindow' not in mirror and 'campaign' not in mirror.replace('campaign/renderer','')
result=dict(kind='source-routing-audit',commit=a.commit,publicOnlyHasPlayerFacingPanels=True,oneTeacherOwnedSessionAndRenderer=True,
    mapAndBattleUseOriginalProductionComponents=True,publicModeDoesNotStartAnotherAIOrDecisionTimer=True,
    privateSheetsRoutedToTeacherWindow=True,legacySinglePlayerTrainingUnderlayRemoved=True,
    publicGameInputsDisabled=True,publicGameCallbacksExplicitlyReadOnly=True,battleCompletionReturnsToExploration=True,fixedCanvasAndDrawablePolicy=True,teacherUsesActualGameOnlyMirror=True,teacherSimplifiedMapRemoved=True,actualProjectionUsedForInput=True,nativeWindowRoutingVerified=False)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
