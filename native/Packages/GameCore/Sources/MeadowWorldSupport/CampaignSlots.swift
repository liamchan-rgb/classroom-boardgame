import Foundation
import ClassroomGameCore

public struct MeadowCampaignCheckpoint:Codable,Equatable {
    public let operationID:String
    public let travel:MeadowCampaignTravel?
    public let camera:MeadowCampaignCamera?
    public let movement:MeadowCampaignMovement?
    public let movementBalances:[String:Double]?
    public let selectedPlayerID:String?
    public init(save:MeadowCampaignSave,operationID:String){self.operationID=operationID;travel=save.travel;camera=save.camera;movement=save.movement;movementBalances=save.movementBalances;selectedPlayerID=save.selectedPlayerID}
}
extension MeadowCampaignSave {
    public func rollingBack(after operationID:String,book:Bool=false)throws->Self {
        guard let index=archive.history.firstIndex(where:{$0.id==operationID}) else{throw GameError("找不到该条操作。")}
        var next=self;next.archive.state=archive.history[index].after
        next.archive.history=Array(archive.history.prefix(index+1));next.completion=nil
        if let c=checkpoints?.first(where:{$0.operationID==operationID}) {
            next.travel=c.travel;next.camera=c.camera;next.movement=c.movement
            next.movementBalances=c.movementBalances;next.selectedPlayerID=c.selectedPlayerID
        } else {
            // Old saves have no road checkpoints. Never reuse a stale road cursor
            // or refill movement when restoring their rule state.
            next.travel=nil
            if !next.archive.state.players.contains(where:{$0.id==next.selectedPlayerID}){next.selectedPlayerID=next.archive.state.players.first?.id}
            let limit=next.movementLimit;if let remaining=next.movement?.remaining{next.movement?.remaining=min(remaining,limit)}
        }
        next.travel?.paused=true
        next.archive.state.pauseReasons.subtract([.background,.editor,.history,.book])
        next.archive.state.pauseReasons.insert(.manual)
        if book{next.archive.state.pauseReasons.insert(.book)}
        let ids=Set(next.archive.history.map(\.id));next.checkpoints=next.checkpoints?.filter{ids.contains($0.operationID)}
        try next.validate();return next
    }
}

public struct MeadowPlayerProfile:Codable,Equatable {
    public var formatVersion=1
    public var name:String
    public var appearance:PlayerAppearance
    public init(name:String,appearance:PlayerAppearance){self.name=name.trimmingCharacters(in:.whitespacesAndNewlines);self.appearance=appearance}
    public func validate()throws {guard formatVersion==1,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=40 else{throw GameError("人物姓名需为1至40个字符。")};try appearance.validate()}
}
public struct MeadowSaveSlot<Value:Codable&Equatable>:Codable,Equatable {
    public var version=1
    public let title:String
    public let savedAt:Date
    public let value:Value
    public init(title:String,value:Value){self.title=title;self.value=value;savedAt=Date()}
}
/// Separate namespaces; damaged entries never hide healthy slots or get erased.
public final class MeadowSlotStore {
    public static let profileCount=12,campaignCount=8
    public let directory:URL
    public init(directory:URL){self.directory=directory}
    private func url(_ kind:String,_ slot:Int)throws->URL {
        guard (1...(kind=="profile" ? Self.profileCount:Self.campaignCount)).contains(slot) else{throw GameError("存档槽位无效。")}
        return directory.appendingPathComponent("\(kind)-\(slot).json")
    }
    private func read<T:Codable&Equatable>(_ kind:String,_ slot:Int,_ type:T.Type)throws->MeadowSaveSlot<T>? {
        try recoverPendingImport()
        let path=try url(kind,slot);guard FileManager.default.fileExists(atPath:path.path) else{return nil}
        let result=try JSONDecoder().decode(MeadowSaveSlot<T>.self,from:Data(contentsOf:path))
        guard result.version==1,result.savedAt.timeIntervalSince1970.isFinite,!result.title.isEmpty,result.title.count<=80 else{throw GameError("存档信息无效。")};return result
    }
    private func write<T:Codable&Equatable>(_ kind:String,_ slot:Int,_ value:MeadowSaveSlot<T>)throws {
        try recoverPendingImport()
        let path=try url(kind,slot);guard !value.title.isEmpty,value.title.count<=80 else{throw GameError("请输入1至80字存档标题。")}
        let bytes=try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try bytes.write(to:path,options:.atomic)
    }
    public func profile(_ slot:Int)throws->MeadowSaveSlot<MeadowPlayerProfile>? {let v=try read("profile",slot,MeadowPlayerProfile.self);try v?.value.validate();return v}
    public func campaign(_ slot:Int)throws->MeadowSaveSlot<MeadowCampaignSave>? {let v=try read("campaign",slot,MeadowCampaignSave.self);try v?.value.validate();return v}
    public func saveProfile(_ profile:MeadowPlayerProfile,slot:Int,title:String)throws {try profile.validate();try write("profile",slot,.init(title:title,value:profile))}
    public func saveCampaign(_ save:MeadowCampaignSave,slot:Int,title:String)throws {try save.validate();try write("campaign",slot,.init(title:title,value:save))}
    @discardableResult public func backup(_ save:MeadowCampaignSave)throws->URL {
        let bytes=try save.encoded(),folder=directory.appendingPathComponent("Recovery",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let path=folder.appendingPathComponent(UUID().uuidString+".json");try bytes.write(to:path,options:.atomic);return path
    }
    public func recoveries()throws->[URL] {
        let folder=directory.appendingPathComponent("Recovery",isDirectory:true)
        guard FileManager.default.fileExists(atPath:folder.path) else{return []}
        return try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.contentModificationDateKey]).filter{$0.pathExtension=="json"}.sorted{a,b in
            let x=(try? a.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let y=(try? b.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast;return x>y
        }
    }
}
