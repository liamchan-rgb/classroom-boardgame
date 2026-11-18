#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import Darwin

/// The Mac's displays, read through CoreGraphics (looked up at run time: the display-configuration calls are not in
/// the Catalyst SDK). Used to warn when the projector only mirrors the Mac screen, to switch it to a separate
/// display, and to put the public window on the second screen.
enum MacDisplays {
    /// Diagnostics for the public-window placement (temp folder, overwritten each launch).
    static func trace(_ text: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("public-window.log")
        let line = "\(Date()) \(text)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
    private typealias OnlineList = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private typealias Flag = @convention(c) (UInt32) -> Int32
    private typealias Mirrors = @convention(c) (UInt32) -> UInt32
    private typealias Bounds = @convention(c) (UInt32) -> CGRect
    private typealias Begin = @convention(c) (UnsafeMutablePointer<OpaquePointer?>) -> Int32
    private typealias Configure = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Int32
    private typealias Complete = @convention(c) (OpaquePointer?, UInt32) -> Int32
    private typealias Cancel = @convention(c) (OpaquePointer?) -> Int32
    private static func fn<T>(_ name: String, _ type: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(p, to: type)
    }
    private static let online = fn("CGGetOnlineDisplayList", OnlineList.self)
    private static let isMain = fn("CGDisplayIsMain", Flag.self)
    private static let inMirrorSet = fn("CGDisplayIsInMirrorSet", Flag.self)
    private static let mirrorsDisplay = fn("CGDisplayMirrorsDisplay", Mirrors.self)
    private static let bounds = fn("CGDisplayBounds", Bounds.self)

    struct Status: Equatable {
        /// Displays besides the Mac's main one.
        var others = 0
        /// Some display shows a copy of another (the projector only mirrors the Mac).
        var mirrored = false
        /// Where the second (separate) screen is, in global display points.
        var second: CGRect?
    }
    static func status() -> Status {
        guard let online, let isMain, let inMirrorSet, let mirrorsDisplay, let bounds else { return Status() }
        var ids = [UInt32](repeating: 0, count: 16), count: UInt32 = 0
        guard online(16, &ids, &count) == 0 else { return Status() }
        let list = ids.prefix(Int(count))
        var s = Status()
        s.others = list.filter { isMain($0) == 0 && mirrorsDisplay($0) == 0 }.count + list.filter { mirrorsDisplay($0) != 0 }.count
        s.mirrored = list.contains { inMirrorSet($0) != 0 }
        s.second = list.first { isMain($0) == 0 && mirrorsDisplay($0) == 0 && inMirrorSet($0) == 0 }.map { bounds($0) }
        return s
    }
    /// Turns mirroring off for this login session: every display that copies another becomes a separate screen.
    @discardableResult static func stopMirroring() -> Bool {
        guard let online, let mirrorsDisplay, let begin = fn("CGBeginDisplayConfiguration", Begin.self),
              let configure = fn("CGConfigureDisplayMirrorOfDisplay", Configure.self),
              let complete = fn("CGCompleteDisplayConfiguration", Complete.self), let cancel = fn("CGCancelDisplayConfiguration", Cancel.self) else { return false }
        var ids = [UInt32](repeating: 0, count: 16), count: UInt32 = 0
        guard online(16, &ids, &count) == 0 else { return false }
        var config: OpaquePointer?
        guard begin(&config) == 0 else { return false }
        var changed = false
        for id in ids.prefix(Int(count)) where mirrorsDisplay(id) != 0 { if configure(config, id, 0) == 0 { changed = true } }
        guard changed else { _ = cancel(config); return false }
        return complete(config, 1) == 0   // kCGConfigureForSession
    }

    /// Moves the public window to the second screen and makes it full screen there.
    /// The open public window's scene (to move it when a separate screen shows up later).
    static weak var publicScene: UIWindowScene?
    static func placePublicWindow(_ scene: UIWindowScene, title: String) {
        publicScene = scene
        let st = status()
        trace("displays others=\(st.others) mirrored=\(st.mirrored) second=\(String(describing: st.second)) online=\(online != nil)")
        guard let frame = st.second else { return }
        scene.requestGeometryUpdate(.Mac(systemFrame: frame.insetBy(dx: 40, dy: 60))) { error in trace("geometry error \(error.localizedDescription)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { trace("scene frame after move \(scene.effectiveGeometry.systemFrame)") }
        // Full screen happens on the screen the window is on, so give the move a moment first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { toggleFullScreen(title: title, enter: true) }
    }
    /// The AppKit window behind a Catalyst scene, found by its title, asked to enter / leave full screen.
    static func toggleFullScreen(title: String, enter: Bool) {
        guard let appClass = NSClassFromString("NSApplication") as? NSObject.Type,
              let app = appClass.value(forKey: "sharedApplication") as? NSObject,
              let windows = app.value(forKey: "windows") as? [NSObject],
              let window = windows.first(where: { ($0.value(forKey: "title") as? String)?.contains(title) == true }) else {
            trace("no AppKit window titled \(title)"); return
        }
        let mask = (window.value(forKey: "styleMask") as? UInt) ?? 0
        let isFull = mask & (1 << 14) != 0   // NSWindowStyleMaskFullScreen
        if isFull != enter { window.perform(NSSelectorFromString("toggleFullScreen:"), with: nil) }
    }
}

/// Watches the displays every two seconds for the teacher bar (cheap CoreGraphics calls).
@MainActor final class MacDisplayMonitor: ObservableObject {
    static let shared = MacDisplayMonitor()
    @Published private(set) var status = MacDisplays.status()
    private var timer: Timer?
    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let s = MacDisplays.status()
                guard s != self?.status else { return }
                let appeared = self?.status.second == nil && s.second != nil
                self?.status = s
                // A separate screen turned up (projector connected, or mirroring switched off) while the public
                // window is open: move it there.
                if appeared, let scene = MacDisplays.publicScene, scene.activationState != .unattached {
                    MacDisplays.placePublicWindow(scene, title: MacPublicWindow.title)
                }
            }
        }
    }
    func refresh() { status = MacDisplays.status() }
}

/// Teacher bar warning when the projector only mirrors the Mac: one click makes it a separate screen.
struct MacMirrorWarning: View {
    @ObservedObject var monitor = MacDisplayMonitor.shared
    @State private var failed = false
    var body: some View {
        if monitor.status.mirrored {
            Button {
                failed = !MacDisplays.stopMirroring()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { monitor.refresh() }
            } label: {
                Label(failed ? "请在系统设置 › 显示器里改为扩展显示器" : "投影屏在镜像 · 改为单独显示", systemImage: "rectangle.on.rectangle.slash")
            }
            .buttonStyle(GlassIconButtonStyle(tint: .orange, prominent: true))
            .help("镜像时投影屏只会复制 Mac 屏幕，公开画面无法单独显示。")
        }
    }
}

/// Finds the window scene a SwiftUI view lives in (the public window places itself on the second screen).
struct SceneProbe: UIViewRepresentable {
    var found: (UIWindowScene) -> Void
    final class Probe: UIView {
        var found: ((UIWindowScene) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); MacDisplays.trace("probe window=\(window != nil) scene=\(window?.windowScene != nil)"); if let scene = window?.windowScene { let f = found; found = nil; f?(scene) } }
    }
    func makeUIView(context: Context) -> Probe { let p = Probe(); p.found = found; p.isUserInteractionEnabled = false; return p }
    func updateUIView(_ view: Probe, context: Context) {}
}
#endif
