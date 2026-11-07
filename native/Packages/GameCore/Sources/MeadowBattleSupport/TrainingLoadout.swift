import Foundation
import ClassroomGameCore

/// Exploration-only equipment staging for the controlled Meadow encounter.
/// Inventory transfers and legality are always performed by the original engine.
public final class TrainingLoadout {
    public private(set) var engine:GameEngine
    public var units:[String:GameUnit] { engine.state.units }
    public init(seed:UInt64=52,persist:((GameArchive)throws->Void)?=nil) throws {
        let catalog=try GameCatalog.initial()
        var p1=try GameFactory.player(id:"p1",name:"P1",classID:"adventurer",teamID:"party",nodeID:0,catalog:catalog)
        let p2=try GameFactory.player(id:"p2",name:"P2",classID:"ranger",teamID:"party",nodeID:0,catalog:catalog)
        let map=GameMap(nodes:[MapNode(id:0,name:"营地",kind:.start)],roads:[],revealed:[0])
        // Demo loan weapons in the camp inventory; catalog and prices stay original.
        p1.inventory["huntingBow"]=1
        p1.inventory["greatSword"]=1
        p1.inventory["legendaryStaff"]=1
        p1.inventory["leatherArmor"]=1
        p1.inventory["runeArmor"]=1
        p1.inventory["powerBadge"]=1
        p1.inventory["actionRing"]=1
        p1.inventory["smallPotion"]=2
        p1.inventory["largePotion"]=1
        p1.inventory["shieldPotion"]=1
        p1.inventory["revivalStone"]=1
        var state=GameState(units:["p1":p1,"p2":p2],teams:[GameTeam(id:"party",name:"旅人小队")],map:map,random:RandomState(seed:seed))
        state.pauseReasons=[]
        engine=try GameEngine(catalog:catalog,state:state,persist:persist)
    }
    public init(archive:GameArchive,persist:((GameArchive)throws->Void)?=nil) throws {
        engine=try GameEngine(catalog:archive.catalog,state:archive.state,history:archive.history,persist:persist)
    }
    @discardableResult public func equipAccessory(_ item:String?,actor:String="p1") throws -> OperationReceipt {
        try engine.apply(.equip(unit:actor,slot:.accessory,item:item))
    }
    @discardableResult public func equipArmor(_ item:String?,actor:String="p1") throws -> OperationReceipt {
        try engine.apply(.equip(unit:actor,slot:.armor,item:item))
    }
    @discardableResult public func equip(_ item:String?,actor:String="p1") throws -> OperationReceipt {
        try engine.apply(.equip(unit:actor,slot:.weapon,item:item))
    }
}

/// A data binding, not a weapon-specific branch in the renderer or body rig.
public struct EquipmentVisualBinding:Codable {
    public let itemID:String,walkingAsset:String,battleAsset:String,iconAsset:String
}

/// A permanent equipment readout. It never creates or consumes a temporary buff.
public struct AccessoryReadout:Codable,Equatable {
    public let itemID:String,name:String,summary:String,detail:String
    public let damageBonus:Int,baseAPBonus:Int
    public static func make(_ unit:GameUnit,catalog:GameCatalog) throws -> AccessoryReadout? {
        guard let id=unit.equipment.accessory else { return nil }
        let item=try catalog.item(id),stats=try GameRules.attributes(unit,catalog:catalog)
        guard item.slot == .accessory else { return nil }
        var parts:[String]=[]
        if item.attributes.damage != 0 { parts.append("伤害＋\(item.attributes.damage)") }
        if item.attributes.baseAP != 0 { parts.append("基础行动＋\(item.attributes.baseAP)") }
        let summary=parts.joined(separator:" · ")
        let detail=item.attributes.baseAP>0 ? "回合基础行动 \(stats.baseAP) · 上限 \(stats.maximumAP)\n换装不立即补充行动点" : "普攻与伤害技能生效\n常驻装备属性 · 不占临时增伤"
        return .init(itemID:id,name:item.name,summary:summary,detail:detail,damageBonus:item.attributes.damage,baseAPBonus:item.attributes.baseAP)
    }
}
public struct AccessoryVisualBinding:Codable {
    public let itemID:String,iconAsset:String
}
