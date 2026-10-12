import Foundation

public struct PublicPlayFrame: Codable, Equatable {
    public var snapshot: PublicGameSnapshot
    public var log: [String]
    public var verification: Bool
    public init(snapshot: PublicGameSnapshot, log: [String], verification: Bool) {
        self.snapshot = snapshot; self.log = log; self.verification = verification
    }
}
public enum OperationSummary {
    public static func lines(_ receipt: OperationReceipt, catalog: GameCatalog, publicOnly: Bool = true) -> [String] {
        let before = receipt.before, after = receipt.after
        func name(_ id: String?) -> String? {
            guard let id, let unit = after.units[id] ?? before.units[id] else { return nil }
            if publicOnly && unit.kind == .monster && !before.map.revealed.contains(unit.nodeID) && !after.map.revealed.contains(unit.nodeID) { return nil }
            return unit.name
        }
        var result: [String] = []
        for event in receipt.events {
            let actor = name(event.actor), target = name(event.target)
            switch event.kind {
            case "naturalTwenty": if let target { result.append("自然20！\(target)生命归零") }
            case "damage": if let target { result.append("\(target)生命减少\(event.amount)，\(event.detail)") }
            case "heal": if let target, event.amount > 0 { result.append("\(target)恢复\(event.amount)生命") }
            case "shield": if let target, event.amount > 0 { result.append("\(target)护盾增加\(event.amount)") }
            case "revive": if let target { result.append("\(target)复活至\(event.amount)生命") }
            case "score": if let actor { result.append("\(actor)积分\(event.amount >= 0 ? "+" : "")\(event.amount)") }
            case "drop":
                if let actor {
                    let item = catalog.items.first { $0.id == event.detail }?.name
                    result.append("\(actor)获得" + (item.map { "\($0)×\(event.amount)" } ?? "\(event.amount)金币"))
                }
            case "teacherReward", "nodeReward": if let target { result.append("\(target)金币\(event.amount >= 0 ? "+" : "")\(event.amount)；\(event.detail)") }
            case "skill": if let actor, let skill = catalog.skills.first(where: { $0.id == event.detail }) { result.append("\(actor)使用\(skill.name)") }
            case "move": if let actor { result.append("\(actor)移动\(event.amount)条道路") }
            case "timeout": if let actor { result.append("\(actor)决策超时，行动点清零") }
            case "teacherHealth", "teacherResources": if let target { result.append("教师调整\(target)状态") }
            case "battleStarted": result.append("PVE开战，先攻队列已确定")
            case "battleEnded": result.append("本场战斗结束，返回探索")
            case "round": result.append("进入第\(event.amount)轮，行动点按基础值补足")
            default: break // AI choice internals, drop probabilities and private editor state stay private.
            }
        }
        if result.isEmpty {
            if case .endTurn(let id, _) = receipt.command, let actor = name(id) { result.append("\(actor)结束本轮行动") }
            if case .monsterStep = receipt.command { result.append("怪物结束本轮行动") }
        }
        return result
    }
}
extension PVEPlaySession {
    public func publicFrame() throws -> PublicPlayFrame {
        let dice = engine.history.last?.dice ?? []
        let log = engine.history.suffix(4).flatMap { OperationSummary.lines($0, catalog: engine.catalog) }
        return PublicPlayFrame(snapshot: try engine.state.publicSnapshot(catalog: engine.catalog, dice: dice),
                               log: Array(log.suffix(8)), verification: engine.state.verificationScenario != nil)
    }
}

extension GameState {
    /// For the teacher's local map only. Never send this value to PublicDisplayModel.
    public func teacherBoard(catalog: GameCatalog) throws -> PublicGameSnapshot {
        var local = self
        local.map.revealed = Set(map.nodes.map(\.id))
        return try local.publicSnapshot(catalog: catalog)
    }
}
