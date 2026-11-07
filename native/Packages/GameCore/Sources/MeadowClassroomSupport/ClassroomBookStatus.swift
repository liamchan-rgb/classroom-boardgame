import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import ClassroomGameCore

/// Deliberately excludes inventory, GM drafts, notes, permissions and history.
public struct ClassroomBookPlayerStatus:Codable,Equatable,Identifiable {
    public let id:String,name:String
    public let health:Int,maximumHealth:Int,ap:Int,maximumAP:Int,coins:Int
    public init(unit:GameUnit,catalog:GameCatalog)throws {
        let stats=try GameRules.attributes(unit,catalog:catalog)
        id=unit.id;name=unit.name;health=unit.health;maximumHealth=stats.maximumHealth
        ap=unit.ap;maximumAP=stats.maximumAP;coins=unit.coins
    }
}
public enum ClassroomBookStatusLayout {
    public static let heightFraction=0.09
    public static func height(in host:CGSize,players:Int)->CGFloat {
        guard host.width.isFinite,host.height.isFinite,host.width>0,host.height>0,(1...7).contains(players) else{return 0}
        return host.height*heightFraction
    }
}
public extension ClassroomGameBackend {
    var bookPlayers:[ClassroomBookPlayerStatus] {
        guard let c=campaign else{return []}
        return c.engine.state.players.compactMap{try? .init(unit:$0,catalog:c.engine.catalog)}
    }
    var canUndoTeacherAction:Bool {
        guard let command=campaign?.engine.history.last?.command else{return false}
        switch command {case .editPlayer,.grantPlayerResources:return true;default:return false}
    }
    func undoTeacherAction(role:ClassroomRole)throws {
        try Self.requireTeacher(role)
        guard let c=campaign,!c.isCompleted,canUndoTeacherAction else{throw GameError("最近操作不是GM修改或绘本发放，不能从此入口撤销。")}
        _=try c.engine.undoPreservingPresentationPause()
    }
    func editPlayer(_ id:String,value:TeacherPlayerEdit,role:ClassroomRole)throws {
        try Self.requireTeacher(role)
        guard let c=campaign,!c.isCompleted else{throw GameError("请先开始未结算的行程。")}
        guard !(value.health==0 && c.travel?.actors.contains(id)==true) else{throw GameError("该成员仍在道路上，请抵达建筑节点后再设为倒地。")}
        _=try c.engine.apply(.editPlayer(unit:id,value:value))
    }
    func grantPlayers(_ ids:[String],ap:Int,coins:Int,role:ClassroomRole)throws {
        try Self.requireTeacher(role)
        guard let c=campaign,!c.isCompleted else{throw GameError("请先开始未结算的行程。")}
        _=try c.engine.apply(.grantPlayerResources(actors:ids,ap:ap,coins:coins))
    }
}
