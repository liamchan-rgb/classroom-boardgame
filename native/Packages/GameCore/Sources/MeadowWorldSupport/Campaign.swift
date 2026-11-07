import Foundation
import ClassroomGameCore

public enum MeadowMovementRules {
    public static let distancePerMaximumAP:Double=50
    public static let distancePerCoin:Double=50
    public static func capacity(_ archive:GameArchive)->Double {
        let values=archive.state.players.compactMap{try? GameRules.attributes($0,catalog:archive.catalog).maximumAP}
        guard !values.isEmpty else{return 0}
        return values.map(Double.init).reduce(0,+)/Double(values.count)*distancePerMaximumAP
    }
}
public struct MeadowCampaignMovement:Codable,Equatable {
    public var scale:Double?=MeadowMovementRules.distancePerMaximumAP
    public var remaining:Double
    public var totalDistance:Double=0
    public var manualRefills:Int=0
    public var purchasedRefills:Int=0
    public init(remaining:Double){self.remaining=remaining}
}
public struct MeadowCampaignTravel: Codable, Equatable {
    public let id:String
    public let actors:[String]
    public let path:[Int]
    public var leg:Int=0
    public var distance:Double=0
    public var paused=false
    public var stopDistance:Double?=nil
}
public struct MeadowCampaignCamera:Codable,Equatable {
    public var x:Double,y:Double,zoom:Double
    public init(x:Double,y:Double,zoom:Double=1){self.x=x;self.y=y;self.zoom=zoom}
    func validate()throws {guard x.isFinite,y.isFinite,zoom.isFinite,(1...3).contains(zoom) else{throw GameError("镜头数据无效。")}}
}
public struct MeadowCampaignCompletion:Codable,Equatable {
    public let id:String,gameID:String,outcome:String
    public let completedAt:Date
    public let players:[GameUnit]
    public let exploredNodes:Int,totalNodes:Int,clearedEncounters:Int,totalEncounters:Int,collectedRewards:Int,totalRewards:Int
    public let distance:Double,movementCoins:Int,historyCount:Int
}
public struct MeadowCampaignSave:Codable,Equatable {
    public var completion:MeadowCampaignCompletion?=nil
    public var formatVersion=1
    public let layout:GeneratedMeadowMap
    public var archive:GameArchive
    public var travel:MeadowCampaignTravel?
    public var camera:MeadowCampaignCamera?
    public var movement:MeadowCampaignMovement?=nil
    public var selectedPlayerID:String?=nil
    public let appearanceID:String
    public func validate() throws {
        try archive.validate();try layout.configuration.validate();try layout.map.validate()
        guard formatVersion==1,layout.generatorVersion==3,["forester","wayfarer"].contains(appearanceID),
              layout.coordinateHeight.isFinite,layout.coordinateHeight>0,
              [.exploration,.pve].contains(archive.state.phase),archive.state.battle == nil || archive.state.battle?.kind == .pve,
              Set(archive.state.players.map(\.id))==Set(["p1","p2"]),archive.catalog == (try MeadowCampaignSession.catalog()),
              archive.state.map.nodes.map(\.id)==layout.map.nodes.map(\.id),archive.state.map.roads==layout.map.roads else {throw GameError("探索存档与当前地图或规则不匹配。")}
        let ids=Set(layout.map.nodes.map(\.id))
        let assets=Set(["CampTent","NodeCombatOutpost","NodeBossSanctum","NodeRewardCache","NodeWaystone","OakA","OakB","Pines","RockLow","RockHigh","RockSmall","Shrub","Flowers"])
        guard layout.props.allSatisfy({assets.contains($0.asset)}),archive.state.units.values.filter({$0.kind == .monster}).allSatisfy({u in
            archive.catalog.monsters.contains(where:{$0.id==u.templateID}) && (u.id=="m-\(u.nodeID)-1" || u.id=="m-\(u.nodeID)-2" || u.id=="m-\(u.nodeID)-3")
        }) else {throw GameError("探索资源或怪物数据不受支持。")}
        guard Set(layout.props.compactMap(\.nodeID))==ids,layout.props.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.width>0}),
              layout.roads.count==layout.map.roads.count,layout.roads.allSatisfy({$0.points.count>=2 && $0.points.allSatisfy{$0.x.isFinite && $0.y.isFinite}}) else {throw GameError("探索布局数据无效。")}
        for node in archive.state.map.nodes {
            guard let original=layout.map.nodes.first(where:{$0.id==node.id}),node.x==original.x,node.y==original.y,node.kind==original.kind,
                  layout.props.filter({$0.nodeID==node.id}).count==1 else {throw GameError("探索节点不匹配。")}
        }
        if let movement {
            guard movement.remaining.isFinite,movement.remaining>=0,movement.remaining<=MeadowMovementRules.capacity(archive)*(movement.scale ?? 150)/MeadowMovementRules.distancePerMaximumAP+0.000001,
                  (movement.scale ?? 150).isFinite,(movement.scale ?? 150)>0,movement.totalDistance.isFinite,movement.totalDistance>=0,movement.manualRefills>=0,movement.purchasedRefills>=0 else{throw GameError("移动条存档无效。")}
        }
        if let result=completion {
            let encounters=archive.state.map.nodes.filter{$0.kind == .combat || $0.kind == .boss}.count
            guard UUID(uuidString:result.id) != nil,result.gameID==archive.state.gameID,result.completedAt.timeIntervalSince1970.isFinite,
                  result.players==archive.state.players,result.historyCount==archive.history.count,archive.state.battle==nil,travel==nil,
                  result.exploredNodes==archive.state.map.revealed.count,result.totalNodes==archive.state.map.nodes.count,
                  result.totalEncounters==encounters,result.clearedEncounters==archive.state.map.nodes.filter({n in (n.kind == .combat || n.kind == .boss) && !archive.state.units.values.contains{$0.kind == .monster && $0.isAlive && $0.nodeID==n.id}}).count,
                  result.collectedRewards==archive.state.map.nodes.filter({$0.kind == .reward && $0.rewardCompleted}).count,
                  result.totalRewards==archive.state.map.nodes.filter({$0.kind == .reward}).count,
                  result.distance==(movement?.totalDistance ?? 0),result.distance.isFinite,result.distance>=0,result.movementCoins>=0,
                  ["victory","defeat"].contains(result.outcome) else{throw GameError("行程结算与存档不一致。")}
        }
        if let result=completion {
            if result.outcome=="victory" {
                guard !archive.state.units.values.contains(where:{$0.kind == .monster && $0.isAlive}),
                      (result.totalEncounters>0 || archive.state.map.nodes.allSatisfy({archive.state.map.revealed.contains($0.id)})),
                      let start=archive.state.map.nodes.first(where:{$0.kind == .start})?.id,
                      !archive.state.players.filter(\.isAlive).isEmpty,archive.state.players.filter(\.isAlive).allSatisfy({$0.nodeID==start}) else{throw GameError("通关条件未达成。")}
            }else{guard !archive.state.players.contains(where: \.isAlive) else{throw GameError("队伍未全员倒地。")}}
        }
        if let selectedPlayerID {guard archive.state.players.contains(where:{$0.id==selectedPlayerID}) else{throw GameError("操作成员无效。")}}
        try camera?.validate()
        if let t=travel {
            if let stop=t.stopDistance {
                guard stop.isFinite,stop>0,let last=t.path.last,t.path.count>=2,let p=Self.road(layout,from:t.path[t.path.count-2],to:last),stop<Self.length(p) else{throw GameError("道路目标无效。")}
            }
            guard archive.state.battle==nil,!t.id.isEmpty,!t.actors.isEmpty,Set(t.actors).count==t.actors.count,
                  t.path.count>=2,t.leg>=0,t.leg<t.path.count-1,t.distance.isFinite,t.distance>=0,
                  t.actors.allSatisfy({archive.state.units[$0]?.isAlive==true && archive.state.units[$0]?.kind == .player && (archive.state.units[$0]?.nodeID==t.path[t.leg] || archive.state.units[$0]?.nodeID==t.path[t.leg+1])}),
                  (1..<t.path.count).allSatisfy({archive.state.map.neighbors(t.path[$0-1]).contains(t.path[$0])}),
                  let points=Self.road(layout,from:t.path[t.leg],to:t.path[t.leg+1]),t.distance<Self.length(points)+0.000001 else {throw GameError("存档中的移动游标无效。")}
        }
    }
    public func encoded()throws->Data {try validate();let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return try e.encode(self)}
    public static func decoded(_ bytes:Data)throws->Self {let s=try JSONDecoder().decode(Self.self,from:bytes);try s.validate();return s}
    static func road(_ layout:GeneratedMeadowMap,from:Int,to:Int)->[MeadowWorldPoint]? {
        guard let r=layout.roads.first(where:{($0.from==from && $0.to==to)||($0.to==from && $0.from==to)}) else{return nil}
        return r.from==from ? r.points:Array(r.points.reversed())
    }
    static func length(_ p:[MeadowWorldPoint])->Double {zip(p,p.dropFirst()).map{hypot($0.1.x-$0.0.x,$0.1.y-$0.0.y)}.reduce(0,+)}
}
public final class MeadowCampaignStore {
    public let url:URL
    public init(url:URL){self.url=url}
    public func read()throws->MeadowCampaignSave? {FileManager.default.fileExists(atPath:url.path) ? try .decoded(Data(contentsOf:url)):nil}
    @discardableResult public func preserveCompletedCampaign()throws->URL? {
        guard let save=try read(),let result=save.completion else{return nil}
        let folder=url.deletingLastPathComponent().appendingPathComponent("Completed",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let target=folder.appendingPathComponent(result.id+".json");try save.encoded().write(to:target,options:.atomic);return target
    }
    public func completedCampaigns()throws->[MeadowCampaignSave] {try completedHistory().saves}
    public func completedHistory()throws->MeadowCampaignHistory {
        var values=[String:MeadowCampaignSave]()
        var issues=[MeadowCampaignReadIssue]()
        let folder=url.deletingLastPathComponent().appendingPathComponent("Completed",isDirectory:true)
        if FileManager.default.fileExists(atPath:folder.path){for file in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) where file.pathExtension=="json" {
            do {
                let save=try MeadowCampaignSave.decoded(Data(contentsOf:file))
                if let result=save.completion {
                    if let old=values[save.archive.state.gameID]?.completion,old.completedAt>result.completedAt{continue}
                    values[save.archive.state.gameID]=save
                }
            }catch{issues.append(.init(file:file.lastPathComponent,message:error.localizedDescription))}
        }}
        do{if let current=try read(),current.completion != nil{values[current.archive.state.gameID]=current}}
        catch{issues.append(.init(file:url.lastPathComponent,message:error.localizedDescription))}
        return .init(saves:values.values.sorted{let a=$0.completion!,b=$1.completion!;return a.completedAt==b.completedAt ? a.id<b.id:a.completedAt>b.completedAt},issues:issues.sorted{$0.file<$1.file})
    }
    public func write(_ data:Data)throws {try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url,options:.atomic)}
}
private final class CampaignWriter {
    var snapshot:MeadowCampaignSave
    let persist:((Data)throws->Void)?
    var closingAsDefeat=false
    init(_ snapshot:MeadowCampaignSave,persist:((Data)throws->Void)?){self.snapshot=snapshot;self.persist=persist}
    func write(_ value:MeadowCampaignSave)throws {
        var next=value
        try next.camera?.validate()
        if let amount=next.movement?.remaining {next.movement?.remaining=min(amount,MeadowMovementRules.capacity(next.archive))}
        if let persist {try persist(next.encoded())};snapshot=next
    }
}
/// Owns one persistent tabletop engine. Rendering advances a saved road cursor;
/// rules, AP, reveal, loot and encounters commit only at actual node arrival.
public final class MeadowCampaignSession {
    public let engine:GameEngine
    private let writer:CampaignWriter
    public var snapshot:MeadowCampaignSave {var s=writer.snapshot;s.archive=engine.archive;if let amount=s.movement?.remaining{s.movement?.remaining=min(amount,movementCapacity)};return s}
    public var travel:MeadowCampaignTravel? {writer.snapshot.travel}
    public var hasPendingTravel:Bool {
        guard let t=travel else{return false}
        return !(t.leg==t.path.count-2 && t.stopDistance.map{t.distance>=$0-0.000001}==true)
    }
    public var isMoving:Bool {travel.map{!$0.paused} ?? false}
    public var playerIDs:[String] {engine.state.players.map(\.id)}
    public var completion:MeadowCampaignCompletion? {writer.snapshot.completion}
    public var isCompleted:Bool {completion != nil}
    public var totalEncounterNodes:Int {engine.state.map.nodes.filter{$0.kind == .combat || $0.kind == .boss}.count}
    public var clearedEncounterNodes:Int {engine.state.map.nodes.filter{n in (n.kind == .combat || n.kind == .boss) && !engine.state.units.values.contains{$0.kind == .monster && $0.nodeID==n.id && $0.isAlive}}.count}
    public var completionGoalMet:Bool {
        if totalEncounterNodes>0{return cleared}
        return engine.state.map.nodes.allSatisfy{engine.state.map.revealed.contains($0.id)}
    }
    public var canComplete:Bool {
        guard !isCompleted,travel==nil,engine.state.battle==nil,completionGoalMet,let start=engine.state.map.nodes.first(where:{$0.kind == .start})?.id else{return false}
        let survivors=engine.state.players.filter(\.isAlive);return !survivors.isEmpty && survivors.allSatisfy{$0.nodeID==start}
    }
    public var completionProgress:String {
        if isCompleted{return "行程已结算，可查看结果"}
        if canCompleteDefeat{return "队伍全部倒地，可结束本次行程"}
        if !completionGoalMet{return totalEncounterNodes>0 ? "清理地点 \(clearedEncounterNodes)/\(totalEncounterNodes)，之后返回营地结算":"探索地点 \(engine.state.map.revealed.count)/\(engine.state.map.nodes.count)，之后返回营地结算"}
        return canComplete ? "目标达成，可结束行程并结算":"目标达成，请返回营地结算"
    }
    public var canCompleteDefeat:Bool {!isCompleted && !isMoving && !engine.state.players.contains(where: \.isAlive)}
    static func makeCompletion(archive:GameArchive,save:MeadowCampaignSave,outcome:String)->MeadowCampaignCompletion {
        let state=archive.state,nodes=state.map.nodes
        let paid=archive.history.flatMap(\.events).filter{$0.kind=="campaignMovementRefilled"}.reduce(0){sum,event in let value=sum.addingReportingOverflow(max(0,event.amount));return value.overflow ? Int.max:value.partialValue}
        let encounters=nodes.filter{$0.kind == .combat || $0.kind == .boss}
        return MeadowCampaignCompletion(id:UUID().uuidString,gameID:state.gameID,outcome:outcome,completedAt:Date(),players:state.players,exploredNodes:state.map.revealed.count,totalNodes:nodes.count,clearedEncounters:encounters.filter{n in !state.units.values.contains{$0.kind == .monster && $0.isAlive && $0.nodeID==n.id}}.count,totalEncounters:encounters.count,collectedRewards:nodes.filter{$0.kind == .reward && $0.rewardCompleted}.count,totalRewards:nodes.filter{$0.kind == .reward}.count,distance:save.movement?.totalDistance ?? 0,movementCoins:paid,historyCount:archive.history.count)
    }
    @discardableResult public func completeCampaign(camera:MeadowCampaignCamera?=nil)throws->MeadowCampaignCompletion {
        if let completion{return completion}
        guard canComplete || canCompleteDefeat else{throw GameError(completionProgress)}
        let before=writer.snapshot
        if canCompleteDefeat,engine.state.battle != nil {
            writer.closingAsDefeat=true;defer{writer.closingAsDefeat=false}
            if let camera{writer.snapshot.camera=camera}
            do{try engine.apply(.finishBattle(winner:"monsters",byScore:false));return writer.snapshot.completion!}
            catch{writer.snapshot=before;throw error}
        }
        var next=snapshot
        next.completion=Self.makeCompletion(archive:engine.archive,save:next,outcome:canCompleteDefeat ? "defeat":"victory")
        if let camera{next.camera=camera};try writer.write(next);return next.completion!
    }
    private func requireOpenCampaign()throws {guard !isCompleted else{throw GameError("本行程已结算，请查看结果或返回设置开始新行程。")}}
    public var cleared:Bool {!engine.state.units.values.contains{$0.kind == .monster && $0.isAlive}}
    public static func catalog()throws->GameCatalog {
        var c=try GameCatalog.initial()
        // Explicit local skins. All source monster stats/AI/drops and original
        // six definitions remain unchanged; only ID/name match the existing art.
        var stag=try c.monster("wolf");stag.id="meadowStag";stag.name="林地鹿灵"
        var elder=try c.monster("caveTroll");elder.id="meadowElderStag";elder.name="古树鹿王"
        c.monsters += [stag,elder];try c.validate();return c
    }
    public static func new(layout:GeneratedMeadowMap,appearanceID:String="forester",playerClassID:String="spellblade",companionClassID:String="ranger",loadouts:[String:GameUnit]?=nil,persist:((Data)throws->Void)?=nil)throws->MeadowCampaignSession {
        let catalog=try self.catalog(),start=layout.map.nodes.first{$0.kind == .start}!.id
        try MeadowPartyConfiguration(playerClassID:playerClassID,companionClassID:companionClassID).validate(catalog:catalog)
        var units=[String:GameUnit]()
        for (id,classID) in [("p1",playerClassID),("p2",companionClassID)] {
            var u=try GameFactory.player(id:id,name:id.uppercased()+" · "+catalog.playerClass(classID).name,classID:classID,teamID:"party",nodeID:start,catalog:catalog)
            u.inventory=["smallPotion":2,"largePotion":1,"shieldPotion":1,"revivalStone":1]
            if let source=loadouts?[id] {u.equipment=source.equipment;u.inventory=source.inventory}
            u.health=try GameRules.attributes(u,catalog:catalog).maximumHealth;try GameRules.refill(&u,catalog:catalog);units[id]=u
        }
        for encounter in MeadowEncounterPlanner.plan(layout) {
            for (index,template) in encounter.templates.enumerated() {
                let id="m-\(encounter.nodeID)-\(index+1)"
                units[id]=try GameFactory.monster(id:id,templateID:template,nodeID:encounter.nodeID,catalog:catalog)
            }
        }
        let provisions=try MeadowProvisioning.plan(layout:layout,players:units.values.filter{$0.kind == .player},catalog:catalog)
        for (id,coins) in provisions.startingCoins{units[id]?.coins=coins}
        var map=layout.map
        for i in map.nodes.indices {if let reward=provisions.rewards[map.nodes[i].id]{map.nodes[i].reward=reward}}
        var state=GameState(units:units,teams:[GameTeam(id:"party",name:"林间小队")],map:map,random:RandomState(seed:layout.configuration.seed ^ 0x43414d504149474e))
        state.pauseReasons=[]
        let save=MeadowCampaignSave(layout:layout,archive:GameArchive(catalog:catalog,state:state,history:[]),appearanceID:appearanceID)
        let session=try MeadowCampaignSession(save:save,persist:persist);try session.checkpoint();return session
    }
    public init(save:MeadowCampaignSave,persist:((Data)throws->Void)?=nil)throws {
        var restored=save
        if let movement=restored.movement,(movement.scale ?? 150) != MeadowMovementRules.distancePerMaximumAP {
            restored.movement?.remaining=movement.remaining*MeadowMovementRules.distancePerMaximumAP/(movement.scale ?? 150)
            restored.movement?.scale=MeadowMovementRules.distancePerMaximumAP
        }
        try restored.validate();restored.travel?.paused=true
        if restored.movement==nil{restored.movement=MeadowCampaignMovement(remaining:MeadowMovementRules.capacity(restored.archive))}
        restored.archive.state.pauseReasons.remove(.background)
        let writer=CampaignWriter(restored,persist:persist);self.writer=writer
        engine=try GameEngine(catalog:restored.archive.catalog,state:restored.archive.state,history:restored.archive.history,persist:{archive in
            if writer.snapshot.completion != nil {
                let old=writer.snapshot.archive
                guard archive.state.units==old.state.units,archive.state.map==old.state.map,archive.history==old.history,archive.state.battle==nil,archive.state.phase == .exploration else{throw GameError("已结算行程只供查看。")}
            }
            var next=writer.snapshot;next.archive=archive
            if next.completion==nil,let remaining=next.movement?.remaining{next.movement?.remaining=min(remaining,MeadowMovementRules.capacity(archive))}
            if writer.closingAsDefeat{next.travel=nil;next.completion=MeadowCampaignSession.makeCompletion(archive:archive,save:next,outcome:"defeat")}
            try writer.write(next)
        })
    }
    public func point(at nodeID:Int)->MeadowWorldPoint {let n=writer.snapshot.layout.map.nodes.first{$0.id==nodeID}!;return .init(n.x*1280,n.y*writer.snapshot.layout.coordinateHeight)}
    public func position(of id:String)->MeadowWorldPoint {
        guard let u=engine.state.units[id] else{return writer.snapshot.layout.spawn}
        guard let t=travel,t.actors.contains(id),let p=MeadowCampaignSave.road(writer.snapshot.layout,from:t.path[t.leg],to:t.path[t.leg+1]) else{return point(at:u.nodeID)}
        var d=t.distance
        for (a,b) in zip(p,p.dropFirst()) {let l=hypot(b.x-a.x,b.y-a.y);if d<=l,l>0{return .init(a.x+(b.x-a.x)*d/l,a.y+(b.y-a.y)*d/l)};d-=l}
        return p.last!
    }
    public var heading:MeadowWorldPoint {
        guard let t=travel,let p=MeadowCampaignSave.road(writer.snapshot.layout,from:t.path[t.leg],to:t.path[t.leg+1]) else{return .init(0,0)}
        var d=t.distance
        for (a,b) in zip(p,p.dropFirst()) {let l=hypot(b.x-a.x,b.y-a.y);if d<=l{return .init(b.x-a.x,b.y-a.y)};d-=l}
        return .init(0,0)
    }
    public var movementCapacity:Double {MeadowMovementRules.capacity(engine.archive)}
    public var movementRemaining:Double {min(writer.snapshot.movement?.remaining ?? movementCapacity,movementCapacity)}
    public var movementRefillCost:Int {Int(ceil(max(0,movementCapacity-movementRemaining)/MeadowMovementRules.distancePerCoin))}
    public var partyCoins:Int {engine.state.players.reduce(0){$0+$1.coins}}
    public var movementPurchaseCoins:Int {min(movementRefillCost,partyCoins)}
    public var movementPurchaseDistance:Double {min(max(0,movementCapacity-movementRemaining),Double(movementPurchaseCoins)*MeadowMovementRules.distancePerCoin)}
    public func routeDistance(_ path:[Int])->Double {
        guard path.count>1 else{return 0}
        return zip(path,path.dropFirst()).reduce(0){sum,edge in sum+(MeadowCampaignSave.road(writer.snapshot.layout,from:edge.0,to:edge.1).map(MeadowCampaignSave.length) ?? 0)}
    }
    public var selectedPlayerID:String {writer.snapshot.selectedPlayerID ?? "p1"}
    public func selectPlayer(_ id:String)throws {
        guard playerIDs.contains(id) else{throw GameError("成员不存在。")}
        var next=snapshot;next.selectedPlayerID=id;try writer.write(next)
    }
    func plannedTravel(node:Int?,point:MeadowWorldPoint?,actor:String,requireMovement:Bool=true)throws->(MeadowCampaignTravel,Double) {
        try requireOpenCampaign()
        guard engine.state.battle==nil,engine.state.phase == .exploration,let unit=engine.state.units[actor],unit.isAlive else{throw GameError("请先结束战斗并选择存活成员。")}
        guard !requireMovement || movementRemaining>0.000001 else{throw GameError("移动条已耗尽，请先补充移动。")}
        let actors=travel?.actors ?? engine.state.players.filter{$0.isAlive && $0.nodeID==unit.nodeID}.map(\.id)
        guard actors.contains(actor) else{throw GameError("请选择当前同行成员。")}
        var goals=[(Int,Int?,Double)]()
        if let node {goals=[(node,nil,0)]}
        else if let point {
            var best:(Int,Int,Double,Double)?,error=Double.infinity
            for road in snapshot.layout.roads {
                var distance=0.0
                for (a,b) in zip(road.points,road.points.dropFirst()) {
                    let dx=b.x-a.x,dy=b.y-a.y,length=hypot(dx,dy),square=dx*dx+dy*dy
                    let u=square>0 ? max(0,min(1,((point.x-a.x)*dx+(point.y-a.y)*dy)/square)):0
                    let e=hypot(point.x-a.x-u*dx,point.y-a.y-u*dy)
                    if e<error {error=e;best=(road.from,road.to,distance+u*length,MeadowCampaignSave.length(road.points))}
                    distance+=length
                }
            }
            guard let hit=best,error<=48 else{throw GameError("请点击道路或建筑。")}
            if hit.2<0.000001{goals=[(hit.0,nil,0)]}
            else if hit.3-hit.2<0.000001{goals=[(hit.1,nil,0)]}
            else{goals=[(hit.0,hit.1,hit.2),(hit.1,hit.0,hit.3-hit.2)]}
        }
        var starts=[([Int],Double,Double)]()
        if let t=travel {
            let a=t.path[t.leg],b=t.path[t.leg+1],length=routeDistance([a,b])
            starts=[([a,b],t.distance,length-t.distance),([b,a],length-t.distance,t.distance)]
            // Direct retargeting on the same edge never visits an endpoint.
            for (a,b,d) in goals where b != nil {
                if Set([a,b!])==Set([t.path[t.leg],t.path[t.leg+1]]) {
                    let current=a==t.path[t.leg] ? t.distance:length-t.distance
                    if d>=current {
                        var direct=MeadowCampaignTravel(id:UUID().uuidString,actors:actors,path:[a,b!]);direct.distance=current;direct.stopDistance=d
                        return (direct,d-current)
                    }else{
                        var direct=MeadowCampaignTravel(id:UUID().uuidString,actors:actors,path:[b!,a]);direct.distance=length-current;direct.stopDistance=length-d
                        return (direct,current-d)
                    }
                }
            }
        }else{starts=[([unit.nodeID],0,0)]}
        var chosen:(MeadowCampaignTravel,Double)?
        for (prefix,initial,firstCost) in starts {
            for (end,other,lastCost) in goals {
                guard let route=engine.state.map.shortestPath(from:prefix.last!,to:end) else{continue}
                var path=prefix+route.dropFirst()
                if let other{path.append(other)}
                guard path.count>=2 else{continue}
                let cost=firstCost+routeDistance(route)+lastCost
                if chosen==nil || cost<chosen!.1 {
                    var t=MeadowCampaignTravel(id:UUID().uuidString,actors:actors,path:path);t.distance=initial;t.stopDistance=other==nil ? nil:lastCost
                    chosen=(t,cost)
                }
            }
        }
        guard let chosen else{throw GameError("已在此处，请选择新的目的地。")};return chosen
    }
    public func preview(to node:Int,actor:String="p1")->ActionPreview {
        do{let(t,cost)=try plannedTravel(node:node,point:nil,actor:actor);return .init(allowed:true,cost:Int(ceil(cost)),message:"路程约\(Int(ceil(cost))) · 移动剩余\(Int(movementRemaining))",path:t.path)}
        catch{return .init(allowed:false,message:error.localizedDescription)}
    }
    @discardableResult public func beginTravel(to node:Int,actor:String="p1")throws->ActionPreview {
        let(t,cost)=try plannedTravel(node:node,point:nil,actor:actor);var next=snapshot;next.travel=t;try writer.write(next)
        return .init(allowed:true,cost:Int(ceil(cost)),message:"前往地点，路程约\(Int(ceil(cost)))",path:t.path)
    }
    @discardableResult public func beginTravel(toRoadPoint point:MeadowWorldPoint,actor:String="p1")throws->ActionPreview {
        let(t,cost)=try plannedTravel(node:nil,point:point,actor:actor);var next=snapshot;next.travel=t;try writer.write(next)
        return .init(allowed:true,cost:Int(ceil(cost)),message:"前往道路选点，路程约\(Int(ceil(cost)))",path:t.path)
    }
    /// Advances the saved road cursor and debits the same world-space distance.
    /// Only arrivals and exhaustion checkpoint to disk; partial frames remain in
    /// the live snapshot and are checkpointed on background/save.
    @discardableResult public func advanceTravel(distance:Double)throws->[OperationReceipt] {
        guard distance.isFinite,distance>=0 else{throw GameError("移动距离无效。")}
        var remainder=distance,receipts=[OperationReceipt]()
        while remainder>0,let t=travel,!t.paused {
            guard let p=MeadowCampaignSave.road(writer.snapshot.layout,from:t.path[t.leg],to:t.path[t.leg+1]) else{throw GameError("道路不存在。")}
            let before=writer.snapshot,last=t.leg==t.path.count-2
            let endpoint=last ? (t.stopDistance ?? MeadowCampaignSave.length(p)):MeadowCampaignSave.length(p)
            let needed=max(0,endpoint-t.distance)
            let available=movementRemaining
            let step=min(remainder,needed,available),remainingAfterStep=max(0,available-min(remainder,needed,available))
            writer.snapshot.movement?.remaining=remainingAfterStep
            writer.snapshot.movement?.totalDistance+=step
            remainder=max(0,remainder-step)
            do {
                if step+0.00000001>=needed && last && t.stopDistance != nil {
                    writer.snapshot.travel?.distance=endpoint;writer.snapshot.travel?.paused=true;try writer.write(snapshot);break
                }else if step+0.00000001>=needed {
                    let nextLeg=t.leg+1
                    if nextLeg==t.path.count-1 {writer.snapshot.travel=nil}
                    else {writer.snapshot.travel?.leg=nextLeg;writer.snapshot.travel?.distance=0}
                    if movementRemaining<=0.000001,writer.snapshot.travel != nil{writer.snapshot.travel?.paused=true}
                    let receipt=try engine.apply(.campaignMove(actors:t.actors,node:t.path[nextLeg]),id:t.id+"/"+String(nextLeg));receipts.append(receipt)
                }else{
                    writer.snapshot.travel?.distance+=step
                    if movementRemaining<=0.000001{writer.snapshot.travel?.paused=true;try writer.write(snapshot)}
                }
                if movementRemaining<=0.000001{break}
            }catch{writer.snapshot=before;writer.snapshot.travel?.paused=true;throw error}
            if step<=0.00000001{break}
        }
        return receipts
    }
    public func setPaused(_ paused:Bool)throws {
        if !paused,let t=travel,t.leg==t.path.count-2,let stop=t.stopDistance,t.distance>=stop-0.000001{throw GameError("已到达道路选点，请点击新的目的地。")}
        if !paused,travel != nil,movementRemaining<=0.000001{throw GameError("移动条已耗尽，请补充移动。")}
        var next=snapshot;next.travel?.paused=paused;try writer.write(next)
    }
    @discardableResult public func refillMovement(usingCoins:Bool)throws->OperationReceipt? {
        try requireOpenCampaign()
        guard engine.state.phase == .exploration,engine.state.battle==nil,!isMoving else{throw GameError("请先暂停移动并结束战斗。")}
        guard movementRemaining+0.000001<movementCapacity else{return nil}
        let before=writer.snapshot,cost=usingCoins ? movementPurchaseCoins:0
        guard !usingCoins || cost>0 else{throw GameError("金币不足，请领取补给、击败怪物或手动补充移动。")}
        let newRemaining=usingCoins ? movementRemaining+movementPurchaseDistance:movementCapacity
        writer.snapshot.movement?.remaining=newRemaining
        if usingCoins{writer.snapshot.movement?.purchasedRefills+=1}else{writer.snapshot.movement?.manualRefills+=1}
        do{return try engine.apply(.refillCampaignMovement(actors:playerIDs,coins:cost,manual:!usingCoins))}
        catch{writer.snapshot=before;throw error}
    }
    @discardableResult public func interactCurrentNode(actor:String="p1")throws->OperationReceipt {
        try requireOpenCampaign()
        guard travel==nil,engine.state.battle==nil,let unit=engine.state.units[actor],unit.isAlive else{throw GameError("请先抵达地点并结束战斗。")}
        let actors=engine.state.players.filter{$0.isAlive && $0.nodeID==unit.nodeID}.map(\.id)
        return try engine.apply(.interactCampaignNode(actors:actors))
    }
    public func pauseAfterFailure(){writer.snapshot.travel?.paused=true}
    public func checkpoint(camera:MeadowCampaignCamera?=nil,pauseTravel:Bool=false)throws {var next=snapshot;if let camera{next.camera=camera};if pauseTravel{next.travel?.paused=true};try writer.write(next)}
    public func suspendAndCheckpoint(camera:MeadowCampaignCamera)throws {
        do{try checkpoint(camera:camera,pauseTravel:true)}catch{pauseAfterFailure();throw error}
    }
    public func refillExploration()throws {_ = try refillMovement(usingCoins:false)}
    @discardableResult public func configureEncounter(node:Int,templates:[String])throws->OperationReceipt {
        try requireOpenCampaign()
        guard travel==nil,engine.state.battle==nil else{throw GameError("请先停下移动并结束当前战斗，再编辑地点。")}
        return try engine.apply(.configureNodeEncounter(node:node,monsterTemplates:templates))
    }
    @discardableResult public func configureReward(node:Int,reward:NodeReward)throws->OperationReceipt {
        try requireOpenCampaign()
        guard travel==nil,engine.state.battle==nil else{throw GameError("请先停下移动并结束当前战斗，再编辑地点。")}
        return try engine.apply(.configureNodeReward(node:node,reward:reward))
    }
    @discardableResult public func resetReward(node:Int)throws->OperationReceipt {
        try requireOpenCampaign()
        guard travel==nil,engine.state.battle==nil else{throw GameError("请先停下移动并结束当前战斗，再编辑地点。")}
        return try engine.apply(.resetNodeReward(node:node))
    }
    public var canManageInventory:Bool {!isCompleted && travel==nil && engine.state.battle==nil && engine.state.phase == .exploration}
    private func requireInventoryAccess()throws {
        guard canManageInventory else{throw GameError("请先完成移动并结束战斗，再管理行囊。")}
    }
    public var inventoryActionRefillNeeded:Bool {
        canManageInventory && engine.state.players.contains{unit in
            unit.isAlive && unit.ap < ((try? GameRules.attributes(unit,catalog:engine.catalog).baseAP) ?? 0)
        }
    }
    /// Restore the original manual exploration-AP operation, separately from
    /// the map's movement refill. Never resets HP, skill uses or inventories.
    @discardableResult public func refillInventoryActions()throws->OperationReceipt? {
        try requireInventoryAccess()
        guard inventoryActionRefillNeeded else{return nil}
        return try engine.apply(.refillExploration)
    }
    public func candidateEquipment(actor:String,slot:ItemSlot,item:String?)throws->GameUnit {
        try requireInventoryAccess()
        guard let unit=engine.state.units[actor],unit.kind == .player else{throw GameError("请选择队伍成员。")}
        if unit.equipment[slot]==item{return unit}
        let clone=try GameEngine(catalog:engine.catalog,state:engine.state)
        try clone.apply(.equip(unit:actor,slot:slot,item:item))
        return clone.state.units[actor]!
    }
    @discardableResult public func equipInventory(actor:String,slot:ItemSlot,item:String?)throws->OperationReceipt? {
        _=try candidateEquipment(actor:actor,slot:slot,item:item)
        guard engine.state.units[actor]?.equipment[slot] != item else{return nil}
        return try engine.apply(.equip(unit:actor,slot:slot,item:item))
    }
    public func inventoryItemCommand(actor:String,item:String,target:String)throws->GameCommand {
        try requireInventoryAccess()
        let definition=try engine.catalog.item(item)
        guard definition.slot==nil else{throw GameError("装备请使用装备操作。")}
        guard let recipient=engine.state.units[target],recipient.kind == .player else{throw GameError("请选择队伍成员。")}
        if definition.kind != .revivalStone {
            let stats=try GameRules.attributes(recipient,catalog:engine.catalog)
            guard (definition.heal>0 && recipient.health<stats.maximumHealth) || definition.shield>recipient.shield else{throw GameError("目标无需恢复，或已有相同及更强护盾。")}
        }
        return definition.kind == .revivalStone ? .rescue(actor:actor,target:target):.useItem(actor:actor,item:item,target:target)
    }
    @discardableResult public func useInventory(actor:String,item:String,target:String)throws->OperationReceipt {
        try engine.apply(inventoryItemCommand(actor:actor,item:item,target:target))
    }

}
