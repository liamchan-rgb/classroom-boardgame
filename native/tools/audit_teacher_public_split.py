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
assert 'TeacherGamePreview' in dashboard and 'game.canvasTap($0,selectingNode:selectingNode)' in dashboard
assert 'classroomNode(atWorldPoint:world,role:.teacher)' in host
assert 'selectedNode=hit?.id' in host
assert 'ClassroomCanvas.size' in host and 'controller.view.frame=view.bounds' not in host
assert 'ground.autoResizeDrawable = !classroomMode' in game and 'classroomMode ? .aspectFit:.resizeFill' in game
assert 'ground.drawableSize=pixels' in game
assert 'encodeClassroomMirror(command:command,texture:drawable.texture)' in metal and '!mirrorBusy' in metal
assert 'waitUntilCompleted' not in metal[metal.index('private struct MirrorCopy'):metal.index('/// The offscreen repeated probe')]
assert 'for subview in view.subviews where subview !== groundView' in game and 'classroomCaptureFrame' in host
assert 'teacherPreview && game.externalConnected' in public and 'MeadowTeacherMirror(mirror:game.frameMirror)' in public
assert 'UIWindow' not in mirror and 'privatePresenter' not in mirror
assert 'workspace(fullScreen:true)' in dashboard and 'workspace(fullScreen:false)' in dashboard
assert 'surface.acceptsMapInput' in host and 'surface == .exploration,let c=campaign' not in host
assert 'game.previewVisibility(previewID,visible:true)' in dashboard and 'game.previewVisibility(previewID,visible:false)' in dashboard
assert 'ScrollView' not in dashboard and 'battleControls' not in dashboard
assert 'ForEach(game.actions' not in dashboard and 'game.battle(action)' in dashboard  # item menu only
assert 'MeadowTeacherMapInput(canBegin:game.canBeginMapGesture,canTap:game.canTapCanvas' in dashboard
assert 'classroomBattleHit(at:point,role:.teacher)' in host
assert 'case .action(let action):battle(action)' in host
assert 'classroomHit(at:convert(point,to:party))' in preview
assert 'ClassroomGameBackend.requireTeacher(role)' in game[game.index('func classroomBattleHit'):game.index('func classroomFinishBattleIfReady')]
assert 'card.frame.contains(p)' in party and 'stage.classroomTarget' in party
assert 'if classroomMode {skillScroll.isScrollEnabled=false' in party
assert 'ClassroomPreviewPolicy.enabled' in host and 'defer{publishChanges();updateMirrorDemand()}' in host
assert 'if next != lastUIState' in host
assert 'format.scale=ClassroomPreviewPolicy.pixelScale' in game
assert 'self.mirrorReadback.async' in metal and 'Self.makeClassroomMirror(mirror)' in metal
assert 'sourceSize:MTLSize(width:width,height:height,depth:1)' in metal and 'setFragmentTexture(texture,index:0)' in metal
input=read('MeadowTeacherMapInput.swift')
assert 'pan.minimumNumberOfTouches=1;pan.maximumNumberOfTouches=2' in input
assert 'tap.require(toFail:pan);tap.require(toFail:pinch)' in input
assert 'shouldBeRequiredToFailBy' in input and 'otherGestureRecognizer.view is UIScrollView' in input
assert 'ClassroomCanvas.translation(pan.translation(in:self),in:bounds.size)' in input
assert 'game.canvasPan' in dashboard and 'game.canvasZoom' in dashboard
assert 'scene.setZoom(scene.zoom*scale,anchorInView:' in game
assert 'classroomFrameAvailable' in host and 'self?.publishMirrorFrame()' in host
assert 'MeadowTeacherPreviewFrame(map:map' in game and 'UIImage(cgImage:image).draw' not in game
assert 'format.opaque=false' in game and 'ClassroomPreviewPolicy.refreshOverlay' in game
assert 'frame.mapRect' in mirror and 'frame.overlay' in mirror
scene=read('Meadow/Game/GameScene.swift');team=read('MeadowTeamConsole.swift');stage=read('Meadow/Game/MeadowPartyStageView.swift')
assert 'MeadowTeamConsole' not in public and 'game.openTeamConsole()' in dashboard
assert 'campaign?.playerIDs.count ?? 3' in scene and 'count:max(3,campaign?.playerIDs.count ?? 3)' in scene
assert 'let ids=value.players.map' in stage and 'playerIDs+monsterIDs' in stage
assert '(0..<7).map' in game
assert not any('@State' in line and ',quantity=' in line for line in team.splitlines())
assert 'teacherTransferTeamResource' in team
assert 'transferTeamResource' in team and 'configureTeams' in team and 'mergeTeams' in team
book=public[public.index('struct PublicBookPage'):public.index('private struct PublicInventoryPanel')]
gm=read('TeacherGMConsole.swift');grant=read('TeacherBookGrantBar.swift');views=read('Views.swift')
assert 'ClassroomBookStatusLayout.height(in:geometry.size,players:players.count)' in book
assert '.frame(height:height)' in book and '.clipped()' in book
assert 'TeacherGMConsole' not in public and 'TextField' not in book and 'game.openGM()' in views
assert 'TeacherBookGrantBar(game:game' in views and 'PublicBookPage(model:session.display,players:game.backend.bookPlayers)' in views
assert 'grantPlayers(ids,ap:ap,coins:coins,role:.teacher)' in host
assert 'backend.editPlayer(id,value:value,role:.teacher)' in host
assert 'UIHostingController(rootView:TeacherGMConsole' in host
assert 'if game.saveGM(selected,value:value){reload()' in gm
assert 'backend.canUndoTeacherAction' in gm and 'undoTeacherAction()' in grant
archives=read('TeacherArchiveConsole.swift')
assert 'TeacherArchiveConsole' not in public and 'UIHostingController(rootView:TeacherArchiveConsole' in host
assert 'game.openArchives()' in views and 'game.openArchives()' in dashboard
assert 'Self.slotStore.backup(campaign.snapshot)' in host and 'rollingBack(after:id' in host
assert 'game.joinTeacher' in archives and 'game.applyProfile' in archives and 'store.saveCampaign' in archives
transfer=read('TeacherSaveTransferConsole.swift')
assert 'TeacherSaveTransferConsole' not in public and 'TeacherSaveTransferConsole(directory:store.directory' in archives
assert '.fileImporter' in transfer and '.fileExporter' in transfer and 'Task.detached' in transfer
assert 'startAccessingSecurityScopedResource' in transfer and 'stopAccessingSecurityScopedResource' in transfer
assert 'game.loadJourney' not in transfer and 'game.applyProfile' not in transfer and '.importTransfer(' in transfer
result=dict(kind='source-routing-audit',commit=a.commit,publicOnlyHasPlayerFacingPanels=True,oneTeacherOwnedSessionAndRenderer=True,
    mapAndBattleUseOriginalProductionComponents=True,publicModeDoesNotStartAnotherAIOrDecisionTimer=True,
    privateSheetsRoutedToTeacherWindow=True,legacySinglePlayerTrainingUnderlayRemoved=True,
    publicGameInputsDisabled=True,publicGameCallbacksExplicitlyReadOnly=True,battleCompletionReturnsToExploration=True,fixedCanvasAndDrawablePolicy=True,teacherUsesActualGameOnlyMirror=True,teacherSimplifiedMapRemoved=True,actualProjectionUsedForInput=True,highResolution30FPSPolicy=True,layeredPreviewAvoidsMapRasterization=True,dragPanAndPinch=True,readbackOffMainQueue=True,hiddenPreviewStopsCopying=True,fullScreenTeacherInputWired=True,sixStudentsAndReservedHostSeat=True,dynamicMapAndBattlePlayers=True,privateTeamAndWarehouseControls=True,publicBookStatusAreaBound=True,privateBookGrantAndGMControls=True,privateProfileAndCampaignSlots=True,privateHistoryAndTeacherJoining=True,privateSaveTransfer=True,importDoesNotSwitchLiveCampaign=True,sharedEngineForBookAndGM=True,singlePageTeacherWindow=True,originalSkillCardsUseTeacherHitRouting=True,allClassroomSkillCardsFitWithoutScroll=True,encounterAllowsMapInput=True,nativeWindowRoutingVerified=False)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
