import SwiftUI
import UIKit
import MeadowClassroomSupport

/// The teacher's laser pointer: L (or the top-bar button) turns it on; moving the pointer over the teacher's
/// preview (game or picture book; a finger on iPad) puts a red dot with a short trail on the TV / public window and
/// the preview. A click makes a ring. Positions are fractions of the 16:9 canvas, so every screen lines up.
@MainActor final class LaserPointer: ObservableObject {
    @Published var on = false { didSet { if !on { point = nil; trail = []; hovering = false } } }
    /// Where the dot is (fraction of the canvas), nil = hidden.
    @Published private(set) var point: CGPoint?
    @Published private(set) var trail: [(p: CGPoint, t: TimeInterval)] = []
    @Published private(set) var pulse: (p: CGPoint, t: TimeInterval)?
    /// Nothing moving: the drawing stops ticking.
    @Published private(set) var idle = true
    /// Pointing at a teacher panel the public screen copies (pack, shop): positions are fractions of that panel,
    /// whose shape this is; nil = the 16:9 game / book canvas.
    @Published private(set) var panelAspect: CGSize?
    private var hovering = false
    private var lastMove: TimeInterval = 0
    private var settle: DispatchWorkItem?
    static let trailLife: TimeInterval = 0.28
    static let pulseLife: TimeInterval = 0.6

    /// `location` in a view of `size`; points outside the canvas are clamped to its edge.
    func move(_ location: CGPoint, in size: CGSize, hover: Bool = false, panel: Bool = false) {
        guard on else { return }
        if panel { if panelAspect != size { panelAspect = size; trail = [] } } else if panelAspect != nil { panelAspect = nil; trail = [] }
        let r = panel ? CGRect(origin: .zero, size: size) : ClassroomCanvas.fitted(in: size)
        guard r.width > 0 else { return }
        let p = CGPoint(x: min(1, max(0, (location.x - r.minX) / r.width)), y: min(1, max(0, (location.y - r.minY) / r.height)))
        let now = Date.timeIntervalSinceReferenceDate
        if hover { hovering = true }
        lastMove = now
        trail.removeAll { now - $0.t > Self.trailLife }
        if let old = point { trail.append((old, now)) }
        point = p
        if idle { idle = false }
        scheduleSettle()
    }
    func click() {
        guard on, let p = point else { return }
        pulse = (p, Date.timeIntervalSinceReferenceDate); idle = false; scheduleSettle(after: Self.pulseLife)
    }
    /// The pointer left the preview (Mac).
    func leave() { hovering = false; point = nil; trail = [] }
    /// A finger lifted (iPad): the dot stays a moment, then goes unless the pointer is hovering (Mac).
    func release() {
        let at = lastMove
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.hovering, self.lastMove == at else { return }
            self.point = nil; self.trail = []
        }
    }
    private func scheduleSettle(after delay: TimeInterval = trailLife + 0.05) {
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = Date.timeIntervalSinceReferenceDate
            if now - self.lastMove >= Self.trailLife, self.pulse.map({ now - $0.t >= Self.pulseLife }) ?? true {
                self.trail = []; self.pulse = nil; self.idle = true
            } else { self.scheduleSettle(after: 0.1) }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// The dot, drawn in the TV overlays (TV, public window and the teacher's preview alike).
struct LaserLayer: View {
    @ObservedObject var laser: LaserPointer
    var body: some View {
        GeometryReader { g in
            if laser.on, laser.point != nil || laser.pulse != nil {
                // On a copied panel: where the public screen draws that copy (fitted, centred); else the canvas.
                let r = laser.panelAspect.map { LaserPointer.fit($0, in: g.size) } ?? ClassroomCanvas.fitted(in: g.size), unit = ClassroomCanvas.fitted(in: g.size).height / 720
                TimelineView(.animation(minimumInterval: 1 / 60, paused: laser.idle)) { context in
                    let now = context.date.timeIntervalSinceReferenceDate
                    let at = { (p: CGPoint) in CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height) }
                    ZStack {
                        if !laser.idle {
                            ForEach(Array(laser.trail.enumerated()), id: \.offset) { _, s in
                                let k = max(0, 1 - (now - s.t) / LaserPointer.trailLife)
                                Circle().fill(Color(red: 1, green: 0.15, blue: 0.1).opacity(0.55 * k))
                                    .frame(width: 16 * unit * (0.4 + 0.6 * k), height: 16 * unit * (0.4 + 0.6 * k)).position(at(s.p))
                            }
                        }
                        if let pulse = laser.pulse, now - pulse.t < LaserPointer.pulseLife {
                            let k = (now - pulse.t) / LaserPointer.pulseLife
                            Circle().stroke(Color(red: 1, green: 0.2, blue: 0.12).opacity(1 - k), lineWidth: 5 * unit * (1 - k) + 1)
                                .frame(width: (20 + 90 * k) * unit, height: (20 + 90 * k) * unit).position(at(pulse.p))
                        }
                        if let p = laser.point {
                            let c = at(p)
                            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.2, blue: 0.12).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 30 * unit))
                                .frame(width: 60 * unit, height: 60 * unit).position(c)
                            Circle().fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.18, blue: 0.1)], center: .center, startRadius: 0, endRadius: 8 * unit))
                                .frame(width: 16 * unit, height: 16 * unit).position(c)
                        }
                    }
                    // One Metal pass for the dot and its trail.
                    .drawingGroup()
                }
            }
        }.allowsHitTesting(false)
    }
}

/// Over the teacher's preview while the laser is on: takes the pointer (hover on Mac, a finger on iPad) instead
/// of the map / page below.
struct LaserCapture: View {
    @ObservedObject var laser: LaserPointer
    var body: some View {
        if laser.on {
            GeometryReader { g in
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): laser.move(p, in: g.size, hover: true)
                        case .ended: laser.leave()
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { laser.move($0.location, in: g.size) }
                        .onEnded { v in
                            if hypot(v.translation.width, v.translation.height) < 6 { laser.click() }
                            laser.release()
                        })
            }
        }
    }
}

/// Top-bar toggle (lit while on).
struct LaserButton: View {
    @ObservedObject var laser: LaserPointer
    var action: () -> Void
    var body: some View {
        Button { action() } label: { Label(laser.on ? "激光笔 开" : "激光笔", systemImage: laser.on ? "smallcircle.filled.circle.fill" : "smallcircle.filled.circle") }
            .foregroundStyle(laser.on ? Color.red : GameTheme.ink)
    }
}

extension LaserPointer {
    static func fit(_ aspect: CGSize, in host: CGSize) -> CGRect {
        guard aspect.width > 0, aspect.height > 0 else { return .zero }
        let k = min(host.width / aspect.width, host.height / aspect.height)
        let w = aspect.width * k, h = aspect.height * k
        return CGRect(x: (host.width - w) / 2, y: (host.height - h) / 2, width: w, height: h)
    }
}

/// Laid over the pack / shop while the laser is on: the pointer there marks the copy on the public screen
/// (hover on Mac, a finger on iPad; a click makes the ring). Taps do not reach the panel while it is there.
final class LaserPanelCatcher: UIView {
    weak var laser: LaserPointer?
    private var start: CGPoint?
    init(laser: LaserPointer) {
        self.laser = laser
        super.init(frame: .zero)
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:))); pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        // The same dot on the teacher's panel (the public screen draws it over its copy of the panel).
        let dot = UIHostingController(rootView: LaserLayer(laser: laser)).view!
        dot.backgroundColor = .clear; dot.isUserInteractionEnabled = false
        dot.frame = bounds; dot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(dot)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var panelSize: CGSize { superview?.bounds.size ?? bounds.size }
    @objc private func hover(_ g: UIHoverGestureRecognizer) {
        MainActor.assumeIsolated {
            switch g.state {
            case .began, .changed: laser?.move(g.location(in: self), in: panelSize, hover: true, panel: true)
            case .ended, .cancelled: laser?.leave()
            default: break
            }
        }
    }
    @objc private func drag(_ g: UIPanGestureRecognizer) {
        MainActor.assumeIsolated {
            laser?.move(g.location(in: self), in: panelSize, panel: true)
            if g.state == .ended || g.state == .cancelled { laser?.release() }
        }
    }
    @objc private func tap(_ g: UITapGestureRecognizer) {
        MainActor.assumeIsolated { laser?.move(g.location(in: self), in: panelSize, panel: true); laser?.click(); laser?.release() }
    }
}
