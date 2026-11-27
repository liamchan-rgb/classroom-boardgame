import Foundation
import ClassroomGameCore

public struct MeadowEquipmentComparison:Codable,Equatable {
    public let before:GameUnit,after:GameUnit
    public let beforeStats:Attributes,afterStats:Attributes
    public let movementBefore:Double,movementAfter:Double
    public let attackBefore:String,attackAfter:String
    public let skillsBefore:[String],skillsAfter:[String]
    public var summary:String {
        "生命 \(before.health)/\(beforeStats.maximumHealth) → \(after.health)/\(afterStats.maximumHealth)\n额外伤害 ＋\(beforeStats.damage) → ＋\(afterStats.damage)\n基础行动 \(beforeStats.baseAP) → \(afterStats.baseAP)\n行动上限 \(beforeStats.maximumAP) → \(afterStats.maximumAP)\n当前行动 \(before.ap) → \(after.ap)\n地图移动上限 \(Int(ceil(movementBefore))) → \(Int(ceil(movementAfter)))\n普攻 \(attackBefore) → \(attackAfter)\n换装后技能：\(skillsAfter.joined(separator:"、"))"
    }

    /// Expected single-roll average damage of a weapon dice formula (for clear upgrade vs downgrade indication).
    public static func expectedDamage(_ dice:DiceFormula)->Double {
        Double(dice.count)*(Double(dice.sides)+1.0)/2.0+Double(dice.flat)
    }

    /// Overall score delta between `before` and `after` (positive = net upgrade, negative = net downgrade, 0 = sidegrade).
    public func upgradeScore(catalog:GameCatalog)->Double {
        let atkBefore=(try? GameRules.attack(before,catalog:catalog))
        let atkAfter=(try? GameRules.attack(after,catalog:catalog))
        let avgBefore=atkBefore.map{Self.expectedDamage($0.dice)} ?? 0
        let avgAfter=atkAfter.map{Self.expectedDamage($0.dice)} ?? 0
        let rangeDelta=Double((atkAfter?.range ?? 0)-(atkBefore?.range ?? 0))
        let hpDelta=Double(afterStats.maximumHealth-beforeStats.maximumHealth)
        let dmgDelta=Double(afterStats.damage-beforeStats.damage)
        let baseAPDelta=Double(afterStats.baseAP-beforeStats.baseAP)
        let maxAPDelta=Double(afterStats.maximumAP-beforeStats.maximumAP)
        let skillDelta=Double(skillsAfter.count-skillsBefore.count)
        return (avgAfter-avgBefore)*2.4 + dmgDelta*2.2 + hpDelta*0.45 + baseAPDelta*3.0 + maxAPDelta*1.2 + rangeDelta*1.5 + skillDelta*4.0
    }
}

public extension MeadowCampaignSession {
    func equipmentComparison(actor:String,slot:ItemSlot,item:String?)throws->MeadowEquipmentComparison {
        let after=try candidateEquipment(actor:actor,slot:slot,item:item),before=engine.state.units[actor]!,catalog=engine.catalog
        return try buildComparison(actor:actor,before:before,after:after,catalog:catalog)
    }

    /// Simulates equipping any catalog item on `actor` — even if `actor` does not yet own it (used by Shop buyer preview).
    func simulatedEquipmentComparison(actor:String,slot:ItemSlot,item:String?)throws->MeadowEquipmentComparison {
        guard let before=engine.state.units[actor],before.kind == .player else{throw GameError("请选择队伍成员。")}
        let catalog=engine.catalog
        if before.equipment[slot]==item {
            return try buildComparison(actor:actor,before:before,after:before,catalog:catalog)
        }
        var simState=engine.state
        if let item {
            let def=try catalog.item(item)
            guard def.slot==slot else{throw GameError("该物品无法装备在此槽位。")}
            var u=simState.units[actor]!
            if (u.inventory[item] ?? 0) <= 0 { u.inventory[item]=1 }
            simState.units[actor]=u
        }
        let clone=try GameEngine(catalog:catalog,state:simState)
        try clone.apply(.equip(unit:actor,slot:slot,item:item))
        return try buildComparison(actor:actor,before:before,after:clone.state.units[actor]!,catalog:catalog)
    }

    private func buildComparison(actor:String,before:GameUnit,after:GameUnit,catalog:GameCatalog)throws->MeadowEquipmentComparison {
        var archive=engine.archive;archive.state.units[actor]=after
        func attack(_ unit:GameUnit)->String {
            guard let a=try? GameRules.attack(unit,catalog:catalog) else{return "无武器"}
            return "\(a.dice.count)D\(a.dice.sides)"+(a.dice.flat==0 ? "":String(format:"%+d",a.dice.flat))+" · 射程\(a.range)"
        }
        func skills(_ unit:GameUnit)throws->[String] {try GameRules.skills(unit,catalog:catalog).map{try catalog.skill($0).name}}
        return try .init(before:before,after:after,beforeStats:GameRules.attributes(before,catalog:catalog),afterStats:GameRules.attributes(after,catalog:catalog),movementBefore:movementCapacity,movementAfter:MeadowMovementRules.capacity(archive),attackBefore:attack(before),attackAfter:attack(after),skillsBefore:skills(before),skillsAfter:skills(after))
    }
}
