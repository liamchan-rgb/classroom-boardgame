import Foundation

/// Teacher-set challenge. Only monsters change: their maximum health is scaled and a flat bonus is added to
/// every attack and damage skill they use. Players, items, rewards and prices are untouched.
/// `nil` in a save means the original numbers (`normal`).
public enum GameDifficulty: String, Codable, CaseIterable, Equatable {
    case easy, normal, hard, nightmare
    public var title: String {
        switch self { case .easy: return "简单"; case .normal: return "标准"; case .hard: return "困难"; case .nightmare: return "噩梦" }
    }
    /// Monster maximum health, in percent of the catalog value.
    public var healthPercent: Int {
        switch self { case .easy: return 75; case .normal: return 100; case .hard: return 150; case .nightmare: return 200 }
    }
    /// Flat damage added to monster attacks and damage skills (the engine never deals below 0).
    public var damageBonus: Int {
        switch self { case .easy: return -1; case .normal: return 0; case .hard: return 2; case .nightmare: return 4 }
    }
    public var summary: String {
        "怪物生命 \(healthPercent)% · 伤害 \(damageBonus >= 0 ? "+" : "")\(damageBonus)"
    }
    /// The monster's attributes at this difficulty, from its catalog attributes.
    public func monsterAttributes(_ base: Attributes) -> Attributes {
        var value = base
        value.maximumHealth = max(1, (base.maximumHealth * healthPercent + 50) / 100)
        value.damage = base.damage + damageBonus
        return value
    }
}

public extension GameState {
    var effectiveDifficulty: GameDifficulty { difficulty ?? .normal }
}

extension Evaluation {
    /// Re-derives every monster from its catalog numbers at the new level. Wounded monsters keep the same share
    /// of their health; defeated ones stay defeated. Only outside battle.
    mutating func setDifficulty(_ level: GameDifficulty) throws {
        guard state.battle == nil else { throw GameError("请在战斗外调整难度。") }
        for (id, monster) in state.units where monster.kind == .monster {
            var unit = monster
            let old = try GameRules.attributes(unit, catalog: catalog).maximumHealth
            unit.baseAttributes = level.monsterAttributes(try catalog.monster(unit.templateID).attributes)
            let new = try GameRules.attributes(unit, catalog: catalog).maximumHealth
            if unit.isAlive { unit.health = min(new, max(1, (unit.health * new + old / 2) / max(1, old))) }
            state.units[id] = unit
        }
        state.difficulty = level == .normal ? nil : level
        events.append(GameEvent("difficulty", detail: level.rawValue))
    }
    /// A freshly placed monster at the journey's difficulty.
    func scaledMonster(_ monster: GameUnit) throws -> GameUnit {
        var unit = monster
        unit.baseAttributes = state.effectiveDifficulty.monsterAttributes(try catalog.monster(unit.templateID).attributes)
        unit.health = unit.baseAttributes.maximumHealth
        return unit
    }
}
