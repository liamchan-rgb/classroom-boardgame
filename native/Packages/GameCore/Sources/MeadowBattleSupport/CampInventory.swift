import Foundation
import ClassroomGameCore

/// A camp configuration, deliberately separate from the resettable combat lab.
public struct CampSave:Codable {
    public var formatVersion=1
    public let appearanceID:String
    public let archive:GameArchive
    public init(appearanceID:String,archive:GameArchive) { self.appearanceID=appearanceID;self.archive=archive }
    public func validate(appearances:[String],equipment:Set<String>) throws {
        guard formatVersion==1,appearances.contains(appearanceID) else { throw GameError("存档版本或衣装不受支持。") }
        try archive.validate()
        let currentCatalog=try GameCatalog.initial()
        guard archive.catalog == currentCatalog,archive.state.phase == .exploration,archive.state.battle == nil,
              Set(archive.state.units.keys)==Set(["p1","p2"]),archive.state.units["p1"]?.kind == .player,
              archive.state.units["p2"]?.kind == .player,
              archive.state.units["p1"]?.templateID=="adventurer",archive.state.units["p2"]?.templateID=="ranger",
              archive.state.units["p2"]?.equipment == Equipment(weapon:"trainingSword") else { throw GameError("请选择当前营地的装备存档，不能载入其他对局。") }
        for unit in archive.state.players {
            guard unit.equipment.itemIDs.allSatisfy(equipment.contains) else { throw GameError("存档含尚未接入的装备外观。") }
        }
    }
    public func encoded() throws -> Data { let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return try e.encode(self) }
}

public final class CampSaveStore {
    public let url:URL
    public init(url:URL) { self.url=url }
    public func read() throws -> Data? { FileManager.default.fileExists(atPath:url.path) ? try Data(contentsOf:url):nil }
    public func write(_ data:Data) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
    }
    @discardableResult public func preserveCurrent() throws -> URL? {
        guard let data=try read() else { return nil }
        let backup=url.deletingPathExtension().appendingPathExtension("preserved-"+UUID().uuidString+".json")
        try data.write(to:backup,options:.atomic);return backup
    }
}

/// Writes before the original engine commits. A failed save leaves inventory,
/// equipment, resources and appearance unchanged; unreadable files stay intact.
public final class CampInventorySession {
    public private(set) var appearanceID:String
    public private(set) var loadIssue:String?
    public private(set) var lastSaved:Date?
    public var savingBlocked:Bool { loadIssue != nil }
    public var loadout:TrainingLoadout { staged! }
    public let appearances:[String]
    public let equipment:Set<String>
    private let store:CampSaveStore?
    private var staged:TrainingLoadout?
    public init(store:CampSaveStore?,appearances:[String]=["forester","wayfarer"],equipment:Set<String>=Set(["trainingSword","huntingBow","greatSword","legendaryStaff","leatherArmor","runeArmor","powerBadge","actionRing"])) throws {
        guard let first=appearances.first else { throw GameError("衣装清单为空。") }
        self.store=store;self.appearances=appearances;self.equipment=equipment;appearanceID=first
        var archive:GameArchive?
        if let store {
            do {
                if let data=try store.read() { let save=try decode(data);archive=save.archive;appearanceID=save.appearanceID;lastSaved=Date() }
            } catch { loadIssue="存档无法读取，原文件已保留。当前试装不会覆盖旧档。" }
        }
        let initial=try archive ?? TrainingLoadout().engine.archive
        staged=try TrainingLoadout(archive:initial,persist:{ [weak self] archive in try self?.persist(archive) })
        if archive==nil,loadIssue==nil { try persist(initial) }
    }
    private func decode(_ data:Data) throws -> CampSave {
        let save=try JSONDecoder().decode(CampSave.self,from:data);try save.validate(appearances:appearances,equipment:equipment);return save
    }
    private func persist(_ archive:GameArchive) throws {
        guard !savingBlocked else { return }
        let save=CampSave(appearanceID:appearanceID,archive:archive);try save.validate(appearances:appearances,equipment:equipment)
        try store?.write(save.encoded());if store != nil { lastSaved=Date() }
    }
    public func saveNow() throws { guard !savingBlocked else { throw GameError(loadIssue!) };try persist(loadout.engine.archive) }
    public func setAppearance(_ id:String) throws {
        guard appearances.contains(id) else { throw GameError("衣装不受支持。") }
        let old=appearanceID;appearanceID=id
        do { try persist(loadout.engine.archive) } catch { appearanceID=old;throw error }
    }
    public func candidateEquipment(slot:ItemSlot,item:String?) throws -> GameUnit {
        if let item { guard equipment.contains(item) else { throw GameError("该装备的外观尚未接入。") } }
        let clone=try TrainingLoadout(archive:loadout.engine.archive)
        if clone.units["p1"]?.equipment[slot] != item { try clone.engine.apply(.equip(unit:"p1",slot:slot,item:item)) }
        return clone.units["p1"]!
    }
    public func equip(slot:ItemSlot,item:String?) throws {
        _=try candidateEquipment(slot:slot,item:item)
        if loadout.units["p1"]?.equipment[slot] != item { try loadout.engine.apply(.equip(unit:"p1",slot:slot,item:item)) }
    }
    public func use(item:String,target:String) throws {
        let command:GameCommand=item==loadout.engine.catalog.rules.revivalStone ? .rescue(actor:"p1",target:target):.useItem(actor:"p1",item:item,target:target)
        try loadout.engine.apply(command)
    }
    public func exportData() throws -> Data { try CampSave(appearanceID:appearanceID,archive:loadout.engine.archive).encoded() }
    public func inspectImport(_ data:Data) throws -> CampSave { try decode(data) }
    public func importData(_ data:Data) throws {
        guard !savingBlocked else { throw GameError("请先保留旧档并启用保存，再载入其他配置。") }
        let save=try decode(data)
        let next=try TrainingLoadout(archive:save.archive,persist:{ [weak self] archive in try self?.persist(archive) })
        _=try store?.preserveCurrent();try store?.write(save.encoded())
        staged=next;appearanceID=save.appearanceID;if store != nil { lastSaved=Date() }
    }
    public func preserveOldAndEnableSaving() throws {
        guard savingBlocked else { try saveNow();return }
        _=try store?.preserveCurrent()
        let save=CampSave(appearanceID:appearanceID,archive:loadout.engine.archive);try save.validate(appearances:appearances,equipment:equipment)
        try store?.write(save.encoded());loadIssue=nil;if store != nil { lastSaved=Date() }
    }
}

public struct InventoryEntry:Codable {
    public let id:String,name:String,category:String,summary:String
    public let quantity:Int,equipped:Bool
}
public struct InventoryDetail:Codable {
    public let id:String,name:String,category:String,summary:String,actionTitle:String,reason:String
    public let quantity:Int,equipped:Bool,enabled:Bool
    public let comparison:[String]
}
public enum CampInventoryProjection {
    public static func category(_ item:ItemDefinition)->String { item.slot?.rawValue ?? "supplies" }
    public static func slotTitle(_ slot:ItemSlot)->String { switch slot { case .weapon:return "武器";case .armor:return "护甲";case .accessory:return "饰品" } }
    public static func summary(_ item:ItemDefinition)->String {
        var parts:[String]=[]
        if let attack=item.attack { parts.append(attack.dice.label+" · 射程\(attack.range)") }
        let a=item.attributes
        if a.maximumHealth != 0 { parts.append("生命上限＋\(a.maximumHealth)") }
        if a.damage != 0 { parts.append("伤害＋\(a.damage)") }
        if a.baseAP != 0 { parts.append("基础行动＋\(a.baseAP)") }
        if item.heal>0 { parts.append("恢复\(item.heal)生命") }
        if item.shield>0 { parts.append("护盾至\(item.shield)") }
        if item.kind == .revivalStone { parts.append("同地点复活队友 · 恢复半数生命") }
        return parts.joined(separator:" · ")
    }
    public static func entries(_ unit:GameUnit,catalog:GameCatalog,filter:String="all") -> [InventoryEntry] {
        catalog.items.filter { (unit.inventory[$0.id] ?? 0)>0 || unit.equipment.itemIDs.contains($0.id) }.filter { filter=="all" || category($0)==filter }.map {
            InventoryEntry(id:$0.id,name:$0.name,category:category($0),summary:summary($0),quantity:unit.inventory[$0.id] ?? 0,equipped:unit.equipment.itemIDs.contains($0.id))
        }
    }
    public static func detail(_ id:String,session:CampInventorySession,target:String="p1") throws -> InventoryDetail {
        let unit=session.loadout.units["p1"]!,catalog=session.loadout.engine.catalog,item=try catalog.item(id)
        let equipped=unit.equipment.itemIDs.contains(id),quantity=unit.inventory[id] ?? 0
        var comparison:[String]=[],enabled=false,reason="",action=""
        if let slot=item.slot {
            action=equipped ? "卸下":"装备"
            do {
                let candidate=try session.candidateEquipment(slot:slot,item:equipped ? nil:id)
                let before=try GameRules.attributes(unit,catalog:catalog),after=try GameRules.attributes(candidate,catalog:catalog)
                let attack=candidate.equipment.weapon.flatMap { try? catalog.item($0).attack?.dice.label } ?? "空手"
                comparison=["普攻：\(attack)","生命：\(unit.health)/\(before.maximumHealth) → \(candidate.health)/\(after.maximumHealth)","额外伤害：＋\(before.damage) → ＋\(after.damage)","基础行动：\(before.baseAP) → \(after.baseAP)","行动上限：\(after.maximumAP)","换装不回复生命或行动点"]
                enabled=true
            } catch { reason=error.localizedDescription }
        } else {
            let revive=item.kind == .revivalStone
            action=revive ? "复活队友 · 2 AP":"使用道具 · 1 AP"
            let command:GameCommand=revive ? .rescue(actor:"p1",target:target):.useItem(actor:"p1",item:id,target:target)
            let preview=session.loadout.engine.preview(command);enabled=preview.allowed;reason=preview.allowed ? "":preview.message
            if let receiver=session.loadout.units[target],let stats=try? GameRules.attributes(receiver,catalog:catalog) {
                comparison=["目标：\(target.uppercased())",revive ? "复活后生命：\((stats.maximumHealth+1)/2)/\(stats.maximumHealth)":"生命：\(receiver.health) → \(min(stats.maximumHealth,receiver.health+item.heal))/\(stats.maximumHealth)","护盾：\(receiver.shield) → \(max(receiver.shield,item.shield))","背包：\(quantity) → \(max(0,quantity-1))"]
                if !revive,preview.allowed,item.heal>0,receiver.health==stats.maximumHealth,item.shield<=receiver.shield { enabled=false;reason="目标生命已满，无需使用。" }
                if !revive,preview.allowed,item.heal==0,item.shield<=receiver.shield { enabled=false;reason="目标已有相同或更强护盾。" }
            }
        }
        return InventoryDetail(id:id,name:item.name,category:category(item),summary:summary(item),actionTitle:action,reason:reason,quantity:quantity,equipped:equipped,enabled:enabled,comparison:comparison)
    }
}

public struct InventoryRect:Codable { public let x:Double,y:Double,width:Double,height:Double }
public struct CampInventoryLayout:Codable {
    public let header:InventoryRect,equipment:InventoryRect,bag:InventoryRect,detail:InventoryRect,footer:InventoryRect
    public init(width:Double,height:Double,left:Double=0,right:Double=0,top:Double=0,bottom:Double=0) {
        let m=12.0,g=10.0,x=max(m,left+8),y=max(8,top+4),w=max(1,width-x-max(m,right+8)),h=max(1,height-y-max(8,bottom+4))
        header=InventoryRect(x:x,y:y,width:w,height:56)
        let bodyY=y+66,bodyH=max(1,h-94),a=min(260,max(166,w*0.25)),b=(w-a-2*g)*0.50,c=w-a-b-2*g
        equipment=InventoryRect(x:x,y:bodyY,width:a,height:bodyH)
        bag=InventoryRect(x:x+a+g,y:bodyY,width:b,height:bodyH)
        detail=InventoryRect(x:x+a+b+2*g,y:bodyY,width:c,height:bodyH)
        footer=InventoryRect(x:x,y:y+h-22,width:w,height:22)
    }
}
