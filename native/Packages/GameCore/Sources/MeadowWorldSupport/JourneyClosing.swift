import Foundation
import ClassroomGameCore

public extension MeadowCampaignSession {
    /// Read-only explanation of the real save, never a settlement or a grant.
    var closingReadout:String {
        if let completion {
            return (completion.outcome=="victory" ? "已通关":"队伍倒地，行程已结束")+" · 已保存最终结果\n结果只读，不会重复发放金币、积分或物品。"
        }
        let supplies=engine.state.map.nodes.filter{$0.kind == .reward && !$0.rewardCompleted}.count
        var rows=[completionProgress,"尚有 \(supplies) 处补给未领取（可选）。"]
        if engine.state.battle != nil && !canCompleteDefeat {rows.append("请先结束当前战斗；已消耗的个人行动与技能次数会随存档恢复。")}
        else if travel != nil {rows.append("道路行进尚未完成；保存退出后从当前位置暂停恢复。")}
        else if completionGoalMet && !canComplete && !canCompleteDefeat,let camp=routeOptions(actor:engine.state.players.first(where: \.isAlive)?.id).first(where:{$0.kind=="camp"}) {
            rows.append("返回营地还需 \(Int(ceil(camp.distance))) 距离 · 至少 \(camp.additionalCoins) 金币。")
            if camp.additionalCoins>partyCoins {rows.append("金币缺口 \(camp.additionalCoins-partyCoins)：可手动补满移动条，或先领取补给。")}
        }
        rows.append("结束后仅记录实际所得，不额外发奖；取消或保存失败保留当前行程，可重试。")
        return rows.joined(separator:"\n")
    }
}
