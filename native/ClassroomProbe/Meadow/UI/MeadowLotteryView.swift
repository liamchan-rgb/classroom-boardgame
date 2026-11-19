import UIKit
import ClassroomGameCore

/// The shop's prize wheel: pick a tier (铜 / 银 / 金), spin, the wheel decelerates onto the prize the rules drew and
/// celebrates it by rarity. The view never decides the prize; `onSpin` performs the rule operation and returns the slot.
final class MeadowLotteryView: UIView {
    var onSpin: ((Int) -> Int?)?
    var onFinished: ((Int, Int) -> Void)?
    private(set) var tier = 0
    private let tiers = UISegmentedControl(items: CampaignLottery.tiers.map { "\($0.title)档 · \($0.cost)" })
    private let wheel = MeadowPrizeWheelView()
    private let card = WheelPrizeCard()
    private let spin = MeadowPreviewPalette.iconButton("sparkles", "抽一次", prominent: true)
    private let note = MeadowPreviewPalette.label("", size: 15, weight: .semibold)
    var catalog: GameCatalog? { didSet { selectTier() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for state in [UIControl.State.normal, .selected] {
            tiers.setTitleTextAttributes([.font: MeadowPreviewPalette.font(16, .bold), .foregroundColor: MeadowPreviewPalette.ink], for: state)
        }
        tiers.selectedSegmentTintColor = MeadowPreviewPalette.primary
        tiers.selectedSegmentIndex = 0
        tiers.addAction(UIAction { [weak self] _ in self?.selectTier() }, for: .valueChanged)
        note.textAlignment = .center; note.numberOfLines = 2; note.textColor = MeadowPreviewPalette.muted
        spin.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
        [tiers, wheel, spin, note, card].forEach(addSubview)
        selectTier()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func slices(_ tier: LotteryTier, catalog: GameCatalog?) -> [WheelSlice] {
        tier.prizes.map { p in
            if let id = p.item {
                let item = try? catalog?.item(id)
                return WheelSlice(title: item?.name ?? id, icon: MeadowItemIcon.image(id, item: item, side: 96), badge: p.count > 1 ? "×\(p.count)" : nil,
                                  rarity: MeadowItemRarity.of(id, item: item))
            }
            return WheelSlice(title: "金币", icon: nil, badge: "\(p.coins)", rarity: p.coins >= 120 ? .rare : .common, coins: true)
        }
    }
    private func selectTier() {
        guard !wheel.spinning else { tiers.selectedSegmentIndex = tier; return }
        tier = max(0, tiers.selectedSegmentIndex)
        let t = CampaignLottery.tiers[tier]
        wheel.slices = Self.slices(t, catalog: catalog); card.hide()
        let sets = t.prizes.filter { p in p.item.flatMap { try? catalog?.item($0).setID } != nil }.map(\.weight).reduce(0, +)
        note.text = "每次 \(t.cost) 金币 · 套装部件概率约 \(Int((Double(sets) / Double(t.totalWeight) * 100).rounded()))%"
    }
    private func go() {
        guard !wheel.spinning, let slot = onSpin?(tier) else { return }
        spin.isEnabled = false; tiers.isEnabled = false; card.hide()
        wheel.spin(to: slot) { [weak self] in
            guard let self else { return }
            self.spin.isEnabled = true; self.tiers.isEnabled = true
            self.wheel.celebrate(slot)
            let slices = Self.slices(CampaignLottery.tiers[self.tier], catalog: self.catalog)
            if slices.indices.contains(slot) { self.card.show(slices[slot]) }
            self.onFinished?(self.tier, slot)
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        tiers.frame = CGRect(x: max(16, (w - 420) / 2), y: 14, width: min(420, w - 32), height: 40)
        let side = max(160, min(w - 20, h - 170))
        wheel.frame = CGRect(x: (w - side) / 2, y: 60, width: side, height: side)
        spin.frame = CGRect(x: w / 2 - 110, y: wheel.frame.maxY + 6, width: 220, height: 52)
        note.frame = CGRect(x: 16, y: spin.frame.maxY + 4, width: w - 32, height: 40)
        let cw = min(300, w - 40)
        card.frame = CGRect(x: (w - cw) / 2, y: wheel.frame.midY - 110, width: cw, height: 230)
    }
}
