import Foundation
import ClassroomGameCore

public enum MeadowJourneyState:String,CaseIterable {case all,exploring,battle,completed
    public var title:String {switch self{case .all:return "全部状态";case .exploring:return "探索中";case .battle:return "战斗中";case .completed:return "已结算"}}
    public static func of(_ save:MeadowCampaignSave)->Self {save.completion != nil ? .completed:(save.archive.state.battle != nil ? .battle:.exploring)}
}
public enum MeadowArchiveOrder:String,CaseIterable {case newest,oldest,slot
    public var title:String {switch self{case .newest:return "最近保存优先";case .oldest:return "最早保存优先";case .slot:return "按原槽号"}}
}
public struct MeadowJourneyIndex:Identifiable,Equatable {
    public let slot:Int,title:String,savedAt:Date,state:MeadowJourneyState,players:Int
    public let searchText:String
    public var id:Int{slot}
    public init(slot:Int,entry:MeadowSaveSlot<MeadowCampaignSave>){
        self.slot=slot;title=entry.title;savedAt=entry.savedAt;state=MeadowJourneyState.of(entry.value);players=entry.value.archive.state.players.count
        let game=entry.value.archive.state
        searchText=MeadowArchiveSearch.normalize(([entry.title,String(slot),String(entry.value.layout.configuration.seed),game.gameID]+game.players.map(\.name)+game.players.map(\.id)+game.teams.map(\.name)).joined(separator:" "))
    }
}
public struct MeadowJourneyQuery:Equatable {
    public var text=""
    public var state:MeadowJourneyState = .all
    public var players=0
    public var order:MeadowArchiveOrder = .newest
    public init(){}
    public func apply(_ rows:[MeadowJourneyIndex])->[MeadowJourneyIndex] {
        let words=MeadowArchiveSearch.words(text)
        return rows.filter{(state == .all || $0.state==state) && (players==0 || $0.players==players) && MeadowArchiveSearch.matches(words,in:$0.searchText)}.sorted {a,b in
            if order == .slot || a.savedAt==b.savedAt{return a.slot<b.slot}
            return order == .newest ? a.savedAt>b.savedAt:a.savedAt<b.savedAt
        }
    }
}
public enum MeadowHistoryCategory:String,CaseIterable {case all,combat,travel,resources,team,appearance,configuration,other
    public var title:String {switch self{case .all:return "全部类别";case .combat:return "战斗";case .travel:return "移动与地点";case .resources:return "资源与物品";case .team:return "组队与老师";case .appearance:return "人物外观";case .configuration:return "地点配置";case .other:return "其他"}}
    public static func of(_ command:GameCommand)->Self {
        switch command {
        case .startBattle,.attack,.cast,.monsterStep,.endTurn,.joinMonster,.reorderQueue,.finishBattle,.rescue,.retreatAfterDefeat:return .combat
        case .campaignMove,.move,.interactCampaignNode,.resolveCampaignSite,.refillCampaignMovement:return .travel
        case .tradeCampaignSite,.campaignLottery,.editPlayer,.grantPlayerResources,.editResources,.useItem,.reward,.setHealth,.revive,.equip,.refillExploration:return .resources
        case .configureTeams,.mergeTeams,.transferTeamResource,.teacherTransferTeamResource,.addHost,.changeTeam:return .team
        case .applyPlayerProfile:return .appearance
        case .configureCampaignSite,.configureNodeEncounter,.configureNodeReward,.resetNodeReward,.setDifficulty:return .configuration
        }
    }
}
public struct MeadowHistoryIndex:Identifiable,Equatable {
    public let id:String,sequence:Int,category:MeadowHistoryCategory,title:String,participants:Set<String>,searchText:String
    public init(entry:OperationReceipt,catalog:GameCatalog){
        id=entry.id;sequence=entry.sequence;category=MeadowHistoryCategory.of(entry.command)
        title=Self.commandTitle(entry.command,catalog:catalog)
        var ids=Set(entry.events.flatMap{[$0.actor,$0.target].compactMap{$0}})
        let all=Set(entry.before.units.keys).union(entry.after.units.keys)
        ids.formUnion(all.filter{entry.before.units[$0] != entry.after.units[$0]})
        switch entry.command {
        case .attack(let actor,let target),.rescue(let actor,let target):ids.formUnion([actor,target])
        case .cast(let actor,_,let target):ids.insert(actor);if case .unit(let id)=target{ids.insert(id)}
        case .useItem(let actor,_,let target):ids.formUnion([actor,target])
        case .endTurn(let actor,_):ids.insert(actor)
        case .campaignMove(let actors,_),.move(let actors,_),.interactCampaignNode(let actors),.refillCampaignMovement(let actors,_,_),.grantPlayerResources(let actors,_,_),.reward(let actors,_):ids.formUnion(actors)
        case .applyPlayerProfile(let id,_,_),.editPlayer(let id,_),.editResources(let id,_),.equip(let id,_,_),.setHealth(let id,_,_),.revive(let id),.changeTeam(let id,_):ids.insert(id)
        case .startBattle,.finishBattle:ids.formUnion(entry.before.battle?.queue ?? []);ids.formUnion(entry.after.battle?.queue ?? [])
        default:break
        }
        let changedTeams=Set(entry.before.teams.filter{before in entry.after.teams.first{$0.id==before.id} != before}.map(\.id)).union(entry.after.teams.filter{after in entry.before.teams.first{$0.id==after.id} != after}.map(\.id))
        ids.formUnion((entry.before.players+entry.after.players).filter{$0.teamID.map(changedTeams.contains) ?? false}.map(\.id))
        participants=ids.intersection(all)
        let names=participants.sorted().flatMap{[entry.before.units[$0]?.name,entry.after.units[$0]?.name].compactMap{$0}}
        var fields=[title,category.title,"#\(entry.sequence)"]
        fields.append(contentsOf:participants.sorted());fields.append(contentsOf:names)
        fields.append(contentsOf:entry.events.map(\.detail));fields.append(contentsOf:entry.events.map(\.kind))
        fields.append(contentsOf:entry.dice.map{String($0.total)})
        searchText=MeadowArchiveSearch.normalize(fields.joined(separator:" "))
    }
    private static func commandTitle(_ command:GameCommand,catalog:GameCatalog)->String {
        switch command {
        case .applyPlayerProfile:return "更新人物档案"
        case .addHost:return "老师加入"
        case .grantPlayerResources:return "发放行动点 / 金币"
        case .editPlayer,.editResources:return "GM修改玩家"
        case .configureTeams,.mergeTeams,.changeTeam:return "调整队伍"
        case .transferTeamResource,.teacherTransferTeamResource:return "转移队伍资源"
        case .campaignMove,.move:return "抵达地图节点"
        case .refillCampaignMovement:return "补充地图移动条"
        case .startBattle:return "开始战斗"
        case .attack:return "普通攻击"
        case .cast(_,let skill,_):return (try? catalog.skill(skill).name) ?? "释放技能"
        case .monsterStep:return "怪物行动"
        case .useItem(_,let item,_):return "使用"+((try? catalog.item(item).name) ?? "物品")
        case .equip:return "更换装备"
        case .endTurn:return "结束行动"
        case .reward:return "发放奖励"
        case .finishBattle:return "结束战斗"
        case .configureCampaignSite,.configureNodeEncounter,.configureNodeReward,.resetNodeReward:return "修改地点配置"
        case .interactCampaignNode:return "交互地点"
        case .tradeCampaignSite:return "地点交易"
        case .resolveCampaignSite:return "处理地点事件"
        case .setHealth,.revive:return "调整生命 / 复活"
        case .rescue:return "救援队友"
        case .joinMonster:return "怪物加入战斗"
        case .reorderQueue:return "调整战斗队列"
        case .refillExploration:return "补充探索资源"
        case .setDifficulty(let level):return "难度改为"+level.title
        case .retreatAfterDefeat:return "全队倒地，撤回地图"
        case .campaignLottery(_,let tier):return "商店抽奖 · "+((try? CampaignLottery.tier(tier).title) ?? "")+"档"
        }
    }
}
public struct MeadowHistoryQuery:Equatable {
    public var text=""
    public var category:MeadowHistoryCategory = .all
    public var participant:String?=nil
    public var newestFirst=true
    public init(){}
    public func apply(_ rows:[MeadowHistoryIndex])->[MeadowHistoryIndex] {
        let words=MeadowArchiveSearch.words(text)
        return rows.filter{(category == .all || $0.category==category) && (participant.map($0.participants.contains) ?? true) && MeadowArchiveSearch.matches(words,in:$0.searchText)}.sorted{newestFirst ? $0.sequence>$1.sequence:$0.sequence<$1.sequence}
    }
}
enum MeadowArchiveSearch {
    static func normalize(_ text:String)->String {text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))}
    static func words(_ query:String)->[String] {query.split(whereSeparator:{$0.isWhitespace}).map{normalize(String($0))}}
    static func matches(_ words:[String],in text:String)->Bool {words.allSatisfy{text.contains($0)}}
}
