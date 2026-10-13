import Foundation

public struct PlayerSetup: Equatable, Identifiable {
    public var id: String
    public var name: String
    public var classID: String
    public var host: Bool
    public init(id: String, name: String, classID: String, host: Bool = false) {
        self.id = id; self.name = name; self.classID = classID; self.host = host
    }
}
public enum PVEScenario: String, CaseIterable, Identifiable {
    case forest, playerTwenty, monsterTwenty
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .forest: return "森林小地图"
        case .playerTwenty: return "验证：龙骑士自然20群攻"
        case .monsterTwenty: return "验证：魔龙自然20群体倒地"
        }
    }
    public var detail: String {
        switch self {
        case .forest: return "森林有史莱姆、弓手和洞穴巨魔。到达敌人地点自动开战，可在战斗中激活新敌人。"
        case .playerTwenty: return "首位角色使用龙骑士，生命5/32。路口有史莱姆、弓手、巨魔；下一次伤害D20固定20，其余骰子正常。"
        case .monsterTwenty: return "至少2个角色在路口与魔龙开战，魔龙先行动，下一次伤害D20固定20；暂停后可由教师复活或调整。"
        }
    }
}
public enum PVEGameFactory {
    public static func make(players: [PlayerSetup], scenario: PVEScenario = .forest, seed: UInt64, catalog: GameCatalog) throws -> GameState {
        let students = players.filter { !$0.host }, hosts = players.filter(\.host)
        guard (1...6).contains(students.count), hosts.count <= 1, Set(players.map(\.id)).count == players.count,
              players.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40 }) else {
            throw GameError("请输入1—6名学生、最多1名主持人和有效姓名。")
        }
        if scenario == .monsterTwenty && players.count < 2 { throw GameError("群体倒地验证需要至少2个玩家角色。") }
        let map = GameMap(nodes: [
            MapNode(id: 1, name: "营地", kind: .start, x: 0.10, y: 0.55),
            MapNode(id: 2, name: "森林路口", kind: .combat, x: 0.36, y: 0.55),
            MapNode(id: 3, name: "弓手哨点", kind: .combat, x: 0.62, y: 0.26),
            MapNode(id: 4, name: "古树补给", kind: .reward, x: 0.62, y: 0.78, reward: NodeReward()),
            MapNode(id: 5, name: "巨魔洞穴", kind: .boss, x: 0.90, y: 0.55)],
            roads: [MapRoad(1,2), MapRoad(2,3), MapRoad(2,4), MapRoad(3,5), MapRoad(4,5)], seed: seed, revealed: [1])
        var units: [String: GameUnit] = [:]
        let ordered = players.sorted { $0.id < $1.id }
        for (index, setup) in ordered.enumerated() {
            let classID = scenario == .playerTwenty && index == 0 ? "dragonKnight" : setup.classID
            units[setup.id] = try GameFactory.player(id: setup.id, name: setup.name, classID: classID, teamID: "blue", nodeID: scenario == .monsterTwenty ? 2 : 1, host: setup.host, catalog: catalog)
        }
        let enemies: [(String, String, Int)]
        switch scenario {
        case .forest: enemies = [("m1","slime",2),("m2","goblinArcher",3),("m3","caveTroll",5)]
        case .playerTwenty: enemies = [("m1","slime",2),("m2","goblinArcher",2),("m3","caveTroll",2)]
        case .monsterTwenty: enemies = [("m1","ruinDragon",2)]
        }
        for (id, template, node) in enemies { units[id] = try GameFactory.monster(id: id, templateID: template, nodeID: node, catalog: catalog) }
        var random = RandomState(seed: seed)
        if scenario != .forest {
            random.damageD20Override = 20
            random.scripted = ordered.indices.map { 19 - $0 } + enemies.indices.map { 10 - $0 }
            if scenario == .playerTwenty { units[ordered[0].id]?.health = 5 }
            else { random.scripted = ordered.indices.map { 10 - $0 } + [20] }
        }
        var state = GameState(units: units, teams: [GameTeam(id: "blue", name: "蓝队")], map: map, random: random)
        state.pauseReasons = []
        state.verificationScenario = scenario == .forest ? nil : scenario.rawValue
        if scenario == .monsterTwenty { state.map.revealed.insert(2) }
        try state.validate(catalog: catalog)
        return state
    }
}

public enum PlayerAction: Equatable, Hashable {
    case move, attack, skill(String), item(String), rescue
}
public struct PlayActionOption: Identifiable {
    public var action: PlayerAction
    public var title: String
    public var detail: String
    public var id: PlayerAction { action }
}

/// UI-independent interaction state. Selections never touch the game archive.
public final class PVEPlaySession {
    public let engine: GameEngine
    public private(set) var selectedPlayerID: String
    public private(set) var rewardIDs: Set<String>
    public private(set) var travelIDs: Set<String>
    public private(set) var action: PlayerAction = .move
    public private(set) var target: ActionTarget?
    public private(set) var path: [Int] = []
    private var pendingActorID: String?
    private var pendingBattle: Bool?
    public init(engine: GameEngine) {
        self.engine = engine
        let id = engine.state.players.first!.id
        selectedPlayerID = id; rewardIDs = [id]; travelIDs = [id]
        synchronize()
    }
    public var actor: GameUnit? {
        if let battle = engine.state.battle { return battle.current.flatMap { engine.state.units[$0] } }
        return engine.state.units[selectedPlayerID]
    }
    public var humanMayAct: Bool { actor?.kind == .player && actor?.isAlive == true }
    public var selectedRewardNames: String { engine.state.players.filter { rewardIDs.contains($0.id) }.map(\.name).joined(separator: "、") }
    public func selectPlayer(_ id: String) {
        guard engine.state.units[id]?.kind == .player else { return }
        selectedPlayerID = id
        if engine.state.battle == nil { travelIDs = [id]; action = .move; target = nil; pendingActorID = nil }
        synchronize()
    }
    public func shortcutPlayer(_ number: Int) -> GameUnit? {
        if number == 7 { return engine.state.players.first(where: \.host) }
        let students = engine.state.players.filter { !$0.host }
        guard (1...6).contains(number), students.indices.contains(number - 1) else { return nil }
        return students[number - 1]
    }
    public func selectReward(_ id: String) { if engine.state.units[id]?.kind == .player { rewardIDs = [id] } }
    public func toggleReward(_ id: String) {
        guard engine.state.units[id]?.kind == .player else { return }
        if !rewardIDs.insert(id).inserted { rewardIDs.remove(id) }
    }
    public func toggleTravel(_ id: String) {
        guard engine.state.battle == nil, let actor, let unit = engine.state.units[id], unit.kind == .player,
              unit.nodeID == actor.nodeID, unit.isAlive, id != actor.id else { return }
        if !travelIDs.insert(id).inserted { travelIDs.remove(id) }
    }
    public func choose(_ value: PlayerAction) { action = value; target = nil; path = actor.map { [$0.nodeID] } ?? []; pendingActorID = actor?.id }
    public func selectTarget(_ value: ActionTarget) { target = value }
    public func tapNode(_ id: Int) throws {
        guard let actor, actor.kind == .player else { throw GameError("当前没有可操作的玩家。") }
        if action == .move {
            if path.isEmpty { path = [actor.nodeID] }
            if path.last == id { return }
            if path.count >= 2 && path[path.count - 2] == id { path.removeLast(); return }
            guard let last = path.last, engine.state.map.neighbors(last).contains(id) else { throw GameError("请按相连道路选择连续路径。") }
            path.append(id)
        } else { target = .node(id) }
    }
    public func clearPath() { path = actor.map { [$0.nodeID] } ?? [] }
    public var command: GameCommand? {
        guard let actor, actor.kind == .player, actor.id == pendingActorID else { return nil }
        switch action {
        case .move: return .move(actors: engine.state.battle == nil ? travelIDs.sorted() : [actor.id], path: path)
        case .attack: if case .unit(let target) = target { return .attack(actor: actor.id, target: target) }
        case .skill(let id): return .cast(actor: actor.id, skill: id, target: target)
        case .item(let id): if case .unit(let target) = target { return .useItem(actor: actor.id, item: id, target: target) }
        case .rescue: if case .unit(let target) = target { return .rescue(actor: actor.id, target: target) }
        }
        return nil
    }
    public var preview: ActionPreview {
        guard humanMayAct else { return ActionPreview(allowed: false, message: "等待玩家回合；怪物未暂停时会自动行动。") }
        guard let command else { return ActionPreview(allowed: false, message: "请选择行动目标。") }
        return engine.preview(command)
    }
    public var options: [PlayActionOption] {
        guard let actor, actor.kind == .player else { return [] }
        var rows = [PlayActionOption(action: .move, title: "移动", detail: "每条道路1行动点")]
        if engine.state.battle != nil, let attack = try? GameRules.attack(actor, catalog: engine.catalog) {
            rows.append(PlayActionOption(action: .attack, title: "普攻", detail: "1行动点 · \(attack.dice.label) · 射程\(attack.range)"))
        }
        for id in (try? GameRules.skills(actor, catalog: engine.catalog)) ?? [] {
            guard let skill = try? engine.catalog.skill(id) else { continue }
            let used = actor.skillUses[id] ?? 0
            rows.append(PlayActionOption(action: .skill(id), title: skill.name, detail: "\(skill.cost)行动点 · 射程\(skill.range)" + (skill.uses.map { " · 剩\(max(0,$0-used))次" } ?? "")))
        }
        for item in engine.catalog.items where item.kind == .consumable && (actor.inventory[item.id] ?? 0) > 0 {
            rows.append(PlayActionOption(action: .item(item.id), title: item.name, detail: "1行动点 · 射程\(item.range) · 个人\(actor.inventory[item.id]!)份"))
        }
        rows.append(PlayActionOption(action: .rescue, title: "救援", detail: "2行动点＋1复活石 · 同地点"))
        return rows
    }
    public var possibleTargets: [ActionTarget] {
        guard let actor else { return [] }
        let units = engine.state.units.values.sorted { $0.id < $1.id }
        switch action {
        case .move: return []
        case .attack: return units.filter { $0.isAlive && GameRules.enemies(actor,$0,in:engine.state) }.map { .unit($0.id) }
        case .skill(let id):
            guard let skill = try? engine.catalog.skill(id) else { return [] }
            switch skill.target {
            case .selfOnly: return []
            case .enemy: return units.filter { $0.isAlive && GameRules.enemies(actor,$0,in:engine.state) }.map { .unit($0.id) }
            case .ally: return units.filter { $0.isAlive && $0.id != actor.id && GameRules.allies(actor,$0,in:engine.state) }.map { .unit($0.id) }
            case .enemiesAtNode, .alliesAtNode: return engine.state.map.nodes.map { .node($0.id) }
            }
        case .item: return units.filter { $0.isAlive && GameRules.allies(actor,$0,in:engine.state) }.map { .unit($0.id) }
        case .rescue: return units.filter { !$0.isAlive && $0.kind == .player && GameRules.allies(actor,$0,in:engine.state) }.map { .unit($0.id) }
        }
    }
    /// Read-only target legality for visual markers. Does not alter selection or random state.
    public func previewForTarget(_ value: ActionTarget) -> ActionPreview {
        guard let actor else { return ActionPreview(allowed:false,message:"当前没有行动者") }
        let command: GameCommand
        switch action {
        case .attack: guard case .unit(let id) = value else { return ActionPreview(allowed:false,message:"请选择单位") }; command = .attack(actor:actor.id,target:id)
        case .skill(let id): command = .cast(actor:actor.id,skill:id,target:value)
        case .item(let item): guard case .unit(let id) = value else { return ActionPreview(allowed:false,message:"请选择队友") }; command = .useItem(actor:actor.id,item:item,target:id)
        case .rescue: guard case .unit(let id) = value else { return ActionPreview(allowed:false,message:"请选择倒地队友") }; command = .rescue(actor:actor.id,target:id)
        case .move: return ActionPreview(allowed:false,message:"沿道路选择路径")
        }
        return engine.preview(command)
    }
    public var legalTargetNodes: Set<Int> {
        Set(possibleTargets.filter { previewForTarget($0).allowed }.compactMap {
            switch $0 { case .node(let id):return id; case .unit(let id):return engine.state.units[id]?.nodeID }
        })
    }
    @discardableResult public func perform() throws -> OperationReceipt {
        guard let command else { throw GameError("当前行动者已变化或尚未选择目标。") }
        let receipt = try engine.apply(command); synchronize(); return receipt
    }
    @discardableResult public func apply(_ command: GameCommand) throws -> OperationReceipt {
        let receipt = try engine.apply(command); synchronize(); return receipt
    }
    @discardableResult public func reward(_ value: ResourceReward) throws -> OperationReceipt {
        try apply(.reward(actors: rewardIDs.sorted(), value: value))
    }
    public func synchronize() {
        if engine.state.units[selectedPlayerID] == nil { selectedPlayerID = engine.state.players.first!.id }
        rewardIDs = rewardIDs.filter { engine.state.units[$0]?.kind == .player }
        if pendingActorID != actor?.id || pendingBattle != engine.state.isBattle {
            pendingBattle = engine.state.isBattle
            pendingActorID = actor?.id; target = nil; action = engine.state.battle == nil ? .move : .attack
            path = actor.map { [$0.nodeID] } ?? []
        }
        if engine.state.battle != nil { travelIDs = actor.map { [$0.id] } ?? [] }
        else if let actor {
            travelIDs = travelIDs.filter { engine.state.units[$0]?.isAlive == true && engine.state.units[$0]?.nodeID == actor.nodeID }
            travelIDs.insert(actor.id)
            if action == .move && path.first != actor.nodeID { path = [actor.nodeID] }
        }
        if action == .move, let actor, path.first != actor.nodeID { path = [actor.nodeID] }
        if case .unit(let id) = target, engine.state.units[id]?.isAlive == false, action != .rescue { target = nil }
    }
}
