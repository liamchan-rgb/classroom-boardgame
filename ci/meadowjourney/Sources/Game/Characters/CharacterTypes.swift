import Foundation

// 人物像素精灵：图层、槽位、装备数据格式。与 layers.ts / types.ts 对应。

/// 纸娃娃图层，从后到前；默认 z = 序号 × 10
enum LayerId: Int, CaseIterable {
    case cape, weaponBack, armBack, legs, bottom, shoes, torso, top, bag, armFront, mantle
    case weaponMid, hairBack, head, scarf, hair, weaponFront

    var z: Int { rawValue * 10 }
}

/// 装备槽位
enum Slot: String, CaseIterable {
    case face, hair, top, bottom, shoes, scarf, bag
    case weaponMain = "weapon_main"
    case weaponOff = "weapon_off"
}

/// 传给部件绘制函数的上下文
final class DrawContext {
    let dir: Dir5
    let frame: Int
    let pose: CharacterPose
    let L: PixelLayer
    let g: SpriteBrush
    /// 武器槽位专用：所在手的锚点
    let hand: HandAnchor?
    private let palettes: [String: SpritePalette]
    private let bodyPalettes: [String: SpritePalette]
    private let fallback: SpritePalette?

    init(dir: Dir5, frame: Int, pose: CharacterPose, L: PixelLayer, g: SpriteBrush, hand: HandAnchor?,
         palettes: [String: SpritePalette], bodyPalettes: [String: SpritePalette], fallback: SpritePalette?) {
        self.dir = dir
        self.frame = frame
        self.pose = pose
        self.L = L
        self.g = g
        self.hand = hand
        self.palettes = palettes
        self.bodyPalettes = bodyPalettes
        self.fallback = fallback
    }

    /// 选择本装备的调色板；找不到时回落到身体的调色板（五官的嘴和眉用 skin）
    func pal(_ key: String = "main") {
        if let p = palettes[key] ?? bodyPalettes[key] ?? fallback { L.use(p) }
    }
}

enum PartLayer {
    case fixed(LayerId)
    /// 按手部锚点和握持方式自动选择 weaponFront / weaponMid / weaponBack
    case weapon
    case dynamic((DrawContext) -> LayerId)
}

/// 一件装备里的一个可绘制部件
struct PartDef {
    var layer: PartLayer
    var draw: ((DrawContext) -> Void)? = nil
    /// 每个方向的像素矩阵（一个字符 = 一格）
    var frames: [Dir5: [String]]? = nil
    /// 矩阵贴到哪个点（单位坐标），默认颈部
    var anchor: ((DrawContext) -> SpritePoint)? = nil
    var offset: (Double, Double) = (0, 0)
    var paletteKey: String = "main"
    var outline: Bool = true
    /// 只画在下面已合成好的本体像素上（五官）
    var maskBelow: Bool = false
}

struct ItemVariant {
    let id: String
    let name: String
    let palettes: [String: SpritePalette]
}

/// 一件装备 = 一个数据对象
struct ItemDef {
    let id: String
    let name: String
    let slot: Slot?
    let palettes: [String: SpritePalette]
    var variants: [ItemVariant] = []
    var parts: [PartDef]
    /// 武器的握持方式
    var hold: Hold? = nil
    /// 图层顺序覆盖：只影响本装备的部件
    var layerOverride: ((Dir5) -> [LayerId: Int])? = nil
    /// 装备后隐藏哪些槽位
    var hides: [Slot] = []
}

/// 套装：一组「槽位 → 装备 id」
struct OutfitDef {
    let id: String
    let name: String
    let slots: [Slot: String?]
    let variants: [Slot: String]
}

/// 合成时的一项
struct LoadoutEntry {
    /// nil = 身体
    let slot: Slot?
    let item: ItemDef
    let palettes: [String: SpritePalette]
}

/// 装备系统：只管「哪个槽位穿着什么、用什么颜色」
final class Equipment {
    private struct Equipped {
        var item: ItemDef
        var overrides: [String: SpritePalette] = [:]
        var variantId: String?
    }

    private let body: ItemDef
    private var slots: [Slot: Equipped] = [:]
    private var bodyOverrides: [String: SpritePalette] = [:]

    init(body: ItemDef) { self.body = body }

    func equip(_ slot: Slot, _ item: ItemDef) { slots[slot] = Equipped(item: item) }
    func unequip(_ slot: Slot) { slots[slot] = nil }
    func item(in slot: Slot) -> ItemDef? { slots[slot]?.item }
    func variant(in slot: Slot) -> String? { slots[slot]?.variantId }

    /// 替换某槽位装备的一个调色板
    func setPalette(_ slot: Slot, _ palette: SpritePalette, key: String = "main") {
        guard var e = slots[slot] else { return }
        e.overrides[key] = palette
        e.variantId = nil
        slots[slot] = e
    }

    /// 替换身体的调色板（肤色 skin）
    func setBodyPalette(_ palette: SpritePalette, key: String = "skin") { bodyOverrides[key] = palette }

    /// 应用装备自带的换色方案
    func setVariant(_ slot: Slot, _ variantId: String) {
        guard var e = slots[slot], let v = e.item.variants.first(where: { $0.id == variantId }) else { return }
        e.overrides = v.palettes
        e.variantId = v.id
        slots[slot] = e
    }

    /// 解析成合成用的列表（身体在最前，处理 hides）
    func resolve() -> [LoadoutEntry] {
        var hidden = Set<Slot>()
        for e in slots.values { e.item.hides.forEach { hidden.insert($0) } }
        var out = [LoadoutEntry(slot: nil, item: body, palettes: body.palettes.merging(bodyOverrides) { $1 })]
        for slot in Slot.allCases {
            guard let e = slots[slot], !hidden.contains(slot) else { continue }
            out.append(LoadoutEntry(slot: slot, item: e.item, palettes: e.item.palettes.merging(e.overrides) { $1 }))
        }
        return out
    }
}
