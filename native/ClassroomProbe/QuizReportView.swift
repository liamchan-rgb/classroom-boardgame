import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Look

private enum Ink {
    static let page = Color(red: 0.975, green: 0.985, blue: 0.99)
    static let ink = Color(red: 0.09, green: 0.25, blue: 0.31)
    static let muted = Color(red: 0.36, green: 0.47, blue: 0.52)
    static let line = Color(red: 0.86, green: 0.91, blue: 0.93)
    static let teal = Color(red: 0.09, green: 0.42, blue: 0.53)
    static let sea = Color(red: 0.16, green: 0.60, blue: 0.58)
    static let gold = Color(red: 0.80, green: 0.58, blue: 0.16)
    static let good = Color(red: 0.20, green: 0.62, blue: 0.40)
    static let mid = Color(red: 0.88, green: 0.60, blue: 0.16)
    static let bad = Color(red: 0.82, green: 0.30, blue: 0.30)
    static func rate(_ r: Double) -> Color { r >= 0.8 ? good : r >= 0.6 ? mid : bad }
    static let avatars: [Color] = [Color(red: 0.36, green: 0.72, blue: 0.52), Color(red: 0.42, green: 0.62, blue: 0.95), Color(red: 0.95, green: 0.62, blue: 0.36),
                                   Color(red: 0.78, green: 0.52, blue: 0.92), Color(red: 0.92, green: 0.70, blue: 0.30), Color(red: 0.40, green: 0.78, blue: 0.85), Color(red: 0.92, green: 0.50, blue: 0.55)]
}
private func percent(_ r: Double) -> String { "\(Int((r * 100).rounded()))%" }
/// The letter on a student's badge: the given name for Chinese names (小明 → 明), else the first letter.
func quizInitial(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard let last = trimmed.last else { return "?" }
    if trimmed.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains($0.value) }), trimmed.count >= 2 { return String(last) }
    return String(trimmed.prefix(1)).uppercased()
}
private func seconds(_ s: Double) -> String { s >= 60 ? String(format: "%d分%02d秒", Int(s) / 60, Int(s) % 60) : "\(Int(s.rounded()))秒" }

/// A4 portrait in points.
private let pageSize = CGSize(width: 595, height: 842)

// MARK: - Fitting chips on a page

/// Measures chips the way the page draws them, so a section only shows as many as fit its lines (the page never
/// overflows, however long the sentences or however many the answers).
enum ChipFit {
    static func text(_ s: String, _ size: CGFloat, _ weight: UIFont.Weight) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]).width * 1.08
    }
    /// How many of `widths` (in order) fit in `rows` lines `line` wide, and how many lines they take.
    /// A chip wider than the line wraps its text over as many lines as it needs (nothing is cut).
    static func fit(_ widths: [CGFloat], line: CGFloat, spacing: CGFloat, rows: Int) -> (count: Int, rows: Int) {
        guard !widths.isEmpty, rows > 0 else { return (0, 0) }
        var done = 0, x: CGFloat = 0, n = 0
        for w in widths {
            if w > line {
                let total = done + (x > 0 ? 1 : 0) + Int((w / line).rounded(.up))
                if total > rows { break }
                done = total; x = 0
            } else if x == 0 {
                if done + 1 > rows { break }
                x = w
            } else if x + spacing + w <= line {
                x += spacing + w
            } else {
                if done + 2 > rows { break }
                done += 1; x = w
            }
            n += 1
        }
        return (n, done + (x > 0 ? 1 : 0))
    }
    /// Height of `s` wrapped to `width` (the rounded design runs a little wider than the system font).
    static func height(_ s: String, _ size: CGFloat, _ weight: UIFont.Weight, width: CGFloat) -> CGFloat {
        let r = (s as NSString).boundingRect(with: CGSize(width: width / 1.08, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin],
                                             attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)], context: nil)
        return ceil(r.height * 1.02)
    }
    static let line: CGFloat = 510
    static func plainChip(_ t: String) -> CGFloat { text(t, 9, .heavy) + 12 }
    static func vocabChip(_ w: QuizReport.VocabItem, small: Bool) -> CGFloat { text(w.word, small ? 7 : 8, .bold) + 18 }
    static func classChip(_ w: QuizReport.WordStat) -> CGFloat {
        text(w.word, 12, .heavy) + (w.meaning.map { text($0, 9, .semibold) + 4 } ?? 0) + text("错\(w.wrong)/\(w.asked)", 8, .heavy) + 20
    }

    // The class flash-card list: number, front, back; rows as tall as their text.
    static let cardFront: CGFloat = 264, cardBack: CGFloat = 170
    static func cardRow(_ c: QuizReport.CardStat) -> CGFloat {
        max(height(c.word, 9.5, .bold, width: cardFront), height(c.meaning ?? "", 9, .medium, width: cardBack)) + 7
    }
    /// The class flash-card list split into pages by the rows' real heights.
    static func cardPages(_ cards: [QuizReport.CardStat]) -> [Range<Int>] {
        let budget: CGFloat = 786 - 20 - 94 - 30 - 24
        var pages: [Range<Int>] = [], start = 0, used: CGFloat = 0
        for (i, c) in cards.enumerated() {
            let h = cardRow(c)
            if used + h > budget, i > start { pages.append(start..<i); start = i; used = 0 }
            used += h
        }
        if start < cards.count { pages.append(start..<cards.count) }
        return pages
    }

    // A student's 错题记录: every question still wrong, in full.
    static func mistakeAnswer(_ line: QuizReport.Line, tries: Int) -> AttributedString {
        let wrong = line.answers.filter { !$0.right }
        var said = AttributedString(wrong.first?.said ?? "")
        said.foregroundColor = Ink.bad
        if let w = wrong.first, !QuizReport.nonAnswers.contains(w.said) { said.strikethroughStyle = .single }
        var right = AttributedString("  →  " + wrong.map(\.expected).joined(separator: " / "))
        right.foregroundColor = Ink.good
        var tag = AttributedString(tries > 1 ? "  · 错\(tries)次" : "")
        tag.foregroundColor = Ink.muted
        return said + right + tag
    }
    static func mistakeHeight(_ line: QuizReport.Line, tries: Int) -> CGFloat {
        height(line.summary, 9, .bold, width: Self.line - 18) + height(String(mistakeAnswer(line, tries: tries).characters), 8, .heavy, width: Self.line - 18) + 8
    }
}

// MARK: - Pages

/// Chips in lines; a chip longer than a line wraps its text instead of being cut.
struct WrapFlow: Layout {
    var spacing: CGFloat = 4
    private func sizes(_ subviews: Subviews, width: CGFloat) -> [CGSize] {
        subviews.map { s in
            let ideal = s.sizeThatFits(.unspecified)
            return ideal.width <= width ? ideal : s.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? ChipFit.line
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for size in sizes(subviews, width: width) {
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for (s, size) in zip(subviews, sizes(subviews, width: bounds.width)) {
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}

extension QuizReport.Student {
    /// How many times each question was answered wrong.
    var wrongTries: [Int: Int] {
        var n: [Int: Int] = [:]
        for l in lines where l.attempt.rightCount < l.attempt.correct.count { n[l.attempt.question, default: 0] += 1 }
        return n
    }
}

/// What one printed page shows.
enum QuizReportPage {
    case overview
    /// A student's summary: results, mistakes, corrected items and their whole flash-card list (page 1 of 2).
    case student(Int)
    /// A student's every answer, one line each, sized to fit one page (page 2 of 2).
    case studentHistory(Int)
    /// The class page's list of every flash card of the course.
    case cards(range: Range<Int>, first: Bool)

    /// Class page and the class flash-card list, then each student in at most two pages.
    static func plan(_ report: QuizReport) -> [QuizReportPage] {
        var pages: [QuizReportPage] = [.overview]
        for (k, r) in ChipFit.cardPages(report.cards).enumerated() { pages.append(.cards(range: r, first: k == 0)) }
        for (i, s) in report.students.enumerated() {
            pages.append(.student(i))
            if !s.lines.isEmpty || !s.vocabulary.isEmpty { pages.append(.studentHistory(i)) }
        }
        return pages
    }
}

struct QuizReportPageView: View {
    let report: QuizReport
    let page: QuizReportPage
    let title: String
    let number: Int
    let count: Int
    /// The lesson (course) the report is for: in the subtitle and the footer.
    var course: String? = nil
    var itemName: (String) -> String = { $0 }
    private var lesson: String { course ?? "课堂" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch page {
            case .overview: overview
            case .student(let i): student(report.students[i], index: i)
            case .studentHistory(let i): history(report.students[i], index: i)
            case .cards(let range, let first): classCards(range: range, first: first)
            }
            Spacer(minLength: 0)
            HStack {
                Text("\(lesson) · 课堂答题报告").font(.system(size: 8, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(number) / \(count)").font(.system(size: 8, weight: .bold, design: .rounded)).monospacedDigit()
            }.foregroundStyle(Ink.muted)
        }
        .padding(28).frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .background(Ink.page).environment(\.colorScheme, .light)
    }

    private func banner(_ heading: String, _ sub: String, icon: String, avatar: (String, Color)? = nil) -> some View {
        HStack(spacing: 14) {
            if let avatar {
                Text(avatar.0).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 52, height: 52).background(Circle().fill(avatar.1)).overlay(Circle().stroke(.white, lineWidth: 2.5))
            } else {
                Image(systemName: icon).font(.system(size: 26, weight: .bold)).foregroundStyle(.white).frame(width: 52, height: 52)
                    .background(Circle().fill(.white.opacity(0.18)))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(heading).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(sub).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "leaf.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.15)).rotationEffect(.degrees(-20))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Ink.teal, Ink.sea], startPoint: .leading, endPoint: .trailing)))
    }
    private func tile(_ value: String, _ label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon).font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.muted)
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(tint).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Ink.line, lineWidth: 0.8))
    }
    private func ring(_ rate: Double, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Ink.line, lineWidth: size * 0.12)
            Circle().trim(from: 0, to: rate).stroke(Ink.rate(rate), style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(percent(rate)).font(.system(size: size * 0.24, weight: .heavy, design: .rounded)).foregroundStyle(Ink.ink)
                Text("正确率").font(.system(size: size * 0.09, weight: .bold, design: .rounded)).foregroundStyle(Ink.muted)
            }
        }.frame(width: size, height: size)
    }
    private func section(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Ink.ink)
    }
    private func bar(_ t: QuizReport.Tally) -> some View {
        HStack(spacing: 8) {
            Text(t.name).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink).frame(width: 64, alignment: .leading).lineLimit(1).minimumScaleFactor(0.6)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.line)
                    if t.right > 0 { Capsule().fill(Ink.rate(t.rate)).frame(width: max(6, g.size.width * t.rate)) }
                }
            }.frame(height: 8)
            Text("\(percent(t.rate))  \(t.right)/\(t.total)").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted).monospacedDigit().frame(width: 62, alignment: .trailing)
        }
    }
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line, lineWidth: 0.8))
    }
    private func dateRange() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy年M月d日 HH:mm"
        guard let a = report.first, let b = report.last else { return "" }
        let day = DateFormatter(); day.locale = f.locale; day.dateFormat = "HH:mm"
        return Calendar.current.isDate(a, inSameDayAs: b) ? f.string(from: a) + "–" + day.string(from: b) : f.string(from: a) + " 至 " + f.string(from: b)
    }

    // MARK: Class page

    /// Class page budget (points): what the banner, figures, the students' table and the hardest questions take,
    /// and how many lines of 易错题 chips are left.
    private var hardestRows: Int { report.words.isEmpty ? 6 : (report.students.count > 4 ? 3 : 4) }
    private var classWordRows: Int {
        let used: CGFloat = 80 + 128 + (44 + CGFloat(report.students.count) * 27) + (36 + CGFloat(min(hardestRows, report.questions.count)) * 34) + 4 * 14 + 40
        // One line in hand: the table and questions measured a little taller than estimated in the stress test.
        return max(1, Int((786 - 20 - used) / 38) - 2)
    }
    @ViewBuilder private var overview: some View {
        banner(title, "\(course.map { $0 + " · " } ?? "")\(dateRange()) · \(report.students.count) 位同学 · \(report.attempts) 次作答", icon: "chart.bar.doc.horizontal")
        HStack(spacing: 10) {
            ring(report.rate, size: 86).padding(.horizontal, 6)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    tile("\(report.attempts)", "作答次数", icon: "pencil.and.list.clipboard", tint: Ink.ink)
                    tile("\(report.right)/\(report.total)", "答对小题", icon: "checkmark.circle", tint: Ink.rate(report.rate))
                }
                tile(seconds(report.averageSeconds), "平均用时", icon: "timer", tint: Ink.teal)
            }
        }
        card {
            section("每位同学", icon: "person.3.fill")
            HStack {
                Text("同学").frame(maxWidth: .infinity, alignment: .leading)
                Text("题数").frame(width: 34); Text("正确率").frame(width: 150, alignment: .leading); Text("平均用时").frame(width: 56); Text("积分").frame(width: 40)
            }.font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.muted)
            ForEach(Array(report.students.enumerated()), id: \.offset) { i, s in
                HStack {
                    HStack(spacing: 6) {
                        Text(quizInitial(s.name)).font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(Circle().fill(Ink.avatars[i % Ink.avatars.count]))
                        Text(s.name).font(.system(size: 10.5, weight: .bold, design: .rounded)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(s.lines.count)").frame(width: 34)
                    HStack(spacing: 6) {
                        GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Ink.line); if s.right > 0 { Capsule().fill(Ink.rate(s.rate)).frame(width: max(5, g.size.width * s.rate)) } } }.frame(height: 7)
                        Text(percent(s.rate)).font(.system(size: 9.5, weight: .heavy, design: .rounded)).foregroundStyle(Ink.rate(s.rate)).frame(width: 32, alignment: .trailing)
                    }.frame(width: 150)
                    Text(seconds(s.averageSeconds)).frame(width: 56)
                    Text("\(s.score)").foregroundStyle(Ink.teal).frame(width: 40)
                }.font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Ink.ink)
                if i < report.students.count - 1 { Divider().overlay(Ink.line) }
            }
        }
        card {
            section("最难的题目", icon: "flame.fill")
            ForEach(Array(report.questions.prefix(hardestRows).enumerated()), id: \.offset) { i, q in
                HStack(alignment: .top, spacing: 8) {
                    Text(percent(q.rate)).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 40, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(Ink.rate(q.rate)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(q.summary).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink).lineLimit(2)
                        HStack(spacing: 6) {
                            Text("\(q.question.type.title)\(q.question.difficulty.map { " " + String(repeating: "★", count: $0) } ?? "") · \(q.attempts) 人作答")
                            if let w = q.commonWrong, w.said != "答错" { Text("常见错答：\(w.said)（\(w.count)次）").foregroundStyle(Ink.bad) }
                        }.font(.system(size: 8.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted).lineLimit(1)
                    }
                }
                if i < min(hardestRows, report.questions.count) - 1 { Divider().overlay(Ink.line) }
            }
            if report.questions.isEmpty { Text("还没有作答记录").font(.system(size: 10)).foregroundStyle(Ink.muted) }
        }
        if !report.words.isEmpty {
            card {
                section("易错题（\(report.words.count)）", icon: "character.book.closed.fill")
                let shown = ChipFit.fit(report.words.map(ChipFit.classChip), line: ChipFit.line, spacing: 6, rows: classWordRows).count
                WrapFlow(spacing: 6) {
                    ForEach(Array(report.words.prefix(shown).enumerated()), id: \.offset) { _, w in
                        wordChip(w.word, meaning: w.meaning, count: w.wrong, of: w.asked, said: w.commonWrong.flatMap { $0 == "答错" ? nil : "常说成 \($0)" })
                    }
                }
                if report.words.count > shown { Text("另有 \(report.words.count - shown) 个，见各人错题记录").font(.system(size: 8.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted) }
            }
        }
    }

    // MARK: Student page

    @ViewBuilder private func student(_ s: QuizReport.Student, index: Int) -> some View {
        // Page 1 is measured so it never overflows: what is left after the figures goes to the 错题记录, in full.
        let fixed = s.correctedWords.map(\.word) + s.corrected.filter { $0.question.type != .flashcard }.map(\.summary)
        let fixedFit = ChipFit.fit(fixed.map(ChipFit.plainChip), line: ChipFit.line, spacing: 4, rows: 3)
        let bars = [s.byKind.count, s.byDifficulty.count, s.byTag.count].map { min(4, $0) }.max() ?? 0
        let used: CGFloat = 94 + 78 + (40 + CGFloat(bars) * 16 + 14) + (fixed.isEmpty ? 0 : 40 + CGFloat(fixedFit.rows) * 17 + (fixedFit.count < fixed.count ? 12 : 0) + 14) + 40 + 16
        let tries = s.wrongTries, mistakes = s.mistakes
        let shown: Int = {
            var left = 786 - 20 - used, n = 0
            for m in mistakes { let h = ChipFit.mistakeHeight(m, tries: tries[m.attempt.question] ?? 1); if h > left { break }; left -= h; n += 1 }
            return n
        }()
        banner(s.name + " 的答题报告", "\(dateRange()) · 作答 \(s.lines.count) 次" + (s.lines.isEmpty ? "" : "（逐条记录见下页）"),
               icon: "person", avatar: (quizInitial(s.name), Ink.avatars[index % Ink.avatars.count]))
        HStack(spacing: 10) {
            ring(s.rate, size: 64).padding(.horizontal, 4)
            tile("\(s.right)/\(s.total)", "答对小题", icon: "checkmark.circle", tint: Ink.rate(s.rate))
            tile(seconds(s.averageSeconds), s.overtime > 0 ? "平均用时 · 超时\(s.overtime)次" : "平均用时", icon: "timer", tint: Ink.teal)
        }
        HStack(alignment: .top, spacing: 8) {
            card { section("按题型", icon: "square.grid.2x2"); ForEach(s.byKind.prefix(4), id: \.name) { miniBar($0) } }
            card { section("按难度", icon: "star.leadinghalf.filled"); ForEach(s.byDifficulty.prefix(4), id: \.name) { miniBar($0) } }
            if !s.byTag.isEmpty { card { section("按知识点", icon: "tag"); ForEach(s.byTag.prefix(4), id: \.name) { miniBar($0) } } }
        }
        if !fixed.isEmpty {
            card {
                section("已改正（\(fixed.count)）", icon: "checkmark.seal.fill")
                WrapFlow(spacing: 4) { ForEach(Array(fixed.prefix(fixedFit.count).enumerated()), id: \.offset) { _, t in miniChip(t, note: nil, extra: nil, tint: Ink.good) } }
                if fixed.count > fixedFit.count { moreLine("另有 \(fixed.count - fixedFit.count) 个") }
            }
        }
        card {
            HStack {
                section("错题记录（\(mistakes.count)）", icon: "character.book.closed.fill")
                Spacer()
                if !mistakes.isEmpty { Text("红字为所答，绿字为正确答案").font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted) }
            }
            if mistakes.isEmpty { Label(s.corrected.isEmpty ? "全部答对，太棒了！" : "错题都已改正，太棒了！", systemImage: "sparkles").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Ink.good) }
            ForEach(Array(mistakes.prefix(shown).enumerated()), id: \.offset) { k, line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(k + 1)").font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(Ink.bad).frame(width: 14, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.summary).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink)
                        Text(ChipFit.mistakeAnswer(line, tries: tries[line.attempt.question] ?? 1)).font(.system(size: 8, weight: .heavy, design: .rounded))
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(.vertical, 2)
            }
            if mistakes.count > shown { moreLine("另有 \(mistakes.count - shown) 题，见下页作答记录（✗）") }
        }
    }
    /// The card list (page 2, above the answers): all of the student's cards, as many lines as it needs up to 14.
    @ViewBuilder private func vocabulary(_ s: QuizReport.Student, shown: Int) -> some View {
        let v = s.vocabulary
        let count = { (st: QuizReport.VocabItem.Status) in v.filter { $0.status == st }.count }
        card {
            HStack {
                section("闪卡掌握表（\(v.count)）", icon: "rectangle.stack.fill")
                Spacer()
                HStack(spacing: 8) {
                    legend("checkmark", "答对 \(count(.right))", Ink.good); legend("arrow.uturn.backward", "已改正 \(count(.corrected))", Ink.teal)
                    legend("xmark", "答错 \(count(.wrong))", Ink.bad); legend("circle.dashed", "未单独考察 \(count(.untested))", Ink.muted)
                }.font(.system(size: 7.5, weight: .semibold, design: .rounded))
            }
            WrapFlow(spacing: 3) { ForEach(Array(v.prefix(shown).enumerated()), id: \.offset) { _, w in vocabMini(w, small: v.count > 60) } }
            if v.count > shown { moreLine("另有 \(v.count - shown) 张，见课堂报告的闪卡总表") }
        }
    }
    /// A word to practise (class page): the word, its meaning, how often it was missed, and what was said instead.
    private func wordChip(_ word: String, meaning: String?, count: Int, of asked: Int?, said: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(word).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Ink.ink)
                if let meaning { Text(meaning).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted) }
                Text(asked.map { "错\(count)/\($0)" } ?? (count > 1 ? "×\(count)" : "")).font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(Ink.bad)
            }
            if let said { Text(said).font(.system(size: 7.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.bad.opacity(0.85)) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.bad.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Ink.bad.opacity(0.25), lineWidth: 0.6))
    }
    private func miniBar(_ t: QuizReport.Tally) -> some View {
        HStack(spacing: 4) {
            Text(t.name).font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(Ink.ink).lineLimit(1).frame(width: 46, alignment: .leading)
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Ink.line); if t.right > 0 { Capsule().fill(Ink.rate(t.rate)).frame(width: max(4, g.size.width * t.rate)) } } }.frame(height: 5)
            Text("\(t.right)/\(t.total)").font(.system(size: 7.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.muted).monospacedDigit().fixedSize()
        }.frame(height: 12)
    }
    /// A one-line chip; long sentences are cut, never wrapped.
    private func miniChip(_ text: String, note: String?, extra: String?, tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(text).font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Ink.ink)
            if let note { Text(note).font(.system(size: 7.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted) }
            if let extra { Text(extra).font(.system(size: 7.5, weight: .heavy, design: .rounded)).foregroundStyle(tint) }
        }
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.09)))
    }
    private func vocabMini(_ w: QuizReport.VocabItem, small: Bool) -> some View {
        let (icon, tint): (String, Color) = {
            switch w.status { case .right: return ("checkmark", Ink.good); case .corrected: return ("arrow.uturn.backward", Ink.teal); case .wrong: return ("xmark", Ink.bad); case .untested: return ("circle.dashed", Ink.muted) }
        }()
        return HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: small ? 5.5 : 6.5, weight: .heavy)).foregroundStyle(tint)
            Text(w.word).font(.system(size: small ? 7 : 8, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink)
        }
        .padding(.horizontal, 4).padding(.vertical, 1.5)
        .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(w.status == .untested ? 0.06 : 0.11)))
    }
    private func moreLine(_ text: String) -> some View {
        Text(text).font(.system(size: 7.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted)
    }
    private func legend(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 2) { Image(systemName: icon).foregroundStyle(tint); Text(text).foregroundStyle(Ink.muted) }
    }

    /// Page 2: every answer on one line; one column up to 42, else two; the lines shrink so all fit on this page.
    @ViewBuilder private func history(_ s: QuizReport.Student, index: Int) -> some View {
        let n = s.lines.count, columns = n <= 42 ? 1 : 2
        let rows = Int((Double(n) / Double(columns)).rounded(.up))
        // The card list first: its lines (at most 14) are measured, the answers share what is left of the page.
        let small = s.vocabulary.count > 60
        let fit = ChipFit.fit(s.vocabulary.map { ChipFit.vocabChip($0, small: small) }, line: ChipFit.line, spacing: 3, rows: 14)
        let vocabHeight: CGFloat = s.vocabulary.isEmpty ? 0 : 44 + CGFloat(fit.rows) * (small ? 14 : 16) + (fit.count < s.vocabulary.count ? 12 : 0) + 14
        let rowHeight = min(16, max(6, (786 - 20 - 40 - vocabHeight - 30) / CGFloat(max(1, rows))))
        HStack(spacing: 10) {
            Text(quizInitial(s.name)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Circle().fill(Ink.avatars[index % Ink.avatars.count]))
            Text(s.name + " · 作答记录").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Ink.ink)
            Text("共 \(n) 次，按时间先后 · ✓ 答对  ✗ 答错（红字为所答，绿字为正确答案）").font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted)
            Spacer()
        }
        if !s.vocabulary.isEmpty { vocabulary(s, shown: fit.count) }
        if n > 0 {
        card {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<columns, id: \.self) { c in
                    let lo = c * rows, hi = min(n, lo + rows)
                    VStack(alignment: .leading, spacing: 0) {
                        if lo < hi { ForEach(lo..<hi, id: \.self) { k in historyRow(s.lines[k], number: k + 1, wide: columns == 1, height: rowHeight) } }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        }
    }
    /// One answer on one line: number, ✓/✗, the question, what was said (→ the right answer), kind and time.
    private func historyRow(_ line: QuizReport.Line, number: Int, wide: Bool, height: CGFloat) -> some View {
        let a = line.attempt, right = a.rightCount == a.correct.count
        let wrong = line.answers.first { !$0.right }
        let f = max(5.5, min(8, height * 0.5))
        return HStack(spacing: 4) {
            Text("\(number)").font(.system(size: f - 1, weight: .heavy, design: .rounded)).foregroundStyle(Ink.muted).frame(width: 14, alignment: .trailing)
            Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: f)).foregroundStyle(right ? Ink.good : Ink.bad)
            Text(line.summary).font(.system(size: f, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 3)
            Group {
                if let wrong {
                    let none = QuizReport.nonAnswers.contains(wrong.said)
                    Text(wrong.said).strikethrough(!none, color: Ink.bad.opacity(0.6)).foregroundStyle(Ink.bad)
                    Text("→ " + wrong.expected).foregroundStyle(Ink.good)
                } else {
                    Text(line.answers.map(\.said).joined(separator: " / ")).foregroundStyle(Ink.good)
                }
            }.font(.system(size: f - 0.5, weight: .heavy, design: .rounded)).lineLimit(1).truncationMode(.tail).frame(maxWidth: wide ? 220 : 110, alignment: .trailing)
            Text((wide ? historyTag(a) + " · " : "") + timeText(a.at)).font(.system(size: f - 1.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted).lineLimit(1).fixedSize()
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 0.5) }
    }

    // MARK: Class flash-card list

    @ViewBuilder private func classCards(range: Range<Int>, first: Bool) -> some View {
        banner("闪卡总表" + (first ? "" : "（续）"), "本课闪卡 \(report.cards.count) 张 · 按难度排列", icon: "rectangle.stack.fill")
        card {
            HStack(spacing: 8) {
                Text("#").frame(width: 22, alignment: .trailing)
                Text("难度").frame(width: 28, alignment: .leading)
                Text("正面").frame(width: ChipFit.cardFront, alignment: .leading)
                Text("背面").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.muted)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(range), id: \.self) { k in
                    let c = report.cards[k]
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(k + 1)").font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(Ink.muted).monospacedDigit().frame(width: 22, alignment: .trailing)
                        Text(String(repeating: "★", count: max(1, min(3, c.difficulty)))).font(.system(size: 7.5, weight: .heavy)).foregroundStyle(Ink.mid).frame(width: 28, alignment: .leading)
                        Text(c.word).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink)
                            .frame(width: ChipFit.cardFront, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        Text(c.meaning ?? "").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(Ink.ink.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 0.5) }
                }
            }
        }
    }
    private func historyTag(_ a: QuizAttempt) -> String {
        if a.skipped == true { return "未作答" }
        if a.practice == true { return a.shared == true ? "全班闪卡" : "闪卡练习" }
        if a.shared == true { return "全班题" }
        return a.limit >= 600 ? "个人挑战" : "个人题"
    }
    private func timeText(_ at: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date(timeIntervalSince1970: at))
    }

    private func chip(_ label: String, _ text: String, _ tint: Color, strike: Bool) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 7.5, weight: .bold, design: .rounded)).opacity(0.75)
            Text(text).font(.system(size: 9.5, weight: .heavy, design: .rounded)).strikethrough(strike, color: tint.opacity(0.6)).lineLimit(1)
        }.foregroundStyle(tint).padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - Rendering and export

@MainActor enum QuizReportExport {
    static func pages(_ report: QuizReport, title: String, course: String? = nil, itemName: @escaping (String) -> String = { $0 }) -> [AnyView] {
        let plan = QuizReportPage.plan(report)
        return plan.enumerated().map { i, p in AnyView(QuizReportPageView(report: report, page: p, title: title, number: i + 1, count: plan.count, course: course, itemName: itemName)) }
    }
    /// Student report: one page per student who answered.
    static func studentPages(_ report: QuizReport, course: String?) -> [AnyView] {
        let students = report.students.enumerated().filter { !$0.element.lines.isEmpty }
        return students.enumerated().map { n, e in
            AnyView(StudentReportPage(sheet: StudentSheet(e.element, index: e.offset), course: course ?? "课堂", number: n + 1, count: students.count))
        }
    }
    static func studentPageNames(_ report: QuizReport) -> [String] { report.students.filter { !$0.lines.isEmpty }.map(\.name) }
    static func images(_ views: [AnyView], scale: CGFloat = 2) -> [UIImage] {
        views.compactMap { v in let r = ImageRenderer(content: v); r.scale = scale; return r.uiImage }
    }
    static func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quiz-report-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func stamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    /// One vector PDF, a page per view.
    /// "答题报告-<课程>-2026-11-19": the lesson in the file name, made safe for a file name.
    static func baseName(_ course: String?, kind: String = "答题报告") -> String {
        let safe = course.map { String($0.map { "/\\:*?\"<>|".contains($0) ? "-" : $0 }.prefix(60)) }
        return kind + "-" + (safe.map { $0 + "-" } ?? "") + stamp()
    }
    static func pdf(_ views: [AnyView], course: String? = nil, kind: String = "答题报告") throws -> URL {
        let url = try folder().appendingPathComponent(baseName(course, kind: kind) + ".pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for v in views {
            context.beginPDFPage(nil)
            ImageRenderer(content: v).render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
    static func pngs(_ images: [UIImage], names: [String], course: String? = nil, kind: String = "答题报告") throws -> [URL] {
        let dir = try folder()
        return try images.enumerated().map { i, image in
            let url = dir.appendingPathComponent(baseName(course, kind: kind) + String(format: "-%02d-", i + 1) + (names.indices.contains(i) ? names[i] : "") + ".png")
            guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url); return url
        }
    }
    static func pageNames(_ report: QuizReport) -> [String] {
        QuizReportPage.plan(report).map { p in
            switch p {
            case .overview: return "全班"
            case .student(let i): return report.students[i].name
            case .studentHistory(let i): return report.students[i].name + "-作答记录"
            case .cards(_, let first): return "闪卡总表" + (first ? "" : "-续")
            }
        }
    }
}

/// Teacher screen: the report pages as they will print, with PDF and picture export.
struct QuizReportScreen: View {
    let report: QuizReport
    let title: String
    var course: String? = nil
    var itemName: (String) -> String = { $0 }
    var onClose: () -> Void
    @State private var images: [UIImage] = []
    @State private var exporting: [URL] = []
    @State private var showExporter = false
    @State private var error: String?
    @State private var copied = false
    /// 学生报告 (one page per student, for families) or 完整报告 (the class pages and each student's two pages).
    @AppStorage("classroom.reportStudent") private var studentVersion = true
    private var views: [AnyView] {
        studentVersion ? QuizReportExport.studentPages(report, course: course) : QuizReportExport.pages(report, title: title, course: course, itemName: itemName)
    }
    private var kind: String { studentVersion ? "学习报告" : "答题报告" }
    /// Each student's wrong words as plain text (for a word list or a message to parents).
    private func copyWords() {
        let lines = report.students.filter { !$0.wrongWords.isEmpty }.map { s in
            s.name + "：" + s.wrongWords.map { w in w.word + (w.meaning.map { "（\($0)）" } ?? "") }.joined(separator: "、")
        }
        UIPasteboard.general.string = (["全班易错：" + report.words.map(\.word).joined(separator: "、")] + lines).joined(separator: "\n")
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Label("答题报告", systemImage: "chart.bar.doc.horizontal").font(.title2.bold())
                Picker("", selection: $studentVersion) { Text("学生报告").tag(true); Text("完整报告").tag(false) }
                    .pickerStyle(.segmented).frame(width: 190)
                Text("\(report.students.count) 位同学 · \(report.attempts) 次作答 · 共 \(images.count) 页").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { export(pdf: true) } label: { Label("导出 PDF", systemImage: "doc.richtext") }.buttonStyle(GlassIconButtonStyle(prominent: true)).disabled(report.attempts == 0)
                Button { export(pdf: false) } label: { Label("导出图片", systemImage: "photo.on.rectangle") }.buttonStyle(GlassIconButtonStyle()).disabled(report.attempts == 0)
                Button { copyWords() } label: { Label(copied ? "已复制" : "复制错词", systemImage: copied ? "checkmark" : "doc.on.doc") }.buttonStyle(GlassIconButtonStyle()).disabled(report.words.isEmpty)
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(GameTheme.muted)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if report.attempts == 0 {
                ContentUnavailableView("还没有作答记录", systemImage: "questionmark.bubble", description: Text("导入题库后，学生在地图答题点作答的记录会出现在这里。"))
            } else {
                GeometryReader { g in
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            ForEach(images.indices, id: \.self) { i in
                                Image(uiImage: images[i]).resizable().aspectRatio(pageSize, contentMode: .fit)
                                    .frame(width: min(g.size.width - 20, 620))
                                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(20).background(GlassBackdrop())
        .onAppear { images = QuizReportExport.images(views) }
        .onChange(of: studentVersion) { _, _ in images = QuizReportExport.images(views) }
        .sheet(isPresented: $showExporter) { ExportPicker(urls: exporting) { showExporter = false } }
    }
    private func export(pdf: Bool) {
        do {
            exporting = pdf ? [try QuizReportExport.pdf(views, course: course, kind: kind)]
                            : try QuizReportExport.pngs(images, names: studentVersion ? QuizReportExport.studentPageNames(report) : QuizReportExport.pageNames(report), course: course, kind: kind)
            error = nil; showExporter = true
        } catch { self.error = "导出失败：\(error.localizedDescription)" }
    }
}

/// System "save to Files / Finder" sheet for the exported files.
private struct ExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    var done: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done() }
    }
}

// MARK: - Student report (one page per student, for families)

/// What one student's page shows: how they did, this lesson's ★/★★ words grouped by how they went, and the
/// challenge sentences (★★★ questions) they did not get right.
struct StudentSheet {
    struct Sentence { var english: String; var chinese: String?; var said: String?; var kind: String }
    let name: String
    let index: Int
    let dates: String
    let rate: Double
    let right: Int
    let total: Int
    let levels: [(name: String, label: String, tally: QuizReport.Tally?)]
    let todo: [QuizReport.VocabItem]
    let improved: [QuizReport.VocabItem]
    let mastered: [QuizReport.VocabItem]
    let unrecorded: [QuizReport.VocabItem]
    let sentences: [Sentence]
    var words: Int { todo.count + improved.count + mastered.count + unrecorded.count }

    init(_ s: QuizReport.Student, index: Int) {
        name = s.name; self.index = index; rate = s.rate; right = s.right; total = s.total
        dates = Self.dates(s.lines.map(\.attempt.at))
        levels = [("★", "基础"), ("★★", "提高"), ("★★★", "挑战")].map { n, l in (n, l, s.byDifficulty.first { $0.name == n }) }
        // The lesson's words once each (a word on two cards: the one that needs the most attention).
        func rank(_ st: QuizReport.VocabItem.Status) -> Int { switch st { case .wrong: return 0; case .corrected: return 1; case .right: return 2; case .untested: return 3 } }
        var words: [QuizReport.VocabItem] = []
        for v in s.vocabulary {
            if let i = words.firstIndex(where: { $0.word.lowercased() == v.word.lowercased() }) {
                if rank(v.status) < rank(words[i].status) { words[i].status = v.status }
                words[i].difficulty = min(words[i].difficulty, v.difficulty)
            } else { words.append(v) }
        }
        var sentences: [Sentence] = []
        for line in s.mistakes {
            let q = line.question
            if q.type == .flashcard {
                guard let w = QuizReport.word(q, part: 0) else { continue }
                // A lesson word is already in the word groups; a sentence card goes to the sentences.
                if words.contains(where: { $0.word.lowercased() == w.word.lowercased() }) { continue }
                sentences.append(Sentence(english: w.word, chinese: w.meaning, said: nil, kind: "句子闪卡"))
                continue
            }
            let wrong = line.answers.indices.filter { !line.answers[$0].right }
            let missed = wrong.compactMap { line.words.indices.contains($0) ? line.words[$0] : nil }
            if !missed.isEmpty {
                // A word missed in a choice / fill-in question: it goes with the words to practise.
                for w in missed {
                    if let i = words.firstIndex(where: { $0.word.lowercased() == w.word.lowercased() }) { words[i].status = .wrong }
                    else { words.append(QuizReport.VocabItem(word: w.word, meaning: w.meaning, status: .wrong, tries: 1, difficulty: 0)) }
                }
                continue
            }
            let said = wrong.first.map { line.answers[$0].said }
            sentences.append(Sentence(english: line.summary, chinese: "正确：" + wrong.map { line.answers[$0].expected }.joined(separator: "、"),
                                      said: said.flatMap { QuizReport.nonAnswers.contains($0) ? nil : $0 }, kind: q.type.title))
        }
        todo = words.filter { $0.status == .wrong }
        improved = words.filter { $0.status == .corrected }
        mastered = words.filter { $0.status == .right }
        unrecorded = words.filter { $0.status == .untested }
        self.sentences = sentences
    }
    static func dates(_ times: [Double]) -> String {
        guard let a = times.min(), let b = times.max() else { return "" }
        let cal = Calendar.current, x = Date(timeIntervalSince1970: a), y = Date(timeIntervalSince1970: b)
        let (m1, d1) = (cal.component(.month, from: x), cal.component(.day, from: x)), (m2, d2) = (cal.component(.month, from: y), cal.component(.day, from: y))
        if m1 == m2 && d1 == d2 { return "\(m1)月\(d1)日" }
        return m1 == m2 ? "\(m1)月\(d1)–\(d2)日" : "\(m1)月\(d1)日–\(m2)月\(d2)日"
    }
    var praise: String { rate >= 0.9 ? "非常棒！" : rate >= 0.75 ? "掌握得不错。" : rate >= 0.6 ? "继续加油。" : "还需要多练习。" }
}

/// One student's page: plain words for a family, nothing about the game.
struct StudentReportPage: View {
    let sheet: StudentSheet
    let course: String
    let number: Int
    let count: Int
    private static let width: CGFloat = 595 - 56 - 28 - 20
    private static func chipWidth(_ v: QuizReport.VocabItem) -> CGFloat {
        ChipFit.text(v.word, 10, .heavy) + ChipFit.text(v.meaning ?? "", 9.5, .medium) + (v.difficulty > 0 ? CGFloat(v.difficulty) * 6 + 4 : 0) + 22
    }
    /// Lines of chips a group takes, and how many fit when the page is short of room.
    private static func rows(_ items: [QuizReport.VocabItem], max: Int = 99) -> (count: Int, rows: Int) {
        ChipFit.fit(items.map(chipWidth), line: width, spacing: 5, rows: max)
    }
    var body: some View {
        // Room left for the words and sentences once the top of the page is drawn; the unrecorded words give way
        // first, then the sentences.
        let budget: CGFloat = 842 - 56 - 84 - 96 - 36 - 22 - 4 * 10
        let groups = [sheet.todo, sheet.improved, sheet.mastered].filter { !$0.isEmpty }
        let fixed: CGFloat = 34 + CGFloat(groups.count) * 36 + groups.map { CGFloat(Self.rows($0).rows) * 24 }.reduce(0, +) + (sheet.todo.isEmpty ? 34 : 0)
        let sentenceRoom = budget - fixed - (sheet.unrecorded.isEmpty ? 0 : 36 + 24)
        let sentencesShown = min(sheet.sentences.count, max(0, Int((sentenceRoom - 40) / 34)))
        let laterRoom = budget - fixed - (sheet.sentences.isEmpty ? 0 : 44 + CGFloat(sentencesShown) * 34) - 36
        let later = Self.rows(sheet.unrecorded, max: max(1, Int(laterRoom / 24)))
        VStack(alignment: .leading, spacing: 10) {
            header
            summary
            HStack(spacing: 8) {
                ForEach(sheet.levels, id: \.name) { l in
                    HStack(spacing: 4) {
                        Text(l.name).foregroundStyle(Ink.gold)
                        Text(l.label)
                        if let t = l.tally { Text("\(t.right)/\(t.total)").fontWeight(.heavy) } else { Text("未出题").foregroundStyle(Ink.muted) }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(l.tally == nil ? Ink.muted : Ink.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.white)).overlay(Capsule().stroke(Ink.line, lineWidth: 0.8))
                }
            }
            box {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "books.vertical.fill").foregroundStyle(Ink.teal)
                    Text("本节课需要掌握的高频词").font(.system(size: 13, weight: .heavy, design: .rounded))
                    count(sheet.words, Ink.teal)
                    Spacer()
                    Text("★ 基础、★★ 提高难度的重点单词，按孩子这节课的表现分组").font(.system(size: 8, weight: .medium, design: .rounded)).foregroundStyle(Ink.muted)
                }
                if sheet.todo.isEmpty {
                    sub(icon: "party.popper.fill", title: "没有要再练的词", note: "", tint: Ink.good, items: [], shown: 0)
                } else {
                    sub(icon: "arrow.counterclockwise", title: "还要练", note: "答错了，在家可以多读几遍", tint: Ink.bad, items: sheet.todo, shown: sheet.todo.count)
                }
                if !sheet.improved.isEmpty { sub(icon: "chart.line.uptrend.xyaxis", title: "进步了", note: "先答错，后来答对了", tint: Ink.teal, items: sheet.improved, shown: sheet.improved.count) }
                if !sheet.mastered.isEmpty { sub(icon: "checkmark.seal.fill", title: "已掌握", note: "答对了，或在更难的句子里说对了", tint: Ink.good, items: sheet.mastered, shown: sheet.mastered.count) }
                if !sheet.unrecorded.isEmpty { sub(icon: "circle.dashed", title: "未记录到闪卡练习中的重点词", note: "课上学过，这节课还没有用闪卡单独考", tint: Ink.muted, items: sheet.unrecorded, shown: later.count) }
            }
            if !sheet.sentences.isEmpty {
                box {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "text.quote").foregroundStyle(Ink.bad)
                        Text("挑战失败的句子").font(.system(size: 13, weight: .heavy, design: .rounded))
                        count(sheet.sentences.count, Ink.bad)
                        Spacer()
                    }
                    ForEach(Array(sheet.sentences.prefix(sentencesShown).enumerated()), id: \.offset) { k, s in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(k + 1).").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Ink.muted)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.english).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink)
                                if let zh = s.chinese { Text(zh).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(Ink.muted) }
                                if let said = s.said { Text("孩子说成：\(said)").font(.system(size: 8.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.bad) }
                            }.fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            Text(s.kind).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(Ink.teal)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Ink.teal.opacity(0.1)))
                        }
                    }
                    if sheet.sentences.count > sentencesShown {
                        Text("另有 \(sheet.sentences.count - sentencesShown) 句").font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("\(course) · 学习报告 · \(number) / \(count)").font(.system(size: 8, weight: .semibold, design: .rounded)).monospacedDigit()
            }.foregroundStyle(Ink.muted)
        }
        .padding(28).frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .background(Ink.page).environment(\.colorScheme, .light)
    }
    private var header: some View {
        HStack(spacing: 14) {
            Text(quizInitial(sheet.name)).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .frame(width: 50, height: 50).background(Circle().fill(Ink.avatars[sheet.index % Ink.avatars.count])).overlay(Circle().stroke(.white, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(course).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(sheet.name) 的学习报告" + (sheet.dates.isEmpty ? "" : " · \(sheet.dates)")).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Ink.teal, Ink.sea], startPoint: .leading, endPoint: .trailing)))
    }
    private var summary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Ink.line, lineWidth: 8)
                Circle().trim(from: 0, to: sheet.rate).stroke(Ink.good, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((sheet.rate * 100).rounded()))%").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Ink.ink)
                    Text("答对").font(.system(size: 7.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted)
                }
            }.frame(width: 66, height: 66)
            Text(summaryText).font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(Ink.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line, lineWidth: 0.8))
    }
    private var summaryText: AttributedString {
        func plain(_ s: String) -> AttributedString { AttributedString(s) }
        func bold(_ s: String) -> AttributedString { var a = AttributedString(s); a.font = .system(size: 11.5, weight: .heavy, design: .rounded); a.foregroundColor = Ink.teal; return a }
        var t = plain("本课答对 ") + bold("\(sheet.right)/\(sheet.total)") + plain(" 题（\(Int((sheet.rate * 100).rounded()))%），\(sheet.praise)")
        t += plain("本节课 ") + bold("\(sheet.words)") + plain(" 个高频词中，已掌握 ") + bold("\(sheet.mastered.count + sheet.improved.count)") + plain(" 个")
        if !sheet.improved.isEmpty { t += plain("（其中 \(sheet.improved.count) 个是先错后对）") }
        if sheet.todo.isEmpty { t += plain("，没有需要再练的词。") }
        else {
            t += plain("，还要练 ") + bold("\(sheet.todo.count)") + plain(" 个：")
            t += plain(sheet.todo.prefix(4).map { $0.word + ($0.meaning.map { "（\($0)）" } ?? "") }.joined(separator: "、") + (sheet.todo.count > 4 ? "等" : "") + "。")
        }
        if !sheet.sentences.isEmpty { t += plain("另有 \(sheet.sentences.count) 个挑战句子没有答对。") }
        return t
    }
    private func count(_ n: Int, _ tint: Color) -> some View {
        Text("\(n)").font(.system(size: 8.5, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(tint))
    }
    private func box<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line, lineWidth: 0.8))
    }
    private func sub(icon: String, title: String, note: String, tint: Color, items: [QuizReport.VocabItem], shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                Text(title).font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundStyle(Ink.ink)
                if !items.isEmpty { count(items.count, tint) }
                Spacer()
                Text(note).font(.system(size: 7.5, weight: .medium, design: .rounded)).foregroundStyle(Ink.muted)
            }
            if !items.isEmpty {
                WrapFlow(spacing: 5) {
                    ForEach(Array(items.prefix(shown).enumerated()), id: \.offset) { _, v in
                        HStack(spacing: 2) {
                            if v.difficulty > 0 { Text(String(repeating: "★", count: v.difficulty)).font(.system(size: 6.5, weight: .heavy)).foregroundStyle(Ink.gold) }
                            Text(v.word).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(tint == Ink.muted ? Ink.muted : Ink.ink)
                            if let m = v.meaning { Text(m).font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(Ink.muted) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(tint == Ink.muted ? 0.08 : 0.1)))
                    }
                }
                if items.count > shown { Text("另有 \(items.count - shown) 个").font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted) }
            }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(tint.opacity(0.18), lineWidth: 0.7))
    }
}
