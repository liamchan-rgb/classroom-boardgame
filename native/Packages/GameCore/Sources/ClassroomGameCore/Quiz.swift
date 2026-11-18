import Foundation

public enum QuizKind: String, Codable, CaseIterable {
    case choice, flashcard, fill, reading
    public var title: String {
        switch self { case .choice: return "选择题"; case .flashcard: return "闪卡"; case .fill: return "填空"; case .reading: return "阅读" }
    }
}

/// One thing the teacher records the student's answer for: a choice, a flash card, one blank, one reading question.
/// `options` are what the teacher can tap (the student's spoken answer), `answer` the right one.
public struct QuizItem: Codable, Equatable {
    public var prompt: String?
    public var options: [String]
    public var answer: Int
    public init(prompt: String? = nil, options: [String], answer: Int) { self.prompt = prompt; self.options = options; self.answer = answer }
}

/// One question of a teacher-imported bank (format: docs/question-bank-format.md).
/// Choice questions keep the original fields (`prompt`, `options`, `answer`); the other kinds put what is graded in `items`:
/// a flash card has one item (its back among distractors), a fill-in one item per blank (blanks in `prompt` are
/// written `{{1}}`, `{{2}}`…), reading one item per question under `passage`.
public struct QuizQuestion: Codable, Equatable {
    public var prompt: String
    public var options: [String]
    /// Index of the correct option (0 = A).
    public var answer: Int
    /// Coins for a fully right answer; without it the difficulty decides (old banks: 10).
    public var coins: Int?
    public var explanation: String?
    public var kind: QuizKind? = nil
    /// 1 easy … 3 hard; nil for old banks (fixed 10 coins, 1 point, no drop).
    public var difficulty: Int? = nil
    /// Answer time; nil = by difficulty.
    public var seconds: Int? = nil
    public var tags: [String]? = nil
    public var passage: String? = nil
    public var items: [QuizItem]? = nil
    /// Who it is for: student names or numbers (专属题). nil, or "全班", = the shared bank (公用题).
    public var audience: [String]? = nil
    /// Which pre-cut portion of exclusive questions it belongs to ("1", "2", "A"…); the teacher decides in the app
    /// whose portion is whose.
    public var portion: String? = nil
    public init(prompt: String, options: [String], answer: Int, coins: Int? = nil, explanation: String? = nil,
                kind: QuizKind? = nil, difficulty: Int? = nil, seconds: Int? = nil, tags: [String]? = nil, passage: String? = nil, items: [QuizItem]? = nil) {
        self.prompt = prompt; self.options = options; self.answer = answer; self.coins = coins; self.explanation = explanation
        self.kind = kind; self.difficulty = difficulty; self.seconds = seconds; self.tags = tags; self.passage = passage; self.items = items
    }
    public static let defaultCoins = 10
    /// In the shared bank (rewards are handed out by the teacher).
    public var isShared: Bool { portion == nil && isSharedAudience }
    private var isSharedAudience: Bool { audience.map { $0.isEmpty || $0.contains { ["全班", "全体", "所有人", "all", "公用"].contains($0.lowercased()) } } ?? true }
    /// Whether this exclusive question is for a student with that name (or short name) and number (p3 → 3).
    public func isFor(names: [String], number: Int?) -> Bool {
        guard portion == nil, !isShared, let audience else { return false }
        return audience.contains { a in names.contains(a) || (number.map { String($0) == a } ?? false) }
    }
    public var type: QuizKind { kind ?? .choice }
    /// What gets graded, in order.
    public var parts: [QuizItem] {
        if type == .choice { return [QuizItem(options: options, answer: answer)] }
        return items ?? []
    }
    /// Coins for everything right.
    public var reward: Int { coins ?? difficulty.map { QuizRewards.baseCoins[$0 - 1] } ?? Self.defaultCoins }
    public var points: Int { difficulty ?? 1 }
    public var timeLimit: Int { seconds ?? QuizRewards.baseSeconds[(difficulty ?? 1) - 1] }
    public func validate() throws {
        let partsOK = parts.allSatisfy { p in
            (1...8).contains(p.options.count) && p.options.indices.contains(p.answer) && (p.prompt?.count ?? 0) <= 400
                && p.options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }
        }
        let minOptions = type == .choice ? 2 : 1
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 1200,
              (1...12).contains(parts.count), partsOK, parts.allSatisfy({ $0.options.count >= minOptions }),
              type != .choice || options.count <= 6,
              (0...500).contains(reward), (explanation?.count ?? 0) <= 600, (passage?.count ?? 0) <= 4000,
              difficulty.map({ (1...3).contains($0) }) ?? true, seconds.map({ (10...600).contains($0) }) ?? true,
              (tags?.count ?? 0) <= 8, (tags ?? []).allSatisfy({ $0.count <= 30 }),
              (audience?.count ?? 0) <= 40, (portion?.count ?? 0) <= 20, (audience ?? []).allSatisfy({ $0.count <= 40 }) else {
            throw GameError("题目格式无效：「\(prompt.prefix(20))」")
        }
    }
}

/// One student's answer to one question, kept in the save for the answer report.
public struct QuizAttempt: Codable, Equatable {
    public var player: String
    /// Name at the time (the report keeps it even if renamed later).
    public var playerName: String
    public var node: Int
    /// Map node of the quiz spot; -1 when the teacher called the quiz up anywhere.
    public var question: Int
    /// Per graded item: the option the student said, nil = did not know / no answer.
    public var picks: [Int?]
    /// Per item: an answer outside the options, typed by the teacher ("其他").
    public var texts: [String?]
    public var correct: [Bool]
    public var seconds: Double
    public var limit: Int
    /// Seconds since 1970 when it was answered.
    public var at: Double
    public var coins: Int = 0
    public var score: Int = 0
    /// Item that dropped for a full, in-time answer.
    public var drop: String? = nil
    public var dropCount: Int? = nil
    /// Asked to the whole class (the teacher picked who answered and handed out the reward).
    public var shared: Bool? = nil
    /// Flash-card practice: recorded for the report, no reward.
    public var practice: Bool? = nil
    public var overtime: Bool { seconds > Double(limit) + 0.5 }
    public var rightCount: Int { correct.filter { $0 }.count }
    public init(player: String, playerName: String, node: Int, question: Int, picks: [Int?], texts: [String?], correct: [Bool], seconds: Double, limit: Int, at: Double) {
        self.player = player; self.playerName = playerName; self.node = node; self.question = question
        self.picks = picks; self.texts = texts; self.correct = correct; self.seconds = seconds; self.limit = limit; self.at = at
    }
}

/// Rewards by difficulty (index 0 = ★). Coins scale with the share answered right; a fully right answer in time also
/// rolls the difficulty's drop table, and one in under half the time pays half again in coins (questions without a
/// difficulty, from older banks, keep their plain fixed reward).
public enum QuizRewards {
    public static let baseCoins = [15, 30, 60]
    public static let baseSeconds = [60, 90, 120]
    private static func item(_ id: String, _ weight: Int, _ count: Int = 1) -> LotteryPrize { LotteryPrize(item: id, count: count, coins: 0, weight: weight) }
    private static let nothing = LotteryPrize(item: nil, count: 0, coins: 0, weight: 0)
    private static let setPieces = ["starlightBlade", "starlightArmor", "starlightCharm", "dragonFangSword", "dragonArmor", "dragonCharm"]
    public static let drops: [[LotteryPrize]] = [
        [LotteryPrize(item: nil, count: 0, coins: 0, weight: 50), item("smallPotion", 32), item("shieldPotion", 18)],
        [item("smallPotion", 22), item("largePotion", 22), item("shieldPotion", 18), item("revivalStone", 12), item("powerBadge", 10), item("leatherArmor", 8), item("huntingBow", 8)],
        [item("largePotion", 14, 2), item("revivalStone", 14), item("runeArmor", 14), item("greatSword", 12), item("actionRing", 12), item("powerBadge", 10), item("legendaryStaff", 6)]
            + setPieces.map { item($0, 3) },
    ]
    /// Coins for `right` of `total` parts; `fast` = all right in under half the time.
    public static func coins(full: Int, right: Int, total: Int, fast: Bool) -> Int {
        guard total > 0, right > 0 else { return 0 }
        let share = Int((Double(full) * Double(right) / Double(total)).rounded())
        return right == total && fast ? share + full / 2 : share
    }
}

/// What the campaign layer graded and wants recorded (the engine pays it and rolls the drop from the save's stream).
public struct QuizRecord: Codable, Equatable {
    public var attempt: QuizAttempt
    public var fullCoins: Int
    public var points: Int
    /// Drop table to roll (0…2) when everything was right in time; nil = none.
    public var dropTier: Int?
    /// Called up by the teacher anywhere (not at a quiz spot on the map): nothing about the map changes.
    public var free: Bool? = nil
    /// Shared-bank questions: the coins the teacher chose to send (the reward or the participation prize); no drop.
    public var manualCoins: Int? = nil
    public init(attempt: QuizAttempt, fullCoins: Int, points: Int, dropTier: Int?, free: Bool = false, manualCoins: Int? = nil) {
        self.attempt = attempt; self.fullCoins = fullCoins; self.points = points; self.dropTier = dropTier; self.free = free ? true : nil; self.manualCoins = manualCoins
    }
}

extension Evaluation {
    /// A quiz event (it takes the place of the roadside find): marks the event done and pays the class's reward for a
    /// right answer. The campaign layer checks the chosen option against its question bank. (Kept for old histories.)
    mutating func answerCampaignQuiz(actor id: String, correct: Bool, coins: Int) throws {
        var (actor, index, kind) = try siteActor(id)
        guard kind == .satchel, state.map.nodes[index].siteResolved != true else { throw GameError("该事件已结束。") }
        guard (0...200).contains(coins), correct || coins == 0 else { throw GameError("答题奖励无效。") }
        if correct, coins > 0 { actor.coins = try checkedAdd(actor.coins, coins) }
        if correct { actor.score = try checkedAdd(actor.score, 1) }
        state.units[id] = actor; state.map.nodes[index].siteResolved = true
        events.append(GameEvent("campaignQuiz", actor: id, amount: coins, detail: "\(actor.nodeID):\(correct ? "correct" : "wrong")"))
    }

    /// One student's answer at a quiz event. Each player present answers once; the event closes when every living
    /// teammate there has answered.
    mutating func recordCampaignQuiz(_ record: QuizRecord) throws {
        var attempt = record.attempt
        let free = record.free == true
        var actor: GameUnit, index = -1
        let log = state.quizLog ?? []
        if free {
            guard let unit = state.units[attempt.player], unit.kind == .player else { throw GameError("答题成员无效。") }
            actor = unit
        } else {
            let site = try siteActor(attempt.player)
            actor = site.0; index = site.1
            guard site.2 == .satchel, state.map.nodes[index].siteResolved != true else { throw GameError("该事件已结束。") }
            guard !log.contains(where: { $0.player == actor.id && $0.node == actor.nodeID }) else { throw GameError("\(actor.shortName) 已在这里答过题。") }
        }
        let n = attempt.correct.count
        guard attempt.node == (free ? -1 : actor.nodeID), (1...12).contains(n), attempt.picks.count == n, attempt.texts.count == n,
              attempt.seconds.isFinite, attempt.seconds >= 0, (10...600).contains(attempt.limit), attempt.question >= 0,
              (0...500).contains(record.fullCoins), (0...3).contains(record.points), (record.manualCoins ?? 0) >= 0, (record.manualCoins ?? 0) <= 1000,
              record.dropTier.map({ QuizRewards.drops.indices.contains($0) }) ?? true,
              attempt.texts.allSatisfy({ ($0?.count ?? 0) <= 120 }), log.count < 5000 else { throw GameError("答题记录无效。") }
        let right = attempt.rightCount, intime = !attempt.overtime
        if attempt.practice == true {
            attempt.coins = 0; attempt.score = 0
        } else if let manual = record.manualCoins {
            attempt.coins = manual; attempt.score = right == n ? record.points : 0
        } else {
            attempt.coins = intime ? QuizRewards.coins(full: record.fullCoins, right: right, total: n, fast: record.dropTier != nil && attempt.seconds * 2 <= Double(attempt.limit)) : 0
            attempt.score = intime && right == n ? record.points : 0
        }
        if attempt.practice != true, record.manualCoins == nil, intime, right == n, let tier = record.dropTier {
            let table = QuizRewards.drops[tier]
            for prize in table { if let item = prize.item { _ = try catalog.item(item) } }
            var roll = try state.random.next(upperBound: table.reduce(0) { $0 + $1.weight }) - 1
            var picked = table.count - 1
            for (i, prize) in table.enumerated() { if roll < prize.weight { picked = i; break }; roll -= prize.weight }
            if let item = table[picked].item {
                actor.inventory[item] = try checkedAdd(actor.inventory[item] ?? 0, table[picked].count)
                attempt.drop = item; attempt.dropCount = table[picked].count
            }
        }
        actor.coins = try checkedAdd(actor.coins, attempt.coins)
        actor.score = try checkedAdd(actor.score, attempt.score)
        attempt.playerName = actor.shortName
        state.units[actor.id] = actor
        state.quizLog = log + [attempt]
        if !free {
            let answered = Set(state.quizLog!.filter { $0.node == actor.nodeID }.map(\.player))
            let present = state.players.filter { $0.isAlive && $0.nodeID == actor.nodeID && $0.teamID == actor.teamID }.map(\.id)
            if present.allSatisfy(answered.contains) { state.map.nodes[index].siteResolved = true }
        }
        events.append(GameEvent("campaignQuiz", actor: actor.id, amount: attempt.coins, detail: "\(free ? "free" : String(actor.nodeID)):\(right)/\(n)\(attempt.drop.map { ":" + $0 } ?? "")"))
    }
}
