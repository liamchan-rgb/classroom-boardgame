import SwiftUI
import ClassroomGameCore

@MainActor
final class RulesLabModel: ObservableObject {
    @Published private(set) var catalog: GameCatalog?
    @Published private(set) var result: RuleExampleResult?
    @Published private(set) var error: String?
    @Published var example = RuleExample.twenty
    @Published var showBefore = false
    @Published var showUndone = false
    init() {
        do { catalog = try GameCatalog.initial() }
        catch { self.error = error.localizedDescription }
    }
    func run() {
        guard let catalog else { return }
        do {
            result = try example.run(catalog: catalog)
            showBefore = false; showUndone = false; error = nil
        } catch { result = nil; self.error = error.localizedDescription }
    }
    func clear() { result = nil; showBefore = false; showUndone = false }
    var snapshot: PublicGameSnapshot? {
        guard let result else { return nil }
        return showBefore ? result.before : showUndone ? result.undone : result.after
    }
}

@MainActor
struct RulesLabView: View {
    @ObservedObject var session: TeacherSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var lab = RulesLabModel()
    @State private var projecting = false
    var body: some View {
        NavigationStack {
            TabView {
                examples.tabItem { Label("规则示例", systemImage: "dice") }
                if let catalog = lab.catalog {
                    CatalogView(catalog: catalog).tabItem { Label("初始资料", systemImage: "books.vertical") }
                }
            }
            .navigationTitle("阶段1 · 规则与资料")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .onChange(of: lab.example) { _, _ in lab.clear(); syncDisplay() }
        .onChange(of: projecting) { _, _ in syncDisplay() }
        .onChange(of: lab.showBefore) { _, _ in syncDisplay() }
        .onChange(of: lab.showUndone) { _, _ in syncDisplay() }
        .onDisappear { session.display.ruleExample = nil }
    }
    private var examples: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("每个示例独立运行，可重复查看。这里的角色与掷骰是示例，正式PVE操作界面将在下一阶段接入。")
                    .foregroundStyle(.secondary)
                Picker("选择示例", selection: $lab.example) {
                    ForEach(RuleExample.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                Text(lab.example.explanation).font(.body)
                HStack {
                    Button("运行示例") { lab.run(); syncDisplay() }.buttonStyle(.borderedProminent)
                        .disabled(lab.catalog == nil)
                    Toggle("将公开结果显示到电视", isOn: $projecting).fixedSize()
                }
                if let error = lab.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if let result = lab.result {
                    Label(result.passed ? "本例检查通过" : "本例存在异常", systemImage: result.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title3.bold()).foregroundStyle(result.passed ? .green : .red)
                    ForEach(result.checks) { check in
                        Label(check.title, systemImage: check.passed ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(check.passed ? Color.primary : .red)
                    }
                    HStack {
                        Toggle("查看行动前", isOn: $lab.showBefore).fixedSize()
                        if result.undone != nil {
                            Toggle("查看整步撤销后", isOn: $lab.showUndone).fixedSize().disabled(lab.showBefore)
                        }
                    }
                    Text(lab.showBefore ? "行动前" : lab.showUndone ? "撤销后" : "行动后").font(.headline)
                    if let snapshot = lab.snapshot {
                        GameExamplePublicView(snapshot: snapshot).frame(minHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func syncDisplay() { session.display.ruleExample = projecting ? lab.snapshot : nil }
}

@MainActor
struct GameExamplePublicView: View {
    let snapshot: PublicGameSnapshot
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("课堂桌游 · 规则示例", systemImage: "dice.fill").font(.title2.bold())
                    Spacer()
                    Text(snapshot.phase.chineseName)
                }
                if snapshot.round > 0 {
                    Text("第\(snapshot.round)轮 · 当前：\(snapshot.currentName ?? "等待") · 剩余\(Int(ceil(snapshot.remainingSeconds)))秒")
                    Text("队列：" + snapshot.queue.joined(separator: " → ")).font(.callout)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                    ForEach(snapshot.units) { unit in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(unit.name + (unit.current ? " · 当前" : "")).font(.headline)
                            Text("生命 \(unit.health)/\(unit.maximumHealth) · 护盾 \(unit.shield)")
                            Text("行动点 \(unit.ap) · 地点 \(unit.nodeID)")
                            if unit.player { Text("金币 \(unit.coins) · 积分 \(unit.score)") }
                            Text(unit.health == 0 ? (unit.player ? "已倒地" : "已击败") : unit.team)
                        }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).background(.white.opacity(unit.current ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                ForEach(Array(snapshot.dice.enumerated()), id: \.offset) { _, roll in
                    Text("\(roll.formula.label)：" + roll.values.map(String.init).joined(separator: "、") + (roll.naturalTwenty ? " · 自然20！" : ""))
                        .font(.title3.bold())
                }
            }.padding(24)
        }.foregroundStyle(.white).background(Color(red: 0.02, green: 0.24, blue: 0.22))
    }
}

private extension GamePhase {
    var chineseName: String {
        switch self {
        case .preparation: return "准备"
        case .exploration: return "探索"
        case .pve: return "PVE战斗"
        case .teamPvp: return "队伍PVP"
        case .freeForAll: return "个人混战"
        case .settlement: return "结算"
        }
    }
}

@MainActor
private struct CatalogView: View {
    let catalog: GameCatalog
    var body: some View {
        List {
            Section("4种职业") {
                ForEach(catalog.classes) { definition in
                    DisclosureGroup(definition.name) {
                        Text(attributes(definition.attributes))
                        ForEach(definition.skills, id: \.self) { id in
                            if let skill = catalog.skills.first(where: { $0.id == id }) { SkillRow(skill: skill) }
                        }
                    }
                }
            }
            Section("18种物品") {
                ForEach(catalog.items) { item in
                    DisclosureGroup(item.name) {
                        Text(item.purchasePrice.map { "买入\($0)金币 · 卖出\(item.sellPrice)金币" } ?? "稀有掉落 · 卖出\(item.sellPrice)金币")
                        if let attack = item.attack { Text("攻击 \(attack.dice.label) · 射程\(attack.range)") }
                        if item.kind == .equipment { Text(bonus(item.attributes)) }
                        if item.heal > 0 { Text("恢复\(item.heal)生命 · 消耗1行动点 · 射程\(item.range)") }
                        if item.shield > 0 { Text("获得\(item.shield)护盾 · 消耗1行动点 · 射程\(item.range)") }
                        if item.kind == .revivalStone { Text("救援消耗1枚复活石和2行动点；同地点队友恢复一半生命，向上取整。") }
                    }
                }
            }
            Section("2种套装 · 两件与三件效果累加") {
                ForEach(catalog.sets) { set in
                    DisclosureGroup(set.name) {
                        Text(set.items.compactMap { id in catalog.items.first { $0.id == id }?.name }.joined(separator: "、"))
                        Text("两件：" + bonus(set.twoPieces))
                        Text("三件：" + bonus(set.threePieces))
                        if let skill = catalog.skills.first(where: { $0.id == set.skill }) { SkillRow(skill: skill) }
                    }
                }
            }
            Section("6种怪物 · 各项掉落独立判定") {
                ForEach(catalog.monsters) { monster in
                    DisclosureGroup(monster.name + (monster.boss ? " · Boss" : "")) {
                        Text(attributes(monster.attributes) + " · 初始护盾\(monster.shield)")
                        Text("攻击 \(monster.attack.dice.label) · 射程\(monster.attack.range) · 击败积分\(monster.score)")
                        ForEach(monster.skills, id: \.self) { id in
                            if let skill = catalog.skills.first(where: { $0.id == id }) { SkillRow(skill: skill) }
                        }
                        ForEach(Array(monster.drops.enumerated()), id: \.offset) { _, drop in
                            Text("\(drop.percent)%：" + (drop.itemID.flatMap { id in catalog.items.first { $0.id == id }?.name }.map { "\($0) ×\(drop.count)" } ?? "\(drop.coins)金币"))
                        }
                    }
                }
            }
        }
    }
    private func attributes(_ value: Attributes) -> String {
        "生命上限\(value.maximumHealth) · 基础行动点\(value.baseAP) · 行动点上限\(value.maximumAP)"
    }
    private func bonus(_ value: Attributes) -> String {
        var parts: [String] = []
        if value.maximumHealth != 0 { parts.append("生命上限＋\(value.maximumHealth)") }
        if value.damage != 0 { parts.append("伤害＋\(value.damage)") }
        if value.baseAP != 0 { parts.append("基础行动点＋\(value.baseAP)") }
        if value.maximumAP != 0 { parts.append("行动点上限＋\(value.maximumAP)") }
        if value.range != 0 { parts.append("射程＋\(value.range)") }
        return parts.isEmpty ? "无额外属性" : parts.joined(separator: " · ")
    }
}

@MainActor
private struct SkillRow: View {
    let skill: SkillDefinition
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(skill.name).font(.headline)
            Text("\(skill.cost)行动点 · 射程\(skill.range) · " + target + " · " + stage + (skill.uses.map { " · 每战\($0)次" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(skill.effects.enumerated()), id: \.offset) { _, effect in
                Text((effect.scope == .caster ? "自身：" : "目标：") + effectText(effect)).font(.callout)
            }
            if skill.oncePerTurn { Text("怪物恢复技能同回合最多1次；需满足施放条件。 ").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
    private var target: String {
        switch skill.target {
        case .selfOnly: return "自身"
        case .enemy: return "单体敌人"
        case .ally: return "单体队友"
        case .enemiesAtNode: return "地点内敌人"
        case .alliesAtNode: return "地点内己方（包含自身）"
        }
    }
    private var stage: String {
        switch skill.stage { case .battle: return "战斗"; case .exploration: return "探索"; case .both: return "战斗或探索" }
    }
    private func effectText(_ effect: SkillEffect) -> String {
        switch effect.kind {
        case .damage: return "伤害 " + (effect.dice?.label ?? "") + (effect.amount == 0 ? "" : "＋\(effect.amount)")
        case .heal: return "恢复\(effect.amount)生命"
        case .shield: return "获得\(effect.amount)护盾（取较高值）"
        case .damageBuff: return "伤害＋\(effect.amount)，持续\(effect.rounds)轮"
        }
    }
}
