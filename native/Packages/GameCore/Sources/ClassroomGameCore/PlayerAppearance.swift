import Foundation

/// Persistent cosmetic identifiers, shared by exploration, inventory and combat.
/// Optional new fields preserve the exact appearance of pre-customization saves.
public struct PlayerAppearance: Codable, Equatable {
    public var body: String
    /// nil follows worn armor. Cosmetic outfits never grant item statistics.
    public var outfit: String?
    public var hair: String?
    public var face: String?
    public static let hairOptions:[String] = ["m1-short","m2-sidepart","m3-topknot","f1-bob","f2-ponytail","f3-bun"].map{"p1-custom-hair-\($0)-v1"}
    public static let faceOptions:[String] = ["m1-bright","m2-calm","f1-gentle","f2-clear"].map{"p1-custom-face-\($0)-v1"}
    public static let outfitOptions = ["blue","leatherArmor","runeArmor","starlightArmor","dragonArmor"]
    public init(body:String="forester",outfit:String?=nil,hair:String?=nil,face:String?=nil){self.body=body;self.outfit=outfit;self.hair=hair;self.face=face}
    public func validate() throws {
        guard ["forester","wayfarer"].contains(body),outfit.map({Self.outfitOptions.contains($0)}) ?? true,
              hair.map({Self.hairOptions.contains($0)}) ?? true,face.map({Self.faceOptions.contains($0)}) ?? true else{throw GameError("外观款式不受支持。")}
    }
    /// A random body, hair style and face (every choice valid). The outfit keeps following worn armor, so a
    /// random look never shows gear the student does not have. `excluding` avoids repeating a look already in use.
    public static func random<R:RandomNumberGenerator>(using rng:inout R,excluding used:[PlayerAppearance]=[])->PlayerAppearance {
        var pick=PlayerAppearance()
        for _ in 0..<8 {
            pick=PlayerAppearance(body:["forester","wayfarer"].randomElement(using:&rng)!,hair:hairOptions.randomElement(using:&rng),face:faceOptions.randomElement(using:&rng))
            if !used.contains(pick) {break}
        }
        return pick
    }
    public static func random(excluding used:[PlayerAppearance]=[])->PlayerAppearance {var g=SystemRandomNumberGenerator();return random(using:&g,excluding:used)}
    public func armor(worn:String?)->String? {outfit == "blue" ? nil:(outfit ?? worn)}
    public var visualKey:String {[body,outfit ?? "follow",hair ?? "original",face ?? "original"].joined(separator:"|")}
}
