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
}
public extension MeadowCampaignSession {
    func equipmentComparison(actor:String,slot:ItemSlot,item:String?)throws->MeadowEquipmentComparison {
        let after=try candidateEquipment(actor:actor,slot:slot,item:item),before=engine.state.units[actor]!,catalog=engine.catalog
        var archive=engine.archive;archive.state.units[actor]=after
        func attack(_ unit:GameUnit)->String {
            guard let a=try? GameRules.attack(unit,catalog:catalog) else{return "无武器"}
            return "\(a.dice.count)D\(a.dice.sides)"+(a.dice.flat==0 ? "":String(format:"%+d",a.dice.flat))+" · 射程\(a.range)"
        }
        func skills(_ unit:GameUnit)throws->[String] {try GameRules.skills(unit,catalog:catalog).map{try catalog.skill($0).name}}
        return try .init(before:before,after:after,beforeStats:GameRules.attributes(before,catalog:catalog),afterStats:GameRules.attributes(after,catalog:catalog),movementBefore:movementCapacity,movementAfter:MeadowMovementRules.capacity(archive),attackBefore:attack(before),attackAfter:attack(after),skillsBefore:skills(before),skillsAfter:skills(after))
    }
}
