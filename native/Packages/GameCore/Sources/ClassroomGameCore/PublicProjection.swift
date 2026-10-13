import Foundation

public struct PublicGameUnit: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var player: Bool
    public var host: Bool
    public var health: Int
    public var maximumHealth: Int
    public var shield: Int
    public var ap: Int
    public var coins: Int
    public var score: Int
    public var team: String
    public var nodeID: Int
    public var current: Bool
    public var templateID: String = ""
    public var teamID: String? = nil
    public var canActFromRound: Int = 1
    public var acted: Bool = false
}
public struct PublicGameNode: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var kind: NodeKind?
    public var x: Double
    public var y: Double
    public var revealed: Bool
    public var claimed: Bool = false
}
public struct PublicGameSnapshot: Codable, Equatable {
    public var phase: GamePhase
    public var round: Int
    public var currentName: String?
    public var queue: [String]
    public var remainingSeconds: Double
    public var paused: Bool
    public var units: [PublicGameUnit]
    public var nodes: [PublicGameNode]
    public var roads: [MapRoad]
    public var dice: [DiceResult]
    public var queueIDs: [String] = []
}

extension GameState {
    public func publicSnapshot(catalog: GameCatalog, dice: [DiceResult] = []) throws -> PublicGameSnapshot {
        var known = map.revealed
        for node in map.revealed { known.formUnion(map.neighbors(node)) }
        known.formUnion(players.map(\.nodeID))
        let visible = units.values.filter { $0.kind == .player || map.revealed.contains($0.nodeID) }.sorted { $0.id < $1.id }
        let rows = try visible.map { unit in
            PublicGameUnit(id: unit.id, name: unit.name, player: unit.kind == .player, host: unit.host,
                           health: unit.health, maximumHealth: try GameRules.attributes(unit, catalog: catalog).maximumHealth,
                           shield: unit.shield, ap: unit.ap, coins: unit.coins, score: unit.score,
                           team: teams.first(where: { $0.id == unit.teamID })?.name ?? (unit.kind == .monster ? "敌方" : "未分队"),
                           nodeID: unit.nodeID, current: battle?.current == unit.id,
                           templateID: unit.templateID, teamID: unit.teamID,
                           canActFromRound: unit.canActFromRound, acted: battle?.acted.contains(unit.id) == true)
        }
        let publicNodes = map.nodes.filter { known.contains($0.id) }.map { node in
            PublicGameNode(id: node.id, name: map.revealed.contains(node.id) ? node.name : "未探索地点\(node.id)",
                           kind: map.revealed.contains(node.id) ? node.kind : nil, x: node.x, y: node.y, revealed: map.revealed.contains(node.id),
                           claimed: map.revealed.contains(node.id) && node.rewardCompleted)
        }
        let names = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.name) })
        return PublicGameSnapshot(phase: phase, round: battle?.round ?? 0,
                                  currentName: battle?.current.flatMap { names[$0] },
                                  queue: battle?.queue.map { names[$0] ?? "未揭示单位" } ?? [],
                                  remainingSeconds: remainingSeconds, paused: !pauseReasons.isEmpty,
                                  units: rows, nodes: publicNodes,
                                  roads: map.roads.filter { map.revealed.contains($0.a) || map.revealed.contains($0.b) }, dice: dice,
                                  queueIDs: battle?.queue.filter { names[$0] != nil } ?? [])
    }
}
