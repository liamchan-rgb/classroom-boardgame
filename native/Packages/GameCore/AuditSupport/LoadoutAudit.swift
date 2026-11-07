import Foundation
import ClassroomGameCore
import MeadowWorldSupport

/// Controlled starting kits for regression, never grants in the application.
/// Set kits verify rules only; their dedicated artwork is still incomplete.
public struct MeadowAuditLoadout:Codable,Equatable {
    public let id:String,equipment:Equipment
    public static let supported:[MeadowAuditLoadout] = ["trainingSword","huntingBow","greatSword","legendaryStaff"].flatMap { weapon in
        [MeadowAuditLoadout(id:weapon+"-plain",equipment:.init(weapon:weapon)),
         .init(id:weapon+"-leather-badge",equipment:.init(weapon:weapon,armor:"leatherArmor",accessory:"powerBadge")),
         .init(id:weapon+"-rune-ring",equipment:.init(weapon:weapon,armor:"runeArmor",accessory:"actionRing"))]
    }
    public static let rulesOnly:[MeadowAuditLoadout] = [
        .init(id:"starlight-two",equipment:.init(weapon:"trainingSword",armor:"starlightArmor",accessory:"starlightCharm")),
        .init(id:"starlight-three",equipment:.init(weapon:"starlightBlade",armor:"starlightArmor",accessory:"starlightCharm")),
        .init(id:"dragon-two",equipment:.init(weapon:"trainingSword",armor:"dragonArmor",accessory:"dragonCharm")),
        .init(id:"dragon-three",equipment:.init(weapon:"dragonFangSword",armor:"dragonArmor",accessory:"dragonCharm"))]
    public static let all=supported+rulesOnly+[.init(id:"unarmed-rune-ring",equipment:.init(armor:"runeArmor",accessory:"actionRing"))]
    public func units(role:String)throws->[String:GameUnit] {
        let catalog=try MeadowCampaignSession.catalog()
        var unit=try GameFactory.player(id:"p1",name:"P1",classID:role,teamID:"party",nodeID:1,catalog:catalog)
        unit.equipment=equipment
        unit.inventory=["smallPotion":2,"largePotion":1,"shieldPotion":1,"revivalStone":1]
        return ["p1":unit]
    }
}
public struct MeadowLoadoutJourneyReport:Codable,Equatable {
    public let loadout:MeadowAuditLoadout
    public let journey:MeadowJourneyAuditReport
    public init(loadout:MeadowAuditLoadout,journey:MeadowJourneyAuditReport){self.loadout=loadout;self.journey=journey}
}
