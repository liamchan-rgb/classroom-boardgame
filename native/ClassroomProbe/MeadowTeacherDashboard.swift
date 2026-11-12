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
        workspace(fullScreen:false).padding(8).background(GameTheme.background)
            .fullScreenCover(isPresented:$fullPreview){workspace(fullScreen:true).background(GameTheme.background)}
            .onChange(of:fullPreview){_,value in game.localOutputPreview=value}
    }
    private var inBattle:Bool {game.campaign?.engine.state.battle != nil}
    private var targetName:String {game.campaign?.engine.state.units[game.selectedTarget]?.name ?? "选择目标"}
    private func workspace(fullScreen:Bool)->some View {
        VStack(spacing:0){
            HStack(spacing:10){
                Text("教师游戏 · v0.20.0").font(.headline)
                Text(game.externalConnected ? "电视已连接":"本机预览").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength:0)
                Button{game.openCharacterStudio()}label:{Label("人物自定义",systemImage:"person.crop.circle.badge.plus")}.disabled(game.busy)
                Button("GM"){game.openGM()}.disabled(!game.ready || game.busy || game.campaign==nil)
                Button(fullScreen ? "退出全屏":"全屏"){fullPreview = !fullScreen}
                Menu {
                    Button("人物档案 / 行程槽 / 历史 / 老师参战"){game.openArchives()}.disabled(game.busy)
                    Button("随机地图与新行程"){game.settings()}.disabled(game.busy || inBattle)
                    Button("继续已保存行程"){game.restore()}.disabled(game.busy || inBattle)
                    Button("保存行程"){game.operation(.save)}.disabled(!game.ready || game.busy)
                    Divider()
                    Button("奖励10金币"){game.award()}.disabled(game.busy || game.campaign==nil)
                    Button("队伍与仓库"){game.openTeamConsole()}.disabled(!game.ready || game.busy)
                    Button("路线与结算"){game.operation(.route)}.disabled(!game.ready || game.busy)
                    Divider()
                    Button("编辑选中地点"){if let id=game.selectedNode{game.operation(.editNode(id))}}.disabled(game.selectedNode==nil || game.campaign?.travel != nil || inBattle)
                    Button("投放选中怪物预览"){if let id=game.selectedNode{game.project(.encounter(id))}}.disabled(game.selectedNode==nil || inBattle)
                }label:{Label("管理",systemImage:"slider.horizontal.3")}
            }.frame(height:44).padding(.horizontal,12)
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
                        }label:{Label("道具",systemImage:"bag")}.disabled(!game.ready || game.busy)
                        Button(game.campaign?.engine.state.pauseReasons.contains(.manual)==true ? "继续战斗":"暂停战斗"){game.toggleBattlePause()}.disabled(game.busy)
                        Spacer(minLength:0)
                        Button("结束行动"){game.battle(.endTurn)}.disabled(!game.canUse(.endTurn))
                    }else{
                        Menu {
                            ForEach(game.campaign?.engine.state.players ?? []){u in Button(u.name){game.select(u.id)}}
                        }label:{Label(game.campaign?.engine.state.units[game.campaign?.selectedPlayerID ?? ""]?.name ?? "成员",systemImage:"person")}
                        .disabled(!game.ready || game.busy)
                        Button(selectingNode ? "完成选点":"编辑地点"){selectingNode.toggle();if selectingNode{game.project(.exploration)}}
                            .tint(selectingNode ? .orange:.accentColor).disabled(!game.ready || game.busy)
                        if selectingNode {
                            Button("修改内容"){if let id=game.selectedNode{game.operation(.editNode(id))}}.disabled(game.selectedNode==nil || game.campaign?.travel != nil)
                        }else{
                            Button("交互地点"){game.operation(.interact)}.disabled(!game.ready || game.busy || game.campaign?.isMoving==true)
                            Button("行囊"){game.operation(.inventory)}.disabled(!game.ready || game.campaign?.canManageInventory != true)
                        }
                        Spacer(minLength:0)
                        Button("补充移动"){game.operation(.refill)}.disabled(!game.ready || game.busy || game.campaign?.isMoving==true)
                        Button("暂停 / 继续"){game.operation(.pauseOrResume)}.disabled(!game.ready || game.busy)
                    }
                }.font(.system(size:15,weight:.semibold)).buttonStyle(.bordered).lineLimit(1).padding(.horizontal,10).frame(height:48)
            }
            ZStack {
                if game.renderer != nil && (fullScreen || !fullPreview) {
                    TeacherGamePreview(game:game,selectingNode:selectingNode)
                }else if game.campaign==nil {
                    VStack(spacing:20){
                        Text("准备林间旅程").font(.title.bold())
                        Button("随机地图与新行程"){game.settings()}
                        Button("继续已保存行程"){game.restore()}
                        Button("人物自定义"){game.openCharacterStudio()}
                    }.buttonStyle(.borderedProminent).foregroundStyle(.white)
                }else{Color.black}
                if !inBattle,game.surface != .exploration {
                    VStack{HStack{Spacer();Button("返回探索地图"){game.project(.exploration)}.buttonStyle(.borderedProminent).padding(12)};Spacer()}
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black).clipped()
            HStack(spacing:10){
                Text(selectingNode && !inBattle ? "点建筑选取地点，再点「修改内容」":"\(game.message)").lineLimit(1).truncationMode(.tail)
                Spacer(minLength:0)
                if inBattle {Text("直接点画面内技能 · 点角色选目标")}
                else if let c=game.campaign {Text("移动 \(Int(ceil(c.movementRemaining)))/\(Int(ceil(c.movementCapacity)))")}
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,12).frame(height:28)
        }.foregroundStyle(GameTheme.ink).background(GameTheme.background,in:RoundedRectangle(cornerRadius:14))
            .overlay{RoundedRectangle(cornerRadius:14).stroke(GameTheme.ink.opacity(0.18))}.clipShape(RoundedRectangle(cornerRadius:14))
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
