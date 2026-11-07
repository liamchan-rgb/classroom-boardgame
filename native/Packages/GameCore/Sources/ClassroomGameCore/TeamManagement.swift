import Foundation

public enum TeamResourceOwner:Codable,Equatable,Hashable {case player(String),warehouse(String)}
extension Evaluation {
    mutating func configureTeams(names:[String:String],members:[String:String])throws {
        guard !names.isEmpty,names.count<=64,names.allSatisfy({!$0.key.isEmpty && !$0.value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}),members.keys.allSatisfy({state.units[$0]?.kind == .player}) else{throw GameError("队伍名称或成员无效。")}
        for id in names.keys.sorted() {
            if let i=state.teams.firstIndex(where:{$0.id==id}){state.teams[i].name=names[id]!}
            else{state.teams.append(GameTeam(id:id,name:names[id]!))}
        }
        for (id,team) in members {
            guard state.teams.contains(where:{$0.id==team}) else{throw GameError("目标队伍不存在。")}
            state.units[id]?.teamID=team
        }
        events.append(GameEvent("teamsConfigured",detail:"个人资产与旧队仓库保留"))
    }
    mutating func mergeTeams(source:String,destination:String)throws {
        guard source != destination,let a=state.teams.firstIndex(where:{$0.id==source}),let b=state.teams.firstIndex(where:{$0.id==destination}) else{throw GameError("请选择两个不同队伍。")}
        state.teams[b].coins=try checkedAdd(state.teams[b].coins,state.teams[a].coins)
        for (item,count) in state.teams[a].inventory {state.teams[b].inventory[item]=try checkedAdd(state.teams[b].inventory[item] ?? 0,count)}
        state.teams[a].coins=0;state.teams[a].inventory=[:]
        for id in state.players.filter({$0.teamID==source}).map(\.id){state.units[id]?.teamID=destination}
        events.append(GameEvent("teamsMerged",actor:source,target:destination,detail:"成员与仓库合并，保留空旧队供历史追溯"))
    }
    func ownerTeam(_ owner:TeamResourceOwner)throws->String {
        switch owner {
        case .player(let id):guard let u=state.units[id],u.kind == .player,let team=u.teamID else{throw GameError("成员无效。")};return team
        case .warehouse(let id):guard state.teams.contains(where:{$0.id==id}) else{throw GameError("仓库不存在。")};return id
        }
    }
    mutating func changeResource(_ owner:TeamResourceOwner,coins:Int,item:String?,count:Int)throws {
        switch owner {
        case .player(let id):
            var u=try unit(id);u.coins=try checkedAdd(u.coins,coins)
            if let item {let n=try checkedAdd(u.inventory[item] ?? 0,count);guard n>=0 else{throw GameError("物品不足。")};if n==0{u.inventory.removeValue(forKey:item)}else{u.inventory[item]=n}}
            guard u.coins>=0 else{throw GameError("金币不足。")};state.units[id]=u
        case .warehouse(let id):
            guard let i=state.teams.firstIndex(where:{$0.id==id}) else{throw GameError("仓库不存在。")}
            state.teams[i].coins=try checkedAdd(state.teams[i].coins,coins);guard state.teams[i].coins>=0 else{throw GameError("仓库金币不足。")}
            if let item {let n=try checkedAdd(state.teams[i].inventory[item] ?? 0,count);guard n>=0 else{throw GameError("仓库物品不足。")};if n==0{state.teams[i].inventory.removeValue(forKey:item)}else{state.teams[i].inventory[item]=n}}
        }
    }
    mutating func transferTeamResource(from:TeamResourceOwner,to:TeamResourceOwner,coins:Int,item:String?,count:Int)throws {
        guard state.phase == .exploration,state.battle==nil,from != to,coins>=0,count>=0,(coins>0 || item != nil && count>0),try ownerTeam(from)==ownerTeam(to) else{throw GameError("仅探索允许同队存取或转交；跨队请由教师调整。")}
        if let item {_=try catalog.item(item)}else{guard count==0 else{throw GameError("未选择物品。")}}
        try changeResource(from,coins:-coins,item:item,count:-count);try changeResource(to,coins:coins,item:item,count:count)
        events.append(GameEvent("teamResourceTransferred",amount:coins,detail:item ?? "金币"))
    }
}
