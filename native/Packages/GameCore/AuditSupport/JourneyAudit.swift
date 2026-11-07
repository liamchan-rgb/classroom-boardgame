import Foundation
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport

public struct MeadowJourneyAuditReport:Codable,Equatable {
    public let size:Int,seed:String,role:String,outcome:String,itinerary:String
    public let battles:Int,cleared:Int,actions:Int,monsterActions:Int,resumes:Int,stagedRestarts:Int
    public let plannedSpecies:[String],foughtSpecies:[String]
    public let visited:[Int],collected:[Int],finalHealth:[String:Int],finalAP:[String:Int]
    public let startingCoins:Int,nodeCoins:Int,dropCoins:Int,movementSpent:Int,finalCoins:Int
    public let totalDistance:Double
    public let actionsUsed:[String:Int]
    public let blockedRecovery:Int
    public let manualActionRefills:Int
    public let battleDetails:[MeadowAuditedBattle]
}
public struct MeadowAuditedBattle:Codable,Equatable {
    public let node:Int,templates:[String],firstActor:String
    public let rounds:Int,outcome:String
    public let healthBefore:[String:Int],healthAfter:[String:Int],naturalTwenties:[String:Int]
    public let collectedSupplies:[Int]
}

/// Pure command-line regression driver, not game autoplay or a balance oracle.
/// A fixed mean-effect heuristic selects legal actions WITHOUT reading staged
/// rolls. No scripted dice, stat edits, free movement or synthetic loot.
/// Recovery uses real items and the same explicit AP-rest operation as the UI.
public enum MeadowJourneyAudit {
    public static func run(size:Int,seed:UInt64,role:String,allowManualRest:Bool=true,supplyDetour:Bool=false,loadout:MeadowAuditLoadout?=nil,companionRole:String="ranger")throws->MeadowJourneyAuditReport {
        let layout=try MeadowMapGenerator.generate(.suggested(total:size,seed:seed))
        var s=try MeadowCampaignSession.new(layout:layout,playerClassID:role,companionClassID:companionRole,loadouts:try loadout?.units(role:role))
        let start=s.engine.state.players[0].nodeID,starting=s.partyCoins
        var visited:Set<Int>=[start],collected=Set<Int>(),fought=Set<String>(),actionsUsed=[String:Int]()
        var battles=0,cleared=0,actions=0,enemyActions=0,resumes=0,restarts=0,blockedRecovery=0
        var outcome="incomplete"
        var battleDetails=[MeadowAuditedBattle]()
        func require(_ condition:Bool,_ message:String)throws {if !condition{throw GameError("audit \(role)/\(size)/\(seed): "+message)}}
        func restore()throws {
            let archive=s.engine.archive,position=s.engine.state.players.map{s.position(of:$0.id)}
            let remaining=s.movementRemaining
            s=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()));resumes+=1
            try require(s.engine.archive==archive,"archive changed on resume")
            try require(s.engine.state.players.map{s.position(of:$0.id)}==position,"road cursor changed on resume")
            try require(s.movementRemaining==remaining,"movement changed on resume")
        }
        func travel(_ target:Int)throws->Bool {
            let actor=try firstAlive(s)
            if s.engine.state.units[actor]!.nodeID==target && s.travel==nil{return true}
            if s.movementRemaining<0.000001 {
                if s.movementPurchaseCoins==0{return false}
                try s.refillMovement(usingCoins:true)
            }
            try s.beginTravel(to:target,actor:actor)
            if resumes==0 {try s.advanceTravel(distance:10);try restore();if s.travel != nil{try s.setPaused(false)}}
            for _ in 0..<500 where s.travel != nil {
                if !s.isMoving {
                    if s.movementPurchaseCoins==0{return false}
                    try s.refillMovement(usingCoins:true);try s.setPaused(false)
                }
                let ap=s.engine.state.players.map(\.ap),hp=s.engine.state.players.map(\.health)
                let receipts=try s.advanceTravel(distance:100000)
                for r in receipts {for e in r.events where e.kind=="campaignArrival" {if let n=Int(e.detail){visited.insert(n)}}}
                try require(s.engine.state.players.map(\.ap)==ap && s.engine.state.players.map(\.health)==hp,"travel altered combat vitals")
                try require(s.engine.state.battle==nil,"passing a node forced a battle")
            }
            try require(s.travel==nil,"travel exceeded step bound");return true
        }
        func recover()throws {
            if allowManualRest, s.inventoryActionRefillNeeded {try s.refillInventoryActions()}
            // Use only real inventories, legal exploration AP, and co-located
            // targets. Record a stranded member rather than teleporting them.
            for recipient in s.engine.state.players where !recipient.isAlive {
                var rescued=false
                for actor in s.engine.state.players where actor.isAlive {
                    if let cmd=try? s.inventoryItemCommand(actor:actor.id,item:"revivalStone",target:recipient.id),s.engine.preview(cmd).allowed {
                        try s.useInventory(actor:actor.id,item:"revivalStone",target:recipient.id);rescued=true;break
                    }
                }
                if !rescued{blockedRecovery+=1}
            }
            for target in s.engine.state.players where target.isAlive {
                let maximum=try GameRules.attributes(target,catalog:s.engine.catalog).maximumHealth
                if target.health*2>=maximum{continue}
                for actor in s.engine.state.players where actor.isAlive {
                    let missing=maximum-s.engine.state.units[target.id]!.health
                    let item=missing>=12 ? "largePotion":"smallPotion"
                    if let cmd=try? s.inventoryItemCommand(actor:actor.id,item:item,target:target.id),s.engine.preview(cmd).allowed {
                        try s.useInventory(actor:actor.id,item:item,target:target.id);break
                    }
                }
            }
        }
        func battle()throws {
            let healthBefore=Dictionary(uniqueKeysWithValues:s.engine.state.players.map{($0.id,$0.health)})
            try s.interactCurrentNode(actor:firstAlive(s));battles+=1
            var model=try PartyEncounter(engine:s.engine,sessionID:"audit/\(battles)/initial")
            let node=try s.engine.state.units[firstAlive(s)]!.nodeID
            let templates=model.monsterIDs.map{s.engine.state.units[$0]!.templateID}
            let firstActor=model.current.flatMap{s.engine.state.units[$0]}.map{$0.kind == .monster ? $0.templateID:$0.id} ?? "none"
            var rounds=0,naturalTwenties=[String:Int]()
            for id in model.monsterIDs{fought.insert(s.engine.state.units[id]!.templateID)}
            for unit in s.engine.state.players where unit.isAlive {
                try require(unit.ap==(try GameRules.attributes(unit,catalog:s.engine.catalog).baseAP),"opening AP is not individual baseAP")
            }
            var resumed=false,restarted=false
            for _ in 0..<600 {
                if model.terminal{break}
                rounds=max(rounds,model.round)
                let actor=try unwrap(model.current,"battle missing current actor")
                let enemy=s.engine.state.units[actor]!.kind == .monster
                if enemy && !resumed {try restore();model=try PartyEncounter(engine:s.engine,sessionID:"audit/\(battles)/resume");resumed=true}
                let before=s.engine.archive
                let choice=enemy ? nil:try choose(model)
                try require(s.engine.archive==before,"preview changed live archive")
                var intent=enemy ? model.prepareMonsterStep():model.prepare(choice!.0,target:choice!.1)
                if !enemy && !restarted {
                    let staged=try unwrap(model.confirmedReceipt,"player action did not stage")
                    model.cancel();try restore();model=try PartyEncounter(engine:s.engine,sessionID:"audit/\(battles)/restart")
                    intent=model.prepare(choice!.0,target:choice!.1)
                    try require(model.confirmedReceipt?.dice==staged.dice && model.confirmedReceipt?.after==staged.after,"staged interruption rerolled action")
                    restarted=true;restarts+=1
                }
                let action=try unwrap(intent,"no legal staged action"),expected=try unwrap(model.confirmedReceipt,"missing confirmed receipt")
                try require(s.engine.archive==before,"confirmation committed before impact")
                let receipt=try unwrap(try model.commit(action.id),"impact missing receipt")
                try require(receipt.after==expected.after && receipt.dice==expected.dice,"impact differs from confirmed roll")
                try require(try model.commit(action.id)==nil,"duplicate impact committed twice")
                actions+=1;if enemy{enemyActions+=1};actionsUsed[(enemy ? "enemy:":"player:")+action.action.rawValue,default:0]+=1
                let twenties=receipt.dice.filter(\.naturalTwenty).count
                if twenties>0 {naturalTwenties[(enemy ? before.state.units[actor]!.templateID:actor)+"/"+(action.sourceSkillID ?? action.action.rawValue),default:0]+=twenties}
            }
            try require(model.terminal,"battle exceeded action bound")
            battleDetails.append(.init(node:node,templates:templates,firstActor:firstActor,rounds:rounds,outcome:s.canCompleteDefeat ? "defeat":"victory",healthBefore:healthBefore,healthAfter:Dictionary(uniqueKeysWithValues:s.engine.state.players.map{($0.id,$0.health)}),naturalTwenties:naturalTwenties,collectedSupplies:collected.sorted()))
            if s.engine.state.players.contains(where: \.isAlive){cleared+=1;try recover()}
        }
        // The baseline follows a closed BFS-spanning-tree walk, matching the
        // supply budget's reference distance. Subtrees with nearby supplies go
        // first; bosses are handled on the way back after their descendants.
        // An optional collect-all-supplies detour remains a separate stress run.
        let encounterPlan=MeadowEncounterPlanner.plan(layout)
        let rewards=layout.map.nodes.filter{$0.kind == .reward}.sorted {
            let a=s.routeDistance(layout.map.shortestPath(from:start,to:$0.id)!),b=s.routeDistance(layout.map.shortestPath(from:start,to:$1.id)!)
            return a==b ? $0.id<$1.id:a<b
        }
        let encounters=encounterPlan.sorted {if ($0.band=="boss") != ($1.band=="boss"){return $1.band=="boss"};return $0.distance==$1.distance ? $0.nodeID<$1.nodeID:$0.distance<$1.distance}
        if supplyDetour {
            for node in rewards {
                if try !travel(node.id){outcome="needsMovementCoins";break}
                try s.interactCurrentNode(actor:firstAlive(s));collected.insert(node.id)
            }
            if outcome=="incomplete" {for entry in encounters {
                if try !travel(entry.nodeID){outcome="needsMovementCoins";break}
                try battle();if s.canCompleteDefeat {outcome="defeat";break}
            }}
        }else{
            var children=[Int:[Int]](),queue=[start],seen:Set<Int>=[start],cursor=0
            while cursor<queue.count {
                let id=queue[cursor];cursor+=1
                for next in layout.map.neighbors(id) where seen.insert(next).inserted {children[id,default:[]].append(next);queue.append(next)}
            }
            func edge(_ a:Int,_ b:Int)->Double{s.routeDistance([a,b])}
            func nearestCache(_ id:Int)->Double {
                if rewards.contains(where:{$0.id==id}){return 0}
                return (children[id] ?? []).map{edge(id,$0)+nearestCache($0)}.min() ?? .infinity
            }
            func visit(_ id:Int)throws {
                guard outcome=="incomplete" else{return}
                if try !travel(id){outcome="needsMovementCoins";return}
                let node=layout.map.nodes.first{$0.id==id}!
                if node.kind == .reward {try s.interactCurrentNode(actor:firstAlive(s));collected.insert(id)}
                if node.kind == .combat {try battle();if s.canCompleteDefeat{outcome="defeat";return}}
                let ordered=(children[id] ?? []).sorted{let a=edge(id,$0)+nearestCache($0),b=edge(id,$1)+nearestCache($1);return a==b ? $0<$1:a<b}
                for child in ordered {
                    try visit(child);guard outcome=="incomplete" else{return}
                    if try !travel(id){outcome="needsMovementCoins";return}
                }
                if node.kind == .boss {try battle();if s.canCompleteDefeat{outcome="defeat"}}
            }
            try visit(start)
        }
        if outcome=="incomplete" {
            if s.completionGoalMet {
                if try travel(start){outcome="victory"}else{outcome="needsMovementCoins"}
            }else{outcome="goalNotMet"}
        }
        if outcome=="victory" || outcome=="defeat" {
            let result=try s.completeCampaign(),archive=s.engine.archive
            try restore();try require(try s.completeCampaign()==result,"completion not idempotent after resume")
            try require(s.engine.archive==archive,"completion changed resources")
            do{try s.beginTravel(to:start);throw GameError("audit: sealed campaign moved")}catch let e as GameError{try require(e.message != "audit: sealed campaign moved",e.message)}
        }
        let history=s.engine.history,events=history.flatMap(\.events)
        let nodeCoins=events.filter{$0.kind=="nodeReward"}.reduce(0){$0+$1.amount}
        let dropCoins=events.filter{$0.kind=="drop" && $0.detail=="coins"}.reduce(0){$0+$1.amount}
        let spent=history.reduce(0){sum,r in if case .refillCampaignMovement(_,let coins,_) = r.command{return sum+coins};return sum}
        try require(s.partyCoins==starting+nodeCoins+dropCoins-spent,"coin ledger does not balance")
        try require(s.snapshot.movement?.manualRefills==0,"audit used free movement refill")
        return .init(size:size,seed:String(seed),role:role,outcome:outcome,itinerary:supplyDetour ? "supplies-first-detour":"closed-tree",battles:battles,cleared:cleared,actions:actions,monsterActions:enemyActions,resumes:resumes,stagedRestarts:restarts,plannedSpecies:Array(Set(encounterPlan.flatMap(\.templates))).sorted(),foughtSpecies:fought.sorted(),visited:visited.sorted(),collected:collected.sorted(),finalHealth:Dictionary(uniqueKeysWithValues:s.engine.state.players.map{($0.id,$0.health)}),finalAP:Dictionary(uniqueKeysWithValues:s.engine.state.players.map{($0.id,$0.ap)}),startingCoins:starting,nodeCoins:nodeCoins,dropCoins:dropCoins,movementSpent:spent,finalCoins:s.partyCoins,totalDistance:s.snapshot.movement?.totalDistance ?? 0,actionsUsed:actionsUsed,blockedRecovery:blockedRecovery,manualActionRefills:history.filter{$0.command == .refillExploration}.count,battleDetails:battleDetails)
    }
    private static func firstAlive(_ s:MeadowCampaignSession)throws->String {try unwrap(s.engine.state.players.first(where: \.isAlive)?.id,"no living expedition actor")}
    private static func unwrap<T>(_ value:T?,_ message:String)throws->T {guard let value else{throw GameError("audit: "+message)};return value}

    private static func choose(_ model:PartyEncounter)throws->(PartyAction,String) {
        let actor=try unwrap(model.current.flatMap{model.state.units[$0]},"missing player")
        let catalog=model.engine.catalog,state=model.state,stats=try GameRules.attributes(actor,catalog:catalog)
        var options=[(Double,PartyAction,String)]()
        for action in (model.playerActions()+[.smallPotion,.largePotion,.shieldPotion,.revivalStone]).sorted(by:{$0.rawValue<$1.rawValue}) {
            for target in state.units.values.sorted(by:{$0.id<$1.id}) where target.kind == .player || model.monsterIDs.contains(target.id) {
                guard model.preview(action,target:target.id).allowed else{continue}
                var score=0.0
                if action == .attack {
                    let attack=try GameRules.attack(actor,catalog:catalog)
                    let mean=Double(attack.dice.count*(attack.dice.sides+1))/2+Double(attack.dice.flat+stats.damage)
                    score=min(mean,Double(target.health+target.shield))+(mean>=Double(target.health+target.shield) ? 4:0)
                }else if action == .revivalStone {
                    score=Double(try GameRules.attributes(target,catalog:catalog).maximumHealth)/2*1.5+12
                }else if action.isItem {
                    let item=try catalog.item(action.rawValue),maximum=try GameRules.attributes(target,catalog:catalog).maximumHealth
                    score=Double(min(item.heal,maximum-target.health))*(target.health*2<maximum ? 1.7:0.7)+Double(max(0,item.shield-target.shield))*0.65
                }else {
                    let skill=try catalog.skill(action.rawValue)
                    let selected:[GameUnit]
                    switch skill.target {
                    case .selfOnly:selected=[actor]
                    case .enemy,.ally:selected=[target]
                    case .alliesAtNode:selected=state.players.filter{$0.isAlive && $0.nodeID==target.nodeID}
                    case .enemiesAtNode:selected=model.monsterIDs.compactMap{state.units[$0]}.filter{$0.isAlive && $0.nodeID==target.nodeID}
                    }
                    for effect in skill.effects {
                        let mean=Double(effect.amount)+(effect.dice.map{Double($0.count*($0.sides+1))/2+Double($0.flat)} ?? 0)
                        for unit in effect.scope == .caster ? [actor]:selected {
                            let maximum=try GameRules.attributes(unit,catalog:catalog).maximumHealth
                            switch effect.kind {
                            case .damage:score+=min(mean+Double(stats.damage),Double(unit.health+unit.shield))+(mean+Double(stats.damage)>=Double(unit.health+unit.shield) ? 4:0)
                            case .heal:score+=min(mean,Double(maximum-unit.health))*(unit.health*2<maximum ? 1.7:0.7)
                            case .shield:score+=max(0,mean-Double(unit.shield))*0.65
                            case .damageBuff:score+=max(0,mean-Double(unit.damageBuff?.amount ?? 0))*Double(min(2,effect.rounds))*1.5
                            }
                        }
                    }
                }
                score/=Double(max(1,model.cost(action)))
                if score>0{options.append((score,action,target.id))}
            }
        }
        let sorted=options.sorted{if abs($0.0-$1.0)>1e-9{return $0.0>$1.0};return $0.1.rawValue==$1.1.rawValue ? $0.2<$1.2:$0.1.rawValue<$1.1.rawValue}
        if let best=sorted.first{return (best.1,best.2)}
        return (.endTurn,actor.id)
    }
}
