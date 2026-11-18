import SwiftUI
import UIKit
import ClassroomProbeCore

// MARK: - Rendered page

/// Which slide element (or which of its paragraphs) a moving layer holds.
struct DeckLayerKey: Hashable {
    var element: Int
    var paragraphs: ClosedRange<Int>?
}
/// One animated part of a slide, cropped to its box (page pixels).
struct DeckLayer {
    var key: DeckLayerKey
    var image: UIImage
    var frame: CGRect
}
/// Drawing order: still runs are full-page pictures, layers sit between them at their own depth.
enum DeckPiece {
    case still(UIImage)
    case layer(Int)
}
struct DeckStep {
    var layer: Int
    var effect: SlideEffect
}
/// A slide ready for the screen: its pictures plus the build (effects on entry, then per click).
struct DeckPage {
    var size: CGSize
    var background: UIColor
    var pieces: [DeckPiece]
    var layers: [DeckLayer]
    var entry: [DeckStep]
    var clicks: [[DeckStep]]
    var transition: PageTransitionEffect?

    /// How every layer looks with nothing played (`clicks` nil) or after the entry effects and `clicks` clicks.
    func looks(after clicks: Int?) -> [DeckLook] {
        var looks = layers.indices.map { index -> DeckLook in
            // A layer whose first effect brings it in starts hidden, the way that effect hides it.
            guard let first = (entry + self.clicks.flatMap { $0 }).first(where: { $0.layer == index }) else { return .visible }
            return first.effect.kind == .entrance ? hidden(first) : .visible
        }
        guard let clicks else { return looks }
        for step in entry + self.clicks.prefix(clicks).flatMap({ $0 }) {
            switch step.effect.kind {
            case .entrance: looks[step.layer] = .visible
            case .exit: looks[step.layer] = hidden(step)
            case .emphasis: break
            }
        }
        return looks
    }
    /// The look an entrance starts from / an exit ends at (page pixels for offsets).
    func hidden(_ step: DeckStep) -> DeckLook {
        let frame = layers[step.layer].frame, effect = step.effect
        var look = DeckLook.visible
        switch effect.style {
        case "fly":
            switch effect.direction {
            case "left": look.dx = -frame.maxX - 8
            case "right": look.dx = size.width - frame.minX + 8
            case "top": look.dy = -frame.maxY - 8
            default: look.dy = size.height - frame.minY + 8
            }
        case "bounce": look.dy = -frame.maxY - 8
        case "float": look.opacity = 0; look.dy = (effect.direction == "top" ? -1 : 1) * size.height * 0.08
        case "zoom": look.opacity = 0; look.scale = 0.2
        case "wipe": look.reveal = 0; look.edge = effect.direction
        default: look.opacity = 0
        }
        return look
    }
}

struct DeckLook: Equatable {
    var opacity: Double = 1
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scale: CGFloat = 1
    /// Wipe: share of the box uncovered from `edge`.
    var reveal: CGFloat = 1
    var edge = "left"
    /// Emphasis, played on top of the rest.
    var pulse: CGFloat = 1
    var rotation: Double = 0
    static let visible = DeckLook()
    /// The resting part only, so emphasis leftovers do not count as a difference.
    func sameRest(_ other: DeckLook) -> Bool {
        opacity == other.opacity && dx == other.dx && dy == other.dy && scale == other.scale && reveal == other.reveal
    }
}

// MARK: - Animated page view

/// Plays one slide: entry effects when it appears, then one click group each time the teacher steps forward.
/// The TV and the teacher's preview each run their own copy from the same published step.
struct DeckPageView: View {
    @ObservedObject var model: PublicDisplayModel
    let page: DeckPage
    /// Drawn at this step and never animated (the page sliding away during a transition).
    var frozenStep: Int? = nil
    @State private var looks: [DeckLook] = []
    @State private var shownStep = -1

    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width / page.size.width, g.size.height / page.size.height)
            ZStack(alignment: .topLeading) {
                Color(page.background)
                ForEach(page.pieces.indices, id: \.self) { index in
                    switch page.pieces[index] {
                    case .still(let image):
                        Image(uiImage: image).resizable().frame(width: page.size.width * k, height: page.size.height * k)
                    case .layer(let layer):
                        layerView(layer, k: k)
                    }
                }
            }
            .frame(width: page.size.width * k, height: page.size.height * k, alignment: .topLeading)
            .clipped()
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .onAppear { enter() }
        .onChange(of: model.buildStep) { _, step in advance(to: step) }
    }

    @ViewBuilder private func layerView(_ index: Int, k: CGFloat) -> some View {
        let layer = page.layers[index], look = looks.indices.contains(index) ? looks[index] : .visible
        let horizontal = look.edge == "left" || look.edge == "right"
        let anchor: UnitPoint = ["left": .leading, "right": .trailing, "top": .top, "bottom": .bottom][look.edge] ?? .leading
        Image(uiImage: layer.image).resizable()
            .frame(width: layer.frame.width * k, height: layer.frame.height * k)
            .mask {
                Rectangle().scaleEffect(x: horizontal ? max(0.0001, look.reveal) : 1, y: horizontal ? 1 : max(0.0001, look.reveal), anchor: anchor)
            }
            .scaleEffect(look.scale * look.pulse)
            .rotationEffect(.degrees(look.rotation))
            .opacity(look.opacity)
            .offset(x: (layer.frame.minX + look.dx) * k, y: (layer.frame.minY + look.dy) * k)
    }

    /// A page that just arrived plays its entry effects; one shown again later (tab switch) is drawn as it stands.
    private func enter() {
        if let frozenStep { looks = page.looks(after: frozenStep); shownStep = frozenStep; return }
        let fresh = Date().timeIntervalSince(model.entryStarted) < 2 && model.buildStep == 0
        shownStep = model.buildStep
        if fresh {
            looks = page.looks(after: nil)
            DispatchQueue.main.async { play(page.entry) }
        } else { looks = page.looks(after: model.buildStep) }
    }
    private func advance(to step: Int) {
        guard frozenStep == nil else { return }
        defer { shownStep = step }
        if step == shownStep + 1, page.clicks.indices.contains(shownStep) { play(page.clicks[shownStep]); return }
        // Stepping back (or a jump) undoes without animation, like PowerPoint.
        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) { looks = page.looks(after: step) }
    }
    private func play(_ steps: [DeckStep]) {
        guard !steps.isEmpty else { return }
        if looks.count != page.layers.count { looks = page.looks(after: nil) }
        var needsReset: [Int: DeckLook] = [:]
        for step in steps where step.effect.kind == .entrance {
            let start = page.hidden(step)
            if !looks[step.layer].sameRest(start) { needsReset[step.layer] = start }
        }
        // An entrance after an exit of another kind first jumps to its own starting look, then animates.
        if !needsReset.isEmpty {
            var still = Transaction(); still.disablesAnimations = true
            withTransaction(still) { for (layer, look) in needsReset { looks[layer].opacity = look.opacity; looks[layer].dx = look.dx; looks[layer].dy = look.dy; looks[layer].scale = look.scale; looks[layer].reveal = look.reveal; looks[layer].edge = look.edge } }
            DispatchQueue.main.async { run(steps) }
        } else { run(steps) }
    }
    private func run(_ steps: [DeckStep]) {
        for step in steps {
            let effect = step.effect, layer = step.layer, d = max(0.001, effect.duration)
            guard looks.indices.contains(layer) else { continue }
            switch effect.kind {
            case .entrance, .exit:
                let target = effect.kind == .entrance ? DeckLook.visible : page.hidden(step)
                let curve: Animation
                switch effect.style {
                case "bounce": curve = .spring(response: max(0.35, d * 0.7), dampingFraction: 0.42)
                case "fly", "float", "zoom": curve = effect.kind == .entrance ? .easeOut(duration: d) : .easeIn(duration: d)
                case "appear": curve = .linear(duration: 0.001)
                default: curve = .easeInOut(duration: d)
                }
                withAnimation(curve.delay(effect.delay)) {
                    looks[layer].opacity = target.opacity; looks[layer].dx = target.dx; looks[layer].dy = target.dy
                    looks[layer].scale = target.scale; looks[layer].reveal = target.reveal
                    if effect.style == "wipe" { looks[layer].edge = effect.direction }
                }
            case .emphasis:
                if effect.style == "spin" {
                    withAnimation(.easeInOut(duration: d).delay(effect.delay)) { looks[layer].rotation += 360 }
                } else {
                    withAnimation(.easeInOut(duration: d / 2).delay(effect.delay)) { looks[layer].pulse = 1.15 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + effect.delay + d / 2) {
                        guard looks.indices.contains(layer) else { return }
                        withAnimation(.easeInOut(duration: d / 2)) { looks[layer].pulse = 1 }
                    }
                }
            }
        }
    }
}

/// The page area: the current slide, and during a slide change the previous one sliding (or fading) away.
/// Done by hand rather than with view transitions, so the old page reliably stays until the new one covers it.
struct DeckStage: View {
    @ObservedObject var model: PublicDisplayModel
    @State private var shown: (page: DeckPage, step: Int, token: Int)?
    @State private var outgoing: (page: DeckPage, step: Int, token: Int)?
    @State private var effect: PageTransitionEffect?
    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { g in
            ZStack {
                if let outgoing {
                    DeckPageView(model: model, page: outgoing.page, frozenStep: outgoing.step).id(outgoing.token)
                        .offset(offset(in: g.size, incoming: false))
                }
                if let page = model.page {
                    DeckPageView(model: model, page: page).id(model.pageToken)
                        .offset(offset(in: g.size, incoming: true))
                        .opacity(effect?.style == "fade" && outgoing != nil ? Double(progress) : 1)
                }
            }
        }
        .onAppear { shown = model.page.map { ($0, model.buildStep, model.pageToken) } }
        // A new page resets the step before its token changes: only steps of the page still shown count.
        .onChange(of: model.buildStep) { _, step in if shown?.token == model.pageToken { shown?.step = step } }
        .onChange(of: model.pageToken) { _, token in arrive(token) }
    }

    private func arrive(_ token: Int) {
        let previous = shown
        shown = model.page.map { ($0, model.buildStep, token) }
        guard let transition = model.arrival, let previous else { outgoing = nil; effect = nil; progress = 1; return }
        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) { outgoing = previous; effect = transition; progress = 0 }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: transition.duration)) { progress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration + 0.1) {
            if shown?.token == token { outgoing = nil }
        }
    }
    /// PowerPoint's push names the way the slides move: "left" brings the new one in from the right.
    private func offset(in size: CGSize, incoming: Bool) -> CGSize {
        guard let effect, effect.style == "push", outgoing != nil else { return .zero }
        let travel = incoming ? 1 - progress : -progress
        switch effect.direction {
        case "right": return CGSize(width: -travel * size.width, height: 0)
        case "top": return CGSize(width: 0, height: travel * size.height)
        case "bottom": return CGSize(width: 0, height: -travel * size.height)
        default: return CGSize(width: travel * size.width, height: 0)
        }
    }
}
