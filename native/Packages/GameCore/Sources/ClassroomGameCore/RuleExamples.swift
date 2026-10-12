import Foundation

public struct RuleCheck: Equatable, Identifiable {
    public var title: String
    public var passed: Bool
    public var id: String { title }
    public init(_ title: String, _ passed: Bool) { self.title = title; self.passed = passed }
}
public struct RuleExampleResult {
    public var before: PublicGameSnapshot
    public var after: PublicGameSnapshot
    public var undone: PublicGameSnapshot?
    public var checks: [RuleCheck]
    public var passed: Bool { checks.allSatisfy(\.passed) }
}

/// Isolated, repeatable examples using the same engine as future live play.
/// Fixed rolls make these examples reviewable; live games use their saved random state.
public enum RuleExample: String, CaseIterable, Identifiable {
    case twenty, groupUndo, rescue, clock, invalidAction, rewards
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .twenty: return "自然20与普通伤害"
        case .groupUndo: return "群攻、掉落与整步撤销"
        case .rescue: return "救援后下一轮行动"
        case .clock: return "暂停与回合超时"
        case .invalidAction: return "无效操作保留原状态"
        case .rewards: return "多人奖励与行动点上限"
        }
    }
    public var explanation: String {
        switch self {
        case .twenty: return "传奇权杖攻击遗迹魔龙。比较D20自然20和18＋2：只有自然20直接击败Boss。"
        case .groupUndo: return "龙骑士用一次龙焰攻击同地点3只怪物，自然20全部击败。完成自疗、护盾、掉落与积分后，再撤销整次行动。"
        case .rescue: return "冒险者用2行动点和1复活石救援同地点队友。队友生命上限13，恢复7点，本轮不能行动。"
        case .clock: return "剩余17秒时打开绘本和编辑页面，再依次关闭。两个暂停原因都解除后才继续；超时清空当前角色行动点并轮到下一位。"
        case .invalidAction: return "尝试用射程0的训练剑攻击相邻地点的怪物，再模拟保存失败。两种失败均保留生命、行动点、随机结果和历史。"
        case .rewards: return "当前行动者与奖励对象分别选择。给两名玩家各发10金币、3行动点、2积分，行动点最多8。"
        }
    }

    public func run(catalog: GameCatalog) throws -> RuleExampleResult {
        var state = try prepared(catalog: catalog)
        var checks: [RuleCheck] = []
        var undone: PublicGameSnapshot?
        var shownDice: [DiceResult] = []
        switch self {
        case .twenty:
            state.units["p1"]?.equipment.weapon = "legendaryStaff"
            state.units["p1"]?.baseAttributes.damage = 2
            state.units["m1"]?.shield = 100
            state.random = RandomState(seed: 1, scripted: [20] + Array(repeating: 100, count: 10))
        case .groupUndo:
            state.units["p1"]?.health = 5
            state.random = RandomState(seed: 1, scripted: [20] + Array(repeating: 100, count: 30))
        case .rescue:
            state.units["p1"]?.inventory["revivalStone"] = 1
            state.units["p2"]?.baseAttributes.maximumHealth = 13
            state.units["p2"]?.health = 0
        case .clock: state.remainingSeconds = 17
        case .invalidAction: state.units["m1"]?.nodeID = 3
        case .rewards:
            state.units["p1"]?.ap = 7
            state.units["p2"]?.ap = 6
        }
        let beforeState = state
        let before = try state.publicSnapshot(catalog: catalog)
        let engine = try GameEngine(catalog: catalog, state: state)
        switch self {
        case .twenty:
            let receipt = try engine.apply(.attack(actor: "p1", target: "m1"))
            shownDice = receipt.dice
            var ordinary = beforeState
            ordinary.random = RandomState(seed: 1, scripted: [18])
            let comparison = try GameEngine(catalog: catalog, state: ordinary)
            let normal = try comparison.apply(.attack(actor: "p1", target: "m1"))
            checks = [RuleCheck("自然20击败72生命的Boss，护盾清零", engine.state.units["m1"]?.health == 0 && engine.state.units["m1"]?.shield == 0),
                      RuleCheck("18＋2只是20点普通伤害，100护盾剩80", normal.dice.first?.values == [18] && normal.dice.first?.naturalTwenty == false && comparison.state.units["m1"]?.shield == 80 && comparison.state.units["m1"]?.health == 72),
                      RuleCheck("Boss击败积分5，必定金币30", engine.state.units["p1"]?.score == 5 && engine.state.units["p1"]?.coins == 30)]
        case .groupUndo:
            let command = GameCommand.cast(actor: "p1", skill: "dragonFlame", target: .node(2))
            let receipt = try engine.apply(command, id: "example-group")
            shownDice = receipt.dice
            let resultState = engine.state
            _ = try engine.replay(receipt.id)
            _ = try engine.apply(command, id: receipt.id)
            checks = [RuleCheck("3个敌人共用1次伤害掷骰并全部击败", receipt.dice.count == 1 && resultState.units.values.filter { $0.kind == .monster }.allSatisfy { !$0.isAlive }),
                      RuleCheck("自疗5→11，护盾6，行动点3→1", resultState.units["p1"]?.health == 11 && resultState.units["p1"]?.shield == 6 && resultState.units["p1"]?.ap == 1),
                      RuleCheck("积分共7；Boss必掉30金币，其他掉落本例固定未触发", resultState.units["p1"]?.score == 7 && resultState.units["p1"]?.coins == 30),
                      RuleCheck("重复提交和查看历史不会重复发奖励", engine.state == resultState && engine.history.count == 1),
                      RuleCheck("所有效果完成后返回探索，战斗增益清除", resultState.phase == .exploration && resultState.units["p1"]?.damageBuff == nil)]
            let after = try resultState.publicSnapshot(catalog: catalog, dice: shownDice)
            try engine.undo()
            undone = try engine.state.publicSnapshot(catalog: catalog)
            checks.append(RuleCheck("撤销恢复全部角色、怪物、掉落、队列和随机状态", engine.state == beforeState && engine.history.isEmpty))
            return RuleExampleResult(before: before, after: after, undone: undone, checks: checks)
        case .rescue:
            try engine.apply(.rescue(actor: "p1", target: "p2"))
            checks = [RuleCheck("13点上限恢复一半向上取整：7", engine.state.units["p2"]?.health == 7),
                      RuleCheck("救援消耗2行动点和1复活石，获得2积分", engine.state.units["p1"]?.ap == 1 && engine.state.units["p1"]?.inventory["revivalStone"] == nil && engine.state.units["p1"]?.score == 2),
                      RuleCheck("获救队友从第2轮开始能行动", engine.state.units["p2"]?.canActFromRound == 2)]
            try engine.apply(.endTurn(actor: "p1", timedOut: false))
            checks.append(RuleCheck("当前轮跳过获救队友，轮到怪物", engine.state.battle?.current == "m1"))
        case .clock:
            try engine.setPause(.book, enabled: true); try engine.setPause(.editor, enabled: true)
            _ = try engine.advanceClock(by: 100)
            checks.append(RuleCheck("两个页面打开期间，仍剩17秒", engine.state.remainingSeconds == 17))
            try engine.setPause(.book, enabled: false); _ = try engine.advanceClock(by: 100)
            checks.append(RuleCheck("关闭绘本后，编辑页仍使计时暂停", engine.state.remainingSeconds == 17))
            try engine.setPause(.editor, enabled: false); _ = try engine.advanceClock(by: 2)
            checks.append(RuleCheck("全部解除后恢复：17→15秒", engine.state.remainingSeconds == 15))
            _ = try engine.advanceClock(by: 15)
            checks.append(RuleCheck("超时清空行动点，轮到下一位并重置30秒", engine.state.units["p1"]?.ap == 0 && engine.state.battle?.current == "p2" && engine.state.remainingSeconds == 30))
            checks.append(RuleCheck("页面暂停没有增加游戏操作历史", engine.history.count == 1))
        case .invalidAction:
            do { try engine.apply(.attack(actor: "p1", target: "m1")); checks.append(RuleCheck("超出射程时拒绝攻击", false)) }
            catch { checks.append(RuleCheck("超出射程时拒绝攻击", true)) }
            checks.append(RuleCheck("无效攻击保持全部状态与历史不变", engine.state == beforeState && engine.history.isEmpty))
            var near = beforeState; near.units["m1"]?.nodeID = 2
            let failedSave = try GameEngine(catalog: catalog, state: near, persist: { _ in throw GameError("示例：无法写入存档。") })
            do { try failedSave.apply(.attack(actor: "p1", target: "m1")); checks.append(RuleCheck("保存失败时整次攻击不提交", false)) }
            catch { checks.append(RuleCheck("保存失败时整次攻击不提交", failedSave.state == near && failedSave.history.isEmpty)) }
        case .rewards:
            try engine.apply(.reward(actors: ["p1", "p2"], value: ResourceReward(coins: 10, ap: 3, score: 2)))
            checks = [RuleCheck("两人各得完整10金币与2积分", engine.state.players.allSatisfy { $0.coins == 10 && $0.score == 2 }),
                      RuleCheck("行动点均封顶8，实际分别增加1和2", engine.state.units["p1"]?.ap == 8 && engine.state.units["p2"]?.ap == 8),
                      RuleCheck("奖励没有改变当前行动者", engine.state.battle?.current == "p1")]
        }
        return RuleExampleResult(before: before, after: try engine.state.publicSnapshot(catalog: catalog, dice: shownDice), undone: undone, checks: checks)
    }

    private func prepared(catalog: GameCatalog) throws -> GameState {
        let map = GameMap(nodes: [MapNode(id: 1, name: "起点"), MapNode(id: 2, name: "交汇处"), MapNode(id: 3, name: "相邻地点")],
                          roads: [MapRoad(1, 2), MapRoad(2, 3)], revealed: [1, 2, 3])
        let classes = self == .groupUndo ? ["dragonKnight", "adventurer"] : ["adventurer", "adventurer"]
        let monsters = self == .groupUndo ? ["slime", "wolf", "ruinDragon"] : self == .twenty ? ["ruinDragon"] : ["stoneGuardian"]
        var units: [String: GameUnit] = [:]
        for (index, classID) in classes.enumerated() {
            let id = "p\(index + 1)"
            units[id] = try GameFactory.player(id: id, name: index == 0 ? "小蓝" : "小青", classID: classID, teamID: "blue", nodeID: 2, catalog: catalog)
        }
        for (index, template) in monsters.enumerated() {
            let id = "m\(index + 1)"
            units[id] = try GameFactory.monster(id: id, templateID: template, nodeID: 2, catalog: catalog)
            units[id]?.active = true
        }
        var state = GameState(gameID: "example-\(rawValue)", units: units, teams: [GameTeam(id: "blue", name: "蓝队")], map: map, random: RandomState(seed: 42))
        let queue = state.players.map(\.id) + units.values.filter { $0.kind == .monster }.map(\.id).sorted()
        state.battle = BattleState(kind: .pve, queue: queue, current: "p1", initiatives: queue.enumerated().map { Initiative(unitID: $0.element, value: 20 - $0.offset) })
        state.phase = .pve; state.pauseReasons = []
        return state
    }
}
