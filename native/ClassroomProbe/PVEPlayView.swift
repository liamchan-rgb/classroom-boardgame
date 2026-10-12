import SwiftUI
import ClassroomGameCore

@MainActor
struct PVEPlayView:View {
    @ObservedObject var model:PVEAppSession
    @ObservedObject var teacher:TeacherSession
    @Environment(\.dismiss) private var dismiss
    @State private var showSetup = false
    @State private var showEditor = false
    @State private var showBook = false
    @State private var showEndBattle = false
    @State private var showHistory = false
    var body:some View {
        GeometryReader { geometry in
            VStack(alignment:.leading,spacing:12) {
                header
                Text(model.message).font(.callout).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                if let play = model.play, let board = try? play.engine.state.teacherBoard(catalog:play.engine.catalog) {
                    HStack(alignment:.top,spacing:14) {
                        playerRail(play:play).frame(width:geometry.size.width*0.19)
                        mapPanel(play:play,board:board).frame(maxWidth:.infinity,maxHeight:.infinity)
                        PVEActionPanel(model:model).frame(width:min(350,geometry.size.width*0.29))
                    }.frame(maxHeight:.infinity)
                    rewardBar(play:play)
                } else {
                    ContentUnavailableView("暂未打开PVE",systemImage:"map",description:Text(model.message)).frame(maxHeight:.infinity)
                }
            }.padding(20).background(GameTheme.background).foregroundStyle(GameTheme.ink).tint(GameTheme.primary)
        }
        .background(PVEKeyboardReceiver(model:model,teacher:teacher).frame(width:0,height:0))
        .sheet(isPresented:$showSetup,onDismiss:{ model.setModal(false) }) { PVESetupView(model:model) }
        .sheet(isPresented:$showEditor,onDismiss:{ model.setModal(false) }) { PVEResourceEditor(model:model) }
        .sheet(isPresented:$showHistory,onDismiss:{ model.setModal(false,reason:.history) }) { PVEHistoryView(model:model) }
        .sheet(isPresented:$showBook,onDismiss:{ teacher.concealNotes(); model.setBook(false) }) { PVEBookView(teacher:teacher,model:model) }
        .onChange(of:showEndBattle) { _,open in model.setModal(open) }
        .confirmationDialog("结束本场PVE，保留当前生命、资源和剩余行动点？",isPresented:$showEndBattle,titleVisibility:.visible) {
            Button("结束本场战斗") { model.apply(.finishBattle(winner:nil,byScore:false)) }
        }
    }
    private var header:some View {
        HStack(spacing:14) {
            Text("PVE课堂 · v0.8").font(.title2.bold())
            if let state = model.state {
                Text(state.phase.displayName).font(.headline)
                if let battle = state.battle {
                    Text("第\(battle.round)轮")
                    Text("\(Int(ceil(state.remainingSeconds)))秒").font(.title3.bold()).monospacedDigit()
                }
                if model.paused { Text("已暂停").foregroundStyle(GameTheme.accent) }
            }
            Spacer()
            Button(model.state?.pauseReasons.contains(.manual) == true ? "继续（空格）" : "暂停（空格）") { model.togglePause() }.buttonStyle(.borderedProminent)
            Button("绘本") { teacher.concealNotes(); model.setBook(true); showBook = true }.buttonStyle(.bordered)
            Menu {
                Button("创建新局") { model.setModal(true); showSetup = true }
                Button("调整资源 / 教师复活") { model.setModal(true); showEditor = true }
                Button("延长15秒") { model.extendTime() }
                Button("探索补足基础行动点") { model.apply(.refillExploration) }.disabled(model.state?.phase != .exploration)
                Button("最近战斗记录") { model.setModal(true,reason:.history); showHistory = true }
                Button("保存到本机") { model.save() }
                Button("恢复本机进度（暂停）") { model.restore() }
                Button("撤销完整一步（暂停）") { model.undo() }.disabled(model.play?.engine.history.isEmpty != false)
                if model.state?.battle != nil { Button("结束本场PVE") { showEndBattle = true } }
            } label:{ Label("教师操作",systemImage:"slider.horizontal.3") }.buttonStyle(.bordered)
            Button("返回") { dismiss() }.buttonStyle(.bordered)
        }
    }
    private func playerRail(play:PVEPlaySession) -> some View {
        GamePanel {
            VStack(alignment:.leading,spacing:8) {
                Text("玩家 · 奖励可多选").font(.headline)
                ScrollView {
                    VStack(spacing:9) {
                        ForEach(play.engine.state.players) { player in
                            let stats = try? GameRules.attributes(player,catalog:play.engine.catalog)
                            let current = play.engine.state.battle?.current == player.id
                            VStack(alignment:.leading,spacing:5) {
                                HStack {
                                    Button(player.name + (player.host ? " · 主持人" : "")) { model.selectPlayer(player.id) }
                                        .font(.headline).disabled(play.engine.state.battle != nil)
                                    Spacer(minLength:4)
                                    Button { model.toggleReward(player.id) } label:{
                                        Image(systemName:play.rewardIDs.contains(player.id) ? "checkmark.square.fill" : "square").font(.title2).frame(width:44,height:44)
                                    }.accessibilityLabel("奖励对象：\(player.name)")
                                }
                                Text("生命\(player.health)/\(stats?.maximumHealth ?? player.health) · 护盾\(player.shield)")
                                Text("AP\(player.ap) · 金币\(player.coins) · 分\(player.score)")
                                if current { Text("行动中").font(.caption.bold()).foregroundStyle(GameTheme.accent) }
                                if player.health == 0 { Text("已倒地").foregroundStyle(GameTheme.danger) }
                                if let battle = play.engine.state.battle, player.canActFromRound > battle.round, player.isAlive { Text("第\(player.canActFromRound)轮可行动").font(.caption) }
                            }.font(.callout).padding(10).background(GameTheme.background,in:RoundedRectangle(cornerRadius:12))
                                .overlay(RoundedRectangle(cornerRadius:12).stroke(current ? GameTheme.accent : .clear,lineWidth:2))
                        }
                    }
                }
            }
        }
    }
    private func mapPanel(play:PVEPlaySession,board:PublicGameSnapshot) -> some View {
        GamePanel {
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text("森林小地图").font(.headline)
                    Spacer()
                    Text("教师可看全图").font(.caption).foregroundStyle(GameTheme.muted)
                }
                if let scenario = model.scenario { Text(scenario.title).font(.callout.bold()).foregroundStyle(GameTheme.accent) }
                if let battle = play.engine.state.battle {
                    Text("队列：" + battle.queue.compactMap { play.engine.state.units[$0]?.name }.joined(separator:" → "))
                        .font(.callout).lineLimit(2)
                    Text("暂停原因：" + play.engine.state.pauseReasons.map(\.displayName).sorted().joined(separator:"、")).font(.caption)
                } else { Text("探索不自动计时；沿道路规划连续路径。").font(.callout) }
                PVEMapView(nodes:board.nodes,roads:board.roads,units:board.units,path:play.action == .move ? play.path : [],interactive:play.humanMayAct && !model.aiRunning,onNode:model.tapNode)
                    .frame(minHeight:280,maxHeight:.infinity)
                if play.engine.state.phase == .exploration, let actor = play.actor,
                   play.engine.state.units.values.contains(where:{ $0.kind == .monster && $0.isAlive && $0.nodeID == actor.nodeID }) {
                    Button("与当前位置敌人开战") { model.startHere() }.buttonStyle(.borderedProminent)
                }
                ScrollView(.horizontal) {
                    HStack(spacing:8) {
                        ForEach(board.units.filter { !$0.player }) { unit in
                            Button {
                                if play.action == .move { model.choose(.attack) }
                                if case .skill(let skillID) = play.action, let skill = try? play.engine.catalog.skill(skillID), [.enemiesAtNode,.alliesAtNode].contains(skill.target) { model.target(.node(unit.nodeID)) }
                                else { model.target(.unit(unit.id)) }
                            } label:{
                                VStack(alignment:.leading,spacing:4) {
                                    Text(unit.name).font(.headline)
                                    Text("地点\(unit.nodeID) · 生命\(unit.health)/\(unit.maximumHealth)")
                                    Text("护盾\(unit.shield) · AP\(unit.ap)" + (unit.health == 0 ? " · 已击败" : ""))
                                }.font(.caption).foregroundStyle(GameTheme.ink).padding(10).background(GameTheme.background,in:RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(height:86)
            }
        }
    }
    private func rewardBar(play:PVEPlaySession) -> some View {
        GamePanel {
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:4) {
                    Text("奖励对象：" + (play.rewardIDs.isEmpty ? "未选择" : play.selectedRewardNames)).font(.headline).lineLimit(2)
                    Text("与当前行动者独立；多人各得完整一份。").font(.caption).foregroundStyle(GameTheme.muted)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Group {
                    Button("金币＋10（G）") { model.award(ResourceReward(coins:10)) }
                    Button("AP＋1（A）") { model.award(ResourceReward(ap:1)) }
                    Button("积分＋2（S）") { model.award(ResourceReward(score:2)) }
                    Button("发练习补给") { model.award(ResourceReward(items:["smallPotion":2,"largePotion":1,"shieldPotion":1,"revivalStone":1])) }
                }.buttonStyle(.bordered).disabled(play.rewardIDs.isEmpty)
            }
        }
    }
}

@MainActor
private struct PVEActionPanel:View {
    @ObservedObject var model:PVEAppSession
    var body:some View {
        GamePanel {
            VStack(alignment:.leading,spacing:12) {
                Text("当前行动者：\(model.actor?.name ?? "等待教师处理")").font(.headline)
                if let play = model.play, play.humanMayAct {
                    ScrollView {
                        VStack(alignment:.leading,spacing:10) {
                            ForEach(play.options) { option in
                                Button { model.choose(option.action) } label:{
                                    VStack(alignment:.leading,spacing:3) {
                                        Text(option.title).font(.headline)
                                        Text(option.detail).font(.caption)
                                    }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
                                        .foregroundStyle(play.action == option.action ? .white : GameTheme.ink)
                                        .background(play.action == option.action ? GameTheme.primary : GameTheme.background,in:RoundedRectangle(cornerRadius:12))
                                }.buttonStyle(.plain)
                            }
                            if play.action == .move {
                                Text("路径：" + play.path.map { id in play.engine.state.map.nodes.first { $0.id == id }?.name ?? "地点\(id)" }.joined(separator:" → ")).font(.callout)
                                Button("清除路径") { model.clearPath() }.buttonStyle(.bordered)
                                if play.engine.state.battle == nil, let actor = play.actor {
                                    Text("同地点同行玩家").font(.headline)
                                    ForEach(play.engine.state.players.filter { $0.nodeID == actor.nodeID && $0.isAlive && $0.id != actor.id }) { unit in
                                        Button { model.toggleTravel(unit.id) } label:{ Label(unit.name,systemImage:play.travelIDs.contains(unit.id) ? "checkmark.circle.fill" : "circle") }
                                            .buttonStyle(.bordered)
                                    }
                                }
                            } else {
                                ForEach(Array(play.possibleTargets.enumerated()),id:\.offset) { _,target in
                                    Button { model.target(target) } label:{
                                        HStack { Text(label(target,play:play)); Spacer(); if play.target == target { Image(systemName:"checkmark.circle.fill") } }
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    Text(play.preview.message).font(.callout).foregroundStyle(play.preview.allowed ? GameTheme.muted : GameTheme.danger).fixedSize(horizontal:false,vertical:true)
                    Button("确认执行 · \(play.preview.cost)行动点") { model.perform() }.buttonStyle(.borderedProminent)
                        .frame(maxWidth:.infinity,minHeight:50).disabled(!play.preview.allowed || model.aiRunning)
                    if play.engine.state.battle != nil { Button("结束回合（E）") { model.endTurn() }.buttonStyle(.bordered).frame(maxWidth:.infinity,minHeight:44) }
                } else {
                    Text(model.aiRunning ? "怪物正在按技能优先级和选敌策略行动。" : "当前没有可行动玩家。可暂停、复活、调整资源或结束本场。")
                        .foregroundStyle(GameTheme.muted).frame(maxHeight:.infinity)
                }
            }
        }
    }
    private func label(_ target:ActionTarget,play:PVEPlaySession) -> String {
        switch target {
        case .unit(let id): return play.engine.state.units[id]?.name ?? "未知单位"
        case .node(let id): return play.engine.state.map.nodes.first { $0.id == id }?.name ?? "地点\(id)"
        }
    }
}
