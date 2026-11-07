import Foundation
import ClassroomGameCore

public enum MeadowSlotKind:String,Codable,CaseIterable {case profile,campaign
    public var count:Int {self == .profile ? MeadowSlotStore.profileCount:MeadowSlotStore.campaignCount}
    public var title:String {self == .profile ? "人物":"行程"}
}
public struct MeadowSlotAddress:Codable,Equatable,Hashable,Identifiable {
    public let kind:MeadowSlotKind
    public let slot:Int
    public var id:String {"\(kind.rawValue)-\(slot)"}
    public init(_ kind:MeadowSlotKind,_ slot:Int){self.kind=kind;self.slot=slot}
    public func validate()throws{guard (1...kind.count).contains(slot) else{throw GameError("存档槽位超出范围。")}}
}
public struct MeadowTransferEntry<T:Codable&Equatable>:Codable,Equatable {
    public let slot:Int
    public let entry:MeadowSaveSlot<T>
    public init(slot:Int,entry:MeadowSaveSlot<T>){self.slot=slot;self.entry=entry}
}
public struct MeadowSaveTransfer:Codable,Equatable {
    public static let maximumBytes=128*1024*1024
    public var format="classroom-meadow-save-transfer"
    public var version=1
    public var exportedAt=Date()
    public var profiles:[MeadowTransferEntry<MeadowPlayerProfile>]=[]
    public var campaigns:[MeadowTransferEntry<MeadowCampaignSave>]=[]
    public init(){}
    public var addresses:[MeadowSlotAddress] {profiles.map{.init(.profile,$0.slot)}+campaigns.map{.init(.campaign,$0.slot)}}
    public func title(at address:MeadowSlotAddress)->String {address.kind == .profile ? profiles.first{$0.slot==address.slot}?.entry.title ?? "人物":campaigns.first{$0.slot==address.slot}?.entry.title ?? "行程"}
    public func validate()throws {
        guard format=="classroom-meadow-save-transfer",version==1,exportedAt.timeIntervalSince1970.isFinite,!addresses.isEmpty,addresses.count<=20,Set(addresses).count==addresses.count else{throw GameError("备份类型、版本或槽位列表无效。")}
        for a in addresses {try a.validate()}
        for p in profiles {try validateMetadata(p.entry);try p.entry.value.validate()}
        for c in campaigns {try validateMetadata(c.entry);try c.entry.value.validate()}
    }
    private func validateMetadata<T>(_ entry:MeadowSaveSlot<T>)throws{guard entry.version==1,!entry.title.isEmpty,entry.title.count<=80,entry.savedAt.timeIntervalSince1970.isFinite else{throw GameError("备份内的存档信息无效。")}}
    public func encoded()throws->Data {try validate();let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let data=try encoder.encode(self);guard data.count<=Self.maximumBytes else{throw GameError("备份超过128MB，请减少所选行程。")};return data}
    public static func read(from url:URL)throws->Self {
        if let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size>maximumBytes{throw GameError("备份超过128MB，请拆分导出。")}
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};var data=Data()
        while let chunk=try file.read(upToCount:1024*1024),!chunk.isEmpty {
            guard data.count<=maximumBytes-chunk.count else{throw GameError("备份超过128MB，请拆分导出。")};data.append(chunk)
        }
        return try decoded(data)
    }
    public static func decoded(_ data:Data)throws->Self {
        guard !data.isEmpty,data.count<=maximumBytes else{throw GameError("备份文件为空或超过128MB。")}
        let decoder=JSONDecoder()
        // A recognized envelope is never reinterpreted as an older file.
        let object=try JSONSerialization.jsonObject(with:data)
        guard let dictionary=object as? [String:Any] else{throw GameError("请选择人物或行程JSON备份。")}
        var result:Self
        if dictionary["format"] != nil {result=try decoder.decode(Self.self,from:data)}
        else if dictionary["value"] != nil {
            if let p=try? decoder.decode(MeadowSaveSlot<MeadowPlayerProfile>.self,from:data) {result=Self();result.profiles=[.init(slot:1,entry:p)]}
            else {let c=try decoder.decode(MeadowSaveSlot<MeadowCampaignSave>.self,from:data);result=Self();result.campaigns=[.init(slot:1,entry:c)]}
        } else if dictionary["archive"] != nil {
            let c=try MeadowCampaignSave.decoded(data);result=Self();result.campaigns=[.init(slot:1,entry:.init(title:"旧版行程",value:c))]
        } else {
            let p=try decoder.decode(MeadowPlayerProfile.self,from:data);result=Self();result.profiles=[.init(slot:1,entry:.init(title:p.name,value:p))]
        }
        try result.validate();return result
    }
    public func selecting(_ addresses:Set<MeadowSlotAddress>)throws->Self {
        guard addresses.isSubset(of:Set(self.addresses)) else{throw GameError("所选条目不属于此备份。")}
        var result=self;result.profiles=profiles.filter{addresses.contains(.init(.profile,$0.slot))};result.campaigns=campaigns.filter{addresses.contains(.init(.campaign,$0.slot))};try result.validate();return result
    }
}

/// Local transaction journal: incomplete imports roll back before any slot is
/// exposed. Raw originals (including damaged JSON) remain in ImportBackups.
struct MeadowSlotImportJournal:Codable {
    struct Row:Codable {let address:MeadowSlotAddress;let before:Data?;let after:Data}
    let version:Int
    let id:String
    let createdAt:Date
    let rows:[Row]
    func validate()throws {guard version==1,UUID(uuidString:id) != nil,!rows.isEmpty,rows.count<=20,Set(rows.map(\.address)).count==rows.count else{throw GameError("导入恢复日志无效。")};for r in rows{try r.address.validate()}}
}
public struct MeadowImportBackup:Identifiable {
    public let id:String
    public let createdAt:Date
    public let overwritten:Int
    public let error:String?
}
extension MeadowSlotStore {
    private var pendingImportURL:URL {directory.appendingPathComponent("pending-import.json")}
    private var importBackupDirectory:URL {directory.appendingPathComponent("ImportBackups",isDirectory:true)}
    private func slotFile(_ address:MeadowSlotAddress)throws->URL {try address.validate();return directory.appendingPathComponent(address.id+".json")}
    private func journalURL(_ id:String)throws->URL {guard UUID(uuidString:id) != nil else{throw GameError("导入备份ID无效。")};return importBackupDirectory.appendingPathComponent(id+".json")}
    func recoverPendingImport()throws {
        guard FileManager.default.fileExists(atPath:pendingImportURL.path) else{return}
        let id=try JSONDecoder().decode(String.self,from:Data(contentsOf:pendingImportURL))
        let journal=try JSONDecoder().decode(MeadowSlotImportJournal.self,from:Data(contentsOf:journalURL(id)));try journal.validate();guard journal.id==id else{throw GameError("导入恢复日志不匹配。")}
        for row in journal.rows {
            let path=try slotFile(row.address)
            if let before=row.before{try before.write(to:path,options:.atomic)}
            else if FileManager.default.fileExists(atPath:path.path){try FileManager.default.removeItem(at:path)}
        }
        try FileManager.default.removeItem(at:pendingImportURL)
    }
    public func exportTransfer(_ selected:Set<MeadowSlotAddress>)throws->MeadowSaveTransfer {
        try recoverPendingImport();var package=MeadowSaveTransfer()
        for a in selected.sorted(by:{$0.id<$1.id}) {
            try a.validate()
            if a.kind == .profile {guard let p=try profile(a.slot) else{throw GameError("所选人物槽为空。")};package.profiles.append(.init(slot:a.slot,entry:p))}
            else{guard let c=try campaign(a.slot) else{throw GameError("所选行程槽为空。")};package.campaigns.append(.init(slot:a.slot,entry:c))}
        }
        try package.validate();return package
    }
    public func importTransfer(_ package:MeadowSaveTransfer,destinations:[MeadowSlotAddress:Int])throws->String {
        try recoverPendingImport();try package.validate()
        guard Set(destinations.keys)==Set(package.addresses) else{throw GameError("请为每个待导入条目选择目标槽。")}
        let targets=package.addresses.map{MeadowSlotAddress($0.kind,destinations[$0]!)}
        guard Set(targets).count==targets.count else{throw GameError("多个条目不能写入同一个目标槽。")};for t in targets{try t.validate()}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        var rows=[MeadowSlotImportJournal.Row]()
        for a in package.addresses {
            let target=MeadowSlotAddress(a.kind,destinations[a]!),path=try slotFile(target)
            let bytes:Data
            if a.kind == .profile{bytes=try encoder.encode(package.profiles.first{$0.slot==a.slot}!.entry)}else{bytes=try encoder.encode(package.campaigns.first{$0.slot==a.slot}!.entry)}
            let before=FileManager.default.fileExists(atPath:path.path) ? try Data(contentsOf:path):nil
            rows.append(.init(address:target,before:before,after:bytes))
        }
        let id=UUID().uuidString,journal=MeadowSlotImportJournal(version:1,id:id,createdAt:Date(),rows:rows)
        try FileManager.default.createDirectory(at:importBackupDirectory,withIntermediateDirectories:true)
        try encoder.encode(journal).write(to:journalURL(id),options:.atomic)
        try encoder.encode(id).write(to:pendingImportURL,options:.atomic)
        do {
            for row in rows{try row.after.write(to:slotFile(row.address),options:.atomic)}
            try FileManager.default.removeItem(at:pendingImportURL)
        }catch {
            let original=error
            do{try recoverPendingImport()}catch{throw GameError("导入未完成，恢复日志已保留。请重试读取以恢复原槽位："+error.localizedDescription)}
            throw original
        }
        return id
    }
    public func importBackups()throws->[MeadowImportBackup] {
        try recoverPendingImport();guard FileManager.default.fileExists(atPath:importBackupDirectory.path) else{return []}
        return try FileManager.default.contentsOfDirectory(at:importBackupDirectory,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.map{url in
            do {
                let j=try JSONDecoder().decode(MeadowSlotImportJournal.self,from:Data(contentsOf:url));try j.validate()
                guard j.id==url.deletingPathExtension().lastPathComponent else{throw GameError("导入备份名称不匹配。")}
                return MeadowImportBackup(id:j.id,createdAt:j.createdAt,overwritten:j.rows.filter{$0.before != nil}.count,error:nil)
            }catch{return MeadowImportBackup(id:url.lastPathComponent,createdAt:.distantPast,overwritten:0,error:error.localizedDescription)}
        }.filter{$0.overwritten>0 || $0.error != nil}.sorted{$0.createdAt>$1.createdAt}
    }
    public func transferBeforeImport(_ id:String)throws->MeadowSaveTransfer {
        try recoverPendingImport();let j=try JSONDecoder().decode(MeadowSlotImportJournal.self,from:Data(contentsOf:journalURL(id)));try j.validate()
        var result=MeadowSaveTransfer();result.exportedAt=j.createdAt
        for row in j.rows {guard let bytes=row.before else{continue}
            if row.address.kind == .profile {let p=try JSONDecoder().decode(MeadowSaveSlot<MeadowPlayerProfile>.self,from:bytes);result.profiles.append(.init(slot:row.address.slot,entry:p))}
            else{let c=try JSONDecoder().decode(MeadowSaveSlot<MeadowCampaignSave>.self,from:bytes);result.campaigns.append(.init(slot:row.address.slot,entry:c))}
        }
        try result.validate();return result
    }
}
