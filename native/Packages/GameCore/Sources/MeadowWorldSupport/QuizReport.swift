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
        /// Per answer: the word it tests (flash cards, blanks, questions tagged 单词/词汇), nil otherwise.
        public var words: [Word?] = []
    }
    /// A vocabulary item: the word and, for flash cards, its meaning.
    public struct Word: Hashable {
        public var word: String
        public var meaning: String?
    }
    /// A word a student got wrong: what they said, how often.
    public struct WordMiss: Equatable {
        public var word: String
        public var meaning: String?
        public var said: [String]
        public var count: Int
    }
    /// A word across the class: how many times it was asked and missed, and the most common wrong answer.
    public struct WordStat: Equatable {
        public var word: String
        public var meaning: String?
        public var asked: Int
        public var wrong: Int
        public var students: [String]
        public var commonWrong: String?
    }
    /// One flash card in a student's deck (shared cards and all of their own), whether asked or not.
    public struct VocabItem: Equatable {
        public enum Status: Equatable { case right, wrong, corrected, untested }
        public var word: String
        public var meaning: String?
        public var status: Status
        public var tries: Int
    }
    /// Said instead of an answer: never listed as "常说成 …".
    public static let nonAnswers: Set<String> = ["不会", "未作答", "答错"]
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
        /// Words still missed (their latest answer was wrong), most often first (then in the order met).
        public var wrongWords: [WordMiss] = []
        /// Words missed earlier and answered right since (已改正).
        public var correctedWords: [WordMiss] = []
        public var wordsAsked: Int = 0
        /// Every flash card of the student's deck (shared + their portions), in bank order, with its status.
        public var vocabulary: [VocabItem] = []
        /// Questions still wrong: one line per question (its latest wrong answer), when the latest answer to it
        /// was not all right.
        public var mistakes: [Line] {
            var latest: [Int: Line] = [:], order: [Int] = []
            for l in lines { if latest[l.attempt.question] == nil { order.append(l.attempt.question) }; latest[l.attempt.question] = l }
            return order.compactMap { q in
                guard let last = latest[q], last.attempt.rightCount < last.attempt.correct.count else { return nil }
                return last
            }
        }
        /// Questions answered wrong earlier and all right later (已改正): the earlier wrong line, to show what was said.
        public var corrected: [Line] {
            var firstWrong: [Int: Line] = [:], order: [Int] = [], latestRight: [Int: Bool] = [:]
            for l in lines {
                let right = l.attempt.rightCount == l.attempt.correct.count
                if !right && firstWrong[l.attempt.question] == nil { firstWrong[l.attempt.question] = l; order.append(l.attempt.question) }
                latestRight[l.attempt.question] = right
            }
            return order.compactMap { latestRight[$0] == true ? firstWrong[$0] : nil }
        }
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
    /// Words anyone missed, most missed first.
    public var words: [WordStat] = []
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
    /// `decks`: per player, the bank indices of their flash cards (listed in the report even when never asked).
    public init(log: [QuizAttempt], bank: [QuizQuestion], order: [String] = [], names: [String: String] = [:], decks: [String: [Int]] = [:]) {
        func line(_ a: QuizAttempt) -> Line? {
            guard bank.indices.contains(a.question) else { return nil }
            let q = bank[a.question], parts = q.parts
            guard parts.count == a.correct.count else { return nil }
            let answers = parts.indices.map { i -> Answer in
                let part = parts[i]
                let said = a.skipped == true ? "未作答" : a.picks[i].flatMap { part.options.indices.contains($0) ? part.options[$0] : nil } ?? a.texts[i] ?? (q.type == .flashcard ? "答错" : "不会")
                let label: String
                switch q.type {
                case .choice: label = "答案"
                case .flashcard: label = "背面"
                case .fill: label = "第\(i + 1)空"
                case .reading: label = "\(i + 1). " + (part.prompt ?? "")
                }
                return Answer(label: label, said: said, expected: part.options[part.answer], right: a.correct[i])
            }
            return Line(attempt: a, question: q, summary: Self.summary(q), answers: answers, words: parts.indices.map { Self.word(q, part: $0) })
        }
        let lines = log.compactMap(line)
        let ids = Array(Set(lines.map(\.attempt.player)).union(decks.filter { !$0.value.isEmpty }.keys)).sorted { a, b in
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
            var misses: [WordMiss] = [], fixed = Set<String>()
            for l in own { for (i, w) in l.words.enumerated() {
                guard let w else { continue }
                s.wordsAsked += 1
                // A right answer after misses: the word counts as corrected (until it is missed again).
                guard !l.answers[i].right else { if misses.contains(where: { $0.word == w.word }) { fixed.insert(w.word) }; continue }
                fixed.remove(w.word)
                let said = Self.nonAnswers.contains(l.answers[i].said) ? [] : [l.answers[i].said]
                if let k = misses.firstIndex(where: { $0.word == w.word }) { misses[k].count += 1; for x in said where !misses[k].said.contains(x) { misses[k].said.append(x) } }
                else { misses.append(WordMiss(word: w.word, meaning: w.meaning, said: said, count: 1)) }
            } }
            let ranked = misses.enumerated().sorted { $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count }.map(\.element)
            s.wrongWords = ranked.filter { !fixed.contains($0.word) }
            s.correctedWords = misses.filter { fixed.contains($0.word) }
            // The whole deck: each card's latest answer (wrong before and right now = corrected), or not asked yet.
            s.vocabulary = (decks[id] ?? []).compactMap { qi in
                guard bank.indices.contains(qi), let w = Self.word(bank[qi], part: 0) else { return nil }
                let tries = own.filter { $0.attempt.question == qi }
                guard let last = tries.last else { return VocabItem(word: w.word, meaning: w.meaning, status: .untested, tries: 0) }
                let right = last.attempt.rightCount == last.attempt.correct.count
                let everWrong = tries.contains { $0.attempt.rightCount < $0.attempt.correct.count }
                return VocabItem(word: w.word, meaning: w.meaning, status: right ? (everWrong ? .corrected : .right) : .wrong, tries: tries.count)
            }
            return s
        }
        var stats: [Int: QuestionStat] = [:], wrongs: [Int: [String: Int]] = [:]
        for l in lines {
            let i = l.attempt.question
            if stats[i] == nil { stats[i] = QuestionStat(index: i, question: l.question, summary: l.summary, attempts: 0, right: 0, total: 0) }
            stats[i]!.attempts += 1; stats[i]!.right += l.attempt.rightCount; stats[i]!.total += l.attempt.correct.count
            for a in l.answers where !a.right && !Self.nonAnswers.contains(a.said) { wrongs[i, default: [:]][(l.answers.count > 1 ? a.label + "：" : "") + a.said, default: 0] += 1 }
        }
        for (i, w) in wrongs { if let top = w.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) { stats[i]!.commonWrong = (top.key, top.value) } }
        var wordStats: [String: WordStat] = [:], wordOrder: [String] = [], said: [String: [String: Int]] = [:]
        for l in lines { for (i, w) in l.words.enumerated() {
            guard let w else { continue }
            if wordStats[w.word] == nil { wordStats[w.word] = WordStat(word: w.word, meaning: w.meaning, asked: 0, wrong: 0, students: []); wordOrder.append(w.word) }
            wordStats[w.word]!.asked += 1
            guard !l.answers[i].right else { continue }
            wordStats[w.word]!.wrong += 1
            let name = names[l.attempt.player] ?? l.attempt.playerName
            if !wordStats[w.word]!.students.contains(name) { wordStats[w.word]!.students.append(name) }
            if !Self.nonAnswers.contains(l.answers[i].said) { said[w.word, default: [:]][l.answers[i].said, default: 0] += 1 }
        } }
        for (word, counts) in said { wordStats[word]!.commonWrong = counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key }
        words = wordOrder.compactMap { wordStats[$0] }.filter { $0.wrong > 0 }.enumerated()
            .sorted { $0.element.wrong == $1.element.wrong ? $0.offset < $1.offset : $0.element.wrong > $1.element.wrong }.map(\.element)
        questions = stats.values.sorted { $0.rate == $1.rate ? $0.index < $1.index : $0.rate < $1.rate }
    }

    /// The word an answer tests: a flash card (the side in Latin letters is the word, the other its meaning), a blank
    /// (its right answer), or any question tagged 单词 / 词汇 / vocab (the right option).
    public static func word(_ q: QuizQuestion, part i: Int) -> Word? {
        let parts = q.parts
        guard parts.indices.contains(i) else { return nil }
        let expected = parts[i].options[parts[i].answer]
        switch q.type {
        case .flashcard:
            let latin = { (s: String) in s.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.isASCII } }
            return latin(q.prompt) || !latin(expected) ? Word(word: q.prompt, meaning: expected) : Word(word: expected, meaning: q.prompt)
        case .fill: return Word(word: expected, meaning: nil)
        case .choice, .reading:
            let tagged = (q.tags ?? []).contains { t in ["单词", "词汇", "生词", "vocab", "word"].contains { t.lowercased().contains($0) } }
            return tagged ? Word(word: expected, meaning: nil) : nil
        }
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
        return QuizReport(log: quizLog, bank: quizBank, order: players.map(\.id), names: Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.shortName) }),
                          decks: Dictionary(uniqueKeysWithValues: players.filter { !$0.host }.map { ($0.id, practiceDeck(for: $0.id)) }))
    }
}
