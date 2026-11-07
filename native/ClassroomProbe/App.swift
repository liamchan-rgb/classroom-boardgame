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
                        TeacherSession.shared.pause(.background,enabled:true)
                        TeacherSession.shared.concealNotes()
                    } else {TeacherSession.shared.pause(.background,enabled:false)}
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
        TeacherSession.shared.game.privatePresenter=self
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
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); becomeFirstResponder()

    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func clearPressedKeys() { heldKeys.removeAll() }
    override func resignFirstResponder() -> Bool { heldKeys.removeAll(); return super.resignFirstResponder() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let session = TeacherSession.shared
        guard !session.isEditingNotes,!session.game.modalOpen else{heldKeys.removeAll();super.pressesBegan(presses,with:event);return}
        var handled=false
        for press in presses {
            guard let key=press.key,key.modifierFlags.intersection([.command,.control,.alternate]).isEmpty else{continue}
            let code=key.charactersIgnoringModifiers.lowercased()
            guard ["1","2","g","a","e"," "].contains(code) || key.keyCode == .keyboardLeftArrow || key.keyCode == .keyboardRightArrow else{continue}
            handled=true;guard heldKeys.insert(code).inserted else{continue}
            if key.keyCode == .keyboardLeftArrow {session.turnPage(-1)}
            else if key.keyCode == .keyboardRightArrow {session.turnPage(1)}
            else if code=="1" || code=="2" {session.game.select("p"+code)}
            else if code=="g" {session.game.award()}
            else if code=="a" {session.game.battle(.attack)}
            else if code=="e" {session.game.battle(.endTurn)}
            else if code==" " {session.game.operation(.pauseOrResume)}
        }
        if !handled {super.pressesBegan(presses,with:event)}
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                heldKeys.remove(key.charactersIgnoringModifiers.lowercased())
                if key.keyCode == .keyboardLeftArrow { heldKeys.remove("book-left") }
                if key.keyCode == .keyboardRightArrow { heldKeys.remove("book-right") }
                if (UIKeyboardHIDUsage.keyboard1.rawValue...UIKeyboardHIDUsage.keyboard7.rawValue).contains(key.keyCode.rawValue) {
                    heldKeys.remove(String(key.keyCode.rawValue - UIKeyboardHIDUsage.keyboard1.rawValue + 1))
                }
            }
        }
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
        created.rootViewController = UIHostingController(rootView: PublicSurface(model: TeacherSession.shared.display,game:TeacherSession.shared.game))
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
