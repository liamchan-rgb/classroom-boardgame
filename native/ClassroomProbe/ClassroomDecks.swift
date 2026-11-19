import SwiftUI
import UIKit
import ClassroomProbeCore

/// Every PPTX the teacher imported, kept in the app (Application Support/ClassroomStage0/Decks) with its cover,
/// page count, the page last shown and the notes edited, so a deck can be called up again in one tap.
struct DeckRecord: Codable, Identifiable, Equatable {
    var name: String
    var file: String
    var pages: Int
    var importedAt: Date
    var openedAt: Date
    var lastPage: Int
    var notes: [Int: String]
    var id: String { file }
}

extension DeckPage {
    /// A small picture of the page as it first shows (every layer in place), for the deck list.
    func thumbnail(width: CGFloat = 360) -> Data? {
        guard size.width > 0 else { return nil }
        let k = width / size.width, out = CGSize(width: width, height: size.height * k)
        let image = UIGraphicsImageRenderer(size: out).image { ctx in
            background.setFill(); ctx.fill(CGRect(origin: .zero, size: out))
            for piece in pieces {
                switch piece {
                case .still(let still): still.draw(in: CGRect(origin: .zero, size: out))
                case .layer(let i):
                    guard layers.indices.contains(i) else { continue }
                    let f = layers[i].frame
                    layers[i].image.draw(in: CGRect(x: f.minX * k, y: f.minY * k, width: f.width * k, height: f.height * k))
                }
            }
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}

@MainActor final class DeckLibrary: ObservableObject {
    static let shared = DeckLibrary()
    /// Most recently opened first.
    @Published private(set) var records: [DeckRecord] = []
    private var thumbs: [String: UIImage] = [:]
    let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ClassroomStage0/Decks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var indexURL: URL { folder.appendingPathComponent("index.json") }
    private let writer = DispatchQueue(label: "deck-library", qos: .utility)

    private init() {
        if let data = try? Data(contentsOf: indexURL), let list = try? JSONDecoder().decode([DeckRecord].self, from: data) {
            records = list.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.file).path) }
        }
        sort()
    }
    private func sort() { records.sort { $0.openedAt > $1.openedAt } }
    private func saveIndex() {
        let list = records, url = indexURL
        writer.async { try? JSONEncoder().encode(list).write(to: url, options: .atomic) }
    }
    func url(_ r: DeckRecord) -> URL { folder.appendingPathComponent(r.file) }
    /// The file name a deck is kept under ("第二章.pptx" → "第二章.pptx", unsafe characters replaced).
    static func fileName(_ name: String) -> String {
        let clean = String(name.map { "/\\:*?\"<>|".contains($0) ? "-" : $0 }.prefix(120))
        return clean.lowercased().hasSuffix(".pptx") ? clean : clean + ".pptx"
    }
    func record(named name: String?) -> DeckRecord? { name.flatMap { n in records.first { $0.name == n } } }

    /// After an import (or a reopen): keeps the file and its cover (same name = the same deck, replaced).
    func remember(data: Data, name: String, pages: Int, page: Int, notes: [Int: String], cover: Data? = nil) {
        let file = Self.fileName(name), now = Date()
        let old = records.first { $0.file == file }
        let record = DeckRecord(name: name, file: file, pages: pages, importedAt: old?.importedAt ?? now, openedAt: now, lastPage: page, notes: notes)
        records.removeAll { $0.file == file }; records.append(record); sort(); saveIndex()
        thumbs[file] = nil
        let target = folder.appendingPathComponent(file), thumbURL = folder.appendingPathComponent(file + ".thumb")
        writer.async {
            // The same bytes are already there when a kept deck is reopened.
            if (try? Data(contentsOf: target, options: .mappedIfSafe)) != data { try? data.write(to: target, options: .atomic) }
            // The first page as drawn (else the picture PowerPoint stored in the file).
            if let thumb = cover ?? PPTXReader.thumbnail(data) { try? thumb.write(to: thumbURL, options: .atomic) }
            Task { @MainActor in DeckLibrary.shared.objectWillChange.send() }
        }
    }
    /// Page turns and note edits of the open deck.
    func update(name: String?, page: Int, notes: [Int: String]) {
        guard let name, let i = records.firstIndex(where: { $0.name == name }) else { return }
        guard records[i].lastPage != page || records[i].notes != notes else { return }
        records[i].lastPage = page; records[i].notes = notes; saveIndex()
    }
    func remove(_ r: DeckRecord) {
        records.removeAll { $0.file == r.file }; saveIndex(); thumbs[r.file] = nil
        try? FileManager.default.removeItem(at: url(r))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(r.file + ".thumb"))
    }
    func thumbnail(_ r: DeckRecord) -> UIImage? {
        if let t = thumbs[r.file] { return t }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(r.file + ".thumb")), let image = UIImage(data: data) else { return nil }
        thumbs[r.file] = image; return image
    }
}

/// "课件": the decks imported before, newest first; tap one to open it on the page it was left on.
struct DeckLibraryPanel: View {
    @ObservedObject var library = DeckLibrary.shared
    @ObservedObject var session: TeacherSession
    var onImport: () -> Void
    var onClose: () -> Void
    @State private var confirmDelete: DeckRecord?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("课件", systemImage: "rectangle.stack").font(.title2.bold())
                Text("\(library.records.count) 份").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { onImport() } label: { Label("导入 PPTX", systemImage: "square.and.arrow.down") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                Button { onClose() } label: { Label("关闭", systemImage: "xmark") }.buttonStyle(GlassIconButtonStyle())
            }
            if library.records.isEmpty {
                ContentUnavailableView("还没有导入过课件", systemImage: "rectangle.stack", description: Text("导入的 PPTX 会自动保存在这里，下次一点就能调出。"))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                        ForEach(library.records) { r in card(r) }
                    }.padding(.vertical, 4)
                }
            }
            if let p = session.importProgress { ProgressView(p.stage, value: p.fraction).tint(GameTheme.primary) }
        }
        .padding(22).frame(minWidth: 760, idealWidth: 860, maxWidth: .infinity, minHeight: 520, idealHeight: 620, maxHeight: .infinity, alignment: .top)
        .background(GlassBackdrop()).foregroundStyle(GameTheme.ink)
        .alert("删除这份课件？", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("删除", role: .destructive) { if let r = confirmDelete { library.remove(r) }; confirmDelete = nil }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: { Text("只删除 App 里保存的副本和它的翻页、备注记录，原 PPTX 文件不受影响。") }
    }
    private func card(_ r: DeckRecord) -> some View {
        let current = session.currentDeckName == r.name
        return Button { session.openDeck(r); onClose() } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.6))
                    if let t = library.thumbnail(r) { Image(uiImage: t).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(4) }
                    else { Image(systemName: "doc.richtext").font(.system(size: 34)).foregroundStyle(GameTheme.muted) }
                }.aspectRatio(16 / 9, contentMode: .fit)
                Text(r.name.replacingOccurrences(of: ".pptx", with: "", options: [.caseInsensitive, .anchored, .backwards])).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text("\(r.pages) 页 · 上次第 \(min(r.lastPage, max(0, r.pages - 1)) + 1) 页").font(.caption).foregroundStyle(GameTheme.muted)
                    Spacer()
                    if current { Text("正在使用").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(GameTheme.primary)) }
                }
                Text(r.openedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(GameTheme.muted)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(current ? 0.7 : 0.45)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(current ? GameTheme.primary : Color.white.opacity(0.6), lineWidth: current ? 2 : 1))
        }
        .buttonStyle(.plain).disabled(session.importProgress != nil)
        .contextMenu { Button(role: .destructive) { confirmDelete = r } label: { Label("删除", systemImage: "trash") } }
        .overlay(alignment: .topTrailing) {
            Button { confirmDelete = r } label: { Image(systemName: "trash.circle.fill").font(.title3).foregroundStyle(GameTheme.muted) }.buttonStyle(.plain).padding(6)
        }
    }
}

/// The classroom tools both top bars share, in one order: timer, course, questions, laser | scoreboard, report.
/// While a question is on, 答题 becomes 结束答题 and the other question buttons wait (the row does not shift).
struct ClassroomToolbarTools: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var prepare: () -> Void = {}
    var body: some View {
        Button { prepare(); game.openTimer() } label: { Label("计时", systemImage: "timer") }
        QuizCourseMenu(game: game)
        if game.quizActive {
            Button { prepare(); game.abortQuiz() } label: { Label("结束答题", systemImage: "xmark.octagon.fill") }.buttonStyle(ToolbarIconStyle(tint: .red))
        } else {
            Button { prepare(); game.openQuiz() } label: { Label("答题", systemImage: "questionmark.bubble") }
        }
        Button { prepare(); game.openClassQuiz() } label: { Label("全班题", systemImage: "person.3.sequence") }.disabled(game.quizActive)
        Button { prepare(); game.openPractice() } label: { Label("闪卡", systemImage: "rectangle.on.rectangle.angled") }.disabled(game.quizActive)
        LaserButton(laser: game.laser) { prepare(); game.toggleLaser() }
        ToolbarGap()
        ClassroomScoreboardButton(overlays: game.overlays) { game.toggleScoreboard() }
        // The class answer report of the open trip: look at it, export PDF / pictures (also R).
        Button { prepare(); game.openQuizReport() } label: { Label("报告", systemImage: "chart.bar.doc.horizontal") }.disabled(game.campaign == nil)
    }
}
