import SwiftUI
import UIKit
import ClassroomProbeCore
import MeadowWorldSupport

@main
struct ClassroomProbeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Before iPadOS 27 (no scene accessories), a TV still gets the public screen through the app delegate.
    @UIApplicationDelegateAdaptor(ClassroomAppDelegate.self) private var appDelegate
    init() {
        // A long class makes the trip save large: encode and write it off the main thread (clicks stay instant),
        // and make sure it is on disk before the app goes to the background or quits.
        MeadowCampaignSession.persistInBackground = true
        MeadowCampaignSession.onSaveError = { error in
            DispatchQueue.main.async { TeacherSession.shared.show("行程保存失败：" + error.localizedDescription) }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MeadowCampaignSession.flushPendingSaves()
        }
    }
    var body: some Scene {
        WindowGroup {
            TeacherHost()
                .ignoresSafeArea()
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        MeadowCampaignSession.flushPendingSaves()
                        TeacherSession.shared.pause(.background,enabled:true)
                        TeacherSession.shared.concealNotes()
                    } else {TeacherSession.shared.pause(.background,enabled:false)}
                }
        }
        #if targetEnvironment(macCatalyst)
        // One teacher console only: no File ▸ New Window (a second console would fight over the game view).
        .commands { CommandGroup(replacing: .newItem) {} }
        #endif
        #if targetEnvironment(macCatalyst)
        // Mac has no external-display scene accessory: the public output is a second
        // window the teacher drags onto the projector/TV screen and makes full screen.
        WindowGroup("课堂公开画面", id: MacPublicWindow.sceneID) { MacPublicWindow() }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Mac counterpart of `PublicSceneDelegate`: same public surface, same connection bookkeeping,
/// and, like the iPad's non-interactive external scene, it takes no clicks.
struct MacPublicWindow: View {
    static let sceneID = "classroom-public-output"
    static let connectionID = "mac-public-window"
    static let title = "课堂公开画面"
    var body: some View {
        PublicSurface(model: TeacherSession.shared.display, game: TeacherSession.shared.game)
            .allowsHitTesting(false)
            .background(Color.black)
            .ignoresSafeArea()
            // Opened while a second (separate) screen is attached: it moves there and goes full screen by itself.
            .background(SceneProbe { scene in
                _ = MacDisplayMonitor.shared
                scene.title = Self.title
                MacDisplays.placePublicWindow(scene, title: Self.title)
            })
            .onAppear { TeacherSession.shared.setConnection(id: Self.connectionID, connected: true) }
            .onDisappear { TeacherSession.shared.setConnection(id: Self.connectionID, connected: false) }
    }
}

/// Teacher toolbar button that opens or closes the Mac public window.
struct MacPublicWindowButton: View {
    var connected: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        Button {
            if connected { dismissWindow(id: MacPublicWindow.sceneID) } else { openWindow(id: MacPublicWindow.sceneID) }
        } label: {
            Label(connected ? "关闭公开" : "公开窗口", systemImage: connected ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle")
        }
    }
}
#endif

@MainActor
struct TeacherHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TeacherHostController { TeacherHostController() }
    func updateUIViewController(_ controller: TeacherHostController, context: Context) {}
}

@MainActor
final class TeacherHostController: UIViewController {
    #if !targetEnvironment(macCatalyst)
    /// An iPadOS 27 `UISceneAccessoryRegistration` (kept as Any so the app also runs on older iPadOS).
    private var registration: Any?
    #endif
    private var heldKeys: Set<String> = []
    /// The live teacher console. Mac can bring back an extra console window (window restoration); it closes itself.
    private static weak var primary: TeacherHostController?
    private var isPrimary: Bool { Self.primary === self }
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        if Self.primary?.view.window == nil { Self.primary = self }
        if isPrimary { TeacherSession.shared.game.privatePresenter=self }
        if isPrimary { ClassroomGlobalTools.handlePresses={[weak self] presses in MainActor.assumeIsolated{self?.globalPresses(presses) ?? false}} }
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
        #if targetEnvironment(macCatalyst)
        _ = configuration
        TeacherSession.shared.setRegistrationStatus("Mac：在屏幕镜像里选“用作扩展显示器”后点“公开窗口”，学生画面会自动放到投影屏并全屏。")
        #else
        if #available(iOS 27.0, *) {
            registration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
            TeacherSession.shared.setRegistrationStatus("已注册iPadOS27公开场景，等待电视连接。")
        } else {
            _ = configuration
            TeacherSession.shared.setRegistrationStatus("等待电视连接（插上或隔空播放后自动显示学生画面）。")
        }
        #endif
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if targetEnvironment(macCatalyst)
        if !isPrimary, let scene = view.window?.windowScene {
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil)
            return
        }
        #endif
        becomeFirstResponder()
        // A tap anywhere outside a text field ends typing (the shortcut keys work again right away).
        if let window=view.window {EndEditingTap.install(on:window)}

    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func clearPressedKeys() { heldKeys.removeAll() }
    override func resignFirstResponder() -> Bool { heldKeys.removeAll(); return super.resignFirstResponder() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let session = TeacherSession.shared
        // A grant icon is being dragged: digits and Backspace change that box's amount.
        if BookDropTargets.shared.dragging != nil,presses.contains(where:{$0.key.map{BookDropTargets.shared.dragKey($0)} ?? false}) {return}
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
        // An answer is showing: Esc or Space ends the reveal right away (advancing any waiting mini-game).
        if presses.contains(where:{$0.key?.keyCode == .keyboardEscape || $0.key?.keyCode == .keyboardSpacebar}),!UIResponder.classroomTyping,session.game.skipQuizReveal() {return}
        // A question panel docked beside the preview gets its keys (Esc, ⏎, 1–7, D/C…) even when the keyboard focus
        // is somewhere else in the window, e.g. back on the notes after the word-card popup closed.
        if let onKey=session.game.dockContent?.onKey {
            var docked=false
            for press in presses {
                guard let key=press.key,key.modifierFlags.intersection([.command,.control,.alternate]).isEmpty,
                      let token=ClassroomShortcuts.panelToken(key),onKey(token) else{continue}
                docked=true
            }
            if docked {return}
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
    /// Timer / scoreboard keys pressed while a game sheet (pack, shop) has the keyboard.
    func globalPresses(_ presses:Set<UIPress>)->Bool {
        guard !UIResponder.classroomTyping else{return false}
        var handled=false
        for press in presses {
            guard let key=press.key,key.modifierFlags.intersection([.command,.control,.alternate]).isEmpty,
                  let token=ClassroomShortcuts.token(key),let action=ClassroomShortcuts.action(for:token),action.global else{continue}
            perform(action,session:TeacherSession.shared);handled=true
        }
        return handled
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
        case .goToPage:if game.bookTabActive {session.pageJumpRequest += 1}
        case .openTimer:game.openTimer()
        case .timerStartPause:game.classTimer.toggle()
        case .timerPlus10:game.classTimer.add(10)
        case .timerClose:game.classTimer.reset();game.classTimer.hide()
        case .toggleScoreboard:game.toggleScoreboard()
        case .toggleTeamScores:game.toggleTeamScores()
        case .openQuizReport:game.openQuizReport()
        case .openQuiz:game.openQuiz()
        case .openClassQuiz:game.openClassQuiz()
        case .openPractice:game.openPractice()
        case .openClassPractice:game.openPractice(classwide:false)
        case .toggleLaser:game.toggleLaser()
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

/// iPadOS before 27: a connected TV asks the app delegate for its scene; it shows the public screen.
final class ClassroomAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if session.role == .windowExternalDisplayNonInteractive {
            let configuration = UISceneConfiguration(name: "Public", sessionRole: session.role)
            configuration.delegateClass = PublicSceneDelegate.self
            return configuration
        }
        return UISceneConfiguration(name: nil, sessionRole: session.role)
    }
}

@MainActor
@objc(ClassroomPublicSceneDelegate)
final class PublicSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private weak var windowScene: UIWindowScene?
    /// The TV scenes that are connected now (the iPad 公开屏 switch shows / hides / rebuilds their windows).
    static let live = NSHashTable<PublicSceneDelegate>.weakObjects()
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        self.windowScene = windowScene
        Self.live.add(self)
        TeacherSession.shared.setConnection(id: session.persistentIdentifier, connected: true)
        if TeacherSession.shared.publicScreenOn { show() }
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        Self.live.remove(self)
        TeacherSession.shared.setConnection(id: scene.session.persistentIdentifier, connected: false)
        window?.isHidden = true
        window = nil
    }
    /// A fresh window with the public surface, filling the TV (the old one, if any, is dropped).
    func show() {
        guard let windowScene else { return }
        window?.isHidden = true
        let created = UIWindow(windowScene: windowScene)
        created.frame = windowScene.coordinateSpace.bounds
        created.backgroundColor = .black
        created.rootViewController = UIHostingController(rootView: PublicSurface(model: TeacherSession.shared.display,game:TeacherSession.shared.game).ignoresSafeArea())
        created.isHidden = false
        window = created
    }
    /// Off: the TV goes back to the system's mirror of the iPad.
    func hide() { window?.isHidden = true; window = nil }
    static func apply(_ on: Bool) { for d in live.allObjects { if on { d.show() } else { d.hide() } } }
}

#if !targetEnvironment(macCatalyst)
/// iPad counterpart of the Mac 公开窗口 button: with a TV / screen mirroring on, shows the students' screen on it
/// (on) or lets the TV mirror the iPad (off); pressing it again rebuilds the TV window.
struct IPadPublicScreenButton: View {
    @ObservedObject var session: TeacherSession
    var connected: Bool
    var body: some View {
        Button {
            if session.publicScreenOn && connected { session.publicScreenOn = false } else { session.publicScreenOn = true }
            PublicSceneDelegate.apply(session.publicScreenOn)
        } label: {
            Label(!connected ? "未接屏" : session.publicScreenOn ? "公开屏" : "镜像中",
                  systemImage: !connected ? "tv.slash" : session.publicScreenOn ? "tv.fill" : "rectangle.on.rectangle")
        }
        .disabled(!connected)
        .help("接上电视或打开屏幕镜像后：开＝电视显示学生画面，关＝电视镜像 iPad")
    }
}
#endif

extension UIResponder {
    private static weak var found:UIResponder?
    @objc private func classroomReportFirstResponder(_ sender:Any?){UIResponder.found=self}
    /// True while any text field or text view has the keyboard: shortcut keys must then reach the text.
    static var classroomTyping:Bool {
        found=nil
        UIApplication.shared.sendAction(#selector(classroomReportFirstResponder(_:)),to:nil,from:nil,for:nil)
        // Read-only text (the notes after double-clicking a word) holds the focus but takes no typing: the
        // shortcuts and the docked question panel's keys must still work.
        if let text=found as? UITextView {return text.isEditable}
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
