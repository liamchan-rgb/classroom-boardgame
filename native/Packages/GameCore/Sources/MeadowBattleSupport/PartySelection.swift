import Foundation
import ClassroomGameCore

public extension PartyEncounter {
    /// Presentation target, still validated by the original command preview.
    /// An ally-only skill defaults to the other player when self was selected.
    func preferredTarget(for action:PartyAction,ally:String,enemy:String)->String {
        if action.isOffensive{return enemy}
        guard let actor=current,let skill=try? engine.catalog.skill(action.rawValue) else{return ally}
        if skill.target == .selfOnly{return actor}
        if skill.target == .ally,ally==actor {
            return state.players.first{$0.id != actor && $0.isAlive}?.id ?? ally
        }
        return ally
    }
}
public extension PartyVisual {
    /// Display reference, not a new gameplay cap. Preserve any higher value.
    static func shieldDisplayMaximum(unit:GameUnit,catalog:GameCatalog)->Int {
        if unit.kind == .monster{return max(unit.shield,MonsterVisualSpec.find(unit.templateID)?.shieldCapacity(catalog:catalog) ?? 8)}
        let skills=catalog.skills.flatMap(\.effects).filter{$0.kind == .shield}.map{effect in effect.amount+(effect.dice.map{$0.count*$0.sides+$0.flat} ?? 0)}
        return max(8,max(unit.shield,max(skills.max() ?? 0,catalog.items.map(\.shield).max() ?? 0)))
    }
}
