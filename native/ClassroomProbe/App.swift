import SwiftUI
import UIKit
import ClassroomProbeCore

@main
struct ClassroomProbeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            TeacherHost()
                .ignoresSafeArea()
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        TeacherSession.shared.display.ruleExample = nil
                        TeacherSession.shared.pause(.background, enabled: true)
                        TeacherSession.shared.concealNotes()
                    }
                }
        }
    }
}

@MainActor
struct TeacherHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TeacherHostController { TeacherHostController() }
    func updateUIViewController(_ controller: TeacherHostController, context: Context) {}
}

@MainActor
final class TeacherHostController: UIViewController {
    private var registration: UISceneAccessoryRegistration?
    private var heldKeys: Set<String> = []
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: TeacherConsole(session: .shared))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        NotificationCenter.default.addObserver(self, selector: #selector(clearPressedKeys),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        let configuration = UISceneConfiguration()
        configuration.delegateClass = PublicSceneDelegate.self
        registration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
        TeacherSession.shared.setRegistrationStatus("已注册iPadOS27公开场景，等待电视连接。")
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func clearPressedKeys() { heldKeys.removeAll() }
    override func resignFirstResponder() -> Bool { heldKeys.removeAll(); return super.resignFirstResponder() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let session = TeacherSession.shared
        guard !session.isEditingNotes, !session.rulesOpen else { heldKeys.removeAll(); super.pressesBegan(presses, with: event); return }
        var handled = false
        for press in presses {
            guard let key = press.key,
                  key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else { continue }
            let code = key.charactersIgnoringModifiers.lowercased()
            guard ["g", " "].contains(code) || (Int(code).map { (1...7).contains($0) } ?? false) else { continue }
            handled = true
            guard heldKeys.insert(code).inserted else { continue }
            if code == "g" { session.award() }
            else if code == " " { session.togglePause() }
            else if let number = Int(code) { session.select(number) }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { heldKeys.remove(key.charactersIgnoringModifiers.lowercased()) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        heldKeys.removeAll(); super.pressesCancelled(presses, with: event)
    }
}

@MainActor
@objc(ClassroomPublicSceneDelegate)
final class PublicSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let created = UIWindow(windowScene: windowScene)
        created.rootViewController = UIHostingController(rootView: PublicSurface(model: TeacherSession.shared.display))
        created.isHidden = false
        window = created
        TeacherSession.shared.setConnection(id: session.persistentIdentifier, connected: true)
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        TeacherSession.shared.setConnection(id: scene.session.persistentIdentifier, connected: false)
        window?.isHidden = true
        window = nil
    }
}
