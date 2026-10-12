import Foundation

public struct ProbeError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PublicPlayer: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var health: Int
    public var maxHealth: Int
    public var shield: Int
    public var coins: Int
    public var score: Int
    public var team: String
}

public enum PauseReason: String, Codable, CaseIterable {
    case manual, notes, background, filePicker, expired, importing
}

// This value is the only game metadata passed to the external display.
public struct PublicSnapshot: Codable, Equatable {
    public var players: [PublicPlayer]
    public var pageIndex: Int
    public var pageCount: Int
    public var remainingSeconds: Double
    public var paused: Bool
}

public struct ProbeState: Codable, Equatable {
    public var players: [PublicPlayer]
    public var selectedPlayerID: Int
    public var pageIndex: Int
    public var pageCount: Int
    public var remainingSeconds: Double
    public var pauseReasons: Set<PauseReason>

    public init() {
        let healthValues = [12, 18, 24, 32, 18, 24, 32]
        players = healthValues.enumerated().map { index, health in
            PublicPlayer(id: index + 1, name: index == 6 ? "主持人" : "学生\(index + 1)",
                         health: health, maxHealth: health, shield: 0, coins: 0, score: 0,
                         team: index % 2 == 0 ? "蓝队" : "橙队")
        }
        selectedPlayerID = 1
        pageIndex = 0
        pageCount = 0
        remainingSeconds = 30
        pauseReasons = [.manual]
    }

    public var publicSnapshot: PublicSnapshot {
        PublicSnapshot(players: players, pageIndex: pageIndex, pageCount: pageCount,
                       remainingSeconds: remainingSeconds, paused: !pauseReasons.isEmpty)
    }

    public mutating func awardCoins() {
        guard let index = players.firstIndex(where: { $0.id == selectedPlayerID }),
              players[index].coins <= 999_990 else { return }
        players[index].coins += 10
    }

    public mutating func advanceClock(by elapsed: Double) {
        guard pauseReasons.isEmpty, elapsed.isFinite, elapsed > 0 else { return }
        remainingSeconds = max(0, remainingSeconds - elapsed)
        if remainingSeconds == 0 { pauseReasons.insert(.expired) }
    }

    public mutating func setPause(_ reason: PauseReason, enabled: Bool) {
        if enabled { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
    }

    public mutating func toggleManualPause() {
        if pauseReasons.contains(.manual) || pauseReasons.contains(.background) {
            pauseReasons.remove(.manual)
            pauseReasons.remove(.background)
        } else { pauseReasons.insert(.manual) }
    }

    public mutating func turnPage(by offset: Int) {
        guard pageCount > 0 else { return }
        pageIndex = min(pageCount - 1, max(0, pageIndex + offset))
    }

    public func validate() throws {
        guard (1...7).contains(players.count), Set(players.map(\.id)).count == players.count,
              players.contains(where: { $0.id == selectedPlayerID }),
              (0...60).contains(pageCount), pageIndex >= 0,
              pageIndex < max(1, pageCount), remainingSeconds.isFinite,
              (0...30).contains(remainingSeconds),
              players.allSatisfy({ player in
                  (1...7).contains(player.id) && player.name.count <= 80 && player.maxHealth > 0 && player.maxHealth <= 100_000
                      && (0...player.maxHealth).contains(player.health)
                      && (0...100_000).contains(player.shield)
                      && (0...1_000_000).contains(player.coins)
                      && (-1_000_000...1_000_000).contains(player.score) && player.team.count <= 80
              }) else { throw ProbeError("测试存档包含非法角色、页码或计时。") }
    }
}

// Private backup, never sent to the student view. This is a stage0 test format,
// not the final game save format (which will later include battle/history data).
public struct ProbeBackup: Codable {
    public var formatVersion: Int
    public var state: ProbeState
    public var pptxData: Data?
    public var sourceName: String?
    public var editedNotes: [Int: String]

    public init(state: ProbeState, pptxData: Data?, sourceName: String?, editedNotes: [Int: String]) {
        formatVersion = 1
        self.state = state
        self.pptxData = pptxData
        self.sourceName = sourceName
        self.editedNotes = editedNotes
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 48 * 1024 * 1024 else { throw ProbeError("测试备份超过48 MiB。") }
        return data
    }

    public static func decoded(_ data: Data) throws -> ProbeBackup {
        guard data.count <= 48 * 1024 * 1024 else { throw ProbeError("测试备份超过48 MiB。") }
        var backup = try JSONDecoder().decode(ProbeBackup.self, from: data)
        try backup.state.validate()
        guard backup.formatVersion == 1, (backup.pptxData?.count ?? 0) <= 32 * 1024 * 1024,
              (backup.sourceName?.count ?? 0) <= 300,
              backup.editedNotes.count <= 60,
              backup.editedNotes.allSatisfy({ key, value in
                  key >= 0 && key < backup.state.pageCount && value.count <= 40_000
              }), backup.pptxData != nil || backup.state.pageCount == 0 else {
            throw ProbeError("测试备份版本、绘本或备注无效。")
        }
        backup.state.pauseReasons = [.manual]
        return backup
    }
}
