import Foundation

extension Evaluation {
    /// Select and resolve exactly one autonomous action in the current transaction.
    /// Target draws, cached random targets, dice and effects all roll back together.
    mutating func monsterStep() throws {
        guard state.pauseReasons.isEmpty, let battle = state.battle, battle.kind == .pve,
              let id = battle.current, let actor = state.units[id], actor.kind == .monster else {
            throw GameError("怪物只在未暂停的PVE当前回合自动行动。")
        }
        _ = try acting(id)
        let definition = try catalog.monster(actor.templateID)
        let enemies = state.players.filter { $0.isAlive && GameRules.enemies(actor, $0, in: state) }
        guard !enemies.isEmpty else { state.battle?.current = nil; return }
        var skillChoices: [(priority: Int, skill: SkillDefinition, target: ActionTarget?)] = []
        for skillID in definition.skills {
            let skill = try catalog.skill(skillID)
            let candidates: [ActionTarget?]
            switch skill.target {
            case .selfOnly: candidates = [nil]
            case .enemy: candidates = enemies.map { .unit($0.id) }
            case .ally: candidates = state.units.values.filter { $0.isAlive && $0.id != id && GameRules.allies(actor, $0, in: state) }.sorted { $0.id < $1.id }.map { .unit($0.id) }
            case .enemiesAtNode: candidates = Set(enemies.map(\.nodeID)).sorted().map { .node($0) }
            case .alliesAtNode:
                candidates = Set(state.units.values.filter { $0.isAlive && GameRules.allies(actor, $0, in: state) }.map(\.nodeID)).sorted().map { .node($0) }
            }
            for target in candidates {
                if (try? castPlan(actor: id, skillID: skillID, target: target)) != nil {
                    skillChoices.append((skill.priority, skill, target))
                }
            }
        }
        if let priority = skillChoices.map(\.priority).min() {
            let available = skillChoices.filter { $0.priority == priority }
            let selected = try choose(available.count, actor: id, reason: "技能同优先级目标")
            let choice = available[selected]
            events.append(GameEvent("aiAction", actor: id, detail: choice.skill.name))
            try cast(actor: id, skillID: choice.skill.id, target: choice.target)
            return
        }
        let target: GameUnit
        if definition.strategy == .random, let retained = battle.monsterTargets?[id], let cached = enemies.first(where: { $0.id == retained }) {
            target = cached
        } else {
            let candidates: [GameUnit]
            switch definition.strategy {
            case .nearest:
                let nearest = enemies.map { state.map.distance(from: actor.nodeID, to: $0.nodeID) ?? Int.max }.min()!
                candidates = enemies.filter { state.map.distance(from: actor.nodeID, to: $0.nodeID) == nearest }
            case .lowestHealthRatio:
                let ratios = try enemies.map { Double($0.health) / Double(try GameRules.attributes($0, catalog: catalog).maximumHealth) }
                let lowest = ratios.min()!
                candidates = enemies.enumerated().filter { ratios[$0.offset] == lowest }.map(\.element)
            case .random: candidates = enemies
            }
            target = candidates[try choose(candidates.count, actor: id, reason: "选敌")]
            var cache = state.battle?.monsterTargets ?? [:]; cache[id] = target.id; state.battle?.monsterTargets = cache
            events.append(GameEvent("aiTarget", actor: id, target: target.id, detail: definition.strategy.rawValue))
        }
        if (try? attackPlan(actor: id, target: target.id)) != nil {
            events.append(GameEvent("aiAction", actor: id, target: target.id, detail: "普攻"))
            try attack(actor: id, target: target.id)
        } else if actor.ap >= 1, let path = state.map.shortestPath(from: actor.nodeID, to: target.nodeID), path.count >= 2 {
            events.append(GameEvent("aiAction", actor: id, target: target.id, detail: "接近"))
            try move(actors: [id], path: Array(path.prefix(2)))
        } else {
            state.battle?.acted.insert(id); state.battle?.current = nil
            events.append(GameEvent("aiEndTurn", actor: id, detail: "没有可执行行动"))
        }
    }
    mutating func choose(_ count: Int, actor: String, reason: String) throws -> Int {
        guard count > 0 else { throw GameError("没有合法的怪物候选目标。") }
        guard count > 1 else { return 0 }
        let selected = try state.random.next(upperBound: count) - 1
        events.append(GameEvent("aiRandomChoice", actor: actor, amount: selected, detail: "\(reason)；候选\(count)"))
        return selected
    }
}
