import Foundation

/// Read-only bridge. It has no engine, commands, RNG or persistence access.
public enum MeadowPublicProjection {
    public static let contactTime = 0.46
    public static func approach(_ age:Double)->Double {
        func smooth(_ t:Double)->Double { let x=min(1,max(0,t));return x*x*(3-2*x) }
        if age<0.12 { return 0 }
        if age<0.38 { return smooth((age-0.12)/0.26) }
        if age<0.58 { return 1 }
        return 1-smooth((age-0.58)/0.57)
    }
    public static func active(_ frame: PublicPlayFrame, at date: Date) -> CommittedPresentation? {
        frame.presentations.first { $0.isVisible(at: date) }
    }
    public static func battle(_ frame: PublicPlayFrame, at date: Date) -> Bool {
        // Keep the map until committed travel arrives; keep the last hit on stage.
        if frame.presentations.contains(where: { $0.opensBattleAfterArrival && date < $0.end }) { return false }
        return frame.snapshot.round > 0 || (active(frame,at:date)?.before?.round ?? 0) > 0
    }
    public static func units(_ frame: PublicPlayFrame, at date: Date) -> [PublicGameUnit] {
        // A queued receipt may already be committed; hold its previous public values.
        guard let next = frame.presentations.first(where: { date < $0.end }), let before = next.before else { return frame.snapshot.units }
        let age = date.timeIntervalSince(next.start)
        if age < contactTime { return before.units }
        // Do not jump to the result of a later queued command.
        let after = frame.presentations.first(where: { $0.start >= next.end })?.before?.units ?? frame.snapshot.units
        // Mixed damage/self-heal skills still hit at contact; recovery is later.
        return after.map { unit in
            let effects=next.units.first(where: { $0.id == unit.id })?.effects ?? []
            if age < 0.72, effects.contains("heal") || effects.contains("shield") || effects.contains("revive"),
               let previous=before.units.first(where: { $0.id == unit.id }) { return previous }
            return unit
        }
    }
    public static func participants(_ frame: PublicPlayFrame, at date: Date) -> [PublicGameUnit] {
        let snapshot = active(frame,at:date)?.before ?? frame.snapshot
        let ids = Set(snapshot.queueIDs)
        return units(frame,at:date).filter { ids.contains($0.id) }
    }
    public static func point(_ unit: PublicGameUnit, frame: PublicPlayFrame, at date: Date) -> MapPoint? {
        if let cue = frame.presentations.first(where: { date < $0.end && $0.mapMoves.contains(where: { $0.unitID == unit.id }) }),
           let move = cue.mapMoves.first(where: { $0.unitID == unit.id }) {
            return move.position(progress:date.timeIntervalSince(cue.start)/1.3)
        }
        return frame.snapshot.nodes.first(where: { $0.id == unit.nodeID }).map { MapPoint(x:$0.x,y:$0.y) }
    }
    public static func recognizedMonster(_ id: String) -> String? {
        ["slime","wolf","goblinArcher","stoneGuardian","caveTroll","ruinDragon"].contains(id) ? id : nil
    }
}
