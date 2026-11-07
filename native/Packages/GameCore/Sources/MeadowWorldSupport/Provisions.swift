import Foundation
import ClassroomGameCore

/// Expedition-only budgets. Original combat stats, item effects and drop rolls
/// stay in the tabletop catalog. Apply exactly once, when creating a new save.
public struct MeadowProvisionPlan:Codable,Equatable {
    public let startingCoins:[String:Int]
    public let rewards:[Int:NodeReward]
    public let treeTourDistance:Double
    public let movementCoinBudget:Int
    public let healingPressure:Int
    public let bossSupplyNodes:[Int:Int]
}
public enum MeadowProvisioning {
    public static let version=2
    public static func plan(layout:GeneratedMeadowMap,players:[GameUnit],catalog:GameCatalog)throws->MeadowProvisionPlan {
        let party=players.sorted{$0.id<$1.id}
        guard !party.isEmpty,let start=layout.map.nodes.first(where:{$0.kind == .start})?.id else{throw GameError("行程需要队伍和起点。")}
        let capacity=try party.map{Double(try GameRules.attributes($0,catalog:catalog).maximumAP)}.reduce(0,+)/Double(party.count)*MeadowMovementRules.distancePerMaximumAP
        guard capacity>0 else{throw GameError("队伍移动上限无效。")}
        func length(_ a:Int,_ b:Int)->Double {MeadowCampaignSave.road(layout,from:a,to:b).map(MeadowCampaignSave.length) ?? 0}
        func route(_ end:Int,from origin:Int?=nil)->Double {
            let path=layout.map.shortestPath(from:origin ?? start,to:end) ?? []
            return zip(path,path.dropFirst()).reduce(0.0){$0+length($1.0,$1.1)}
        }
        var visited:Set<Int>=[start],queue=[start],cursor=0,tour=0.0
        while cursor<queue.count {
            let node=queue[cursor];cursor+=1
            for next in layout.map.neighbors(node) where visited.insert(next).inserted {queue.append(next);tour+=2*length(node,next)}
        }
        let refillPrice=Int(ceil(capacity/MeadowMovementRules.distancePerCoin))
        // A closed walk along a deterministic spanning tree visits every node.
        // Budget whole-bar purchases (including the final partially used bar),
        // plus one reserve. Random drops are deliberately not counted as income.
        let budget=Int(ceil(max(0,tour-capacity)/capacity))*refillPrice+refillPrice
        let caches=layout.map.nodes.filter{$0.kind == .reward}.sorted {
            let a=route($0.id),b=route($1.id);return a==b ? $0.id<$1.id:a<b
        }
        let first=caches.first.map{route($0.id)} ?? tour
        let initial=caches.isEmpty ? budget:min(budget,Int(ceil(max(0,first-capacity)/capacity))*refillPrice+refillPrice)
        var coins=[String:Int]()
        for (i,p) in party.enumerated(){coins[p.id]=initial/party.count+(i<initial%party.count ? 1:0)}
        let encounters=MeadowEncounterPlanner.plan(layout)
        let totalHP=try encounters.flatMap(\.templates).map{try catalog.monster($0).attributes.maximumHealth}.reduce(0,+)
        let pressure=max(1,min(3,Int(ceil(Double(totalHP)/Double(max(1,caches.count)*party.count*48)))))
        // NodeReward is paid to EACH living recipient by the existing engine.
        // Divide the party budget before distributing it, to avoid doubling it.
        let perMember=caches.isEmpty ? 0:Int(ceil(Double(budget-initial)/Double(party.count)))
        let bosses=encounters.filter{$0.band=="boss"}
        var bossSupplies=[Int:Int]()
        for boss in bosses {
            // Prefer a cache reachable earlier from camp, then the cheapest
            // actual movement route from that cache to this boss. No fake cache
            // is inserted when the user configured zero reward nodes.
            let earlier=caches.filter{route($0.id)<=route(boss.nodeID)+0.000001}
            let choices=earlier.isEmpty ? caches:earlier
            if let supply=choices.min(by:{
                let a=route(boss.nodeID,from:$0.id),b=route(boss.nodeID,from:$1.id)
                return a==b ? $0.id<$1.id:a<b
            }) {bossSupplies[boss.nodeID]=supply.id}
        }
        let preparation=Set(bossSupplies.values)
        var large=Set(caches.enumerated().filter{!($0.offset*2<caches.count && pressure==1)}.map{$0.element.id})
        // Move an existing large-potion allocation to the preparation cache
        // before adding any. A lone small cache is upgraded, not left with only
        // six HP of healing before its boss. Potion quantities remain 1...3.
        for id in preparation.sorted() where !large.contains(id) {
            if let donor=caches.reversed().first(where:{large.contains($0.id) && !preparation.contains($0.id)}) {large.remove(donor.id)}
            large.insert(id)
        }
        let shieldCaches:Set<Int>
        if bosses.count==1 {shieldCaches=Set(caches.first.map{[$0.id]} ?? [])}
        else{shieldCaches=preparation}
        var rewards=[Int:NodeReward]()
        for (i,node) in caches.enumerated() {
            var items=[String:Int]()
            if !encounters.isEmpty {
                items[large.contains(node.id) ? "largePotion":"smallPotion"]=pressure
                if shieldCaches.contains(node.id){items["shieldPotion"]=1}
                let revivals=bossSupplies.values.filter{$0==node.id}.count
                if revivals>0{items["revivalStone"]=revivals}
            }
            let amount=perMember/caches.count+(i<perMember%caches.count ? 1:0)
            rewards[node.id]=NodeReward(coins:amount,score:2,items:items)
        }
        return .init(startingCoins:coins,rewards:rewards,treeTourDistance:tour,movementCoinBudget:budget,healingPressure:pressure,bossSupplyNodes:bossSupplies)
    }
}
