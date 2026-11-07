import UIKit

enum MeadowBattlePreviewMode: Int, CaseIterable {
    case exploration, playerTurn, monsterTurn
    var showsBattle: Bool { self != .exploration }
    var showsDetails: Bool { self == .playerTurn }
}

/// Layout contract from the classroom-boardgame round-three review and the
/// 2026-10-13 feedback: shared header, equal-height map/battle, full-width track
/// and compact player details. Values adapt to the actual iPad window.
struct MeadowBattleLayout {
    let header: CGRect
    let map: CGRect
    let battlefield: CGRect
    let track: CGRect
    let details: CGRect

    init(size: CGSize, safeArea: UIEdgeInsets, mode: MeadowBattlePreviewMode) {
        let unit = size.height / 1080
        let left = max(safeArea.left + 12, size.width * 0.05)
        let right = max(safeArea.right + 12, size.width * 0.05)
        let top = max(safeArea.top + 12, size.height * 0.05)
        let bottom = size.height - max(safeArea.bottom + 12, size.height * 0.05)
        let width = max(1, size.width - left - right)
        let gap = max(8, 18 * unit)
        header = CGRect(x: left, y: top, width: width, height: max(76, 76 * unit))
        let detailHeight: CGFloat = mode.showsDetails ? max(142, 174 * unit) : 0
        let trackHeight: CGFloat = mode.showsBattle ? max(64, 80 * unit) : 0
        details = mode.showsDetails
            ? CGRect(x: left, y: bottom - detailHeight, width: width, height: detailHeight) : .zero
        let trackBottom = mode.showsDetails ? details.minY - gap : bottom
        track = mode.showsBattle
            ? CGRect(x: left, y: trackBottom - trackHeight, width: width, height: trackHeight) : .zero
        let middleBottom = mode.showsBattle ? track.minY - gap : bottom
        let middleY = header.maxY + gap
        let middleHeight = max(1, middleBottom - middleY)
        // Historical references: 760:944 at 16:9, 596:676 at 4:3.
        let fraction: CGFloat = size.width / max(1, size.height) >= 1.6 ? 760 / 1704 : 596 / 1272
        let mapWidth = mode.showsBattle ? (width - gap) * fraction : width
        map = CGRect(x: left, y: middleY, width: mapWidth, height: middleHeight)
        battlefield = mode.showsBattle
            ? CGRect(x: map.maxX + gap, y: middleY, width: width - mapWidth - gap, height: middleHeight) : .zero
    }
}
