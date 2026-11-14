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
