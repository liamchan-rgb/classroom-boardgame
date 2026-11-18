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

// MARK: - Pages

/// What one printed page shows.
enum QuizReportPage {
    case overview
    case student(Int, mistakes: Range<Int>, first: Bool)

    /// Class page, then each student; a long list of mistakes continues on extra pages.
    static func plan(_ report: QuizReport) -> [QuizReportPage] {
        var pages: [QuizReportPage] = [.overview]
        for (i, s) in report.students.enumerated() {
            let n = s.mistakes.count, firstCount = 5, more = 9
            pages.append(.student(i, mistakes: 0..<min(n, firstCount), first: true))
            var start = firstCount
            while start < n { pages.append(.student(i, mistakes: start..<min(n, start + more), first: false)); start += more }
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
    var itemName: (String) -> String = { $0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch page {
            case .overview: overview
            case .student(let i, let range, let first): student(report.students[i], index: i, mistakes: range, first: first)
            }
            Spacer(minLength: 0)
            HStack {
                Text("林间行旅 · 课堂答题报告").font(.system(size: 8, weight: .semibold, design: .rounded))
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

    @ViewBuilder private var overview: some View {
        banner(title, "\(dateRange()) · \(report.students.count) 位同学 · \(report.attempts) 次作答", icon: "chart.bar.doc.horizontal")
        HStack(spacing: 10) {
            ring(report.rate, size: 86).padding(.horizontal, 6)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    tile("\(report.attempts)", "作答次数", icon: "pencil.and.list.clipboard", tint: Ink.ink)
                    tile("\(report.right)/\(report.total)", "答对小题", icon: "checkmark.circle", tint: Ink.rate(report.rate))
                }
                HStack(spacing: 10) {
                    tile(seconds(report.averageSeconds), "平均用时", icon: "timer", tint: Ink.teal)
                    tile("\(report.coins)", "发出金币 · 掉落 \(report.drops)", icon: "bitcoinsign.circle", tint: Ink.gold)
                }
            }
        }
        card {
            section("每位同学", icon: "person.3.fill")
            HStack {
                Text("同学").frame(maxWidth: .infinity, alignment: .leading)
                Text("题数").frame(width: 34); Text("正确率").frame(width: 150, alignment: .leading); Text("平均用时").frame(width: 56); Text("金币").frame(width: 40); Text("积分").frame(width: 32)
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
                    Text("\(s.coins)").foregroundStyle(Ink.gold).frame(width: 40)
                    Text("\(s.score)").foregroundStyle(Ink.teal).frame(width: 32)
                }.font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Ink.ink)
                if i < report.students.count - 1 { Divider().overlay(Ink.line) }
            }
        }
        card {
            section("最难的题目", icon: "flame.fill")
            ForEach(Array(report.questions.prefix(6).enumerated()), id: \.offset) { i, q in
                HStack(alignment: .top, spacing: 8) {
                    Text(percent(q.rate)).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 40, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(Ink.rate(q.rate)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(q.summary).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink).lineLimit(2)
                        HStack(spacing: 6) {
                            Text("\(q.question.type.title)\(q.question.difficulty.map { " " + String(repeating: "★", count: $0) } ?? "") · \(q.attempts) 人作答")
                            if let w = q.commonWrong { Text("常见错答：\(w.said)（\(w.count)次）").foregroundStyle(Ink.bad) }
                        }.font(.system(size: 8.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted).lineLimit(1)
                    }
                }
                if i < min(6, report.questions.count) - 1 { Divider().overlay(Ink.line) }
            }
            if report.questions.isEmpty { Text("还没有作答记录").font(.system(size: 10)).foregroundStyle(Ink.muted) }
        }
    }

    // MARK: Student page

    @ViewBuilder private func student(_ s: QuizReport.Student, index: Int, mistakes range: Range<Int>, first: Bool) -> some View {
        banner(s.name + (first ? " 的答题报告" : " · 错题（续）"), "\(dateRange()) · 作答 \(s.lines.count) 题", icon: "person", avatar: (quizInitial(s.name), Ink.avatars[index % Ink.avatars.count]))
        if first {
            HStack(spacing: 10) {
                ring(s.rate, size: 86).padding(.horizontal, 6)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        tile("\(s.right)/\(s.total)", "答对小题", icon: "checkmark.circle", tint: Ink.rate(s.rate))
                        tile(seconds(s.averageSeconds), s.overtime > 0 ? "平均用时 · 超时\(s.overtime)次" : "平均用时", icon: "timer", tint: Ink.teal)
                    }
                    HStack(spacing: 10) {
                        tile("+\(s.coins)", "获得金币", icon: "bitcoinsign.circle", tint: Ink.gold)
                        tile("+\(s.score)", "获得积分", icon: "star.circle", tint: Ink.teal)
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                card { section("按题型", icon: "square.grid.2x2"); ForEach(s.byKind, id: \.name) { bar($0) } }
                card { section("按难度", icon: "star.leadinghalf.filled"); ForEach(s.byDifficulty, id: \.name) { bar($0) } }
            }
            if !s.drops.isEmpty {
                HStack(spacing: 6) {
                    Label("答题掉落", systemImage: "gift.fill").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Ink.gold)
                    ForEach(Array(s.drops.enumerated()), id: \.offset) { _, d in
                        Text(itemName(d)).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Ink.gold.opacity(0.15)))
                    }
                    Spacer()
                }
            }
            if !s.byTag.isEmpty {
                card { section("按知识点", icon: "tag"); ForEach(s.byTag.prefix(6), id: \.name) { bar($0) } }
            }
        }
        card {
            section(first ? "需要再练的题（\(s.mistakes.count)）" : "需要再练的题（续）", icon: "arrow.triangle.2.circlepath")
            if s.mistakes.isEmpty { Label("全部答对，太棒了！", systemImage: "sparkles").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Ink.good) }
            ForEach(Array(range), id: \.self) { i in
                let line = s.mistakes[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(line.summary).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Ink.ink).lineLimit(2)
                        Spacer(minLength: 6)
                        Text("\(line.question.type.title) · \(seconds(line.attempt.seconds))\(line.attempt.overtime ? " · 超时" : "")")
                            .font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted)
                    }
                    ForEach(Array(line.answers.enumerated()).filter { !$0.element.right }.prefix(4), id: \.offset) { _, a in
                        HStack(spacing: 6) {
                            if line.answers.count > 1 { Text(a.label).font(.system(size: 8.5, weight: .semibold, design: .rounded)).foregroundStyle(Ink.muted).lineLimit(1).frame(maxWidth: 150, alignment: .leading) }
                            chip("说的", a.said, Ink.bad, strike: true)
                            Image(systemName: "arrow.right").font(.system(size: 7, weight: .bold)).foregroundStyle(Ink.muted)
                            chip("正确", a.expected, Ink.good, strike: false)
                        }
                    }
                }
                if i < range.upperBound - 1 { Divider().overlay(Ink.line) }
            }
        }
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
    static func pages(_ report: QuizReport, title: String, itemName: @escaping (String) -> String = { $0 }) -> [AnyView] {
        let plan = QuizReportPage.plan(report)
        return plan.enumerated().map { i, p in AnyView(QuizReportPageView(report: report, page: p, title: title, number: i + 1, count: plan.count, itemName: itemName)) }
    }
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
    static func pdf(_ views: [AnyView]) throws -> URL {
        let url = try folder().appendingPathComponent("答题报告-\(stamp()).pdf")
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
    static func pngs(_ images: [UIImage], names: [String]) throws -> [URL] {
        let dir = try folder()
        return try images.enumerated().map { i, image in
            let url = dir.appendingPathComponent(String(format: "答题报告-%02d-%@.png", i + 1, names[i]))
            guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url); return url
        }
    }
    static func pageNames(_ report: QuizReport) -> [String] {
        QuizReportPage.plan(report).map { p in
            switch p { case .overview: return "全班"; case .student(let i, _, let first): return report.students[i].name + (first ? "" : "-续") }
        }
    }
}

/// Teacher screen: the report pages as they will print, with PDF and picture export.
struct QuizReportScreen: View {
    let report: QuizReport
    let title: String
    var itemName: (String) -> String = { $0 }
    var onClose: () -> Void
    @State private var images: [UIImage] = []
    @State private var exporting: [URL] = []
    @State private var showExporter = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Label("答题报告", systemImage: "chart.bar.doc.horizontal").font(.title2.bold())
                Text("\(report.students.count) 位同学 · \(report.attempts) 次作答 · 共 \(images.count) 页").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { export(pdf: true) } label: { Label("导出 PDF", systemImage: "doc.richtext") }.buttonStyle(GlassIconButtonStyle(prominent: true)).disabled(report.attempts == 0)
                Button { export(pdf: false) } label: { Label("导出图片", systemImage: "photo.on.rectangle") }.buttonStyle(GlassIconButtonStyle()).disabled(report.attempts == 0)
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
        .onAppear { images = QuizReportExport.images(QuizReportExport.pages(report, title: title, itemName: itemName)) }
        .sheet(isPresented: $showExporter) { ExportPicker(urls: exporting) { showExporter = false } }
    }
    private func export(pdf: Bool) {
        do {
            exporting = pdf ? [try QuizReportExport.pdf(QuizReportExport.pages(report, title: title, itemName: itemName))]
                            : try QuizReportExport.pngs(images, names: QuizReportExport.pageNames(report))
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
