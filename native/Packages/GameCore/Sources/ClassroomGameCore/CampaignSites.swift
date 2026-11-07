import Foundation

/// Fixed by map seed and node ID; independent of the battle RNG cursor.
public enum CampaignSiteKind:String,Codable {case shop,satchel,spring}
public struct CampaignSiteConfiguration:Codable,Equatable {
    public var kind:CampaignSiteKind
    public var buyPercent:Int,sellPercent:Int,gold:Int,healing:Int
    public init(kind:CampaignSiteKind,buyPercent:Int=100,sellPercent:Int=100,gold:Int=5,healing:Int=4){self.kind=kind;self.buyPercent=buyPercent;self.sellPercent=sellPercent;self.gold=gold;self.healing=healing}
    public func validate()throws {
        guard (10...500).contains(buyPercent),(10...500).contains(sellPercent),(1...1000).contains(gold),(1...100).contains(healing) else{throw GameError("买卖比例范围10—500%，金币1—1000，恢复1—100。")}
    }
}
public enum CampaignSiteRules {
    public static func kind(node:MapNode,seed:UInt64)->CampaignSiteKind? {
        if let config=node.siteConfiguration{return config.kind}
        if node.kind == .start{return .shop}
        guard node.kind == .empty else{return nil}
        var value=seed ^ (UInt64(truncatingIfNeeded:node.id) &* 0x9e3779b97f4a7c15) ^ 0x534954455331
        value=(value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value=(value ^ (value >> 27)) &* 0x94d049bb133111eb
        return [.shop,.satchel,.spring][Int((value ^ (value >> 31)) % 3)]
    }
    public static func configuration(node:MapNode,seed:UInt64)->CampaignSiteConfiguration? {
        node.siteConfiguration ?? kind(node:node,seed:seed).map{CampaignSiteConfiguration(kind:$0)}
    }
    public static func validatePrices(node:MapNode,seed:UInt64,catalog:GameCatalog)throws {
        guard configuration(node:node,seed:seed)?.kind == .shop else{return}
        for item in catalog.items where item.purchasePrice != nil && item.setID==nil {
            guard try price(item:item,buy:false,node:node,seed:seed)<=price(item:item,buy:true,node:node,seed:seed) else{throw GameError("卖出价格不能高于买入价格，请调整比例。")}
        }
    }
    public static func price(item:ItemDefinition,buy:Bool,node:MapNode,seed:UInt64)throws->Int {
        guard let config=configuration(node:node,seed:seed),config.kind == .shop else{throw GameError("此地点没有商店。")}
        try config.validate()
        guard let base=buy ? item.purchasePrice:item.sellPrice else{throw GameError("此商品不出售。")}
        let percent=buy ? config.buyPercent:config.sellPercent
        let product=base.multipliedReportingOverflow(by:percent)
        guard base>=0,!product.overflow else{throw GameError("商品价格超出范围。")}
        return base==0 ? 0:max(1,product.partialValue/100)
    }

}
extension Evaluation {
    mutating func configureCampaignSite(node id:Int,configuration:CampaignSiteConfiguration)throws {
        guard state.phase == .exploration,state.battle==nil,let index=state.map.nodes.firstIndex(where:{$0.id==id}),[NodeKind.start,.empty].contains(state.map.nodes[index].kind),state.map.nodes[index].siteResolved != true else{throw GameError("只能编辑未处理的营地或空地点，不能重置已结束事件。")}
        try configuration.validate()
        guard state.map.nodes[index].kind != .start || configuration.kind == .shop else{throw GameError("营地必须保留商店。")}
        var candidate=state.map.nodes[index];candidate.siteConfiguration=configuration
        try CampaignSiteRules.validatePrices(node:candidate,seed:state.map.seed,catalog:catalog)
        state.map.nodes[index]=candidate
        events.append(GameEvent("campaignSiteConfigured",detail:String(id)))
    }
    func siteActor(_ id:String)throws->(GameUnit,Int,CampaignSiteKind) {
        let actor=try acting(id)
        guard state.phase == .exploration,state.battle==nil,actor.kind == .player,
              let index=state.map.nodes.firstIndex(where:{$0.id==actor.nodeID}),
              let kind=CampaignSiteRules.kind(node:state.map.nodes[index],seed:state.map.seed) else{throw GameError("当前地点没有商店或事件。")}
        return(actor,index,kind)
    }
    mutating func tradeCampaignSite(actor id:String,item itemID:String,buy:Bool)throws {
        var (actor,index,kind)=try siteActor(id)
        guard kind == .shop else{throw GameError("请到商店交易。")}
        let item=try catalog.item(itemID),price:Int
        if buy {
            guard let purchase=item.purchasePrice,purchase>0,item.setID==nil else{throw GameError("此物品不出售。")}
            price=try CampaignSiteRules.price(item:item,buy:true,node:state.map.nodes[index],seed:state.map.seed);guard actor.coins>=price else{throw GameError("购买者个人金币不足。")}
            actor.inventory[itemID]=try checkedAdd(actor.inventory[itemID] ?? 0,1);actor.coins-=price
        }else {
            price=try CampaignSiteRules.price(item:item,buy:false,node:state.map.nodes[index],seed:state.map.seed)
            guard price>0,let count=actor.inventory[itemID],count>0 else{throw GameError("只能出售个人行囊内的物品，请先卸下已装备物品。")}
            actor.coins=try checkedAdd(actor.coins,price)
            if count==1{actor.inventory.removeValue(forKey:itemID)}else{actor.inventory[itemID]=count-1}
        }
        state.units[id]=actor
        events.append(GameEvent("campaignTrade",actor:id,amount:buy ? -price:price,detail:(buy ? "buy:":"sell:")+itemID))
    }
    mutating func resolveCampaignSite(actor id:String,accept:Bool)throws {
        var (actor,index,kind)=try siteActor(id)
        guard kind != .shop,state.map.nodes[index].siteResolved != true else{throw GameError("该事件已结束。")}
        let config=CampaignSiteRules.configuration(node:state.map.nodes[index],seed:state.map.seed)!
        var amount=0
        if accept {
            if kind == .satchel {amount=config.gold;actor.coins=try checkedAdd(actor.coins,amount)}
            else {
                let maximum=try GameRules.attributes(actor,catalog:catalog).maximumHealth
                amount=min(config.healing,max(0,maximum-actor.health))
                guard amount>0 else{throw GameError("当前成员生命已满，可换成员或离开此事件。")}
                actor.health+=amount
            }
        }
        state.units[id]=actor;state.map.nodes[index].siteResolved=true
        events.append(GameEvent("campaignSiteEvent",actor:id,amount:amount,detail:"\(actor.nodeID):\(kind.rawValue):\(accept ? "accept":"leave")"))
    }
}
