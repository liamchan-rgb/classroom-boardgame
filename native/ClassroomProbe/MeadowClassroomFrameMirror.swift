import SwiftUI
import UIKit

/// Both layers originate in the one clean game controller, never the teacher root.
struct MeadowTeacherPreviewFrame {
    let map:CGImage?
    let mapRect:CGRect
    let overlay:UIImage?
    let background:UIColor
}
@MainActor final class MeadowFrameMirror:ObservableObject {
    @Published var frame:MeadowTeacherPreviewFrame?
}
struct MeadowTeacherMirror:View {
    @ObservedObject var mirror:MeadowFrameMirror
    var body:some View {
        ZStack(alignment:.topLeading) {
            if let frame=mirror.frame {
                Color(uiColor:frame.background)
                if let map=frame.map {
                    Image(decorative:map,scale:1).resizable().interpolation(.none)
                        .frame(width:frame.mapRect.width,height:frame.mapRect.height)
                        .position(x:frame.mapRect.midX,y:frame.mapRect.midY)
                }
                if let overlay=frame.overlay {Image(uiImage:overlay).resizable().interpolation(.none)}
            }else{Color.black;Text("正在同步游戏画面…").foregroundStyle(.white)}
        }
    }
}

/// The teacher's view of the TV, drawn by the GPU: every display frame it takes a render-server snapshot view of the
/// live game (`snapshotView(afterScreenUpdates:false)`). The snapshot refers to the picture the GPU already composited
/// for the TV, so nothing is re-rasterized or copied to the CPU, and everything the TV shows (Metal map, skill effects,
/// pixel heroes) appears at full size. If the system cannot provide a snapshot, the image mirror is used instead.
struct MeadowLiveMirror:View {
    /// Teacher's choice (更多 → 教师画面): GPU live view (default) or the older image mirror.
    static var preferred:Bool {
        get {UserDefaults.standard.object(forKey:"classroom.liveMirror") as? Bool ?? true}
        set {UserDefaults.standard.set(newValue,forKey:"classroom.liveMirror")}
    }
    @ObservedObject var game:MeadowTeacherCoordinator
    @State private var failed=false
    var body:some View {
        if failed || !game.liveMirrorPreferred {MeadowTeacherMirror(mirror:game.frameMirror)}
        else {MeadowLiveMirrorHost(game:game,onFailure:{failed=true})}
    }
}
private struct MeadowLiveMirrorHost:UIViewRepresentable {
    let game:MeadowTeacherCoordinator
    var onFailure:()->Void
    func makeUIView(context:Context)->MeadowLiveMirrorView {
        let view=MeadowLiveMirrorView();view.game=game;view.onFailure=onFailure;return view
    }
    func updateUIView(_ view:MeadowLiveMirrorView,context:Context){view.game=game;view.onFailure=onFailure}
    static func dismantleUIView(_ view:MeadowLiveMirrorView,coordinator:()){view.stop()}
}
final class MeadowLiveMirrorView:UIView {
    weak var game:MeadowTeacherCoordinator?
    var onFailure:(()->Void)?
    private var link:CADisplayLink?
    private var current:UIView?
    private var misses=0
    private var registered=false
    override init(frame:CGRect){super.init(frame:frame);backgroundColor = .black;clipsToBounds=true;isUserInteractionEnabled=false}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {stop();return}
        guard link == nil else{return}
        let link=CADisplayLink(target:MeadowLiveMirrorTarget(self),selector:#selector(MeadowLiveMirrorTarget.tick))
        // The TV runs the game at 60 Hz; the teacher's view refreshes at 30, which is smooth and halves the cost.
        link.preferredFrameRateRange=CAFrameRateRange(minimum:20,maximum:30,preferred:30)
        link.add(to:.main,forMode:.common);self.link=link
        if !registered {registered=true;game?.setLiveMirror(true)}
    }
    func stop(){
        link?.invalidate();link=nil
        current?.removeFromSuperview();current=nil
        if registered {registered=false;game?.setLiveMirror(false)}
    }
    fileprivate func tick() {
        guard let game,let source=game.renderer?.view,source.window != nil,game.surface != .book else{return}
        guard let snapshot=source.snapshotView(afterScreenUpdates:false) else {
            // A few misses can happen while the TV window is being (re)attached; give up only if it keeps failing.
            misses += 1
            if misses>90 {stop();onFailure?()}
            return
        }
        misses=0
        snapshot.frame=CGRect(origin:.zero,size:bounds.size);snapshot.isUserInteractionEnabled=false
        addSubview(snapshot)
        current?.removeFromSuperview();current=snapshot
    }
}
/// Keeps the display link from retaining the view.
private final class MeadowLiveMirrorTarget:NSObject {
    weak var view:MeadowLiveMirrorView?
    init(_ view:MeadowLiveMirrorView){self.view=view}
    @objc func tick(){view?.tick()}
}

/// The inventory and shop open on the teacher's own window (they take input). The public screen shows a live,
/// read-only copy of exactly that screen — same art, same tab, same selection — using the same render-server
/// snapshot as the teacher's live mirror. Only these two screens are copied; other teacher panels stay private.
struct MeadowPanelMirror:UIViewRepresentable {
    let game:MeadowTeacherCoordinator
    func makeUIView(context:Context)->MeadowPanelMirrorView {let view=MeadowPanelMirrorView();view.game=game;return view}
    func updateUIView(_ view:MeadowPanelMirrorView,context:Context){view.game=game}
    static func dismantleUIView(_ view:MeadowPanelMirrorView,coordinator:()){view.stop()}
}
final class MeadowPanelMirrorView:UIView {
    weak var game:MeadowTeacherCoordinator?
    private var link:CADisplayLink?
    private var current:UIView?
    override init(frame:CGRect){super.init(frame:frame);backgroundColor = .black;clipsToBounds=true;isUserInteractionEnabled=false;isHidden=true}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {stop();return}
        guard link == nil else{return}
        let link=CADisplayLink(target:MeadowPanelMirrorTarget(self),selector:#selector(MeadowPanelMirrorTarget.tick))
        link.preferredFrameRateRange=CAFrameRateRange(minimum:20,maximum:30,preferred:30)
        link.add(to:.main,forMode:.common);self.link=link
    }
    func stop(){link?.invalidate();link=nil;clear()}
    private func clear(){current?.removeFromSuperview();current=nil;isHidden=true}
    fileprivate func tick() {
        guard let source=game?.publicPanelSource,source.window != nil,source.bounds.width>0,source.bounds.height>0,
              let snapshot=source.snapshotView(afterScreenUpdates:false) else{clear();return}
        // Same aspect as the teacher's screen, fitted into the public display.
        let scale=min(bounds.width/source.bounds.width,bounds.height/source.bounds.height)
        snapshot.isUserInteractionEnabled=false
        snapshot.bounds=CGRect(origin:.zero,size:source.bounds.size)
        snapshot.transform=CGAffineTransform(scaleX:scale,y:scale)
        snapshot.center=CGPoint(x:bounds.midX,y:bounds.midY)
        addSubview(snapshot)
        current?.removeFromSuperview();current=snapshot;isHidden=false
    }
}
private final class MeadowPanelMirrorTarget:NSObject {
    weak var view:MeadowPanelMirrorView?
    init(_ view:MeadowPanelMirrorView){self.view=view}
    @objc func tick(){view?.tick()}
}
