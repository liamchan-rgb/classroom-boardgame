import UIKit
import Combine
import ClassroomProbeCore
import ClassroomGameCore

@MainActor
final class PublicDisplayModel: ObservableObject {
    @Published var snapshot = ProbeState().publicSnapshot
    @Published var image: UIImage?
    @Published var ruleExample: PublicGameSnapshot?
}

@MainActor
final class TeacherSession: ObservableObject {
    static let shared = TeacherSession()
    let display = PublicDisplayModel()
    @Published private(set) var state = ProbeState()
    @Published private(set) var message = "阶段0：先验证安装与独立公开画面。"
    @Published private(set) var connectionCount = 0
    @Published private(set) var registrationStatus = "正在准备公开画面。"
    @Published private(set) var importReport = "尚未导入PPTX。"
    @Published var showNotes = false
    private(set) var isEditingNotes = false
    private(set) var rulesOpen = false
    private var connectedIDs: Set<String> = []
    private var deck: ParsedDeck?
    private var pptxData: Data?
    private var sourceName: String?
    private var editedNotes: [Int: String] = [:]
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    private init() {
        if let url = try? saveURL(), FileManager.default.fileExists(atPath: url.path) {
            do { try restore(Data(contentsOf: url), saveAfterValidation: false) }
            catch { message = "本地恢复失败，原文件保留：\(error.localizedDescription)" }
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
    func beginRules() {
        concealNotes()
        rulesOpen = true
        pause(.rules, enabled: true)
    }
    func endRules() {
        display.ruleExample = nil
        rulesOpen = false
        pause(.rules, enabled: false)
    }
    func setConnection(id: String, connected: Bool) {
        if connected { connectedIDs.insert(id) } else { connectedIDs.remove(id) }
        connectionCount = connectedIDs.count
        if connectedIDs.isEmpty { display.ruleExample = nil; concealNotes(); pause(.manual, enabled: true) }
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

    func turnPage(_ offset: Int) {
        var candidate = state
        candidate.turnPage(by: offset)
        do {
            let result = try render(deck: deck, index: candidate.pageIndex)
            try persist(state: candidate)
            state = candidate
            display.image = result?.image
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
    func loadPPTX(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 32 * 1024 * 1024 else { throw ProbeError("阶段0支持最多32 MiB的PPTX。") }
            let data = try Data(contentsOf: url)
            let parsed = try PPTXReader.read(data)
            let firstPage = try render(deck: parsed, index: 0)
            var candidate = state
            candidate.pageIndex = 0
            candidate.pageCount = parsed.slides.count
            candidate.pauseReasons.insert(.manual)
            let backup = ProbeBackup(state: candidate, pptxData: data, sourceName: url.lastPathComponent, editedNotes: [:])
            try write(backup)
            deck = parsed; pptxData = data; sourceName = url.lastPathComponent; editedNotes = [:]
            state = candidate; display.image = firstPage?.image; showNotes = false
            publish(); refreshReport(firstPage?.warnings ?? [])
            message = "已离线读取\(parsed.slides.count)页，页序及备注来自PPTX。请核对页面。"
        } catch { message = "导入失败，当前资料保留：\(error.localizedDescription)" }
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
            guard size <= 48 * 1024 * 1024 else { throw ProbeError("测试备份超过48 MiB。") }
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
        state = candidate.state; display.image = rendered?.image; showNotes = false; isEditingNotes = false
        lastTick = ProcessInfo.processInfo.systemUptime
        publish(); refreshReport(rendered?.warnings ?? [])
        message = "测试状态与绘本已恢复；计时保持暂停。"
    }
    private func backup(state: ProbeState) -> ProbeBackup {
        ProbeBackup(state: state, pptxData: pptxData, sourceName: sourceName, editedNotes: editedNotes)
    }
    private func persist(state: ProbeState) throws { try write(backup(state: state)) }
    private func write(_ value: ProbeBackup) throws {
        try value.state.validate()
        try value.encoded().write(to: saveURL(), options: .atomic)
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
