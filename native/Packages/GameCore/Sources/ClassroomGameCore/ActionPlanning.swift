import Foundation

public struct ActionPreview: Equatable {
    public var allowed: Bool
    public var cost: Int
    public var message: String
    public var path: [Int]
    public init(allowed: Bool, cost: Int = 0, message: String, path: [Int] = []) {
        self.allowed = allowed; self.cost = cost; self.message = message; self.path = path
    }
}
extension GameEngine {
    /// Shared validation only: no dice, save, time changes or history entries.
    public func preview(_ command: GameCommand) -> ActionPreview {
        do { return try Evaluation(state: state, catalog: catalog).preview(command) }
        catch { return ActionPreview(allowed: false, message: error.localizedDescription) }
    }
}
extension Evaluation {
    func movementPlan(actors: [String], path: [Int]) throws -> ([GameUnit], [Int], Bool) {
        guard !actors.isEmpty, Set(actors).count == actors.count, path.count >= 2 else { throw GameError("请选择同行角色和连续路径。") }
        if let battle = state.battle { guard actors == [battle.current ?? ""] else { throw GameError("战斗中仅当前角色可正常移动。") } }
        let travelers = try actors.map(acting)
        guard travelers.allSatisfy({ $0.nodeID == path[0] }) else { throw GameError("同行角色必须在同一出发节点。") }
        for index in 1..<path.count { guard state.map.neighbors(path[index - 1]).contains(path[index]) else { throw GameError("路径存在不相邻节点。") } }
        var stops = Array(path.dropFirst())
        let triggersEncounters = travelers[0].kind == .player && (state.battle == nil || state.battle?.kind == .pve)
        if triggersEncounters, let encounter = stops.firstIndex(where: { node in state.units.values.contains { $0.kind == .monster && $0.isAlive && !$0.active && $0.nodeID == node } }) {
            stops = Array(stops.prefix(encounter + 1))
        }
        guard travelers.allSatisfy({ $0.ap >= stops.count }) else { throw GameError("有同行角色行动点不足，整组移动未执行。") }
        return (travelers, stops, triggersEncounters)
    }
    func attackPlan(actor id: String, target targetID: String) throws -> (GameUnit, GameUnit, AttackDefinition, Attributes) {
        guard state.battle != nil else { throw GameError("普通攻击仅在战斗中使用。") }
        let actor = try acting(id), target = try unit(targetID), attack = try GameRules.attack(actor, catalog: catalog)
        guard target.isAlive, GameRules.enemies(actor, target, in: state), actor.ap >= 1 else { throw GameError("攻击目标或行动点无效。") }
        let stats = try GameRules.attributes(actor, catalog: catalog)
        try inRange(actor, node: target.nodeID, range: checkedAdd(attack.range, stats.range))
        return (actor, target, attack, stats)
    }
    func castPlan(actor id: String, skillID: String, target: ActionTarget?) throws -> (GameUnit, SkillDefinition, [String], Attributes) {
        let actor = try acting(id), skill = try catalog.skill(skillID)
        guard try GameRules.skills(actor, catalog: catalog).contains(skillID), actor.ap >= skill.cost,
              skill.uses.map({ (actor.skillUses[skillID] ?? 0) < $0 }) ?? true,
              skill.stage == .both || (state.isBattle ? skill.stage == .battle : skill.stage == .exploration) else { throw GameError("技能阶段、次数或行动点不满足。") }
        let selected = try targets(actor: actor, skill: skill, target: target)
        let stats = try GameRules.attributes(actor, catalog: catalog)
        for targetID in selected { try inRange(actor, node: unit(targetID).nodeID, range: checkedAdd(skill.range, stats.range)) }
        if actor.kind == .monster {
            switch skill.condition {
            case .always: break
            case .shieldEmpty: guard actor.shield == 0 else { throw GameError("怪物护盾尚未耗尽。") }
            case .healthHalfOrLess: guard actor.health <= stats.maximumHealth / 2 else { throw GameError("怪物生命尚高于一半。") }
            case .twoEnemiesAtNode: guard selected.count >= 2 else { throw GameError("群攻条件需要至少两名存活敌人。") }
            }
            if skill.oncePerTurn && state.battle?.onceSkillsThisTurn.contains(skillID) == true { throw GameError("同一怪物回合不重复施放自恢复技能。") }
        }
        return (actor, skill, selected, stats)
    }
    func itemPlan(actor id: String, itemID: String, target targetID: String) throws -> ItemDefinition {
        let actor = try acting(id), target = try unit(targetID), item = try catalog.item(itemID)
        guard item.kind == .consumable, actor.ap >= 1, (actor.inventory[itemID] ?? 0) >= 1,
              target.isAlive, GameRules.allies(actor, target, in: state) else { throw GameError("药水、背包或队友目标无效。") }
        try inRange(actor, node: target.nodeID, range: item.range)
        return item
    }
    func rescuePlan(actor id: String, target targetID: String) throws {
        let actor = try acting(id), target = try unit(targetID)
        guard actor.kind == .player, target.kind == .player, !target.isAlive,
              actor.nodeID == target.nodeID, GameRules.allies(actor, target, in: state),
              actor.ap >= catalog.rules.rescueCost,
              (actor.inventory[catalog.rules.revivalStone] ?? 0) > 0 else { throw GameError("救援需要同节点倒地队友、2行动点和个人复活石。") }
    }

    func preview(_ command: GameCommand) throws -> ActionPreview {
        switch command {
        case .move(let actors, let path):
            let (_, stops, _) = try movementPlan(actors: actors, path: path)
            return ActionPreview(allowed: true, cost: stops.count, message: "每人消耗\(stops.count)行动点，到达地点\(stops.last!)。", path: [path[0]] + stops)
        case .attack(let actor, let target):
            let (_, _, attack, stats) = try attackPlan(actor: actor, target: target)
            return ActionPreview(allowed: true, cost: 1, message: "消耗1行动点 · \(attack.dice.label) · 额外伤害\(stats.damage) · 射程\(attack.range + stats.range)。")
        case .cast(let actor, let skillID, let target):
            let (_, skill, _, _) = try castPlan(actor: actor, skillID: skillID, target: target)
            return ActionPreview(allowed: true, cost: skill.cost, message: "\(skill.name)：消耗\(skill.cost)行动点，确认后执行全部效果。")
        case .useItem(let actor, let itemID, let target):
            let item = try itemPlan(actor: actor, itemID: itemID, target: target)
            return ActionPreview(allowed: true, cost: 1, message: "消耗1行动点及1份\(item.name)。")
        case .rescue(let actor, let target):
            try rescuePlan(actor: actor, target: target)
            return ActionPreview(allowed: true, cost: catalog.rules.rescueCost, message: "消耗2行动点及1复活石；恢复半生命，战斗中下一轮可行动。")
        case .endTurn(let actor, _):
            _ = try acting(actor)
            guard state.battle != nil else { throw GameError("探索阶段没有自动回合。") }
            return ActionPreview(allowed: true, message: "结束本轮行动，保留剩余行动点。")
        default: throw GameError("该操作不提供普通行动预览。")
        }
    }
}
