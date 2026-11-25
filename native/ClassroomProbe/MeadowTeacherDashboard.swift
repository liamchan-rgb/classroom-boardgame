import SwiftUI
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport
import MeadowClassroomSupport

/// All game controls belong to this teacher-only window, not the public renderer.
struct MeadowTeacherDashboard:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    @State private var selectingNode=false
    @State private var fullPreview=false
    @State private var decks=false
    var body:some View {
        workspace(fullScreen:false).padding(8).background(GlassBackdrop())
            .fullScreenCover(isPresented:$fullPreview){workspace(fullScreen:true).padding(8).background(GlassBackdrop())}
            .onChange(of:fullPreview){_,value in game.localOutputPreview=value}
            .onChange(of:game.miniGame != nil){_,active in if active {selectingNode=false}}
            // 课件 from the game tab: opening a deck (or importing one) goes on in the book tab.
            .sheet(isPresented:$decks){
                DeckLibraryPanel(session:TeacherSession.shared,onImport:{
                    decks=false
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.5){TeacherSession.shared.bookTabRequest += 1;TeacherSession.shared.importRequest += 1}
                },onClose:{decks=false})
            }
    }
    private var inBattle:Bool {game.campaign?.engine.state.battle != nil}
    private var miniGameActive:Bool {game.miniGame != nil}
    private var targetName:String {game.campaign?.engine.state.units[game.selectedTarget]?.name ?? "选择目标"}
    private func workspace(fullScreen:Bool)->some View {
        VStack(spacing:8){
            HStack(spacing:8){
                Image(systemName:"leaf.fill").font(.system(size:18,weight:.bold)).foregroundStyle(GameTheme.primary).accessibilityLabel("林间旅程 v0.31.1")
                GlassChip(icon:game.externalConnected ? "tv.fill":"ipad.landscape",text:game.externalConnected ? "TV":"本机",tint:game.externalConnected ? .green:GameTheme.muted)
                #if targetEnvironment(macCatalyst)
                MacPublicWindowButton(connected:game.externalConnected)
                MacMirrorWarning()
                #else
                IPadPublicScreenButton(session:TeacherSession.shared,connected:game.externalConnected)
                #endif
                if let c=game.campaign,!inBattle {
                    GlassChip(icon:"figure.walk.motion",text:"\(MeadowMovementRules.steps(c.movementRemaining))/\(MeadowMovementRules.steps(c.movementCapacity))")
                    GlassChip(icon:"bitcoinsign.circle.fill",text:"\(c.engine.state.units[c.selectedPlayerID]?.coins ?? 0)",tint:GameTheme.accent)
                }
                if let c=game.campaign {
                    GlassChip(icon:difficultyIcon(c.difficulty),text:c.difficulty.title,tint:difficultyTint(c.difficulty))
                }
                Spacer(minLength:0)
                ClassroomToolbarTools(game:game)
                ToolbarGap()
                Button{fullPreview = !fullScreen}label:{Label(fullScreen ? "退出":"全屏",systemImage:fullScreen ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right")}
                // Everything not used every few minutes in class lives here, grouped; no duplicates of the bar buttons.
                Menu {
                    Section("行程") {
                        Button{game.settings()}label:{Label("新地图",systemImage:"map")}.disabled(game.busy || inBattle)
                        Button{game.restore()}label:{Label("继续上次行程",systemImage:"arrow.clockwise.circle")}.disabled(game.busy || inBattle)
                        Button{game.openArchives()}label:{Label("存档与历史",systemImage:"archivebox")}.disabled(game.busy)
                        Button{game.operation(.save)}label:{Label("立即保存",systemImage:"square.and.arrow.down")}.disabled(!game.ready || game.busy)
                    }
                    Section("地图") {
                        Button{game.operation(.route)}label:{Label("路线与结算",systemImage:"flag.checkered")}.disabled(!game.ready || game.busy)
                        Button{if let id=game.selectedNode{game.operation(.editNode(id))}}label:{Label("编辑选中地点",systemImage:"pencil")}.disabled(miniGameActive || game.selectedNode==nil || game.campaign?.isMoving==true || inBattle)
                        Button{if let id=game.selectedNode{game.project(.encounter(id))}}label:{Label("预览选中地点的怪物",systemImage:"eye")}.disabled(miniGameActive || game.selectedNode==nil || inBattle)
                        Menu {
                            ForEach(GameDifficulty.allCases,id:\.self){level in
                                Button{game.setDifficulty(level)}label:{Label(level.title+" · "+level.summary,systemImage:game.campaign?.difficulty==level ? "checkmark.circle.fill":difficultyIcon(level))}
                            }
                        }label:{Label("难度",systemImage:"gauge.with.dots.needle.67percent")}.disabled(game.busy || game.campaign==nil || inBattle || game.campaign?.isCompleted==true)
                    }
                    Section("队伍 PVP") {
                        Button{game.startDuel()}label:{Label("两队开战",systemImage:"figure.fencing")}.disabled(miniGameActive || !game.ready || game.busy || inBattle || game.duelOpponent==nil)
                        Button{game.resetDuels()}label:{Label("重置 PVP 次数",systemImage:"arrow.counterclockwise.circle")}.disabled(game.busy || game.campaign==nil || (game.campaign?.engine.state.pvpPairs ?? []).isEmpty)
                    }
                    Section("工具") {
                        Button{game.openGM()}label:{Label("GM 修改数值",systemImage:"wand.and.stars")}.disabled(!game.ready || game.busy || game.campaign==nil)
                        Button{game.openCharacterStudio()}label:{Label("人物形象",systemImage:"person.crop.circle.badge.plus")}.disabled(game.busy)
                        Button{decks=true}label:{Label("课件",systemImage:"rectangle.stack")}
                    }
                    Menu {
                        Button{game.openShortcutEditor()}label:{Label("快捷键",systemImage:"keyboard")}
                        Toggle(isOn:$game.liveMirrorPreferred){Label("教师画面用 GPU 实时显示",systemImage:"display.2")}
                        Toggle(isOn:$game.highFrameRate){Label("地图 60 帧（关：30 帧更省电）",systemImage:"speedometer")}
                        Button{game.openPixelCharacterLab()}label:{Label("像素人物实验室",systemImage:"square.grid.3x3.square")}.disabled(game.busy)
                    }label:{Label("设置",systemImage:"gearshape")}
                }label:{Label("更多",systemImage:"ellipsis.circle")}
            }.buttonStyle(ToolbarIconStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            if game.campaign != nil {
                HStack(spacing:8){
                    if inBattle {
                        Menu {
                            ForEach(battleTargets){u in Button(u.name){game.chooseBattleTarget(u.id)}}
                        }label:{Label(targetName,systemImage:"scope")}
                        .disabled(miniGameActive || !game.ready || game.busy)
                        Menu {
                            ForEach([PartyAction.smallPotion,.largePotion,.shieldPotion,.revivalStone],id:\.rawValue){action in
                                Button(action.title){game.battle(action)}.disabled(!game.canUse(action))
                            }
                        }label:{Label("道具",systemImage:"cross.vial.fill")}.disabled(miniGameActive || !game.ready || game.busy)
                        let paused=game.campaign?.engine.state.pauseReasons.contains(.manual)==true
                        Button{game.toggleBattlePause()}label:{Label(paused ? "继续":"暂停",systemImage:paused ? "play.fill":"pause.fill")}.disabled(miniGameActive || game.busy)
                        Menu {
                            Button(role:.destructive){game.leaveBattle()}label:{Label("确认撤离战斗（无掉落，怪物留在原地）",systemImage:"figure.walk.departure")}
                        }label:{Label("撤离",systemImage:"figure.walk.departure")}.disabled(miniGameActive || !game.ready || game.busy || game.campaign?.canLeaveBattle != true)
                        Spacer(minLength:0)
                        Button{game.battle(.endTurn)}label:{Label("结束",systemImage:"forward.end.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(miniGameActive || !game.canUse(.endTurn))
                    }else{
                        memberPicker
                        Button{selectingNode.toggle();if selectingNode{game.project(.exploration)}}label:{Label(selectingNode ? "完成":"选点",systemImage:selectingNode ? "checkmark.circle.fill":"mappin.and.ellipse")}
                            .buttonStyle(GlassIconButtonStyle(tint:selectingNode ? .orange:GameTheme.primary)).disabled(miniGameActive || !game.ready || game.busy)
                        if selectingNode {
                            Button{if let id=game.selectedNode{game.operation(.editNode(id))}}label:{Label("修改",systemImage:"pencil")}.disabled(miniGameActive || game.selectedNode==nil || game.campaign?.isMoving==true)
                        }else{
                            Button{game.operation(.interact)}label:{Label("交互",systemImage:"hand.tap.fill")}.disabled(miniGameActive || !game.ready || game.busy || game.campaign?.isMoving==true)
                            Button{game.operation(.inventory)}label:{Label("行囊",systemImage:"bag.fill")}.disabled(!game.ready || game.busy || game.campaign?.isCompleted != false)
                            Button{game.operation(.shop)}label:{Label("商店",systemImage:"cart.fill")}.disabled(!game.ready || game.busy || game.campaign?.isCompleted != false)
                            Button{game.openTeamConsole()}label:{Label("队伍",systemImage:"person.3.fill")}.disabled(!game.ready || game.busy || game.campaign?.isCompleted != false)
                        }
                        Spacer(minLength:0)
                        if miniGameActive {
                            Label("小游戏进行中，地图已锁定",systemImage:"lock.fill").font(.caption.bold()).foregroundStyle(.orange)
                        }
                        Button{game.operation(.refill)}label:{Label("补充",systemImage:"bolt.fill")}.disabled(miniGameActive || !game.ready || game.busy || game.campaign?.isMoving==true)
                        Button{game.operation(.pauseOrResume)}label:{Label(game.campaign?.isMoving==true ? "暂停":"出发",systemImage:game.campaign?.isMoving==true ? "pause.fill":"play.fill")}
                            .buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(miniGameActive || !game.ready || game.busy)
                    }
                }.buttonStyle(GlassIconButtonStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            }
            HStack(spacing:8){
            ZStack {
                if game.renderer != nil && (fullScreen || !fullPreview) {
                    TeacherGamePreview(game:game,selectingNode:selectingNode)
                }else if game.campaign==nil {
                    VStack(spacing:22){
                        Image(systemName:"leaf.circle.fill").font(.system(size:64)).foregroundStyle(.white.opacity(0.9))
                        HStack(spacing:16){
                            Button{game.settings()}label:{Label("新地图",systemImage:"map.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true))
                            Button{game.restore()}label:{Label("继续",systemImage:"arrow.clockwise.circle.fill")}.buttonStyle(GlassIconButtonStyle(tint:.white))
                            Button{game.openCharacterStudio()}label:{Label("形象",systemImage:"person.crop.circle.badge.plus")}.buttonStyle(GlassIconButtonStyle(tint:.white))
                            Button{game.openPixelCharacterLab()}label:{Label("像素人物",systemImage:"square.grid.3x3.square")}.buttonStyle(GlassIconButtonStyle(tint:.white))
                        }.scaleEffect(1.3)
                    }
                }else{Color.black}
                if game.surface == .book {
                    VStack(spacing:14){
                        Image(systemName:"book.pages.fill").font(.system(size:44))
                        Text("TV 正在显示绘本").font(.headline)
                        Button{TeacherSession.shared.concealNotes();game.project(.exploration)}label:{Label("切回游戏",systemImage:"gamecontroller.fill")}
                            .buttonStyle(GlassIconButtonStyle(prominent:true)).scaleEffect(1.2)
                    }.foregroundStyle(.white).padding(28).background(.black.opacity(0.55),in:RoundedRectangle(cornerRadius:22,style:.continuous))
                }else if !inBattle,game.surface != .exploration,!miniGameActive {
                    VStack{HStack{Spacer();Button{game.project(.exploration)}label:{Label("地图",systemImage:"map")}.buttonStyle(GlassIconButtonStyle(tint:.white)).padding(12)};Spacer()}
                }
            // minWidth 0: the preview gives up width to the docked answer panel.
            }.frame(minWidth:0,maxWidth:.infinity,minHeight:0,maxHeight:.infinity).background(.black).clipShape(RoundedRectangle(cornerRadius:18,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(.white.opacity(0.5),lineWidth:1))
            // The question's answer panel, beside the preview (the full-screen copy shows it when it is up).
            if fullScreen == fullPreview {QuizDock(game:game,book:false)}
            }
            MiniGameBar(game:game)
            HStack(spacing:8){
                Image(systemName:selectingNode && !inBattle ? "mappin.and.ellipse":(inBattle ? "hand.point.up.left.fill":"info.circle")).foregroundStyle(GameTheme.primary)
                Text(selectingNode && !inBattle ? "点建筑选取地点":"\(game.message)").lineLimit(1).truncationMode(.tail)
                Spacer(minLength:0)
            }.font(.caption).foregroundStyle(GameTheme.muted).padding(.horizontal,14).frame(height:30).glassPanel(radius:15,padding:0)
        }.foregroundStyle(GameTheme.ink).background(GlassBackdrop())
    }
    /// Members grouped by team: picking someone of another team switches the walking party (the other team's road is parked).
    private var memberPicker:some View {
        let c=game.campaign,teams=c?.engine.state.teams ?? [],players=c?.engine.state.players ?? []
        let current=c?.engine.state.units[c?.selectedPlayerID ?? ""]
        return Menu {
            ForEach(teams){team in
                let members=players.filter{$0.teamID==team.id}
                if !members.isEmpty {
                    Section(team.name+(c?.parkedTravels[team.id] != nil ? " · 路上":"")) {
                        ForEach(members){u in
                            Button{game.select(u.id)}label:{Label(u.name,systemImage:u.id==current?.id ? "checkmark.circle.fill":(u.isAlive ? "person.fill":"person.slash"))}
                        }
                    }
                }
            }
        }label:{Label(current.map{$0.name.components(separatedBy:" · ").first ?? $0.name} ?? "成员",systemImage:teams.count>1 ? "person.2.fill":"person.fill")}
        .disabled(!game.ready || game.busy)
    }
    private func difficultyIcon(_ level:GameDifficulty)->String {
        switch level {case .easy:return "leaf";case .normal:return "shield.lefthalf.filled";case .hard:return "flame";case .nightmare:return "bolt.trianglebadge.exclamationmark"}
    }
    private func difficultyTint(_ level:GameDifficulty)->Color {
        switch level {case .easy:return .green;case .normal:return GameTheme.primary;case .hard:return .orange;case .nightmare:return .red}
    }
    private var battleTargets:[GameUnit] {
        guard let c=game.campaign else{return []}
        return c.engine.state.units.values.filter{$0.kind == .player || c.engine.state.battle?.queue.contains($0.id)==true}.sorted{$0.id<$1.id}
    }
}

private struct TeacherGamePreview:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    let selectingNode:Bool
    @State private var previewID=UUID()
    var body:some View {
        PublicSurface(model:TeacherSession.shared.display,game:game,teacherPreview:true)
            .overlay {
                MeadowTeacherMapInput(canBegin:game.canBeginMapGesture,canTap:game.canTapCanvas,
                    tap:{game.canvasTap($0,selectingNode:selectingNode)},
                    pan:game.canvasPan,zoom:{game.canvasZoom($0,anchor:$1)},hover:game.canvasHover)
            }
            .overlay{MiniGameTapLayer(game:game)}
            .overlay{QuizRevealTapCatcher(game:game)}
            .overlay{LaserCapture(laser:game.laser)}
            .onAppear{game.previewVisibility(previewID,visible:true)}
            .onDisappear{game.previewVisibility(previewID,visible:false);game.canvasHover(nil)}
    }
}
