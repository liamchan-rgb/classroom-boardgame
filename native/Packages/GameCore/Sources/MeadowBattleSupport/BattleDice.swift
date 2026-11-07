import Foundation
import ClassroomGameCore

public struct BattleDie:Codable,Equatable {
    public let color:String
    public let sides:Int
    public let value:Int?
    public let label:String
    public init(_ color:String,sides:Int=0,value:Int?=nil,label:String="定值") { self.color=color;self.sides=sides;self.value=value;self.label=label }
}
public struct BattleDiePose:Codable {
    public let angle:Double,offsetY:Double,scale:Double,resultMix:Double,alpha:Double
    public let face:Int
}
public enum BattleDice {
    /// No RNG is used here: only the engine receipt may supply a rolled result.
    public static func channels(_ action:PartyAction,actor:GameUnit,target:GameUnit,catalog:GameCatalog,receipt:OperationReceipt?=nil,sourceSkillID:String?=nil)->[BattleDie] {
        if action == .endTurn { return [] }
        if let sourceSkillID{return skillChannels(sourceSkillID,actor:actor,catalog:catalog,receipt:receipt)}
        if action == .revivalStone { let maximum=(try? GameRules.attributes(target,catalog:catalog).maximumHealth) ?? target.baseAttributes.maximumHealth;return [BattleDie("green",value:(maximum+1)/2,label:"固定复活")] }
        if action == .attack {
            guard let attack=try? GameRules.attack(actor,catalog:catalog) else { return [] }
            let roll=receipt?.dice.first { $0.source=="damage" }
            return formula(roll?.formula ?? attack.dice,color:"red",roll:roll)+modifiers(actor,catalog:catalog,committed:receipt != nil)
        }
        if action.isItem,let item=try? catalog.item(action.rawValue) {
            var result:[BattleDie]=[]
            if item.heal>0 { result.append(.init("green",value:item.heal,label:"固定恢复")) }
            if item.shield>0 { result.append(.init("blue",value:item.shield,label:"固定授盾")) }
            return result
        }
        return skillChannels(action.rawValue,actor:actor,catalog:catalog,receipt:receipt)
    }
    private static func formula(_ value:DiceFormula,color:String,roll:DiceResult?)->[BattleDie] {
        var result=(0..<value.count).map { i in BattleDie(color,sides:value.sides,value:roll.flatMap { i<$0.values.count ? $0.values[i]:nil },label:"D\(value.sides)") }
        if value.flat != 0 { result.append(BattleDie("yellow",value:value.flat,label:"固定加值")) }
        return result
    }
    private static func modifiers(_ actor:GameUnit,catalog:GameCatalog,committed:Bool)->[BattleDie] {
        var result:[BattleDie]=[]
        let buff=actor.damageBuff?.amount ?? 0
        let base=(try? GameRules.attributes(actor,catalog:catalog).damage).map { $0-buff } ?? 0
        if base != 0 { result.append(.init("yellow",value:base,label:"固定属性")) }
        if buff != 0 { result.append(.init("yellow",value:buff,label:"固定增伤")) }
        return result
    }
    /// Resolves every die in the source formula, including two-die skills and
    /// rolled support effects. Fixed amounts remain explicitly marked counters.
    public static func skillChannels(_ id:String,actor:GameUnit,catalog:GameCatalog,receipt:OperationReceipt?=nil)->[BattleDie] {
        guard let skill=try? catalog.skill(id) else { return [] }
        var result:[BattleDie]=[],used:[String:Int]=[:]
        for effect in skill.effects {
            let key=effect.kind.rawValue,color=effect.kind == .damage ? "red":effect.kind == .heal ? "green":effect.kind == .shield ? "blue":"yellow"
            let label=effect.kind == .damage ? "固定加值":effect.kind == .heal ? "固定恢复":effect.kind == .shield ? "固定授盾":"固定增伤"
            if let dice=effect.dice {
                let matches=receipt?.dice.filter { $0.source==key } ?? [],index=used[key] ?? 0
                let roll=index<matches.count ? matches[index]:nil;used[key]=index+1
                result += formula(roll?.formula ?? dice,color:color,roll:roll)
            }
            if effect.amount != 0 { result.append(.init(color,value:effect.amount,label:label)) }
        }
        if skill.effects.contains(where: { $0.kind == .damage }) { result += modifiers(actor,catalog:catalog,committed:receipt != nil) }
        return result
    }
    public static func pose(time:Double,index:Int,resolvedAge:Double?,visibleAge:Double,exitAge:Double?=nil)->BattleDiePose {
        let settle=resolvedAge.map { PartyVisual.smooth($0/0.65) } ?? 0
        let moving=1-settle,t=time*13+Double(index)*2.1
        let fade=exitAge.map { 1-PartyVisual.smooth($0/0.22) } ?? (resolvedAge.map { 1-PartyVisual.smooth(($0-1.10)/0.4) } ?? 1)
        return BattleDiePose(angle:(sin(t)*0.21+sin(t*0.47)*0.09)*moving,offsetY:(sin(t*0.79)*4)*moving,scale:1+sin(t*0.69)*0.035*moving,resultMix:settle,alpha:PartyVisual.smooth(visibleAge/0.18)*fade,face:Int(floor(max(0,time)*11+Double(index)*1.7)).quotientAndRemainder(dividingBy:6).remainder+1)
    }
    public static func darkness(_ action:PartyAction)->Double {
        switch action { case .runeSlash:return 0.64;case .dragonFlame:return 0.66;case .runeWard:return 0.48;case .battleRune:return 0.44;case .ambush:return 0.52;case .heavyStrike:return 0.46;case .attack:return 0.24;case .support:return 0.32;case .rally:return 0.36;case .largePotion,.revivalStone:return 0.34;case .simpleGuard,.shieldPotion:return 0.25;case .endTurn:return 0;default:return 0.22 }
    }
}

public struct PartyMonsterPose:Codable {
    public let progress:Double,scaleY:Double,recoil:Double,flash:Double
}
extension PartyVisual {
    /// Existing attack artwork plus subtle registered idle/preparation/hit/recovery.
    public static func monster(time:Double,attackAge:Double?,hurtAge:Double?=nil,preparing:Bool=false)->PartyMonsterPose {
        let p=attackAge.map { min(1,max(0,$0/0.96)) } ?? 0
        let breathing=sin(time*2.4)*0.007
        let hit=hurtAge.map { pulse($0,0,0.055,0.42) } ?? 0
        let prepare=preparing ? 0.012*(0.5+0.5*sin(time*6)):0
        return PartyMonsterPose(progress:p,scaleY:1+breathing-prepare-hit*0.012,recoil:hit*14,flash:hit*0.65)
    }
}

extension PartyVisual {
    public static func diceAnchor(actor:String,intent:PartyIntent?,age:Double,shielded:Bool=false,diceCount:Int=2,monsterTemplateID:String?=nil)->PartyPoint {
        // Campaign identities (m-<node>-<index>) share the reviewed m1/m2
        // formation. Resolve both ends just like travel, hit and HP labels.
        guard let actorFoot=foot(actor) else { return PartyPoint(width/2,0) }
        let moving=intent?.actor==actor ? travel(intent,age:age,shielded:shielded):PartyPoint(0,0)
        var inset=0.0
        if let intent,!intent.enemy,intent.action.isOffensive,intent.actor==actor,let to=foot(intent.target) {
            let halfWidth=Double(max(0,diceCount-1))*PolyhedralDice.spacing(count:diceCount)/2+PolyhedralDice.radius(count:diceCount)*1.3
            let old=hitPoint(target:intent.target,weaponID:intent.weaponID),new=hitPoint(target:intent.target,weaponID:intent.weaponID,templateID:intent.targetTemplateID)
            let correction=new.x-old.x
            inset=(max(18,halfWidth-36)+max(0,correction))*min(1,abs(moving.x)/max(1,abs(to.x-140+correction-actorFoot.x)))
        }
        var x=actorFoot.x+moving.x-inset
        if actor=="p2",let firstPlayer=foot("p1") {
            // A wide group over P2 otherwise intersects P1's fixed HP header.
            let half=Double(max(0,diceCount-1))*PolyhedralDice.spacing(count:diceCount)/2+PolyhedralDice.radius(count:diceCount)*1.3
            x=max(x,firstPlayer.x+88+12+half)
        }
        let spec=MonsterVisualSpec.find(monsterTemplateID ?? intent?.monsterTemplateID)
        let lift=actor.hasPrefix("m") ? (spec.map{224*$0.scale+156} ?? 357):287
        return PartyPoint(x,actorFoot.y+moving.y-lift)
    }
}
