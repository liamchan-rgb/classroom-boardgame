import Foundation

/// What a PowerPoint animation effect acts on: a whole shape, or some of its paragraphs (bullets built one by one).
public struct SlideAnimationTarget: Hashable {
    public var shapeID: Int
    /// Paragraph indices in the shape's text body, nil for the whole shape.
    public var paragraphs: ClosedRange<Int>?
    public init(shapeID: Int, paragraphs: ClosedRange<Int>? = nil) { self.shapeID = shapeID; self.paragraphs = paragraphs }
}

public enum SlideEffectKind: String { case entrance, exit, emphasis }

/// One effect, reduced to what the classroom display can show: a family of motion (appear, fade, fly, float, wipe,
/// zoom, bounce; for emphasis pulse or spin), the side it comes from / leaves to, and its timing after the click.
public struct SlideEffect: Equatable {
    public var target: SlideAnimationTarget
    public var kind: SlideEffectKind
    public var style: String
    /// "left" / "right" / "top" / "bottom", or "" when the effect has no direction.
    public var direction: String
    /// Seconds after the click (with-previous / after-previous chains add up here).
    public var delay: Double
    public var duration: Double
}

/// The slide's build: effects that run by themselves when the slide appears, then one group per click.
public struct SlideBuild: Equatable {
    public var entry: [SlideEffect] = []
    public var clicks: [[SlideEffect]] = []
    public var isEmpty: Bool { entry.isEmpty && clicks.isEmpty }
    public var all: [SlideEffect] { entry + clicks.flatMap { $0 } }
    public init(entry: [SlideEffect] = [], clicks: [[SlideEffect]] = []) { self.entry = entry; self.clicks = clicks }
}

/// Slide change effect, reduced to fade or push.
public struct PageTransitionEffect: Equatable {
    public var style: String
    public var direction: String
    public var duration: Double
}

enum PPTXAnimations {
    /// Reads `p:timing` (main sequence only; triggers on shapes and media commands are skipped).
    static func build(_ slide: XMLNode, warnings: inout [String]) -> SlideBuild {
        guard let timing = slide.first("timing"),
              let main = timing.descendants("cTn").first(where: { $0.attributes["nodeType"] == "mainSeq" }) else { return SlideBuild() }
        var result = SlideBuild()
        var unsupported = Set<String>()
        for group in childTimeNodes(main) {
            var effects = collect(group, offset: 0, unsupported: &unsupported)
            // A group that does not wait for a click starts by itself: at the top of the slide it plays on entry;
            // later it chains after the previous group (rare), so it joins that click after its effects end.
            if delayText(group) == "indefinite" { result.clicks.append(effects); continue }
            if result.clicks.isEmpty { result.entry += effects; continue }
            let start = result.clicks[result.clicks.count - 1].map { $0.delay + $0.duration }.max() ?? 0
            for index in effects.indices { effects[index].delay += start }
            result.clicks[result.clicks.count - 1] += effects
        }
        result.clicks.removeAll { $0.isEmpty }
        if unsupported.contains("path") { warnings.append("动作路径动画暂以强调（放大）显示。") }
        if unsupported.contains("other") { warnings.append("部分动画类型（媒体、触发器等）已跳过。") }
        return result
    }

    static func transition(_ slide: XMLNode) -> PageTransitionEffect? {
        guard let node = slide.first("transition") else { return nil }
        let speed: Double = ["fast": 0.5, "med": 0.75, "slow": 1.0][node.attributes["spd"] ?? "fast"] ?? 0.5
        let duration = Double(node.attribute("dur") ?? "").map { $0 / 1000 } ?? speed
        guard let effect = node.children.first else { return nil }
        let side: [String: String] = ["l": "left", "r": "right", "u": "top", "d": "bottom"]
        switch effect.name {
        case "push", "cover", "pull", "wipe", "reveal", "pan":
            return PageTransitionEffect(style: "push", direction: side[effect.attributes["dir"] ?? ""] ?? (effect.name == "wipe" ? "left" : "left"), duration: min(2, max(0.2, duration)))
        case "cut": return nil
        default: return PageTransitionEffect(style: "fade", direction: "", duration: min(2, max(0.2, duration)))
        }
    }

    /// The `cTn` of each `par`/`seq` directly inside a time node's child list.
    private static func childTimeNodes(_ cTn: XMLNode) -> [XMLNode] {
        (cTn.children.first { $0.name == "childTnLst" }?.children ?? [])
            .filter { $0.name == "par" || $0.name == "seq" }
            .compactMap { $0.children.first { $0.name == "cTn" } }
    }
    private static func delayText(_ cTn: XMLNode) -> String? {
        cTn.children.first { $0.name == "stCondLst" }?.children.first { $0.name == "cond" }?.attributes["delay"]
    }
    private static func collect(_ cTn: XMLNode, offset: Double, unsupported: inout Set<String>) -> [SlideEffect] {
        let start = offset + (Double(delayText(cTn) ?? "") ?? 0) / 1000
        guard let presetClass = cTn.attributes["presetClass"] else {
            return childTimeNodes(cTn).flatMap { collect($0, offset: start, unsupported: &unsupported) }
        }
        let kind: SlideEffectKind
        switch presetClass {
        case "entr": kind = .entrance
        case "exit": kind = .exit
        case "emph": kind = .emphasis
        case "path": kind = .emphasis; unsupported.insert("path")
        default: unsupported.insert("other"); return []
        }
        guard let target = cTn.first("spTgt"), let shape = Int(target.attributes["spid"] ?? "") else { unsupported.insert("other"); return [] }
        var paragraphs: ClosedRange<Int>?
        if let range = target.first("pRg"), let low = Int(range.attributes["st"] ?? ""), let high = Int(range.attributes["end"] ?? ""), low >= 0, high >= low {
            paragraphs = low...high
        }
        let durations = cTn.descendants("cTn").dropFirst().compactMap { Double($0.attributes["dur"] ?? "") }
        let duration = min(10, max(0, (durations.max() ?? 500) / 1000))
        let preset = Int(cTn.attributes["presetID"] ?? "") ?? 10, subtype = Int(cTn.attributes["presetSubtype"] ?? "") ?? 0
        var style: String, direction = ""
        func side(_ value: Int, fallback: String) -> String {
            switch value { case 1, 3, 9: return "top"; case 2: return "right"; case 4, 6, 12: return "bottom"; case 8: return "left"; default: return fallback }
        }
        if presetClass == "path" { style = "pulse" }
        else if kind == .emphasis { style = preset == 8 ? "spin" : "pulse" }
        else {
            switch preset {
            case 1: style = "appear"
            case 2, 7, 12: style = "fly"; direction = side(subtype, fallback: "bottom")
            case 3, 16, 18, 22: style = "wipe"; direction = side(subtype, fallback: "left")
            case 4, 6, 8, 13, 15, 17, 19, 20, 21, 23, 53, 55: style = "zoom"
            case 26: style = "bounce"; direction = "top"
            case 37, 42: style = "float"; direction = "bottom"
            case 47: style = "float"; direction = "top"
            default: style = "fade"
            }
        }
        return [SlideEffect(target: SlideAnimationTarget(shapeID: shape, paragraphs: paragraphs), kind: kind, style: style,
                            direction: direction, delay: start, duration: style == "appear" ? 0 : duration)]
    }
}
