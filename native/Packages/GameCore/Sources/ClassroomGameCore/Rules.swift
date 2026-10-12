import Foundation

public struct RankingRow: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var score: Int
    public var rank: Int
}

public enum GameRules {
    public static func attributes(_ unit: GameUnit, catalog: GameCatalog) throws -> Attributes {
        var value = unit.baseAttributes
        for id in unit.equipment.itemIDs { value = try value.adding(catalog.item(id).attributes) }
        for set in catalog.sets {
            let count = unit.equipment.itemIDs.filter { set.items.contains($0) }.count
            if count >= 2 { value = try value.adding(set.twoPieces) }
            if count >= 3 { value = try value.adding(set.threePieces) }
        }
        if let buff = unit.damageBuff { value.damage = try checkedAdd(value.damage, buff.amount) }
        try GameCatalog.validateBase(value)
        return value
    }
    public static func skills(_ unit: GameUnit, catalog: GameCatalog) throws -> [String] {
        var result = try unit.kind == .player ? catalog.playerClass(unit.templateID).skills : catalog.monster(unit.templateID).skills
        for set in catalog.sets where set.items.allSatisfy(unit.equipment.itemIDs.contains) { result.append(set.skill) }
        return result
    }
    public static func attack(_ unit: GameUnit, catalog: GameCatalog) throws -> AttackDefinition {
        if unit.kind == .monster { return try catalog.monster(unit.templateID).attack }
        guard let weapon = unit.equipment.weapon, let attack = try catalog.item(weapon).attack else { throw GameError("角色没有可用于普攻的武器。") }
        return attack
    }
    public static func refill(_ unit: inout GameUnit, catalog: GameCatalog) throws {
        let stats = try attributes(unit, catalog: catalog)
        unit.ap = min(stats.maximumAP, max(unit.ap, stats.baseAP))
    }
    public static func faction(_ unit: GameUnit, in state: GameState) -> String {
        if state.battle?.kind == .freeForAll { return unit.id }
        if unit.kind == .monster { return "monsters" }
        return unit.teamID ?? unit.id
    }
    public static func allies(_ first: GameUnit, _ second: GameUnit, in state: GameState) -> Bool {
        if first.id == second.id { return true }
        if state.battle?.kind == .freeForAll { return false }
        if first.kind != second.kind { return false }
        if first.kind == .monster { return true }
        return first.teamID != nil && first.teamID == second.teamID
    }
    public static func enemies(_ first: GameUnit, _ second: GameUnit, in state: GameState) -> Bool {
        switch state.battle?.kind {
        case .freeForAll: return first.id != second.id && first.kind == .player && second.kind == .player
        case .teamPvp: return first.kind == .player && second.kind == .player && faction(first, in: state) != faction(second, in: state)
        case .pve, nil: return first.kind != second.kind
        }
    }
    public static func rankings(_ entries: [(String, String, Int)]) -> [RankingRow] {
        let ordered = entries.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }
        var previous: Int?, rank = 0
        return ordered.enumerated().map { index, entry in
            if previous != entry.2 { rank = index + 1; previous = entry.2 }
            return RankingRow(id: entry.0, name: entry.1, score: entry.2, rank: rank)
        }
    }
    public static func teamRankings(_ state: GameState) throws -> [RankingRow] {
        try rankings(state.teams.map { team in
            let score = try state.players.filter { $0.teamID == team.id }.reduce(0) { try checkedAdd($0, $1.score) }
            return (team.id, team.name, score)
        })
    }
}

extension GameState {
    public func validate(catalog: GameCatalog) throws {
        try map.validate()
        let teamIDs = Set(teams.map(\.id)), nodeIDs = Set(map.nodes.map(\.id))
        guard formatVersion == 1, !gameID.isEmpty, (1...7).contains(players.count),
              teamIDs.count == teams.count, remainingSeconds.isFinite, remainingSeconds >= 0,
              random.cursor >= 0, random.cursor <= random.scripted.count else { throw GameError("本局状态或计时、随机状态无效。") }
        if let value = random.damageD20Override, !(1...20).contains(value) { throw GameError("验证骰值无效。") }
        for (key, unit) in units {
            let stats = try GameRules.attributes(unit, catalog: catalog)
            guard key == unit.id, !unit.id.isEmpty, !unit.name.isEmpty, nodeIDs.contains(unit.nodeID),
                  (0...stats.maximumHealth).contains(unit.health), unit.shield >= 0,
                  (0...stats.maximumAP).contains(unit.ap), unit.coins >= 0, unit.canActFromRound >= 1,
                  unit.teamID.map(teamIDs.contains) ?? true else { throw GameError("角色资源、队伍或位置无效：\(unit.name)") }
            if unit.kind == .player { _ = try catalog.playerClass(unit.templateID) }
            else { _ = try catalog.monster(unit.templateID) }
            for slot in ItemSlot.allCases {
                if let id = unit.equipment[slot], try catalog.item(id).slot != slot { throw GameError("装备槽位不匹配。") }
            }
            for (id, count) in unit.inventory { _ = try catalog.item(id); guard count > 0 else { throw GameError("背包不能保存非正数量。") } }
            for (id, used) in unit.skillUses {
                let skill = try catalog.skill(id)
                guard used >= 0, skill.uses.map({ used <= $0 }) ?? true else { throw GameError("技能已用次数无效。") }
            }
            if let buff = unit.damageBuff {
                guard buff.amount >= 0, buff.roundsLeft >= 1, buff.appliedRound >= 0 else { throw GameError("临时增益无效。") }
            }
            if !unit.isAlive && (unit.shield != 0 || unit.damageBuff != nil) { throw GameError("倒地单位不能保留护盾或临时增益。") }
        }
        for team in teams {
            guard !team.id.isEmpty, team.coins >= 0 else { throw GameError("队伍仓库无效。") }
            for (id, count) in team.inventory { _ = try catalog.item(id); guard count > 0 else { throw GameError("仓库物品数量无效。") } }
        }
        for node in map.nodes {
            if let reward = node.reward {
                guard reward.coins >= 0, reward.score >= 0 else { throw GameError("地点奖励无效。") }
                for (id, count) in reward.items { _ = try catalog.item(id); guard count > 0 else { throw GameError("地点道具奖励无效。") } }
            }
        }
        if let battle {
            for (monster, target) in battle.monsterTargets ?? [:] {
                guard units[monster]?.kind == .monster, units[target]?.kind == .player else { throw GameError("怪物选敌记录无效。") }
            }
            let queue = Set(battle.queue)
            let expected: GamePhase = battle.kind == .pve ? .pve : battle.kind == .teamPvp ? .teamPvp : .freeForAll
            guard phase == expected, battle.round >= 1, queue.count == battle.queue.count,
                  Set(players.map(\.id)).isSubset(of: queue), battle.acted.isSubset(of: queue),
                  battle.queue.allSatisfy({ units[$0] != nil }), battle.current.map(queue.contains) ?? true,
                  Set(battle.initiatives.map(\.unitID)).count == battle.initiatives.count,
                  battle.initiatives.allSatisfy({ queue.contains($0.unitID) && (1...20).contains($0.value) }) else {
                throw GameError("战斗阶段或固定队列无效。")
            }
        } else if [.pve, .teamPvp, .freeForAll].contains(phase) { throw GameError("战斗阶段缺少战斗状态。") }
        _ = try GameRules.teamRankings(self)
    }
}

public enum ActionTarget: Codable, Equatable { case unit(String), node(Int) }
public struct ResourceReward: Codable, Equatable {
    public var coins: Int
    public var ap: Int
    public var score: Int
    public var items: [String: Int]
    public init(coins: Int = 0, ap: Int = 0, score: Int = 0, items: [String: Int] = [:]) {
        self.coins = coins; self.ap = ap; self.score = score; self.items = items
    }
}
public struct ResourcePatch: Codable, Equatable {
    public var health: Int?
    public var shield: Int?
    public var ap: Int?
    public var coins: Int?
    public var score: Int?
    public init(health: Int? = nil, shield: Int? = nil, ap: Int? = nil, coins: Int? = nil, score: Int? = nil) {
        self.health = health; self.shield = shield; self.ap = ap; self.coins = coins; self.score = score
    }
}
public enum GameCommand: Codable, Equatable {
    case monsterStep
    case editResources(unit: String, value: ResourcePatch)
    case startBattle(kind: BattleKind, monsters: [String])
    case move(actors: [String], path: [Int])
    case attack(actor: String, target: String)
    case cast(actor: String, skill: String, target: ActionTarget?)
    case useItem(actor: String, item: String, target: String)
    case rescue(actor: String, target: String)
    case endTurn(actor: String, timedOut: Bool)
    case joinMonster(String)
    case reward(actors: [String], value: ResourceReward)
    case setHealth(unit: String, value: Int, killer: String?)
    case revive(String)
    case equip(unit: String, slot: ItemSlot, item: String?)
    case changeTeam(unit: String, team: String)
    case reorderQueue([String])
    case finishBattle(winner: String?, byScore: Bool)
    case refillExploration
}
public struct DiceResult: Codable, Equatable {
    public var source: String
    public var formula: DiceFormula
    public var values: [Int]
    public var total: Int
    public var naturalTwenty: Bool
}
public struct GameEvent: Codable, Equatable {
    public var kind: String
    public var actor: String?
    public var target: String?
    public var amount: Int
    public var detail: String
    public init(_ kind: String, actor: String? = nil, target: String? = nil, amount: Int = 0, detail: String = "") {
        self.kind = kind; self.actor = actor; self.target = target; self.amount = amount; self.detail = detail
    }
}
public struct OperationReceipt: Codable, Equatable, Identifiable {
    public var id: String
    public var sequence: Int
    public var command: GameCommand
    public var dice: [DiceResult]
    public var events: [GameEvent]
    public var before: GameState
    public var after: GameState
}

public struct GameArchive: Codable, Equatable {
    public var formatVersion: Int = 1
    public var catalog: GameCatalog
    public var state: GameState
    public var history: [OperationReceipt]
    public init(catalog: GameCatalog, state: GameState, history: [OperationReceipt]) { self.catalog = catalog; self.state = state; self.history = history }
    public func validate() throws {
        try catalog.validate(); try state.validate(catalog: catalog)
        guard formatVersion == 1, Set(history.map(\.id)).count == history.count else { throw GameError("操作历史版本或ID无效。") }
        for (index, entry) in history.enumerated() {
            guard !entry.id.isEmpty, entry.sequence == index + 1,
                  entry.before.gameID == state.gameID, entry.after.gameID == state.gameID else { throw GameError("操作历史不属于同一局或序号无效。") }
            try entry.before.validate(catalog: catalog); try entry.after.validate(catalog: catalog)
        }
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    public static func decoded(_ bytes: Data, pauseOnRestore: Bool = true) throws -> GameArchive {
        var archive = try JSONDecoder().decode(GameArchive.self, from: bytes)
        try archive.validate()
        if pauseOnRestore { archive.state.pauseReasons.insert(.manual) }
        return archive
    }
}

public final class AtomicGameStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func save(_ archive: GameArchive) throws {
        let data = try archive.encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    public func load() throws -> GameArchive { try GameArchive.decoded(Data(contentsOf: url)) }
}
