import Foundation
import ClassroomGameCore

/// New-journey choices only. Saved GameUnit template IDs remain authoritative.
public struct MeadowPartyConfiguration:Codable,Equatable {
    public static let classIDs=["adventurer","ranger","spellblade","dragonKnight"]
    public var playerClassID:String,companionClassID:String
    public init(playerClassID:String="spellblade",companionClassID:String="ranger") {
        self.playerClassID=playerClassID;self.companionClassID=companionClassID
    }
    public func validate(catalog:GameCatalog)throws {
        for id in [playerClassID,companionClassID] {
            guard Self.classIDs.contains(id),catalog.classes.contains(where:{$0.id==id}) else{throw GameError("请选择已支持的小队职业。")}
        }
    }
    public static func summary(for id:String,catalog:GameCatalog)throws->String {
        guard classIDs.contains(id) else{throw GameError("职业不受支持。")}
        let definition=try catalog.playerClass(id),a=definition.attributes
        let names=try definition.skills.map{try catalog.skill($0).name}.joined(separator:"、")
        return "\(definition.name) · 基础生命 \(a.maximumHealth)\n基础行动 \(a.baseAP) · 行动上限 \(a.maximumAP)\n技能：\(names)"
    }
}
public extension MeadowCampaignSession {
    var partyConfiguration:MeadowPartyConfiguration {
        .init(playerClassID:engine.state.units["p1"]!.templateID,companionClassID:engine.state.units["p2"]!.templateID)
    }
}
