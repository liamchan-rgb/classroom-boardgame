import Foundation

/// Display-only values; not part of GameArchive or the on-disk format.
public struct PublicSkillDisplay: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var cost: Int
    public var detail: String
    public var available: Bool? = nil
    public var unavailableReason: String? = nil
}
public struct PublicItemDisplay: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var quantity: Int
    public var detail: String = ""
    public var available: Bool? = nil
    public var unavailableReason: String? = nil
}
public struct PublicTurnDetails: Codable, Equatable {
    public var unitID: String
    public var className: String
    public var skills: [PublicSkillDisplay]
    public var items: [PublicItemDisplay]
    public init(unit: GameUnit, catalog: GameCatalog) throws {
        unitID = unit.id
        className = try catalog.playerClass(unit.templateID).name
        skills = try GameRules.skills(unit, catalog: catalog).map { id in
            let skill = try catalog.skill(id)
            let effects = skill.effects.map { effect -> String in
                let scope = effect.scope == .caster ? "自身" : "目标"
                switch effect.kind {
                case .damage: return scope + "伤害" + (effect.dice?.label ?? "") + (effect.amount == 0 ? "" : "+\(effect.amount)")
                case .heal: return scope + "恢复\(effect.amount)生命"
                case .shield: return scope + "护盾\(effect.amount)"
                case .damageBuff: return scope + "伤害+\(effect.amount)·\(effect.rounds)轮"
                }
            }.joined(separator: "；")
            let target: String
            switch skill.target {
            case .selfOnly: target = "自身"
            case .enemy: target = "单敌"
            case .ally: target = "队友"
            case .enemiesAtNode: target = "节点全部敌人"
            case .alliesAtNode: target = "节点全部队友"
            }
            let stage = skill.stage == .battle ? "战斗" : skill.stage == .exploration ? "探索" : "通用"
            let uses = skill.uses.map { " · 余\(max(0,$0-(unit.skillUses[id] ?? 0)))次" } ?? " · 不限次"
            return PublicSkillDisplay(id:id, name:skill.name, cost:skill.cost,
                                      detail:"\(target) · 射程\(skill.range) · \(stage)\(uses)\n\(effects)")
        }
        items = unit.inventory.keys.sorted().compactMap { id in
            guard let count = unit.inventory[id], count > 0, let item = try? catalog.item(id) else { return nil }
            return PublicItemDisplay(id:id,name:item.name,quantity:count)
        }
    }
}
public struct UnitPresentation: Codable, Equatable, Identifiable {
    public var id: String
    public var motion: String
    public var effects: [String]
}
public struct CommittedPresentation: Codable, Equatable, Identifiable {
    public var id: String
    public var start: Date
    public var text: String
    public var units: [UnitPresentation]
    public var dice: [DiceResult]
    public var mapMoves: [PublicMapMove] = []
    public var opensBattleAfterArrival: Bool = false
    public var end: Date { start.addingTimeInterval(1.3) }
    public func isVisible(at date: Date) -> Bool { date >= start && date < end }
}

/// One group per committed receipt. Restore seeds the ledger; views never consume
/// history or call an engine. Absolute timestamps prevent reconnect/onAppear replay.
public struct PresentationLedger {
    private var consumed: Set<String> = []
    public private(set) var pending: [CommittedPresentation] = []
    public init() {}
    public mutating func suppressHistory(_ history: [OperationReceipt]) {
        consumed.formUnion(history.map { $0.after.gameID + ":" + $0.id })
        pending = []
    }
    @discardableResult public mutating func removeExpired(at date:Date) -> Bool {
        let count = pending.count; pending.removeAll { $0.end <= date }; return count != pending.count
    }
    public mutating func clearVisible() { pending = [] }
    @discardableResult
    public mutating func submit(_ receipt: OperationReceipt, catalog: GameCatalog, now: Date) throws -> CommittedPresentation? {
        let key = receipt.after.gameID + ":" + receipt.id
        guard consumed.insert(key).inserted else { return nil }
        pending.removeAll { $0.end <= now }
        let snapshot = try receipt.after.publicSnapshot(catalog:catalog)
        let visible = Set(snapshot.units.map(\.id))
        var rows: [String:UnitPresentation] = [:]
        func mark(_ id: String?, motion: String? = nil, effect: String? = nil) {
            guard let id, visible.contains(id) else { return }
            var row = rows[id] ?? UnitPresentation(id:id,motion:"idle",effects:[])
            if let motion { row.motion = motion }
            if let effect, !row.effects.contains(effect) { row.effects.append(effect) }
            rows[id] = row
        }
        for e in receipt.events {
            switch e.kind {
            case "move": mark(e.actor,motion:"move")
            case "damage": mark(e.actor,motion:"attack"); mark(e.target,motion:"hurt",effect:"impact")
            case "naturalTwenty": mark(e.actor,motion:"attack"); mark(e.target,motion:"down",effect:"natural20")
            case "heal": if e.amount > 0 { mark(e.target,effect:"heal") }
            case "shield": if e.amount > 0 { mark(e.target,effect:"shield") }
            case "revive": mark(e.target,motion:"revive",effect:"revive")
            case "skill":
                // Style chosen from the actual committed effect definition, not a localized name.
                if let skill = try? catalog.skill(e.detail) {
                    mark(e.actor,motion:"attack",effect:skill.effects.contains { $0.kind == .damage } ? (skill.effects.contains { $0.dice?.sides == 20 } ? "flame" : "projectile") : "rune")
                }
            default: break
            }
        }
        for unit in snapshot.units where unit.health == 0 && receipt.before.units[unit.id]?.isAlive == true { mark(unit.id,motion:"down") }
        // Actual deltas only; no AP leaks and no guessed teacherReward amount.
        var changes: [String] = []
        for unit in snapshot.units {
            guard let before = receipt.before.units[unit.id], let after = receipt.after.units[unit.id] else { continue }
            var deltas: [String] = []
            for (label,value) in [("生命",after.health-before.health),("护盾",after.shield-before.shield),("金币",after.coins-before.coins),("积分",after.score-before.score)] where value != 0 {
                deltas.append(label + (value > 0 ? "+" : "") + String(value))
            }
            for id in Set(before.inventory.keys).union(after.inventory.keys).sorted() {
                let delta = (after.inventory[id] ?? 0)-(before.inventory[id] ?? 0)
                if delta != 0, let item = try? catalog.item(id) { deltas.append(item.name + (delta > 0 ? "+" : "") + String(delta)) }
            }
            if !deltas.isEmpty { changes.append(unit.name + "：" + deltas.joined(separator:"、")) }
        }
        let dice = receipt.dice.filter { $0.source != "initiative" }
        if dice.contains(where: \.naturalTwenty) { changes.insert("自然20！",at:0) }
        guard !changes.isEmpty || !rows.isEmpty || !dice.isEmpty else { return nil }
        var event = CommittedPresentation(id:key,start:max(now,pending.last?.end ?? now),text:changes.joined(separator:"；"),units:rows.values.sorted { $0.id < $1.id },dice:dice)
        let nodes = Dictionary(uniqueKeysWithValues:snapshot.nodes.map { ($0.id,MapPoint(x:$0.x,y:$0.y)) })
        // Parse the engine's committed stops, never the unsubmitted/requested path.
        if let move = receipt.events.first(where: { $0.kind == "move" }) {
            let stops = move.detail.split(separator:"→").compactMap { Int($0) }
            let movingIDs: Set<String>
            if case .move(let actors,_) = receipt.command { movingIDs = Set(actors) }
            else { movingIDs = Set([move.actor].compactMap { $0 }) }
            let beforeVisible = Set(try receipt.before.publicSnapshot(catalog:catalog).units.map(\.id))
            for unit in snapshot.units {
                guard movingIDs.contains(unit.id), beforeVisible.contains(unit.id), let before = receipt.before.units[unit.id],
                      let first = nodes[before.nodeID], stops.last == unit.nodeID else { continue }
                let points = [first] + stops.compactMap { nodes[$0] }
                guard points.count == stops.count+1 else { continue }
                event.mapMoves.append(PublicMapMove(unitID:unit.id,points:points))
            }
            event.opensBattleAfterArrival = receipt.before.battle == nil && receipt.after.battle != nil && !event.mapMoves.isEmpty
        }
        pending.append(event)
        return event
    }
    /// Exclude only actual presentation intervals from the student decision clock.
    public func elapsedDecisionTime(from: Date, to: Date) -> Double {
        let excluded = pending.reduce(0.0) { total,e in total + max(0,min(to,e.end).timeIntervalSince(max(from,e.start))) }
        return max(0,to.timeIntervalSince(from)-excluded)
    }
}
