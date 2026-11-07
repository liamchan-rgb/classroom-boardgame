import Foundation
import ClassroomGameCore

/// Read-only guidance over the saved cursor and actual saved node contents.
/// Never replans rewards, selects an event, spends coins or advances RNG.
public struct MeadowRouteReadout:Codable,Equatable {
    public let destination:String
    public let remainingDistance:Double
    public let additionalCoins:Int
    public let coinsMissing:Int
    public let paused:Bool
    public let points:[MeadowWorldPoint]
    public var arrived:Bool {remainingDistance<=0.000001}
    public var title:String {arrived ? "已抵达道路选点":(paused ? "路线暂停 · ":"前往 · ")+destination}
    public var detail:String {
        if arrived{return "点击新的道路目的地，或选择附近建筑。"}
        let distance="剩余路程 \(Int(ceil(remainingDistance)))"
        if additionalCoins==0{return distance+" · 当前移动足够"}
        if coinsMissing>0{return distance+" · 途中需补\(additionalCoins)金币，尚差\(coinsMissing)"}
        return distance+" · 途中需补移动，至少\(additionalCoins)金币"
    }
}
public struct MeadowRouteOption:Codable,Equatable {
    public let kind:String,nodeID:Int,name:String,distance:Double,additionalCoins:Int
    public var title:String {name+" · \(Int(ceil(distance)))距离"+(additionalCoins>0 ? " · 至少\(additionalCoins)金币补移动":"")}
}
extension MeadowMovementRules {
    /// Minimum coins to finish through the real capped refill operation. A
    /// fractional party mean can yield a 375-distance bar: buying it twice costs
    /// 8 + 8 coins, not ceil(750 / 50). The final purchase may be partial.
    static func minimumRouteCoins(distance:Double,available:Double,capacity:Double)->Int {
        let deficit=max(0,distance-available-0.000001)
        guard deficit>0,capacity>0 else{return 0}
        let full=max(0,Int(floor((deficit-0.000001)/capacity)))
        return full*Int(ceil(capacity/distancePerCoin))+Int(ceil(max(0,deficit-Double(full)*capacity)/distancePerCoin))
    }
}
public extension MeadowCampaignSession {
    var routeReadout:MeadowRouteReadout? {
        guard !isCompleted,engine.state.battle==nil,let t=travel,let last=t.path.last else{return nil}
        var points=[MeadowWorldPoint](),remaining=0.0
        func at(_ p:[MeadowWorldPoint],_ distance:Double)->MeadowWorldPoint {
            var d=max(0,distance)
            for (a,b) in zip(p,p.dropFirst()) {
                let length=hypot(b.x-a.x,b.y-a.y)
                if length>0 && d<=length{return .init(a.x+(b.x-a.x)*d/length,a.y+(b.y-a.y)*d/length)}
                d-=length
            }
            return p.last!
        }
        for leg in t.leg..<(t.path.count-1) {
            guard let road=MeadowCampaignSave.road(snapshot.layout,from:t.path[leg],to:t.path[leg+1]),!road.isEmpty else{return nil}
            let start=leg==t.leg ? t.distance:0,end=leg==t.path.count-2 ? (t.stopDistance ?? MeadowCampaignSave.length(road)):MeadowCampaignSave.length(road)
            remaining+=max(0,end-start)
            if points.isEmpty{points.append(at(road,start))}
            var d=0.0
            for (a,b) in zip(road,road.dropFirst()) {
                d+=hypot(b.x-a.x,b.y-a.y)
                if d>start+0.000001 && d<end-0.000001{points.append(b)}
            }
            let endpoint=at(road,end)
            if points.last != endpoint{points.append(endpoint)}
        }
        let coins=MeadowMovementRules.minimumRouteCoins(distance:remaining,available:movementRemaining,capacity:movementCapacity)
        let destination=t.stopDistance==nil ? (engine.state.map.nodes.first{$0.id==last}.map{routeName($0)} ?? "地点 #\(last)"):"道路选点"
        return .init(destination:destination,remainingDistance:remaining,additionalCoins:coins,coinsMissing:max(0,coins-partyCoins),paused:t.paused,points:points)
    }
    /// Only requested when opening the route menu, not on every render frame.
    /// Uses the same planner as a map tap, including mid-edge reversals.
    func routeOptions(actor:String?=nil)->[MeadowRouteOption] {
        guard !isCompleted,engine.state.battle==nil else{return []}
        var choices=[MeadowRouteOption]()
        for node in engine.state.map.nodes {
            let kind:String
            if node.kind == .start{kind="camp"}
            else if node.kind == .reward && !node.rewardCompleted{kind="supply"}
            else if (node.kind == .combat || node.kind == .boss) && engine.state.units.values.contains(where:{$0.kind == .monster && $0.isAlive && $0.nodeID==node.id}){kind="encounter"}
            else{continue}
            guard let (_,distance)=try? plannedTravel(node:node.id,point:nil,actor:actor ?? selectedPlayerID,requireMovement:false) else{continue}
            let coins=MeadowMovementRules.minimumRouteCoins(distance:distance,available:movementRemaining,capacity:movementCapacity)
            choices.append(.init(kind:kind,nodeID:node.id,name:routeName(node),distance:distance,additionalCoins:coins))
        }
        return ["supply","encounter","camp"].compactMap { kind in
            choices.filter{$0.kind==kind}.min{abs($0.distance-$1.distance)<0.000001 ? $0.nodeID<$1.nodeID:$0.distance<$1.distance}
        }
    }
    var resourceGuidance:String {
        let rows=engine.state.players.map { unit -> String in
            let medicine=["smallPotion","largePotion","shieldPotion","revivalStone"].compactMap { id -> String? in
                guard let name=try? engine.catalog.item(id).name else{return nil}
                return name+"×\(unit.inventory[id] ?? 0)"
            }.joined(separator:" · ")
            return unit.id.uppercased()+(unit.isAlive ? "":"（倒地）")+"："+medicine
        }
        return "移动 \(Int(floor(movementRemaining)))/\(Int(ceil(movementCapacity))) · 全队金币 \(partyCoins)\n"+rows.joined(separator:"\n")
    }
    private func routeName(_ node:MapNode)->String {
        let kind:[NodeKind:String]=[.start:"营地",.reward:"补给",.combat:"战斗",.boss:"首领",.empty:"空地点"]
        return (kind[node.kind] ?? node.name)+" #\(node.id)"
    }
}
