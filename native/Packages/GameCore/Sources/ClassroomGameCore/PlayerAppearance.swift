import Foundation

/// Persistent cosmetic identifiers, shared by exploration, inventory and combat.
/// Optional new fields preserve the exact appearance of pre-customization saves.
public struct PlayerAppearance: Codable, Equatable {
    public var body: String
    /// nil follows worn armor. Cosmetic outfits never grant item statistics.
    public var outfit: String?
    public var hair: String?
    /// nil follows body default hair color.
    public var hairColor: String?
    public var face: String?

    /// 6 legacy hairstyle IDs preserved at indices 0...5 for existing saves & rosters, followed by 14 expanded styles (20 total).
    public static let hairOptions: [String] = [
        "p1-custom-hair-m1-short-v1",
        "p1-custom-hair-m2-sidepart-v1",
        "p1-custom-hair-m3-topknot-v1",
        "p1-custom-hair-f1-bob-v1",
        "p1-custom-hair-f2-ponytail-v1",
        "p1-custom-hair-f3-bun-v1",
        "hair_neat",
        "hair_ponytail",
        "hair_twintails",
        "hair_twin_buns",
        "hair_bob_cut",
        "hair_spiky",
        "hair_wolf_cut",
        "hair_hime_cut",
        "hair_wavy_long",
        "hair_half_up",
        "hair_curtain",
        "hair_fluffy_curl",
        "hair_side_braid",
        "hair_quiff",
    ]

    /// 20 curated 5-ramp procedural hair colors shared across all hairstyles.
    public static let hairColorOptions: [String] = [
        "black", "brown", "chestnut", "blonde", "cream",
        "caramel", "red", "wine", "pink", "coral",
        "violet", "lavender", "navy", "sky", "teal",
        "mint", "emerald", "ash", "silver", "midnight",
    ]

    /// 4 legacy eye IDs preserved at indices 0...3, followed by 14 expanded jewel & heterochromia eye options (18 total).
    public static let faceOptions: [String] = [
        "p1-custom-face-m1-bright-v1",
        "p1-custom-face-m2-calm-v1",
        "p1-custom-face-f1-gentle-v1",
        "p1-custom-face-f2-clear-v1",
        "eye_teal",
        "eye_ruby",
        "eye_sakura",
        "eye_gold",
        "eye_ice",
        "eye_obsidian",
        "eye_hazel",
        "eye_emerald",
        "eye_orange",
        "eye_silver",
        "eye_indigo",
        "eye_magenta",
        "eye_hetero_gold_blue",
        "eye_hetero_crimson_cyan",
    ]

    /// 16 dedicated cosmetic costumes (时装) — completely independent from in-game armor equipment.
    public static let costumeOptions: [String] = [
        "costume_academy",
        "costume_sailor",
        "costume_mage_robe",
        "costume_hoodie",
        "costume_overalls",
        "costume_kimono",
        "costume_hanfu",
        "costume_noble",
        "costume_sundress",
        "costume_captain",
        "costume_bard",
        "costume_winter_coat",
        "costume_explorer",
        "costume_phantom",
        "costume_chef",
        "costume_idol",
    ]

    /// Legacy outfit IDs accepted for decoding/validating older saves; no longer offered in the costume picker.
    public static let legacyOutfitOptions: [String] = ["blue", "leatherArmor", "runeArmor", "starlightArmor", "dragonArmor"]

    /// All valid persisted `outfit` identifiers (legacy + dedicated costumes).
    public static let outfitOptions: [String] = legacyOutfitOptions + costumeOptions

    public init(body: String = "forester", outfit: String? = nil, hair: String? = nil, hairColor: String? = nil, face: String? = nil) {
        self.body = body
        self.outfit = outfit
        self.hair = hair
        self.hairColor = hairColor
        self.face = face
    }

    public func validate() throws {
        guard ["forester", "wayfarer"].contains(body),
              outfit.map({ Self.outfitOptions.contains($0) }) ?? true,
              hair.map({ Self.hairOptions.contains($0) }) ?? true,
              hairColor.map({ Self.hairColorOptions.contains($0) }) ?? true,
              face.map({ Self.faceOptions.contains($0) }) ?? true else {
            throw GameError("外观款式不受支持。")
        }
    }

    /// A random body, hair style, hair color and eye color (every choice valid). The outfit keeps following worn armor,
    /// so a random look never overrides equipped gear unexpectedly. `excluding` avoids repeating a look already in use.
    public static func random<R: RandomNumberGenerator>(using rng: inout R, excluding used: [PlayerAppearance] = []) -> PlayerAppearance {
        var pick = PlayerAppearance()
        for _ in 0..<8 {
            pick = PlayerAppearance(
                body: ["forester", "wayfarer"].randomElement(using: &rng)!,
                hair: hairOptions.randomElement(using: &rng),
                hairColor: hairColorOptions.randomElement(using: &rng),
                face: faceOptions.randomElement(using: &rng)
            )
            if !used.contains(pick) { break }
        }
        return pick
    }

    public static func random(excluding used: [PlayerAppearance] = []) -> PlayerAppearance {
        var g = SystemRandomNumberGenerator()
        return random(using: &g, excluding: used)
    }

    public func armor(worn: String?) -> String? { outfit == "blue" ? nil : (outfit ?? worn) }

    public var visualKey: String {
        [body, outfit ?? "follow", hair ?? "original", hairColor ?? "default", face ?? "original"].joined(separator: "|")
    }
}
