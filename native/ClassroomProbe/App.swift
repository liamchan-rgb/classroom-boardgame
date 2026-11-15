import SwiftUI
import UIKit
import ClassroomProbeCore
import MeadowWorldSupport

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
        // A tap anywhere outside a text field ends typing (the shortcut keys work again right away).
        if let window=view.window {EndEditingTap.install(on:window)}

    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func clearPressedKeys() { heldKeys.removeAll() }
    override func resignFirstResponder() -> Bool { heldKeys.removeAll(); return super.resignFirstResponder() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let session = TeacherSession.shared
        guard !session.isEditingNotes,!UIResponder.classroomTyping else{heldKeys.removeAll();super.pressesBegan(presses,with:event);return}
        // A grant key is waiting for its amount: digits / Enter / Backspace / Esc belong to it.
        if session.game.grantCapture != nil,let key=presses.first?.key {
            switch key.keyCode {
            case .keyboardReturnOrEnter,.keypadEnter:session.game.grantCaptureCommit();return
            case .keyboardEscape:session.game.grantCaptureCancel();return
            case .keyboardDeleteOrBackspace:session.game.grantCaptureBackspace();return
            default:
                let c=key.charactersIgnoringModifiers
                if c.count==1,let d=c.first,d.isASCII,d.isNumber {session.game.grantCaptureDigit(d);return}
                // Any other key (except the grant keys themselves, which may be a double press) cancels the entry.
                if let t=ClassroomShortcuts.token(key),let a=ClassroomShortcuts.action(for:t),a == .award || a == .grantMovement {break}
                session.game.grantCaptureCancel()
            }
        }
        var handled=false
        for press in presses {
            guard let key=press.key,key.modifierFlags.intersection([.command,.control,.alternate]).isEmpty,
                  let token=ClassroomShortcuts.token(key),let action=ClassroomShortcuts.action(for:token) else{continue}
            // Over the pack, shop or another sheet only the classroom-wide tools (timer, scoreboard) answer.
            if session.game.modalOpen,!action.global {continue}
            handled=true;guard heldKeys.insert(token).inserted else{continue}
            perform(action,session:session)
        }
        if !handled {super.pressesBegan(presses,with:event)}
    }
    /// Teacher keyboard shortcuts (editable under 快捷键).
    private func perform(_ action:ClassroomShortcutAction,session:TeacherSession) {
        let game=session.game
        switch action {
        case .select1,.select2,.select3,.select4,.select5,.select6,.select7:
            // Number keys follow the seat numbers set by long-pressing in the grant picker.
            guard let seat=action.seat,let id=game.player(forSeat:seat) else{return}
            if game.bookTabActive {
                if game.grantDraft.recipients.contains(id){game.grantDraft.recipients.remove(id)}else{game.grantDraft.recipients.insert(id)}
            } else {game.select(id)}
        case .award:game.grantKey(.coins)
        case .grantMovement:game.grantKey(.movement)
        case .attack:game.battle(.attack)
        case .endTurn:game.battle(.endTurn)
        case .pauseResume:game.operation(.pauseOrResume)
        case .pageBack:session.turnPage(-1)
        case .pageForward:session.turnPage(1)
        case .openTimer:game.openTimer()
        case .timerStartPause:game.classTimer.toggle()
        case .timerPlus10:game.classTimer.add(10)
        case .toggleScoreboard:game.toggleScoreboard()
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {if let key=press.key,let token=ClassroomShortcuts.token(key) {heldKeys.remove(token)}}
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

extension UIResponder {
    private static weak var found:UIResponder?
    @objc private func classroomReportFirstResponder(_ sender:Any?){UIResponder.found=self}
    /// True while any text field or text view has the keyboard: shortcut keys must then reach the text.
    static var classroomTyping:Bool {
        found=nil
        UIApplication.shared.sendAction(#selector(classroomReportFirstResponder(_:)),to:nil,from:nil,for:nil)
        return found is UITextInput
    }
}

/// Window-wide tap that ends text input when the tap lands outside any text field / text view. It never swallows the tap.
@MainActor final class EndEditingTap:NSObject,UIGestureRecognizerDelegate {
    static let shared=EndEditingTap()
    static let name="classroomEndEditingTap"
    static func install(on window:UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where:{$0.name==name}) else{return}
        let tap=UITapGestureRecognizer(target:shared,action:#selector(fired(_:)))
        tap.name=name;tap.cancelsTouchesInView=false;tap.delaysTouchesBegan=false;tap.delaysTouchesEnded=false;tap.delegate=shared
        window.addGestureRecognizer(tap)
    }
    @objc private func fired(_ tap:UITapGestureRecognizer) {
        tap.view?.endEditing(true)
        // Hand the keys back to the console so shortcuts reach it.
        tap.view?.window?.rootViewController?.becomeFirstResponder()
    }
    func gestureRecognizer(_ g:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
        var v=touch.view
        while let current=v {if current is UITextField || current is UITextView || current is UISearchBar {return false};v=current.superview}
        return UIResponder.classroomTyping
    }
    func gestureRecognizer(_ g:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith other:UIGestureRecognizer)->Bool {true}
}
