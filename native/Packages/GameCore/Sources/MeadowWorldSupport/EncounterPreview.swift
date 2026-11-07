import Foundation
import ClassroomGameCore

public struct MeadowMonsterReadout:Codable,Equatable {
    public let id:String,templateID:String,name:String
    public let health:Int,maximumHealth:Int,shield:Int,baseAP:Int
    public let attack:String,skills:[String]
}
public struct MeadowEncounterReadout:Codable,Equatable {
    public let nodeID:Int,title:String,boss:Bool
    public let monsters:[MeadowMonsterReadout]
    public let canInteract:Bool
    public var cleared:Bool {monsters.allSatisfy{$0.health==0}}
}
public extension MeadowCampaignSession {
    func rewardSummary(node id:Int)throws->String? {
        guard let node=engine.state.map.nodes.first(where:{$0.id==id}),node.kind == .reward,let reward=node.reward else{return nil}
        let items=try reward.items.keys.sorted().map{try engine.catalog.item($0).name+" ×\(reward.items[$0]!)"}
        return (node.rewardCompleted ? "此处补给已领取。\n":"")+"每位存活领取者各获：\n金币 \(reward.coins) · 积分 \(reward.score)\n"+(items.isEmpty ? "物品：无":items.joined(separator:"\n"))
    }
    /// Read saved units, never the new-game planner; this also reflects manual
    /// edits, damaged monsters and cleared/legacy nodes without consuming RNG.
    func encounterPreview(node id:Int,actor:String?=nil)throws->MeadowEncounterReadout? {
        guard let node=engine.state.map.nodes.first(where:{$0.id==id}),node.kind == .combat || node.kind == .boss else{return nil}
        let catalog=engine.catalog
        let monsters=try engine.state.units.values.filter{$0.kind == .monster && $0.nodeID==id}.sorted{$0.id<$1.id}.map { unit -> MeadowMonsterReadout in
            let definition=try catalog.monster(unit.templateID),stats=try GameRules.attributes(unit,catalog:catalog),dice=definition.attack.dice
            let formula="\(dice.count)D\(dice.sides)"+(dice.flat==0 ? "":(dice.flat>0 ? "+":"")+String(dice.flat))
            return .init(id:unit.id,templateID:unit.templateID,name:unit.name,health:unit.health,maximumHealth:stats.maximumHealth,shield:unit.shield,baseAP:stats.baseAP,attack:formula,skills:try definition.skills.map{try catalog.skill($0).name})
        }
        let player=engine.state.units[actor ?? selectedPlayerID]
        let available = !isCompleted && travel==nil && engine.state.battle==nil && player?.isAlive==true && player?.nodeID==id && monsters.contains{$0.health>0}
        return .init(nodeID:id,title:node.name,boss:node.kind == .boss,monsters:monsters,canInteract:available)
    }
}
