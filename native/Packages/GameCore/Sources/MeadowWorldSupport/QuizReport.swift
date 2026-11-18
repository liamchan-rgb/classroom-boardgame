import Foundation
import ClassroomGameCore

/// Answer report built from the quiz log: per student (accuracy by item, time, rewards, by kind / difficulty / tag,
/// the answers they got wrong) and per question (accuracy and the most common wrong answer).
public struct QuizReport {
    public struct Answer: Equatable {
        public var label: String
        /// What the student said ("不会" when nothing was recorded).
        public var said: String
        public var expected: String
        public var right: Bool
    }
    public struct Line {
        public var attempt: QuizAttempt
        public var question: QuizQuestion
        public var summary: String
        public var answers: [Answer]
    }
    public struct Tally: Equatable {
        public var name: String
        public var right: Int
        public var total: Int
        public var rate: Double { total == 0 ? 0 : Double(right) / Double(total) }
    }
    public struct Student {
        public var id: String
        public var name: String
        public var lines: [Line]
        public var right: Int { lines.reduce(0) { $0 + $1.attempt.rightCount } }
        public var total: Int { lines.reduce(0) { $0 + $1.attempt.correct.count } }
        public var rate: Double { total == 0 ? 0 : Double(right) / Double(total) }
        public var averageSeconds: Double { lines.isEmpty ? 0 : lines.reduce(0) { $0 + $1.attempt.seconds } / Double(lines.count) }
        public var coins: Int { lines.reduce(0) { $0 + $1.attempt.coins } }
        public var score: Int { lines.reduce(0) { $0 + $1.attempt.score } }
        public var drops: [String] { lines.compactMap(\.attempt.drop) }
        public var overtime: Int { lines.filter(\.attempt.overtime).count }
        public var byKind: [Tally] = []
        public var byDifficulty: [Tally] = []
        public var byTag: [Tally] = []
        /// Questions with at least one wrong part.
        public var mistakes: [Line] { lines.filter { $0.attempt.rightCount < $0.attempt.correct.count } }
    }
    public struct QuestionStat {
        public var index: Int
        public var question: QuizQuestion
        public var summary: String
        public var attempts: Int
        public var right: Int
        public var total: Int
        public var rate: Double { total == 0 ? 0 : Double(right) / Double(total) }
        /// The wrong answer said most often, and how many times.
        public var commonWrong: (said: String, count: Int)?
    }
    public var students: [Student]
    /// Hardest first.
    public var questions: [QuestionStat]
    public var attempts: Int { students.reduce(0) { $0 + $1.lines.count } }
    public var right: Int { students.reduce(0) { $0 + $1.right } }
    public var total: Int { students.reduce(0) { $0 + $1.total } }
    public var rate: Double { total == 0 ? 0 : Double(right) / Double(total) }
    public var coins: Int { students.reduce(0) { $0 + $1.coins } }
    public var drops: Int { students.reduce(0) { $0 + $1.drops.count } }
    public var averageSeconds: Double { attempts == 0 ? 0 : students.reduce(0) { $0 + $1.lines.reduce(0) { $0 + $1.attempt.seconds } } / Double(attempts) }
    public var first: Date? { students.flatMap(\.lines).map { Date(timeIntervalSince1970: $0.attempt.at) }.min() }
    public var last: Date? { students.flatMap(\.lines).map { Date(timeIntervalSince1970: $0.attempt.at) }.max() }

    /// `order`: player ids in seat order (others follow by id); `names`: current names, else the name at answer time.
    public init(log: [QuizAttempt], bank: [QuizQuestion], order: [String] = [], names: [String: String] = [:]) {
        func line(_ a: QuizAttempt) -> Line? {
            guard bank.indices.contains(a.question) else { return nil }
            let q = bank[a.question], parts = q.parts
            guard parts.count == a.correct.count else { return nil }
            let answers = parts.indices.map { i -> Answer in
                let part = parts[i]
                let said = a.picks[i].flatMap { part.options.indices.contains($0) ? part.options[$0] : nil } ?? a.texts[i] ?? "不会"
                let label: String
                switch q.type {
                case .choice: label = "答案"
                case .flashcard: label = "背面"
                case .fill: label = "第\(i + 1)空"
                case .reading: label = "\(i + 1). " + (part.prompt ?? "")
                }
                return Answer(label: label, said: said, expected: part.options[part.answer], right: a.correct[i])
            }
            return Line(attempt: a, question: q, summary: Self.summary(q), answers: answers)
        }
        let lines = log.compactMap(line)
        let ids = Array(Set(lines.map(\.attempt.player))).sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max, ib = order.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }
        func tallies(_ ls: [Line], keys: (Line) -> [String]) -> [Tally] {
            var map: [String: Tally] = [:], seen: [String] = []
            for l in ls { for k in keys(l) {
                if map[k] == nil { map[k] = Tally(name: k, right: 0, total: 0); seen.append(k) }
                map[k]!.right += l.attempt.rightCount; map[k]!.total += l.attempt.correct.count
            } }
            return seen.map { map[$0]! }
        }
        students = ids.map { id in
            let own = lines.filter { $0.attempt.player == id }
            var s = Student(id: id, name: names[id] ?? own.last?.attempt.playerName ?? id, lines: own)
            s.byKind = tallies(own) { [$0.question.type.title] }
            s.byDifficulty = tallies(own) { [$0.question.difficulty.map { String(repeating: "★", count: $0) } ?? "未分级"] }.sorted { $0.name < $1.name }
            s.byTag = tallies(own) { $0.question.tags ?? [] }
            return s
        }
        var stats: [Int: QuestionStat] = [:], wrongs: [Int: [String: Int]] = [:]
        for l in lines {
            let i = l.attempt.question
            if stats[i] == nil { stats[i] = QuestionStat(index: i, question: l.question, summary: l.summary, attempts: 0, right: 0, total: 0) }
            stats[i]!.attempts += 1; stats[i]!.right += l.attempt.rightCount; stats[i]!.total += l.attempt.correct.count
            for a in l.answers where !a.right { wrongs[i, default: [:]][(l.answers.count > 1 ? a.label + "：" : "") + a.said, default: 0] += 1 }
        }
        for (i, w) in wrongs { if let top = w.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) { stats[i]!.commonWrong = (top.key, top.value) } }
        questions = stats.values.sorted { $0.rate == $1.rate ? $0.index < $1.index : $0.rate < $1.rate }
    }

    /// One line naming a question in the report.
    public static func summary(_ q: QuizQuestion) -> String {
        switch q.type {
        case .choice: return q.prompt
        case .flashcard: return "闪卡：" + q.prompt
        case .fill: return q.prompt.replacingOccurrences(of: #"\{\{(\d+)\}\}"#, with: "（$1）", options: .regularExpression)
        case .reading: return "阅读：" + (q.passage ?? q.prompt).prefix(40) + ((q.passage?.count ?? 0) > 40 ? "…" : "")
        }
    }
}

public extension MeadowCampaignSession {
    var quizReport: QuizReport {
        let players = engine.state.players
        return QuizReport(log: quizLog, bank: quizBank, order: players.map(\.id), names: Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.shortName) }))
    }
}
