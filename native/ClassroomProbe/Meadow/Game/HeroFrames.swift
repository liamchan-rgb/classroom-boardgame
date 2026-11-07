import SpriteKit
import MeadowBattleSupport

enum HeroFrames {
    // Shared distance-clock resolution; artwork can contain fewer whole poses.
    static let walkFrameCount = 24
    static let columns = walkFrameCount + 5
    static let atlasRows = 4

    private struct Layout: Decodable {
        let authoredFrames: [Int]
        let reviewFrameMs: Double
        let modularP1: ModularLayout?
        let equipmentVisuals:[String:EquipmentVisualBinding]?
        let armorVisuals:[String:ArmorVisualBinding]?
        let accessoryVisuals:[String:AccessoryVisualBinding]?
    }
    private struct ModularLayout: Decodable {
        struct Loadout: Decodable { let id: String; let title: String; let atlasNames: [String];let weaponAtlasNames:[String:[String]]?;let armorAtlasNames:[String:[String:[String]]]? }
        let rasterColumns: Int
        let loadouts: [Loadout]
    }
    private static let layout: Layout = {
        guard let url = Bundle.main.url(forResource: "hero-gait", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Layout.self, from: data) else {
            fatalError("Missing authored gait layout")
        }
        precondition(value.authoredFrames.count == 3 && value.authoredFrames.allSatisfy { $0 > 0 && walkFrameCount % $0 == 0 })
        return value
    }()

    static func authoredFrameCount(heroIndex: Int) -> Int {
        layout.authoredFrames[min(2, max(0, heroIndex))]
    }

    static let locomotionPlan: AuthoredLocomotion.Plan? = {
        guard layout.modularP1 != nil,
              let url = Bundle.main.url(forResource: "hero-gait", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = object["modularP1"], let encoded = try? JSONSerialization.data(withJSONObject: plan),
              let decoded = try? JSONDecoder().decode(AuthoredLocomotion.Plan.self, from: encoded) else { return nil }
        return decoded
    }()

    struct ArmorVisualBinding:Decodable {
        let itemID:String,iconAsset:String
        let battleLayers:[String:String]
        let battleLayerOrder:[String]?
        let bowAtlas:String,bowTorso:String
    }
    static func armorVisual(_ id:String?)->ArmorVisualBinding? { id.flatMap { layout.armorVisuals?[$0] } }
    static var armorAtlasNames:Set<String> { Set(layout.modularP1?.loadouts.flatMap { $0.armorAtlasNames?.values.flatMap { $0.values.flatMap { $0 } } ?? [] } ?? []) }
    static func weaponVisual(_ id:String?)->EquipmentVisualBinding? { id.flatMap { layout.equipmentVisuals?[$0] } }

    static func accessoryVisual(_ id:String?)->AccessoryVisualBinding? { id.flatMap { layout.accessoryVisuals?[$0] } }

    static var appearanceIDs:[String] { layout.modularP1?.loadouts.map(\.id) ?? [] }

    static var appearanceTitles: [String] { layout.modularP1?.loadouts.map(\.title) ?? [] }

    static func atlasName(heroIndex: Int, diagonal: Bool, appearanceIndex: Int = 0,weaponID:String?="trainingSword",armorID:String?=nil) -> String {
        if heroIndex == 0, let presets = layout.modularP1?.loadouts {
            precondition(presets.indices.contains(appearanceIndex))
            let preset=presets[appearanceIndex]
            if let armorID,let names=preset.armorAtlasNames?[armorID]?[weaponID ?? "none"] { return names[diagonal ? 1:0] }
            return (preset.weaponAtlasNames?[weaponID ?? "none"] ?? preset.atlasNames)[diagonal ? 1 : 0]
        }
        return "Hero\(heroIndex + 1)\(diagonal ? "Diagonals" : "Directions")"
    }

    static var atlasNames: [String] {
        let defaults = (0..<3).flatMap { hero in [false, true].map { atlasName(heroIndex: hero, diagonal: $0) } }
        return Array(Set(defaults + (layout.modularP1?.loadouts.flatMap { $0.atlasNames+($0.weaponAtlasNames?.values.flatMap { $0 } ?? []) } ?? []))).sorted()
    }

    /// Exact idle + eight authored front-walk cells, without re-synthesizing art.
    static func inventoryImages(appearanceIndex:Int,weaponID:String?,armorID:String?) -> [UIImage] {
        let name=atlasName(heroIndex:0,diagonal:false,appearanceIndex:appearanceIndex,weaponID:weaponID,armorID:armorID)
        guard let image=UIImage(named:name)?.cgImage else { return [] }
        let cell=image.height/atlasRows
        return (0...8).compactMap { index in
            image.cropping(to:CGRect(x:index*cell,y:0,width:cell,height:cell)).map { UIImage(cgImage:$0) }
        }
    }

    static func rasterColumns(heroIndex: Int) -> Int {
        heroIndex == 0 ? layout.modularP1?.rasterColumns ?? authoredFrameCount(heroIndex: 0) + 1
            : authoredFrameCount(heroIndex: heroIndex) + 1
    }

    static var reviewSpeed: CGFloat {
        24 / (CGFloat(authoredFrameCount(heroIndex: 0)) * CGFloat(layout.reviewFrameMs) / 1000)
    }

    // The retained blue-boot prototype was baked from the older 24-pose P1.
    // Offer its comparison only while the primary artwork uses that layout.
    static var layeredPrototypeAvailable: Bool { authoredFrameCount(heroIndex: 0) == walkFrameCount }

    static func sourceColumn(frame: Int, heroIndex: Int = 0) -> Int {
        let frame = min(columns - 1, max(0, frame))
        if frame > walkFrameCount { return heroIndex == 0 && layout.modularP1 != nil ? frame - walkFrameCount + 8 : 0 }
        return frame == 0 ? 0 : 1 + (frame - 1) * authoredFrameCount(heroIndex: heroIndex) / walkFrameCount
    }

    static func load(_ hero: Int, appearanceIndex: Int = 0,weaponID:String?="trainingSword",armorID:String?=nil) -> [[SKTexture]] {
        [false, true].flatMap { diagonal -> [[SKTexture]] in
            let name = atlasName(heroIndex: hero - 1, diagonal: diagonal, appearanceIndex: appearanceIndex,weaponID:weaponID,armorID:armorID)
            guard let atlas = UIImage(named: name)?.cgImage else {
                fatalError("Missing hero atlas: \(name)")
            }
            let cell = atlas.height / atlasRows
            let sourceColumns = rasterColumns(heroIndex: hero - 1)
            precondition(atlas.width == cell * sourceColumns && atlas.height == cell * atlasRows)
            return (0..<atlasRows).map { row in
                let poses = (0..<sourceColumns).map { column -> SKTexture in
                    let rect = CGRect(x: column * cell, y: row * cell, width: cell, height: cell)
                    guard let image = atlas.cropping(to: rect) else { fatalError("Invalid hero frame") }
                    let texture = SKTexture(cgImage: image)
                    texture.filteringMode = .nearest
                    return texture
                }
                return (0..<columns).map { poses[sourceColumn(frame: $0, heroIndex: hero - 1)] }
            }
        }
    }

    /// Baked output of the layered P1 shoe-color prototype. The art is authored
    /// as transparent layers offline, then packed for the app's normal atlas path.
    static func loadLayeredP1BlueVariant() -> [SKTexture] {
        guard let atlas = UIImage(named: "LayeredP1BlueVariant")?.cgImage else {
            fatalError("Missing layered P1 colorway preview")
        }
        let cell = atlas.height
        precondition(cell == 256 && atlas.width == cell * walkFrameCount,
                     "Layered P1 colorway atlas must be 24 square frames")
        let strip = SKTexture(cgImage: atlas)
        return (0..<walkFrameCount).map { column in
            let rect = CGRect(x: CGFloat(column) / CGFloat(walkFrameCount), y: 0,
                              width: 1 / CGFloat(walkFrameCount), height: 1)
            let texture = SKTexture(rect: rect, in: strip)
            texture.filteringMode = .nearest
            return texture
        }
    }

    static func sourceFacing(_ facing: Int) -> Int { ((facing % 8) + 8) % 8 }
    static func isMirrored(_ facing: Int) -> Bool { false }

    /// Foreground and native alpha-depth pass address the same authored pose.
    static func atlasRect(facing: Int, frame: Int, heroIndex: Int = 0) -> SIMD4<Float> {
        let sourceColumns = rasterColumns(heroIndex: heroIndex)
        return SIMD4(Float(sourceColumn(frame: frame, heroIndex: heroIndex)) / Float(sourceColumns),
                     Float(sourceFacing(facing) % atlasRows) / Float(atlasRows),
                     1 / Float(sourceColumns), 1 / Float(atlasRows))
    }
}

/// Limb motion is drawn in whole frames. Neither foreground nor shadow caster
/// stretches or splices pixels around a knee.
struct HeroPose {
    private struct Footprint: Decodable { let feet: [[Float]] }
    private struct Rig: Decodable { let heroes: [[[Footprint]]] }
    private static let rig: Rig = {
        guard let url = Bundle.main.url(forResource: "hero-gait", withExtension: "json"),
              let data = try? Data(contentsOf: url), let rig = try? JSONDecoder().decode(Rig.self, from: data) else {
            fatalError("Missing authored gait footprint data")
        }
        return rig
    }()
    static let gridColumns = 8
    static let gridRows = 8
    static let referenceSize: CGFloat = 64
    let heroIndex: Int
    let facing: Int
    let frame: Int
    let phase: CGFloat
    private let firstFoot: SIMD3<Float>
    private let secondFoot: SIMD3<Float>

    init(heroIndex: Int, facing: Int, frame: Int, phase: CGFloat) {
        let hero = min(2, max(0, heroIndex)), direction = HeroFrames.sourceFacing(facing)
        let column = min(Self.rig.heroes[hero][direction].count - 1, max(0, frame))
        self.heroIndex = hero
        self.facing = direction
        self.frame = column
        let wrapped = phase.truncatingRemainder(dividingBy: 1)
        self.phase = wrapped < 0 ? wrapped + 1 : wrapped
        let feet = Self.rig.heroes[hero][direction][column].feet
        let a = SIMD3(feet[0][0], feet[0][1], feet[0][2]), b = SIMD3(feet[1][0], feet[1][1], feet[1][2])
        firstFoot = a
        secondFoot = b
    }

    func bodyOffset(size: CGSize = CGSize(width: referenceSize, height: referenceSize)) -> CGPoint { .zero }

    // Retain relief tessellation and the exact sole-height row, with identity
    // positions for every animation phase.
    var sourcePositions: [SIMD2<Float>] {
        let feet = footLandmarks
        let xs = Self.stops([0, 0.15, 0.30, 0.50, 0.70, 0.85, 1, feet[0].x, feet[1].x])
        let ys = Self.stops([0, 0.125, 0.25, 0.40, 0.55, 0.75, 1, feet[0].y, feet[1].y])
        return ys.flatMap { y in xs.map { x in SIMD2(x, y) } }
    }

    private static func stops(_ values: [Float]) -> [Float] {
        var result: [Float] = []
        for value in values.sorted() where result.last.map({ abs($0 - value) > 0.000001 }) ?? true { result.append(value) }
        while result.count < 9 {
            var widestGapIndex = 0
            var widestGapWidth: Float = -1
            for index in 0..<(result.count - 1) {
                let gapWidth = result[index + 1] - result[index]
                if gapWidth > widestGapWidth {
                    widestGapWidth = gapWidth
                    widestGapIndex = index
                }
            }
            let midpoint = (result[widestGapIndex] + result[widestGapIndex + 1]) * 0.5
            result.insert(midpoint, at: widestGapIndex + 1)
        }
        return result
    }

    /// x/y are exact source-art landmarks, z is lift in image-height units.
    /// Include these points in the depth mesh so a boot cannot miss the ground
    /// because its foot falls between coarse regular grid vertices.
    var footLandmarks: [SIMD3<Float>] {
        [Self.landmark(firstFoot), Self.landmark(secondFoot)]
    }

    private static func landmark(_ foot: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(foot.x, 1 - foot.y + foot.z * 0.8660254, foot.z * 0.8660254)
    }

    func destinationPositions() -> [SIMD2<Float>] { sourcePositions }

    /// Both feet can overlap in x while occupying different depths. Select
    /// their ground depth in two image dimensions, then blend back to the
    /// body's root plane above the legs to keep the torso relief stable.
    func groundLine(at point: SIMD2<Float>) -> Float {
        let first = Self.landmark(firstFoot), second = Self.landmark(secondFoot)
        func squared(_ foot: SIMD3<Float>) -> Float {
            let dx = point.x - foot.x, dy = point.y - foot.y
            return dx * dx + dy * dy
        }
        let da = squared(first), db = squared(second)
        let ground: Float
        if da < 0.00000001 { ground = 1 - firstFoot.y }
        else if db < 0.00000001 { ground = 1 - secondFoot.y }
        else {
            let a = 1 / (da * da), b = 1 / (db * db)
            ground = ((1 - firstFoot.y) * a + (1 - secondFoot.y) * b) / (a + b)
        }
        let t = max(0, min(1, (point.y - 0.22) / 0.20))
        let blend = t * t * (3 - 2 * t)
        return ground * (1 - blend) + 0.125 * blend
    }
}
