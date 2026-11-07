import Foundation
import ClassroomGameCore

public extension MeadowCampaignSession {
    static func siteSummary(layout:GeneratedMeadowMap)->String {
        let names:[CampaignSiteKind:String]=[.shop:"行商",.satchel:"失物",.spring:"清泉"]
        let rows=layout.map.nodes.filter{$0.kind == .empty}.map{node in "#\(node.id) \(names[CampaignSiteRules.kind(node:node,seed:layout.map.seed)!]!)"}
        return "营地可交易；空地点服务由地图种子固定（不新增节点）："+(rows.isEmpty ? "无空地点，无额外事件。":rows.joined(separator:"、"))
    }
    @discardableResult func configureSite(node:Int,configuration:CampaignSiteConfiguration)throws->OperationReceipt {
        guard canManageInventory else{throw GameError("请先完成移动并结束战斗，再编辑地点。")};return try engine.apply(.configureCampaignSite(node:node,configuration:configuration))
    }
    func siteKind(node:Int)->CampaignSiteKind? {
        guard let n=engine.state.map.nodes.first(where:{$0.id==node}) else{return nil}
        return CampaignSiteRules.kind(node:n,seed:engine.state.map.seed)
    }
    func siteAvailable(actor:String)->Bool {
        guard canManageInventory,let u=engine.state.units[actor],u.isAlive,
              let node=engine.state.map.nodes.first(where:{$0.id==u.nodeID}),let kind=siteKind(node:node.id) else{return false}
        return kind == .shop || node.siteResolved != true
    }
    @discardableResult func tradeAtSite(actor:String,item:String,buy:Bool,id:String=UUID().uuidString)throws->OperationReceipt {
        guard canManageInventory else{throw GameError("请抵达地点、结束战斗后交易。")}
        return try engine.apply(.tradeCampaignSite(actor:actor,item:item,buy:buy),id:id)
    }
    @discardableResult func resolveSite(actor:String,accept:Bool,id:String=UUID().uuidString)throws->OperationReceipt {
        guard canManageInventory else{throw GameError("请抵达地点、结束战斗后处理事件。")}
        return try engine.apply(.resolveCampaignSite(actor:actor,accept:accept),id:id)
    }
}
