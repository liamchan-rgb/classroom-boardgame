import Foundation
import ClassroomGameCore

public enum PartyAction:String,CaseIterable,Codable {
    case regeneration,attack,heavyStrike,ambush,breather,simpleGuard,support,rally,runeSlash,runeWard,battleRune,dragonFlame,starlightPulse,sweep,dragonSoulWard,dragonScaleWard,dragonOrder,smallPotion,largePotion,shieldPotion,revivalStone,endTurn
    public var title:String {
        switch self {
        case .regeneration:return "再生"
        case .attack:return "普通攻击"
        case .heavyStrike:return "强击"
        case .ambush:return "突袭"
        case .breather:return "喘息"
        case .simpleGuard:return "简易防护"
        case .support:return "援护"
        case .rally:return "振奋"
        case .runeSlash:return "符文斩"
        case .runeWard:return "符文庇护"
        case .battleRune:return "战斗符文"
        case .dragonFlame:return "龙焰"
        case .starlightPulse:return "星辉脉冲"
        case .sweep:return "横扫"
        case .dragonSoulWard:return "龙魂庇护"
        case .dragonScaleWard:return "龙鳞庇护"
        case .dragonOrder:return "龙之号令"
        case .smallPotion:return "小治疗药水"
        case .largePotion:return "大治疗药水"
        case .shieldPotion:return "护盾药水"
        case .revivalStone:return "复活石"
        case .endTurn:return "结束行动"
        }
    }
    public var visual:String {
        switch self {
        case .runeSlash,.runeWard,.battleRune,.dragonFlame:return rawValue
        case .starlightPulse,.sweep:return "attack"
        case .rally,.dragonSoulWard,.dragonScaleWard,.dragonOrder:return "support"
        case .ambush:return "ambush"
        case .support:return "support"
        case .regeneration,.breather,.smallPotion,.largePotion:return "heal"
        case .simpleGuard,.shieldPotion:return "guard"
        case .revivalStone:return "revive"
        case .endTurn:return "wait"
        default:return "attack"
        }
    }
    public var isRune:Bool { [.runeSlash,.runeWard,.battleRune].contains(self) }
    public var skillVFX:PartySkillVFXSpec? { PartySkillVFXSpec.find(rawValue) }
    public var statusVFXCueAge:Double? { SpellbladeEffects.statusVFXCueAge(for:self) }
    public var usesRangedMotion:Bool { self == .starlightPulse }
    public var isNodeCast:Bool { [.rally,.runeWard,.battleRune,.dragonFlame,.starlightPulse,.sweep,.dragonSoulWard,.dragonScaleWard,.dragonOrder].contains(self) }
    public var isNodeSupport:Bool { [.rally,.runeWard,.battleRune,.dragonSoulWard,.dragonScaleWard,.dragonOrder].contains(self) }
    public var impact:Double { if self == .runeSlash { return 1.048 };if self == .runeWard { return 0.72 };if self == .battleRune { return 0.56 };if self == .endTurn { return 0 };if self == .ambush { return 0.72 };if self == .dragonFlame { return 0.46 };return visual == "attack" ? 1.048 : visual == "support" ? 0.56 : visual == "revive" ? 0.72 : 0.46 }
    public var duration:Double { if self == .runeSlash { return 3.0 };if self == .runeWard { return 2.65 };if self == .battleRune { return 2.30 };if self == .dragonFlame { return 2.75 };if self == .endTurn { return 0.25 };if self == .ambush { return 2.10 };return visual == "attack" ? 1.70 : visual == "revive" ? 2.10 : 1.80 }
    public var isOffensive:Bool { [.attack,.heavyStrike,.ambush,.runeSlash,.dragonFlame,.starlightPulse,.sweep].contains(self) }
    public var isItem:Bool { [.smallPotion,.largePotion,.shieldPotion,.revivalStone].contains(self) }
}
public struct PartyIntent {
    public let id:String
    public let action:PartyAction
    public let actor:String
    public let target:String
    public let targets:[String]
    public let command:GameCommand
    public let enemy:Bool
    public let weaponID:String?
    public var monsterTemplateID:String?=nil
    public var enemyRanged:Bool=false
    public var sourceSkillID:String?=nil
    public var targetTemplateID:String?=nil
    public var impactAge:Double { enemy ? 0.46:action.impact }
    public var visualDuration:Double { enemy && action == .attack ? 1.10:action.duration }
    public init(id:String,action:PartyAction,actor:String,target:String,targets:[String],command:GameCommand,enemy:Bool,weaponID:String?,monsterTemplateID:String?=nil,enemyRanged:Bool=false,sourceSkillID:String?=nil,targetTemplateID:String?=nil) {
        self.id=id;self.action=action;self.actor=actor;self.target=target;self.targets=targets;self.command=command;self.enemy=enemy;self.weaponID=weaponID;self.monsterTemplateID=monsterTemplateID;self.enemyRanged=enemyRanged;self.sourceSkillID=sourceSkillID;self.targetTemplateID=targetTemplateID
    }
    public var magical:Bool { weaponID=="legendaryStaff" && !enemy && action.visual=="attack" && action != .starlightPulse }
    public var ranged:Bool { enemyRanged || weaponID=="huntingBow" && !enemy && action.isOffensive && !action.isRune && action != .dragonFlame && action != .starlightPulse }
}
/// Uses the original atomic rule engine. Pending visual actions do not mutate it.
public final class PartyEncounter {
    public private(set) var engine:GameEngine
    public private(set) var pending:PartyIntent?
    public private(set) var confirmedReceipt:OperationReceipt?
    private var confirmedEngine:GameEngine?
    public let monsterIDs:[String]
    public let sessionID:String
    private var serial=0
    public var state:GameState { engine.state }
    public var current:String? { state.battle?.current }
    public var round:Int { state.battle?.round ?? 0 }
    public var terminal:Bool { state.battle == nil || state.pauseReasons.contains(.allPlayersDown) }
    public init(seed:UInt64=UInt64.random(in:1...UInt64.max),sessionID:String=UUID().uuidString,loadouts:[String:GameUnit]?=nil,playerClassID:String="adventurer") throws {
        guard ["adventurer","spellblade","dragonKnight"].contains(playerClassID) else { throw GameError("该职业尚未接入演练。") }
        self.sessionID=sessionID
        self.monsterIDs=["m1","m2"]
        var catalog=try GameCatalog.initial()
        // A local training creature using the existing deer art. The six formal
        // monster definitions and all19 skills/18 items remain unchanged.
        var warden=try catalog.monster("wolf")
        warden.id="meadowTrainingWarden";warden.name="林地鹿灵"
        warden.attributes=Attributes(maximumHealth:18,baseAP:1,maximumAP:8)
        warden.attack=AttackDefinition(dice:DiceFormula(sides:6),range:0)
        warden.skills=[];warden.drops=[];warden.score=0
        catalog.monsters.append(warden);try catalog.validate()
        var units:[String:GameUnit]=[:]
        units["p1"]=try GameFactory.player(id:"p1",name:"P1 · "+catalog.playerClass(playerClassID).name,classID:playerClassID,teamID:"party",nodeID:1,catalog:catalog)
        units["p2"]=try GameFactory.player(id:"p2",name:"P2 · 游侠",classID:"ranger",teamID:"party",nodeID:1,catalog:catalog)
        for id in ["p1","p2"] {
            units[id]?.inventory=["smallPotion":2,"largePotion":1,"shieldPotion":1,"revivalStone":1]
            if let source=loadouts?[id] {
                units[id]?.equipment=source.equipment
                units[id]?.ap=source.ap
                for (item,count) in source.inventory where (try? catalog.item(item).slot) != nil { units[id]?.inventory[item]=count }
            }
        }
        // Same battle-entry refill as GameEngine.start, including equipped AP.
        for id in ["p1","p2"] {
            if var unit=units[id] { try GameRules.refill(&unit,catalog:catalog);units[id]=unit }
        }
        units["p1"]?.health=playerClassID=="spellblade" ? 12:playerClassID=="dragonKnight" ? 20:6;units["p2"]?.health=12
        for (i,id) in ["m1","m2"].enumerated() {
            units[id]=try GameFactory.monster(id:id,templateID:warden.id,nodeID:1,catalog:catalog)
            units[id]?.active=true;units[id]?.name="鹿灵\(i==0 ? "甲":"乙")"
        }
        let map=GameMap(nodes:[MapNode(id:0,name:"营地",kind:.start),MapNode(id:1,name:"林地演练",kind:.combat)],roads:[MapRoad(0,1)],revealed:[0,1])
        var state=GameState(gameID:sessionID,units:units,teams:[GameTeam(id:"party",name:"旅人小队")],map:map,random:RandomState(seed:seed))
        state.pauseReasons=[];state.phase = .pve
        state.battle=BattleState(kind:.pve,queue:["p2","p1","m1","m2"],current:"p2")
        self.engine=try GameEngine(catalog:catalog,state:state)
    }
    public init(engine:GameEngine,sessionID:String=UUID().uuidString) throws {
        guard let battle=engine.state.battle,battle.kind == .pve else {throw GameError("当前没有探索战斗。")}
        self.engine=engine;self.sessionID=sessionID
        self.monsterIDs=battle.queue.filter{engine.state.units[$0]?.kind == .monster}.sorted()
        guard (1...3).contains(monsterIDs.count) else {throw GameError("当前战场支持1—3个敌人。")}
    }
    public func command(_ action:PartyAction,target:String)->GameCommand? {
        guard let actor=current else { return nil }
        switch action {
        case .attack:return .attack(actor:actor,target:target)
        case .endTurn:return .endTurn(actor:actor,timedOut:false)
        case .revivalStone:return .rescue(actor:actor,target:target)
        case .smallPotion,.largePotion,.shieldPotion:return .useItem(actor:actor,item:action.rawValue,target:target)
        case .rally,.runeWard,.battleRune,.dragonFlame,.starlightPulse,.sweep,.dragonSoulWard,.dragonScaleWard,.dragonOrder:return .cast(actor:actor,skill:action.rawValue,target:.node(state.units[target]?.nodeID ?? 1))
        case .regeneration,.breather,.simpleGuard:return .cast(actor:actor,skill:action.rawValue,target:.unit(actor))
        default:return .cast(actor:actor,skill:action.rawValue,target:.unit(target))
        }
    }
    public func preview(_ action:PartyAction,target:String)->ActionPreview {
        guard pending==nil,let command=command(action,target:target),!terminal else { return ActionPreview(allowed:false,message:"等待当前动作完成") }
        return engine.preview(command)
    }
    @discardableResult public func prepare(_ action:PartyAction,target:String)->PartyIntent? {
        guard pending==nil,preview(action,target:target).allowed,let actor=current,let command=command(action,target:target) else { return nil }
        serial += 1
        let targets:[String]
        if action.isNodeSupport { targets=state.players.filter { $0.isAlive && $0.nodeID==state.units[target]?.nodeID }.map(\.id) }
        else if action == .dragonFlame || action == .starlightPulse { targets=state.units.values.filter { $0.kind == .monster && $0.isAlive && $0.nodeID==state.units[target]?.nodeID }.map(\.id).sorted() }
        else if action == .sweep { targets=state.players.filter { $0.isAlive && $0.nodeID==state.units[target]?.nodeID }.map(\.id).sorted() }
        else if action == .regeneration || action == .breather || action == .simpleGuard { targets=[actor] }
        else { targets=[target] }
        let intent=PartyIntent(id:sessionID+"/"+String(serial),action:action,actor:actor,target:target,targets:targets,command:command,enemy:state.units[actor]?.kind == .monster,weaponID:state.units[actor]?.equipment.weapon,targetTemplateID:state.units[target]?.templateID)
        // Resolve once in an isolated transaction at confirmation. Live HP/AP,
        // RNG and history remain unchanged until the visible impact commits it.
        guard let staged=try? GameEngine(catalog:engine.catalog,state:state,history:engine.history),
              let receipt=try? staged.apply(command,id:intent.id) else { return nil }
        confirmedEngine=staged;confirmedReceipt=receipt;pending=intent;return intent
    }
    /// Exactly one atomic result at the visible contact; no duplicate effects on replay.
    public func commit(_ id:String) throws -> OperationReceipt? {
        guard let intent=pending,intent.id==id else { return nil }
        guard let staged=confirmedEngine,let receipt=confirmedReceipt else { return nil }
        defer { cancel() }
        guard state==receipt.before else { throw GameError("动作确认后状态已变化，请重新选择。") }
        guard staged.state==receipt.after else {throw GameError("确认回执无效。")}
        return try engine.apply(intent.command,id:intent.id)
    }
    /// Ask the original monster AI to select and roll exactly once, then show
    /// that staged receipt using the already-supported melee/heal animations.
    @discardableResult public func prepareMonsterStep()->PartyIntent? {
        guard pending==nil,!terminal,let actor=current,state.units[actor]?.kind == .monster else{return nil}
        serial+=1;let id=sessionID+"/"+String(serial)
        guard let staged=try? GameEngine(catalog:engine.catalog,state:state,history:engine.history),let receipt=try? staged.apply(.monsterStep,id:id) else{return nil}
        let skillName=receipt.events.first{$0.kind=="aiAction"}?.detail
        let ownSkills=(try? engine.catalog.monster(state.units[actor]!.templateID).skills) ?? []
        let skillID=ownSkills.first{(try? engine.catalog.skill($0).name)==skillName}
        let aliases:[String:PartyAction]=["stoneSkin":.simpleGuard,"monsterDragonScale":.dragonScaleWard,"monsterDragonFlame":.dragonFlame]
        let action=skillID.flatMap{aliases[$0] ?? PartyAction(rawValue:$0)} ?? .attack
        let changed=state.units.keys.sorted().filter{key in
            guard let before=state.units[key],let after=receipt.after.units[key] else{return false}
            return before.health != after.health || before.shield != after.shield || before.damageBuff != after.damageBuff
        }
        let targets=changed.isEmpty ? [nextEnemyTarget() ?? "p1"]:changed
        let intent=PartyIntent(id:id,action:action,actor:actor,target:targets[0],targets:targets,command:.monsterStep,enemy:true,weaponID:nil,monsterTemplateID:state.units[actor]?.templateID,enemyRanged:action == .attack && ((try? engine.catalog.monster(state.units[actor]!.templateID).attack.range) ?? 0)>0,sourceSkillID:skillID,targetTemplateID:state.units[targets[0]]?.templateID)
        confirmedEngine=staged;confirmedReceipt=receipt;pending=intent;return intent
    }
    public func cancel() { pending=nil;confirmedEngine=nil;confirmedReceipt=nil }
    public func playerActions()->[PartyAction] { current.map(actions(for:)) ?? [] }
    public func actions(for actor:String)->[PartyAction] {
        guard let unit=state.units[actor],unit.kind == .player else { return [] }
        let available=(try? GameRules.skills(unit,catalog:engine.catalog)) ?? []
        return [.attack]+available.compactMap(PartyAction.init(rawValue:))
    }
    public func cost(_ action:PartyAction)->Int {
        if action == .endTurn { return 0 };if action == .revivalStone { return 2 }
        return (try? engine.catalog.skill(action.rawValue).cost) ?? 1
    }
    public func nextEnemyTarget()->String? { state.players.filter(\.isAlive).min { a,b in Double(a.health)/Double(a.baseAttributes.maximumHealth)<Double(b.health)/Double(b.baseAttributes.maximumHealth) }?.id }
}
