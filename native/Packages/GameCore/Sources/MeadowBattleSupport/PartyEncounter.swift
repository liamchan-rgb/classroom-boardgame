import Foundation
import ClassroomGameCore

public enum PartyAction:String,CaseIterable,Codable {
    // Classic actions
    case regeneration,attack,heavyStrike,ambush,breather,simpleGuard,support,rally,runeSlash,runeWard,battleRune,dragonFlame,starlightPulse,sweep,dragonSoulWard,dragonScaleWard,dragonOrder,smallPotion,largePotion,shieldPotion,revivalStone,endTurn
    // +30 Expansion class skills
    case holyBolt,prayerHeal,blessingVeil,quickShot,nimbleStep,scoutMark,shieldBash,ironBulwark,steadfastVow,fireball,frostNova,manaBarrier,sonicNote,healingLullaby,heroicAnthem,judgmentStrike,radiantBaptism,oathBanner,piercingArrow,galeBarrage,windMomentum,thornSnare,elderBloom,barkAegis,meteorStarfall,astralDome,arcaneOverdrive,skybreaker,valkyrieGuard,warlordRoar
    // +6 Expansion set skills
    case wildwoodBreeze,galeVolley,oakBulwark,emberNova,seraphAegis,astralJudgement
    // +26 Expansion monster skills
    case sporeCoat,waspFrenzy,vineGuard,shamanMend,shamanChant,emberBreath,nightPlume,runeCleave,armorCharge,crystalShell,quakeSlam,frostHowl,frostFang,kingRegen,capSlam,warlordRally,boomBomb,heartwoodWall,ancientRegen,rootSweep,glacialWard,frostRebirth,blizzardBreath,celestialBastion,stellarSurge,eclipseRay
    // +8 Expansion consumables
    case berryTea,ironbarkElixir,honeySalve,superPotion,crystalBarrierFlask,phoenixNectar,starlightElixir,aegisCrystal

    public static let allConsumables:[PartyAction]=[
        .smallPotion,.berryTea,.shieldPotion,.largePotion,.ironbarkElixir,.revivalStone,
        .honeySalve,.superPotion,.crystalBarrierFlask,.phoenixNectar,.starlightElixir,.aegisCrystal
    ]

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
        // Class skills
        case .holyBolt:return "圣光弹"
        case .prayerHeal:return "祈祷愈合"
        case .blessingVeil:return "祈福护幕"
        case .quickShot:return "迅捷快射"
        case .nimbleStep:return "轻身步"
        case .scoutMark:return "弱点标记"
        case .shieldBash:return "盾击震荡"
        case .ironBulwark:return "钢铁壁垒"
        case .steadfastVow:return "坚守反击"
        case .fireball:return "烈焰火球"
        case .frostNova:return "冰霜新星"
        case .manaBarrier:return "魔力屏障"
        case .sonicNote:return "音波箭"
        case .healingLullaby:return "治愈摇篮曲"
        case .heroicAnthem:return "英雄赞歌"
        case .judgmentStrike:return "审判重击"
        case .radiantBaptism:return "圣光洗礼"
        case .oathBanner:return "誓约战旗"
        case .piercingArrow:return "穿云箭"
        case .galeBarrage:return "疾风连射"
        case .windMomentum:return "猎风迅捷"
        case .thornSnare:return "荆棘缠绕"
        case .elderBloom:return "生命古树"
        case .barkAegis:return "树皮灵甲"
        case .meteorStarfall:return "星辰陨落"
        case .astralDome:return "穹顶圣盾"
        case .arcaneOverdrive:return "奥术超载"
        case .skybreaker:return "天穹断空"
        case .valkyrieGuard:return "英灵护佑"
        case .warlordRoar:return "战神怒吼"
        // Set skills
        case .wildwoodBreeze:return "林风祈愿"
        case .galeVolley:return "飓风齐射"
        case .oakBulwark:return "大地壁垒"
        case .emberNova:return "炽焰陨爆"
        case .seraphAegis:return "圣盾天降"
        case .astralJudgement:return "终焉星陨"
        // Monster skills
        case .sporeCoat:return "孢子薄膜"
        case .waspFrenzy:return "蜂群振翅"
        case .vineGuard:return "藤蔓缠壁"
        case .shamanMend:return "部落愈合"
        case .shamanChant:return "战鼓呐喊"
        case .emberBreath:return "火星吐息"
        case .nightPlume:return "夜幕羽盾"
        case .runeCleave:return "符文重斩"
        case .armorCharge:return "铁壁蓄能"
        case .crystalShell:return "晶化护壳"
        case .quakeSlam:return "震地冲击"
        case .frostHowl:return "霜狼嗥叫"
        case .frostFang:return "冰牙连扑"
        case .kingRegen:return "孢子回春"
        case .capSlam:return "菌盖震击"
        case .warlordRally:return "战酋号令"
        case .boomBomb:return "轰天爆弹"
        case .heartwoodWall:return "树心护壁"
        case .ancientRegen:return "古木再生"
        case .rootSweep:return "根须横扫"
        case .glacialWard:return "寒冰羽壁"
        case .frostRebirth:return "冰晶浴火"
        case .blizzardBreath:return "极寒风暴"
        case .celestialBastion:return "星穹壁垒"
        case .stellarSurge:return "星核充能"
        case .eclipseRay:return "星蚀吐息"
        // Consumables
        case .berryTea:return "浆果暖茶"
        case .ironbarkElixir:return "铁皮护盾剂"
        case .honeySalve:return "蜂蜜修复膏"
        case .superPotion:return "特级生命圣药"
        case .crystalBarrierFlask:return "晶壁魔瓶"
        case .phoenixNectar:return "炽凰琼浆"
        case .starlightElixir:return "星辉灵液"
        case .aegisCrystal:return "苍穹圣晶"
        }
    }
    public var visual:String {
        switch self {
        case .runeSlash,.runeWard,.battleRune,.dragonFlame:return rawValue
        case .ambush:return "ambush"
        case .regeneration,.breather,.smallPotion,.largePotion,.prayerHeal,.healingLullaby,.elderBloom,.kingRegen,.ancientRegen,.frostRebirth,.shamanMend,.berryTea,.honeySalve,.superPotion,.phoenixNectar,.starlightElixir,.aegisCrystal:return "heal"
        case .simpleGuard,.shieldPotion,.ironbarkElixir,.crystalBarrierFlask,.ironBulwark,.blessingVeil,.barkAegis,.astralDome,.oakBulwark,.sporeCoat,.vineGuard,.nightPlume,.armorCharge,.crystalShell,.heartwoodWall,.glacialWard,.celestialBastion:return "guard"
        case .support,.rally,.dragonSoulWard,.dragonScaleWard,.dragonOrder,.nimbleStep,.scoutMark,.steadfastVow,.manaBarrier,.heroicAnthem,.radiantBaptism,.oathBanner,.windMomentum,.arcaneOverdrive,.valkyrieGuard,.warlordRoar,.wildwoodBreeze,.seraphAegis,.waspFrenzy,.shamanChant,.frostHowl,.warlordRally,.stellarSurge:return "support"
        case .revivalStone:return "revive"
        case .endTurn:return "wait"
        default:return "attack"
        }
    }
    public var isRune:Bool { [.runeSlash,.runeWard,.battleRune].contains(self) }
    public var skillVFX:PartySkillVFXSpec? { PartySkillVFXSpec.find(rawValue) }
    public var statusVFXCueAge:Double? { SpellbladeEffects.statusVFXCueAge(for:self) }
    public var usesRangedMotion:Bool {
        [.starlightPulse,.holyBolt,.quickShot,.fireball,.frostNova,.sonicNote,.piercingArrow,.galeBarrage,.thornSnare,.meteorStarfall,.galeVolley,.emberNova,.astralJudgement,
         .emberBreath,.quakeSlam,.boomBomb,.rootSweep,.blizzardBreath,.eclipseRay].contains(self)
    }
    public var isNodeAttack:Bool {
        [.dragonFlame,.starlightPulse,.sweep,.frostNova,.galeBarrage,.thornSnare,.meteorStarfall,.galeVolley,.emberNova,.astralJudgement,.emberBreath,.quakeSlam,.capSlam,.boomBomb,.rootSweep,.blizzardBreath,.eclipseRay].contains(self)
    }
    public var isNodeSupport:Bool {
        [.rally,.runeWard,.battleRune,.dragonSoulWard,.dragonScaleWard,.dragonOrder,.blessingVeil,.scoutMark,.ironBulwark,.manaBarrier,.healingLullaby,.heroicAnthem,.radiantBaptism,.oathBanner,.windMomentum,.elderBloom,.barkAegis,.astralDome,.arcaneOverdrive,.valkyrieGuard,.warlordRoar,.wildwoodBreeze,.oakBulwark,.seraphAegis,.shamanChant,.frostHowl].contains(self)
    }
    public var isSelfOnly:Bool {
        [.regeneration,.breather,.simpleGuard,.nimbleStep,.steadfastVow,.sporeCoat,.waspFrenzy,.vineGuard,.nightPlume,.armorCharge,.crystalShell,.kingRegen,.warlordRally,.heartwoodWall,.ancientRegen,.glacialWard,.frostRebirth,.celestialBastion,.stellarSurge].contains(self)
    }
    public var isNodeCast:Bool { isNodeSupport || isNodeAttack }
    public var impact:Double {
        if self == .runeSlash { return 1.048 }
        if self == .starlightPulse { return 1.048 }
        if self == .runeWard { return 0.72 }
        if self == .battleRune { return 0.56 }
        if self == .endTurn { return 0 }
        if self == .ambush { return 0.72 }
        if self == .dragonFlame { return 0.46 }
        if usesRangedMotion { return 0.72 }
        return visual == "attack" ? 1.048 : visual == "support" ? 0.56 : visual == "revive" ? 0.72 : 0.46
    }
    public var duration:Double {
        if self == .runeSlash { return 3.0 }
        if self == .runeWard { return 2.65 }
        if self == .battleRune { return 2.30 }
        if self == .dragonFlame { return 2.75 }
        if self == .endTurn { return 0.25 }
        if self == .ambush { return 2.10 }
        if [.meteorStarfall,.astralJudgement,.seraphAegis,.valkyrieGuard,.skybreaker,.blizzardBreath,.eclipseRay,.boomBomb].contains(self) { return 2.40 }
        return visual == "attack" ? 1.70 : visual == "revive" ? 2.10 : 1.80
    }
    public var isOffensive:Bool {
        [.attack,.heavyStrike,.ambush,.runeSlash,.dragonFlame,.starlightPulse,.sweep,
         .holyBolt,.quickShot,.shieldBash,.fireball,.frostNova,.sonicNote,.judgmentStrike,.piercingArrow,.galeBarrage,.thornSnare,.meteorStarfall,.skybreaker,
         .galeVolley,.emberNova,.astralJudgement,
         .emberBreath,.runeCleave,.quakeSlam,.frostFang,.capSlam,.boomBomb,.rootSweep,.blizzardBreath,.eclipseRay].contains(self)
    }
    public var isItem:Bool { Self.allConsumables.contains(self) }
}
public struct PartyIntent {
    public static let rangedWeapons:Set<String>=["huntingBow","oakSlingshot","thunderCrossbow","galeLongbow","astralGreatbow"]
    public static let magicalWeapons:Set<String>=["legendaryStaff","woodenStaff","frostWand","emeraldScepter","emberStaff","astralCodex"]
    public static let heavyWeapons:Set<String>=["greatSword","knightHalberd","flameAxe","oakHammer","sunbreakerBlade","aegisLance","dragonFangSword"]
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
    public var magical:Bool { weaponID.map(Self.magicalWeapons.contains) == true && !enemy && action.visual=="attack" && !action.usesRangedMotion }
    public var ranged:Bool { enemyRanged || (weaponID.map(Self.rangedWeapons.contains) == true && !enemy && action.isOffensive && !action.isRune && action != .dragonFlame && !action.usesRangedMotion) }
}
/// Uses the original atomic rule engine. Pending visual actions do not mutate it.
public final class PartyEncounter {
    public private(set) var engine:GameEngine
    public private(set) var pending:PartyIntent?
    public private(set) var confirmedReceipt:OperationReceipt?
    private var confirmedEngine:GameEngine?
    public let monsterIDs:[String]
    /// Campaign team duel: the two hero teams (left / mirrored right). Empty in a monster fight.
    public private(set) var duelLeft:[String]=[],duelRight:[String]=[]
    public var isDuel:Bool {!duelRight.isEmpty}
    public let sessionID:String
    private var serial=0
    public var state:GameState { engine.state }
    public var current:String? { state.battle?.current }
    public var round:Int { state.battle?.round ?? 0 }
    public var terminal:Bool { state.battle == nil || state.pauseReasons.contains(.allPlayersDown) || state.pauseReasons.contains(.noSurvivors) }
    public init(seed:UInt64=UInt64.random(in:1...UInt64.max),sessionID:String=UUID().uuidString,loadouts:[String:GameUnit]?=nil,playerClassID:String="adventurer") throws {
        var catalog=try GameCatalog.initial()
        guard catalog.classes.contains(where:{$0.id==playerClassID}) else { throw GameError("该职业尚未接入演练。") }
        self.sessionID=sessionID
        self.monsterIDs=["m1","m2"]
        // A local training creature using the existing deer art. The six formal
        // monster definitions and all original skills/items remain unchanged.
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
        let p1Max=units["p1"]?.baseAttributes.maximumHealth ?? 12
        units["p1"]?.health=playerClassID=="spellblade" ? 12:playerClassID=="dragonKnight" ? 20:playerClassID=="adventurer" ? 6:max(6,p1Max/2)
        units["p2"]?.health=12
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
        guard let battle=engine.state.battle,battle.kind == .pve || battle.duel == true else {throw GameError("当前没有探索战斗。")}
        self.engine=engine;self.sessionID=sessionID
        if battle.duel == true {
            // Teams sorted by id: the first stands on the left, the other is drawn mirrored on the right.
            let fighters=battle.queue.compactMap{engine.state.units[$0]}.filter{$0.kind == .player}
            let teams=Array(Set(fighters.compactMap(\.teamID))).sorted()
            guard teams.count==2 else {throw GameError("PVP需要两支队伍。")}
            self.monsterIDs=[]
            duelLeft=fighters.filter{$0.teamID==teams[0]}.map(\.id).sorted();duelRight=fighters.filter{$0.teamID==teams[1]}.map(\.id).sorted()
            return
        }
        self.monsterIDs=battle.queue.filter{engine.state.units[$0]?.kind == .monster}.sorted()
        guard (1...3).contains(monsterIDs.count) else {throw GameError("当前战场支持1—3个敌人。")}
    }
    /// Someone joined or left a running duel (the teacher, a late student): keep each side to who fights on it now.
    /// Returns true when a side changed.
    @discardableResult public func syncDuelSides()->Bool {
        guard isDuel,let battle=engine.state.battle else{return false}
        let units=engine.state.units
        let leftTeam=duelLeft.compactMap{units[$0]?.teamID}.first,fighters=battle.queue.compactMap{units[$0]}.filter{$0.kind == .player}
        let left=fighters.filter{$0.teamID==leftTeam}.map(\.id).sorted(),right=fighters.filter{$0.teamID != leftTeam}.map(\.id).sorted()
        guard left != duelLeft || right != duelRight,!right.isEmpty else{return false}
        duelLeft=left;duelRight=right;return true
    }
    public func command(_ action:PartyAction,target:String)->GameCommand? {
        guard let actor=current else { return nil }
        switch action {
        case .attack:return .attack(actor:actor,target:target)
        case .endTurn:return .endTurn(actor:actor,timedOut:false)
        case .revivalStone:return .rescue(actor:actor,target:target)
        default:
            if action.isItem { return .useItem(actor:actor,item:action.rawValue,target:target) }
            if action.isNodeCast { return .cast(actor:actor,skill:action.rawValue,target:.node(state.units[target]?.nodeID ?? 1)) }
            if action.isSelfOnly { return .cast(actor:actor,skill:action.rawValue,target:.unit(actor)) }
            return .cast(actor:actor,skill:action.rawValue,target:.unit(target))
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
        if action.isNodeSupport {
            if state.units[actor]?.kind == .monster {
                targets=state.units.values.filter { $0.isAlive && $0.kind == .monster && $0.nodeID==state.units[target]?.nodeID }.map(\.id).sorted()
            } else {
                targets=state.players.filter { $0.isAlive && $0.nodeID==state.units[target]?.nodeID && (!isDuel || $0.teamID==state.units[actor]?.teamID) }.map(\.id)
            }
        }
        else if action.isNodeAttack {
            let me=state.units[actor]
            if me?.kind == .monster {
                targets=state.players.filter { $0.isAlive && $0.nodeID==state.units[target]?.nodeID && (!isDuel || (duelLeft+duelRight).contains($0.id)) }.map(\.id).sorted()
            } else {
                targets=state.units.values.filter { u in u.isAlive && u.nodeID==state.units[target]?.nodeID && (isDuel ? (u.kind == .player && me.map{GameRules.enemies($0,u,in:state)} == true && (duelLeft+duelRight).contains(u.id)):u.kind == .monster) }.map(\.id).sorted()
            }
        }
        else if action.isSelfOnly { targets=[actor] }
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
        let targets:[String]
        if action.isSelfOnly {
            targets=[actor]
        } else if action.isOffensive {
            let enemyChanged=changed.filter { state.units[$0]?.kind != .monster }
            if !enemyChanged.isEmpty {
                targets=enemyChanged
            } else if action.isNodeAttack {
                let alivePlayers=state.players.filter { $0.isAlive && $0.nodeID == state.units[actor]?.nodeID }.map(\.id).sorted()
                targets=alivePlayers.isEmpty ? [nextEnemyTarget() ?? "p1"]:alivePlayers
            } else {
                targets=[nextEnemyTarget() ?? "p1"]
            }
        } else if action.isNodeSupport {
            let allyChanged=changed.filter { state.units[$0]?.kind == .monster }
            if !allyChanged.isEmpty {
                targets=allyChanged
            } else {
                let aliveAllies=state.units.values.filter { $0.isAlive && $0.kind == .monster && $0.nodeID == state.units[actor]?.nodeID }.map(\.id).sorted()
                targets=aliveAllies.isEmpty ? [actor]:aliveAllies
            }
        } else {
            targets=changed.isEmpty ? [nextEnemyTarget() ?? "p1"]:changed
        }
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
    public func nextEnemyTarget()->String? { state.players.filter{$0.isAlive && (state.battle?.queue.contains($0.id) ?? true)}.min { a,b in Double(a.health)/Double(a.baseAttributes.maximumHealth)<Double(b.health)/Double(b.baseAttributes.maximumHealth) }?.id }
}
