import Foundation
import MeadowBattleSupport
import ClassroomGameCore

@main struct Export {
    static func main() throws {
        let out=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        if CommandLine.arguments.contains("--monster-only") { try exportMonsters(out:out);return }
        if CommandLine.arguments.contains("--dragon-flame-only") { try exportDragonFlame(out:out);return }
        if CommandLine.arguments.contains("--rune-only") { try exportRunes(out:out);return }
        if CommandLine.arguments.contains("--inventory-only") { try exportInventory(out:out);return }
        if CommandLine.arguments.contains("--accessory-only") { try exportAccessories(out:out);return }
        if CommandLine.arguments.contains("--bow-only") { try exportBow(out:out);return }
        var rows:[[String:Any]]=[],requests:[[String:Any]]=[]
        let healingOnly = CommandLine.arguments.contains("--healing-only")
        let scenarios = healingOnly
            ? ["healing-micro", "healing-standard", "healing-strong"]
            : ["support", "rally", "items", "revive", "combat", "healing-micro", "healing-standard", "healing-strong"]
        for scenario in scenarios {
            let model=try PartyEncounter(seed:17,sessionID:"review-"+scenario)
            if scenario=="rally" { let i=model.prepare(.support,target:"p1")!;_ = try model.commit(i.id) }
            if scenario=="revive" { try model.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:0))) }
            if scenario=="healing-micro" { try model.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:9))) }
            if scenario=="healing-standard" { try model.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:6))) }
            if scenario=="healing-strong" { try model.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:1))) }
            if scenario=="combat" {
                let i=model.prepare(.rally,target:"p1")!;_ = try model.commit(i.id)
                try model.engine.apply(.endTurn(actor:"p2",timedOut:false))
                let guardIntent=model.prepare(.simpleGuard,target:"p1")!;_ = try model.commit(guardIntent.id)
                try model.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3)))
            }
            let count=scenario=="combat" ? 320:scenario=="items" ? 370:scenario=="revive" ? 180:160
            var current:PartyIntent?,start=0.0,fired=false
            var births:[String:Double]=[:],heals:[String:Double]=[:],healingTiers:[String:HealingEffectTier]=[:],forms:[String:Double]=[:]
            var messages:[[String:Any]]=[]
            var death:[String:Double]=[:],hurt:[String:Double]=[:]
            var emitters:[[String:Any]]=[];var shielded=false
            for frame in 0..<count {
                let time=Double(frame)*0.02
                if frame==20 || (scenario=="items" && (frame==140 || frame==260)) || (scenario=="combat" && frame==140) {
                    let action:PartyAction
                    if scenario=="combat" { action = .attack }
                    else if scenario=="healing-strong" { action = .largePotion }
                    else if scenario.hasPrefix("healing-") { action = .smallPotion }
                    else if ["support","unarmed"].contains(scenario) { action = .support }
                    else if scenario=="rally" { action = .rally }
                    else if scenario=="revive" { action = .revivalStone }
                    else { action = frame==20 ? .smallPotion:frame==140 ? .largePotion:.shieldPotion }
                    if scenario=="combat" && frame==140 { try model.engine.apply(.endTurn(actor:"p1",timedOut:false)) }
                    let target=scenario=="combat" && frame==20 ? "m1":scenario=="items" && frame==140 ? "p2":"p1"
                    shielded=(model.state.units[target]?.shield ?? 0)>0
                    current=model.prepare(action,target:target)!;start=time;fired=false
                    let offset=max(0,action.impact-0.46)
                    for id in current!.targets {
                        if ["support","guard"].contains(action.visual) { forms[id]=time+offset }
                    }
                }
                var receipt:OperationReceipt?
                let age=time-start
                if let intent=current,!fired,age+1e-9>=(intent.enemy ? 0.46:intent.action.impact) {
                    fired=true;receipt=try model.commit(intent.id)
                    if let receipt {
                        for id in ["p1","p2","m1","m2"] {
                            let before=receipt.before.units[id]!,after=receipt.after.units[id]!
                            let foot=PartyVisual.feet[id]!
                            let damage=max(0,before.health-after.health),absorbed=max(0,before.shield-after.shield)
                            if damage>0 || absorbed>0 {
                                hurt[id]=time
                                let x=foot.x+(absorbed>0 ? (5+240*0.41)*PartyVisual.heroScale:(id.hasPrefix("m") ? -80:0))
                                let y=foot.y-(id.hasPrefix("p") ? 65:72)
                                emitters.append(["kind":absorbed>0 ? "shieldContact":"strike","at":time,"x":x,"y":y,"floor":foot.y])
                                if absorbed>0 && after.shield==0 { emitters.append(["kind":"shieldBreak","at":time,"x":foot.x,"y":foot.y-60,"floor":foot.y]) }
                                messages.append(["id":id,"text":damage>0 ? "−\(damage)":"格挡","at":time,"kind":"damage"])
                            }
                            if before.isAlive && !after.isAlive && after.kind == .monster {
                                death[id]=time;emitters.append(["kind":"death","at":time,"x":foot.x-80,"y":foot.y-72,"floor":foot.y])
                            }
                            if after.shield>before.shield { births[id]=time }
                            if after.health>before.health {
                                let amount=after.health-before.health
                                heals[id]=time
                                healingTiers[id]=HealingEffectTier.classify(actualHPGained:amount)
                                messages.append(["id":id,"text":"＋\(amount)","at":time,"kind":"heal"])
                            }
                            if after.shield>before.shield { messages.append(["id":id,"text":"盾 ＋\(after.shield-before.shield)","at":time,"kind":"shield"]) }
                            if after.damageBuff != before.damageBuff { messages.append(["id":id,"text":"伤害 ＋2","at":time,"kind":"buff"]) }
                        }
                    }
                }
                if let intent=current,age>=(intent.enemy ? 1.10:intent.action.duration) { current=nil }
                var units:[[String:Any]]=[]
                for id in ["p1","p2","m1","m2"] {
                    let u=model.state.units[id]!,pose=PartyVisual.pose(unit:u,intent:current,age:age,time:time,hurtAge:hurt[id].map { time-$0 },blocked:id=="p1" && shielded && hurt[id] != nil)
                    units.append(["id":id,"name":u.name,"weaponID":u.equipment.weapon as Any? ?? NSNull(),"weaponPose":u.equipment.weapon=="legendaryStaff" ? try JSONSerialization.jsonObject(with:JSONEncoder().encode(LegendaryStaffRig.pose(progress:pose.progress,clip:pose.clip))) : u.equipment.weapon=="greatSword" ? try JSONSerialization.jsonObject(with:JSONEncoder().encode(GreatSwordRig.pose(progress:pose.progress,clip:pose.clip))) : NSNull(),"vitalsVisible":u.kind != .monster || u.isAlive,"hp":u.health,"maxHP":u.baseAttributes.maximumHealth,"shield":u.shield,"ap":u.ap,"buff":u.damageBuff?.amount ?? 0,"buffRounds":u.damageBuff?.roundsLeft ?? 0,"clip":pose.clip,"progress":pose.progress,"deathAge":death[id].map { time-$0 } as Any? ?? NSNull()])
                    if id.hasPrefix("p") {
                        var r:[String:Any]=["kind":scenario+"-"+id,"frame":frame,"time":time,"shield":u.shield,"emitters":[]]
                        if let at=heals[id],u.isAlive,let tier=healingTiers[id] { r["recoveryAge"]=time-at;r["recoveryTier"]=tier.rawValue }
                        if let at=forms[id],u.shield==0,time-at<1 { r["formation"]=time-at }
                        if let at=births[id] { r["birth"]=time-at }
                        requests.append(r)
                    }
                }
                let activeEmitters=emitters.compactMap { e -> [String:Any]? in
                    let age=time-(e["at"] as! Double);guard age<3 else { return nil }
                    return ["kind":e["kind"]!,"age":age,"x":e["x"]!,"y":e["y"]!,"floor":e["floor"]!]
                }
                requests.append(["kind":scenario+"-fx","frame":frame,"time":time,"emitters":activeEmitters,"shield":0])
                var action:[String:Any]=[:]
                if let i=current { action=["actor":i.actor,"target":i.target,"targets":i.targets,"action":i.action.rawValue,"visual":i.action.visual,"age":age,"enemy":i.enemy,"shielded":shielded,"travel":try JSONSerialization.jsonObject(with:JSONEncoder().encode(PartyVisual.travel(i,age:age,shielded:shielded)))] }
                let from=current.map { PartyVisual.chest($0.actor) } ?? PartyPoint(0,0),to=current.map { PartyVisual.chest($0.target) } ?? PartyPoint(0,0)
                let trail=PartyVisual.trail(age:age,from:from,to:to)
                let rally=["p1","p2"].map { id -> [String:Any] in
                    let data=try! JSONEncoder().encode(PartyVisual.rally(age:age,at:PartyVisual.chest(id)))
                    return ["id":id,"particles":try! JSONSerialization.jsonObject(with:data)]
                }
                rows.append(["scenario":scenario,"frame":frame,"time":time,"current":model.current as Any? ?? NSNull(),"units":units,"action":action,"trail":try JSONSerialization.jsonObject(with:JSONEncoder().encode(trail)),"rally":rally,"messages":messages.filter { time-($0["at"] as! Double)<1 },"committed":receipt != nil])
            }
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("party-frames.json"))
        try JSONSerialization.data(withJSONObject:requests,options:[.sortedKeys]).write(to:out.appendingPathComponent("legacy-light-requests.json"))
        // Healing review fixtures have no active shield or hit-particle layers.
        // Keep only the inactive attachment defaults; treatment age and tier are
        // already exported with each production frame above.
        let attachments: [[String: Any]] = requests.map { request in
            let kind = request["kind"] as? String ?? ""
            let frame = request["frame"] as? Int ?? 0
            return [
                "kind": kind, "frame": frame, "shieldOpacity": 0.0,
                "particles": [[String: Any]](), "wisps": [[String: Double]](),
                "recovery": [[String: Double]]()
            ]
        }
        let attachmentDocument: [String: Any] = [
            "frames": attachments,
            "scope": "healing review; shield and hit-particle layers are inactive in these fixtures"
        ]
        try JSONSerialization.data(withJSONObject: attachmentDocument, options: [.sortedKeys])
            .write(to: out.appendingPathComponent("legacy-attachment-samples.json"))
        try exportDice(out:out)
        try exportPoly(out:out)
        try exportBow(out:out)
        try exportGreatSword(out:out)
        try exportLegendaryStaff(out:out)
        try exportAccessories(out:out)
        try exportInventory(out:out)
        try exportRunes(out:out)
        print("Exported \(rows.count) actual GameCore support/item frames and \(requests.count) attachment samples")
    }
}

extension Export {
    static func exportDice(out:URL) throws {
        var rows:[[String:Any]]=[]
        for scenario in ["attack-buff","support","shield","heal","lethal","ambush","ambush-last","unarmed","bow","bow-heavy","bow-lethal","great-sword","great-sword-heavy","great-sword-lethal","legendary-staff","legendary-staff-heavy","legendary-staff-lethal","legendary-staff-natural20"] {
            let gear=try TrainingLoadout()
            if scenario=="unarmed" { try gear.equip(nil) };if scenario.hasPrefix("bow") { try gear.equip("huntingBow") };if scenario.hasPrefix("great-sword") { try gear.equip("greatSword") }
            if scenario.hasPrefix("legendary-staff") { try gear.equip("legendaryStaff") }
            var seed:UInt64=47
            if scenario=="legendary-staff-natural20" {
                for candidate in UInt64(1)...1000 {
                    let probe=try PartyEncounter(seed:candidate,loadouts:gear.units);try probe.engine.apply(.endTurn(actor:"p2",timedOut:false))
                    _=probe.prepare(.attack,target:"m1")
                    if probe.confirmedReceipt?.dice.contains(where: { $0.naturalTwenty })==true { seed=candidate;break }
                }
            }
            let p=try PartyEncounter(seed:seed,sessionID:"dice-review-"+scenario,loadouts:scenario=="unarmed" || scenario.hasPrefix("bow") || scenario.hasPrefix("great-sword") || scenario.hasPrefix("legendary-staff") ? gear.units:nil)
            let action:PartyAction=["bow-heavy","great-sword-heavy","legendary-staff-heavy"].contains(scenario) ? .heavyStrike:scenario.hasPrefix("ambush") ? .ambush:["support","unarmed"].contains(scenario) ? .support:scenario=="shield" ? .simpleGuard:scenario=="heal" ? .largePotion:.attack
            if scenario=="attack-buff" || scenario=="lethal" || scenario=="ambush-last" {
                let rally=p.prepare(.rally,target:"p1")!;_ = try p.commit(rally.id)
            }
            if scenario != "support" && scenario != "unarmed" && scenario != "heal" && !scenario.hasPrefix("ambush") { try p.engine.apply(.endTurn(actor:"p2",timedOut:false)) }
            if scenario=="lethal" || scenario=="bow-lethal" || scenario=="great-sword-lethal" || scenario=="legendary-staff-lethal" { try p.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3))) }
            if scenario=="ambush-last" {
                try p.engine.apply(.editResources(unit:"m2",value:ResourcePatch(health:0)))
                try p.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3)))
            }
            let target=action.isOffensive ? "m1":"p1"
            var intent:PartyIntent?,receipt:OperationReceipt?,activeAction=action,start=1.0,hitAt:Double?,fired=false
            var dieActor=p.current!,dieTarget=target,dieActorUnit=p.state.units[p.current!]!,dieTargetUnit=p.state.units[target]!
            var hurt:[String:Double]=[:],death:[String:Double]=scenario=="ambush-last" ? ["m2":-3.0]:[:]
            var damageLabels:[[String:Any]]=[]
            var dice=BattleDice.channels(action,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog)
            let count=scenario=="attack-buff" ? 300:scenario.hasPrefix("ambush") ? 220:190
            for frame in 0..<count {
                let time=Double(frame)*0.02
                if frame==50 || scenario=="attack-buff" && frame==190 {
                    if frame==190 {
                        try p.engine.apply(.endTurn(actor:"p1",timedOut:false));activeAction = .attack
                        dieActor=p.current!;dieTarget="p1";dieActorUnit=p.state.units[dieActor]!;dieTargetUnit=p.state.units[dieTarget]!
                        dice=BattleDice.channels(activeAction,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog)
                    }
                    intent=p.prepare(activeAction,target:dieTarget)!;start=time;fired=false;hitAt=nil;receipt=nil
                    dice=BattleDice.channels(activeAction,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog,receipt:p.confirmedReceipt)
                }
                let age=time-start
                if let i=intent,!fired,age+1e-8 >= (i.enemy ? 0.46:i.action.impact) {
                    receipt=try p.commit(i.id);fired=true;hitAt=time
                    if let r=receipt {
                        dice=BattleDice.channels(activeAction,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog,receipt:r)
                        if r.dice.contains(where: { $0.naturalTwenty }) { let hit=PartyVisual.hitPoint(target:i.target,weaponID:i.weaponID);damageLabels.append(["text":"自然20","x":hit.x,"y":hit.y-55,"at":time]) }
                        for id in ["p1","p2","m1","m2"] {
                            let damage=max(0,r.before.units[id]!.health-r.after.units[id]!.health),absorbed=max(0,r.before.units[id]!.shield-r.after.units[id]!.shield)
                            if damage>0 || absorbed>0 {
                                hurt[id]=time;let point=PartyVisual.hitPoint(target:id,shielded:absorbed>0,weaponID:i.weaponID)
                                damageLabels.append(["text":damage>0 ? "−\(damage)":"格挡","x":point.x,"y":point.y,"at":time])
                            }
                            if r.before.units[id]!.isAlive && !r.after.units[id]!.isAlive { death[id]=time }
                        }
                    }
                }
                let showing=intent.flatMap { age<($0.enemy ? 1.10:$0.action.duration) ? $0:nil }
                let travel=PartyVisual.travel(showing,age:age,shielded:dieTargetUnit.shield>0)
                var units:[[String:Any]]=[]
                for id in ["p1","p2","m1","m2"] {
                    let u=p.state.units[id]!,pose=PartyVisual.pose(unit:u,intent:showing,age:age,time:time,hurtAge:hurt[id].map { time-$0 },blocked:u.shield>0)
                    let monster=PartyVisual.monster(time:time+(id=="m2" ? 0.7:0),attackAge:showing?.actor==id ? age:nil,hurtAge:hurt[id].map { time-$0 },preparing:p.current==id && showing==nil)
                    units.append(["id":id,"weaponID":u.equipment.weapon as Any? ?? NSNull(),"weaponPose":u.equipment.weapon=="legendaryStaff" ? try JSONSerialization.jsonObject(with:JSONEncoder().encode(LegendaryStaffRig.pose(progress:pose.progress,clip:pose.clip))) : u.equipment.weapon=="greatSword" ? try JSONSerialization.jsonObject(with:JSONEncoder().encode(GreatSwordRig.pose(progress:pose.progress,clip:pose.clip))) : NSNull(),"vitalsVisible":u.kind != .monster || u.isAlive,"hp":u.health,"maxHP":u.baseAttributes.maximumHealth,"shield":u.shield,"ap":u.ap,"buff":u.damageBuff?.amount ?? 0,"clip":pose.clip,"progress":pose.progress,"monster":try JSONSerialization.jsonObject(with:JSONEncoder().encode(monster)),"deathAge":death[id].map { time-$0 } as Any? ?? NSNull()])
                }
                let bowProjectile=showing.flatMap { i -> BowProjectile? in
                    guard i.ranged,let f=PartyVisual.feet[i.actor] else { return nil }
                    let tip=BowRig.releaseArrowTip
                    return BowRig.projectile(age:age,from:PartyPoint(f.x+(tip.x-123)*PartyVisual.heroScale,f.y+(tip.y-214)*PartyVisual.heroScale),to:PartyVisual.hitPoint(target:i.target,shielded:dieTargetUnit.shield>0),impact:i.action.impact,scale:PartyVisual.heroScale)
                }
                let staff=showing.flatMap { i -> StaffEffectSample? in
                    guard i.magical,let foot=PartyVisual.feet[i.actor],let target=PartyVisual.feet[i.target] else { return nil }
                    return LegendaryStaffRig.effect(age:age,foot:foot,target:PartyVisual.hitPoint(target:i.target,weaponID:i.weaponID),groundY:target.y,scale:PartyVisual.heroScale,naturalTwenty:p.confirmedReceipt?.dice.contains(where: { $0.naturalTwenty }) ?? receipt?.dice.contains(where: { $0.naturalTwenty }) ?? false)
                }
                let diePose=dice.indices.map { index in BattleDice.pose(time:time,index:index,resolvedAge:hitAt.map { time-$0 },visibleAge:frame>=190 && scenario=="attack-buff" ? time-3.8:time) }
                let hover=time<1
                let initial=BattleDice.darkness(action)
                let dim=hover ? initial*PartyVisual.smooth(time/0.28):showing != nil ? (initial+(max(initial,activeAction.isOffensive ? 0.58:0.32)-initial)*PartyVisual.smooth(age/0.4))*(1-PartyVisual.smooth((age-1.2)/0.6)):0
                rows.append(["scenario":scenario,"frame":frame,"time":time,"hitPoints":try JSONSerialization.jsonObject(with:JSONEncoder().encode(Dictionary(uniqueKeysWithValues:["p1","p2","m1","m2"].map { ($0,PartyVisual.hitPoint(target:$0,weaponID:showing?.weaponID)) }))),"damageLabels":damageLabels.filter { time-($0["at"] as! Double)<1 },"staff":staff.map { try! JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) } as Any? ?? NSNull(),"ranged":showing?.ranged ?? false,"weaponTrail":try JSONSerialization.jsonObject(with:JSONEncoder().encode(showing.flatMap { i in i.weaponID=="greatSword" && !i.enemy && i.action.visual=="attack" ? GreatSwordRig.trail(age:age,from:PartyVisual.feet[i.actor]!,to:PartyVisual.hitPoint(target:i.target,shielded:dieTargetUnit.shield>0,weaponID:i.weaponID),scale:PartyVisual.heroScale):nil } ?? [])),"projectile":bowProjectile.map { try! JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) } as Any? ?? NSNull(),"locked":!hover,"confirmationAge":hover ? NSNull():age,"hover":hover,"darkness":dim,"actor":dieActor,"target":dieTarget,"action":activeAction.rawValue,"age":age,"playing":showing != nil,"enemy":showing?.enemy ?? false,"impact":hitAt as Any? ?? NSNull(),"afterimages":try JSONSerialization.jsonObject(with:JSONEncoder().encode(PartyVisual.afterimages(showing,age:age))),"ambushSlashes":try JSONSerialization.jsonObject(with:JSONEncoder().encode(activeAction == .ambush ? PartyVisual.ambushSlashes(age:age,at:PartyPoint(PartyVisual.feet[dieTarget]!.x-80,PartyVisual.feet[dieTarget]!.y-72)):[])),"receiptDice":try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt?.dice ?? [])),"dice":try JSONSerialization.jsonObject(with:JSONEncoder().encode(dice)),"diceAnchor":try JSONSerialization.jsonObject(with:JSONEncoder().encode(PartyVisual.diceAnchor(actor:dieActor,intent:showing,age:age,shielded:dieTargetUnit.shield>0,diceCount:dice.count))),"poly":try JSONSerialization.jsonObject(with:JSONEncoder().encode(dice.enumerated().map { index,die in PolyhedralDice.sample(die:die,time:time,index:index,count:dice.count,resolvedAge:hitAt.map { time-$0 },visibleAge:frame>=190 && scenario=="attack-buff" ? time-3.8:time,locked:!hover,confirmationAge:hover ? nil:age) })),"dicePose":try JSONSerialization.jsonObject(with:JSONEncoder().encode(diePose)),"travel":try JSONSerialization.jsonObject(with:JSONEncoder().encode(travel)),"current":(showing?.actor ?? p.current) as Any? ?? NSNull(),"acted":Array(p.state.battle?.acted ?? []),"units":units])
            }
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("dice-frames.json"))
        print("Exported \(rows.count) receipt-bound dice / monster / queue frames")
    }
}

extension Export {
    static func exportPoly(out:URL) throws {
        var rows:[[String:Any]]=[]
        for group in ["types","bonus"] {
            let p=try PartyEncounter(seed:48,sessionID:"poly-review-"+group)
            var sources:[(GameEngine,GameCommand,String)]=[]
            if group=="types" {
                for sides in [4,6,8,12,20,10] {
                    var catalog=p.engine.catalog,state=p.state
                    var weapon=try catalog.item("trainingSword")
                    let id=[6:"trainingSword",8:"huntingBow",12:"greatSword",20:"legendaryStaff"][sides]
                    if let id { weapon=try catalog.item(id) }
                    else { weapon.id="offlineReviewD\(sides)";weapon.name="离线骰型D\(sides)";weapon.attack?.dice=DiceFormula(sides:sides);catalog.items.append(weapon) }
                    state.units["p1"]?.equipment.weapon=weapon.id;state.battle?.queue=["p1","p2","m1","m2"];state.battle?.current="p1"
                    sources.append((try GameEngine(catalog:catalog,state:state),.attack(actor:"p1",target:"m1"),"D\(sides)"))
                }
            } else {
                let rally=p.prepare(.rally,target:"p1")!;_ = try p.commit(rally.id)
                sources.append((p.engine,.cast(actor:"p2",skill:"ambush",target:.unit("m1")),"突袭 · 2D8＋2 / 增伤＋2"))
                var state=p.state;var actor=try GameFactory.player(id:"p1",name:"符文公式审核",classID:"spellblade",teamID:"party",nodeID:1,catalog:p.engine.catalog)
                actor.health=6;actor.damageBuff=state.units["p1"]?.damageBuff;state.units["p1"]=actor;state.battle?.queue=["p1","p2","m1","m2"];state.battle?.current="p1"
                sources.append((try GameEngine(catalog:p.engine.catalog,state:state),.cast(actor:"p1",skill:"runeSlash",target:.unit("m1")),"符文斩 · 2D12＋2 / 增伤＋2"))
            }
            var receipts:[OperationReceipt]=[]
            for (engine,command,_) in sources { receipts.append(try engine.apply(command)) }
            for frame in 0..<180 {
                let time=Double(frame)*0.02,at=1.2,resolved=time>=at
                var entries:[[String:Any]]=[]
                for (i,source) in sources.enumerated() {
                    let receipt=receipts[i],actorID=group=="bonus" && i==0 ? "p2":"p1",actor=receipt.before.units[actorID]!,target=receipt.before.units["m1"]!
                    let dice=group=="types" ? BattleDice.channels(.attack,actor:actor,target:target,catalog:source.0.catalog,receipt:resolved ? receipt:nil):BattleDice.skillChannels(i==0 ? "ambush":"runeSlash",actor:actor,catalog:source.0.catalog,receipt:resolved ? receipt:nil)
                    let samples=dice.enumerated().map { index,die in PolyhedralDice.sample(die:die,time:time,index:index+i*3,count:dice.count,resolvedAge:resolved ? time-at:nil,visibleAge:time) }
                    entries.append(["title":source.2,"dice":try JSONSerialization.jsonObject(with:JSONEncoder().encode(dice)),"samples":try JSONSerialization.jsonObject(with:JSONEncoder().encode(samples)),"receiptDice":try JSONSerialization.jsonObject(with:JSONEncoder().encode(resolved ? receipt.dice:[]))])
                }
                rows.append(["group":group,"frame":frame,"time":time,"entries":entries])
            }
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("poly-frames.json"))
        print("Exported \(rows.count) polyhedron gallery and source-formula bonus frames")
    }
}

extension Export {
    static func exportBow(out:URL) throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data=try Data(contentsOf:root.appendingPathComponent("Sources/Resources/Assets.xcassets/MeadowBattleHeroAnimationV2.dataset/animation.json"))
        let json=try JSONSerialization.jsonObject(with:data) as! [String:Any],clips=json["clips"] as! [String:[String:Any]]
        var rows:[[String:Any]]=[]
        for clip in ["idle","attack","guard","hit","victory","defeat"] {
            let keys=clips[clip]!["keys"] as! [[String:Any]]
            for i in 0...600 {
                let p=Double(i)/600,u=keys.firstIndex { ($0["t"] as! Double)>=p } ?? keys.count-1,a=keys[max(0,u-1)],b=keys[u]
                let at=a["t"] as! Double,bt=b["t"] as! Double,f=bt==at ? 0:(p-at)/(bt-at)
                func value(_ key:String)->Double { let x=a[key] as! Double,y=b[key] as! Double;return x+(y-x)*f }
                let fixed=["attack","idle"].contains(clip)
                let sample=BowRig.sample(clip:clip,progress:p,lean:fixed ? 0:value("lean"),crouch:fixed ? 0:value("crouch"))
                rows.append(["clip":clip,"progress":p,"sample":try JSONSerialization.jsonObject(with:JSONEncoder().encode(sample))])
            }
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("bow-poses.json"))
        print("Exported \(rows.count) shared bow/arm/string poses")
    }
}


extension Export {
    static func exportGreatSword(out:URL) throws {
        let poses=["idle","attack","guard","hit","victory","defeat"].flatMap { clip in (0...600).map { i -> [String:Any] in
            let p=Double(i)/600
            return ["clip":clip,"progress":p,"sample":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(GreatSwordRig.pose(progress:p,clip:clip)))]
        } }

        try JSONSerialization.data(withJSONObject:poses,options:[.sortedKeys]).write(to:out.appendingPathComponent("great-sword-poses.json"))
        let clock=(0...200).map { i -> [String:Any] in
            let age=Double(i)/100
            let target=PartyVisual.hitPoint(target:"m1",weaponID:"greatSword"),from=PartyVisual.feet["p1"]!
            return ["age":age,"progress":GreatSwordRig.progress(age:age),"tip":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(GreatSwordRig.tip(progress:GreatSwordRig.progress(age:age)))),"travel":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(GreatSwordRig.travel(age:age,from:from,to:target,scale:PartyVisual.heroScale)))]
        }
        try JSONSerialization.data(withJSONObject:clock,options:[.sortedKeys]).write(to:out.appendingPathComponent("great-sword-clock.json"))
        print("Exported3606 shared heavy-sword poses and201 contact-clock samples")
    }
}

extension Export {
    static func exportLegendaryStaff(out:URL) throws {
        let poses=["idle","attack","guard","hit","victory","defeat"].flatMap { clip in (0...600).map { i -> [String:Any] in
            let p=Double(i)/600
            return ["clip":clip,"progress":p,"sample":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(LegendaryStaffRig.pose(progress:p,clip:clip)))]
        } }
        try JSONSerialization.data(withJSONObject:poses,options:[.sortedKeys]).write(to:out.appendingPathComponent("legendary-staff-poses.json"))
        let clock=(0...200).map { i -> StaffEffectSample in
            LegendaryStaffRig.effect(age:Double(i)/100,foot:PartyVisual.feet["p1"]!,target:PartyVisual.hitPoint(target:"m1",weaponID:"legendaryStaff"),groundY:PartyVisual.feet["m1"]!.y,scale:PartyVisual.heroScale)
        }
        try JSONEncoder().encode(clock).write(to:out.appendingPathComponent("legendary-staff-clock.json"))
        print("Exported3606 shared staff poses and201 spell samples")
    }
}

extension Export {
    static func exportAccessories(out:URL) throws {
        var rows:[[String:Any]]=[]
        for scenario in ["accessory-none","accessory-powerBadge","accessory-actionRing"] {
            let gear=try TrainingLoadout()
            try gear.equipArmor("leatherArmor");try gear.equip("legendaryStaff")
            if scenario != "accessory-none" { try gear.equipAccessory(scenario.replacingOccurrences(of:"accessory-",with:"")) }
            if scenario=="unarmed" { try gear.equip(nil) };if scenario.hasPrefix("bow") { try gear.equip("huntingBow") };if scenario.hasPrefix("great-sword") { try gear.equip("greatSword") }
            if scenario.hasPrefix("legendary-staff") { try gear.equip("legendaryStaff") }
            var seed:UInt64=47
            if scenario=="legendary-staff-natural20" {
                for candidate in UInt64(1)...1000 {
                    let probe=try PartyEncounter(seed:candidate,loadouts:gear.units);try probe.engine.apply(.endTurn(actor:"p2",timedOut:false))
                    _=probe.prepare(.attack,target:"m1")
                    if probe.confirmedReceipt?.dice.contains(where: { $0.naturalTwenty })==true { seed=candidate;break }
                }
            }
            let p=try PartyEncounter(seed:seed,sessionID:"dice-review-"+scenario,loadouts:gear.units)
            let action:PartyAction = .heavyStrike
            if scenario=="attack-buff" || scenario=="lethal" || scenario=="ambush-last" {
                let rally=p.prepare(.rally,target:"p1")!;_ = try p.commit(rally.id)
            }
            if scenario != "support" && scenario != "unarmed" && scenario != "heal" && !scenario.hasPrefix("ambush") { try p.engine.apply(.endTurn(actor:"p2",timedOut:false)) }
            if scenario=="lethal" || scenario=="bow-lethal" || scenario=="great-sword-lethal" || scenario=="legendary-staff-lethal" { try p.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3))) }
            if scenario=="ambush-last" {
                try p.engine.apply(.editResources(unit:"m2",value:ResourcePatch(health:0)))
                try p.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3)))
            }
            let target=action.isOffensive ? "m1":"p1"
            var intent:PartyIntent?,receipt:OperationReceipt?,activeAction=action,start=1.0,hitAt:Double?,fired=false
            var dieActor=p.current!,dieTarget=target,dieActorUnit=p.state.units[p.current!]!,dieTargetUnit=p.state.units[target]!
            var hurt:[String:Double]=[:],death:[String:Double]=scenario=="ambush-last" ? ["m2":-3.0]:[:]
            var damageLabels:[[String:Any]]=[]
            var dice=BattleDice.channels(action,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog)
            let count=scenario=="attack-buff" ? 300:scenario.hasPrefix("ambush") ? 220:190
            for frame in 0..<count {
                let time=Double(frame)*0.02
                if frame==50 || scenario=="attack-buff" && frame==190 {
                    if frame==190 {
                        try p.engine.apply(.endTurn(actor:"p1",timedOut:false));activeAction = .attack
                        dieActor=p.current!;dieTarget="p1";dieActorUnit=p.state.units[dieActor]!;dieTargetUnit=p.state.units[dieTarget]!
                        dice=BattleDice.channels(activeAction,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog)
                    }
                    intent=p.prepare(activeAction,target:dieTarget)!;start=time;fired=false;hitAt=nil;receipt=nil
                    dice=BattleDice.channels(activeAction,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog,receipt:p.confirmedReceipt)
                }
                let age=time-start
                if let i=intent,!fired,age+1e-8 >= (i.enemy ? 0.46:i.action.impact) {
                    receipt=try p.commit(i.id);fired=true;hitAt=time
                    if let r=receipt {
                        dice=BattleDice.channels(activeAction,actor:dieActorUnit,target:dieTargetUnit,catalog:p.engine.catalog,receipt:r)
                        if r.dice.contains(where: { $0.naturalTwenty }) { let hit=PartyVisual.hitPoint(target:i.target,weaponID:i.weaponID);damageLabels.append(["text":"自然20","x":hit.x,"y":hit.y-55,"at":time]) }
                        for id in ["p1","p2","m1","m2"] {
                            let damage=max(0,r.before.units[id]!.health-r.after.units[id]!.health),absorbed=max(0,r.before.units[id]!.shield-r.after.units[id]!.shield)
                            if damage>0 || absorbed>0 {
                                hurt[id]=time;let point=PartyVisual.hitPoint(target:id,shielded:absorbed>0,weaponID:i.weaponID)
                                damageLabels.append(["text":damage>0 ? "−\(damage)":"格挡","x":point.x,"y":point.y,"at":time])
                            }
                            if r.before.units[id]!.isAlive && !r.after.units[id]!.isAlive { death[id]=time }
                        }
                    }
                }
                let showing=intent.flatMap { age<($0.enemy ? 1.10:$0.action.duration) ? $0:nil }
                let travel=PartyVisual.travel(showing,age:age,shielded:dieTargetUnit.shield>0)
                var units:[[String:Any]]=[]
                for id in ["p1","p2","m1","m2"] {
                    let u=p.state.units[id]!;let stats=try GameRules.attributes(u,catalog:p.engine.catalog);let accessory=try AccessoryReadout.make(u,catalog:p.engine.catalog);let pose=PartyVisual.pose(unit:u,intent:showing,age:age,time:time,hurtAge:hurt[id].map { time-$0 },blocked:u.shield>0)
                    let monster=PartyVisual.monster(time:time+(id=="m2" ? 0.7:0),attackAge:showing?.actor==id ? age:nil,hurtAge:hurt[id].map { time-$0 },preparing:p.current==id && showing==nil)
                    units.append(["id":id,"weaponID":u.equipment.weapon as Any? ?? NSNull(),"weaponPose":u.equipment.weapon=="legendaryStaff" ? try JSONSerialization.jsonObject(with:JSONEncoder().encode(LegendaryStaffRig.pose(progress:pose.progress,clip:pose.clip))) : u.equipment.weapon=="greatSword" ? try JSONSerialization.jsonObject(with:JSONEncoder().encode(GreatSwordRig.pose(progress:pose.progress,clip:pose.clip))) : NSNull(),"vitalsVisible":u.kind != .monster || u.isAlive,"hp":u.health,"maxHP":stats.maximumHealth,"baseAP":stats.baseAP,"maximumAP":stats.maximumAP,"attributeDamage":stats.damage,"accessory":accessory.map { try! JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) } as Any? ?? NSNull(),"shield":u.shield,"ap":u.ap,"buff":u.damageBuff?.amount ?? 0,"clip":pose.clip,"progress":pose.progress,"monster":try JSONSerialization.jsonObject(with:JSONEncoder().encode(monster)),"deathAge":death[id].map { time-$0 } as Any? ?? NSNull()])
                }
                let bowProjectile=showing.flatMap { i -> BowProjectile? in
                    guard i.ranged,let f=PartyVisual.feet[i.actor] else { return nil }
                    let tip=BowRig.releaseArrowTip
                    return BowRig.projectile(age:age,from:PartyPoint(f.x+(tip.x-123)*PartyVisual.heroScale,f.y+(tip.y-214)*PartyVisual.heroScale),to:PartyVisual.hitPoint(target:i.target,shielded:dieTargetUnit.shield>0),impact:i.action.impact,scale:PartyVisual.heroScale)
                }
                let staff=showing.flatMap { i -> StaffEffectSample? in
                    guard i.magical,let foot=PartyVisual.feet[i.actor],let target=PartyVisual.feet[i.target] else { return nil }
                    return LegendaryStaffRig.effect(age:age,foot:foot,target:PartyVisual.hitPoint(target:i.target,weaponID:i.weaponID),groundY:target.y,scale:PartyVisual.heroScale,naturalTwenty:p.confirmedReceipt?.dice.contains(where: { $0.naturalTwenty }) ?? receipt?.dice.contains(where: { $0.naturalTwenty }) ?? false)
                }
                let diePose=dice.indices.map { index in BattleDice.pose(time:time,index:index,resolvedAge:hitAt.map { time-$0 },visibleAge:frame>=190 && scenario=="attack-buff" ? time-3.8:time) }
                let hover=time<1
                let initial=BattleDice.darkness(action)
                let dim=hover ? initial*PartyVisual.smooth(time/0.28):showing != nil ? (initial+(max(initial,activeAction.isOffensive ? 0.58:0.32)-initial)*PartyVisual.smooth(age/0.4))*(1-PartyVisual.smooth((age-1.2)/0.6)):0
                rows.append(["scenario":scenario,"frame":frame,"time":time,"hitPoints":try JSONSerialization.jsonObject(with:JSONEncoder().encode(Dictionary(uniqueKeysWithValues:["p1","p2","m1","m2"].map { ($0,PartyVisual.hitPoint(target:$0,weaponID:showing?.weaponID)) }))),"damageLabels":damageLabels.filter { time-($0["at"] as! Double)<1 },"staff":staff.map { try! JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) } as Any? ?? NSNull(),"ranged":showing?.ranged ?? false,"weaponTrail":try JSONSerialization.jsonObject(with:JSONEncoder().encode(showing.flatMap { i in i.weaponID=="greatSword" && !i.enemy && i.action.visual=="attack" ? GreatSwordRig.trail(age:age,from:PartyVisual.feet[i.actor]!,to:PartyVisual.hitPoint(target:i.target,shielded:dieTargetUnit.shield>0,weaponID:i.weaponID),scale:PartyVisual.heroScale):nil } ?? [])),"projectile":bowProjectile.map { try! JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) } as Any? ?? NSNull(),"locked":!hover,"confirmationAge":hover ? NSNull():age,"hover":hover,"darkness":dim,"actor":dieActor,"target":dieTarget,"action":activeAction.rawValue,"age":age,"playing":showing != nil,"enemy":showing?.enemy ?? false,"impact":hitAt as Any? ?? NSNull(),"afterimages":try JSONSerialization.jsonObject(with:JSONEncoder().encode(PartyVisual.afterimages(showing,age:age))),"ambushSlashes":try JSONSerialization.jsonObject(with:JSONEncoder().encode(activeAction == .ambush ? PartyVisual.ambushSlashes(age:age,at:PartyPoint(PartyVisual.feet[dieTarget]!.x-80,PartyVisual.feet[dieTarget]!.y-72)):[])),"receiptDice":try JSONSerialization.jsonObject(with:JSONEncoder().encode(receipt?.dice ?? [])),"dice":try JSONSerialization.jsonObject(with:JSONEncoder().encode(dice)),"diceAnchor":try JSONSerialization.jsonObject(with:JSONEncoder().encode(PartyVisual.diceAnchor(actor:dieActor,intent:showing,age:age,shielded:dieTargetUnit.shield>0,diceCount:dice.count))),"poly":try JSONSerialization.jsonObject(with:JSONEncoder().encode(dice.enumerated().map { index,die in PolyhedralDice.sample(die:die,time:time,index:index,count:dice.count,resolvedAge:hitAt.map { time-$0 },visibleAge:frame>=190 && scenario=="attack-buff" ? time-3.8:time,locked:!hover,confirmationAge:hover ? nil:age) })),"dicePose":try JSONSerialization.jsonObject(with:JSONEncoder().encode(diePose)),"travel":try JSONSerialization.jsonObject(with:JSONEncoder().encode(travel)),"current":(showing?.actor ?? p.current) as Any? ?? NSNull(),"acted":Array(p.state.battle?.acted ?? []),"units":units])
            }
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("accessory-frames.json"))
        print("Exported \(rows.count) accessory equipment / dice / AP frames")
    }
}

extension Export {
    static func exportInventory(out:URL) throws {
        let session=try CampInventorySession(store:nil)
        var rows:[[String:Any]]=[]
        func capture(_ id:String,_ selected:String,_ filter:String="all") throws {
            let unit=session.loadout.units["p1"]!,stats=try GameRules.attributes(unit,catalog:session.loadout.engine.catalog)
            func object<T:Encodable>(_ value:T)throws->Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) }
            rows.append(["id":id,"appearanceID":session.appearanceID,"unit":try object(unit),"stats":try object(stats),"filter":filter,"selected":selected,"entries":try object(CampInventoryProjection.entries(unit,catalog:session.loadout.engine.catalog,filter:filter)),"detail":try object(CampInventoryProjection.detail(selected,session:session)),"pad":try object(CampInventoryLayout(width:1194,height:834,bottom:20)),"phone":try object(CampInventoryLayout(width:844,height:390,left:47,right:47,bottom:21))])
        }
        try capture("initial","huntingBow")
        try session.equip(slot:.weapon,item:"huntingBow");try session.equip(slot:.armor,item:"leatherArmor");try session.setAppearance("wayfarer")
        try capture("equipped-bow","huntingBow","weapon")
        try session.equip(slot:.accessory,item:"actionRing")
        try capture("ring","actionRing","accessory")
        try session.use(item:"shieldPotion",target:"p1");try session.use(item:"smallPotion",target:"p1")
        try capture("supplies","smallPotion","supplies")
        let data=try session.exportData();try session.importData(data)
        try capture("restored","actionRing")
        for slot in ItemSlot.allCases { try session.equip(slot:slot,item:nil) }
        try capture("empty-slots","trainingSword")
        try session.equip(slot:.weapon,item:"greatSword");try session.equip(slot:.armor,item:"runeArmor");try session.equip(slot:.accessory,item:"powerBadge")
        try capture("rune-sword-badge","powerBadge")
        let dataOut=try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]);try dataOut.write(to:out.appendingPathComponent("inventory-frames.json"))
        print("Exported \(rows.count) actual camp inventory, equipment, import and layout states")
    }
}

extension Export {
    /// Whole-scene, receipt-bound Dragon Flame frames for offline art review.
    /// The scenario deliberately leaves one node target alive so the review
    /// shows both the immediate death dissolve and a surviving hit reaction.
    static func exportDragonFlame(out:URL) throws {
        var chosen:UInt64=0
        for seed in UInt64(1)...1000 {
            let probe=try PartyEncounter(seed:seed,sessionID:"dragon-flame-seed-\(seed)",playerClassID:"dragonKnight")
            try probe.engine.apply(.endTurn(actor:"p2",timedOut:false))
            try probe.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3)))
            guard probe.prepare(.dragonFlame,target:"m1") != nil,let roll=probe.confirmedReceipt?.dice.first(where:{$0.source=="damage"}) else { continue }
            if !roll.naturalTwenty && roll.total<18 { chosen=seed;break }
        }
        guard chosen != 0 else { throw NSError(domain:"DragonFlameReview",code:1,userInfo:[NSLocalizedDescriptionKey:"Unable to find a review roll that preserves one node target."]) }
        let model=try PartyEncounter(seed:chosen,sessionID:"dragon-flame-review",playerClassID:"dragonKnight")
        try model.engine.apply(.endTurn(actor:"p2",timedOut:false))
        try model.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3)))
        let actor="p1",target="m1",action=PartyAction.dragonFlame
        let baseline=model.state,actorUnit=baseline.units[actor]!,targetUnit=baseline.units[target]!
        var dice=BattleDice.channels(action,actor:actorUnit,target:targetUnit,catalog:model.engine.catalog)
        let start=0.75,step=1.0/60.0,count=270
        var intent:PartyIntent?,receipt:OperationReceipt?,hitAt:Double?
        var hurts:[String:Double]=[:],deaths:[String:Double]=[:],supportStarts:[String:Double]=[:],supportStrength:[String:Double]=[:],shieldBirths:[String:Double]=[:],labels:[[String:Any]]=[],emitters:[[String:Any]]=[]
        var visualHealth=Dictionary(uniqueKeysWithValues:baseline.units.map { ($0.key,$0.value.health) }),visualShield=Dictionary(uniqueKeysWithValues:baseline.units.map { ($0.key,$0.value.shield) })
        var pendingStatus:[String:(at:Double,health:Int,shield:Int,heal:Int,gain:Int,x:Double,y:Double)]=[:]
        var rows:[[String:Any]]=[],requests:[[String:Any]]=[]
        func object<T:Encodable>(_ value:T)throws->Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) }
        for frame in 0..<count {
            let time=Double(frame)*step,hover=time>=0.20 && time<start
            if frame==45 {
                intent=model.prepare(action,target:target)
                guard let staged=model.confirmedReceipt else { throw NSError(domain:"DragonFlameReview",code:2,userInfo:[NSLocalizedDescriptionKey:"Dragon Flame could not be staged."]) }
                dice=BattleDice.channels(action,actor:actorUnit,target:targetUnit,catalog:model.engine.catalog,receipt:staged)
            }
            let age=time-start
            var committed:OperationReceipt?
            if let intent,receipt==nil,age+1e-9>=action.impact {
                receipt=try model.commit(intent.id);committed=receipt;hitAt=time
                if let value=receipt {
                    dice=BattleDice.channels(action,actor:actorUnit,target:targetUnit,catalog:model.engine.catalog,receipt:value)
                    let cues=SpellbladeEffects.recipients(intent,catalog:model.engine.catalog)
                    for id in ["p1","p2","m1","m2"] {
                        let before=value.before.units[id]!,after=value.after.units[id]!,foot=PartyVisual.feet[id]!,point=PartyVisual.hitPoint(target:id)
                        let damage=max(0,before.health-after.health),heal=max(0,after.health-before.health),gain=max(0,after.shield-before.shield)
                        if damage>0 {
                            hurts[id]=time;labels.append(["text":"−\(damage)","x":point.x,"y":point.y,"at":time])
                            emitters.append(["kind":"strike","at":time,"x":point.x,"y":point.y,"floor":foot.y])
                        }
                        if before.isAlive && !after.isAlive && after.kind == .monster {
                            deaths[id]=time;emitters.append(["kind":"death","at":time,"x":point.x,"y":point.y,"floor":foot.y])
                        }
                        visualHealth[id]=after.health-heal;visualShield[id]=after.shield-gain
                        if heal>0 || gain>0 {
                            let cueAt=start+(SpellbladeEffects.statusVFXCueAge(for:action) ?? action.impact)
                            if cueAt>time+0.0001 { pendingStatus[id]=(cueAt,after.health,after.shield,heal,gain,foot.x,foot.y) }
                            else {
                                visualHealth[id]=after.health;visualShield[id]=after.shield
                                if heal>0 { supportStarts[id]=cueAt;supportStrength[id]=SpellbladeEffects.healingStrength(heal);labels.append(["text":"＋\(heal)","x":foot.x,"y":foot.y,"at":cueAt,"supportUnit":id,"supportLine":0,"recoveryStrength":supportStrength[id]!]) }
                                if gain>0 { shieldBirths[id]=cueAt;labels.append(["text":"盾 ＋\(gain)","x":foot.x,"y":foot.y,"at":cueAt,"supportUnit":id,"supportLine":1]) }
                            }
                        }
                        if after.damageBuff != before.damageBuff,let buff=after.damageBuff { labels.append(["text":"增伤 ＋\(buff.amount)","x":foot.x,"y":foot.y,"at":time,"supportUnit":id,"supportLine":(heal>0 || gain>0) ? 2:0]) }
                    }
                }
            }
            let readyStatus=pendingStatus.filter { $0.value.at<=time+1e-9 }
            for (id,cue) in readyStatus {
                pendingStatus.removeValue(forKey:id);visualHealth[id]=cue.health;visualShield[id]=cue.shield
                if cue.heal>0 { supportStarts[id]=cue.at;supportStrength[id]=SpellbladeEffects.healingStrength(cue.heal);labels.append(["text":"＋\(cue.heal)","x":cue.x,"y":cue.y,"at":cue.at,"supportUnit":id,"supportLine":0,"recoveryStrength":supportStrength[id]!]) }
                if cue.gain>0 { shieldBirths[id]=cue.at;labels.append(["text":"盾 ＋\(cue.gain)","x":cue.x,"y":cue.y,"at":cue.at,"supportUnit":id,"supportLine":1]) }
            }
            let visible=intent.flatMap { age<action.duration ? $0:nil }
            let cues=intent.map { SpellbladeEffects.recipients($0,catalog:model.engine.catalog) } ?? []
            var units:[[String:Any]]=[]
            for id in ["p1","p2","m1","m2"] {
                let unit=model.state.units[id]!,stats=try GameRules.attributes(unit,catalog:model.engine.catalog)
                let pose=PartyVisual.pose(unit:unit,intent:visible,age:age,time:time,hurtAge:hurts[id].map{time-$0})
                let monster=PartyVisual.monster(time:time+(id=="m2" ? 0.7:0),attackAge:nil,hurtAge:hurts[id].map{time-$0},preparing:model.current==id && visible==nil)
                units.append(["id":id,"name":unit.name,"weaponID":unit.equipment.weapon as Any? ?? NSNull(),"armorID":unit.equipment.armor as Any? ?? NSNull(),"weaponPose":NSNull(),"vitalsVisible":unit.kind != .monster || unit.isAlive,"hp":visualHealth[id] ?? unit.health,"gameHP":unit.health,"maxHP":stats.maximumHealth,"baseAP":stats.baseAP,"maximumAP":stats.maximumAP,"attributeDamage":stats.damage,"shield":visualShield[id] ?? unit.shield,"gameShield":unit.shield,"ap":unit.ap,"buff":unit.damageBuff?.amount ?? 0,"buffRounds":unit.damageBuff?.roundsLeft ?? 0,"clip":pose.clip,"progress":pose.progress,"monster":try object(monster),"deathAge":deaths[id].map{time-$0} as Any? ?? NSNull()])
                if id.hasPrefix("p") {
                    var request:[String:Any]=["kind":"dragonFlame-\(id)","frame":frame,"time":time,"shield":visualShield[id] ?? unit.shield,"emitters":[]]
                    if let at=supportStarts[id],time-at<1.8 { request["recoveryAge"]=time-at;request["recoveryStrength"]=supportStrength[id] ?? 1 }
                    if let at=shieldBirths[id],(visualShield[id] ?? unit.shield)>0 { request["birth"]=time-at }
                    requests.append(request)
                }
            }
            let geometry=visible.map { SpellbladeEffects.sample(action:action,age:age,actor:actor,target:target,recipients:cues,weaponID:$0.weaponID,targets:$0.targets) } ?? RuneEffectSample()
            let dark=hover ? BattleDice.darkness(action)*PartyVisual.smooth((time-0.20)/0.28):visible != nil ? SpellbladeEffects.darkness(action,age:age,from:BattleDice.darkness(action)):0
            let travel=PartyVisual.travel(visible,age:age)
            let anchor=PartyVisual.diceAnchor(actor:actor,intent:visible,age:age,diceCount:dice.count)
            let diePose=dice.indices.map { BattleDice.pose(time:time,index:$0,resolvedAge:hitAt.map{time-$0},visibleAge:max(0,time-0.20)) }
            let projectedDice=dice.enumerated().map { index,die in
                PolyhedralDice.sample(die:die,time:time,index:index,count:dice.count,resolvedAge:hitAt.map{time-$0},visibleAge:max(0,time-0.20),locked:!hover,confirmationAge:hover ? nil:age)
            }
            rows.append(["scenario":"dragonFlame","statusCueAge":action.statusVFXCueAge ?? action.impact,"statusCueAt":start+(action.statusVFXCueAge ?? action.impact),"statusFeedbackPending":!pendingStatus.isEmpty,"frame":frame,"time":time,"hitPoints":try object(Dictionary(uniqueKeysWithValues:["p1","p2","m1","m2"].map{($0,PartyVisual.hitPoint(target:$0))})),"damageLabels":labels.filter{time-($0["at"] as! Double)<1},"staff":NSNull(),"ranged":false,"weaponTrail":[],"projectile":NSNull(),"locked":!hover,"confirmationAge":hover ? NSNull():age,"hover":hover,"darkness":dark,"actor":actor,"target":target,"action":action.rawValue,"age":age,"playing":visible != nil,"enemy":false,"impact":hitAt as Any? ?? NSNull(),"afterimages":[],"ambushSlashes":[],"receiptDice":try object(receipt?.dice ?? []),"dice":try object(dice),"diceAnchor":try object(anchor),"dicePose":try object(diePose),"poly":try object(projectedDice),"travel":try object(travel),"current":(visible?.actor ?? model.current) as Any? ?? NSNull(),"acted":Array(model.state.battle?.acted ?? []),"units":units,"runes":try object(geometry),"recipients":try object(cues),"committed":committed != nil])
            let active=emitters.compactMap { e -> [String:Any]? in let elapsed=time-(e["at"] as! Double);guard elapsed<3 else{return nil};return ["kind":e["kind"]!,"age":elapsed,"x":e["x"]!,"y":e["y"]!,"floor":e["floor"]!] }
            requests.append(["kind":"dragonFlame-fx","frame":frame,"time":time,"shield":0,"emitters":active])
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("dragon-flame-frames.json"))
        try JSONSerialization.data(withJSONObject:requests,options:[.sortedKeys]).write(to:out.appendingPathComponent("dragon-flame-light-requests.json"))
        print("Exported \(rows.count) 60 Hz full-scene Dragon Flame frames; one atomic node-wide receipt, impact and layered light included (seed \(chosen))")
    }

    static func exportRunes(out:URL) throws {
        var rows:[[String:Any]]=[],requests:[[String:Any]]=[]
        func object<T:Encodable>(_ value:T)throws->Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) }
        for scenario in ["runeSlash","runeSlash-lethal","runeWard","battleRune","runeSlash-buffed"] {
            let gear=try TrainingLoadout();try gear.equip("greatSword");try gear.equipArmor("runeArmor");try gear.equipAccessory("powerBadge")
            let action:PartyAction=scenario.hasPrefix("runeSlash") ? .runeSlash:scenario=="runeWard" ? .runeWard:.battleRune
            var seed:UInt64=47
            if scenario=="runeSlash" {
                for n in UInt64(1)...100 {
                    let probe=try PartyEncounter(seed:n,loadouts:gear.units,playerClassID:"spellblade");try probe.engine.apply(.endTurn(actor:"p2",timedOut:false))
                    _=probe.prepare(.runeSlash,target:"m1")
                    if (probe.confirmedReceipt?.after.units["m1"]?.health ?? 0)>0 { seed=n;break }
                }
            }
            let p=try PartyEncounter(seed:seed,sessionID:"rune-review-"+scenario,loadouts:gear.units,playerClassID:"spellblade")
            try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
            if scenario=="runeSlash-buffed" { let i=p.prepare(.battleRune,target:"p1")!;_=try p.commit(i.id) }
            if scenario=="runeSlash-lethal" { try p.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:3)));try p.engine.apply(.editResources(unit:"m2",value:ResourcePatch(health:0))) }
            let target=action.isOffensive ? "m1":"p1",actor="p1",original=p.state
            let actorUnit=original.units[actor]!,targetUnit=original.units[target]!
            var dice=BattleDice.channels(action,actor:actorUnit,target:targetUnit,catalog:p.engine.catalog),intent:PartyIntent?,receipt:OperationReceipt?,hitAt:Double?
            var hurts:[String:Double]=[:],deaths:[String:Double]=scenario=="runeSlash-lethal" ? ["m2":-3]:[:],births:[String:Double]=[:],heals:[String:Double]=[:],strengths:[String:Double]=[:],healingTiers:[String:HealingEffectTier]=[:]
            var visualHealth=Dictionary(uniqueKeysWithValues:original.units.map { ($0.key,$0.value.health) }),visualShield=Dictionary(uniqueKeysWithValues:original.units.map { ($0.key,$0.value.shield) })
            var pendingStatus:[String:(at:Double,health:Int,shield:Int,heal:Int,gain:Int,x:Double,y:Double)]=[:]
            var emitters:[[String:Any]]=[],labels:[[String:Any]]=[];let start=1.0,count=235
            for frame in 0..<count {
                let time=Double(frame)*0.02,age=time-start
                if frame==50 {
                    intent=p.prepare(action,target:target)!
                    dice=BattleDice.channels(action,actor:actorUnit,target:targetUnit,catalog:p.engine.catalog,receipt:p.confirmedReceipt)
                }
                let cues=intent.map { SpellbladeEffects.recipients($0,catalog:p.engine.catalog) } ?? []
                if let i=intent,receipt==nil,age+1e-8>=action.impact {
                    receipt=try p.commit(i.id);hitAt=time
                    if let r=receipt {
                        dice=BattleDice.channels(action,actor:actorUnit,target:targetUnit,catalog:p.engine.catalog,receipt:r)
                        for id in ["p1","p2","m1","m2"] {
                            let a=r.before.units[id]!,b=r.after.units[id]!,foot=PartyVisual.feet[id]!,point=PartyVisual.hitPoint(target:id,weaponID:i.weaponID)
                            let damage=max(0,a.health-b.health),gain=max(0,b.shield-a.shield),heal=max(0,b.health-a.health)
                            if damage>0 { hurts[id]=time;labels.append(["text":"−\(damage)","x":point.x,"y":point.y,"at":time]);emitters.append(["kind":"strike","at":time,"x":point.x,"y":point.y,"floor":foot.y]) }
                            visualHealth[id]=b.health-heal;visualShield[id]=b.shield-gain
                            if heal>0 || gain>0 {
                                let cueAt=start+(SpellbladeEffects.statusVFXCueAge(for:i.action) ?? i.action.impact)
                                if cueAt>time+0.0001 { pendingStatus[id]=(cueAt,b.health,b.shield,heal,gain,foot.x,foot.y) }
                                else {
                                    visualHealth[id]=b.health;visualShield[id]=b.shield
                                    if heal>0 { heals[id]=cueAt;healingTiers[id]=HealingEffectTier.classify(actualHPGained:heal);strengths[id]=SpellbladeEffects.healingStrength(heal);labels.append(["text":"＋\(heal)","x":foot.x,"y":foot.y,"at":cueAt,"supportUnit":id,"supportLine":0]) }
                                    if gain>0 { births[id]=cueAt;labels.append(["text":"盾 ＋\(gain)","x":foot.x,"y":foot.y,"at":cueAt,"supportUnit":id,"supportLine":1]) }
                                }
                            }
                            if b.damageBuff != a.damageBuff,let buff=b.damageBuff { labels.append(["text":"伤害 ＋\(buff.amount)","x":foot.x,"y":foot.y,"at":time,"supportUnit":id,"supportLine":(heal>0 || gain>0) ? 2:0]) }
                            if a.isAlive && !b.isAlive { deaths[id]=time;emitters.append(["kind":"death","at":time,"x":point.x,"y":point.y,"floor":foot.y]) }
                        }
                    }
                }
                let readyStatus=pendingStatus.filter { $0.value.at<=time+1e-9 }
                for (id,cue) in readyStatus {
                    visualHealth[id]=cue.health;visualShield[id]=cue.shield;pendingStatus.removeValue(forKey:id)
                    if cue.heal>0 { heals[id]=cue.at;healingTiers[id]=HealingEffectTier.classify(actualHPGained:cue.heal);strengths[id]=SpellbladeEffects.healingStrength(cue.heal);labels.append(["text":"＋\(cue.heal)","x":cue.x,"y":cue.y,"at":cue.at,"supportUnit":id,"supportLine":0]) }
                    if cue.gain>0 { births[id]=cue.at;labels.append(["text":"盾 ＋\(cue.gain)","x":cue.x,"y":cue.y,"at":cue.at,"supportUnit":id,"supportLine":1]) }
                }
                let showing=intent.flatMap { age<action.duration ? $0:nil },victory=(p.state.battle==nil && time>=start+action.duration) ? time-(start+action.duration):nil
                var units:[[String:Any]]=[]
                for id in ["p1","p2","m1","m2"] {
                    let u=p.state.units[id]!,stats=try GameRules.attributes(u,catalog:p.engine.catalog)
                    let pose=PartyVisual.pose(unit:u,intent:showing,age:age,time:time,hurtAge:hurts[id].map { time-$0 },victoryAge:victory)
                    let monster=PartyVisual.monster(time:time+(id=="m2" ? 0.7:0),attackAge:nil,hurtAge:hurts[id].map { time-$0 },preparing:p.current==id && showing==nil)
                    units.append(["id":id,"name":u.name,"weaponID":u.equipment.weapon as Any? ?? NSNull(),"armorID":u.equipment.armor as Any? ?? NSNull(),"weaponPose":u.equipment.weapon=="greatSword" ? try object(GreatSwordRig.pose(progress:pose.progress,clip:pose.clip)):NSNull(),"vitalsVisible":u.kind != .monster || u.isAlive,"hp":visualHealth[id] ?? u.health,"gameHP":u.health,"maxHP":stats.maximumHealth,"baseAP":stats.baseAP,"maximumAP":stats.maximumAP,"attributeDamage":stats.damage,"accessory":try AccessoryReadout.make(u,catalog:p.engine.catalog).map { try object($0) } as Any? ?? NSNull(),"shield":visualShield[id] ?? u.shield,"gameShield":u.shield,"ap":u.ap,"buff":u.damageBuff?.amount ?? 0,"buffRounds":u.damageBuff?.roundsLeft ?? 0,"clip":pose.clip,"progress":pose.progress,"monster":try object(monster),"deathAge":deaths[id].map { time-$0 } as Any? ?? NSNull()])
                    if id.hasPrefix("p") {
                        var q:[String:Any]=["kind":scenario+"-"+id,"frame":frame,"time":time,"shield":visualShield[id] ?? u.shield,"emitters":[],"recoveryStrength":strengths[id] ?? 1]
                        if let at=heals[id],let tier=healingTiers[id] { q["recoveryAge"]=time-at;q["recoveryTier"]=tier.rawValue }
                        if let at=births[id] { q["birth"]=time-at }
                        requests.append(q)
                    }
                }
                let hovering=time<start,geometry=showing.map { SpellbladeEffects.sample(action:action,age:age,actor:actor,target:target,recipients:cues,weaponID:$0.weaponID) } ?? RuneEffectSample()
                let dark=hovering ? BattleDice.darkness(action)*PartyVisual.smooth(time/0.28):showing != nil ? SpellbladeEffects.darkness(action,age:age,from:BattleDice.darkness(action)):0
                rows.append(["scenario":scenario,"statusCueAge":action.statusVFXCueAge ?? action.impact,"statusCueAt":start+(action.statusVFXCueAge ?? action.impact),"statusFeedbackPending":!pendingStatus.isEmpty,"frame":frame,"time":time,"hitPoints":try object(Dictionary(uniqueKeysWithValues:["p1","p2","m1","m2"].map { ($0,PartyVisual.hitPoint(target:$0,weaponID:"greatSword")) })),"damageLabels":labels.filter { time-($0["at"] as! Double)<1 },"staff":NSNull(),"ranged":false,"weaponTrail":[],"projectile":NSNull(),"locked":!hovering,"confirmationAge":hovering ? NSNull():age,"hover":hovering,"darkness":dark,"actor":actor,"target":target,"action":action.rawValue,"age":age,"playing":showing != nil,"enemy":false,"impact":hitAt as Any? ?? NSNull(),"afterimages":[],"ambushSlashes":[],"receiptDice":try object(receipt?.dice ?? []),"dice":try object(dice),"diceAnchor":try object(PartyVisual.diceAnchor(actor:actor,intent:showing,age:age,diceCount:dice.count)),"poly":try object(dice.enumerated().map { index,die in PolyhedralDice.sample(die:die,time:time,index:index,count:dice.count,resolvedAge:hitAt.map { time-$0 },visibleAge:time,locked:!hovering,confirmationAge:hovering ? nil:age) }),"dicePose":try object(dice.indices.map { BattleDice.pose(time:time,index:$0,resolvedAge:hitAt.map { time-$0 },visibleAge:time) }),"travel":try object(PartyVisual.travel(showing,age:age)),"current":(showing?.actor ?? p.current) as Any? ?? NSNull(),"acted":Array(p.state.battle?.acted ?? []),"units":units,"runes":try object(geometry),"recipients":try object(cues)])
                let emissions=emitters.compactMap { e -> [String:Any]? in
                    let t=time-(e["at"] as! Double);guard t<3 else{return nil};return ["kind":e["kind"]!,"age":t,"x":e["x"]!,"y":e["y"]!,"floor":e["floor"]!]
                }
                requests.append(["kind":scenario+"-fx","frame":frame,"time":time,"shield":0,"emitters":emissions])
            }
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("spellblade-frames.json"))
        try JSONSerialization.data(withJSONObject:requests,options:[.sortedKeys]).write(to:out.appendingPathComponent("spellblade-light-requests.json"))
        print("Exported \(rows.count) spellblade receipt, dice, pose and rune frames plus \(requests.count) light requests")
    }
    static func exportMonsters(out:URL)throws {
        var rows=[[String:Any]]()
        for id in MonsterVisualSpec.ids {
            let spec=MonsterVisualSpec.find(id)!,actor="m-9-1",foot=PartyVisual.foot(actor)!
            let intent=PartyIntent(id:"review-"+id,action:.attack,actor:actor,target:"p1",targets:["p1"],command:.monsterStep,enemy:true,weaponID:nil,monsterTemplateID:id,enemyRanged:spec.ranged)
            for frame in 0..<320 {
                let time=Double(frame)*0.02,attack=time>=0.8 && time<1.9 ? time-0.8:nil,hurt=time>=2.4 && time<2.8 ? time-2.4:nil,cast=time>=3.2 && time<4.6 ? time-3.2:nil,death=time>=5 ? time-5:nil
                let index=death.map(MonsterVisualSpec.deathFrame) ?? spec.frame(time:time,attackAge:attack,castAge:cast,hurtAge:hurt)
                let offset=PartyVisual.travel(attack != nil ? intent:nil,age:attack ?? 0)
                let arrow=attack.flatMap{spec.projectile(age:$0,foot:foot,target:PartyVisual.hitPoint(target:"p1"))}
                let enc=JSONEncoder()
                func point(_ p:PartyPoint)->[Double]{[p.x,p.y]}
                var row:[String:Any]=["species":id,"frame":frame,"time":time,"poseIndex":index,"death":death != nil,"visible":death.map{$0<MonsterVisualSpec.deathDuration} ?? true,"foot":point(foot),"offset":point(offset),"scale":spec.scale,"phase":death != nil ? "death":attack != nil ? "attack":hurt != nil ? "hurt":cast != nil ? "cast":"idle"]
                let incoming=PartyIntent(id:"incoming",action:.attack,actor:"p1",target:actor,targets:[actor],command:.attack(actor:"p1",target:actor),enemy:false,weaponID:"trainingSword",targetTemplateID:id)
                row["registeredHit"]=point(PartyVisual.hitPoint(target:actor,templateID:id));row["hitAnchor"]=point(spec.hitAnchor);row["incomingTravel"]=point(PartyVisual.travel(incoming,age:1.048))
                if let arrow{row["projectile"]=try JSONSerialization.jsonObject(with:enc.encode(arrow))}
                rows.append(row)
            }
        }
        try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]).write(to:out.appendingPathComponent("monster-frames.json"))
        print("Exported \(rows.count) registered species pose/travel/missile frames; no App or simulator")
    }

}
