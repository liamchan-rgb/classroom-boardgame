import UIKit
import SwiftUI
import UniformTypeIdentifiers

// Candidate probe for the user's iPadOS 27 device, with a public-API runtime bridge
// because the currently listed Swift Playground SDK is 26. Not yet compiled.
struct PublicState: Codable {
    var page = 1
    var coins = 0
    var remainingSeconds = 30.0
    var paused = true
}

struct ProbeBackup: Codable {
    let formatVersion: Int
    let publicState: PublicState
    let privateTestNotes: String
}

extension Notification.Name {
    static let probePublicChanged = Notification.Name("probe.public.changed")
    static let probeConnectionChanged = Notification.Name("probe.connection.changed")
    static let probeHostInactive = Notification.Name("probe.host.inactive")
}

final class ProbeStore {
    static let shared = ProbeStore()
    private(set) var publicState = PublicState()
    var testNotes = "教师私有测试台词 PRIVATE-TEST-4731。只使用假台词，暂不输入真实课堂资料。"
    private(set) var pauseReasons: Set<String> = ["manual"]
    var externalSessions: Set<String> = [] {
        didSet {
            NotificationCenter.default.post(name: .probeConnectionChanged, object: nil)
        }
    }
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - self.lastTick
            self.lastTick = now
            guard self.pauseReasons.isEmpty else { return }
            self.publicState.remainingSeconds = max(0, self.publicState.remainingSeconds - elapsed)
            if self.publicState.remainingSeconds == 0 { self.pauseReasons.insert("expired") }
            self.publish()
        }
    }

    func publish() {
        publicState.paused = !pauseReasons.isEmpty
        NotificationCenter.default.post(name: .probePublicChanged, object: publicState)
    }

    func setPause(_ reason: String, enabled: Bool) {
        if enabled { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        lastTick = ProcessInfo.processInfo.systemUptime
        publish()
    }

    func togglePause() {
        if pauseReasons.contains("manual") || pauseReasons.contains("background") {
            pauseReasons.remove("manual")
            pauseReasons.remove("background")
            publish()
            lastTick = ProcessInfo.processInfo.systemUptime
        } else { setPause("manual", enabled: true) }
    }

    func reward() { publicState.coins += 10; publish() }
    func turnPage(_ offset: Int) {
        publicState.page = min(3, max(1, publicState.page + offset)); publish()
    }
    func resetClock() {
        publicState.remainingSeconds = 30
        pauseReasons.remove("expired")
        publish()
    }

    func backupData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ProbeBackup(formatVersion: 1, publicState: publicState,
                                             privateTestNotes: testNotes))
    }

    func restore(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(ProbeBackup.self, from: data)
        guard decoded.formatVersion == 1,
              (1...3).contains(decoded.publicState.page),
              (0...1_000_000).contains(decoded.publicState.coins),
              decoded.publicState.remainingSeconds.isFinite,
              (0...30).contains(decoded.publicState.remainingSeconds),
              decoded.privateTestNotes.count <= 20000 else {
            throw NSError(domain: "Probe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "测试存档格式或数值无效；原状态未改变。"])
        }
        publicState = decoded.publicState
        testNotes = decoded.privateTestNotes
        pauseReasons = ["manual"]
        lastTick = ProcessInfo.processInfo.systemUptime
        publish()
    }
}

@main
struct ClassroomProbeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TeacherControllerHost()
                .ignoresSafeArea()
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        NotificationCenter.default.post(name: .probeHostInactive, object: nil)
                        ProbeStore.shared.setPause("background", enabled: true)
                    }
                }
        }
    }
}

// Keep the Playgrounds-native SwiftUI launch/preview lifecycle. UIKit still
// implements the teacher interface and registers the external scene accessory.
struct TeacherControllerHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TeacherViewController {
        TeacherViewController()
    }
    func updateUIViewController(_ controller: TeacherViewController, context: Context) {}
}

@objc(PublicSceneDelegate)
final class PublicSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let newWindow = UIWindow(windowScene: windowScene)
        // Explicit public value only; notes are never passed to the public controller.
        newWindow.rootViewController = PublicViewController(state: ProbeStore.shared.publicState)
        window = newWindow
        newWindow.isHidden = false
        ProbeStore.shared.externalSessions.insert(session.persistentIdentifier)
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        ProbeStore.shared.externalSessions.remove(scene.session.persistentIdentifier)
        window?.isHidden = true
        window = nil
    }
}

final class PublicViewController: UIViewController {
    private var state: PublicState
    private let titleLabel = UILabel()
    private let detailsLabel = UILabel()
    init(state: PublicState) { self.state = state; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.21, blue: 0.20, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 52, weight: .bold)
        detailsLabel.font = .systemFont(ofSize: 34)
        for label in [titleLabel, detailsLabel] {
            label.textColor = .white; label.numberOfLines = 0; label.textAlignment = .center
        }
        let stack = UIStackView(arrangedSubviews: [titleLabel, detailsLabel])
        stack.axis = NSLayoutConstraint.Axis.vertical; stack.spacing = 32; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(receive(_:)),
                                               name: .probePublicChanged, object: nil)
        refresh()
    }
    @objc private func receive(_ notification: Notification) {
        guard let publicValue = notification.object as? PublicState else { return }
        state = publicValue; refresh()
    }
    private func refresh() {
        titleLabel.text = "学生公开画面 · 第 \(state.page) 页"
        detailsLabel.text = "金币 \(state.coins)\n剩余 \(Int(ceil(state.remainingSeconds))) 秒\n\(state.paused ? "已暂停" : "计时中")"
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

final class TeacherViewController: UIViewController, UITextViewDelegate, UIDocumentPickerDelegate {
    private let store = ProbeStore.shared
    private let connection = UILabel()
    private let summary = UILabel()
    private let notes = UITextView()
    private var heldKeys: Set<String> = []
    // Retain registration for this controller's lifetime. No private notes in it.
    private var displayRegistration: NSObject?
    private var bridgeMessage = "尚未调用外屏注册。"
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let heading = UILabel()
        heading.text = "教师端 · 阶段0测试 v0.4（只用假台词）"
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        connection.numberOfLines = 0; summary.numberOfLines = 0
        notes.font = .systemFont(ofSize: 21)
        notes.backgroundColor = .systemYellow
        notes.text = store.testNotes
        notes.delegate = self
        notes.isHidden = true
        notes.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let controls: UIStackView = UIStackView(arrangedSubviews: [
            button("上一页", #selector(TeacherViewController.probePreviousPage)),
            button("下一页", #selector(TeacherViewController.probeNextPage)),
            button("发10金币（G）", #selector(TeacherViewController.probeGrantCoins)),
            button("暂停／继续", #selector(TeacherViewController.probeTogglePause)),
            button("重置30秒", #selector(TeacherViewController.probeResetClock))
        ])
        controls.spacing = 12; controls.distribution = UIStackView.Distribution.fillEqually
        let files: UIStackView = UIStackView(arrangedSubviews: [
            button("显示／隐藏假台词", #selector(TeacherViewController.probeToggleTestNotes)),
            button("保存测试状态", #selector(TeacherViewController.probeSaveState)),
            button("恢复测试状态", #selector(TeacherViewController.probeRestoreState)),
            button("导出JSON", #selector(TeacherViewController.probeExportBackup)),
            button("导入JSON", #selector(TeacherViewController.probeImportBackup))
        ])
        files.spacing = 12; files.distribution = UIStackView.Distribution.fillEqually
        let help = UILabel()
        help.numberOfLines = 0
        help.text = "外屏应显示绿色公开页，iPad显示本页。未建立独立外屏时不开放台词。\n台词编辑自动暂停；输入G不应发奖，长按G只发一次。\nJSON仅测试本地文件；此样例尚未导入或渲染PPTX。"
        let stack: UIStackView = UIStackView(arrangedSubviews: [heading, connection, summary, controls, files, notes, help])
        stack.axis = NSLayoutConstraint.Axis.vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .probePublicChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateConnection), name: .probeConnectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(probeConcealForHost), name: .probeHostInactive, object: nil)
        configureExternalDisplay()
        update(); updateConnection()
    }

    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
    private func button(_ title: String, _ action: Selector) -> UIButton {
        let result = UIButton(type: .system)
        result.setTitle(title, for: .normal)
        result.addTarget(self, action: action, for: .touchUpInside)
        return result
    }
    private func configureExternalDisplay() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else {
            bridgeMessage = "本次外屏注册测试需要iPadOS27；当前系统低于27。"
            return
        }
        let configuration = UISceneConfiguration()
        configuration.delegateClass = PublicSceneDelegate.self
        do {
            displayRegistration = try SceneAccessoryBridge.register(on: self, configuration: configuration)
            bridgeMessage = "已调用iPadOS27公开外屏注册接口；等待独立公开场景。"
        } catch {
            bridgeMessage = "注册失败：\(error.localizedDescription)"
            displayRegistration = nil
        }
    }
    @objc private func update() {
        let state = store.publicState
        summary.text = "第\(state.page)页 · 金币\(state.coins) · 剩余\(Int(ceil(state.remainingSeconds)))秒 · 暂停原因：\(store.pauseReasons.sorted().joined(separator: ", "))"
    }
    @objc private func updateConnection() {
        let count = store.externalSessions.count
        let result = count > 0 ? "检测到\(count)个公开显示场景。仍须目视核查外屏。" : "未检测到独立公开显示场景；台词保持隐藏。"
        connection.text = bridgeMessage + "\n" + result
        if count == 0 { concealNotes() }
    }
    func concealNotes() {
        notes.resignFirstResponder(); notes.isHidden = true
        heldKeys.removeAll()
        store.setPause("notes", enabled: false)
    }
    @objc private func probeConcealForHost() { concealNotes() }
    @objc private func probePreviousPage() { store.turnPage(-1) }
    @objc private func probeNextPage() { store.turnPage(1) }
    @objc private func probeGrantCoins() { store.reward() }
    @objc private func probeTogglePause() { store.togglePause() }
    @objc private func probeResetClock() { store.resetClock() }
    @objc private func probeToggleTestNotes() {
        guard !store.externalSessions.isEmpty else {
            message("请先确认外屏出现独立绿色公开页，再测试假台词。"); return
        }
        if notes.isHidden { notes.isHidden = false }
        else { concealNotes(); becomeFirstResponder() }
    }
    func textViewDidBeginEditing(_ textView: UITextView) {
        heldKeys.removeAll(); store.setPause("notes", enabled: true)
    }
    func textViewDidEndEditing(_ textView: UITextView) {
        store.testNotes = textView.text; store.setPause("notes", enabled: false)
    }
    func textViewDidChange(_ textView: UITextView) { store.testNotes = textView.text }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if notes.isFirstResponder { super.pressesBegan(presses, with: event); return }
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let code = key.charactersIgnoringModifiers.lowercased()
            guard ["g", " "].contains(code),
                  key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else { continue }
            handled = true
            if heldKeys.insert(code).inserted {
                if code == "g" { store.reward() } else { store.togglePause() }
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key { heldKeys.remove(key.charactersIgnoringModifiers.lowercased()) }
        }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        heldKeys.removeAll(); super.pressesCancelled(presses, with: event)
    }

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stage0-private-test.json")
    }
    @objc private func probeSaveState() {
        do { try store.backupData().write(to: saveURL, options: .atomic); message("已本地保存测试状态。") }
        catch { message(error.localizedDescription) }
    }
    @objc private func probeRestoreState() {
        do { try store.restore(Data(contentsOf: saveURL)); notes.text = store.testNotes; message("已恢复，保持暂停。") }
        catch { message(error.localizedDescription) }
    }
    @objc private func probeExportBackup() {
        do {
            try store.backupData().write(to: saveURL, options: .atomic)
            concealNotes()
            present(UIDocumentPickerViewController(forExporting: [saveURL], asCopy: true), animated: true)
        } catch { message(error.localizedDescription) }
    }
    @objc private func probeImportBackup() {
        concealNotes()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1024 * 1024 else {
                message("测试存档限1 MiB，原状态未改变。"); return
            }
            try store.restore(Data(contentsOf: url)); notes.text = store.testNotes
            message("已导入，保持暂停。")
        } catch { message("导入失败，原状态未改变：\(error.localizedDescription)") }
    }
    private func message(_ text: String) {
        let alert = UIAlertController(title: "阶段0验证", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
