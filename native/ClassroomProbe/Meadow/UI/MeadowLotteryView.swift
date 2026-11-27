import UIKit
import ClassroomGameCore

/// The shop's skeuomorphic prize wheel stage:
/// Left (~56%): 4-tier metallic picker (铜30 / 银80 / 金180 / 星穹280), large walnut-brass prize wheel, and spin CTA.
/// Right (~44%): Frosted prize-pool ledger grouped by rarity (传说 → 史诗 → 稀有 → 普通) with live percentages & win highlight,
/// eliminating dead whitespace on widescreen TV / iPad displays.
final class MeadowLotteryView: UIView {
    var onSpin: ((Int) -> Int?)?
    var onFinished: ((Int, Int) -> Void)?
    private(set) var tier = 0

    private let tiers = UISegmentedControl(items: CampaignLottery.tiers.map { "\($0.title)档 · \($0.cost)" })
    private let wheel = MeadowPrizeWheelView()
    private let card = WheelPrizeCard()
    private let spin = MeadowPreviewPalette.iconButton("sparkles", "抽一次", prominent: true)
    private let note = MeadowPreviewPalette.label("", size: 13.5, weight: .semibold)

    private let poolPanel = UIView()
    private let poolHeader = UILabel()
    private let setRateBadge = UILabel()
    private let oddsStrip = UIStackView()
    private let poolScroll = UIScrollView()
    private let poolContent = UIView()
    private var poolRows: [(slot: Int, view: UIView)] = []

    var catalog: GameCatalog? { didSet { selectTier() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for state in [UIControl.State.normal, .selected] {
            tiers.setTitleTextAttributes([
                .font: MeadowPreviewPalette.font(15, .heavy),
                .foregroundColor: state == .selected ? UIColor.white : MeadowPreviewPalette.ink,
            ], for: state)
        }
        tiers.selectedSegmentTintColor = MeadowPreviewPalette.primary
        tiers.selectedSegmentIndex = 0
        tiers.addAction(UIAction { [weak self] _ in self?.selectTier() }, for: .valueChanged)

        note.textAlignment = .center
        note.numberOfLines = 1
        note.textColor = MeadowPreviewPalette.muted

        spin.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
        wheel.onHubTap = { [weak self] in self?.go() }
        wheel.onWinFaded = { [weak self] in self?.card.hide() }

        MeadowPreviewPalette.stylePanel(poolPanel, liveBlur: false, level: .thick)
        poolHeader.font = MeadowPreviewPalette.font(18, .heavy)
        poolHeader.textColor = MeadowPreviewPalette.ink

        setRateBadge.font = MeadowPreviewPalette.font(12.5, .heavy)
        setRateBadge.textColor = .white
        setRateBadge.textAlignment = .center
        setRateBadge.backgroundColor = UIColor(red: 0.48, green: 0.24, blue: 0.80, alpha: 1)
        setRateBadge.layer.cornerRadius = 11
        setRateBadge.clipsToBounds = true

        oddsStrip.axis = .horizontal
        oddsStrip.spacing = 6
        oddsStrip.distribution = .fillEqually

        poolScroll.alwaysBounceVertical = true
        poolScroll.addSubview(poolContent)
        [poolHeader, setRateBadge, oddsStrip, poolScroll].forEach(poolPanel.addSubview)

        [tiers, wheel, spin, note, poolPanel, card].forEach(addSubview)
        selectTier()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func slices(_ tier: LotteryTier, catalog: GameCatalog?) -> [WheelSlice] {
        tier.prizes.map { p in
            if let id = p.item {
                let item = try? catalog?.item(id)
                let stat = item.map { MeadowItemRarity.shortStat($0) }
                let sub = [item?.setID != nil ? "套装部件" : nil, stat].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return WheelSlice(
                    title: item?.name ?? id,
                    icon: MeadowItemIcon.image(id, item: item, side: 96),
                    badge: p.count > 1 ? "×\(p.count)" : nil,
                    rarity: MeadowItemRarity.of(id, item: item),
                    weight: Double(p.weight),
                    subtitle: sub.isEmpty ? nil : sub
                )
            }
            return WheelSlice(
                title: "金币袋",
                icon: nil,
                badge: "+\(p.coins)",
                rarity: p.coins >= 120 ? .rare : .common,
                coins: true,
                weight: Double(p.weight),
                subtitle: "直接计入当前成员金币"
            )
        }
    }

    private func selectTier() {
        guard !wheel.spinning else { tiers.selectedSegmentIndex = tier; return }
        tier = max(0, tiers.selectedSegmentIndex)
        let t = CampaignLottery.tiers[tier]
        let list = Self.slices(t, catalog: catalog)
        wheel.slices = list
        card.hide()
        spin.configuration?.title = "抽一次 · \(t.cost) 金币"
        note.text = "点击中心「抽!」旋转 · 极窄扇面以品级徽标简略呈现，详见右侧奖池"
        rebuildPoolLedger(tier: t, slices: list)
        setNeedsLayout()
    }

    private func rebuildPoolLedger(tier t: LotteryTier, slices: [WheelSlice]) {
        poolContent.subviews.forEach { $0.removeFromSuperview() }
        poolRows = []
        oddsStrip.arrangedSubviews.forEach { oddsStrip.removeArrangedSubview($0); $0.removeFromSuperview() }

        let total = max(1, t.totalWeight)
        var rarityWeight: [MeadowItemRarity: Int] = [:]
        var setWeight = 0

        struct Entry {
            let slot: Int
            let prize: LotteryPrize
            let slice: WheelSlice
            let item: ItemDefinition?
            let pct: Double
        }

        var entries: [Entry] = []
        for (i, p) in t.prizes.enumerated() {
            let s = slices[i]
            let item = p.item.flatMap { try? catalog?.item($0) }
            rarityWeight[s.rarity, default: 0] += p.weight
            if item?.setID != nil { setWeight += p.weight }
            entries.append(Entry(slot: i, prize: p, slice: s, item: item, pct: Double(p.weight) / Double(total) * 100.0))
        }

        // Order pool highest rarity first, set pieces first within same rarity, then by chance.
        entries.sort { a, b in
            if a.slice.rarity != b.slice.rarity { return a.slice.rarity > b.slice.rarity }
            let aSet = a.item?.setID != nil, bSet = b.item?.setID != nil
            if aSet != bSet { return aSet }
            return a.pct > b.pct
        }

        poolHeader.attributedText = MeadowGlassText.iconLine("list.bullet.rectangle.portrait.fill", "\(t.title)档奖池 · \(t.prizes.count)项", size: 17, tint: MeadowPreviewPalette.gold, weight: .heavy)
        let setPct = Double(setWeight) / Double(total) * 100.0
        setRateBadge.text = String(format: "套装 %.1f%%", setPct)

        for r in [MeadowItemRarity.legendary, .epic, .rare, .common] {
            let pct = Double(rarityWeight[r] ?? 0) / Double(total) * 100.0
            let chip = UILabel()
            chip.font = MeadowPreviewPalette.font(11.5, .heavy)
            chip.textAlignment = .center
            chip.textColor = pct > 0 ? .white : MeadowPreviewPalette.muted
            chip.backgroundColor = pct > 0 ? r.badgeColor : UIColor.white.withAlphaComponent(0.45)
            chip.layer.cornerRadius = 8
            chip.clipsToBounds = true
            chip.text = String(format: "%@ %.0f%%", r.title, pct)
            oddsStrip.addArrangedSubview(chip)
        }

        for entry in entries {
            let row = UIView()
            row.backgroundColor = entry.slice.rarity.surfaceTint
            row.layer.cornerRadius = 11
            row.layer.cornerCurve = .continuous
            row.layer.borderWidth = 1.2
            row.layer.borderColor = entry.slice.rarity.borderColor.withAlphaComponent(0.75).cgColor
            row.clipsToBounds = true

            let bar = UIView(); bar.backgroundColor = entry.slice.rarity.badgeColor; bar.tag = 1
            let iconV = UIImageView(); iconV.contentMode = .scaleAspectFit; iconV.layer.magnificationFilter = .nearest; iconV.tag = 2
            if let img = entry.slice.icon {
                iconV.image = img
            } else {
                iconV.image = UIImage(systemName: "bitcoinsign.circle.fill")
                iconV.tintColor = MeadowPreviewPalette.gold
            }

            let titleL = UILabel()
            titleL.font = MeadowPreviewPalette.font(14, .heavy)
            titleL.textColor = entry.slice.rarity >= .epic ? entry.slice.rarity.inkColor : MeadowPreviewPalette.ink
            let suffix = entry.prize.item != nil ? (entry.prize.count > 1 ? " ×\(entry.prize.count)" : "") : " \(entry.prize.coins)"
            titleL.text = entry.slice.title + suffix
            titleL.lineBreakMode = .byTruncatingTail
            titleL.tag = 3

            let subL = UILabel()
            subL.font = MeadowPreviewPalette.font(11.5, .semibold)
            subL.textColor = MeadowPreviewPalette.muted
            subL.text = entry.slice.subtitle ?? (entry.prize.item == nil ? "金币奖励" : "")
            subL.lineBreakMode = .byTruncatingTail
            subL.tag = 4

            let tagL = UILabel()
            tagL.font = MeadowPreviewPalette.font(10.5, .heavy)
            tagL.textColor = .white
            tagL.textAlignment = .center
            tagL.layer.cornerRadius = 6
            tagL.clipsToBounds = true
            tagL.backgroundColor = entry.item?.setID != nil ? UIColor(red: 0.48, green: 0.24, blue: 0.80, alpha: 1) : entry.slice.rarity.badgeColor
            tagL.text = entry.item?.setID != nil ? "套装" : entry.slice.rarity.title
            tagL.tag = 5

            let pctL = UILabel()
            pctL.font = UIFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .heavy)
            pctL.textAlignment = .right
            pctL.textColor = entry.slice.rarity.inkColor
            pctL.text = String(format: "%.1f%%", entry.pct)
            pctL.tag = 6

            [bar, iconV, titleL, subL, tagL, pctL].forEach(row.addSubview)
            poolContent.addSubview(row)
            poolRows.append((entry.slot, row))
        }
    }

    private func highlightWonSlot(_ slot: Int) {
        for (s, row) in poolRows {
            let won = s == slot
            row.layer.borderWidth = won ? 2.6 : 1.2
            if won {
                row.layer.borderColor = MeadowPreviewPalette.gold.cgColor
                let targetY = max(0, min(poolScroll.contentSize.height - poolScroll.bounds.height, row.frame.midY - poolScroll.bounds.height / 2))
                poolScroll.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
                UIView.animate(withDuration: 0.18, animations: { row.transform = CGAffineTransform(scaleX: 1.02, y: 1.02) }) { _ in
                    UIView.animate(withDuration: 0.25) { row.transform = .identity }
                }
            }
        }
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
            self.highlightWonSlot(slot)
            self.onFinished?(self.tier, slot)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let wide = w >= 760
        if wide {
            let rightW = min(430, max(310, w * 0.41))
            let leftW = w - rightW - 14
            tiers.frame = CGRect(x: max(8, (leftW - 440) / 2), y: 8, width: min(440, leftW - 16), height: 38)
            let side = max(200, min(leftW - 12, h - 134))
            wheel.frame = CGRect(x: (leftW - side) / 2, y: 50, width: side, height: side)
            spin.frame = CGRect(x: (leftW - 240) / 2, y: wheel.frame.maxY + 6, width: 240, height: 48)
            note.frame = CGRect(x: 8, y: spin.frame.maxY + 4, width: leftW - 16, height: 22)

            poolPanel.isHidden = false
            poolPanel.frame = CGRect(x: leftW + 14, y: 6, width: rightW, height: h - 12)
            let pw = poolPanel.bounds.width
            poolHeader.frame = CGRect(x: 14, y: 12, width: pw - 118, height: 26)
            setRateBadge.frame = CGRect(x: pw - 100, y: 13, width: 86, height: 24)
            oddsStrip.frame = CGRect(x: 12, y: 44, width: pw - 24, height: 26)
            poolScroll.frame = CGRect(x: 10, y: 78, width: pw - 20, height: max(1, poolPanel.bounds.height - 88))
            layoutPoolRows()

            let cw = min(310, leftW - 32)
            card.frame = CGRect(x: (leftW - cw) / 2, y: wheel.frame.midY - 122, width: cw, height: 248)
        } else {
            poolPanel.isHidden = true
            tiers.frame = CGRect(x: max(12, (w - 420) / 2), y: 10, width: min(420, w - 24), height: 38)
            let side = max(180, min(w - 16, h - 144))
            wheel.frame = CGRect(x: (w - side) / 2, y: 54, width: side, height: side)
            spin.frame = CGRect(x: w / 2 - 120, y: wheel.frame.maxY + 6, width: 240, height: 48)
            note.frame = CGRect(x: 12, y: spin.frame.maxY + 4, width: w - 24, height: 24)
            let cw = min(300, w - 40)
            card.frame = CGRect(x: (w - cw) / 2, y: wheel.frame.midY - 120, width: cw, height: 244)
        }
    }

    private func layoutPoolRows() {
        let rw = poolScroll.bounds.width
        let rowH: CGFloat = 46, gap: CGFloat = 6
        for (idx, item) in poolRows.enumerated() {
            let row = item.view
            row.frame = CGRect(x: 0, y: CGFloat(idx) * (rowH + gap), width: rw, height: rowH)
            row.viewWithTag(1)?.frame = CGRect(x: 0, y: 0, width: 4.5, height: rowH)
            row.viewWithTag(2)?.frame = CGRect(x: 10, y: 6, width: 34, height: 34)
            row.viewWithTag(6)?.frame = CGRect(x: rw - 56, y: 13, width: 48, height: 20)
            row.viewWithTag(5)?.frame = CGRect(x: rw - 98, y: 14, width: 38, height: 18)
            let textW = max(40, rw - 156)
            row.viewWithTag(3)?.frame = CGRect(x: 50, y: 6, width: textW, height: 18)
            row.viewWithTag(4)?.frame = CGRect(x: 50, y: 25, width: textW, height: 15)
        }
        poolContent.frame = CGRect(x: 0, y: 0, width: rw, height: max(1, CGFloat(poolRows.count) * (rowH + gap)))
        poolScroll.contentSize = poolContent.bounds.size
    }
}
