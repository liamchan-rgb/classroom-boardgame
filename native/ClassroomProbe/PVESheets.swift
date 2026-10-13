import SwiftUI
import UniformTypeIdentifiers
import ClassroomGameCore

@MainActor
struct PVESetupView:View {
    @ObservedObject var model:PVEAppSession
    @Environment(\.dismiss) private var dismiss
    @State private var count = 2
    @State private var includeHost = false
    @State private var names = (1...6).map { "学生\($0)" } + ["主持人"]
    @State private var classes = ["adventurer","spellblade","ranger","dragonKnight","adventurer","spellblade","dragonKnight"]
    @State private var scenario = PVEScenario.forest
    var body:some View {
        NavigationStack {
            Form {
                Section("玩家") {
                    Stepper("学生人数：\(count)",value:$count,in:1...6)
                    Toggle("主持人也参战",isOn:$includeHost)
                    ForEach(0..<count,id:\.self) { index in playerFields(index) }
                    if includeHost { playerFields(6) }
                }
                Section("小地图 / 验证剧本") {
                    Picker("剧本",selection:$scenario) { ForEach(PVEScenario.allCases) { Text($0.title).tag($0) } }
                    Text(scenario.detail).font(.callout)
                    if scenario == .monsterTwenty && count + (includeHost ? 1 : 0) < 2 { Text("至少需要2个玩家角色。").foregroundStyle(GameTheme.danger) }
                }
                Section {
                    Text("新局重置玩家资产、积分与地图。当前PVE会先备份到本机；绘本与原阶段0备份保留。")
                    Text(model.message).font(.callout)
                    Button("创建新局") { create() }.disabled(scenario == .monsterTwenty && count + (includeHost ? 1 : 0) < 2)
                }
            }.navigationTitle("建立PVE课堂")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
                .onChange(of:scenario) { _,value in if value == .playerTwenty { classes[0] = "dragonKnight" } }
        }.tint(GameTheme.primary)
    }
    private func playerFields(_ index:Int) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(index == 6 ? "主持人" : "学生\(index+1)").font(.headline)
            TextField("姓名",text:$names[index])
            Picker("职业",selection:$classes[index]) {
                ForEach(model.catalog?.classes ?? []) { definition in Text("\(definition.name) · 生命\(definition.attributes.maximumHealth)").tag(definition.id) }
            }.disabled(index == 0 && scenario == .playerTwenty)
        }
    }
    private func create() {
        var players = (0..<count).map { PlayerSetup(id:"p\($0+1)",name:names[$0],classID:classes[$0]) }
        if includeHost { players.append(PlayerSetup(id:"p7",name:names[6],classID:classes[6],host:true)) }
        if model.newGame(players:players,scenario:scenario) { dismiss() }
    }
}

@MainActor
struct PVEResourceEditor:View {
    @ObservedObject var model:PVEAppSession
    @Environment(\.dismiss) private var dismiss
    @State private var unitID = ""
    @State private var health = ""
    @State private var shield = ""
    @State private var ap = ""
    @State private var coins = ""
    @State private var score = ""
    @State private var error = ""
    var body:some View {
        NavigationStack {
            Form {
                Section("对象") {
                    Picker("玩家或怪物",selection:$unitID) {
                        ForEach((model.state?.units.values.sorted { $0.id < $1.id }) ?? []) { unit in Text(unit.name).tag(unit.id) }
                    }
                }
                Section("本局当前资源") {
                    field("生命",text:$health)
                    field("护盾",text:$shield)
                    field("行动点",text:$ap)
                    field("金币",text:$coins)
                    field("积分（可负数）",text:$score)
                    if let unit = model.state?.units[unitID], let catalog = model.catalog, let stats = try? GameRules.attributes(unit,catalog:catalog) {
                        Text("生命0…\(stats.maximumHealth)，行动点0…\(stats.maximumAP)；倒地清除护盾与临时增益。")
                    }
                    Button("应用修改") { apply() }
                    if let unit = model.state?.units[unitID], unit.kind == .player, !unit.isAlive {
                        Button("教师复活（半生命，不耗道具、不加分）") { model.apply(.revive(unitID)); sync() }
                    }
                }
                Section {
                    Text("面板期间已叠加暂停；调整只影响本局，教师将怪物生命改为0不会自动发击杀分或掉落。")
                    if !error.isEmpty { Text(error).foregroundStyle(GameTheme.danger) }
                    Text(model.message).font(.callout)
                }
            }.navigationTitle("教师资源调整")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
                .onAppear { unitID = model.actor?.id ?? model.state?.players.first?.id ?? ""; sync() }
                .onChange(of:unitID) { _,_ in sync() }
                .onChange(of:health) { _,value in if Int(value) == 0 { shield = "0" } }
        }.tint(GameTheme.primary)
    }
    private func field(_ name:String,text:Binding<String>) -> some View { HStack { Text(name); TextField(name,text:text).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation) } }
    private func sync() {
        guard let unit = model.state?.units[unitID] else { return }
        health = String(unit.health); shield = String(unit.shield); ap = String(unit.ap); coins = String(unit.coins); score = String(unit.score); error = ""
    }
    private func apply() {
        guard let h = Int(health), let s = Int(shield), let a = Int(ap), let c = Int(coins), let p = Int(score) else { error = "请输入有效整数。"; return }
        model.apply(.editResources(unit:unitID,value:ResourcePatch(health:h,shield:h == 0 ? 0 : s,ap:a,coins:c,score:p)))
        sync()
    }
}

@MainActor
struct PVEBookView:View {
    @ObservedObject var teacher:TeacherSession
    @ObservedObject var model:PVEAppSession
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @FocusState private var focused:Bool
    var body:some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Button("上一页") { teacher.turnPage(-1) }
                    Text("\(teacher.state.pageCount == 0 ? 0 : teacher.state.pageIndex+1) / \(teacher.state.pageCount)")
                    Button("下一页") { teacher.turnPage(1) }
                    Spacer()
                    Button("内置PPTX") { teacher.loadSample() }
                    Button("导入PPTX") { focused = false; importing = true }
                }.buttonStyle(.bordered)
                HStack(alignment:.top,spacing:18) {
                    PVEPagePreview(display:teacher.display).frame(maxWidth:.infinity,maxHeight:.infinity)
                    VStack(alignment:.leading,spacing:10) {
                        Toggle("教师备注",isOn:$teacher.showNotes).disabled(teacher.connectionCount == 0 || teacher.state.pageCount == 0)
                        if teacher.showNotes && teacher.connectionCount > 0 {
                            TextEditor(text:Binding(get:{ teacher.currentNote },set:{ teacher.editNote($0) })).focused($focused)
                        } else { Text("确认电视显示独立公开页面后，可开启教师备注。").foregroundStyle(.secondary) }
                    }.frame(width:300)
                }
                Text("PVE已因绘本暂停；返回后保留其他暂停原因和剩余时间。").font(.callout)
                Text(teacher.message).font(.caption)
                if let play = model.play {
                    HStack {
                        Text("奖励对象：" + play.selectedRewardNames).lineLimit(1)
                        Button("金币＋10（G）") { model.award(ResourceReward(coins:10)) }.disabled(play.rewardIDs.isEmpty)
                        Button("暂停/继续（空格）") { model.togglePause() }
                    }.buttonStyle(.bordered)
                }
            }.padding(20).navigationTitle("课堂绘本")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("回游戏") { focused = false; teacher.concealNotes(); dismiss() } } }
                .onChange(of:focused) { _,value in teacher.notesFocus(value) }
                .onChange(of:teacher.showNotes) { _,visible in if !visible { focused = false } }
                .onDisappear { teacher.concealNotes() }
                .fileImporter(isPresented:$importing,allowedContentTypes:[UTType(filenameExtension:"pptx") ?? .data]) { result in
                    switch result { case .success(let url):teacher.loadPPTX(url); case .failure(let error):teacher.fileSelectionFailed(error) }
                }
        }.tint(GameTheme.primary)
    }
}
private struct PVEPagePreview:View {
    @ObservedObject var display:PublicDisplayModel
    var body:some View {
        if let image = display.image { Image(uiImage:image).resizable().scaledToFit() }
        else { ContentUnavailableView("尚未导入绘本",systemImage:"book.closed",description:Text("可加载内置PPTX或选择本地文件。")) }
    }
}

@MainActor
struct PVEHistoryView:View {
    @ObservedObject var model:PVEAppSession
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                if let play = model.play {
                    ForEach(Array(play.engine.history.reversed())) { receipt in
                        VStack(alignment:.leading,spacing:8) {
                            Text("第\(receipt.sequence)步").font(.headline)
                            DisclosureGroup("资源前后值、费用与原事件") {
                                ForEach(receipt.after.units.keys.sorted(),id:\.self) { id in
                                    if let before = receipt.before.units[id], let after = receipt.after.units[id], before != after {
                                        Text("\(after.name)：生命\(before.health)→\(after.health)，护盾\(before.shield)→\(after.shield)，AP\(before.ap)→\(after.ap)，金币\(before.coins)→\(after.coins)，积分\(before.score)→\(after.score)")
                                    }
                                }
                                ForEach(Array(receipt.events.enumerated()),id:\.offset) { _,event in
                                    Text("\(event.kind)：\(event.amount) · \(event.detail)").font(.caption)
                                }
                            }
                            ForEach(Array(OperationSummary.lines(receipt,catalog:play.engine.catalog,publicOnly:false).enumerated()),id:\.offset) { _,line in Text(line) }
                            ForEach(Array(receipt.dice.enumerated()),id:\.offset) { _,dice in
                                Text(dice.formula.label + "：" + dice.values.map(String.init).joined(separator:"、") + (dice.naturalTwenty ? " · 自然20" : "")).font(.callout.bold())
                            }
                        }.padding(.vertical,6)
                    }
                }
            }.navigationTitle("整场游戏 · 只读记录")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
