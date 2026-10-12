import Foundation

public struct GameError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

func checkedAdd(_ values: Int...) throws -> Int {
    var total = 0
    for value in values {
        let result = total.addingReportingOverflow(value)
        guard !result.overflow else { throw GameError("数值超过可保存的整数范围。") }
        total = result.partialValue
    }
    return total
}

public struct Attributes: Codable, Equatable {
    public var maximumHealth: Int
    public var damage: Int
    public var baseAP: Int
    public var maximumAP: Int
    public var range: Int
    public init(maximumHealth: Int = 0, damage: Int = 0, baseAP: Int = 0, maximumAP: Int = 0, range: Int = 0) {
        self.maximumHealth = maximumHealth; self.damage = damage
        self.baseAP = baseAP; self.maximumAP = maximumAP; self.range = range
    }
    public func adding(_ other: Attributes) throws -> Attributes {
        try Attributes(maximumHealth: checkedAdd(maximumHealth, other.maximumHealth),
                       damage: checkedAdd(damage, other.damage), baseAP: checkedAdd(baseAP, other.baseAP),
                       maximumAP: checkedAdd(maximumAP, other.maximumAP), range: checkedAdd(range, other.range))
    }
}

public struct DiceFormula: Codable, Equatable {
    public var sides: Int
    public var count: Int
    public var flat: Int
    public init(sides: Int, count: Int = 1, flat: Int = 0) { self.sides = sides; self.count = count; self.flat = flat }
    public var label: String { "\(count)D\(sides)" + (flat == 0 ? "" : flat > 0 ? "+\(flat)" : "\(flat)") }
    func validate() throws {
        guard [4, 6, 8, 10, 12, 20].contains(sides), (1...100).contains(count) else { throw GameError("骰子种类或数量无效。") }
    }
}

public struct AttackDefinition: Codable, Equatable {
    public var dice: DiceFormula
    public var range: Int
    public init(dice: DiceFormula, range: Int) { self.dice = dice; self.range = range }
}

public enum SkillTarget: String, Codable { case selfOnly, enemy, ally, enemiesAtNode, alliesAtNode }
public enum SkillStage: String, Codable { case battle, exploration, both }
public enum EffectScope: String, Codable { case targets, caster }
public enum EffectKind: String, Codable { case damage, heal, shield, damageBuff }
public enum AICondition: String, Codable { case always, shieldEmpty, healthHalfOrLess, twoEnemiesAtNode }

public struct SkillEffect: Codable, Equatable {
    public var kind: EffectKind
    public var scope: EffectScope
    public var amount: Int
    public var rounds: Int
    public var dice: DiceFormula?
}

public struct SkillDefinition: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var cost: Int
    public var target: SkillTarget
    public var range: Int
    public var stage: SkillStage
    public var uses: Int?
    public var effects: [SkillEffect]
    public var priority: Int
    public var condition: AICondition
    public var oncePerTurn: Bool
}

public struct ClassDefinition: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var attributes: Attributes
    public var skills: [String]
}

public enum ItemSlot: String, Codable, CaseIterable { case weapon, armor, accessory }
public enum ItemKind: String, Codable { case equipment, consumable, revivalStone }

public struct ItemDefinition: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: ItemKind
    public var slot: ItemSlot?
    public var attributes: Attributes
    public var attack: AttackDefinition?
    public var purchasePrice: Int?
    public var sellPrice: Int
    public var setID: String?
    public var heal: Int
    public var shield: Int
    public var range: Int
}

public struct SetDefinition: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var items: [String]
    public var twoPieces: Attributes
    public var threePieces: Attributes
    public var skill: String
}

public struct DropDefinition: Codable, Equatable {
    public var itemID: String?
    public var coins: Int
    public var count: Int
    public var percent: Int
}

public enum EnemyStrategy: String, Codable { case nearest, lowestHealthRatio, random }
public struct MonsterDefinition: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var boss: Bool
    public var attributes: Attributes
    public var shield: Int
    public var attack: AttackDefinition
    public var strategy: EnemyStrategy
    public var skills: [String]
    public var score: Int
    public var drops: [DropDefinition]
}

public struct GlobalRules: Codable, Equatable {
    public var decisionSeconds: Double
    public var rescueCost: Int
    public var rescueScore: Int
    public var pvpKnockoutScore: Int
    public var starterWeapon: String
    public var revivalStone: String
    public var defaultRewardCoins: Int
    public var defaultRewardScore: Int
    public var mapNodeCount: Int
    public var mapDistribution: [String: Int]
}

public struct GameCatalog: Codable, Equatable {
    public var formatVersion: Int
    public var rules: GlobalRules
    public var classes: [ClassDefinition]
    public var skills: [SkillDefinition]
    public var items: [ItemDefinition]
    public var sets: [SetDefinition]
    public var monsters: [MonsterDefinition]

    public static func initial() throws -> GameCatalog {
        guard let url = Bundle.module.url(forResource: "initial-content", withExtension: "json") else {
            throw GameError("初始规则数据缺失。")
        }
        let catalog = try JSONDecoder().decode(GameCatalog.self, from: Data(contentsOf: url))
        try catalog.validate()
        return catalog
    }
    public func playerClass(_ id: String) throws -> ClassDefinition {
        guard let value = classes.first(where: { $0.id == id }) else { throw GameError("职业不存在：\(id)") }; return value
    }
    public func skill(_ id: String) throws -> SkillDefinition {
        guard let value = skills.first(where: { $0.id == id }) else { throw GameError("技能不存在：\(id)") }; return value
    }
    public func item(_ id: String) throws -> ItemDefinition {
        guard let value = items.first(where: { $0.id == id }) else { throw GameError("物品不存在：\(id)") }; return value
    }
    public func monster(_ id: String) throws -> MonsterDefinition {
        guard let value = monsters.first(where: { $0.id == id }) else { throw GameError("怪物不存在：\(id)") }; return value
    }

    public func validate() throws {
        func unique(_ ids: [String]) -> Bool { !ids.contains("") && Set(ids).count == ids.count }
        guard formatVersion == 1, unique(classes.map(\.id)), unique(skills.map(\.id)),
              unique(items.map(\.id)), unique(sets.map(\.id)), unique(monsters.map(\.id)),
              rules.decisionSeconds.isFinite, rules.decisionSeconds > 0,
              rules.rescueCost == 2, rules.rescueScore >= 0, rules.pvpKnockoutScore >= 0 else {
            throw GameError("规则版本、ID或全局参数无效。")
        }
        for value in classes {
            try Self.validateBase(value.attributes)
            guard value.skills.count == 3, Set(value.skills).count == 3 else { throw GameError("职业需要3个不同技能。") }
            for id in value.skills { _ = try skill(id) }
        }
        for value in skills {
            guard value.cost > 0, value.range >= 0, value.uses.map({ $0 >= 0 }) ?? true,
                  !value.effects.isEmpty else { throw GameError("技能配置无效：\(value.name)") }
            for effect in value.effects {
                guard effect.amount >= 0, effect.rounds >= 0 else { throw GameError("技能效果数值无效。") }
                if effect.kind == .damage { guard let dice = effect.dice else { throw GameError("伤害技能缺少骰子。") }; try dice.validate() }
                if effect.kind == .damageBuff && effect.rounds < 1 { throw GameError("增益持续时间必须至少1轮。") }
            }
        }
        for value in items {
            guard value.sellPrice >= 0, value.purchasePrice.map({ $0 >= 0 }) ?? true,
                  value.range >= 0, value.heal >= 0, value.shield >= 0,
                  (value.kind == .equipment) == (value.slot != nil) else { throw GameError("物品配置无效：\(value.name)") }
            if let attack = value.attack { try attack.dice.validate(); guard attack.range >= 0, value.slot == .weapon else { throw GameError("武器攻击配置无效。") } }
            if let setID = value.setID, !sets.contains(where: { $0.id == setID }) { throw GameError("物品引用未知套装。") }
        }
        for value in sets {
            let parts = try value.items.map(item)
            guard parts.count == 3, Set(parts.compactMap(\.slot)).count == 3,
                  parts.allSatisfy({ $0.setID == value.id && $0.purchasePrice == nil }) else { throw GameError("套装需要武器、护甲、饰品各一件。") }
            _ = try skill(value.skill)
        }
        for value in monsters {
            try Self.validateBase(value.attributes); try value.attack.dice.validate()
            guard value.shield >= 0, value.attack.range >= 0, value.score >= 0 else { throw GameError("怪物配置无效。") }
            for id in value.skills { _ = try skill(id) }
            for drop in value.drops {
                guard (0...100).contains(drop.percent), drop.coins >= 0, drop.count > 0,
                      (drop.itemID != nil) != (drop.coins > 0) else { throw GameError("掉落配置无效。") }
                if let id = drop.itemID { _ = try item(id) }
            }
        }
        guard try item(rules.starterWeapon).slot == .weapon,
              try item(rules.revivalStone).kind == .revivalStone else { throw GameError("初始武器或复活石引用无效。") }
    }
    static func validateBase(_ value: Attributes) throws {
        guard value.maximumHealth >= 1, value.baseAP >= 1, value.maximumAP >= value.baseAP,
              value.range >= 0 else { throw GameError("生命或行动点上限、基础值无效。") }
    }
}
