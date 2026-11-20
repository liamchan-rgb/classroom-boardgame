import UIKit
import Combine
import ClassroomProbeCore

@MainActor
final class PublicDisplayModel: ObservableObject {
    @Published var snapshot = ProbeState().publicSnapshot
    /// The slide on screen, its build step (clicks played) and a token that changes with every new page shown.
    @Published private(set) var page: DeckPage?
    @Published var buildStep = 0
    @Published private(set) var pageToken = 0
    /// When the page arrived (its entry effects play only right after).
    private(set) var entryStarted = Date.distantPast
    /// Slide change effect for the page that just arrived, nil when it should simply cut.
    private(set) var arrival: PageTransitionEffect?
    func show(_ result: DeckRenderer.Result?, step: Int = 0, animated: Bool = false) {
        arrival = animated ? result?.page.transition : nil
        page = result?.page
        buildStep = min(step, result?.page.clicks.count ?? 0)
        entryStarted = Date()
        pageToken &+= 1
    }
    var hasPage: Bool { page != nil }

}

@MainActor
final class TeacherSession: ObservableObject {
    static let shared = TeacherSession()
    let display = PublicDisplayModel()
    @Published private(set) var state = ProbeState()
    @Published private(set) var message = "就绪"
    @Published private(set) var connectionCount = 0
    @Published private(set) var registrationStatus = "正在准备公开画面。"
    @Published private(set) var importReport = "尚未导入PPTX。"
    @Published var showNotes = false
    /// PPTX import in progress (stage text and 0…1), nil when idle.
    @Published private(set) var importProgress: (stage: String, fraction: Double)?
    /// One-line result of the last import, shown to the teacher as an alert (success or the reason it failed).
    @Published var importOutcome: String?
    private(set) var isEditingNotes = false
    lazy var game = MeadowTeacherCoordinator()
    private var connectedIDs: Set<String> = []
    private var deck: ParsedDeck?
    private var pptxData: Data?
    private var sourceName: String?
    private var editedNotes: [Int: String] = [:]
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    private init() {
        if let url = try? saveURL(), FileManager.default.fileExists(atPath: url.path) {
            do { try restore(Data(contentsOf: url), saveAfterValidation: false); applyLiteSave() }
            catch { message = "本地恢复失败，原文件保留：\(error.localizedDescription)" }
        }
        // The deck in use before the deck list existed joins the list.
        if let data = pptxData, let name = sourceName, DeckLibrary.shared.record(named: name) == nil {
            let cover = deck?.slides.first.flatMap { try? DeckRenderer.render($0).page.thumbnail() }
            DeckLibrary.shared.remember(data: data, name: name, pages: state.pageCount, page: state.pageIndex, notes: editedNotes, cover: cover)
        }
        publish()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var currentNote: String {
        if let edited = editedNotes[state.pageIndex] { return edited }
        guard let deck, deck.slides.indices.contains(state.pageIndex) else { return "" }
        return deck.slides[state.pageIndex].notes
    }
    /// The deck on screen (its imported file name), for the deck list.
    var currentDeckName: String? { sourceName }
    /// Asks the root view to show the picture-book tab (a deck was opened from the game tab).
    @Published var bookTabRequest = 0
    /// Asks the book tab to open the PPTX file picker (from the game tab's 课件 list).
    @Published var importRequest = 0
    /// Opens a kept deck on the page it was left on, with its edited notes.
    func openDeck(_ record: DeckRecord) {
        DeckLibrary.shared.update(name: sourceName, page: state.pageIndex, notes: editedNotes)
        loadPPTX(DeckLibrary.shared.url(record), name: record.name, resume: record)
        bookTabRequest += 1
    }
    var selectedName: String { state.players.first(where: { $0.id == state.selectedPlayerID })?.name ?? "" }

    func editNote(_ value: String) {
        guard deck != nil, value.count <= 40_000 else { return }
        editedNotes[state.pageIndex] = value
        objectWillChange.send()
    }
    func notesFocus(_ active: Bool) {
        isEditingNotes = active
        pause(.notes, enabled: active)
    }
    func concealNotes() {
        showNotes = false
        isEditingNotes = false
        pause(.notes, enabled: false)
    }
    func setConnection(id: String, connected: Bool) {
        if connected { connectedIDs.insert(id) } else { connectedIDs.remove(id) }
        connectionCount = connectedIDs.count
        game.setConnection(id,connected:connected)
        if connectedIDs.isEmpty {
            concealNotes(); pause(.manual, enabled: true)
        }
    }
    func setRegistrationStatus(_ text: String) { registrationStatus = text }
    func fileSelectionFailed(_ error: Error) { message = "选择文件失败：\(error.localizedDescription)" }
    func select(_ id: Int) { mutate { if $0.players.contains(where: { $0.id == id }) { $0.selectedPlayerID = id } } }
    func award() {
        if mutate({ $0.awardCoins() }) { message = "奖励对象：\(selectedName)；金币已更新。" }
    }
    func togglePause() { mutate { $0.toggleManualPause() } }
    func resetClock() { mutate { $0.remainingSeconds = 30; $0.pauseReasons.remove(.expired) } }
    func pause(_ reason: PauseReason, enabled: Bool) {
        if enabled {
            // Background/notes must pause even if storage is unavailable.
            let now = ProcessInfo.processInfo.systemUptime
            state.advanceClock(by: now - lastTick)
            state.setPause(reason, enabled: true)
            lastTick = now
            publish()
            do { try persist(state: state) }
            catch { message = "已经暂停，但保存失败：\(error.localizedDescription)" }
        } else { mutate { $0.setPause(reason, enabled: false) } }
    }

    /// Forward plays the next animation of the slide before moving on; back undoes it, then shows the previous
    /// page fully built (as PowerPoint does).
    func turnPage(_ offset: Int) {
        if offset > 0, let page = display.page, display.buildStep < page.clicks.count { display.buildStep += 1; return }
        if offset < 0, display.page != nil, display.buildStep > 0 { display.buildStep -= 1; return }
        var candidate = state
        candidate.turnPage(by: offset)
        show(candidate, step: offset < 0 ? Int.max : 0, animated: offset > 0)
    }
    /// Jumps straight to a page (1-based, clamped to the deck); the page starts from its first animation.
    func goToPage(_ number: Int) {
        guard state.pageCount > 0 else { return }
        var candidate = state
        candidate.pageIndex = min(state.pageCount - 1, max(0, number - 1))
        guard candidate.pageIndex != state.pageIndex else { display.buildStep = 0; return }
        show(candidate, step: 0, animated: true)
    }
    /// Bumped by the 跳页 shortcut; the book toolbar opens its page-number field.
    @Published var pageJumpRequest = 0
    private func show(_ candidate: ProbeState, step: Int, animated: Bool) {
        guard candidate.pageIndex != state.pageIndex || display.page == nil else { return }
        do {
            let result = try render(deck: deck, index: candidate.pageIndex)
            try persist(state: candidate)
            state = candidate
            DeckLibrary.shared.update(name: sourceName, page: candidate.pageIndex, notes: editedNotes)
            display.show(result, step: step, animated: animated)
            publish()
            refreshReport(result?.warnings ?? [])
        } catch { message = error.localizedDescription }
    }

    func loadSample() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "pptx") else {
            message = "内置测试PPTX缺失。"; return
        }
        loadPPTX(url)
    }
    /// Reads, checks and renders the first page in the background with a progress bar; the current book stays in use
    /// until the new one is fully ready. Large photo decks take a few seconds.
    func loadPPTX(_ url: URL, name shownName: String? = nil, resume: DeckRecord? = nil) {
        guard importProgress == nil else { message = "正在导入上一个文件，请稍候。"; return }
        importProgress = ("读取文件", 0.02)
        let name = shownName ?? url.lastPathComponent
        let page = resume.map { max(0, $0.lastPage) } ?? 0
        let report: @Sendable (String, Double) -> Void = { stage, fraction in
            Task { @MainActor in if TeacherSession.shared.importProgress != nil { TeacherSession.shared.importProgress = (stage, fraction) } }
        }
        Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= PPTXLimits.fileBytes else { throw ProbeError("PPTX超过\(PPTXLimits.fileLabel)，请压缩图片后再导入。") }
                let data = try Data(contentsOf: url)
                report("解析页面", 0.08)
                let parsed = try PPTXReader.read(data) { done, total in
                    report("解析第 \(done)/\(total) 页", 0.08 + 0.72 * Double(done) / Double(max(1, total)))
                }
                report("生成第一页", 0.85)
                let at = parsed.slides.indices.contains(page) ? page : 0
                let first = try parsed.slides.indices.contains(at) ? DeckRenderer.render(parsed.slides[at]) : nil
                let cover = (at == 0 ? first : try? parsed.slides.first.map { try DeckRenderer.render($0) })?.page.thumbnail()
                report("保存绘本", 0.93)
                await MainActor.run { TeacherSession.shared.adoptImported(parsed, data: data, name: name, first: first, page: at, notes: resume?.notes ?? [:], cover: cover, reopened: resume != nil) }
            } catch {
                let reason = error.localizedDescription
                await MainActor.run {
                    let session = TeacherSession.shared
                    session.importProgress = nil
                    session.message = "导入失败，当前资料保留：\(reason)"
                    session.importOutcome = "导入失败：\(reason)"
                }
            }
        }
    }
    private func adoptImported(_ parsed: ParsedDeck, data: Data, name: String, first: DeckRenderer.Result?, page: Int = 0, notes: [Int: String] = [:], cover: Data? = nil, reopened: Bool = false) {
        defer { importProgress = nil }
        var candidate = state
        candidate.pageIndex = page
        candidate.pageCount = parsed.slides.count
        candidate.pauseReasons.insert(.manual)
        do {
            try write(ProbeBackup(state: candidate, pptxData: data, sourceName: name, editedNotes: notes))
        } catch {
            message = "导入失败，当前资料保留：\(error.localizedDescription)"; importOutcome = "导入失败：\(error.localizedDescription)"; return
        }
        deck = parsed; pptxData = data; sourceName = name; editedNotes = notes
        state = candidate; display.show(first); showNotes = false
        publish(); refreshReport(first?.warnings ?? [])
        DeckLibrary.shared.remember(data: data, name: name, pages: parsed.slides.count, page: page, notes: notes, cover: cover)
        let skipped = parsed.slides.reduce(0) { $0 + ($1.warnings.isEmpty ? 0 : 1) }
        message = page > 0 || !notes.isEmpty ? "已调出 \(name)：第 \(page + 1)/\(parsed.slides.count) 页" : "已导入 \(parsed.slides.count) 页：\(name)"
        // A deck called up again from 课件 needs no import notice.
        if !reopened { importOutcome = "已导入 \(parsed.slides.count) 页" + (skipped > 0 ? "，其中 \(skipped) 页有未支持的对象，可在「导入报告」查看。" : "。") }
    }

    func save() {
        do { try persist(state: state); message = "已保存到本App的本地存储。" }
        catch { message = "保存失败：\(error.localizedDescription)" }
    }
    func restoreLocal() {
        do { try restore(Data(contentsOf: saveURL()), saveAfterValidation: false) }
        catch { message = "恢复失败，当前状态保留：\(error.localizedDescription)" }
    }
    func importBackup(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= PPTXLimits.backupBytes else { throw ProbeError("绘本备份过大。") }
            try restore(Data(contentsOf: url), saveAfterValidation: true)
        } catch { message = "备份导入失败，当前状态保留：\(error.localizedDescription)" }
    }
    func exportedURL() -> URL? {
        do {
            let data = try backup(state: state).encoded()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("classroom-stage0-backup.json")
            try data.write(to: url, options: .atomic)
            return url
        } catch { message = "导出失败：\(error.localizedDescription)"; return nil }
    }

    private func restore(_ bytes: Data, saveAfterValidation: Bool) throws {
        let candidate = try ProbeBackup.decoded(bytes)
        let parsed = try candidate.pptxData.map { try PPTXReader.read($0) }
        guard (parsed?.slides.count ?? 0) == candidate.state.pageCount else { throw ProbeError("备份页数与PPTX不一致。") }
        let rendered = try render(deck: parsed, index: candidate.state.pageIndex)
        if saveAfterValidation { try write(candidate) }
        deck = parsed; pptxData = candidate.pptxData; sourceName = candidate.sourceName; editedNotes = candidate.editedNotes
        state = candidate.state; display.show(rendered); showNotes = false; isEditingNotes = false
        lastTick = ProcessInfo.processInfo.systemUptime
        publish(); refreshReport(rendered?.warnings ?? [])
        message = "绘本已恢复"
    }
    private func backup(state: ProbeState) -> ProbeBackup {
        ProbeBackup(state: state, pptxData: pptxData, sourceName: sourceName, editedNotes: editedNotes)
    }
    /// Page turns, pauses and rewards save only the small state file; the deck itself is written once at import.
    /// (Re-encoding a large photo deck as JSON on every page turn froze the teacher iPad.)
    private struct LiteSave: Codable { var state: ProbeState; var editedNotes: [Int: String] }
    private func persist(state: ProbeState) throws {
        try state.validate()
        guard pptxData != nil || state.pageCount == 0 else { try write(backup(state: state)); return }
        let data = try JSONEncoder().encode(LiteSave(state: state, editedNotes: editedNotes))
        try data.write(to: liteURL(), options: .atomic)
    }
    private func write(_ value: ProbeBackup) throws {
        try value.state.validate()
        try value.encoded().write(to: saveURL(), options: .atomic)
        try? FileManager.default.removeItem(at: liteURL())
    }
    private func liteURL() throws -> URL { try saveURL().deletingLastPathComponent().appendingPathComponent("session-state.json") }
    /// After restoring the deck, the newer page / pause state from the small file (if it fits the deck).
    private func applyLiteSave() {
        guard let url = try? liteURL(), let data = try? Data(contentsOf: url),
              let lite = try? JSONDecoder().decode(LiteSave.self, from: data),
              (try? lite.state.validate()) != nil, lite.state.pageCount == state.pageCount else { return }
        let rendered = try? render(deck: deck, index: lite.state.pageIndex)
        state = lite.state; editedNotes = lite.editedNotes.filter { $0.key >= 0 && $0.key < lite.state.pageCount && $0.value.count <= 40_000 }
        if let rendered { display.show(rendered) }
        publish()
    }
    private func saveURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("ClassroomStage0", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("session.json")
    }
    @discardableResult
    private func mutate(_ action: (inout ProbeState) -> Void) -> Bool {
        var candidate = state
        let now = ProcessInfo.processInfo.systemUptime
        candidate.advanceClock(by: now - lastTick)
        action(&candidate)
        do {
            try persist(state: candidate)
            state = candidate
            lastTick = now
            publish()
            return true
        } catch { message = "操作未保存、状态未提交：\(error.localizedDescription)"; return false }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick
        lastTick = now
        state.advanceClock(by: elapsed)
        publish()
    }
    private func publish() { display.snapshot = state.publicSnapshot }
    private func render(deck: ParsedDeck?, index: Int) throws -> DeckRenderer.Result? {
        guard let deck else { return nil }
        guard deck.slides.indices.contains(index) else { throw ProbeError("绘本页码无效。") }
        return try DeckRenderer.render(deck.slides[index])
    }
    private func refreshReport(_ warnings: [String]) {
        guard let deck else { importReport = "尚未导入PPTX。"; return }
        var lines = deck.slides.enumerated().map { index, slide in
            "第\(index + 1)页：\(slide.elements.count)个对象；备注\(slide.notes.count)字符。\n" + slide.warnings.joined(separator: "\n")
        }
        lines.append(contentsOf: warnings)
        importReport = lines.joined(separator: "\n\n")
    }
}
