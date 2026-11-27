import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Screen-independent placement math for the compact ("边看图边看题") quiz card overlay.
/// All coordinates live in the 720-pt-tall canonical overlay coordinate space shared by the
/// teacher preview and the external TV / Mac public window, while normalized `anchor` (`0...1`
/// across the free travel box) keeps relative edge placement consistent across aspect ratios.
public enum ClassroomQuizCardLayout {
    /// Top-center by default: leaves the picture-book center illustration and bottom player strip unobstructed.
    public static let defaultAnchor = CGPoint(x: 0.5, y: 0.0)
    public static let edgeMargin: CGFloat = 18
    public static let challengeTopInset: CGFloat = 82
    public static let timerTopInset: CGFloat = 104

    /// Computes the top safe inset in 720-pt overlay units so the compact card never overlaps
    /// the challenge banner or top-centered class countdown badge.
    public static func topInset(challengeActive: Bool, timerTopCenter: Bool) -> CGFloat {
        if timerTopCenter { return max(challengeActive ? challengeTopInset : edgeMargin, timerTopInset) }
        return challengeActive ? challengeTopInset : edgeMargin
    }

    /// Clamps a normalized anchor into `[0, 1] × [0, 1]`, falling back to `defaultAnchor` on non-finite values.
    public static func clampedAnchor(_ anchor: CGPoint) -> CGPoint {
        let x = anchor.x.isFinite ? min(1, max(0, anchor.x)) : defaultAnchor.x
        let y = anchor.y.isFinite ? min(1, max(0, anchor.y)) : defaultAnchor.y
        return CGPoint(x: x, y: y)
    }

    /// Free travel box `[minX...maxX] × [minY...maxY]` for the compact card's top-left origin inside `bounds`.
    public static func travelBounds(cardSize: CGSize, in bounds: CGSize, topInset: CGFloat = edgeMargin, margin: CGFloat = edgeMargin) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, cardSize.width >= 0, cardSize.height >= 0 else { return .zero }
        let centeredX = max(0, (bounds.width - cardSize.width) / 2)
        let minX = min(margin, centeredX)
        let maxX = max(minX, bounds.width - margin - cardSize.width)
        let centeredY = max(0, (bounds.height - cardSize.height) / 2)
        let effectiveTop = max(margin, topInset)
        let minY = min(effectiveTop, centeredY)
        let maxY = max(minY, bounds.height - margin - cardSize.height)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// Resolves the compact card frame inside `bounds` from normalized `anchor` (`0...1`).
    public static func compactFrame(cardSize: CGSize, in bounds: CGSize, anchor: CGPoint, topInset: CGFloat = edgeMargin, margin: CGFloat = edgeMargin) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return CGRect(origin: .zero, size: cardSize) }
        let a = clampedAnchor(anchor)
        let travel = travelBounds(cardSize: cardSize, in: bounds, topInset: topInset, margin: margin)
        let x = travel.width > 0.5 ? travel.minX + a.x * travel.width : max(0, (bounds.width - cardSize.width) / 2)
        let y = travel.height > 0.5 ? travel.minY + a.y * travel.height : max(0, (bounds.height - cardSize.height) / 2)
        return CGRect(x: x, y: y, width: cardSize.width, height: cardSize.height)
    }

    /// Applies a drag delta (in 720-pt overlay units) to `startAnchor`, clamping cleanly within `[0, 1]`.
    public static func draggedAnchor(from startAnchor: CGPoint, delta: CGPoint, cardSize: CGSize, in bounds: CGSize, topInset: CGFloat = edgeMargin, margin: CGFloat = edgeMargin) -> CGPoint {
        let start = clampedAnchor(startAnchor)
        guard delta.x.isFinite, delta.y.isFinite else { return start }
        let travel = travelBounds(cardSize: cardSize, in: bounds, topInset: topInset, margin: margin)
        let nx = travel.width > 1 ? min(1, max(0, start.x + delta.x / travel.width)) : start.x
        let ny = travel.height > 1 ? min(1, max(0, start.y + delta.y / travel.height)) : start.y
        return CGPoint(x: nx, y: ny)
    }
}
