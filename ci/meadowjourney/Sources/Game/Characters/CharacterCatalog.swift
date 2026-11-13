import Foundation

// 人物像素精灵：装备目录、套装与角色预设。与 registry.ts / outfits.ts / characters.ts 对应。
// 用代码画的装备（衣服、武器）在这里登记；发型、五官从 Resources/CharacterParts 的 JSON 自动读入。

final class CharacterCatalog {
    static let shared = CharacterCatalog(bundle: .main)

    private(set) var items: [String: ItemDef] = [:]

    init(bundle: Bundle) {
        for item in [ClothingItems.travelerJacket, ClothingItems.redCloak, ClothingItems.trousers,
                     ClothingItems.boots, ClothingItems.navyScarf, ClothingItems.satchel,
                     WeaponItems.shortSword, WeaponItems.staff] {
            items[item.id] = item
        }
        let decoder = JSONDecoder()
        for url in Self.partFiles(bundle, "hair") {
            if let data = try? Data(contentsOf: url), let hair = try? decoder.decode(HairData.self, from: data) {
                items[hair.id] = HairKit.make(hair)
            }
        }
        for url in Self.partFiles(bundle, "face") {
            if let data = try? Data(contentsOf: url), let face = try? decoder.decode(FaceData.self, from: data) {
                items[face.id] = FaceKit.make(face)
            }
        }
    }

    /// Resources/CharacterParts/<kind>/*.json，按文件名排序（与网页端一致）
    private static func partFiles(_ bundle: Bundle, _ kind: String) -> [URL] {
        guard let root = bundle.url(forResource: "CharacterParts", withExtension: nil) else { return [] }
        let dir = root.appendingPathComponent(kind)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func item(_ id: String) -> ItemDef? { items[id] }

    func items(for slot: Slot) -> [ItemDef] {
        items.values.filter { $0.slot == slot }.sorted { $0.id < $1.id }
    }

    // MARK: 套装

    static let outfits: [OutfitDef] = [
        OutfitDef(id: "traveler", name: "蓝色旅人装",
                  slots: [.top: "top_traveler", .bottom: "bottom_trousers", .shoes: "shoes_boots",
                          .scarf: "scarf_navy", .bag: "bag_satchel"],
                  variants: [.top: "blue", .bottom: "dark", .shoes: "brown", .scarf: "navy"]),
        OutfitDef(id: "red_cloak", name: "红色斗篷装",
                  slots: [.top: "top_red_cloak", .bottom: "bottom_trousers", .shoes: "shoes_boots",
                          .scarf: nil, .bag: "bag_satchel"],
                  variants: [.top: "red", .bottom: "brown", .shoes: "black"]),
    ]

    // MARK: 角色预设（与 hd2d-walk-demo/src/items/characters.ts 保持一致）

    static let characters: [CharacterPreset] = [
        CharacterPreset(id: "hero1", name: "旅人", outfit: "traveler", hair: "hair_messy", face: "face_round",
                        weapon: "weapon_short_sword"),
        CharacterPreset(id: "hero2", name: "红斗篷", outfit: "red_cloak", hair: "hair_neat", face: "face_smile",
                        skin: "light", weapon: "weapon_staff", variants: [.hair: "black"]),
        CharacterPreset(id: "hero3", name: "林间行者", outfit: "traveler", hair: "hair_messy", face: "face_round",
                        skin: "tan", variants: [.top: "green", .scarf: "cream", .hair: "blonde", .face: "amber"]),
    ]

    enum BuildError: Error, CustomStringConvertible {
        case missingItem(String, preset: String)
        case missingOutfit(String, preset: String)
        var description: String {
            switch self {
            case let .missingItem(id, p): return "角色 \(p)：找不到装备 \(id)"
            case let .missingOutfit(id, p): return "角色 \(p)：找不到套装 \(id)"
            }
        }
    }

    /// 按预设穿戴好一套装备。找不到的 id 直接报错，避免悄悄画出缺件的角色。
    func equipment(for p: CharacterPreset) throws -> Equipment {
        func need(_ id: String) throws -> ItemDef {
            guard let it = item(id) else { throw BuildError.missingItem(id, preset: p.id) }
            return it
        }
        guard let outfit = Self.outfits.first(where: { $0.id == p.outfit }) else {
            throw BuildError.missingOutfit(p.outfit, preset: p.id)
        }
        let eq = Equipment(body: BodyItem.body)
        if let skin = p.skin, let tone = BodyItem.skinTones[skin] { eq.setBodyPalette(tone) }
        eq.equip(.hair, try need(p.hair))
        eq.equip(.face, try need(p.face))
        for slot in Slot.allCases {
            if let entry = outfit.slots[slot], let id = entry { eq.equip(slot, try need(id)) }
        }
        if let w = p.weapon { eq.equip(.weaponMain, try need(w)) }
        let variants = outfit.variants.merging(p.variants) { $1 }
        for slot in Slot.allCases { if let v = variants[slot] { eq.setVariant(slot, v) } }
        return eq
    }
}

/// 一个角色 = 套装 + 发型 + 五官 + 肤色 + 武器 + 各槽位的换色方案
struct CharacterPreset {
    var id: String
    var name: String
    var outfit: String
    var hair: String
    var face: String
    var skin: String? = nil
    var weapon: String? = nil
    var variants: [Slot: String] = [:]
}
