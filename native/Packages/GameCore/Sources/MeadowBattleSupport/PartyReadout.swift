import Foundation
import ClassroomGameCore

public struct PartyActionReadout:Equatable {
    public let actor:String,target:String,resources:String,availability:String
    public let allowed:Bool
    public var text:String {"\(actor) → \(target)\n\(resources)\n\(availability)"}
}
public extension PartyEncounter {
    func actionReadout(_ action:PartyAction,ally:String,enemy:String)->PartyActionReadout {
        let target=preferredTarget(for:action,ally:ally,enemy:enemy)
        let actor=current.flatMap{state.units[$0]},preview=preview(action,target:target)
        let destination:String
        if action.isNodeSupport {destination="同地点存活队员"}
        else if [.dragonFlame,.starlightPulse].contains(action){destination="目标地点敌人"}
        else {destination=state.units[target]?.name ?? target}
        var resources="个人行动 \(actor?.ap ?? 0) · 消耗 \(cost(action))"
        if action.isItem {resources+=" · 个人库存 \(actor?.inventory[action.rawValue] ?? 0)"}
        else if let skill=try? engine.catalog.skill(action.rawValue) {
            if let limit=skill.uses {resources+=" · 剩余 \(max(0,limit-(actor?.skillUses[action.rawValue] ?? 0)))/\(limit)次"}
            else {resources+=" · 次数不限"}
        }
        return .init(actor:actor?.name ?? "等待行动",target:destination,resources:resources,availability:preview.allowed ? "可使用":preview.message,allowed:preview.allowed)
    }
    var partyResourceSummary:String {
        state.players.map {u in
            let items=["smallPotion","largePotion","shieldPotion","revivalStone"].map{((try? engine.catalog.item($0).name) ?? $0)+"×\(u.inventory[$0] ?? 0)"}.joined(separator:" · ")
            return "\(u.name)\(u.isAlive ? "":"（倒地）") · 个人行动 \(u.ap)\n"+items
        }.joined(separator:"\n\n")
    }
}
