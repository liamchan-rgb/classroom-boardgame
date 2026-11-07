import Foundation

/// Cosmetics only: never grants equipment or changes combat statistics.
public struct PlayerAppearance: Codable, Equatable {
    public var body: String
    /// nil follows worn armor; "blue" is the approved blue outfit.
    public var outfit: String?
    public init(body:String="forester",outfit:String?=nil){self.body=body;self.outfit=outfit}
    public func validate() throws {
        guard ["forester","wayfarer"].contains(body),outfit.map({["blue","leatherArmor","runeArmor"].contains($0)}) ?? true else{throw GameError("外观款式不受支持。")}
    }
    public func armor(worn:String?)->String? {outfit == "blue" ? nil:(outfit ?? worn)}
}
