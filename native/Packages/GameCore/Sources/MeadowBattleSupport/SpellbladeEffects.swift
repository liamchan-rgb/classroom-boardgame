import Foundation
import ClassroomGameCore

public struct RuneStroke:Codable { public let points:[PartyPoint];public let width:Double,alpha:Double;public let color:String }
public struct RuneGlow:Codable { public let point:PartyPoint;public let rx:Double,ry:Double,alpha:Double;public let color:String }
public struct RuneMote:Codable { public let id:Int;public let point:PartyPoint;public let size:Double,angle:Double,alpha:Double;public let color:String;public let groundAge:Double?;public let ground:PartyPoint }
public struct BattleEffectSpriteLayer:Codable { public let asset:String;public let center:PartyPoint;public let size:Double;public let alpha:Double }
public struct RuneEffectSample:Codable {
    public var strokes:[RuneStroke]=[];public var glows:[RuneGlow]=[];public var motes:[RuneMote]=[]
    public var spriteLayers:[BattleEffectSpriteLayer]=[]
    public var spriteFrame:Int?=nil;public var spriteCenter:PartyPoint?=nil;public var spriteSize:Double?=nil;public var spriteAlpha:Double?=nil
    public init() {}
}
public struct RuneRecipient:Codable,Equatable { public let unitID:String;public var heal:Int=0,shield:Int=0,buff:Int=0 }

/// Catalog scopes, rather than the clicked target, own each effect channel.
public enum SpellbladeEffects {
    private static let runeSlashDurations:[Double]=[0.040,0.040,0.045,0.045,0.045,0.040,0.035,0.035,0.035,0.045,0.050,0.040,0.045,0.045,0.050,0.055,0.055,0.060,0.070,0.080]
    private static let runeWardDurations:[Double]=[0.100,0.070,0.070,0.070,0.070,0.070,0.070,0.060,0.060,0.080,0.060,0.050,0.090,0.070,0.070,0.070,0.070,0.070,0.070,0.100]

    /// The game rules still resolve at contact. Positive HP/shield presentation
    /// waits until the associated effect has played through 58% of its motion.
    public static func statusVFXCueAge(for action:PartyAction)->Double? {
        let hit=action.impact
        if let spec=action.skillVFX {
            return max(hit,spec.startTime(actionStart:0,impactAge:hit)+spec.duration*0.58)
        }
        let start:Double,duration:Double
        switch action {
        case .runeSlash:
            duration=runeSlashDurations.reduce(0,+)
            start=hit-runeSlashDurations.prefix(10).reduce(0,+)
        case .runeWard:
            start=0;duration=runeWardDurations.reduce(0,+)
        case .dragonFlame:
            start=hit;duration=1.3333333333333333
        default:
            // The remaining recovery and ward actions use their established
            // guard/support motion, which begins with the action itself.
            start=0;duration=action.duration
        }
        return max(hit,start+duration*0.58)
    }

    private static func authoredFrames(prefix:String,elapsed:Double,durations:[Double],center:PartyPoint,size:Double)->[BattleEffectSpriteLayer] {
        let total=durations.reduce(0,+)
        guard elapsed>=0,elapsed<total-1e-9 else { return [] }
        var local=elapsed,index=0
        while index<durations.count-1 && local>=durations[index]-1e-9 { local=max(0,local-durations[index]);index+=1 }
        let next=min(durations.count-1,index+1),progress=PartyVisual.smooth(local/durations[index])
        let currentAsset=prefix+String(format:"%02d",index+1),nextAsset=prefix+String(format:"%02d",next+1)
        if next==index || progress<0.001 { return [.init(asset:currentAsset,center:center,size:size,alpha:1)] }
        if progress>0.999 { return [.init(asset:nextAsset,center:center,size:size,alpha:1)] }
        return [
            .init(asset:currentAsset,center:center,size:size,alpha:1-progress),
            .init(asset:nextAsset,center:center,size:size,alpha:progress)
        ]
    }

    /// Impact debris stays tied to the true receipt and arcs down to the ground.
    private static func runeSlashImpact(age:Double,hit:Double,at:PartyPoint,foot:PartyPoint)->([RuneMote],Double) {
        let elapsed=age-hit
        guard elapsed>=0,elapsed<0.95 else { return ([],0) }
        let gravity=310.0,groundY=foot.y-5.0
        let colors=["white","cyan","blue","gold","cyan","white"]
        var motes:[RuneMote]=[]
        for i in 0..<32 {
            let delay=i<12 ? 0.0:Double(i%5)*0.018,local=elapsed-delay,life=0.48+Double(i%5)*0.085
            guard local>=0,local<life else { continue }
            let angle=Double(i)*2.399963229728653,speed=72.0+Double((i*7)%6)*16.0
            let start=PartyPoint(at.x+cos(angle)*5,at.y+sin(angle)*5)
            let vx=cos(angle)*speed+12.0,vy = -45.0+Double((i*11)%7)*22.0
            let gap=max(1,groundY-start.y),impactTime=(-vy+sqrt(vy*vy+2*gravity*gap))/gravity
            let x=start.x+vx*local
            var y=start.y+vy*local+0.5*gravity*local*local,groundAge:Double?=nil
            let groundX=start.x+vx*impactTime
            if local>=impactTime {
                let bounce=local-impactTime
                groundAge=bounce
                y=bounce<0.18 ? groundY-10.0*sin(Double.pi*bounce/0.18):groundY
            }
            let fade=1-PartyVisual.smooth(max(0,(local-life*0.30)/(life*0.70)))
            motes.append(.init(id:900+i,point:PartyPoint(x,y),size:i%7==0 ? 9:i%3==0 ? 6:4,angle:angle+local*3.4,alpha:fade,color:colors[i%colors.count],groundAge:groundAge,ground:PartyPoint(groundX,groundY)))
        }
        return (motes,1-PartyVisual.smooth(elapsed/0.38))
    }

    public static func recipients(_ intent:PartyIntent,catalog:GameCatalog)->[RuneRecipient] {
        guard (intent.action.isRune || intent.action == .dragonFlame),let skill=try? catalog.skill(intent.action.rawValue) else { return [] }
        var values:[String:RuneRecipient]=[:]
        for effect in skill.effects where effect.kind != .damage {
            let ids=effect.scope == .caster ? [intent.actor]:intent.targets
            for id in ids {
                var v=values[id] ?? RuneRecipient(unitID:id)
                switch effect.kind { case .heal:v.heal=max(v.heal,effect.amount);case .shield:v.shield=max(v.shield,effect.amount);case .damageBuff:v.buff=max(v.buff,effect.amount);default:break }
                values[id]=v
            }
        }
        return values.values.sorted { $0.unitID<$1.unitID }
    }
    /// Healing4 is the established baseline; stronger healing thickens the helix.
    public static func healingStrength(_ amount:Int)->Double { min(2.2,max(1,sqrt(Double(max(4,amount))/4))) }
    public static func darkness(_ action:PartyAction,age:Double,from:Double)->Double {
        let peak=BattleDice.darkness(action),hold=action.impact+0.28
        return (from+(peak-from)*PartyVisual.smooth(age/0.30))*(1-PartyVisual.smooth((age-hold)/0.78))
    }
    public static func sample(action:PartyAction,age:Double,actor:String,target:String,recipients:[RuneRecipient],weaponID:String?=nil,targets:[String]=[],templates:[String:String]=[:])->RuneEffectSample {
        var result=RuneEffectSample()
        guard age>=0,age<action.duration else { return result }
        if action == .dragonFlame { return dragonFlame(age:age,targetIDs:targets.isEmpty ? [target]:targets,templates:templates) }
        guard action.isRune,let actorFoot=PartyVisual.foot(actor),let targetFoot=PartyVisual.foot(target) else { return result }
        let hit=action.impact,at=PartyVisual.hitPoint(target:target,weaponID:weaponID,templateID:templates[target]),source=PartyPoint(actorFoot.x+42,actorFoot.y-73)
        if action == .runeSlash {
            // Frame 010 begins exactly at the authoritative 1.048s damage receipt.
            // Its authored burst center is offset inside the 256px canvas, so
            // shift the canvas to land the white core on the struck body part.
            let hitCoreOffset=PartyPoint(52,20),canvasCenter=PartyPoint(at.x-hitCoreOffset.x,at.y-hitCoreOffset.y)
            let onset=hit-runeSlashDurations.prefix(10).reduce(0,+)
            result.spriteLayers=authoredFrames(prefix:"MeadowRuneSlashAttack",elapsed:age-onset,durations:runeSlashDurations,center:canvasCenter,size:256)
            let (debris,flash)=runeSlashImpact(age:age,hit:hit,at:at,foot:targetFoot)
            result.motes=debris
            if flash>0.001 {
                result.glows.append(.init(point:at,rx:112,ry:84,alpha:flash*0.62,color:"cyan"))
                result.glows.append(.init(point:PartyPoint(targetFoot.x,targetFoot.y-4),rx:120,ry:21,alpha:flash*0.50,color:"gold"))
            }
            return result
        }
        if action == .runeWard {
            let points=recipients.compactMap { PartyVisual.foot($0.unitID) }
            let node=points.isEmpty ? targetFoot:PartyPoint(points.map(\.x).reduce(0,+)/Double(points.count),points.map(\.y).reduce(0,+)/Double(points.count))
            let center=PartyPoint(node.x,node.y-65)
            result.spriteLayers=authoredFrames(prefix:"MeadowRuneWardCast",elapsed:age,durations:runeWardDurations,center:center,size:270)
            let glow=PartyVisual.pulse(age,0.12,0.84,1.50)
            if glow>0.001 { result.glows.append(.init(point:center,rx:142,ry:112,alpha:glow*0.22,color:"cyan")) }
            return result
        }
        func stroke(_ points:[PartyPoint],_ width:Double,_ alpha:Double,_ color:String) { if alpha>0.00001 { result.strokes.append(.init(points:points,width:width,alpha:min(1,alpha),color:color)) } }
        func glow(_ p:PartyPoint,_ rx:Double,_ ry:Double,_ alpha:Double,_ color:String) { if alpha>0.00001 { result.glows.append(.init(point:p,rx:rx,ry:ry,alpha:min(1,alpha),color:color)) } }
        func rune(_ p:PartyPoint,_ radius:Double,_ angle:Double,_ alpha:Double,_ color:String,_ index:Int) {
            let local:[PartyPoint]=index%3==0 ? [.init(-0.4,-0.8),.init(0.4,0),.init(-0.4,0.8),.init(0,0),.init(-0.4,-0.8)]:index%3==1 ? [.init(-0.5,-0.8),.init(0.5,-0.25),.init(-0.3,0.1),.init(0.5,0.8)]:[.init(-0.6,0.6),.init(0,-0.8),.init(0.6,0.6),.init(-0.6,0.6)]
            let points=local.map { v in PartyPoint(p.x+(v.x*cos(angle)-v.y*sin(angle))*radius,p.y+(v.x*sin(angle)+v.y*cos(angle))*radius) }
            stroke(points,2.6,alpha,color)
        }
        func seal(_ p:PartyPoint,_ radius:Double,_ turn:Double,_ alpha:Double,_ color:String,_ split:Double=0) {
            for side in 0..<2 {
                let points=(0...32).map { i -> PartyPoint in
                    let a=turn+Double(side)*Double.pi+Double(i)/32*Double.pi
                    return .init(p.x+cos(a)*radius+(side==0 ? split:-split),p.y+sin(a)*radius*0.86)
                }
                stroke(points,3.0,alpha*0.70,color)
            }
            for i in 0..<8 {
                let a=turn+Double(i)*Double.pi/4
                rune(.init(p.x+cos(a)*radius*0.74,p.y+sin(a)*radius*0.65),9,a+Double.pi/2,alpha,color,i)
            }
        }
        let color="gold"
        for (index,v) in recipients.enumerated() {
                guard let foot=PartyVisual.foot(v.unitID) else { continue }
                let chest=PartyPoint(foot.x+5,foot.y-69),build=PartyVisual.smooth(age/hit)
                let opacity=PartyVisual.smooth(age/0.25)*(1-PartyVisual.smooth((age-hit-0.18)/0.85))
                let radius=33.0+17.0*build
                seal(chest,radius,-age*0.75+Double(index)*0.4,opacity*0.68,color)
                for sign in [-1.0,1.0] {
                    let rise=PartyVisual.smooth((age-0.12)/0.74),p=PartyPoint(chest.x+sign*(48-28*rise),chest.y+26-63*rise)
                    rune(p,19,-sign*age*0.5,opacity,"gold",2)
                }
                glow(chest,72,100,opacity*0.16,color)
                let contact=PartyVisual.pulse(age,hit,hit+0.06,hit+0.70)
                glow(foot,110,23,contact*0.54,color)
                if v.unitID != actor {
                    let end=PartyPoint(foot.x,foot.y-70),alpha=PartyVisual.pulse(age,0.10,hit*0.65,hit+0.35)
                    stroke((0...40).map { PartyVisual.beam(source,end,Double($0)/40) },2,alpha*0.58,color)
                }
                for i in 0..<22 {
                    let t=age-hit-Double(i%6)*0.025,life=1.15+Double(i%4)*0.09
                    guard t>0,t<life else { continue }
                    let u=t/life,a=Double(i)*2.399+u*2.8,r=30.0*(1-u*0.35),p=PartyPoint(chest.x+cos(a)*r,chest.y+40-u*135)
                    result.motes.append(.init(id:100+index*30+i,point:p,size:i%5==0 ? 8:4,angle:a,alpha:sin(Double.pi*u)*0.88,color:i%4==0 ? "gold":color,groundAge:nil,ground:foot))
                }
        }
        return result
    }

    /// The source sequence begins at the exact damage receipt. Fractional frame
    /// blending keeps its 20 authored poses smooth at the requested 60 Hz.
    private static func dragonFlame(age:Double,targetIDs:[String],templates:[String:String])->RuneEffectSample {
        var result=RuneEffectSample()
        let hit=PartyAction.dragonFlame.impact,elapsed=age-hit
        guard elapsed>=0,elapsed<1.95 else { return result }
        // 15 FPS base with a short authored hold across the 11–13 impact burst.
        let durations=(0..<20).map { (10...12).contains($0) ? 0.10:1.0/15.0 }
        let sequenceDuration=durations.reduce(0,+)
        var frameTime=elapsed,lower=0
        while lower<19 && frameTime>=durations[lower] { frameTime-=durations[lower];lower+=1 }
        let upper=min(19,lower+1),mix=lower==19 ? 0:frameTime/durations[lower]
        let tail=elapsed>sequenceDuration ? 1-PartyVisual.smooth((elapsed-sequenceDuration)/0.15):1
        for (index,id) in targetIDs.enumerated() {
            guard let foot=PartyVisual.foot(id) else { continue }
            let body=PartyVisual.hitPoint(target:id,templateID:templates[id])
            let center=body,spriteSize=280.0
            let lowerWeight=(lower==upper ? 1:1-mix)*tail
            if lowerWeight>0.001 { result.spriteLayers.append(.init(asset:String(format:"MeadowDragonFlame%02d",lower+1),center:center,size:spriteSize,alpha:lowerWeight)) }
            if upper != lower,mix*tail>0.001 { result.spriteLayers.append(.init(asset:String(format:"MeadowDragonFlame%02d",upper+1),center:center,size:spriteSize,alpha:mix*tail)) }

            func glow(_ point:PartyPoint,_ rx:Double,_ ry:Double,_ alpha:Double,_ color:String) {
                if alpha>0.001 { result.glows.append(.init(point:point,rx:rx,ry:ry,alpha:min(1,alpha),color:color)) }
            }
            // Broad warm spill lifts the monster, grass and nearby scene over
            // the skill's deliberate screen dim; a tighter pulse marks contact.
            let bodyFlash=PartyVisual.pulse(age,hit,hit+0.045,hit+0.82)
            let sceneSpill=PartyVisual.pulse(age,hit,hit+0.18,hit+1.05)
            let groundFlash=PartyVisual.pulse(age,hit+0.04,hit+0.26,hit+1.12)
            glow(body,124,106,bodyFlash*0.72,"fireGold")
            glow(PartyPoint(body.x,body.y-16),190,152,sceneSpill*0.33,"fireOrange")
            glow(PartyPoint(foot.x,foot.y-4),188,32,groundFlash*0.70,"fireRed")
            glow(PartyPoint(foot.x,foot.y-4),120,18,groundFlash*0.48,"fireGold")

            // Warm embers fly out from the body, arc under gravity, then make
            // a short visible ground contact with a colored spark and light.
            for i in 0..<36 {
                let delay=Double(i%8)*0.026,local=elapsed-delay
                let life=1.36+Double(i%5)*0.075
                guard local>=0,local<life else { continue }
                let spread=Double(i%13)-6
                let vx=spread*12.5+(i%2==0 ? -18:18)
                let vy = -(92+Double((i*7)%8)*17)
                let gravity=330.0,offsetX=Double((i*5)%9-4)*2.8,offsetY = -Double(i%5)*3.0
                let start=PartyPoint(body.x+offsetX,body.y+8+offsetY),groundY=foot.y-4
                let gap=max(0,groundY-start.y)
                let impactTime=(-vy+sqrt(vy*vy+2*gravity*gap))/gravity
                let x=start.x+vx*local
                var y=start.y+vy*local+0.5*gravity*local*local
                var groundAge:Double?=nil
                let groundX=start.x+vx*impactTime
                if local>=impactTime {
                    let bounce=local-impactTime
                    groundAge=bounce<0.23 ? bounce:nil
                    if bounce<0.23 { y=groundY-(31*bounce-0.5*185*bounce*bounce) }
                    else { y=groundY }
                }
                let alpha=0.90*(1-PartyVisual.smooth(local/life))
                let color:[String] = ["fireOrange","fireGold","fireRed","fireGold","fireWhite"]
                result.motes.append(.init(id:700+index*40+i,point:PartyPoint(x,y),size:i%9==0 ? 10:i%3==0 ? 7:4,angle:Double(i)*2.399+local*2.4,alpha:alpha,color:color[i%color.count],groundAge:groundAge,ground:PartyPoint(groundX,groundY)))
            }
        }
        return result
    }
}
