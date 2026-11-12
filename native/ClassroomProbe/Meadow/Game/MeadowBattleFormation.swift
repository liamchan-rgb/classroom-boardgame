import Foundation

/// Where every unit stands in a party battle, for any team size the full game uses: up to 7 heroes against up to 3 monsters, or two
/// hero teams in PvP (the right-hand team is mirrored and faces left). Pure maths - no UIKit - so `scripts/battle-formation-regression.swift`
/// can check it on any machine; `scripts/battle-vfx/formation.py` is the reference the review images were drawn from.
///
/// Units never shrink. A bigger battle makes the world bigger instead (1000Z x 600Z, plates scaled by Z), so the camera simply sees more
/// of the meadow; Z is 1, 1.25 or 1.45.
enum MeadowBattleFormation {
    struct Layout: Equatable {
        /// World zoom: the world is `1000 * zoom` wide and `600 * zoom` high.
        var zoom: Double
        /// Feet (world units) per unit id, in the order the ids were given.
        var feet: [String: (x: Double, y: Double)]
        /// Units drawn facing left (the PvP right-hand team).
        var mirrored: Set<String>
        var width: Double { 1000 * zoom }
        var height: Double { 600 * zoom }

        static func == (a: Layout, b: Layout) -> Bool {
            a.zoom == b.zoom && a.mirrored == b.mirrored && a.feet.count == b.feet.count
                && a.feet.allSatisfy { k, v in b.feet[k].map { $0.x == v.x && $0.y == v.y } ?? false }
        }
    }

    /// Hero slots in filling order for each zoom; the front of the formation is towards the middle of the field.
    static let heroes: [Double: [(x: Double, y: Double)]] = [
        1.0: [(165, 420), (315, 505)],
        1.25: [(520, 560), (470, 690), (330, 600), (290, 720)],
        1.45: [(610, 650), (570, 770), (460, 600), (430, 700), (400, 800), (290, 650), (260, 760)],
    ]
    static let monsters: [Double: [(x: Double, y: Double)]] = [
        1.0: [(650, 395), (835, 510), (600, 585)],
        1.25: [(820, 560), (1010, 690), (1040, 520)],
        1.45: [(940, 640), (1140, 770), (1180, 590)],
    ]
    static let maxHeroes = 7, maxMonsters = 3
    /// PvP: at most 4 heroes per side (3v4 or 4v3 in the full game), so it never needs more than zoom 1.25.
    static let maxPvPSide = 4

    /// The smallest world that holds this many units: the classic 2-hero stand keeps zoom 1 (and exactly its old feet).
    static func zoom(players: Int, foes: Int, pvp: Bool) -> Double {
        let n = max(players, pvp ? foes : 0)
        if n <= 2 && (pvp || foes <= 3) { return 1.0 }
        if n <= 4 { return 1.25 }
        return 1.45
    }

    /// Feet for the left team (`players`) and the right team (`foes`: monsters, or the other heroes in PvP, mirrored left-right).
    /// Units past the slot count (more than 7 heroes / 3 monsters, or 4 per side in PvP) are left out.
    static func layout(players: [String], foes: [String], pvp: Bool) -> Layout {
        let players = pvp ? Array(players.prefix(maxPvPSide)) : players, foes = pvp ? Array(foes.prefix(maxPvPSide)) : foes
        let z = zoom(players: players.count, foes: foes.count, pvp: pvp), w = 1000 * z
        var feet: [String: (x: Double, y: Double)] = [:], mirrored: Set<String> = []
        let left = heroes[z]!
        for (i, id) in players.enumerated() where i < left.count { feet[id] = left[i] }
        if pvp {
            for (i, id) in foes.enumerated() where i < left.count { feet[id] = (w - left[i].x, left[i].y); mirrored.insert(id) }
        } else {
            let right = monsters[z]!
            for (i, id) in foes.enumerated() where i < right.count { feet[id] = right[i] }
        }
        return Layout(zoom: z, feet: feet, mirrored: mirrored)
    }

    /// The part of the world a pane of this aspect shows at rest (the world is scaled to the pane's width and centred).
    static func visibleY(zoom: Double, aspect: Double) -> ClosedRange<Double> {
        let h = 600 * zoom, half = 1000 * zoom / aspect / 2
        return (h / 2 - half)...(h / 2 + half)
    }
}
