import SwiftUI
import UIKit

/// A responder inside the presented PVE screen; it remains independent of the
/// stage0 presenting controller and yields to every text editor/modal.
@MainActor
struct PVEKeyboardReceiver:UIViewControllerRepresentable {
    @ObservedObject var model:PVEAppSession
    @ObservedObject var teacher:TeacherSession
    func makeUIViewController(context:Context) -> PVEKeyboardController {
        let controller = PVEKeyboardController(); controller.model = model; controller.teacher = teacher; return controller
    }
    func updateUIViewController(_ controller:PVEKeyboardController,context:Context) {
        controller.model = model; controller.teacher = teacher
        if model.modalOpen || teacher.isEditingNotes {
            if controller.isFirstResponder { _ = controller.resignFirstResponder() }
        } else if !controller.isFirstResponder && UIApplication.shared.applicationState == .active {
            _ = controller.becomeFirstResponder()
        }
    }
}
@MainActor
final class PVEKeyboardController:UIViewController {
    weak var model:PVEAppSession?
    weak var teacher:TeacherSession?
    private var held:Set<Int> = []
    override var canBecomeFirstResponder:Bool { true }
    override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self,selector:#selector(clearHeldKeys),name:UIApplication.willResignActiveNotification,object:nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func clearHeldKeys() { held.removeAll() }
    override func viewDidAppear(_ animated:Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { held.removeAll(); return super.resignFirstResponder() }
    override func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        guard let model, let teacher, !model.modalOpen, !teacher.isEditingNotes else {
            held.removeAll(); super.pressesBegan(presses,with:event); return
        }
        var handled = false
        for press in presses {
            guard let key = press.key, key.modifierFlags.intersection([.command,.control,.alternate]).isEmpty else { continue }
            let code:String
            if (UIKeyboardHIDUsage.keyboard1.rawValue...UIKeyboardHIDUsage.keyboard7.rawValue).contains(key.keyCode.rawValue) { code = String(key.keyCode.rawValue - UIKeyboardHIDUsage.keyboard1.rawValue + 1) }
            else { code = key.charactersIgnoringModifiers.lowercased() }
            let arrow = model.bookOpen && [.keyboardLeftArrow,.keyboardRightArrow].contains(key.keyCode)
            guard arrow || ["g","a","s","e"," "].contains(code) || Int(code).map({ (1...7).contains($0) }) == true else { continue }
            handled = true
            guard held.insert(Int(key.keyCode.rawValue)).inserted else { continue }
            if arrow { teacher.turnPage(key.keyCode == .keyboardLeftArrow ? -1 : 1) }
            else { _ = model.handleKey(code,shift:key.modifierFlags.contains(.shift)) }
        }
        if !handled { super.pressesBegan(presses,with:event) }
    }
    override func pressesEnded(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        for press in presses { if let key = press.key { held.remove(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses,with:event)
    }
    override func pressesCancelled(_ presses:Set<UIPress>,with event:UIPressesEvent?) { held.removeAll(); super.pressesCancelled(presses,with:event) }
}
