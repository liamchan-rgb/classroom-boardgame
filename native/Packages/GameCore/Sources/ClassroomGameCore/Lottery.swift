import Foundation

/// The shop's prize wheel. Three tiers: the dearer the spin, the better the pool; set pieces (which the shop never sells)
/// can only come from here or from monsters. Each spin draws once from the save's own random stream, so it replays
/// identically and is undoable like any other operation.
public struct LotteryPrize: Equatable {
    public let item: String?
    public let count: Int
    public let coins: Int
    public let weight: Int
}
public struct LotteryTier: Equatable {
    public let title: String
    public let cost: Int
    public let prizes: [LotteryPrize]
    public var totalWeight: Int { prizes.reduce(0) { $0 + $1.weight } }
}
public enum CampaignLottery {
    private static func item(_ id: String, _ weight: Int, _ count: Int = 1) -> LotteryPrize { LotteryPrize(item: id, count: count, coins: 0, weight: weight) }
    private static func coins(_ amount: Int, _ weight: Int) -> LotteryPrize { LotteryPrize(item: nil, count: 0, coins: amount, weight: weight) }
    private static let t1SetPieces = ["wildwoodSpear", "wildwoodArmor", "wildwoodCharm"]
    private static let t2SetPieces = ["galeLongbow", "galeArmor", "galeCharm", "oakHammer", "oakArmor", "oakCharm"]
    private static let t3SetPieces = ["starlightBlade", "starlightArmor", "starlightCharm", "emberStaff", "emberArmor", "emberCharm"]
    private static let t4SetPieces = ["dragonFangSword", "dragonArmor", "dragonCharm", "aegisLance", "aegisArmor", "aegisCharm", "astralCodex", "astralArmor", "astralCharm"]
    public static let tiers: [LotteryTier] = [
        LotteryTier(title: "铜", cost: 30, prizes: [
            coins(15, 22), item("smallPotion", 18), item("berryTea", 14), item("shieldPotion", 12), item("largePotion", 10),
            item("oakSlingshot", 6), item("woodenStaff", 6), item("ironDagger", 5), item("travelerCloak", 6), item("leatherArmor", 6),
            item("studdedVest", 5), item("cloverAmulet", 5), item("woodenWhistle", 5), item("huntingBow", 4), item("powerBadge", 4),
            item("revivalStone", 4), coins(60, 4)
        ] + t1SetPieces.map { item($0, 4) } + t2SetPieces.map { item($0, 1) }),
        LotteryTier(title: "银", cost: 80, prizes: [
            coins(45, 14), item("largePotion", 12, 2), item("ironbarkElixir", 10), item("honeySalve", 10), item("revivalStone", 10),
            item("frostWand", 8), item("knightHalberd", 8), item("greatSword", 7), item("runeArmor", 8), item("chainmailCoat", 7),
            item("windrunnerGarb", 7), item("eagleEyeLens", 7), item("actionRing", 7), item("powerBadge", 6), coins(150, 5)
        ] + t2SetPieces.map { item($0, 4) } + t3SetPieces.map { item($0, 2) }),
        LotteryTier(title: "金", cost: 180, prizes: [
            coins(120, 8), item("superPotion", 10, 2), item("crystalBarrierFlask", 10), item("phoenixNectar", 8), item("revivalStone", 8, 2),
            item("flameAxe", 8), item("thunderCrossbow", 8), item("emeraldScepter", 8), item("shadowTwinblades", 7),
            item("mithrilPlate", 8), item("arcaneMantle", 8), item("rubyHeartPendant", 8), item("chronoPocketwatch", 7),
            item("legendaryStaff", 8)
        ] + t3SetPieces.map { item($0, 6) } + t4SetPieces.map { item($0, 3) }),
        LotteryTier(title: "星穹", cost: 280, prizes: [
            item("phoenixNectar", 8, 2), item("starlightElixir", 8, 2), item("aegisCrystal", 8, 2),
            item("legendaryStaff", 9), item("sunbreakerBlade", 10), item("astralGreatbow", 10),
            item("titanFortressArmor", 9), item("phoenixFeatherRobe", 10), item("crownOfValor", 9), item("infinityHourglass", 10)
        ] + t3SetPieces.map { item($0, 4) } + t4SetPieces.map { item($0, 8) }),
    ]
    public static func tier(_ index: Int) throws -> LotteryTier {
        guard tiers.indices.contains(index) else { throw GameError("没有这一档抽奖。") }
        return tiers[index]
    }
}

extension Evaluation {
    mutating func campaignLottery(actor id: String, tier index: Int) throws {
        var actor = try acting(id)
        guard state.phase == .exploration, state.battle == nil, actor.kind == .player else { throw GameError("请在探索中抽奖。") }
        let tier = try CampaignLottery.tier(index)
        guard actor.coins >= tier.cost else { throw GameError("金币不足：\(tier.title)档需要 \(tier.cost) 金币。") }
        for prize in tier.prizes { if let item = prize.item { _ = try catalog.item(item) } }
        actor.coins -= tier.cost
        var roll = try state.random.next(upperBound: tier.totalWeight)
        var picked = tier.prizes.count - 1
        for (i, prize) in tier.prizes.enumerated() { if roll < prize.weight { picked = i; break }; roll -= prize.weight }
        let prize = tier.prizes[picked]
        if let item = prize.item { actor.inventory[item] = try checkedAdd(actor.inventory[item] ?? 0, prize.count) }
        else { actor.coins = try checkedAdd(actor.coins, prize.coins) }
        state.units[id] = actor
        events.append(GameEvent("lottery", actor: id, amount: picked, detail: "\(index):\(prize.item ?? "coins"):\(prize.item == nil ? prize.coins : prize.count)"))
    }
}

/// A wheel the teacher makes: in-game prizes (an item, coins, score) or a prize outside the game (text only, e.g.
/// "免作业一次"), each with its own weight. Spinning may cost coins (0 = free).
public struct CustomWheelPrize: Codable, Equatable {
    public var title: String
    public var item: String?
    public var count: Int
    public var coins: Int
    public var score: Int
    public var weight: Int
    public init(title: String, item: String? = nil, count: Int = 0, coins: Int = 0, score: Int = 0, weight: Int) {
        self.title = title; self.item = item; self.count = count; self.coins = coins; self.score = score; self.weight = weight
    }
    /// Only text: the reward is given outside the game.
    public var offGame: Bool { item == nil && coins == 0 && score == 0 }
}
public struct CustomWheel: Codable, Equatable {
    public var name: String
    public var cost: Int
    public var prizes: [CustomWheelPrize]
    public init(name: String, cost: Int = 0, prizes: [CustomWheelPrize]) { self.name = name; self.cost = cost; self.prizes = prizes }
    public var totalWeight: Int { prizes.reduce(0) { $0 + max(0, $1.weight) } }
    /// Chance of each prize (0…1).
    public func chance(_ i: Int) -> Double { totalWeight == 0 || !prizes.indices.contains(i) ? 0 : Double(max(0, prizes[i].weight)) / Double(totalWeight) }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 40 else { throw GameError("转盘名称需为1–40字。") }
        guard (2...24).contains(prizes.count) else { throw GameError("转盘需要2–24个奖项。") }
        guard (0...1000).contains(cost) else { throw GameError("每次花费需在0–1000金币之间。") }
        for p in prizes {
            guard !p.title.trimmingCharacters(in: .whitespaces).isEmpty, p.title.count <= 40 else { throw GameError("每个奖项需要1–40字的名字。") }
            guard (0...1000).contains(p.weight), (0...99).contains(p.count), (0...10000).contains(p.coins), (0...1000).contains(p.score) else { throw GameError("奖项「\(p.title)」的数值超出范围。") }
            if p.item != nil { guard p.count >= 1 else { throw GameError("奖项「\(p.title)」至少给1件物品。") } }
        }
        guard totalWeight > 0 else { throw GameError("至少要有一个奖项的概率大于0。") }
    }
}

extension Evaluation {
    mutating func customWheel(actor id: String, wheel: CustomWheel) throws {
        var actor = try acting(id)
        guard state.battle == nil, actor.kind == .player else { throw GameError("请在战斗外转转盘。") }
        try wheel.validate()
        for prize in wheel.prizes { if let item = prize.item { _ = try catalog.item(item) } }
        guard actor.coins >= wheel.cost else { throw GameError("金币不足：转一次需要 \(wheel.cost) 金币。") }
        actor.coins -= wheel.cost
        var roll = try state.random.next(upperBound: wheel.totalWeight)
        var picked = wheel.prizes.count - 1
        for (i, prize) in wheel.prizes.enumerated() { let w = max(0, prize.weight); if roll < w { picked = i; break }; roll -= w }
        let prize = wheel.prizes[picked]
        if let item = prize.item { actor.inventory[item] = try checkedAdd(actor.inventory[item] ?? 0, prize.count) }
        actor.coins = try checkedAdd(actor.coins, prize.coins)
        actor.score = try checkedAdd(actor.score, prize.score)
        state.units[id] = actor
        events.append(GameEvent("customWheel", actor: id, amount: picked, detail: "\(wheel.name):\(prize.title)"))
    }
}
