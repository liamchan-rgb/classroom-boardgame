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
    var body:some View {
        workspace(fullScreen:false).padding(8).background(GlassBackdrop())
            .fullScreenCover(isPresented:$fullPreview){workspace(fullScreen:true).padding(8).background(GlassBackdrop())}
            .onChange(of:fullPreview){_,value in game.localOutputPreview=value}
    }
    private var inBattle:Bool {game.campaign?.engine.state.battle != nil}
    private var targetName:String {game.campaign?.engine.state.units[game.selectedTarget]?.name ?? "选择目标"}
    private func workspace(fullScreen:Bool)->some View {
        VStack(spacing:8){
            HStack(spacing:8){
                Label("v0.28.0",systemImage:"leaf.fill").font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(GameTheme.primary)
                GlassChip(icon:game.externalConnected ? "tv.fill":"ipad.landscape",text:game.externalConnected ? "TV":"本机",tint:game.externalConnected ? .green:GameTheme.muted)
                if let c=game.campaign,!inBattle {
                    GlassChip(icon:"figure.walk.motion",text:"\(Int(ceil(c.movementRemaining)))/\(Int(ceil(c.movementCapacity)))")
                    GlassChip(icon:"bitcoinsign.circle.fill",text:"\(c.engine.state.units[c.selectedPlayerID]?.coins ?? 0)",tint:GameTheme.accent)
                }
                if let c=game.campaign {
                    GlassChip(icon:difficultyIcon(c.difficulty),text:c.difficulty.title,tint:difficultyTint(c.difficulty))
                }
                Spacer(minLength:0)
                Button{game.openTimer()}label:{Label("计时",systemImage:"timer")}
                ClassroomScoreboardButton(overlays:game.overlays){game.toggleScoreboard()}
                Button{game.openCharacterStudio()}label:{Label("形象",systemImage:"person.crop.circle.badge.plus")}.disabled(game.busy)
                Button{game.openPixelCharacterLab()}label:{Label("像素人物",systemImage:"square.grid.3x3.square")}.disabled(game.busy)
                Button{game.openGM()}label:{Label("GM",systemImage:"wand.and.stars")}.disabled(!game.ready || game.busy || game.campaign==nil)
                Button{fullPreview = !fullScreen}label:{Label(fullScreen ? "退出":"全屏",systemImage:fullScreen ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right")}
                Menu {
                    Button{game.openArchives()}label:{Label("档案 · 行程槽 · 历史",systemImage:"archivebox")}.disabled(game.busy)
                    Button{game.settings()}label:{Label("新地图",systemImage:"map")}.disabled(game.busy || inBattle)
                    Button{game.restore()}label:{Label("继续行程",systemImage:"arrow.clockwise.circle")}.disabled(game.busy || inBattle)
                    Button{game.operation(.save)}label:{Label("保存",systemImage:"square.and.arrow.down")}.disabled(!game.ready || game.busy)
                    Divider()
                    Menu {
                        ForEach(GameDifficulty.allCases,id:\.self){level in
                            Button{game.setDifficulty(level)}label:{Label(level.title+" · "+level.summary,systemImage:game.campaign?.difficulty==level ? "checkmark.circle.fill":difficultyIcon(level))}
                        }
                    }label:{Label("难度",systemImage:"gauge.with.dots.needle.67percent")}.disabled(game.busy || game.campaign==nil || inBattle || game.campaign?.isCompleted==true)
                    Button{game.award()}label:{Label("+10 金币",systemImage:"bitcoinsign.circle")}.disabled(game.busy || game.campaign==nil)
                    Button{game.openShortcutEditor()}label:{Label("快捷键",systemImage:"keyboard")}
                    Toggle(isOn:$game.liveMirrorPreferred){Label("教师画面用 GPU 实时显示",systemImage:"display.2")}
                    Button{game.openTeamConsole()}label:{Label("队伍与仓库",systemImage:"person.3")}.disabled(!game.ready || game.busy)
                    Button{game.operation(.route)}label:{Label("路线与结算",systemImage:"flag.checkered")}.disabled(!game.ready || game.busy)
                    Divider()
                    Button{if let id=game.selectedNode{game.operation(.editNode(id))}}label:{Label("编辑地点",systemImage:"pencil")}.disabled(game.selectedNode==nil || game.campaign?.isMoving==true || inBattle)
                    Button{if let id=game.selectedNode{game.project(.encounter(id))}}label:{Label("怪物预览",systemImage:"eye")}.disabled(game.selectedNode==nil || inBattle)
                }label:{Label("更多",systemImage:"ellipsis.circle")}
            }.buttonStyle(GlassIconButtonStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            if game.campaign != nil {
                HStack(spacing:8){
                    if inBattle {
                        Menu {
                            ForEach(battleTargets){u in Button(u.name){game.chooseBattleTarget(u.id)}}
                        }label:{Label(targetName,systemImage:"scope")}
                        .disabled(!game.ready || game.busy)
                        Menu {
                            ForEach([PartyAction.smallPotion,.largePotion,.shieldPotion,.revivalStone],id:\.rawValue){action in
                                Button(action.title){game.battle(action)}.disabled(!game.canUse(action))
                            }
                        }label:{Label("道具",systemImage:"cross.vial.fill")}.disabled(!game.ready || game.busy)
                        let paused=game.campaign?.engine.state.pauseReasons.contains(.manual)==true
                        Button{game.toggleBattlePause()}label:{Label(paused ? "继续":"暂停",systemImage:paused ? "play.fill":"pause.fill")}.disabled(game.busy)
                        Spacer(minLength:0)
                        Button{game.battle(.endTurn)}label:{Label("结束",systemImage:"forward.end.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(!game.canUse(.endTurn))
                    }else{
                        memberPicker
                        Button{selectingNode.toggle();if selectingNode{game.project(.exploration)}}label:{Label(selectingNode ? "完成":"选点",systemImage:selectingNode ? "checkmark.circle.fill":"mappin.and.ellipse")}
                            .buttonStyle(GlassIconButtonStyle(tint:selectingNode ? .orange:GameTheme.primary)).disabled(!game.ready || game.busy)
                        if selectingNode {
                            Button{if let id=game.selectedNode{game.operation(.editNode(id))}}label:{Label("修改",systemImage:"pencil")}.disabled(game.selectedNode==nil || game.campaign?.isMoving==true)
                        }else{
                            Button{game.operation(.interact)}label:{Label("交互",systemImage:"hand.tap.fill")}.disabled(!game.ready || game.busy || game.campaign?.isMoving==true)
                            Button{game.operation(.inventory)}label:{Label("行囊",systemImage:"bag.fill")}.disabled(!game.ready || game.busy || game.campaign?.isCompleted != false)
                            Button{game.operation(.shop)}label:{Label("商店",systemImage:"cart.fill")}.disabled(!game.ready || game.busy || game.campaign?.isCompleted != false)
                        }
                        Spacer(minLength:0)
                        Button{game.operation(.refill)}label:{Label("补充",systemImage:"bolt.fill")}.disabled(!game.ready || game.busy || game.campaign?.isMoving==true)
                        Button{game.operation(.pauseOrResume)}label:{Label(game.campaign?.isMoving==true ? "暂停":"出发",systemImage:game.campaign?.isMoving==true ? "pause.fill":"play.fill")}
                            .buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(!game.ready || game.busy)
                    }
                }.buttonStyle(GlassIconButtonStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            }
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
                }else if !inBattle,game.surface != .exploration {
                    VStack{HStack{Spacer();Button{game.project(.exploration)}label:{Label("地图",systemImage:"map")}.buttonStyle(GlassIconButtonStyle(tint:.white)).padding(12)};Spacer()}
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black).clipShape(RoundedRectangle(cornerRadius:18,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(.white.opacity(0.5),lineWidth:1))
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
            .onAppear{game.previewVisibility(previewID,visible:true)}
            .onDisappear{game.previewVisibility(previewID,visible:false);game.canvasHover(nil)}
    }
}
