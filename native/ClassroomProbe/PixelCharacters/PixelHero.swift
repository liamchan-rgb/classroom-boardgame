import ClassroomGameCore
import MeadowBattleSupport
import UIKit

/// 游戏里一个人物的外观：体型 + 护甲 + 武器 + 发型 + 五官（都是游戏里的 id）。
/// spec 把它翻译成像素人物的装备（发型、衣服、武器……），交给 PixelBaker 烘焙。
struct PixelHeroLook: Hashable {
    /// forester / wayfarer（可选体型），crimson / grove（没有自定义外观的 2、3 号旅人）
    var body: String = "forester"
    /// 桌游物品表的护甲 id；nil = 体型自带的布衣
    var armor: String?
    /// 桌游物品表的武器 id；nil = 空手
    var weapon: String?
    /// PlayerAppearance.hairOptions 里的 id；nil = 体型原有发型
    var hair: String?
    /// PlayerAppearance.faceOptions 里的 id；nil = 体型原有五官
    var face: String?

    static let presetBodies = ["forester", "crimson", "grove"]

    var key: String { [body, armor ?? "base", weapon ?? "none", hair ?? "original", face ?? "original"].joined(separator: "|") }

    init(body: String = "forester", armor: String? = nil, weapon: String? = nil, hair: String? = nil, face: String? = nil) {
        self.body = body; self.armor = armor; self.weapon = weapon; self.hair = hair; self.face = face
    }

    init?(key: String) {
        let p = key.components(separatedBy: "|")
        guard p.count == 5 else { return nil }
        self.init(body: p[0], armor: p[1] == "base" ? nil : p[1], weapon: p[2] == "none" ? nil : p[2],
                  hair: p[3] == "original" ? nil : p[3], face: p[4] == "original" ? nil : p[4])
    }

    /// 发型选项（短碎、偏分、小束、长发、侧马尾、盘发）→ 像素发型
    static let hairStyles: [String: String] = [
        "p1-custom-hair-m1-short-v1": "hair_messy",
        "p1-custom-hair-m2-sidepart-v1": "hair_swept",
        "p1-custom-hair-m3-topknot-v1": "hair_tied",
        "p1-custom-hair-f1-bob-v1": "hair_long",
        "p1-custom-hair-f2-ponytail-v1": "hair_side_tail",
        "p1-custom-hair-f3-bun-v1": "hair_bun",
    ]
    /// 五官选项（蓝瞳、琥珀、绿瞳、紫瞳）→ 圆脸的瞳色
    static let eyeColors: [String: String] = [
        "p1-custom-face-m1-bright-v1": "blue",
        "p1-custom-face-m2-calm-v1": "amber",
        "p1-custom-face-f1-gentle-v1": "green",
        "p1-custom-face-f2-clear-v1": "violet",
    ]
    static let weapons: [String: String] = [
        "trainingSword": "weapon_training_sword",
        "huntingBow": "weapon_hunting_bow",
        "greatSword": "weapon_great_sword",
        "legendaryStaff": "weapon_legendary_staff",
        "starlightBlade": "weapon_starlight_blade",
        "dragonFangSword": "weapon_dragon_fang",
    ]
    static let armors: [String: String] = [
        "leatherArmor": "top_leather_armor",
        "runeArmor": "top_rune_armor",
        "starlightArmor": "top_starlight_armor",
        "dragonArmor": "top_dragon_armor",
    ]

    private struct Base {
        let hair: String, hairColor: String, face: String, eyes: String?, skin: String
        let top: String, topVariant: String, scarf: String?, scarfVariant: String?
    }

    private var base: Base {
        switch body {
        case "wayfarer":
            return Base(hair: "hair_neat", hairColor: "silver", face: "face_round", eyes: "amber", skin: "light",
                        top: "top_red_cloak", topVariant: "red", scarf: nil, scarfVariant: nil)
        case "crimson":
            return Base(hair: "hair_neat", hairColor: "black", face: "face_smile", eyes: nil, skin: "light",
                        top: "top_red_cloak", topVariant: "forest", scarf: nil, scarfVariant: nil)
        case "grove":
            return Base(hair: "hair_messy", hairColor: "blonde", face: "face_round", eyes: "amber", skin: "tan",
                        top: "top_traveler", topVariant: "green", scarf: "scarf_navy", scarfVariant: "cream")
        default:
            return Base(hair: "hair_messy", hairColor: "chestnut", face: "face_round", eyes: "blue", skin: "fair",
                        top: "top_traveler", topVariant: "blue", scarf: "scarf_navy", scarfVariant: "navy")
        }
    }

    var spriteWeapon: String? { weapon.flatMap { Self.weapons[$0] } }

    /// 交给 PixelBaker 的装备规格
    var spec: [String: Any] {
        let b = base
        var slots: [String: String] = ["bottom": "bottom_trousers", "shoes": "shoes_boots"]
        var variants: [String: String] = ["bottom": "dark", "shoes": "brown"]
        // 换发型时发色跟着体型走
        slots["hair"] = hair.flatMap { Self.hairStyles[$0] } ?? b.hair
        variants["hair"] = b.hairColor
        if let face, let eye = Self.eyeColors[face] {
            slots["face"] = "face_round"; variants["face"] = eye
        } else {
            slots["face"] = b.face
            if let eye = b.eyes { variants["face"] = eye }
        }
        if let armor, let top = Self.armors[armor] {
            slots["top"] = top
        } else {
            slots["top"] = b.top; variants["top"] = b.topVariant
            if let scarf = b.scarf { slots["scarf"] = scarf; variants["scarf"] = b.scarfVariant }
            slots["bag"] = "bag_satchel"
        }
        if let w = spriteWeapon { slots["weapon_main"] = w }
        return ["slots": slots, "variants": variants, "skin": b.skin]
    }

    /// 战斗里的人物：有自定义外观就用它（护甲按外观规则：可以「跟随所穿护甲」），否则按入队顺序用三位预设旅人
    static func battle(unit: GameUnit, slot: Int) -> PixelHeroLook {
        if let a = unit.appearance {
            return PixelHeroLook(body: a.body, armor: a.armor(worn: unit.equipment.armor), weapon: unit.equipment.weapon, hair: a.hair, face: a.face)
        }
        return PixelHeroLook(body: presetBodies[((slot % 3) + 3) % 3], armor: unit.equipment.armor, weapon: unit.equipment.weapon)
    }
}

/// 把烘焙结果排成游戏现有的两种格式：
///   地图：两张 13 列 × 4 行、每格 256 px 的图集（Directions：下 左 上 右；Diagonals：右下 左下 左上 右上），
///         列 0 待机，1–8 行走 8 相位，9–12 起步 / 停步；HeroFrames、投影渲染都按这个格式读，不用改。
///   战斗：右侧朝向的战斗帧，排在 256 px 画布上，脚底对准 (123, 214)，和原来的战斗人物同一个锚点。
/// 精灵放大 4 倍（整数倍，像素不糊）：地图上一个精灵像素正好 1 pt。
enum PixelHeroAtlas {
    static var enabled = true
    static let cell = 256
    static let columns = 13
    static let zoom = 4
    /// 地图格子里脚底中心的位置（精灵节点的 anchorPoint 是 (0.5, 0.125)）
    static let mapFoot = CGPoint(x: 128, y: 224)
    /// 战斗画布的脚底锚点
    static let battleFoot = CGPoint(x: 123, y: 214)
    /// 战斗用的高画布：在 256 画布上方多留 64 px，举过头顶的武器不会被裁掉
    static let battleHeadroom = 64

    private static let baker = PixelBaker.shared
    private static var dirs: [String] { baker.info.dirs }

    /// 地图朝向 0–7 → (5 个手绘方向里的第几个, 是否镜像)。手绘方向顺序：S SE E NE N
    static let facingSource: [(dir: Int, mirrored: Bool)] = [
        (0, false), (2, true), (4, false), (2, false),   // 下 左 上 右
        (1, false), (1, true), (3, true), (3, false),    // 右下 左下 左上 右上
    ]

    // MARK: 后台预烘
    //
    // App 里的 JavaScriptCore 没有 JIT，第一次烘一个人约 1 秒。所有「要用到新外观」的地方先问 isMapReady / isBattleReady，
    // 没好就调 prepare 在后台烘，界面先保持原样，烘好后在主线程回调再刷新，这样换装、进战斗都不会卡住主线程。

    private static let workQueue = DispatchQueue(label: "pixel-hero.prepare", qos: .userInitiated)
    /// 正在后台烘的外观（只在主线程读写）
    private static var inFlight: [String: [() -> Void]] = [:]

    static func isMapReady(_ look: PixelHeroLook) -> Bool {
        atlasCache.object(forKey: name(look: look, half: 0) as NSString) != nil && atlasCache.object(forKey: name(look: look, half: 1) as NSString) != nil
    }
    static func isBattleReady(_ look: PixelHeroLook) -> Bool { battleCache.object(forKey: look.key as NSString) != nil }

    /// 在后台烘好这些外观的地图图集 / 战斗帧，全部完成后在主线程调用 completion。主线程调用。
    static func prepare(map: [PixelHeroLook] = [], battle: [PixelHeroLook] = [], completion: @escaping () -> Void = {}) {
        let mapNeeded = Array(Set(map.filter { !isMapReady($0) }))
        let battleNeeded = Array(Set(battle.filter { !isBattleReady($0) }))
        guard !mapNeeded.isEmpty || !battleNeeded.isEmpty else { completion(); return }
        let key = "map:" + mapNeeded.map(\.key).sorted().joined(separator: ",") + "|battle:" + battleNeeded.map(\.key).sorted().joined(separator: ",")
        if inFlight[key] != nil { inFlight[key]?.append(completion); return }
        inFlight[key] = [completion]
        workQueue.async {
            for look in mapNeeded { for half in 0...1 { _ = atlas(named: name(look: look, half: half)) } }
            for look in battleNeeded { _ = battle(look) }
            DispatchQueue.main.async {
                let callbacks = inFlight.removeValue(forKey: key) ?? []
                callbacks.forEach { $0() }
            }
        }
    }

    // MARK: 名字（HeroFrames 用名字找图集）

    static let prefix = "Pixel|"
    static func isPixel(_ name: String) -> Bool { name.hasPrefix(prefix) }
    static func name(look: PixelHeroLook, half: Int) -> String { prefix + look.key + "|" + String(half) }
    static func parse(_ name: String) -> (look: PixelHeroLook, half: Int)? {
        guard isPixel(name) else { return nil }
        let rest = String(name.dropFirst(prefix.count))
        guard let bar = rest.lastIndex(of: "|"), let half = Int(rest[rest.index(after: bar)...]),
              let look = PixelHeroLook(key: String(rest[..<bar])) else { return nil }
        return (look, half)
    }

    // MARK: 地图图集

    /// 地图图集的 13 列分别取哪一帧：待机、8 相位行走、起步（行走前两相位）、停步（行走后两相位）
    private static var mapColumnFrames: [Int] {
        let walk = baker.info.frames["walk8"] ?? Array(100..<108)
        return [0] + walk + [walk[0], walk[1], walk[6], walk[7]]
    }

    private static let atlasCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>(); c.totalCostLimit = 220 * 1024 * 1024; return c
    }()

    /// HeroFrames.image(named:) 的像素版：按名字烘焙（或读缓存）并排成图集
    static func atlas(named name: String) -> UIImage? {
        if let hit = atlasCache.object(forKey: name as NSString) { return hit }
        guard let parsed = parse(name) else { return nil }
        let look = parsed.look, half = parsed.half
        let frames = Array(Set(mapColumnFrames)).sorted()
        guard let strip = baker.bake(spec: look.spec, dirs: dirs, frames: frames) else { return nil }
        let w = baker.info.sprW, h = baker.info.sprH
        let stripW = w * frames.count
        let W = cell * columns, H = cell * 4
        var out = [UInt8](repeating: 0, count: W * H * 4)
        let footPx = baker.info.footPx
        strip.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            for row in 0..<4 {
                let facing = half * 4 + row
                let (dir, mirrored) = facingSource[facing]
                // 镜像时脚底中心也跟着翻过去，四舍五入到整像素
                let fx = mirrored ? Double(w) - footPx[0] : footPx[0]
                let ox = Int((Double(mapFoot.x) - fx * Double(zoom)).rounded())
                let oy = Int((Double(mapFoot.y) - footPx[1] * Double(zoom)).rounded())
                for (column, frame) in mapColumnFrames.enumerated() {
                    guard let k = frames.firstIndex(of: frame) else { continue }
                    blit(src: src, srcStride: stripW, sx: k * w, sy: dir * h, w: w, h: h, mirrored: mirrored,
                         dst: &out, dstStride: W, cellX: column * cell, cellY: row * cell, ox: ox, oy: oy)
                }
            }
        }
        guard let image = makeImage(out, width: W, height: H) else { return nil }
        atlasCache.setObject(image, forKey: name as NSString, cost: W * H * 4)
        return image
    }

    /// 人物工作室的格子预览：图集已经在内存里就直接裁一格，否则只烘这一帧（选项很多，整张图集太慢）
    static func cell(look: PixelHeroLook, facing: Int, column: Int) -> UIImage? {
        let half = facing >= 4 ? 1 : 0
        let atlasName = name(look: look, half: half)
        if let atlas = atlasCache.object(forKey: atlasName as NSString)?.cgImage,
           let crop = atlas.cropping(to: CGRect(x: column * cell, y: (facing % 4) * cell, width: cell, height: cell)) {
            return UIImage(cgImage: crop)
        }
        let (dir, mirrored) = facingSource[((facing % 8) + 8) % 8]
        let columnFrames = mapColumnFrames
        let frame = columnFrames[min(columnFrames.count - 1, max(0, column))]
        guard let strip = baker.bake(spec: look.spec, dirs: [dirs[dir]], frames: [frame]) else { return nil }
        let w = baker.info.sprW, h = baker.info.sprH, footPx = baker.info.footPx
        let fx = mirrored ? Double(w) - footPx[0] : footPx[0]
        let ox = Int((Double(mapFoot.x) - fx * Double(zoom)).rounded())
        let oy = Int((Double(mapFoot.y) - footPx[1] * Double(zoom)).rounded())
        var out = [UInt8](repeating: 0, count: cell * cell * 4)
        strip.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            blit(src: src, srcStride: w, sx: 0, sy: 0, w: w, h: h, mirrored: mirrored, dst: &out, dstStride: cell, cellX: 0, cellY: 0, ox: ox, oy: oy)
        }
        return makeImage(out, width: cell, height: cell)
    }

    // MARK: 战斗

    /// 一个人物的战斗帧：右侧朝向，每帧两张图（显示用的高画布、投影用的 256 画布）和两只脚的落点
    final class BattleSprite {
        let look: PixelHeroLook
        /// 普通攻击动作：slash / heavy / shoot / cast
        let attack: String
        /// 动画名 → 帧
        let frames: [String: [Frame]]
        struct Frame {
            /// 256 × (256 + headroom)，脚底在 (123, 214 + headroom)
            let tall: UIImage
            /// 256 × 256，脚底在 (123, 214)，给地面投影用
            let canvas: UIImage
            /// 画布坐标里的两只脚
            let contacts: [CGPoint]
        }
        init(look: PixelHeroLook, attack: String, frames: [String: [Frame]]) { self.look = look; self.attack = attack; self.frames = frames }
    }

    private static let battleCache: NSCache<NSString, BattleSprite> = {
        let c = NSCache<NSString, BattleSprite>(); c.countLimit = 16; return c
    }()

    static let battleAnimations = ["ready", "slash", "heavy", "shoot", "cast", "guard", "hurt", "victory", "defeat"]

    static func battle(_ look: PixelHeroLook) -> BattleSprite? {
        if let hit = battleCache.object(forKey: look.key as NSString) { return hit }
        let info = baker.info
        let weapon = look.spriteWeapon
        let attack = baker.attackAnimation(ofSpriteWeapon: weapon)
        // 只烘这个人会用到的：战斗待机、自己武器的攻击、施法、格挡、受击、胜利、倒下
        let names = ["ready", attack, "cast", "guard", "hurt", "victory", "defeat"].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let frameIDs = names.flatMap { info.frames[$0] ?? [] }
        guard !frameIDs.isEmpty, let strip = baker.bake(spec: look.spec, dirs: ["E"], frames: frameIDs) else { return nil }
        let feet = baker.feet(hold: baker.hold(ofSpriteWeapon: weapon), dir: "E", frames: frameIDs)
        let w = info.sprW, h = info.sprH, stripW = w * frameIDs.count
        let ox = Int((Double(battleFoot.x) - info.footPx[0] * Double(zoom)).rounded())
        let oy = Int((Double(battleFoot.y) - info.footPx[1] * Double(zoom)).rounded())
        let tallH = cell + battleHeadroom
        var built: [String: [BattleSprite.Frame]] = [:]
        strip.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            var index = 0
            for name in names {
                var list: [BattleSprite.Frame] = []
                for _ in info.frames[name] ?? [] {
                    var tall = [UInt8](repeating: 0, count: cell * tallH * 4)
                    blit(src: src, srcStride: stripW, sx: index * w, sy: 0, w: w, h: h, mirrored: false,
                         dst: &tall, dstStride: cell, cellX: 0, cellY: 0, ox: ox, oy: oy + battleHeadroom, cellW: cell, cellH: tallH)
                    let canvasBytes = Array(tall[(battleHeadroom * cell * 4)...])
                    let contacts = (index < feet.count ? feet[index] : []).map {
                        CGPoint(x: CGFloat(ox) + $0.x * CGFloat(zoom), y: CGFloat(oy) + $0.y * CGFloat(zoom))
                    }
                    if let t = makeImage(tall, width: cell, height: tallH), let c = makeImage(canvasBytes, width: cell, height: cell) {
                        list.append(.init(tall: t, canvas: c, contacts: contacts))
                    }
                    index += 1
                }
                built[name] = list
            }
        }
        let sprite = BattleSprite(look: look, attack: attack, frames: built)
        battleCache.setObject(sprite, forKey: look.key as NSString)
        return sprite
    }

    /// 弓箭离弦的位置（战斗画布坐标）：放箭那一帧持弓的左手，往前一点
    static let bowTip: PartyPoint = {
        guard let release = baker.info.frames["shoot"]?[2], let hand = baker.hand(hold: "bow", dir: "E", frame: release) else {
            return PartyPoint(Double(battleFoot.x) + 40, Double(battleFoot.y) - 120)
        }
        return canvasPoint(hand.point.x + 3 * hand.scale, hand.point.y)
    }()

    /// 法杖施法释放的位置（战斗画布坐标）：施法第 3 帧的杖头宝珠
    static let staffGem: PartyPoint = {
        guard let burst = baker.info.frames["cast"]?[2], let hand = baker.hand(hold: "up", dir: "E", frame: burst) else {
            return PartyPoint(Double(battleFoot.x) + 30, Double(battleFoot.y) - 160)
        }
        let length = 38 * hand.scale * hand.reach
        return canvasPoint(hand.point.x + cos(hand.angle) * length, hand.point.y + sin(hand.angle) * length)
    }()

    private static func canvasPoint(_ x: CGFloat, _ y: CGFloat) -> PartyPoint {
        let info = baker.info
        let ox = Double(battleFoot.x) - info.footPx[0] * Double(zoom), oy = Double(battleFoot.y) - info.footPx[1] * Double(zoom)
        return PartyPoint(ox + Double(x) * Double(zoom), oy + Double(y) * Double(zoom))
    }

    // MARK: 像素搬运

    /// 把精灵的一帧（w × h）放大 zoom 倍贴进目标缓冲：贴在格子 (cellX, cellY) 里偏移 (ox, oy) 的位置，超出格子的部分裁掉
    private static func blit(src: UnsafeRawBufferPointer, srcStride: Int, sx: Int, sy: Int, w: Int, h: Int, mirrored: Bool,
                             dst: inout [UInt8], dstStride: Int, cellX: Int, cellY: Int, ox: Int, oy: Int,
                             cellW: Int = cell, cellH: Int = cell) {
        for y in 0..<h {
            for x in 0..<w {
                let si = ((sy + y) * srcStride + sx + (mirrored ? w - 1 - x : x)) * 4
                let a = src[si + 3]
                if a == 0 { continue }
                for dy in 0..<zoom {
                    let ty = oy + y * zoom + dy
                    if ty < 0 || ty >= cellH { continue }
                    for dx in 0..<zoom {
                        let tx = ox + x * zoom + dx
                        if tx < 0 || tx >= cellW { continue }
                        let di = ((cellY + ty) * dstStride + cellX + tx) * 4
                        dst[di] = src[si]; dst[di + 1] = src[si + 1]; dst[di + 2] = src[si + 2]; dst[di + 3] = a
                    }
                }
            }
        }
    }

    static func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}
