import XCTest
@testable import ClassroomGameCore

func fixture(classes: [String] = ["adventurer", "adventurer"], monsters: [String] = ["slime"],
             kind: BattleKind? = .pve, scripted: [Int] = []) throws -> (GameCatalog, GameState) {
    let catalog = try GameCatalog.initial()
    let map = GameMap(nodes: [MapNode(id: 1, name: "起点", kind: .start), MapNode(id: 2, name: "交汇处"),
                             MapNode(id: 3, name: "补给点", kind: .reward, reward: NodeReward()), MapNode(id: 4, name: "秘密地点")],
                      roads: [MapRoad(1, 2), MapRoad(2, 3), MapRoad(2, 4)], revealed: kind == nil ? [1] : [1, 2])
    var units: [String: GameUnit] = [:]
    for (index, classID) in classes.enumerated() {
        let id = "p\(index + 1)"
        units[id] = try GameFactory.player(id: id, name: "玩家\(index + 1)", classID: classID, teamID: "blue", nodeID: kind == nil ? 1 : 2, catalog: catalog)
    }
    for (index, template) in monsters.enumerated() {
        let id = "m\(index + 1)"
        units[id] = try GameFactory.monster(id: id, templateID: template, nodeID: 2, catalog: catalog)
        units[id]?.active = kind != nil
    }
    var state = GameState(gameID: "rules-fixture", units: units,
                          teams: [GameTeam(id: "blue", name: "蓝队"), GameTeam(id: "orange", name: "橙队"), GameTeam(id: "green", name: "绿队")],
                          map: map, random: RandomState(seed: 12345, scripted: scripted))
    state.pauseReasons = []
    if let kind {
        let players = state.players.map(\.id), enemies = units.values.filter { $0.kind == .monster }.map(\.id).sorted()
        let queue = players + enemies
        state.battle = BattleState(kind: kind, queue: queue, current: "p1", initiatives: queue.enumerated().map { Initiative(unitID: $0.element, value: 20 - $0.offset) })
        state.phase = kind == .pve ? .pve : kind == .teamPvp ? .teamPvp : .freeForAll
    }
    return (catalog, state)
}

func finishRound(_ engine: GameEngine) throws {
    let round = try XCTUnwrap(engine.state.battle?.round)
    var guardCount = 0
    while engine.state.battle?.round == round {
        guardCount += 1
        guard guardCount < 30, let current = engine.state.battle?.current else { throw GameError("测试队列无法推进。") }
        try engine.apply(.endTurn(actor: current, timedOut: false))
    }
}
