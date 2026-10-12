import Foundation

public final class GameEngine {
    public let catalog: GameCatalog
    public private(set) var state: GameState
    public private(set) var history: [OperationReceipt]
    private let persist: ((GameArchive) throws -> Void)?

    public init(catalog: GameCatalog, state: GameState, history: [OperationReceipt] = [],
                persist: ((GameArchive) throws -> Void)? = nil) throws {
        let archive = GameArchive(catalog: catalog, state: state, history: history)
        try archive.validate()
        self.catalog = catalog; self.state = state; self.history = history; self.persist = persist
    }
    public var archive: GameArchive { GameArchive(catalog: catalog, state: state, history: history) }

    @discardableResult
    public func apply(_ command: GameCommand, id: String = UUID().uuidString) throws -> OperationReceipt {
        guard !id.isEmpty else { throw GameError("操作ID不能为空。") }
        if let recorded = history.first(where: { $0.id == id }) {
            guard recorded.command == command else { throw GameError("同一操作ID对应了不同请求。") }
            return recorded // Retries/read-only replays never roll or pay rewards again.
        }
        var evaluation = Evaluation(state: state, catalog: catalog)
        try evaluation.execute(command)
        try evaluation.state.validate(catalog: catalog)
        let receipt = OperationReceipt(id: id, sequence: history.count + 1, command: command,
                                       dice: evaluation.dice, events: evaluation.events,
                                       before: state, after: evaluation.state)
        let nextHistory = history + [receipt]
        try persist?(GameArchive(catalog: catalog, state: evaluation.state, history: nextHistory))
        state = evaluation.state; history = nextHistory
        return receipt
    }
    public func replay(_ id: String) throws -> OperationReceipt {
        guard let entry = history.first(where: { $0.id == id }) else { throw GameError("操作记录不存在。") }
        return entry
    }
    @discardableResult
    public func undo() throws -> OperationReceipt {
        guard let entry = history.last else { throw GameError("没有可撤销的游戏操作。") }
        let shortened = Array(history.dropLast())
        try persist?(GameArchive(catalog: catalog, state: entry.before, history: shortened))
        state = entry.before; history = shortened
        return entry
    }
    public func rollback(after id: String) throws {
        guard let index = history.firstIndex(where: { $0.id == id }) else { throw GameError("历史操作不存在。") }
        let shortened = Array(history.prefix(index + 1)), restored = history[index].after
        try persist?(GameArchive(catalog: catalog, state: restored, history: shortened))
        state = restored; history = shortened
    }
    public func setPause(_ reason: GamePause, enabled: Bool) throws {
        // View changes are metadata, not game actions. Pausing remains effective if saving fails.
        if enabled {
            state.pauseReasons.insert(reason)
            try persist?(archive)
        } else {
            var next = state; next.pauseReasons.remove(reason)
            try persist?(GameArchive(catalog: catalog, state: next, history: history))
            state = next
        }
    }
    public func extendTime(by seconds: Double) throws {
        guard seconds.isFinite, seconds > 0, (state.remainingSeconds + seconds).isFinite else { throw GameError("延长时间无效。") }
        var next = state; next.remainingSeconds += seconds
        try persist?(GameArchive(catalog: catalog, state: next, history: history)); state = next
    }
    @discardableResult
    public func advanceClock(by seconds: Double) throws -> OperationReceipt? {
        guard seconds.isFinite, seconds >= 0 else { throw GameError("计时时长无效。") }
        guard state.pauseReasons.isEmpty, let current = state.battle?.current,
              state.units[current]?.kind == .player, seconds > 0 else { return nil }
        if seconds >= state.remainingSeconds { return try apply(.endTurn(actor: current, timedOut: true)) }
        state.remainingSeconds -= seconds
        return nil
    }
}

struct Evaluation {
    var state: GameState
    let catalog: GameCatalog
    var dice: [DiceResult] = []
    var events: [GameEvent] = []

    func unit(_ id: String) throws -> GameUnit {
        guard let value = state.units[id] else { throw GameError("角色或怪物不存在：\(id)") }; return value
    }
    func acting(_ id: String) throws -> GameUnit {
        let value = try unit(id)
        guard value.isAlive else { throw GameError("倒地或战败单位不能行动。") }
        guard state.phase == .exploration || state.isBattle else { throw GameError("当前阶段不能正常行动。") }
        if let battle = state.battle {
            guard battle.current == id, !battle.acted.contains(id), value.canActFromRound <= battle.round else { throw GameError("尚未轮到该角色行动。") }
        } else if value.kind != .player { throw GameError("探索阶段不执行怪物回合。") }
        return value
    }
    func inRange(_ from: GameUnit, node: Int, range: Int) throws {
        guard let distance = state.map.distance(from: from.nodeID, to: node), distance <= range else { throw GameError("目标不在合法射程内。") }
    }
    mutating func roll(_ formula: DiceFormula, source: String) throws -> DiceResult {
        try formula.validate()
        var values: [Int] = []
        for _ in 0..<formula.count {
            if source == "damage", formula.sides == 20, let forced = state.random.damageD20Override {
                guard (1...20).contains(forced) else { throw GameError("验证D20值必须在1…20。") }
                values.append(forced); state.random.damageD20Override = nil
                events.append(GameEvent("verificationRoll", amount: forced, detail: "伤害D20"))
            } else { values.append(try state.random.next(upperBound: formula.sides)) }
        }
        let total = try values.reduce(formula.flat) { try checkedAdd($0, $1) }
        let result = DiceResult(source: source, formula: formula, values: values, total: total,
                                naturalTwenty: source == "damage" && formula.sides == 20 && values.contains(20))
        dice.append(result); return result
    }
    mutating func spend(_ id: String, cost: Int) throws {
        var actor = try unit(id)
        guard cost >= 0, actor.ap >= cost else { throw GameError("行动点不足。") }
        actor.ap -= cost; state.units[id] = actor
        events.append(GameEvent("ap", actor: id, target: id, amount: -cost))
    }

    mutating func execute(_ command: GameCommand) throws {
        switch command {
        case .monsterStep: try monsterStep()
        case .editResources(let id, let patch):
            if let health = patch.health { try setHealth(id, value: health, killer: nil) }
            var edited = try unit(id)
            if let shield = patch.shield { edited.shield = shield }
            if let ap = patch.ap { edited.ap = ap }
            if let coins = patch.coins { edited.coins = coins }
            if let score = patch.score { edited.score = score }
            state.units[id] = edited
            events.append(GameEvent("teacherResources", target: id))
        case .startBattle(let kind, let monsters): try start(kind: kind, monsters: monsters)
        case .move(let actors, let path): try move(actors: actors, path: path)
        case .attack(let actor, let target): try attack(actor: actor, target: target)
        case .cast(let actor, let skill, let target): try cast(actor: actor, skillID: skill, target: target)
        case .useItem(let actor, let item, let target): try useItem(actor: actor, itemID: item, target: target)
        case .rescue(let actor, let target): try rescue(actor: actor, target: target)
        case .endTurn(let actor, let timeout):
            _ = try acting(actor)
            guard state.battle != nil else { throw GameError("探索阶段没有自动行动队列。") }
            if timeout { state.units[actor]?.ap = 0; events.append(GameEvent("timeout", actor: actor)) }
            state.battle?.acted.insert(actor); state.battle?.current = nil
        case .joinMonster(let id): try join(id)
        case .reward(let actors, let reward): try rewardActors(actors, reward: reward)
        case .setHealth(let id, let value, let killer): try setHealth(id, value: value, killer: killer)
        case .revive(let id): try revive(id)
        case .equip(let id, let slot, let item): try equip(id, slot: slot, itemID: item)
        case .changeTeam(let id, let team):
            guard try unit(id).kind == .player, state.teams.contains(where: { $0.id == team }) else { throw GameError("换队对象或队伍无效。") }
            state.units[id]?.teamID = team; events.append(GameEvent("team", target: id, detail: team))
        case .reorderQueue(let queue):
            guard let battle = state.battle, Set(queue) == Set(battle.queue), queue.count == battle.queue.count else { throw GameError("改队列必须保留所有参战单位各一次。") }
            state.battle?.queue = queue
        case .finishBattle(let winner, let byScore):
            guard let battle = state.battle else { throw GameError("当前没有战斗。") }
            if battle.kind != .pve && winner == nil && !byScore { throw GameError("提前结束PVP须指定胜者或按积分结算。") }
            if let winner {
                guard battle.queue.contains(where: { state.units[$0].map { GameRules.faction($0, in: state) == winner } ?? false }) else { throw GameError("指定胜者不属于参战阵营。") }
            }
            try finish(winner: winner, byScore: byScore)
        case .refillExploration:
            guard state.phase == .exploration else { throw GameError("只在探索时手动补足行动点。") }
            for id in state.players.map(\.id) { var actor = try unit(id); try GameRules.refill(&actor, catalog: catalog); state.units[id] = actor }
        }
        try checkOutcome()
        if let current = state.battle?.current, let actor = state.units[current], !actor.isAlive || actor.ap == 0 {
            state.battle?.acted.insert(current); state.battle?.current = nil
        }
        if state.battle != nil && state.battle?.current == nil &&
            !state.pauseReasons.contains(.allPlayersDown) && !state.pauseReasons.contains(.noSurvivors) { try nextActor() }
    }

    mutating func start(kind: BattleKind, monsters: [String]) throws {
        guard state.phase == .exploration, state.battle == nil else { throw GameError("新战斗应从探索阶段开始。") }
        let playerIDs = state.players.map(\.id)
        var participants = playerIDs
        if kind == .pve {
            guard !monsters.isEmpty, Set(monsters).count == monsters.count else { throw GameError("PVE需要有效的敌人列表。") }
            for id in monsters { let enemy = try unit(id); guard enemy.kind == .monster && enemy.isAlive else { throw GameError("战败怪物不能自动重新加入。") } }
            participants += monsters
        } else {
            guard monsters.isEmpty else { throw GameError("PVP不加入怪物。") }
            let alive = state.players.filter(\.isAlive)
            let factions = Set(alive.map { kind == .freeForAll ? $0.id : $0.teamID ?? $0.id })
            guard factions.count >= 2 else { throw GameError("PVP至少需要两个存活阵营。") }
        }
        var initiatives: [Initiative] = []
        for id in participants { initiatives.append(Initiative(unitID: id, value: try roll(DiceFormula(sides: 20), source: "initiative").total)) }
        let queue = try orderedInitiatives(initiatives)
        for id in participants {
            var actor = try unit(id); actor.active = true; actor.canActFromRound = 1; actor.skillUses = [:]
            try GameRules.refill(&actor, catalog: catalog); state.units[id] = actor
            if actor.kind == .monster { state.map.revealed.insert(actor.nodeID) }
        }
        state.phase = kind == .pve ? .pve : kind == .teamPvp ? .teamPvp : .freeForAll
        state.battle = BattleState(kind: kind, queue: queue, initiatives: initiatives)
        state.lastOutcome = nil; state.remainingSeconds = catalog.rules.decisionSeconds
        state.pauseReasons.remove(.allPlayersDown); state.pauseReasons.remove(.noSurvivors)
        events.append(GameEvent("battleStarted", detail: kind.rawValue))
    }
    mutating func orderedInitiatives(_ entries: [Initiative]) throws -> [String] {
        var ordered: [String] = []
        for value in Set(entries.map(\.value)).sorted(by: >) {
            var group = entries.filter { $0.value == value }.map(\.unitID).sorted()
            if group.count > 1 {
                for index in stride(from: group.count - 1, through: 1, by: -1) {
                    let selected = try state.random.next(upperBound: index + 1) - 1
                    group.swapAt(index, selected)
                    events.append(GameEvent("initiativeTie", amount: selected, detail: "\(index + 1)"))
                }
            }
            ordered += group
        }
        return ordered
    }
    mutating func join(_ id: String) throws {
        guard let battle = state.battle, battle.kind == .pve else { throw GameError("仅PVE允许中途加入怪物。") }
        var enemy = try unit(id)
        guard enemy.kind == .monster, enemy.isAlive, !battle.queue.contains(id) else { throw GameError("怪物不可加入或已经参战。") }
        let initiative = try roll(DiceFormula(sides: 20), source: "initiative")
        enemy.active = true; enemy.canActFromRound = try checkedAdd(battle.round, 1); enemy.skillUses = [:]
        try GameRules.refill(&enemy, catalog: catalog); state.units[id] = enemy
        let entry = Initiative(unitID: id, value: initiative.total)
        // Keep existing tie order; randomize the new member's position only within its tie group.
        var queue = battle.queue
        let values = Dictionary(uniqueKeysWithValues: battle.initiatives.map { ($0.unitID, $0.value) })
        let same = queue.indices.filter { values[queue[$0]] == entry.value }
        let insertion: Int
        if let first = same.first { insertion = first + (try state.random.next(upperBound: same.count + 1) - 1) }
        else { insertion = queue.firstIndex(where: { (values[$0] ?? 0) < entry.value }) ?? queue.count }
        queue.insert(id, at: insertion)
        state.battle?.queue = queue; state.battle?.initiatives.append(entry)
        state.map.revealed.insert(enemy.nodeID)
        events.append(GameEvent("monsterJoined", target: id, amount: enemy.canActFromRound))
    }

    mutating func move(actors: [String], path: [Int]) throws {
        let (travelers, stops, triggersEncounters) = try movementPlan(actors: actors, path: path)
        for id in actors { try spend(id, cost: stops.count) }
        for node in stops {
            for id in actors { state.units[id]?.nodeID = node }
            if travelers[0].kind == .player { state.map.revealed.insert(node) }
            if travelers[0].kind == .player, let index = state.map.nodes.firstIndex(where: { $0.id == node }), let reward = state.map.nodes[index].reward,
               !state.map.nodes[index].rewardCompleted {
                try rewardActors(actors, reward: ResourceReward(coins: reward.coins, score: reward.score, items: reward.items), source: "nodeReward")
                state.map.nodes[index].rewardCompleted = true
            }
        }
        let encountered = triggersEncounters ? state.units.values.filter { $0.kind == .monster && $0.isAlive && !$0.active && $0.nodeID == stops.last }.map(\.id).sorted() : []
        if !encountered.isEmpty {
            if state.battle == nil { try start(kind: .pve, monsters: encountered) }
            else { for id in encountered { try join(id) } }
        }
        state.remainingSeconds = catalog.rules.decisionSeconds
        events.append(GameEvent("move", actor: actors.first, amount: stops.count, detail: stops.map(String.init).joined(separator: "→")))
    }

    mutating func attack(actor id: String, target targetID: String) throws {
        let (_, target, attack, stats) = try attackPlan(actor: id, target: targetID)
        if target.kind == .monster && !target.active { try join(targetID) }
        try spend(id, cost: 1)
        let rolled = try roll(attack.dice, source: "damage")
        let amount = max(0, try checkedAdd(rolled.total, stats.damage))
        let down = try damage(targetID, amount: amount, instant: rolled.naturalTwenty, actor: id)
        try rewardDefeats(down ? [targetID] : [], killer: id)
        state.remainingSeconds = catalog.rules.decisionSeconds
    }

    func targets(actor: GameUnit, skill: SkillDefinition, target: ActionTarget?) throws -> [String] {
        switch skill.target {
        case .selfOnly:
            if let target, target != .unit(actor.id) { throw GameError("该技能只能对自己使用。") }
            return [actor.id]
        case .enemy, .ally:
            guard case .unit(let id) = target, let selected = state.units[id], selected.isAlive else { throw GameError("技能需要有效的存活单体目标。") }
            let legal = skill.target == .enemy ? GameRules.enemies(actor, selected, in: state) : actor.id != id && GameRules.allies(actor, selected, in: state)
            guard legal else { throw GameError("技能目标阵营不合法。") }; return [id]
        case .enemiesAtNode, .alliesAtNode:
            guard case .node(let node) = target, state.map.nodes.contains(where: { $0.id == node }) else { throw GameError("技能需要指定一个地图节点。") }
            let selected = state.units.values.filter { unit in
                unit.isAlive && unit.nodeID == node && (skill.target == .enemiesAtNode ? GameRules.enemies(actor, unit, in: state) : GameRules.allies(actor, unit, in: state))
            }.map(\.id).sorted()
            guard !selected.isEmpty else { throw GameError("目标节点没有合法对象。") }; return selected
        }
    }
    mutating func cast(actor id: String, skillID: String, target: ActionTarget?) throws {
        let (actor, skill, selected, stats) = try castPlan(actor: id, skillID: skillID, target: target)
        for targetID in selected where state.units[targetID]?.kind == .monster && state.units[targetID]?.active == false { try join(targetID) }
        try spend(id, cost: skill.cost)
        state.units[id]?.skillUses[skillID, default: 0] += 1
        if actor.kind == .monster && skill.oncePerTurn { state.battle?.onceSkillsThisTurn.insert(skillID) }
        var defeated: [String] = []
        for effect in skill.effects {
            let ids = effect.scope == .caster ? [id] : selected
            if effect.kind == .damage {
                guard let formula = effect.dice else { throw GameError("伤害效果缺少骰子。") }
                let rolled = try roll(formula, source: "damage")
                let amount = max(0, try checkedAdd(rolled.total, effect.amount, stats.damage))
                for targetID in ids { if try damage(targetID, amount: amount, instant: rolled.naturalTwenty, actor: id) { defeated.append(targetID) } }
            } else {
                let rolled = try effect.dice.map { try roll($0, source: effect.kind.rawValue).total } ?? 0
                let amount = max(0, try checkedAdd(effect.amount, rolled))
                for targetID in ids {
                    switch effect.kind {
                    case .heal: try heal(targetID, amount: amount, actor: id)
                    case .shield: try shield(targetID, amount: amount, actor: id)
                    case .damageBuff: try buff(targetID, amount: amount, rounds: effect.rounds, actor: id)
                    case .damage: break
                    }
                }
            }
        }
        try rewardDefeats(Array(Set(defeated)).sorted(), killer: id)
        state.remainingSeconds = catalog.rules.decisionSeconds
        events.append(GameEvent("skill", actor: id, amount: 1, detail: skillID))
    }

    mutating func damage(_ id: String, amount: Int, instant: Bool, actor: String?) throws -> Bool {
        var target = try unit(id)
        guard target.isAlive else { return false }
        let oldHealth = target.health, oldShield = target.shield
        if instant { target.health = 0 }
        else {
            let absorbed = min(target.shield, amount); target.shield -= absorbed
            target.health = max(0, target.health - (amount - absorbed))
        }
        if !target.isAlive { target.shield = 0; target.damageBuff = nil }
        state.units[id] = target
        events.append(GameEvent(instant ? "naturalTwenty" : "damage", actor: actor, target: id, amount: oldHealth - target.health,
                                detail: "护盾减少\(oldShield - target.shield)"))
        return !target.isAlive
    }
    mutating func heal(_ id: String, amount: Int, actor: String?) throws {
        var target = try unit(id); guard target.isAlive else { return }
        let maximum = try GameRules.attributes(target, catalog: catalog).maximumHealth
        let restored = min(amount, maximum - target.health)
        target.health += restored; state.units[id] = target
        events.append(GameEvent("heal", actor: actor, target: id, amount: restored))
    }
    mutating func shield(_ id: String, amount: Int, actor: String?) throws {
        var target = try unit(id); guard target.isAlive else { return }
        let added = max(0, amount - target.shield); target.shield = max(target.shield, amount); state.units[id] = target
        events.append(GameEvent("shield", actor: actor, target: id, amount: added))
    }
    mutating func buff(_ id: String, amount: Int, rounds: Int, actor: String?) throws {
        var target = try unit(id); guard target.isAlive, target.damageBuff.map({ amount >= $0.amount }) ?? true else { return }
        guard rounds > 0 else { throw GameError("增益持续轮数无效。") }
        target.damageBuff = DamageBuff(amount: amount, roundsLeft: rounds, appliedRound: state.battle?.round ?? 0)
        state.units[id] = target; events.append(GameEvent("buff", actor: actor, target: id, amount: amount, detail: "\(rounds)轮"))
    }

    mutating func useItem(actor id: String, itemID: String, target targetID: String) throws {
        let item = try itemPlan(actor: id, itemID: itemID, target: targetID)
        try spend(id, cost: 1); try consume(id, itemID: itemID)
        try heal(targetID, amount: item.heal, actor: id); try shield(targetID, amount: item.shield, actor: id)
        state.remainingSeconds = catalog.rules.decisionSeconds
    }
    mutating func consume(_ id: String, itemID: String) throws {
        var actor = try unit(id)
        guard let count = actor.inventory[itemID], count > 0 else { throw GameError("个人背包缺少所需道具。") }
        if count == 1 { actor.inventory.removeValue(forKey: itemID) } else { actor.inventory[itemID] = count - 1 }
        state.units[id] = actor; events.append(GameEvent("item", actor: id, target: id, amount: -1, detail: itemID))
    }
    mutating func rescue(actor id: String, target targetID: String) throws {
        try rescuePlan(actor: id, target: targetID)
        try spend(id, cost: catalog.rules.rescueCost); try consume(id, itemID: catalog.rules.revivalStone)
        try revive(targetID)
        try addScore(id, amount: catalog.rules.rescueScore, source: "rescue", target: targetID)
        state.remainingSeconds = catalog.rules.decisionSeconds
    }
    mutating func revive(_ id: String) throws {
        var target = try unit(id)
        guard target.kind == .player, !target.isAlive else { throw GameError("复活目标必须为倒地玩家。") }
        let maximum = try GameRules.attributes(target, catalog: catalog).maximumHealth
        target.health = maximum / 2 + maximum % 2
        target.shield = 0; target.damageBuff = nil
        target.canActFromRound = try state.battle.map { try checkedAdd($0.round, 1) } ?? 1
        state.units[id] = target; events.append(GameEvent("revive", target: id, amount: target.health))
    }
    mutating func setHealth(_ id: String, value: Int, killer: String?) throws {
        var target = try unit(id)
        let maximum = try GameRules.attributes(target, catalog: catalog).maximumHealth
        guard (0...maximum).contains(value) else { throw GameError("当前生命必须在0与最大生命之间。") }
        if let killer { guard try unit(killer).kind == .player else { throw GameError("奖励归属必须为玩家角色。") } }
        let wasAlive = target.isAlive
        target.health = value
        if value == 0 { target.shield = 0; target.damageBuff = nil }
        if !wasAlive && value > 0 { target.canActFromRound = try state.battle.map { try checkedAdd($0.round, 1) } ?? 1 }
        state.units[id] = target
        if value == 0 && (wasAlive || (target.kind == .monster && !target.defeatRewarded)) { try rewardDefeats([id], killer: killer) }
        events.append(GameEvent("teacherHealth", target: id, amount: value))
    }
    mutating func rewardActors(_ ids: [String], reward: ResourceReward, source: String = "teacherReward") throws {
        guard !ids.isEmpty, Set(ids).count == ids.count else { throw GameError("请选择不同的奖励对象。") }
        for (id, count) in reward.items { _ = try catalog.item(id); guard count > 0 else { throw GameError("物品奖励数量必须为正。") } }
        for id in ids {
            var actor = try unit(id)
            guard actor.kind == .player else { throw GameError("课堂奖励对象须为玩家。") }
            let maximum = try GameRules.attributes(actor, catalog: catalog).maximumAP
            let nextAP = try checkedAdd(actor.ap, reward.ap), coins = try checkedAdd(actor.coins, reward.coins)
            guard nextAP >= 0, coins >= 0 else { throw GameError("不能把行动点或金币调整为负数。") }
            let oldAP = actor.ap; actor.ap = min(maximum, nextAP); actor.coins = coins
            actor.score = try checkedAdd(actor.score, reward.score)
            for (item, count) in reward.items { actor.inventory[item] = try checkedAdd(actor.inventory[item] ?? 0, count) }
            state.units[id] = actor
            events.append(GameEvent(source, actor: id, target: id, amount: reward.coins, detail: "金币；行动点实际变化\(actor.ap - oldAP)"))
            if reward.score != 0 { events.append(GameEvent("score", actor: id, target: id, amount: reward.score, detail: source)) }
        }
    }
    mutating func addScore(_ id: String, amount: Int, source: String, target: String?) throws {
        var actor = try unit(id); actor.score = try checkedAdd(actor.score, amount); state.units[id] = actor
        events.append(GameEvent("score", actor: id, target: target, amount: amount, detail: source))
    }
    mutating func rewardDefeats(_ ids: [String], killer: String?) throws {
        guard let killer else { return }
        let credited = try unit(killer)
        guard credited.kind == .player else { return }
        for id in ids {
            var defeated = try unit(id)
            if defeated.kind == .monster {
                guard !defeated.defeatRewarded else { continue }
                let definition = try catalog.monster(defeated.templateID)
                // Marking, all rolls and the complete payout belong to the same candidate state.
                defeated.defeatRewarded = true; state.units[id] = defeated
                try addScore(killer, amount: definition.score, source: definition.boss ? "bossKill" : "monsterKill", target: id)
                for drop in definition.drops {
                    let chance: Int?
                    if drop.percent == 0 || drop.percent == 100 { chance = nil }
                    else { chance = try state.random.next(upperBound: 100) }
                    let won = drop.percent == 100 || chance.map({ $0 <= drop.percent }) == true
                    events.append(GameEvent("dropCheck", actor: killer, target: id, amount: chance ?? drop.percent,
                                            detail: "\(drop.itemID ?? "coins"): \(won ? "获得" : "未获得")"))
                    guard won else { continue }
                    var receiver = try unit(killer)
                    if let item = drop.itemID { receiver.inventory[item] = try checkedAdd(receiver.inventory[item] ?? 0, drop.count) }
                    else { receiver.coins = try checkedAdd(receiver.coins, drop.coins) }
                    state.units[killer] = receiver
                    events.append(GameEvent("drop", actor: killer, target: id, amount: drop.itemID == nil ? drop.coins : drop.count, detail: drop.itemID ?? "coins"))
                }
            } else if state.battle?.kind == .teamPvp || state.battle?.kind == .freeForAll {
                guard GameRules.enemies(credited, defeated, in: state) else { continue }
                try addScore(killer, amount: catalog.rules.pvpKnockoutScore, source: "pvpKnockout", target: id)
            }
        }
    }
    mutating func equip(_ id: String, slot: ItemSlot, itemID: String?) throws {
        guard state.phase == .exploration, state.battle == nil else { throw GameError("战斗中不能换装。") }
        var actor = try unit(id)
        guard actor.kind == .player else { throw GameError("只给玩家换装。") }
        if let itemID {
            guard try catalog.item(itemID).slot == slot, (actor.inventory[itemID] ?? 0) > 0 else { throw GameError("装备槽位或背包数量不满足。") }
            if actor.inventory[itemID] == 1 { actor.inventory.removeValue(forKey: itemID) }
            else { actor.inventory[itemID]! -= 1 }
        }
        if let old = actor.equipment[slot] { actor.inventory[old] = try checkedAdd(actor.inventory[old] ?? 0, 1) }
        actor.equipment[slot] = itemID
        let stats = try GameRules.attributes(actor, catalog: catalog)
        actor.health = min(actor.health, stats.maximumHealth); actor.ap = min(actor.ap, stats.maximumAP)
        state.units[id] = actor
        events.append(GameEvent("equipment", target: id, detail: itemID ?? "卸下\(slot.rawValue)"))
    }

    mutating func checkOutcome() throws {
        guard let battle = state.battle else { return }
        let players = state.players.filter(\.isAlive)
        if battle.kind == .pve {
            let enemies = battle.queue.compactMap { state.units[$0] }.filter { $0.kind == .monster && $0.isAlive }
            if enemies.isEmpty { try finish(winner: "players", byScore: false); return }
            if players.isEmpty { state.pauseReasons.insert(.allPlayersDown); state.battle?.current = nil }
            else { state.pauseReasons.remove(.allPlayersDown) }
        } else {
            let factions = Set(players.map { GameRules.faction($0, in: state) })
            if factions.count == 1 { try finish(winner: factions.first, byScore: false); return }
            if factions.isEmpty { state.pauseReasons.insert(.noSurvivors); state.battle?.current = nil }
            else { state.pauseReasons.remove(.noSurvivors) }
        }
    }
    mutating func finish(winner: String?, byScore: Bool) throws {
        guard let battle = state.battle else { return }
        let individual = GameRules.rankings(state.players.map { ($0.id, $0.name, $0.score) })
        let teams = try GameRules.teamRankings(state)
        var winners = winner.map { [$0] } ?? []
        if byScore {
            let participantFactions = Set(state.players.map { GameRules.faction($0, in: state) })
            let ranking = battle.kind == .teamPvp ? teams : individual
            let competing = ranking.filter { participantFactions.contains($0.id) }
            if let first = competing.first { winners = competing.filter { $0.score == first.score }.map(\.id) }
        }
        state.lastOutcome = BattleOutcome(kind: battle.kind, winners: winners, scoreSettlement: byScore,
                                          personalRanking: individual, teamRanking: teams)
        for id in state.units.keys {
            state.units[id]?.damageBuff = nil
            if state.units[id]?.kind == .monster { state.units[id]?.active = false }
        }
        state.battle = nil; state.phase = battle.kind == .pve ? .exploration : .settlement
        state.pauseReasons.remove(.allPlayersDown); state.pauseReasons.remove(.noSurvivors)
        events.append(GameEvent("battleEnded", detail: winners.joined(separator: ",")))
    }
    mutating func nextActor() throws {
        guard var battle = state.battle else { return }
        func eligible(_ id: String, battle: BattleState, units: [String: GameUnit]) -> Bool {
            guard let unit = units[id] else { return false }
            return unit.isAlive && unit.ap > 0 && unit.canActFromRound <= battle.round && !battle.acted.contains(id)
        }
        if let current = battle.queue.first(where: { eligible($0, battle: battle, units: state.units) }) {
            battle.current = current; battle.onceSkillsThisTurn = []; state.battle = battle
            state.remainingSeconds = catalog.rules.decisionSeconds; return
        }
        // Nobody may act twice in a round. Dead players still receive their normal refill.
        let endedRound = battle.round
        for id in state.units.keys {
            if var buff = state.units[id]?.damageBuff, buff.appliedRound != endedRound {
                buff.roundsLeft -= 1
                state.units[id]?.damageBuff = buff.roundsLeft > 0 ? buff : nil
            }
        }
        battle.round = try checkedAdd(battle.round, 1); battle.acted = []; battle.onceSkillsThisTurn = []
        for id in battle.queue { var actor = try unit(id); try GameRules.refill(&actor, catalog: catalog); state.units[id] = actor }
        guard let current = battle.queue.first(where: { eligible($0, battle: battle, units: state.units) }) else { throw GameError("新轮没有可行动单位，队列需要教师处理。") }
        battle.current = current; state.battle = battle; state.remainingSeconds = catalog.rules.decisionSeconds
        events.append(GameEvent("round", amount: battle.round))
    }
}
