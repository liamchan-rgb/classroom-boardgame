import Foundation
import ClassroomGameCore

// MARK: - Classroom mini-games (about 10 minutes each), driven by the class's answers.
//
// The questions themselves go through the normal quiz flow (recorded, rewarded, in the report); each game only
// looks at who answered which question right and moves its own board. Nothing here is saved with the trip.

/// One student's answer to the question just sent.
public struct MiniGameAnswer: Equatable {
    public var player: String
    public var right: Bool
    public init(player: String, right: Bool) { self.player = player; self.right = right }
}

/// The question just resolved: its difficulty (1–3) and the answers that were recorded (empty: nobody answered).
public struct MiniGameRound: Equatable {
    public var level: Int
    public var answers: [MiniGameAnswer]
    public init(level: Int, answers: [MiniGameAnswer]) { self.level = min(3, max(1, level)); self.answers = answers }
    public var rightCount: Int { answers.filter(\.right).count }
    public func answer(of player: String) -> MiniGameAnswer? { answers.first { $0.player == player } }
}

/// Seeded dice for the games (same seed, same rolls).
public struct MiniGameDice: Equatable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// 1...sides
    public mutating func roll(_ sides: Int) -> Int { Int(next() % UInt64(max(1, sides))) + 1 }
    public mutating func shuffle<T>(_ list: [T]) -> [T] {
        var a = list
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(next() % UInt64(i + 1))) }
        return a
    }
}

/// Someone (or a team) taking turns in a game.
public struct MiniGameSide: Equatable, Identifiable {
    public var id: String
    public var name: String
    /// The students answering for this side (a student is a side of one).
    public var members: [String]
    public init(id: String, name: String, members: [String]) { self.id = id; self.name = name; self.members = members }

    /// Teams when there are two or more with students, otherwise every student on their own.
    public static func sides(_ state: GameState) -> [MiniGameSide] {
        let students = state.players.filter { !$0.host }
        let teams = state.teams.compactMap { team -> MiniGameSide? in
            let members = students.filter { $0.teamID == team.id }.map(\.id)
            return members.isEmpty ? nil : MiniGameSide(id: team.id, name: team.name, members: members)
        }
        if teams.count >= 2 { return teams }
        return students.map { MiniGameSide(id: $0.id, name: $0.shortName, members: [$0.id]) }
    }
}

public enum MiniGameOutcome: Equatable { case won, lost }

// MARK: 全班打Boss

/// The whole class against one big monster: every right answer rolls an attack die (bigger for harder questions);
/// when fewer than half of the answers are right (or nobody answered) the boss hits back and the class loses a heart.
public struct BossRaid: Equatable {
    public struct Hit: Equatable { public var player: String; public var sides: Int; public var damage: Int }
    public static let hearts = 5
    /// ★ d4, ★★ d6, ★★★ d10.
    public static func dieSides(level: Int) -> Int { [4, 6, 10][min(3, max(1, level)) - 1] }
    /// About ten questions for a class answering ★★ questions mostly right.
    public static func hp(students: Int) -> Int { max(24, students * 18) }

    public var monster: String
    public let maxHP: Int
    public var hp: Int
    public var hearts: Int
    public var round = 0
    public var lastHits: [Hit] = []
    public var lastCounter = false
    public var outcome: MiniGameOutcome?
    public init(monster: String, students: Int) {
        self.monster = monster; maxHP = Self.hp(students: students); hp = maxHP; hearts = Self.hearts
    }
    public mutating func resolve(_ q: MiniGameRound, dice: inout MiniGameDice) {
        guard outcome == nil else { return }
        round += 1
        let sides = Self.dieSides(level: q.level)
        lastHits = q.answers.filter(\.right).map { Hit(player: $0.player, sides: sides, damage: dice.roll(sides)) }
        hp = max(0, hp - lastHits.reduce(0) { $0 + $1.damage })
        lastCounter = hp > 0 && (q.answers.isEmpty || q.rightCount * 2 < q.answers.count)
        if lastCounter { hearts -= 1 }
        if hp == 0 { outcome = .won } else if hearts <= 0 { outcome = .lost }
    }
}

// MARK: 守护营地

/// A monster walks down the path toward the camp, one step per question; the class's answers push it back: all
/// right → one step back, at least half right → it stays, otherwise it comes one step closer. Hold out for the
/// rounds and the camp is safe.
public struct CampDefense: Equatable {
    public static let length = 6
    public static let rounds = 12
    public var position = 0
    public var round = 0
    /// −1 back, 0 held, +1 closer.
    public var lastMove = 0
    public var outcome: MiniGameOutcome?
    public init() {}
    public static func move(_ q: MiniGameRound) -> Int {
        let n = q.answers.count, right = q.rightCount
        guard n > 0 else { return 1 }
        if right == n { return -1 }
        return right * 2 >= n ? 0 : 1
    }
    public mutating func resolve(_ q: MiniGameRound) {
        guard outcome == nil else { return }
        round += 1
        lastMove = Self.move(q)
        position = min(Self.length, max(0, position + lastMove))
        if position >= Self.length { outcome = .lost } else if round >= Self.rounds { outcome = .won }
    }
    /// The wave on the path (it gets tougher as the rounds go by).
    public var wave: Int { min(2, round / 4) }
}

// MARK: 答题赛跑

/// Sides race along a straight track. On its turn a side answers; right → roll a d6 and move. Cells: reward (spin
/// the wheel), trap (the next turn's question must be answered right or go back 2), boost (+3). First to the end wins.
public struct RaceTrack: Equatable {
    public enum Cell: Equatable { case plain, reward, trap, boost, finish }
    public enum Event: Equatable {
        case moved(side: String, roll: Int, to: Int)
        case missed(side: String)
        case trapFailed(side: String, to: Int)
        case landed(side: String, cell: Cell)
    }
    public static let length = 20
    public let sides: [MiniGameSide]
    public let cells: [Cell]
    public var positions: [String: Int]
    public var turn = 0
    public var trapped = Set<String>()
    public var events: [Event] = []
    public var winner: String?
    public init(sides: [MiniGameSide], seed: UInt64) {
        self.sides = sides
        positions = Dictionary(uniqueKeysWithValues: sides.map { ($0.id, 0) })
        cells = Self.track(seed: seed)
    }
    /// 0 is the start, `length` the finish; three reward cells, two traps and two boosts on seven of the odd cells
    /// 3…17 (never side by side). A boost (+3) always lands on a plain even cell.
    public static func track(seed: UInt64) -> [Cell] {
        var dice = MiniGameDice(seed: seed)
        var cells = Array(repeating: Cell.plain, count: length + 1)
        cells[length] = .finish
        let slots = dice.shuffle(Array(stride(from: 3, through: 17, by: 2))).prefix(7)
        let boosts = Array(slots.filter { $0 <= 15 }.prefix(2))
        let rest = dice.shuffle(slots.filter { !boosts.contains($0) })
        for i in boosts { cells[i] = .boost }
        for (k, i) in rest.enumerated() { cells[i] = k < 2 ? .trap : .reward }
        return cells
    }
    public var current: MiniGameSide? { sides.isEmpty ? nil : sides[turn % sides.count] }
    public mutating func resolve(_ q: MiniGameRound, dice: inout MiniGameDice) {
        guard winner == nil, let side = current else { return }
        events = []
        let right = q.answers.contains { $0.right && side.members.contains($0.player) }
        var at = positions[side.id] ?? 0
        if trapped.contains(side.id) {
            trapped.remove(side.id)
            if !right {
                at = max(0, at - 2); positions[side.id] = at
                events.append(.trapFailed(side: side.id, to: at))
                turn += 1; return
            }
        }
        guard right else { events.append(.missed(side: side.id)); turn += 1; return }
        let roll = dice.roll(6)
        at = min(Self.length, at + roll)
        events.append(.moved(side: side.id, roll: roll, to: at))
        switch cells[at] {
        case .boost:
            events.append(.landed(side: side.id, cell: .boost))
            at = min(Self.length, at + 3)
        case .trap:
            trapped.insert(side.id); events.append(.landed(side: side.id, cell: .trap))
        case .reward:
            events.append(.landed(side: side.id, cell: .reward))
        case .plain, .finish: break
        }
        positions[side.id] = at
        if at >= Self.length { winner = side.id } else { turn += 1 }
    }
    /// Sides by how far along they are.
    public var standings: [MiniGameSide] { sides.sorted { (positions[$0.id] ?? 0) > (positions[$1.id] ?? 0) } }
}

// MARK: 翻牌寻宝

/// Cards face down, two sides of each flash card (English and its meaning). A side turns two cards; a pair has to
/// be read out (the teacher judges) to be kept, and then the side goes again. No pair, or said wrong: both turn back,
/// next side. Most pairs when the board is clear wins.
public struct MemoryMatch: Equatable {
    public struct Card: Equatable { public var pair: Int; public var text: String; public var english: Bool }
    public enum Phase: Equatable { case picking, judging, mismatch }
    public let sides: [MiniGameSide]
    public let cards: [Card]
    public var faceUp: [Int] = []
    /// Pair → the side that kept it.
    public var owner: [Int: String] = [:]
    public var turn = 0
    public init(pairs: [(english: String, meaning: String)], sides: [MiniGameSide], seed: UInt64) {
        var dice = MiniGameDice(seed: seed)
        let all = pairs.enumerated().flatMap { i, p in [Card(pair: i, text: p.english, english: true), Card(pair: i, text: p.meaning, english: false)] }
        cards = dice.shuffle(all)
        self.sides = sides
    }
    public var pairCount: Int { cards.count / 2 }
    public var current: MiniGameSide? { sides.isEmpty ? nil : sides[turn % sides.count] }
    public var phase: Phase {
        guard faceUp.count == 2 else { return .picking }
        return cards[faceUp[0]].pair == cards[faceUp[1]].pair ? .judging : .mismatch
    }
    public var finished: Bool { owner.count == pairCount }
    public func matched(_ i: Int) -> Bool { owner[cards[i].pair] != nil }
    public func canFlip(_ i: Int) -> Bool { !finished && cards.indices.contains(i) && faceUp.count < 2 && !faceUp.contains(i) && !matched(i) }
    public mutating func flip(_ i: Int) { if canFlip(i) { faceUp.append(i) } }
    /// After a pair: read out right → kept, the same side goes again; wrong → turned back, next side.
    public mutating func judge(right: Bool) {
        guard phase == .judging, let side = current else { return }
        if right { owner[cards[faceUp[0]].pair] = side.id } else { turn += 1 }
        faceUp = []
    }
    /// Two different cards were shown: they turn back, next side.
    public mutating func turnBack() { guard phase == .mismatch else { return }; faceUp = []; turn += 1 }
    public func pairs(of side: String) -> Int { owner.values.filter { $0 == side }.count }
    /// The flash cards that fit a card (a word or short phrase each side), ★ and ★★ only.
    public static func candidates(_ bank: [QuizQuestion], among indices: [Int]) -> [(english: String, meaning: String)] {
        // Each English word and each meaning once: two cards reading 谢谢 would make a pair ambiguous.
        var seen = Set<String>(), meanings = Set<String>(), result: [(english: String, meaning: String)] = []
        for i in indices where bank.indices.contains(i) {
            let q = bank[i]
            guard q.type == .flashcard, q.level <= 2, let w = QuizReport.word(q, part: 0), let meaning = w.meaning else { continue }
            let english = w.word.trimmingCharacters(in: .whitespaces), back = meaning.trimmingCharacters(in: .whitespaces)
            guard !english.isEmpty, !back.isEmpty, english.count <= 18, back.count <= 10, !seen.contains(english.lowercased()), meanings.insert(back).inserted else { continue }
            seen.insert(english.lowercased())
            result.append((english, back))
        }
        return result
    }
}

// MARK: 擂台王

/// Two students up front, the same question for both. The winner stays: the challenger takes the stage by being
/// right when the champion is not, or by getting a ★★★ question right. Both wrong: the champion stays, nobody
/// scores. The loser goes to the back of the line. Every third win in a row earns a spin of the wheel.
public struct ArenaKing: Equatable {
    public enum Result: Equatable { case defended, dethroned, nobody }
    public var champion: String
    public var challenger: String
    public var line: [String]
    public var streak = 0
    public var wins: [String: Int] = [:]
    public var best: [String: Int] = [:]
    public var round = 0
    public var last: Result?
    /// The champion just reached 3, 6, … wins in a row.
    public var bonus = false
    public init?(players: [String]) {
        guard players.count >= 2 else { return nil }
        champion = players[0]; challenger = players[1]; line = Array(players.dropFirst(2))
    }
    public mutating func resolve(_ q: MiniGameRound) {
        let defender = q.answer(of: champion)?.right ?? false, attacker = q.answer(of: challenger)?.right ?? false
        round += 1; bonus = false
        let loser: String
        if attacker && (!defender || q.level == 3) {
            loser = champion; champion = challenger; streak = 1; last = .dethroned
            wins[champion, default: 0] += 1
        } else if defender {
            loser = challenger; streak += 1; last = .defended
            wins[champion, default: 0] += 1
            bonus = streak % 3 == 0
        } else {
            loser = challenger; last = .nobody
        }
        best[champion] = max(best[champion] ?? 0, streak)
        line.append(loser)
        challenger = line.removeFirst()
    }
    /// Players by wins (then their best streak).
    public func ranking(_ players: [String]) -> [String] {
        players.sorted { a, b in
            let x = (wins[a] ?? 0, best[a] ?? 0), y = (wins[b] ?? 0, best[b] ?? 0)
            return x == y ? (players.firstIndex(of: a) ?? 0) < (players.firstIndex(of: b) ?? 0) : x > y
        }
    }
}
