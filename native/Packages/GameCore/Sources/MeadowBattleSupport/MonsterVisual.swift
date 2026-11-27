import Foundation
import ClassroomGameCore

/// Species artwork is independent of persistent battle IDs and rule stats.
public struct MonsterVisualSpec:Equatable {
    public let id:String
    public init(id:String){self.id=id}
    public var asset:String { "MeadowMonster"+id.prefix(1).uppercased()+id.dropFirst() }
    public static let bossIDs:Set<String>=["caveTroll","ruinDragon","mushroomKing","goblinWarlord","thornTreant","frostPhoenix","eclipseBehemoth"]
    public static let apexIDs:Set<String>=["crystalGolem","frostAlphaWolf"]
    public var scale:Double { Self.bossIDs.contains(id) ? 1.04 : Self.apexIDs.contains(id) ? 0.94 : 0.88 }
    public var hitAnchor:PartyPoint {
        // Y is anchored at battle-lane strike elevation (~foot.y - 72: 158 for 0.88, 163 for 0.94, 171 for 1.04)
        // so melee heroes stay grounded on the lane while X tracks each species' true torso center.
        let points:[String:PartyPoint]=[
            "slime":PartyPoint(110,158),"wolf":PartyPoint(110,158),"goblinArcher":PartyPoint(198,158),
            "stoneGuardian":PartyPoint(183,158),"caveTroll":PartyPoint(190,171),"ruinDragon":PartyPoint(152,171),
            "hopShroom":PartyPoint(140,158),"acornBandit":PartyPoint(129,158),"bubbleCrab":PartyPoint(136,158),
            "stingWasp":PartyPoint(143,158),"brambleSprite":PartyPoint(130,158),"goblinShaman":PartyPoint(145,158),
            "emberLizard":PartyPoint(131,158),"shadowOwl":PartyPoint(133,158),"runeKnight":PartyPoint(132,158),
            "crystalGolem":PartyPoint(129,163),"frostAlphaWolf":PartyPoint(129,163),"mushroomKing":PartyPoint(135,171),
            "goblinWarlord":PartyPoint(117,171),"thornTreant":PartyPoint(130,171),"frostPhoenix":PartyPoint(130,171),
            "eclipseBehemoth":PartyPoint(135,171)
        ]
        return points[id] ?? PartyPoint(94,152)
    }
    public func hitPoint(at foot:PartyPoint)->PartyPoint {PartyPoint(foot.x+(hitAnchor.x-178.5)*scale,foot.y+(hitAnchor.y-240)*scale)}
    public var contactX:Double {
        ["slime":20,"wolf":6,"stoneGuardian":72,"caveTroll":50,
         "hopShroom":32,"bubbleCrab":30,"brambleSprite":38,"runeKnight":56,
         "crystalGolem":64,"frostAlphaWolf":22,"mushroomKing":44,"thornTreant":58][id].map(Double.init) ?? 42
    }
    public func shieldCapacity(catalog:GameCatalog)->Int {
        guard let definition=try? catalog.monster(id) else{return 8}
        let amounts=definition.skills.compactMap{try? catalog.skill($0)}.flatMap(\.effects).filter{$0.kind == .shield}.map(\.amount)
        return max(1,([definition.shield]+amounts).max() ?? 0)
    }
    public static let rangedIDs:Set<String>=[
        "goblinArcher","ruinDragon","acornBandit","stingWasp","goblinShaman",
        "emberLizard","shadowOwl","goblinWarlord","frostPhoenix","eclipseBehemoth"
    ]
    public var ranged:Bool { Self.rangedIDs.contains(id) }
    public var muzzleOffset:PartyPoint {
        let offsets:[String:PartyPoint]=[
            "goblinArcher":PartyPoint(-82,-144),"ruinDragon":PartyPoint(-143,-149),
            "acornBandit":PartyPoint(-86,-83),"stingWasp":PartyPoint(-63,-102),
            "goblinShaman":PartyPoint(-59,-86),"emberLizard":PartyPoint(-84,-78),
            "shadowOwl":PartyPoint(-80,-109),"goblinWarlord":PartyPoint(-108,-101),
            "frostPhoenix":PartyPoint(-85,-118),"eclipseBehemoth":PartyPoint(-76,-108)
        ]
        return offsets[id] ?? PartyPoint(-82,-120)
    }
    public static let ids=[
        "slime","wolf","goblinArcher","stoneGuardian","caveTroll","ruinDragon",
        "hopShroom","acornBandit","bubbleCrab","stingWasp","brambleSprite","goblinShaman",
        "emberLizard","shadowOwl","runeKnight","crystalGolem","frostAlphaWolf",
        "mushroomKing","goblinWarlord","thornTreant","frostPhoenix","eclipseBehemoth"
    ]
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
        let m=muzzleOffset
        let from=PartyPoint(foot.x+m.x*scale,foot.y+m.y*scale)
        let t=(age-0.24)/0.22,tip=PartyPoint(from.x+(target.x-from.x)*t,from.y+(target.y-from.y)*t)
        let dx=target.x-from.x,dy=target.y-from.y,length=max(1,hypot(dx,dy)),span=["goblinArcher","stingWasp","frostPhoenix"].contains(id) ? 35.0:18.0
        return BowProjectile(tail:PartyPoint(tip.x-dx/length*span,tip.y-dy/length*span),tip:tip,alpha:1)
    }
}
