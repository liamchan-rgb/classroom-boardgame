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
    private static let setPieces = ["starlightBlade", "starlightArmor", "starlightCharm", "dragonFangSword", "dragonArmor", "dragonCharm"]
    public static let tiers: [LotteryTier] = [
        LotteryTier(title: "铜", cost: 30, prizes: [
            coins(15, 22), item("smallPotion", 22), item("shieldPotion", 14), item("largePotion", 12), item("leatherArmor", 8),
            item("huntingBow", 7), item("powerBadge", 5), item("revivalStone", 4), coins(60, 3)
        ] + setPieces.map { item($0, 1) }),
        LotteryTier(title: "银", cost: 80, prizes: [
            coins(40, 14), item("largePotion", 14, 2), item("revivalStone", 12), item("runeArmor", 11), item("greatSword", 9),
            item("actionRing", 9), item("powerBadge", 8), coins(150, 5)
        ] + setPieces.map { item($0, 3) }),
        LotteryTier(title: "金", cost: 180, prizes: [
            item("legendaryStaff", 12), item("greatSword", 8), item("actionRing", 8), item("revivalStone", 8, 2), coins(120, 8)
        ] + setPieces.map { item($0, 9) }),
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
