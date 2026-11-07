import Foundation
import ClassroomGameCore

public struct MeadowCampaignReadIssue:Equatable {
    public let file:String,message:String
}
public struct MeadowCampaignHistory {
    public let saves:[MeadowCampaignSave],issues:[MeadowCampaignReadIssue]
    public var notice:String {issues.isEmpty ? "":"有\(issues.count)份记录无法读取，原文件已保留。"}
}

/// A local editing draft. Opening, changing or cancelling never edits the engine.
public struct MeadowEncounterEditDraft:Equatable {
    public let nodeID:Int,maximumCount:Int
    public let choices:[MonsterDefinition]
    public private(set) var count:Int
    private var slots:[String]
    public var templates:[String] {Array(slots.prefix(count))}
    public init(node:MapNode,templates:[String],catalog:GameCatalog)throws {
        guard node.kind == .combat || node.kind == .boss,templates.count<=3,!catalog.monsters.isEmpty,templates.allSatisfy({id in catalog.monsters.contains{$0.id==id}}) else{throw GameError("此地点的遭遇无法编辑。")}
        nodeID=node.id;choices=catalog.monsters
        maximumCount=node.kind == .boss ? max(1,templates.count):3
        count=max(1,templates.count);slots=templates
        while slots.count<maximumCount{slots.append(catalog.monsters[0].id)}
    }
    public mutating func setCount(_ value:Int)throws {
        guard (1...maximumCount).contains(value) else{throw GameError("此地点最多设置\(maximumCount)只怪物。")};count=value
    }
    public mutating func setTemplate(_ id:String,at index:Int)throws {
        guard (0..<count).contains(index),choices.contains(where:{$0.id==id}) else{throw GameError("请选择已登记的怪物。")};slots[index]=id
    }
}
