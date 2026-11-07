import Foundation
import ClassroomGameCore
public struct PartyPoint:Codable { public var x:Double;public var y:Double;public init(_ x:Double,_ y:Double) { self.x=x;self.y=y } }
public struct PartyParticle:Codable {
    public let id:Int;public let x:Double;public let y:Double;public let size:Double;public let alpha:Double;public let angle:Double
}
public struct PartyAfterimage:Codable { public let offset:PartyPoint;public let progress:Double;public let alpha:Double }
public struct PartySlash:Codable { public let points:[PartyPoint];public let alpha:Double }
public enum PartySkillVFXMotion:String,Codable,Equatable { case melee,ranged,support }
public enum PartySkillVFXTarget:String,Codable,Equatable { case enemyNode,allyNode }
public struct PartySkillVFXSpec:Codable,Equatable,Identifiable {
    public let id:String
    public let assetName:String
    public let frameCount:Int
    public let framesPerSecond:Double
    public let frameWidth:Int
    public let frameHeight:Int
    public let anchorX:Double
    public let anchorY:Double
    public let peakFrame:Int
    public let motion:PartySkillVFXMotion
    public let target:PartySkillVFXTarget
    public var duration:Double { Double(frameCount)/framesPerSecond }
    public var peakTime:Double { Double(peakFrame)/framesPerSecond }
    public func startTime(actionStart:Double,impactAge:Double)->Double {
        if motion == .support { return actionStart+impactAge }
        return actionStart+max(0,impactAge-peakTime)
    }
    public static let all:[PartySkillVFXSpec] = [
        .init(id:"starlightPulse",assetName:"MeadowBattleVFXStarlightPulse",frameCount:20,framesPerSecond:16,frameWidth:344,frameHeight:344,anchorX:172,anchorY:172,peakFrame:12,motion:.ranged,target:.enemyNode),
        .init(id:"rally",assetName:"MeadowBattleVFXRally",frameCount:20,framesPerSecond:12,frameWidth:256,frameHeight:256,anchorX:128,anchorY:128,peakFrame:14,motion:.support,target:.allyNode),
        .init(id:"sweep",assetName:"MeadowBattleVFXSweep",frameCount:20,framesPerSecond:20,frameWidth:339,frameHeight:287,anchorX:169.5,anchorY:143.5,peakFrame:9,motion:.melee,target:.allyNode),
        .init(id:"dragonSoulWard",assetName:"MeadowBattleVFXDragonSoulWard",frameCount:20,framesPerSecond:12,frameWidth:256,frameHeight:256,anchorX:133,anchorY:154,peakFrame:12,motion:.support,target:.allyNode),
        .init(id:"dragonScaleWard",assetName:"MeadowBattleVFXDragonScaleWard",frameCount:20,framesPerSecond:20,frameWidth:256,frameHeight:256,anchorX:128,anchorY:128,peakFrame:12,motion:.support,target:.allyNode)
    ]
    public static func find(_ skillID:String)->PartySkillVFXSpec? { all.first { $0.id==skillID } }
    public init(id:String,assetName:String,frameCount:Int,framesPerSecond:Double,frameWidth:Int,frameHeight:Int,anchorX:Double,anchorY:Double,peakFrame:Int,motion:PartySkillVFXMotion,target:PartySkillVFXTarget) {
        self.id=id;self.assetName=assetName;self.frameCount=frameCount;self.framesPerSecond=framesPerSecond;self.frameWidth=frameWidth;self.frameHeight=frameHeight;self.anchorX=anchorX;self.anchorY=anchorY;self.peakFrame=peakFrame;self.motion=motion;self.target=target
    }
}
public enum PartyVisual {
    public static let width=1000.0,height=600.0,heroScale=0.83,enemyScale=0.82
    public static func slot(_ id:String)->String {
        if id.hasPrefix("m-") {return id.hasSuffix("-3") ? "m3":id.hasSuffix("-2") ? "m2":"m1"};return id
    }
    public static func foot(_ id:String)->PartyPoint? {feet[slot(id)]}
    public static let feet:[String:PartyPoint]=["p1":PartyPoint(165,420),"p2":PartyPoint(315,505),"m1":PartyPoint(650,395),"m2":PartyPoint(835,510),"m3":PartyPoint(600,585)]
    public static func smooth(_ x:Double)->Double { let t=min(1,max(0,x));return t*t*(3-2*t) }
    public static func pulse(_ age:Double,_ start:Double,_ peak:Double,_ end:Double)->Double { age<peak ? smooth((age-start)/(peak-start)):1-smooth((age-peak)/(end-peak)) }
    public static func chest(_ id:String)->PartyPoint { let p=foot(id)!;return PartyPoint(p.x+5*heroScale,p.y-70*heroScale) }
    public static func skillEffectCenter(targets:[String],actor:String,templates:[String:String]=[:])->PartyPoint {
        let points=targets.compactMap { id -> PartyPoint? in
            guard let foot=foot(id) else { return nil }
            let monster=id.hasPrefix("m")
            if monster,let spec=MonsterVisualSpec.find(templates[id]){return spec.hitPoint(at:foot)}
            return PartyPoint(foot.x+(monster ? 13.5*enemyScale:5*heroScale),foot.y-(monster ? 112*enemyScale:86*heroScale))
        }
        guard !points.isEmpty else { return foot(actor).map { PartyPoint($0.x,$0.y-70*heroScale) } ?? PartyPoint(width/2,height/2) }
        return PartyPoint(points.reduce(0){$0+$1.x}/Double(points.count),points.reduce(0){$0+$1.y}/Double(points.count))
    }
    public static func hitPoint(target:String,shielded:Bool=false,weaponID:String?=nil,templateID:String?=nil)->PartyPoint {
        let foot=foot(target)!
        if target.hasPrefix("m"),let spec=MonsterVisualSpec.find(templateID){return spec.hitPoint(at:foot)}
        if ["greatSword","legendaryStaff"].contains(weaponID ?? ""),target.hasPrefix("m") { return PartyPoint(foot.x+(94-178.5)*enemyScale,foot.y+(152-240)*enemyScale) }
        return PartyPoint(foot.x+(target.hasPrefix("m") ? -80:shielded ? (5+240*0.41)*heroScale:10),foot.y-(target.hasPrefix("m") ? 72:65))
    }
    public static func damageLabelOrigin(at:PartyPoint,width:Double,height:Double,age:Double)->PartyPoint {
        PartyPoint(at.x-width/2,at.y-height/2-max(0,age)*26)
    }
    /// Non-damage effect numbers remain beside their owner and below every HP header.
    public static func supportLabelOrigin(at:PartyPoint,width:Double,line:Int,age:Double)->PartyPoint {
        PartyPoint(max(4,at.x-14-width),at.y-86+Double(line)*36-max(0,age)*26)
    }
    public static func beam(_ from:PartyPoint,_ to:PartyPoint,_ t:Double)->PartyPoint {
        let u=1-t;return PartyPoint(u*u*from.x+2*u*t*((from.x+to.x)/2)+t*t*to.x,u*u*from.y+2*u*t*(min(from.y,to.y)-90)+t*t*to.y)
    }
    public static func trail(age:Double,from:PartyPoint,to:PartyPoint)->[PartyParticle] {
        guard age>=0,age<1.65 else { return [] }
        return (0..<28).compactMap { i in
            let delay=Double(i)*0.018;let t=(age-delay)/0.55
            guard t>=0,t<=1 else { return nil };let p=beam(from,to,t)
            return PartyParticle(id:i,x:p.x,y:p.y+sin(Double(i)*2.399+t*7)*4,size:i%5==0 ? 11:5,alpha:sin(Double.pi*t)*0.95,angle:t*3+Double(i))
        }
    }
    public static func rally(age:Double,at:PartyPoint)->[PartyParticle] {
        guard age>=0,age<1.8 else { return [] }
        return (0..<22).compactMap { i in
            let local=age-Double(i%6)*0.045
            guard local>=0,local<1.35 else { return nil }
            let t=local/1.35;let angle=Double(i)*2.399
            return PartyParticle(id:i,x:at.x+cos(angle)*(24+13*t),y:at.y+30-t*125,size:Double(i%4==0 ? 12:6),alpha:sin(Double.pi*t)*0.9,angle:-Double.pi/2)
        }
    }
    public static func ambushProgress(_ age:Double)->Double {
        if age<0.24 { return 0.18*smooth(age/0.24) }
        if age<0.72 { return 0.18+0.36*smooth((age-0.24)/0.48) }
        if age<0.84 { return 0.54+0.10*smooth((age-0.72)/0.12) }
        return 0.64+0.36*smooth((age-0.84)/0.58)
    }
    public static func afterimages(_ intent:PartyIntent?,age:Double)->[PartyAfterimage] {
        guard let intent,intent.action == .ambush,age>=0.22,age<1.0 else { return [] }
        return (1...3).map { i in
            let past=max(0,age-Double(i)*0.065)
            return PartyAfterimage(offset:travel(intent,age:past),progress:ambushProgress(past),alpha:pulse(age,0.22,0.48,1.0)*(0.26-Double(i)*0.045))
        }
    }
    /// Two visual strokes, one atomic hit. Sweep heads and tails continuously.
    public static func ambushSlashes(age:Double,at:PartyPoint)->[PartySlash] {
        (0..<2).compactMap { i in
            let local=age-0.72-Double(i)*0.065
            guard local>=0,local<0.42 else { return nil }
            let head=min(1,local/0.16),tail=max(0,(local-0.10)/0.32),alpha=pulse(local,0,0.035,0.42)
            let points=(0...24).map { j -> PartyPoint in
                let t=tail+(head-tail)*Double(j)/24,x = -72+144*t
                return PartyPoint(at.x+x,at.y+(i==0 ? 1.0:-1.0)*(62-124*t)+sin(Double.pi*t)*20)
            }
            return PartySlash(points:points,alpha:alpha)
        }
    }
    public static func travel(_ intent:PartyIntent?,age:Double,shielded:Bool=false)->PartyPoint {
        guard let intent,intent.action.isOffensive,let from=foot(intent.actor),let to=foot(intent.target) else { return PartyPoint(0,0) }
        if intent.action == .dragonFlame { return PartyPoint(0,0) }
        let legacy=hitPoint(target:intent.target,shielded:shielded,weaponID:intent.weaponID)
        let registered=hitPoint(target:intent.target,shielded:shielded,weaponID:intent.weaponID,templateID:intent.targetTemplateID)
        let correction=PartyPoint(registered.x-legacy.x,registered.y-legacy.y)
        if intent.action == .runeSlash {
            let approach=smooth(age/0.82),retreat=1-smooth((age-1.25)/0.52),p=min(approach,retreat)
            return PartyPoint((to.x-155+correction.x-from.x)*p,(to.y-12+correction.y-from.y)*p)
        }
        if intent.ranged || intent.magical || intent.action.usesRangedMotion || intent.action.isRune { return PartyPoint(0,0) }
        if intent.weaponID=="greatSword",!intent.enemy,intent.action != .ambush {
            return GreatSwordRig.travel(age:age,from:from,to:registered,scale:heroScale)
        }
        if intent.action == .ambush {
            let p=age<0.72 ? smooth((age-0.22)/0.50):1-smooth((age-0.84)/0.58)
            return PartyPoint((to.x-140+correction.x-from.x)*p,(to.y-12+correction.y-from.y)*p)
        }
        let t=intent.enemy ? age/0.96 : max(0,age-0.4-min(0.1,max(0,age-1.048)))/1.2
        let p=t<0.4 ? smooth((t-0.12)/0.28) : t<0.66 ? 1:1-smooth((t-0.66)/0.34)
        if intent.enemy { let spec=MonsterVisualSpec.find(intent.monsterTemplateID),scale=spec?.scale ?? enemyScale,contact=spec?.contactX ?? 42;let move=pulse(age,0.08,0.46,0.96);return PartyPoint((to.x+(178.5-contact)*scale+(shielded ? (5+240*0.41)*heroScale:0)-from.x)*move,(to.y-from.y)*move) }
        return PartyPoint((to.x-140+correction.x-from.x)*p,(to.y-12+correction.y-from.y)*p)
    }
}

public struct PartyActorPose:Codable { public let clip:String;public let progress:Double }
extension PartyVisual {
    public static func pose(unit:GameUnit,intent:PartyIntent?,age:Double,time:Double,hurtAge:Double?=nil,blocked:Bool=false,downAge:Double?=nil,victoryAge:Double?=nil)->PartyActorPose {
        var clip=unit.isAlive ? "idle":"defeat"
        var progress=unit.isAlive ? time.truncatingRemainder(dividingBy:2.4)/2.4:(downAge.map { smooth($0/0.6) } ?? 1)
        if let intent,intent.actor==unit.id,unit.isAlive {
            if intent.action == .runeSlash {
                clip="attack"
                if unit.equipment.weapon=="greatSword" { progress=GreatSwordRig.progress(age:age) }
                else if unit.equipment.weapon=="legendaryStaff" { progress=LegendaryStaffRig.progress(age:age) }
                else if unit.equipment.weapon=="huntingBow" { progress=BowRig.progress(age:age) }
                else { let action=max(0,age-0.28);progress=min(1,max(0,action-min(0.1,max(0,action-0.648)))/1.2) }
            } else if intent.action == .dragonFlame {
                clip="guard";progress=PartyVisual.smooth(age/intent.action.duration)
            } else if intent.action.isRune {
                clip="guard";progress=smooth(age/intent.action.duration)
            } else if intent.action == .starlightPulse {
                clip="attack"
                if unit.equipment.weapon=="greatSword" { progress=GreatSwordRig.progress(age:age) }
                else if unit.equipment.weapon=="legendaryStaff" { progress=LegendaryStaffRig.progress(age:age) }
                else if unit.equipment.weapon=="huntingBow" { progress=BowRig.progress(age:age) }
                else { let action=max(0,age-0.4);progress=min(1,max(0,action-min(0.1,max(0,action-0.648)))/1.2) }
            } else if intent.action == .ambush {
                clip="attack";progress=ambushProgress(age)
            } else if intent.action.visual=="attack" {
                clip="attack"
                if intent.ranged && unit.equipment.weapon=="huntingBow" { progress=BowRig.progress(age:age) }
                else if intent.magical { progress=LegendaryStaffRig.progress(age:age) }
                else if intent.weaponID=="greatSword" { progress=GreatSwordRig.progress(age:age) }
                else { let action=max(0,age-0.4);progress=min(1,max(0,action-min(0.1,max(0,action-0.648)))/1.2) }
            } else if ["support","rally","guard"].contains(intent.action.visual) { clip="guard";progress=min(1,age/1.4) }
        }
        if let intent,intent.action == .revivalStone,intent.target==unit.id,age>=intent.action.impact { clip="defeat";progress=1-smooth((age-intent.action.impact)/0.6) }
        if let hurtAge,hurtAge<0.7,unit.isAlive { clip=blocked ? "guard":"hit";progress=min(1,hurtAge/0.7) }
        if let victoryAge,unit.isAlive,intent == nil,hurtAge == nil || hurtAge!>=0.7 { clip="victory";progress=min(1,max(0,victoryAge/1.08)) }
        return PartyActorPose(clip:clip,progress:progress)
    }
}
