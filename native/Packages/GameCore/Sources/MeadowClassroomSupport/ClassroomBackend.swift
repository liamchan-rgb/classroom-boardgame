import Foundation
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport

public enum ClassroomRole { case teacher, publicDisplay }
/// Only player-facing surfaces can be projected. Editors/configuration are not cases.
public enum ClassroomPublicSurface:Equatable { case waiting, exploration, inventory(String), encounter(Int), battle, book, results }

/// One authority for the current demo. The display never creates a campaign,
/// generates a map, edits a node, advances AI or submits another copy of a roll.
public final class ClassroomGameBackend {
    public private(set) var campaign:MeadowCampaignSession?
    public private(set) var encounter:PartyEncounter?
    private var encounterKey:String?
    private var requested:ClassroomPublicSurface = .exploration
    public init() {}
    public static func requireTeacher(_ role:ClassroomRole)throws {
        guard case .teacher=role else{throw GameError("此操作仅限教师后台。")}
    }
    public func generate(_ configuration:MeadowMapConfiguration,role:ClassroomRole)throws->GeneratedMeadowMap {
        try Self.requireTeacher(role);return try MeadowMapGenerator.generate(configuration)
    }
    public func install(_ session:MeadowCampaignSession,role:ClassroomRole)throws {
        try Self.requireTeacher(role)
        // A saved PPT presentation is transient UI state, not a permanent game pause.
        if session.engine.state.pauseReasons.contains(.book){try session.engine.setPause(.book,enabled:false)}
        campaign=session;encounter=nil;encounterKey=nil;requested = .exploration
    }
    public func project(_ surface:ClassroomPublicSurface,role:ClassroomRole)throws {
        try Self.requireTeacher(role)
        switch surface {
        case .inventory(let id):
            guard let c=campaign,c.engine.state.players.contains(where:{$0.id==id}),c.engine.state.battle==nil else{throw GameError("当前无法展示此角色的行囊。")}
        case .encounter(let id):
            guard let c=campaign,c.engine.state.battle==nil,(try c.encounterPreview(node:id)) != nil else{throw GameError("请选择可预览的战斗地点。")}
        default:break
        }
        requested=surface
    }
    public var surface:ClassroomPublicSurface {
        if requested == .book{return .book}
        guard let c=campaign else{return .waiting}
        if c.engine.state.battle != nil{return .battle}
        if c.isCompleted{return .results}
        switch requested {case .inventory,.encounter:return requested;default:return .exploration}
    }
    public func travel(to point:MeadowWorldPoint,role:ClassroomRole)throws {
        try Self.requireTeacher(role);guard let c=campaign else{throw GameError("请先在后台生成行程。")}
        _=try c.beginTravel(toRoadPoint:point,actor:c.selectedPlayerID);requested = .exploration
    }
    public func selectPlayer(_ id:String,role:ClassroomRole)throws {
        try Self.requireTeacher(role);try campaign?.selectPlayer(id)
    }
    public func advanceTravel(distance:Double,role:ClassroomRole)throws->[OperationReceipt] {
        try Self.requireTeacher(role);return try campaign?.advanceTravel(distance:distance) ?? []
    }
    public func battleModel(role:ClassroomRole)throws->PartyEncounter {
        try Self.requireTeacher(role)
        guard let c=campaign,c.engine.state.battle != nil else{throw GameError("当前没有战斗。")}
        let key=c.engine.state.gameID+":"+(c.engine.history.last(where:{$0.events.contains(where:{$0.kind=="battleStarted"})})?.id ?? "restored")
        if let encounter,encounterKey==key{return encounter}
        let model=try PartyEncounter(engine:c.engine);encounter=model;encounterKey=key;return model
    }
    /// Read/validate the same model used by the renderer, without preparing a
    /// transaction or consuming RNG. Also protects keyboard/other teacher inputs.
    public func battleTarget(for action:PartyAction,selected:String,role:ClassroomRole)throws->String {
        try Self.requireTeacher(role)
        let model=try battleModel(role:role)
        guard model.state.pauseReasons.isEmpty else{throw GameError("请先继续战斗。")}
        guard let actor=model.current,model.state.units[actor]?.kind == .player else{throw GameError("请等待怪物行动结束。")}
        let items:[PartyAction]=[.smallPotion,.largePotion,.shieldPotion,.revivalStone,.endTurn]
        guard model.playerActions().contains(action) || items.contains(action) else{throw GameError("当前角色没有此技能。")}
        let ally=model.state.units[selected]?.kind == .player ? selected:actor
        let enemy=model.state.units[selected]?.kind == .monster ? selected:(model.state.battle?.queue.first{model.state.units[$0]?.kind == .monster && model.state.units[$0]?.isAlive==true} ?? "")
        let target=model.preferredTarget(for:action,ally:ally,enemy:enemy)
        let preview=model.preview(action,target:target)
        guard preview.allowed else{throw GameError(preview.message)}
        return target
    }
    /// Reserved separate host seat: never counts toward the six student seats.
    public func joinTeacher(name:String,classID:String,team:String,role:ClassroomRole)throws {
        try Self.requireTeacher(role)
        guard let c=campaign,c.travel==nil,!c.isCompleted else{throw GameError("请先停止行程。")}
        let node=c.engine.state.units[c.selectedPlayerID]!.nodeID
        _=try c.engine.apply(.addHost(id:"p7",name:name,classID:classID,team:team,node:node))
    }
    public func configureEncounter(node:Int,templates:[String],role:ClassroomRole)throws {
        try Self.requireTeacher(role);guard let c=campaign else{throw GameError("行程未开始。")}
        _=try c.configureEncounter(node:node,templates:templates)
    }
    public func refill(usingCoins:Bool,role:ClassroomRole)throws {
        try Self.requireTeacher(role);_ = try campaign?.refillMovement(usingCoins:usingCoins)
    }
    public func apply(_ command:GameCommand,role:ClassroomRole)throws {
        try Self.requireTeacher(role);guard let c=campaign,!c.isCompleted else{throw GameError("当前不能修改行程。")}
        _=try c.engine.apply(command)
    }
}
