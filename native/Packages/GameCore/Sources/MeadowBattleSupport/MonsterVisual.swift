import Foundation
import ClassroomGameCore

/// Species artwork is independent of persistent battle IDs and rule stats.
public struct MonsterVisualSpec:Equatable {
    public let id:String
    public var asset:String { "MeadowMonster"+id.prefix(1).uppercased()+id.dropFirst() }
    public var scale:Double { ["caveTroll","ruinDragon"].contains(id) ? 1.04:0.88 }
    public var hitAnchor:PartyPoint {
        let points:[String:PartyPoint]=["slime":PartyPoint(110,158),"wolf":PartyPoint(110,158),"goblinArcher":PartyPoint(198,158),"stoneGuardian":PartyPoint(183,158),"caveTroll":PartyPoint(190,171),"ruinDragon":PartyPoint(152,171)]
        return points[id] ?? PartyPoint(94,152)
    }
    public func hitPoint(at foot:PartyPoint)->PartyPoint {PartyPoint(foot.x+(hitAnchor.x-178.5)*scale,foot.y+(hitAnchor.y-240)*scale)}
    public var contactX:Double { ["slime":20,"wolf":6,"stoneGuardian":72,"caveTroll":50][id].map(Double.init) ?? 42 }
    public func shieldCapacity(catalog:GameCatalog)->Int {
        guard let definition=try? catalog.monster(id) else{return 8}
        let amounts=definition.skills.compactMap{try? catalog.skill($0)}.flatMap(\.effects).filter{$0.kind == .shield}.map(\.amount)
        return max(1,([definition.shield]+amounts).max() ?? 0)
    }
    public var ranged:Bool { ["goblinArcher","ruinDragon"].contains(id) }
    public static let ids=["slime","wolf","goblinArcher","stoneGuardian","caveTroll","ruinDragon"]
    public static func find(_ id:String?)->Self? { guard let id,ids.contains(id) else{return nil};return Self(id:id) }
    public func frame(time:Double,attackAge:Double?,castAge:Double?,hurtAge:Double?,preparing:Bool=false)->Int {
        if let age=hurtAge,age>=0,age<0.40{return 48+min(7,Int(age/0.40*8))}
        if let age=attackAge,age>=0,age<0.96{return 12+min(23,Int(age/0.96*24))}
        if let age=castAge,age>=0,age<1.40{return 36+min(11,Int(age/1.40*12))}
        if preparing{return 36+Int((sin(time*3)+1)*1.5)}
        return min(11,Int(max(0,time).truncatingRemainder(dividingBy:2.4)/2.4*12))
    }
    public static let deathDuration=0.8
    public static func deathFrame(_ age:Double)->Int { min(39,max(0,Int(max(0,age)/deathDuration*40))) }
    /// The missile departs the actual left-facing muzzle/bow, then contacts at .46.
    public func projectile(age:Double,foot:PartyPoint,target:PartyPoint)->BowProjectile? {
        guard ranged,age>=0.24,age<0.46 else{return nil}
        let from=PartyPoint(foot.x+(id=="goblinArcher" ? -82:-143)*scale,foot.y-(id=="goblinArcher" ? 144:149)*scale)
        let t=(age-0.24)/0.22,tip=PartyPoint(from.x+(target.x-from.x)*t,from.y+(target.y-from.y)*t)
        let dx=target.x-from.x,dy=target.y-from.y,length=max(1,hypot(dx,dy)),span=id=="goblinArcher" ? 35.0:18.0
        return BowProjectile(tail:PartyPoint(tip.x-dx/length*span,tip.y-dy/length*span),tip:tip,alpha:1)
    }
}
