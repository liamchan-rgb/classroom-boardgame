import Foundation

public enum GamePhase: String, Codable { case preparation, exploration, pve, teamPvp, freeForAll, settlement }
public enum GamePause: String, Codable, CaseIterable { case manual, book, editor, history, background, allPlayersDown, noSurvivors }
public enum UnitKind: String, Codable { case player, monster }
public enum BattleKind: String, Codable { case pve, teamPvp, freeForAll }

public struct Equipment: Codable, Equatable {
    public var weapon: String?
    public var armor: String?
    public var accessory: String?
    public init(weapon: String? = nil, armor: String? = nil, accessory: String? = nil) {
        self.weapon = weapon; self.armor = armor; self.accessory = accessory
    }
    public subscript(slot: ItemSlot) -> String? {
        get { switch slot { case .weapon: return weapon; case .armor: return armor; case .accessory: return accessory } }
        set { switch slot { case .weapon: weapon = newValue; case .armor: armor = newValue; case .accessory: accessory = newValue } }
    }
    public var itemIDs: [String] { [weapon, armor, accessory].compactMap { $0 } }
}

public struct DamageBuff: Codable, Equatable {
    public var amount: Int
    public var roundsLeft: Int
    public var appliedRound: Int
}

public struct GameUnit: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: UnitKind
    public var templateID: String
    public var host: Bool
    public var teamID: String?
    public var nodeID: Int
    public var baseAttributes: Attributes
    public var health: Int
    public var shield: Int
    public var ap: Int
    public var coins: Int
    public var score: Int
    public var inventory: [String: Int]
    public var equipment: Equipment
    public var skillUses: [String: Int]
    public var damageBuff: DamageBuff?
    public var canActFromRound: Int
    public var active: Bool
    public var defeatRewarded: Bool
    public var isAlive: Bool { health > 0 }
}

public struct GameTeam: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var coins: Int
    public var inventory: [String: Int]
    public init(id: String, name: String, coins: Int = 0, inventory: [String: Int] = [:]) {
        self.id = id; self.name = name; self.coins = coins; self.inventory = inventory
    }
}

public enum NodeKind: String, Codable { case start, combat, boss, reward, empty }
public struct NodeReward: Codable, Equatable {
    public var coins: Int
    public var score: Int
    public var items: [String: Int]
    public init(coins: Int = 10, score: Int = 2, items: [String: Int] = [:]) { self.coins = coins; self.score = score; self.items = items }
}
public struct MapNode: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var kind: NodeKind
    public var x: Double
    public var y: Double
    public var reward: NodeReward?
    public var rewardCompleted: Bool
    public init(id: Int, name: String, kind: NodeKind = .empty, x: Double = 0, y: Double = 0, reward: NodeReward? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.x = x; self.y = y
        self.reward = reward; rewardCompleted = false
    }
}
public struct MapRoad: Codable, Equatable {
    public var a: Int
    public var b: Int
    public init(_ a: Int, _ b: Int) { self.a = a; self.b = b }
}
public struct GameMap: Codable, Equatable {
    public var nodes: [MapNode]
    public var roads: [MapRoad]
    public var seed: UInt64
    public var revealed: Set<Int>
    public init(nodes: [MapNode], roads: [MapRoad], seed: UInt64 = 1, revealed: Set<Int> = []) {
        self.nodes = nodes; self.roads = roads; self.seed = seed; self.revealed = revealed
    }
    public func neighbors(_ node: Int) -> [Int] {
        roads.compactMap { $0.a == node ? $0.b : $0.b == node ? $0.a : nil }.sorted()
    }
    public func shortestPath(from start: Int, to end: Int) -> [Int]? {
        guard nodes.contains(where: { $0.id == start }), nodes.contains(where: { $0.id == end }) else { return nil }
        var frontier = [start], cursor = 0, previous: [Int: Int] = [:], visited: Set<Int> = [start]
        while cursor < frontier.count {
            let current = frontier[cursor]; cursor += 1
            if current == end {
                var path = [end]
                while let parent = previous[path.last!] { path.append(parent) }
                return path.reversed()
            }
            for next in neighbors(current) where visited.insert(next).inserted { previous[next] = current; frontier.append(next) }
        }
        return nil
    }
    public func distance(from start: Int, to end: Int) -> Int? { shortestPath(from: start, to: end).map { $0.count - 1 } }
    public func validate() throws {
        let ids = Set(nodes.map(\.id))
        guard !nodes.isEmpty, ids.count == nodes.count, revealed.isSubset(of: ids),
              nodes.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw GameError("地图节点或揭示状态无效。") }
        var edgeKeys: Set<String> = []
        for road in roads {
            guard ids.contains(road.a), ids.contains(road.b), road.a != road.b,
                  edgeKeys.insert("\(min(road.a, road.b)):\(max(road.a, road.b))").inserted else { throw GameError("道路重复或引用无效。") }
        }
        for id in ids { guard shortestPath(from: nodes[0].id, to: id) != nil else { throw GameError("地图不连通。") } }
    }
}

public struct Initiative: Codable, Equatable { public var unitID: String; public var value: Int }
public struct BattleState: Codable, Equatable {
    public var kind: BattleKind
    public var round: Int
    public var queue: [String]
    public var acted: Set<String>
    public var current: String?
    public var initiatives: [Initiative]
    public var monsterTargets: [String: String]? = nil
    public var onceSkillsThisTurn: Set<String>
    public init(kind: BattleKind, queue: [String], current: String? = nil, round: Int = 1, initiatives: [Initiative] = []) {
        self.kind = kind; self.queue = queue; self.current = current; self.round = round
        self.initiatives = initiatives; acted = []; onceSkillsThisTurn = []
    }
}
public struct BattleOutcome: Codable, Equatable {
    public var kind: BattleKind
    public var winners: [String]
    public var scoreSettlement: Bool
    public var personalRanking: [RankingRow]
    public var teamRanking: [RankingRow]
}

public struct RandomState: Codable, Equatable {
    public var seed: UInt64
    public var scripted: [Int]
    public var cursor: Int
    public var damageD20Override: Int? = nil
    public init(seed: UInt64 = 1, scripted: [Int] = []) { self.seed = seed; self.scripted = scripted; cursor = 0 }
    public mutating func next(upperBound: Int) throws -> Int {
        guard upperBound > 0, cursor >= 0, cursor <= scripted.count else { throw GameError("随机范围或游标无效。") }
        if cursor < scripted.count {
            let value = scripted[cursor]
            guard (1...upperBound).contains(value) else { throw GameError("固定随机值\(value)超出1…\(upperBound)。") }
            cursor += 1; return value
        }
        let bound = UInt64(upperBound), threshold = (0 &- bound) % bound
        while true {
            seed &+= 0x9E3779B97F4A7C15
            var value = seed
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            if value >= threshold { return Int(value % bound) + 1 }
        }
    }
}

public struct GameState: Codable, Equatable {
    public var formatVersion: Int = 1
    public var gameID: String
    public var verificationScenario: String? = nil
    public var phase: GamePhase
    public var units: [String: GameUnit]
    public var teams: [GameTeam]
    public var map: GameMap
    public var battle: BattleState?
    public var lastOutcome: BattleOutcome?
    public var pauseReasons: Set<GamePause>
    public var remainingSeconds: Double
    public var random: RandomState
    public init(gameID: String = UUID().uuidString, units: [String: GameUnit], teams: [GameTeam], map: GameMap, random: RandomState = RandomState()) {
        self.gameID = gameID; phase = .exploration; self.units = units; self.teams = teams; self.map = map
        battle = nil; lastOutcome = nil; pauseReasons = [.manual]; remainingSeconds = 30; self.random = random
    }
    public var players: [GameUnit] { units.values.filter { $0.kind == .player }.sorted { $0.id < $1.id } }
    public var isBattle: Bool { battle != nil }
}

public enum GameFactory {
    public static func player(id: String, name: String, classID: String, teamID: String, nodeID: Int, host: Bool = false, catalog: GameCatalog) throws -> GameUnit {
        let definition = try catalog.playerClass(classID)
        return GameUnit(id: id, name: name, kind: .player, templateID: classID, host: host, teamID: teamID,
                        nodeID: nodeID, baseAttributes: definition.attributes, health: definition.attributes.maximumHealth,
                        shield: 0, ap: definition.attributes.baseAP, coins: 0, score: 0, inventory: [:],
                        equipment: Equipment(weapon: catalog.rules.starterWeapon), skillUses: [:], damageBuff: nil,
                        canActFromRound: 1, active: true, defeatRewarded: false)
    }
    public static func monster(id: String, templateID: String, nodeID: Int, catalog: GameCatalog) throws -> GameUnit {
        let definition = try catalog.monster(templateID)
        return GameUnit(id: id, name: definition.name, kind: .monster, templateID: templateID, host: false, teamID: nil,
                        nodeID: nodeID, baseAttributes: definition.attributes, health: definition.attributes.maximumHealth,
                        shield: definition.shield, ap: definition.attributes.baseAP, coins: 0, score: 0, inventory: [:],
                        equipment: Equipment(), skillUses: [:], damageBuff: nil, canActFromRound: 1,
                        active: false, defeatRewarded: false)
    }
}
