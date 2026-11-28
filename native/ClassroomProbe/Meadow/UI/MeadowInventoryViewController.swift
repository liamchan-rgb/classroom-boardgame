import UIKit
import UniformTypeIdentifiers
import MeadowWorldSupport
import MeadowBattleSupport
import ClassroomGameCore

// MARK: - Shared High-Readability Equipment Detail UI (Inventory + Shop)

/// Shared builder for compact rarity headers, structured before→after comparison cards, and set bonus progress cards.
enum MeadowEquipmentDetailUI {
    /// Horizontal rarity-tinted identity header (saves ~100pt of wasted vertical space over the old centered giant icon).
    static func identityHeader(item: ItemDefinition, rarity: MeadowItemRarity, subtitle: String, catalog: GameCatalog, width: CGFloat) -> UIView {
        let card = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 92))
        card.backgroundColor = rarity.surfaceTint
        card.layer.cornerRadius = 15
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.6
        card.layer.borderColor = rarity.borderColor.cgColor
        card.clipsToBounds = true

        let bar = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 4.5))
        bar.backgroundColor = rarity.badgeColor
        card.addSubview(bar)

        let halo = UIView(frame: CGRect(x: 12, y: 15, width: 66, height: 66))
        halo.backgroundColor = rarity == .common ? UIColor.white.withAlphaComponent(0.80) : rarity.badgeColor.withAlphaComponent(0.14)
        halo.layer.cornerRadius = 14
        halo.layer.cornerCurve = .continuous
        halo.layer.borderWidth = 1.3
        halo.layer.borderColor = rarity.borderColor.withAlphaComponent(0.55).cgColor
        card.addSubview(halo)

        let icon = UIImageView(image: MeadowItemIcon.image(item.id, item: item, side: 64))
        icon.contentMode = .scaleAspectFit
        icon.layer.magnificationFilter = .nearest
        icon.frame = halo.bounds.insetBy(dx: 5, dy: 5)
        halo.addSubview(icon)

        let textX: CGFloat = 88
        let textW = max(60, width - textX - 12)

        // Row 1: Rarity pill + Slot/Kind pill + Set name pill
        var px = textX
        func addPill(_ text: String, bg: UIColor, fg: UIColor = .white) {
            let p = UILabel()
            p.text = text
            p.font = MeadowPreviewPalette.font(11, .heavy)
            p.textColor = fg
            p.textAlignment = .center
            p.backgroundColor = bg
            p.layer.cornerRadius = 6
            p.clipsToBounds = true
            let pw = min(textW - (px - textX), ceil(p.intrinsicContentSize.width) + 12)
            guard pw >= 22 else { return }
            p.frame = CGRect(x: px, y: 12, width: pw, height: 19)
            card.addSubview(p)
            px += pw + 5
        }
        addPill("\(rarity.title) \(rarity.stars)", bg: rarity.badgeColor)
        let kindText = item.slot.map { CampInventoryProjection.slotTitle($0) } ?? (item.kind == .revivalStone ? "复活" : "补给")
        addPill(kindText, bg: UIColor.white.withAlphaComponent(0.75), fg: MeadowPreviewPalette.ink)
        if let sid = item.setID, let setDef = catalog.sets.first(where: { $0.id == sid }) {
            addPill(setDef.name, bg: UIColor(red: 0.48, green: 0.24, blue: 0.80, alpha: 1))
        }

        let nameL = UILabel(frame: CGRect(x: textX, y: 34, width: textW, height: 28))
        nameL.text = item.name
        nameL.font = MeadowPreviewPalette.font(21, .heavy)
        nameL.textColor = rarity >= .epic ? rarity.inkColor : MeadowPreviewPalette.ink
        nameL.adjustsFontSizeToFitWidth = true
        nameL.minimumScaleFactor = 0.72
        card.addSubview(nameL)

        let subL = UILabel(frame: CGRect(x: textX, y: 63, width: textW, height: 19))
        subL.text = subtitle
        subL.font = MeadowPreviewPalette.font(13, .semibold)
        subL.textColor = MeadowPreviewPalette.muted
        subL.adjustsFontSizeToFitWidth = true
        subL.minimumScaleFactor = 0.78
        card.addSubview(subL)

        return card
    }

    /// Structured 2-column metric comparison box showing exact before → after deltas with vivid green/red uplift badges.
    static func comparisonCard(
        title: String,
        subtitle: String,
        comparison c: MeadowEquipmentComparison,
        catalog: GameCatalog,
        width: CGFloat
    ) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.68)
        box.layer.cornerRadius = 14
        box.layer.cornerCurve = .continuous
        box.layer.borderWidth = 1.2
        box.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor

        var y: CGFloat = 10
        let pad: CGFloat = 12
        let innerW = max(60, width - pad * 2)

        // Header + overall verdict badge
        let score = c.upgradeScore(catalog: catalog)
        let verdict = UILabel()
        verdict.font = MeadowPreviewPalette.font(11.5, .heavy)
        verdict.textColor = .white
        verdict.textAlignment = .center
        verdict.layer.cornerRadius = 8
        verdict.clipsToBounds = true
        if score > 0.25 {
            verdict.text = "▲ 综合提升"
            verdict.backgroundColor = UIColor(red: 0.11, green: 0.62, blue: 0.30, alpha: 1)
        } else if score < -0.25 {
            verdict.text = "▼ 综合下降"
            verdict.backgroundColor = UIColor(red: 0.80, green: 0.22, blue: 0.20, alpha: 1)
        } else {
            verdict.text = "≈ 属性平级"
            verdict.backgroundColor = UIColor(red: 0.44, green: 0.51, blue: 0.57, alpha: 1)
        }
        let vw = ceil(verdict.intrinsicContentSize.width) + 14
        verdict.frame = CGRect(x: width - pad - vw, y: y, width: vw, height: 22)
        box.addSubview(verdict)

        let titleL = UILabel(frame: CGRect(x: pad, y: y, width: max(40, innerW - vw - 6), height: 22))
        titleL.text = title
        titleL.font = MeadowPreviewPalette.font(15, .heavy)
        titleL.textColor = MeadowPreviewPalette.ink
        box.addSubview(titleL)
        y += 24

        let subL = UILabel(frame: CGRect(x: pad, y: y, width: innerW, height: 17))
        subL.text = subtitle
        subL.font = MeadowPreviewPalette.font(12, .semibold)
        subL.textColor = MeadowPreviewPalette.muted
        subL.lineBreakMode = .byTruncatingMiddle
        box.addSubview(subL)
        y += 22

        struct Metric {
            let label: String
            let valueText: String
            let deltaText: String
            let trend: Int // +1 better, -1 worse, 0 neutral
            let fullWidth: Bool
        }

        var metrics: [Metric] = []
        if c.attackBefore != c.attackAfter {
            let atkA = try? GameRules.attack(c.before, catalog: catalog)
            let atkB = try? GameRules.attack(c.after, catalog: catalog)
            let avgA = atkA.map { MeadowEquipmentComparison.expectedDamage($0.dice) } ?? 0
            let avgB = atkB.map { MeadowEquipmentComparison.expectedDamage($0.dice) } ?? 0
            let diff = avgB - avgA
            let trend = diff > 0.05 ? 1 : (diff < -0.05 ? -1 : ((atkB?.range ?? 0) > (atkA?.range ?? 0) ? 1 : ((atkB?.range ?? 0) < (atkA?.range ?? 0) ? -1 : 0)))
            let deltaStr: String
            if abs(diff) >= 0.1 {
                deltaStr = String(format: "%@%.1f均伤", diff > 0 ? "+" : "", diff)
            } else {
                let rd = (atkB?.range ?? 0) - (atkA?.range ?? 0)
                deltaStr = rd == 0 ? "调整" : (rd > 0 ? "射程+\(rd)" : "射程\(rd)")
            }
            metrics.append(Metric(label: "普攻", valueText: "\(c.attackBefore) → \(c.attackAfter)", deltaText: deltaStr, trend: trend, fullWidth: true))
        }

        func addInt(_ label: String, _ a: Int, _ b: Int, prefix: String = "") {
            guard a != b else { return }
            let d = b - a
            metrics.append(Metric(label: label, valueText: "\(prefix)\(a) → \(prefix)\(b)", deltaText: d > 0 ? "+\(d)" : "\(d)", trend: d > 0 ? 1 : -1, fullWidth: false))
        }
        addInt("生命上限", c.beforeStats.maximumHealth, c.afterStats.maximumHealth)
        addInt("额外伤害", c.beforeStats.damage, c.afterStats.damage, prefix: "+")
        addInt("基础行动", c.beforeStats.baseAP, c.afterStats.baseAP)
        addInt("行动上限", c.beforeStats.maximumAP, c.afterStats.maximumAP)
        let movA = Int(ceil(c.movementBefore)), movB = Int(ceil(c.movementAfter))
        addInt("地图移动", movA, movB)

        if metrics.isEmpty {
            let same = UILabel(frame: CGRect(x: pad, y: y, width: innerW, height: 28))
            same.text = "基础数值无变化"
            same.font = MeadowPreviewPalette.font(13.5, .semibold)
            same.textColor = MeadowPreviewPalette.muted
            same.textAlignment = .center
            same.backgroundColor = UIColor.white.withAlphaComponent(0.55)
            same.layer.cornerRadius = 8
            same.clipsToBounds = true
            box.addSubview(same)
            y += 34
        } else {
            let fullMetrics = metrics.filter(\.fullWidth)
            let halfMetrics = metrics.filter { !$0.fullWidth }
            for m in fullMetrics {
                let tile = metricTile(label: m.label, value: m.valueText, delta: m.deltaText, trend: m.trend, width: innerW)
                tile.frame.origin = CGPoint(x: pad, y: y)
                box.addSubview(tile)
                y += tile.frame.height + 6
            }
            let colGap: CGFloat = 7
            let colW = (innerW - colGap) / 2
            for (idx, m) in halfMetrics.enumerated() {
                let col = idx % 2
                let tile = metricTile(label: m.label, value: m.valueText, delta: m.deltaText, trend: m.trend, width: colW)
                tile.frame.origin = CGPoint(x: pad + CGFloat(col) * (colW + colGap), y: y)
                box.addSubview(tile)
                if col == 1 || idx == halfMetrics.count - 1 { y += tile.frame.height + 6 }
            }
        }

        // Skill unlock / loss pills
        let gained = c.skillsAfter.filter { !c.skillsBefore.contains($0) }
        let lost = c.skillsBefore.filter { !c.skillsAfter.contains($0) }
        for s in gained {
            let pill = skillDeltaBanner(text: "+ 解锁技能：\(s)", positive: true, width: innerW)
            pill.frame.origin = CGPoint(x: pad, y: y)
            box.addSubview(pill)
            y += pill.frame.height + 5
        }
        for s in lost {
            let pill = skillDeltaBanner(text: "− 失去技能：\(s)", positive: false, width: innerW)
            pill.frame.origin = CGPoint(x: pad, y: y)
            box.addSubview(pill)
            y += pill.frame.height + 5
        }

        box.frame = CGRect(x: 0, y: 0, width: width, height: y + 6)
        return box
    }

    private static func metricTile(label: String, value: String, delta: String, trend: Int, width: CGFloat) -> UIView {
        let upColor = UIColor(red: 0.08, green: 0.56, blue: 0.25, alpha: 1)
        let downColor = UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        let neutralColor = UIColor(red: 0.36, green: 0.44, blue: 0.50, alpha: 1)
        let accent = trend > 0 ? upColor : (trend < 0 ? downColor : neutralColor)

        let tile = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 46))
        tile.backgroundColor = trend > 0
            ? UIColor(red: 0.87, green: 0.97, blue: 0.90, alpha: 0.94)
            : (trend < 0 ? UIColor(red: 0.99, green: 0.90, blue: 0.90, alpha: 0.94) : UIColor(red: 0.94, green: 0.96, blue: 0.97, alpha: 0.9))
        tile.layer.cornerRadius = 10
        tile.layer.cornerCurve = .continuous
        tile.layer.borderWidth = 1.1
        tile.layer.borderColor = accent.withAlphaComponent(0.38).cgColor

        let nameL = UILabel(frame: CGRect(x: 9, y: 5, width: width - 74, height: 15))
        nameL.text = label
        nameL.font = MeadowPreviewPalette.font(11.5, .bold)
        nameL.textColor = MeadowPreviewPalette.muted
        tile.addSubview(nameL)

        let deltaPill = UILabel()
        deltaPill.text = (trend > 0 ? "▲ " : (trend < 0 ? "▼ " : "")) + delta
        deltaPill.font = MeadowPreviewPalette.font(11, .heavy)
        deltaPill.textColor = .white
        deltaPill.textAlignment = .center
        deltaPill.backgroundColor = accent
        deltaPill.layer.cornerRadius = 6
        deltaPill.clipsToBounds = true
        let dw = min(width * 0.52, max(36, ceil(deltaPill.intrinsicContentSize.width) + 10))
        deltaPill.frame = CGRect(x: width - dw - 7, y: 5, width: dw, height: 17)
        tile.addSubview(deltaPill)

        let valL = UILabel(frame: CGRect(x: 9, y: 23, width: width - 18, height: 19))
        valL.text = value
        valL.font = MeadowPreviewPalette.font(14, .heavy)
        valL.textColor = accent
        valL.adjustsFontSizeToFitWidth = true
        valL.minimumScaleFactor = 0.72
        tile.addSubview(valL)

        return tile
    }

    private static func skillDeltaBanner(text: String, positive: Bool, width: CGFloat) -> UIView {
        let l = UILabel()
        l.text = "  " + text
        l.font = MeadowPreviewPalette.font(13, .heavy)
        l.textColor = positive ? UIColor(red: 0.07, green: 0.48, blue: 0.22, alpha: 1) : UIColor(red: 0.74, green: 0.16, blue: 0.14, alpha: 1)
        l.backgroundColor = positive ? UIColor(red: 0.87, green: 0.97, blue: 0.90, alpha: 0.95) : UIColor(red: 0.99, green: 0.90, blue: 0.90, alpha: 0.95)
        l.layer.cornerRadius = 8
        l.layer.borderWidth = 1
        l.layer.borderColor = l.textColor.withAlphaComponent(0.35).cgColor
        l.clipsToBounds = true
        l.frame = CGRect(x: 0, y: 0, width: width, height: 28)
        return l
    }

    /// Set bonus progress card (e.g. "龙纹套装 · 1/3 → 2/3") showing 2-piece & 3-piece bonuses and unlocked set skill.
    static func setBonusCard(setID: String, beforeUnit: GameUnit, afterUnit: GameUnit, catalog: GameCatalog, width: CGFloat) -> UIView? {
        guard let setDef = catalog.sets.first(where: { $0.id == setID }) else { return nil }
        let setItems = Set(setDef.items)
        let beforeCount = beforeUnit.equipment.itemIDs.filter { setItems.contains($0) }.count
        let afterCount = afterUnit.equipment.itemIDs.filter { setItems.contains($0) }.count

        let card = UIView()
        card.backgroundColor = UIColor(red: 0.95, green: 0.91, blue: 1.00, alpha: 0.88)
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.3
        card.layer.borderColor = UIColor(red: 0.56, green: 0.30, blue: 0.88, alpha: 0.55).cgColor

        let pad: CGFloat = 12
        let innerW = max(60, width - pad * 2)
        var y: CGFloat = 10

        let countText = beforeCount == afterCount ? "\(afterCount)/3 件" : "\(beforeCount)/3 → \(afterCount)/3 件"
        let countBadge = UILabel()
        countBadge.text = countText
        countBadge.font = MeadowPreviewPalette.font(11.5, .heavy)
        countBadge.textColor = .white
        countBadge.textAlignment = .center
        countBadge.backgroundColor = afterCount > beforeCount
            ? UIColor(red: 0.11, green: 0.62, blue: 0.30, alpha: 1)
            : (afterCount < beforeCount ? UIColor(red: 0.78, green: 0.22, blue: 0.20, alpha: 1) : UIColor(red: 0.48, green: 0.24, blue: 0.80, alpha: 1))
        countBadge.layer.cornerRadius = 8
        countBadge.clipsToBounds = true
        let cw = ceil(countBadge.intrinsicContentSize.width) + 14
        countBadge.frame = CGRect(x: width - pad - cw, y: y, width: cw, height: 22)
        card.addSubview(countBadge)

        let titleL = UILabel(frame: CGRect(x: pad, y: y, width: max(40, innerW - cw - 6), height: 22))
        titleL.attributedText = MeadowGlassText.iconLine("seal.fill", setDef.name, size: 14.5, tint: UIColor(red: 0.46, green: 0.17, blue: 0.78, alpha: 1), weight: .heavy)
        card.addSubview(titleL)
        y += 26

        func attrText(_ a: Attributes) -> String {
            var p: [String] = []
            if a.maximumHealth != 0 { p.append("生命+\(a.maximumHealth)") }
            if a.damage != 0 { p.append("伤害+\(a.damage)") }
            if a.baseAP != 0 { p.append("基础行动+\(a.baseAP)") }
            if a.maximumAP != 0 { p.append("行动上限+\(a.maximumAP)") }
            if a.range != 0 { p.append("射程+\(a.range)") }
            return p.isEmpty ? "全属性强化" : p.joined(separator: " · ")
        }

        let twoActive = afterCount >= 2
        let twoL = UILabel(frame: CGRect(x: pad, y: y, width: innerW, height: 18))
        twoL.text = (twoActive ? "● " : "○ ") + "2件：" + attrText(setDef.twoPieces)
        twoL.font = MeadowPreviewPalette.font(12.5, twoActive ? .heavy : .semibold)
        twoL.textColor = twoActive ? UIColor(red: 0.08, green: 0.52, blue: 0.24, alpha: 1) : MeadowPreviewPalette.muted
        card.addSubview(twoL)
        y += 20

        let threeActive = afterCount >= 3
        let skillName = (try? catalog.skill(setDef.skill).name) ?? setDef.skill
        let threeL = UILabel()
        threeL.numberOfLines = 0
        threeL.text = (threeActive ? "● " : "○ ") + "3件：" + attrText(setDef.threePieces) + " · 套装技「\(skillName)」"
        threeL.font = MeadowPreviewPalette.font(12.5, threeActive ? .heavy : .semibold)
        threeL.textColor = threeActive ? UIColor(red: 0.46, green: 0.17, blue: 0.78, alpha: 1) : MeadowPreviewPalette.muted
        let th = max(18, ceil(threeL.sizeThatFits(CGSize(width: innerW, height: 200)).height))
        threeL.frame = CGRect(x: pad, y: y, width: innerW, height: th)
        card.addSubview(threeL)
        y += th + 10

        card.frame = CGRect(x: 0, y: 0, width: width, height: y)
        return card
    }
}

// MARK: - Equipped Slot Card (Left Column of Backpack)

private final class MeadowEquippedSlotCard: UIControl {
    private let bar = UIView()
    private let iconBox = UIView()
    private let iconView = UIImageView()
    private let slotPill = UILabel()
    private let rarityPill = UILabel()
    private let replacePill = UILabel()
    private let nameLabel = UILabel()
    private let statLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 13
        layer.cornerCurve = .continuous

        bar.isUserInteractionEnabled = false
        iconBox.layer.cornerRadius = 9
        iconBox.layer.cornerCurve = .continuous
        iconBox.isUserInteractionEnabled = false

        iconView.contentMode = .scaleAspectFit
        iconView.layer.magnificationFilter = .nearest
        iconView.isUserInteractionEnabled = false

        slotPill.font = MeadowPreviewPalette.font(10.5, .heavy)
        slotPill.textAlignment = .center
        slotPill.layer.cornerRadius = 5
        slotPill.clipsToBounds = true
        slotPill.isUserInteractionEnabled = false

        rarityPill.font = MeadowPreviewPalette.font(10, .heavy)
        rarityPill.textColor = .white
        rarityPill.textAlignment = .center
        rarityPill.layer.cornerRadius = 5
        rarityPill.clipsToBounds = true
        rarityPill.isUserInteractionEnabled = false

        replacePill.text = "将替换"
        replacePill.font = MeadowPreviewPalette.font(10, .heavy)
        replacePill.textColor = .white
        replacePill.textAlignment = .center
        replacePill.backgroundColor = UIColor(red: 0.88, green: 0.48, blue: 0.05, alpha: 1)
        replacePill.layer.cornerRadius = 6
        replacePill.clipsToBounds = true
        replacePill.isUserInteractionEnabled = false

        nameLabel.font = MeadowPreviewPalette.font(14.5, .heavy)
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.78
        nameLabel.isUserInteractionEnabled = false

        statLabel.font = MeadowPreviewPalette.font(11.5, .semibold)
        statLabel.textColor = MeadowPreviewPalette.muted
        statLabel.adjustsFontSizeToFitWidth = true
        statLabel.minimumScaleFactor = 0.78
        statLabel.isUserInteractionEnabled = false

        [bar, iconBox, iconView, slotPill, rarityPill, replacePill, nameLabel, statLabel].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(slot: ItemSlot, item: ItemDefinition?, willReplace: Bool) {
        let slotIcons: [ItemSlot: String] = [.weapon: "bolt.horizontal.fill", .armor: "shield.lefthalf.filled", .accessory: "sparkle"]
        slotPill.text = CampInventoryProjection.slotTitle(slot)
        slotPill.backgroundColor = UIColor.white.withAlphaComponent(0.75)
        slotPill.textColor = MeadowPreviewPalette.ink

        if let item {
            let r = MeadowItemRarity.of(item.id, item: item)
            backgroundColor = r.surfaceTint
            bar.backgroundColor = r.badgeColor
            iconBox.backgroundColor = r == .common ? UIColor.white.withAlphaComponent(0.75) : r.badgeColor.withAlphaComponent(0.15)
            iconView.image = MeadowItemIcon.image(item.id, item: item, side: 44)
            iconView.tintColor = nil
            rarityPill.text = r.title
            rarityPill.backgroundColor = r.badgeColor
            rarityPill.isHidden = false
            nameLabel.text = item.name
            nameLabel.textColor = r >= .epic ? r.inkColor : MeadowPreviewPalette.ink
            statLabel.text = MeadowItemRarity.shortStat(item)
            layer.borderColor = (willReplace ? UIColor(red: 0.90, green: 0.50, blue: 0.06, alpha: 1) : r.borderColor).cgColor
            layer.borderWidth = willReplace ? 2.4 : 1.3
            accessibilityLabel = "\(CampInventoryProjection.slotTitle(slot)) \(r.title) \(item.name)"
        } else {
            backgroundColor = MeadowPreviewPalette.glass(.thin)
            bar.backgroundColor = MeadowPreviewPalette.muted.withAlphaComponent(0.35)
            iconBox.backgroundColor = UIColor.white.withAlphaComponent(0.45)
            iconView.image = UIImage(systemName: slotIcons[slot] ?? "circle")
            iconView.tintColor = MeadowPreviewPalette.muted
            rarityPill.isHidden = true
            nameLabel.text = slot == .weapon ? "空手" : "未装备\(CampInventoryProjection.slotTitle(slot))"
            nameLabel.textColor = MeadowPreviewPalette.muted
            statLabel.text = "点击筛选\(CampInventoryProjection.slotTitle(slot))"
            layer.borderColor = (willReplace ? UIColor(red: 0.90, green: 0.50, blue: 0.06, alpha: 1) : UIColor.white.withAlphaComponent(0.7)).cgColor
            layer.borderWidth = willReplace ? 2.4 : 1.0
            accessibilityLabel = "\(CampInventoryProjection.slotTitle(slot)) 未装备"
        }
        replacePill.isHidden = !willReplace
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        bar.frame = CGRect(x: 0, y: 0, width: 4.5, height: h)
        let boxSide = min(40, h - 14)
        iconBox.frame = CGRect(x: 10, y: (h - boxSide) / 2, width: boxSide, height: boxSide)
        iconView.frame = iconBox.frame.insetBy(dx: 3, dy: 3)

        let tx = iconBox.frame.maxX + 8
        slotPill.frame = CGRect(x: tx, y: 6, width: 32, height: 16)
        rarityPill.frame = CGRect(x: slotPill.frame.maxX + 4, y: 6, width: 30, height: 16)
        if !replacePill.isHidden {
            replacePill.frame = CGRect(x: w - 48, y: 6, width: 42, height: 16)
        }
        nameLabel.frame = CGRect(x: tx, y: 23, width: max(40, w - tx - 8), height: 18)
        statLabel.frame = CGRect(x: tx, y: 40, width: max(40, w - tx - 8), height: 14)
    }
}

// MARK: - Standalone Camp Inventory (Training Mode)

/// UIKit inventory. The camp model is the single source of counts and actions.
final class MeadowInventoryViewController:UIViewController,UIDocumentPickerDelegate {
    let session:CampInventorySession
    var performEquip:((ItemSlot,String?)throws->Void)?
    var performAppearance:((String)throws->Void)?
    var performImport:((Data)throws->Void)?
    var onChange:(()->Void)?
    var onClose:(()->Void)?
    var startupIssue:String?
    private let header=UIView(),left=UIScrollView(),middle=UIView(),right=UIView()
    private let titleLabel=MeadowPreviewPalette.label("行囊与装备",size:24,weight:.heavy)
    private let saveLabel=MeadowPreviewPalette.label("",size:14)
    private let close=MeadowPreviewPalette.button("返回林地")
    private let exportButton=MeadowPreviewPalette.button("导出")
    private let importButton=MeadowPreviewPalette.button("导入")
    private let footer=MeadowPreviewPalette.label("林地演练使用独立补给，不扣除营地背包。",size:14)
    private let hero=UIImageView(),walk=MeadowPreviewPalette.button("查看步态")
    private let clothes=UISegmentedControl(items:HeroFrames.appearanceTitles)
    private let slots=ItemSlot.allCases.map { _ in MeadowEquippedSlotCard() }
    private let vitals=MeadowBattleResourceBar()
    private let filterButton=MeadowPreviewPalette.button("全部物品 ▾")
    private let list=UIScrollView(),empty=MeadowPreviewPalette.label("背包里暂时没有这类物品",size:17)
    private let detailScroll=UIScrollView(),detailContent=UIView()
    private let primary=MeadowPreviewPalette.button("装备")
    private let actions=MeadowBattleActionPointsView()
    private let statsLabel=MeadowPreviewPalette.label("",size:15,weight:.bold)
    private var filter="all",selected:String?,target="p1",walking=false
    private var rows:[UIButton]=[]
    private let filters=[("all","全部物品"),("weapon","武器"),("armor","护甲"),("accessory","饰品"),("supplies","道具")]
    init(session:CampInventorySession) { self.session=session;super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen;isModalInPresentation=true }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden:Bool { true }
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask { .landscape }
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor=UIColor(red:0.80,green:0.88,blue:0.88,alpha:1);MeadowGlassBackdrop.install(in:view)
        [header,left,middle,right].forEach { MeadowPreviewPalette.stylePanel($0,liveBlur:true);view.addSubview($0) }
        [titleLabel,saveLabel,close,exportButton,importButton].forEach(header.addSubview)
        view.addSubview(footer);right.addSubview(detailScroll);detailScroll.addSubview(detailContent);right.addSubview(primary)
        primary.addAction(UIAction { [weak self] _ in self?.activateSelected() },for:.touchUpInside)
        close.addAction(UIAction { [weak self] _ in guard let self else{return};self.hero.stopAnimating();self.dismiss(animated:true) { self.onClose?() } },for:.touchUpInside)
        exportButton.addAction(UIAction { [weak self] _ in self?.exportSave() },for:.touchUpInside)
        importButton.addAction(UIAction { [weak self] _ in self?.openImport() },for:.touchUpInside)
        hero.contentMode = .scaleAspectFit;hero.layer.magnificationFilter = .nearest;hero.layer.minificationFilter = .nearest;hero.isAccessibilityElement=true;hero.accessibilityLabel="P1当前衣装与装备预览"
        [hero,walk,clothes,vitals,actions,statsLabel].forEach(left.addSubview)
        walk.addAction(UIAction { [weak self] _ in guard let self else{return};self.walking.toggle();self.refreshHero() },for:.touchUpInside)
        clothes.addTarget(self,action:#selector(changeClothes),for:.valueChanged)
        clothes.setTitleTextAttributes([.font:MeadowPreviewPalette.font(15,.semibold),.foregroundColor:MeadowPreviewPalette.ink],for:.normal)
        clothes.setTitleTextAttributes([.font:MeadowPreviewPalette.font(15,.bold),.foregroundColor:UIColor.white],for:.selected)
        clothes.selectedSegmentTintColor=MeadowPreviewPalette.primary
        for (index,slotView) in slots.enumerated() {
            left.addSubview(slotView)
            slotView.addAction(UIAction { [weak self] _ in self?.selectSlot(ItemSlot.allCases[index]) },for:.touchUpInside)
        }
        middle.addSubview(filterButton);middle.addSubview(list);list.addSubview(empty)
        filterButton.showsMenuAsPrimaryAction=true;list.alwaysBounceVertical=true;left.alwaysBounceVertical=true;detailScroll.alwaysBounceVertical=true
        for scroll in [left,list,detailScroll] { scroll.indicatorStyle = .black }
        refresh()
    }
    func refresh() {
        let unit=session.loadout.units["p1"]!,catalog=session.loadout.engine.catalog
        let entries=CampInventoryProjection.entries(unit,catalog:catalog,filter:filter).sorted { a,b in
            if a.equipped != b.equipped { return a.equipped }
            let ra=MeadowItemRarity.of(a.id,item:try? catalog.item(a.id)),rb=MeadowItemRarity.of(b.id,item:try? catalog.item(b.id))
            if ra != rb { return ra > rb }
            return a.name < b.name
        }
        if !entries.contains(where:{$0.id==selected}) { selected=entries.first?.id }
        for row in rows { row.removeFromSuperview() };rows=[]
        for entry in entries {
            let item=try? catalog.item(entry.id),rarity=MeadowItemRarity.of(entry.id,item:item)
            let chosen=entry.id==selected
            let row=UIButton(type:.system)
            row.backgroundColor=chosen ? rarity.surfaceTint.withAlphaComponent(0.98):rarity.surfaceTint
            row.layer.cornerRadius=12;row.layer.cornerCurve = .continuous
            row.layer.borderWidth=chosen ? 2.4:(entry.equipped ? 1.8:1.2)
            row.layer.borderColor=(chosen ? MeadowPreviewPalette.primary:(entry.equipped ? MeadowPreviewPalette.gold:rarity.borderColor)).cgColor
            row.clipsToBounds=true
            let bar=UIView();bar.backgroundColor=rarity.badgeColor;bar.tag=10
            let icon=UIImageView(image:inventoryIcon(entry.id));icon.contentMode = .scaleAspectFit;icon.layer.magnificationFilter = .nearest;icon.tag=1
            let pill=UILabel();pill.text=rarity.title;pill.font=MeadowPreviewPalette.font(10.5,.heavy);pill.textColor = .white;pill.textAlignment = .center;pill.backgroundColor=rarity.badgeColor;pill.layer.cornerRadius=5;pill.clipsToBounds=true;pill.tag=4
            let name=MeadowPreviewPalette.label(entry.name,size:16.5,weight:.heavy);name.textColor=rarity >= .epic ? rarity.inkColor:MeadowPreviewPalette.ink;name.numberOfLines=1;name.tag=2
            let statText=item.map{MeadowItemRarity.shortStat($0)} ?? ""
            let amount=MeadowPreviewPalette.label((entry.equipped ? "已装备 · ":"")+"×\(entry.quantity)"+(statText.isEmpty ? "":" · "+statText),size:13,weight:.semibold);amount.textColor=MeadowPreviewPalette.muted;amount.tag=3
            [bar,icon,pill,name,amount].forEach { $0.isUserInteractionEnabled=false;row.addSubview($0) }
            row.accessibilityLabel="\(rarity.title) \(entry.name)，背包\(entry.quantity)"+(entry.equipped ? "，已装备":"")
            row.accessibilityIdentifier="inventoryItem-"+entry.id
            row.addAction(UIAction { [weak self] _ in self?.selected=entry.id;self?.refresh() },for:.touchUpInside)
            list.addSubview(row);rows.append(row)
        }
        empty.isHidden = !entries.isEmpty
        let selectedSlot=(selected.flatMap{try? catalog.item($0)}?.slot)
        for (i,slot) in ItemSlot.allCases.enumerated() {
            let item=unit.equipment[slot].flatMap{try? catalog.item($0)}
            let replacing = selectedSlot == slot && selected != unit.equipment[slot]
            slots[i].configure(slot:slot,item:item,willReplace:replacing)
        }
        clothes.selectedSegmentIndex=HeroFrames.appearanceIDs.firstIndex(of:session.appearanceID) ?? 0
        let stats=try? GameRules.attributes(unit,catalog:catalog)
        vitals.show("生命",value:unit.health,maximum:stats?.maximumHealth ?? 12,color:.systemGreen)
        actions.show(value:unit.ap,maximum:stats?.maximumAP ?? 8)
        statsLabel.text="额外伤害＋\(stats?.damage ?? 0) · 金币 \(unit.coins)"
        filterButton.configuration?.title=(filters.first{$0.0==filter}?.1 ?? "全部物品")+" ▾"
        filterButton.menu=UIMenu(children:filters.map { id,title in UIAction(title:title,state:id==filter ? .on:.off) { [weak self] _ in self?.filter=id;self?.selected=nil;self?.list.setContentOffset(.zero,animated:false);self?.refresh() } })
        if session.loadIssue != nil || startupIssue != nil { saveLabel.text="保存未启用 · 当前临时试装";saveLabel.textColor = .systemOrange }
        else if let saved=session.lastSaved { let f=DateFormatter();f.dateFormat="HH:mm:ss";saveLabel.text="P1 · 营地 · 已保存 "+f.string(from:saved);saveLabel.textColor=MeadowPreviewPalette.ink }
        else { saveLabel.text="P1 · 营地 · 临时配置" }
        refreshHero();view.setNeedsLayout()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();let s=view.safeAreaInsets
        let layout=CampInventoryLayout(width:Double(view.bounds.width),height:Double(view.bounds.height),left:Double(s.left),right:Double(s.right),top:Double(s.top),bottom:Double(s.bottom))
        header.frame=rect(layout.header);left.frame=rect(layout.equipment);middle.frame=rect(layout.bag);right.frame=rect(layout.detail);footer.frame=rect(layout.footer)
        let w=header.bounds.width;titleLabel.frame=CGRect(x:12,y:2,width:max(1,w-284),height:29);saveLabel.frame=CGRect(x:12,y:31,width:max(1,w-284),height:22)
        close.frame=CGRect(x:w-118,y:9,width:108,height:38);exportButton.frame=CGRect(x:w-184,y:9,width:60,height:38);importButton.frame=CGRect(x:w-250,y:9,width:60,height:38)
        let lw=left.bounds.width,heroHeight=min(220,max(128,left.bounds.height*0.28)),shift=heroHeight-128
        hero.frame=CGRect(x:12,y:8,width:lw-24,height:heroHeight)
        walk.frame=CGRect(x:12,y:140+shift,width:lw-24,height:34);clothes.frame=CGRect(x:12,y:180+shift,width:lw-24,height:32)
        vitals.frame=CGRect(x:12,y:218+shift,width:lw-24,height:40)
        actions.frame=CGRect(x:12,y:264+shift,width:lw-24,height:40);statsLabel.frame=CGRect(x:12,y:310+shift,width:lw-24,height:24)
        for (i,slotView) in slots.enumerated() { slotView.frame=CGRect(x:10,y:340+shift+CGFloat(i)*64,width:lw-20,height:58) }
        left.contentSize=CGSize(width:lw,height:540+shift)
        filterButton.frame=CGRect(x:10,y:9,width:middle.bounds.width-20,height:36)
        list.frame=CGRect(x:8,y:52,width:middle.bounds.width-16,height:max(1,middle.bounds.height-60))
        for (i,row) in rows.enumerated() {
            row.frame=CGRect(x:0,y:CGFloat(i)*72,width:list.bounds.width,height:64)
            row.viewWithTag(10)?.frame=CGRect(x:0,y:0,width:4.5,height:64)
            row.viewWithTag(1)?.frame=CGRect(x:10,y:10,width:44,height:44)
            row.viewWithTag(4)?.frame=CGRect(x:60,y:9,width:32,height:17)
            row.viewWithTag(2)?.frame=CGRect(x:96,y:7,width:max(40,row.bounds.width-104),height:22)
            row.viewWithTag(3)?.frame=CGRect(x:60,y:34,width:max(40,row.bounds.width-68),height:20)
        }
        list.contentSize=CGSize(width:list.bounds.width,height:CGFloat(rows.count)*72);empty.frame=CGRect(x:8,y:12,width:list.bounds.width-16,height:70);empty.numberOfLines=3
        detailScroll.frame=CGRect(x:0,y:0,width:right.bounds.width,height:max(1,right.bounds.height-66))
        primary.frame=CGRect(x:12,y:max(0,right.bounds.height-54),width:right.bounds.width-24,height:44)
        layoutDetail()
    }
    private func layoutDetail() {
        detailContent.subviews.forEach { $0.removeFromSuperview() }
        let w=right.bounds.width,catalog=session.loadout.engine.catalog;var y:CGFloat=12
        func text(_ value:String,_ size:CGFloat=15.5,_ weight:UIFont.Weight = .medium,_ color:UIColor=MeadowPreviewPalette.ink) {
            let l=MeadowPreviewPalette.label(value,size:size,weight:weight);l.numberOfLines=0;l.textColor=color
            let h=ceil(l.sizeThatFits(CGSize(width:w-24,height:10000)).height);l.frame=CGRect(x:12,y:y,width:w-24,height:max(22,h));detailContent.addSubview(l);y+=max(22,h)+8
        }
        func button(_ title:String,_ enabled:Bool=true,_ action:@escaping ()->Void) {
            let b=MeadowPreviewPalette.button(title);b.isEnabled=enabled;b.alpha=enabled ? 1:0.45;b.frame=CGRect(x:12,y:y,width:w-24,height:40)
            b.addAction(UIAction { _ in action() },for:.touchUpInside);detailContent.addSubview(b);y+=48
        }
        if let issue=session.loadIssue ?? startupIssue {
            text(issue,15,.semibold,.systemOrange)
            if session.savingBlocked { button("保留旧档并启用保存") { [weak self] in self?.attempt { try self?.session.preserveOldAndEnableSaving() } } }
        }
        if let selected,let item=try? catalog.item(selected),let d=try? CampInventoryProjection.detail(selected,session:session,target:target) {
            let rarity=MeadowItemRarity.of(selected,item:item)
            let hdr=MeadowEquipmentDetailUI.identityHeader(item:item,rarity:rarity,subtitle:"背包 ×\(d.quantity)"+(d.equipped ? " · 当前装备":""),catalog:catalog,width:w-24)
            hdr.frame.origin=CGPoint(x:12,y:y);detailContent.addSubview(hdr);y+=hdr.frame.height+10
            if !d.summary.isEmpty { text(d.summary,15,.bold,MeadowPreviewPalette.gold) }
            text(d.category=="supplies" ? "使用效果":"换装对比",16,.heavy)
            if d.category=="supplies" {
                let targets=UISegmentedControl(items:["P1","P2"]);targets.selectedSegmentIndex=target=="p1" ? 0:1
                for state in [UIControl.State.normal,.selected] { targets.setTitleTextAttributes([.font:MeadowPreviewPalette.font(15,.bold),.foregroundColor:state == .selected ? UIColor.white:MeadowPreviewPalette.ink],for:state) }
                targets.selectedSegmentTintColor=MeadowPreviewPalette.primary
                targets.addAction(UIAction { [weak self,weak targets] _ in self?.target=targets?.selectedSegmentIndex==1 ? "p2":"p1";self?.view.setNeedsLayout() },for:.valueChanged)
                targets.frame=CGRect(x:12,y:y,width:w-24,height:34);detailContent.addSubview(targets);y+=42
            }
            for line in d.comparison { text(line,15,.semibold) }
            if !d.reason.isEmpty { text(d.reason,14.5,.semibold,.systemOrange) }
            primary.configuration?.title=d.actionTitle;primary.isEnabled=d.enabled;primary.alpha=d.enabled ? 1:0.45;primary.isHidden=false
        } else { text("选择物品查看详情与换装对比。",16,.semibold,MeadowPreviewPalette.muted);primary.isHidden=true }
        button("立即保存",!session.savingBlocked && startupIssue==nil) { [weak self] in self?.attempt { try self?.session.saveNow() } }
        detailContent.frame=CGRect(x:0,y:0,width:w,height:y+8);detailScroll.contentSize=detailContent.bounds.size
    }
    private func refreshHero() {
        let unit=session.loadout.units["p1"]!,index=HeroFrames.appearanceIDs.firstIndex(of:session.appearanceID) ?? 0
        let images=HeroFrames.inventoryImages(appearanceIndex:index,weaponID:unit.equipment.weapon,armorID:unit.equipment.armor)
        hero.stopAnimating();hero.image=images.first
        if walking,images.count>1 { hero.animationImages=Array(images.dropFirst());hero.animationDuration=Double(images.count-1)*0.12;hero.animationRepeatCount=0;hero.startAnimating() }
        else { hero.animationImages=nil }
        walk.configuration?.title=walking ? "查看站姿":"查看步态"
    }
    private func selectSlot(_ slot:ItemSlot) { filter=slot.rawValue;selected=session.loadout.units["p1"]?.equipment[slot];list.setContentOffset(.zero,animated:false);refresh() }
    @objc private func changeClothes() {
        guard HeroFrames.appearanceIDs.indices.contains(clothes.selectedSegmentIndex) else{return}
        let id=HeroFrames.appearanceIDs[clothes.selectedSegmentIndex];attempt { try performAppearance?(id) }
    }
    private func activateSelected() {
        guard let selected,let item=try? session.loadout.engine.catalog.item(selected) else{return}
        attempt {
            if let slot=item.slot { let equipped=session.loadout.units["p1"]?.equipment[slot]==selected;try performEquip?(slot,equipped ? nil:selected) }
            else { try session.use(item:selected,target:target) }
        }
    }
    private func attempt(_ operation:()throws->Void) {
        do { try operation();onChange?();refresh() }
        catch { refresh();let a=UIAlertController(title:"操作未完成",message:error.localizedDescription,preferredStyle:.alert);a.addAction(UIAlertAction(title:"知道了",style:.default));present(a,animated:true) }
    }
    private func exportSave() {
        do {
            let u=FileManager.default.temporaryDirectory.appendingPathComponent("Meadow-Camp-"+UUID().uuidString+".json");try session.exportData().write(to:u,options:.atomic)
            let sheet=UIActivityViewController(activityItems:[u],applicationActivities:nil);sheet.popoverPresentationController?.sourceView=exportButton;sheet.popoverPresentationController?.sourceRect=exportButton.bounds;present(sheet,animated:true)
        } catch { attempt { throw error } }
    }
    private func openImport() {
        let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.json],asCopy:true);picker.delegate=self;picker.allowsMultipleSelection=false;present(picker,animated:true)
    }
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
        guard let url=urls.first else{return};let scoped=url.startAccessingSecurityScopedResource();defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data=try Data(contentsOf:url);let save=try session.inspectImport(data),unit=save.archive.state.units["p1"]!
            let names=try unit.equipment.itemIDs.map { try save.archive.catalog.item($0).name }
            let a=UIAlertController(title:"载入营地配置？",message:"P1："+names.joined(separator:"、")+"\n当前配置会另存一份后再载入。",preferredStyle:.alert)
            a.addAction(UIAlertAction(title:"取消",style:.cancel));a.addAction(UIAlertAction(title:"载入",style:.default) { [weak self] _ in self?.attempt { try self?.performImport?(data) } });present(a,animated:true)
        } catch { attempt { throw error } }
    }
    private func rect(_ r:InventoryRect)->CGRect { CGRect(x:r.x,y:r.y,width:r.width,height:r.height) }
    private func inventoryIcon(_ id:String)->UIImage? { MeadowItemIcon.image(id) }
}

// MARK: - Live Campaign Backpack (Mirrored to Public Screen)

/// Uses the expedition's live engine; redesigned for classroom TV projection with:
/// - Live hero try-on preview + 2×2 baseline stat chips + rarity-coded equipped slots with "将替换" indicator;
/// - Auto-sorted high-contrast rarity item cards (with "▲ 提升" upgrade tags & live category counts);
/// - Compact horizontal identity header + structured 2-column before→after stat delta cards + set-bonus progress card.
final class MeadowCampaignInventoryViewController:UIViewController {
    override var canBecomeFirstResponder:Bool {true}
    override func viewDidAppear(_ animated:Bool) {super.viewDidAppear(animated);becomeFirstResponder()}
    override func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        if ClassroomGlobalTools.handlePresses?(presses)==true {return}
        super.pressesBegan(presses,with:event)
    }
    let session:MeadowCampaignSession
    var performEquip:((String,ItemSlot,String?)throws->Void)?
    var onChange:(()->Void)?,onClose:(()->Void)?
    var onActorChanged:((String)->Void)?
    private var actor:String,target:String,selected:String?,filter="all"

    private let header=UIView(),left=UIScrollView(),middle=UIView(),right=UIView()
    private let titleLabel=UILabel(),saveLabel=MeadowPreviewPalette.label("",size:14,weight:.bold)
    private let members=UISegmentedControl()
    private let close=MeadowPreviewPalette.iconButton("xmark")
    private let refillActions=MeadowPreviewPalette.iconButton("bolt.fill","整备")
    private let timerButton=ClassroomGlobalTools.timerButton()

    // Left column (Hero try-on pedestal + vitals + 2×2 stat chips + 3 equipped slot cards)
    private let heroPedestal=UIView(),hero=UIImageView(),tryOnBadge=UILabel(),classBadge=UILabel()
    /// The background bake for the piece being tried on (waits until the choice rests; a new pick cancels it).
    private var prebake:DispatchWorkItem?
    private let health=MeadowBattleResourceBar(),ap=MeadowBattleActionPointsView()
    private let statChips=[UILabel(),UILabel(),UILabel(),UILabel()]
    private let slots=ItemSlot.allCases.map{_ in MeadowEquippedSlotCard()}

    // Middle column (Category tabs with counts + rarity card grid)
    private let filterBar=UISegmentedControl(),list=UIScrollView()
    private var rows:[UIView]=[]

    // Right column (Compact detail + structured comparison + set bonus + gifts + primary CTA)
    private let detail=UIScrollView(),detailContent=UIView()
    private let primary=MeadowPreviewPalette.button("装备")

    private let filters:[(String,String)]=[("all","全部"),("weapon","武器"),("armor","护甲"),("accessory","饰品"),("supplies","补给")]

    init(session:MeadowCampaignSession,actor:String) {
        self.session=session;self.actor=session.playerIDs.contains(actor) ? actor:"p1";target=self.actor
        super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen;isModalInPresentation=true
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var prefersStatusBarHidden:Bool{true}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.landscape}

    override func viewDidLoad(){
        super.viewDidLoad()
        view.backgroundColor=UIColor(red:0.80,green:0.88,blue:0.88,alpha:1);MeadowGlassBackdrop.install(in:view)
        [header,left,middle,right].forEach{MeadowPreviewPalette.stylePanel($0,liveBlur:true);view.addSubview($0)}
        titleLabel.attributedText=MeadowGlassText.iconLine("bag.fill","行囊",size:23,tint:MeadowPreviewPalette.gold,weight:.heavy)
        saveLabel.textColor=MeadowPreviewPalette.gold;saveLabel.alpha=0
        [titleLabel,saveLabel,members,refillActions,close,timerButton].forEach(header.addSubview)

        // Hero try-on pedestal
        heroPedestal.backgroundColor=UIColor.white.withAlphaComponent(0.55)
        heroPedestal.layer.cornerRadius=16;heroPedestal.layer.cornerCurve = .continuous
        heroPedestal.layer.borderWidth=1.2;heroPedestal.layer.borderColor=UIColor.white.withAlphaComponent(0.85).cgColor
        hero.contentMode = .scaleAspectFit;hero.layer.magnificationFilter = .nearest;hero.layer.minificationFilter = .nearest
        heroPedestal.addSubview(hero)

        tryOnBadge.text="试穿预览"
        tryOnBadge.font=MeadowPreviewPalette.font(11,.heavy);tryOnBadge.textColor = .white;tryOnBadge.textAlignment = .center
        tryOnBadge.backgroundColor=UIColor(red:0.88,green:0.48,blue:0.06,alpha:1)
        tryOnBadge.layer.cornerRadius=8;tryOnBadge.clipsToBounds=true;tryOnBadge.isHidden=true
        heroPedestal.addSubview(tryOnBadge)

        classBadge.font=MeadowPreviewPalette.font(11.5,.heavy);classBadge.textColor = .white;classBadge.textAlignment = .center
        classBadge.backgroundColor=MeadowPreviewPalette.primary
        classBadge.layer.cornerRadius=8;classBadge.clipsToBounds=true
        heroPedestal.addSubview(classBadge)

        [heroPedestal,health,ap].forEach(left.addSubview)
        for chip in statChips {
            chip.font=MeadowPreviewPalette.font(12.5,.heavy)
            chip.textAlignment = .center
            chip.backgroundColor=UIColor.white.withAlphaComponent(0.62)
            chip.layer.cornerRadius=9;chip.layer.cornerCurve = .continuous
            chip.layer.borderWidth=1;chip.layer.borderColor=UIColor.white.withAlphaComponent(0.85).cgColor
            chip.clipsToBounds=true
            chip.adjustsFontSizeToFitWidth=true;chip.minimumScaleFactor=0.75
            left.addSubview(chip)
        }
        left.alwaysBounceVertical=false

        refillActions.accessibilityIdentifier="campaignRefillInventoryActions";refillActions.accessibilityLabel="手动补足各成员基础行动"
        refillActions.addAction(UIAction{[weak self] _ in
            guard let self else{return}
            do{try self.session.refillInventoryActions();self.flash("行动已补足");self.onChange?();self.refresh()}
            catch{self.refresh();let alert=UIAlertController(title:"整备未完成",message:error.localizedDescription,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"好",style:.default));self.present(alert,animated:true)}
        },for:.touchUpInside)

        list.alwaysBounceVertical=true;detail.alwaysBounceVertical=true
        middle.addSubview(filterBar);middle.addSubview(list)
        right.addSubview(detail);detail.addSubview(detailContent);right.addSubview(primary)
        close.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true){self?.onClose?()}},for:.touchUpInside)

        for (i,id) in session.playerIDs.enumerated(){members.insertSegment(withTitle:session.engine.state.units[id]?.shortName ?? id.uppercased(),at:i,animated:false)}
        for control in [members,filterBar] {
            control.setTitleTextAttributes([.font:MeadowPreviewPalette.font(14.5,.bold),.foregroundColor:MeadowPreviewPalette.ink],for:.normal)
            control.setTitleTextAttributes([.font:MeadowPreviewPalette.font(14.5,.heavy),.foregroundColor:UIColor.white],for:.selected)
            control.selectedSegmentTintColor=MeadowPreviewPalette.primary
        }
        members.addAction(UIAction{[weak self] _ in
            guard let self else{return}
            self.actor=self.session.playerIDs[max(0,self.members.selectedSegmentIndex)]
            self.target=self.actor;self.selected=nil;self.filter="all"
            self.onActorChanged?(self.actor);self.refresh()
        },for:.valueChanged)

        for (i,(_,title)) in filters.enumerated(){filterBar.insertSegment(withTitle:title,at:i,animated:false)}
        filterBar.selectedSegmentIndex=0
        filterBar.addAction(UIAction{[weak self] _ in
            guard let self else{return}
            self.filter=self.filters[max(0,self.filterBar.selectedSegmentIndex)].0
            self.selected=nil;self.refresh()
        },for:.valueChanged)

        for (i,slot) in ItemSlot.allCases.enumerated(){
            left.addSubview(slots[i])
            slots[i].addAction(UIAction{[weak self] _ in
                guard let self else{return}
                self.filter=slot.rawValue
                self.selected=self.session.engine.state.units[self.actor]?.equipment[slot]
                self.refresh()
            },for:.touchUpInside)
        }
        primary.addAction(UIAction{[weak self] _ in self?.activate()},for:.touchUpInside)
        refresh()
    }

    private func flash(_ text:String){
        saveLabel.text=text;saveLabel.alpha=1
        UIView.animate(withDuration:0.4,delay:1.8,options:[]){self.saveLabel.alpha=0}
    }

    private func categoryRank(_ c:String)->Int { ["weapon":0,"armor":1,"accessory":2,"supplies":3][c] ?? 4 }

    private func refresh(){
        guard let unit=session.engine.state.units[actor] else{return}
        let catalog=session.engine.catalog

        // Update filter segment labels with live item counts.
        let allEntries=CampInventoryProjection.entries(unit,catalog:catalog,filter:"all")
        for (i,(code,title)) in filters.enumerated() {
            let count = code == "all" ? allEntries.count : allEntries.filter{$0.category==code}.count
            filterBar.setTitle(count > 0 ? "\(title)(\(count))" : title, forSegmentAt: i)
        }

        // Smart sort: Equipped first → Rarity descending → Slot order → Name
        var entries=CampInventoryProjection.entries(unit,catalog:catalog,filter:filter)
        entries.sort { a,b in
            if a.equipped != b.equipped { return a.equipped }
            let ia=try? catalog.item(a.id),ib=try? catalog.item(b.id)
            let ra=MeadowItemRarity.of(a.id,item:ia),rb=MeadowItemRarity.of(b.id,item:ib)
            if ra != rb { return ra > rb }
            let ca=categoryRank(a.category),cb=categoryRank(b.category)
            if ca != cb { return ca < cb }
            return a.name < b.name
        }
        if !entries.contains(where:{$0.id==selected}){selected=entries.first?.id}

        rows.forEach{$0.removeFromSuperview()};rows=[]
        for e in entries {
            guard let item=try? catalog.item(e.id) else{continue}
            let rarity=MeadowItemRarity.of(e.id,item:item)
            let chosen=e.id==selected
            var upgradeTag:String?=nil
            if let slot=item.slot,!e.equipped,let comp=try? session.equipmentComparison(actor:actor,slot:slot,item:e.id) {
                if comp.upgradeScore(catalog:catalog) > 0.25 { upgradeTag="▲ 提升" }
            }
            let card=MeadowItemCardButton()
            card.configure(
                item:item,
                rarity:rarity,
                chosen:chosen,
                equipped:e.equipped,
                statusText:e.quantity>1 ? "×\(e.quantity)":nil,
                footerText:MeadowItemRarity.shortStat(item),
                upgradeTag:upgradeTag
            )
            card.accessibilityIdentifier="campaignInventoryItem-"+e.id
            card.addAction(UIAction{[weak self] _ in self?.selected=e.id;self?.refresh()},for:.touchUpInside)
            list.addSubview(card);rows.append(card)
        }
        if rows.isEmpty {
            let emptyL=MeadowPreviewPalette.label("该分类下暂时没有物品",size:16,weight:.semibold)
            emptyL.textColor=MeadowPreviewPalette.muted;emptyL.textAlignment = .center
            list.addSubview(emptyL);rows=[emptyL]
        }

        members.selectedSegmentIndex=session.playerIDs.firstIndex(of:actor) ?? 0
        filterBar.selectedSegmentIndex=filters.firstIndex{$0.0==filter} ?? 0
        refillActions.isEnabled=session.inventoryActionRefillNeeded;refillActions.alpha=refillActions.isEnabled ? 1:0.4

        // Hero stats + live try-on preview
        let a=try? GameRules.attributes(unit,catalog:catalog)
        let clsName=catalog.classes.first{$0.id==unit.templateID}?.name ?? "冒险者"
        classBadge.text="  \(clsName)  "
        health.show("生命",value:unit.health,maximum:a?.maximumHealth ?? 1,color:.systemGreen)
        ap.show(value:unit.ap,maximum:a?.maximumAP ?? 8)

        let atkText=(try? GameRules.attack(unit,catalog:catalog)).map{"\($0.dice.label)"} ?? "空手"
        statChips[0].attributedText=MeadowGlassText.iconLine("scope",atkText,size:13,tint:MeadowPreviewPalette.primary,weight:.heavy)
        statChips[1].attributedText=MeadowGlassText.iconLine("burst.fill","+\(a?.damage ?? 0)",size:13,tint:UIColor(red:0.78,green:0.20,blue:0.18,alpha:1),weight:.heavy)
        statChips[2].attributedText=MeadowGlassText.iconLine("bitcoinsign.circle.fill","\(unit.coins)",size:13,tint:MeadowPreviewPalette.gold,weight:.heavy)
        statChips[3].attributedText=MeadowGlassText.iconLine("star.fill","\(unit.score)",size:13,tint:UIColor(red:0.12,green:0.45,blue:0.72,alpha:1),weight:.heavy)

        let selectedItem=selected.flatMap{try? catalog.item($0)}
        var previewWeapon=unit.equipment.weapon
        var previewArmor=unit.equipment.armor
        var tryingOn=false
        if let sel=selectedItem,let slot=sel.slot,unit.equipment[slot] != sel.id {
            if slot == .weapon { previewWeapon=sel.id;tryingOn=true }
            else if slot == .armor { previewArmor=sel.id;tryingOn=true }
        }
        tryOnBadge.isHidden = !tryingOn
        heroPedestal.layer.borderColor=(tryingOn ? UIColor(red:0.90,green:0.50,blue:0.06,alpha:1):UIColor.white.withAlphaComponent(0.85)).cgColor
        heroPedestal.layer.borderWidth=tryingOn ? 2.2:1.2

        let look=unit.appearance ?? PlayerAppearance(body:session.snapshot.appearanceID)
        let slotIdx=session.playerIDs.firstIndex(of:actor) ?? 0
        let appearanceIndex=HeroFrames.appearanceIDs.firstIndex(of:look.body) ?? 0
        var previewUnit=unit
        previewUnit.equipment.weapon=previewWeapon
        previewUnit.equipment.armor=previewArmor
        let shownArmor=tryingOn && selectedItem?.slot == .armor ? previewArmor : look.armor(worn:previewArmor)
        if PixelHeroAtlas.enabled {
            let pixel=(actor=="p1" && unit.appearance==nil)
                ? (HeroFrames.pixelLook(heroIndex:0,appearanceIndex:appearanceIndex,weaponID:previewWeapon,armorID:shownArmor,hair:look.hair,hairColor:look.hairColor,face:look.face) ?? PixelHeroLook.battle(unit:previewUnit,slot:slotIdx))
                : PixelHeroLook.battle(unit:previewUnit,slot:slotIdx)
            hero.image=PixelHeroAtlas.fullBody(pixel){[weak self,actor,selected] in
                if self?.actor==actor,self?.selected==selected {self?.hero.image=PixelHeroAtlas.fullBody(pixel)}
            }
            // Trying a piece on: once the choice rests, bake the map and battle pictures for it in the background, so
            // pressing 装备 changes the hero on the map / in battle at once instead of after a bake.
            prebake?.cancel()
            if tryingOn {
                let battleLook=PixelHeroLook.battle(unit:previewUnit,slot:slotIdx)
                let mapLook=(unit.appearance==nil && actor != "p1")
                    ? HeroFrames.pixelLook(heroIndex:slotIdx%3,weaponID:previewWeapon,armorID:previewArmor)
                    : HeroFrames.pixelLook(heroIndex:0,appearanceIndex:appearanceIndex,weaponID:previewWeapon,armorID:look.armor(worn:previewArmor),hair:look.hair,hairColor:look.hairColor,face:look.face)
                let task=DispatchWorkItem{PixelHeroAtlas.prepare(map:mapLook.map{[$0]} ?? [],battle:[battleLook])}
                prebake=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:task)
            }
        } else {
            hero.image=HeroFrames.inventoryImages(appearanceIndex:appearanceIndex,weaponID:previewWeapon,armorID:shownArmor,hair:look.hair,hairColor:look.hairColor,face:look.face).first
        }

        for (i,slot) in ItemSlot.allCases.enumerated(){
            let item=unit.equipment[slot].flatMap{try? catalog.item($0)}
            let willReplace = selectedItem?.slot == slot && unit.equipment[slot] != selectedItem?.id
            slots[i].configure(slot:slot,item:item,willReplace:willReplace)
        }
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews()
        let s=view.safeAreaInsets
        let b=view.bounds.inset(by:UIEdgeInsets(top:max(10,s.top),left:max(14,s.left),bottom:max(10,s.bottom),right:max(14,s.right)))
        let gap:CGFloat=12
        header.frame=CGRect(x:b.minX,y:b.minY,width:b.width,height:58)
        let top=header.frame.maxY+gap,h=b.maxY-top
        let lw=min(316,max(244,b.width*0.255))
        let rw=min(430,max(320,b.width*0.35))
        left.frame=CGRect(x:b.minX,y:top,width:lw,height:h)
        right.frame=CGRect(x:b.maxX-rw,y:top,width:rw,height:h)
        middle.frame=CGRect(x:left.frame.maxX+gap,y:top,width:max(120,right.frame.minX-gap-left.frame.maxX-gap),height:h)

        let w=header.bounds.width
        titleLabel.frame=CGRect(x:16,y:11,width:110,height:36)
        saveLabel.frame=CGRect(x:126,y:17,width:180,height:24)
        close.frame=CGRect(x:w-58,y:8,width:48,height:42)
        refillActions.frame=CGRect(x:w-162,y:8,width:96,height:42)
        timerButton.frame=CGRect(x:w-222,y:8,width:52,height:42)
        let mx:CGFloat=134
        let mw=max(140,min(540,w-234-mx))
        members.frame=CGRect(x:w-234-mw,y:11,width:mw,height:36)

        // Left column layout (tight, zero wasted vertical space)
        let lw2=left.bounds.width
        let pedH=min(182,max(126,left.bounds.height*0.28))
        heroPedestal.frame=CGRect(x:10,y:10,width:lw2-20,height:pedH)
        hero.frame=heroPedestal.bounds.insetBy(dx:10,dy:8)
        let cbW=min(heroPedestal.bounds.width-16,max(64,ceil(classBadge.intrinsicContentSize.width)+6))
        classBadge.frame=CGRect(x:8,y:8,width:cbW,height:20)
        tryOnBadge.frame=CGRect(x:heroPedestal.bounds.width-70,y:8,width:62,height:20)

        health.frame=CGRect(x:12,y:heroPedestal.frame.maxY+8,width:lw2-24,height:38)
        ap.frame=CGRect(x:12,y:health.frame.maxY+6,width:lw2-24,height:34)

        let chipW=(lw2-28)/2,chipH:CGFloat=28
        let chipTop=ap.frame.maxY+8
        for (i,chip) in statChips.enumerated() {
            chip.frame=CGRect(x:10+CGFloat(i%2)*(chipW+8),y:chipTop+CGFloat(i/2)*(chipH+6),width:chipW,height:chipH)
        }
        let slotTop=chipTop+chipH*2+16
        for (i,slotView) in slots.enumerated() {
            slotView.frame=CGRect(x:10,y:slotTop+CGFloat(i)*64,width:lw2-20,height:58)
        }
        left.contentSize=CGSize(width:lw2,height:slotTop+CGFloat(slots.count)*64+6)

        // Middle column layout
        filterBar.frame=CGRect(x:10,y:10,width:middle.bounds.width-20,height:36)
        list.frame=CGRect(x:10,y:54,width:middle.bounds.width-20,height:max(1,middle.bounds.height-64))
        if rows.count == 1 && !(rows[0] is MeadowItemCardButton) {
            rows[0].frame=CGRect(x:0,y:24,width:list.bounds.width,height:48)
            list.contentSize=CGSize(width:list.bounds.width,height:90)
        } else {
            let columns=max(2,Int((list.bounds.width+8)/146))
            let tileW=(list.bounds.width-CGFloat(columns-1)*8)/CGFloat(columns),tileH:CGFloat=126
            for (i,row) in rows.enumerated() {
                row.frame=CGRect(x:CGFloat(i%columns)*(tileW+8),y:CGFloat(i/columns)*(tileH+8),width:tileW,height:tileH)
            }
            let totalRows=(rows.count+columns-1)/columns
            list.contentSize=CGSize(width:list.bounds.width,height:max(1,CGFloat(totalRows)*(tileH+8)))
        }

        // Right column layout
        detail.frame=CGRect(x:0,y:0,width:right.bounds.width,height:max(1,right.bounds.height-68))
        primary.frame=CGRect(x:14,y:right.bounds.height-58,width:right.bounds.width-28,height:46)
        layoutDetail()
    }

    private func layoutDetail(){
        detailContent.subviews.forEach{$0.removeFromSuperview()}
        let width=detail.bounds.width,pad:CGFloat=14,innerW=max(80,width-pad*2)
        var y:CGFloat=12
        primary.isHidden=true
        guard let id=selected,let item=try? session.engine.catalog.item(id),let unit=session.engine.state.units[actor] else{
            let l=UILabel(frame:CGRect(x:pad,y:28,width:innerW,height:30))
            l.attributedText=MeadowGlassText.iconLine("hand.tap","选择一件物品查看品质与属性提升",size:16,tint:MeadowPreviewPalette.muted,weight:.semibold)
            l.textAlignment = .center
            detailContent.addSubview(l)
            detailContent.frame=CGRect(x:0,y:0,width:width,height:80);detail.contentSize=detailContent.bounds.size;return
        }
        let catalog=session.engine.catalog
        let rarity=MeadowItemRarity.of(id,item:item)
        let owned=unit.inventory[id] ?? 0
        let worn=item.slot.map{unit.equipment[$0]==id} ?? false

        // 1. Compact horizontal rarity header
        let statusParts=[worn ? "当前穿着":nil, owned>0 ? "行囊 \(owned) 件":nil].compactMap{$0}
        let headerCard=MeadowEquipmentDetailUI.identityHeader(item:item,rarity:rarity,subtitle:statusParts.joined(separator:" · "),catalog:catalog,width:innerW)
        headerCard.frame.origin=CGPoint(x:pad,y:y)
        detailContent.addSubview(headerCard)
        y+=headerCard.frame.height+10

        // 2. Concise full item stat summary strip
        let summary=CampInventoryProjection.summary(item)
        if !summary.isEmpty {
            let strip=UILabel()
            strip.attributedText=MeadowGlassText.iconLine("sparkles",summary,size:14.5,tint:MeadowPreviewPalette.gold,weight:.bold)
            strip.numberOfLines=0
            let sh=max(26,ceil(strip.sizeThatFits(CGSize(width:innerW-16,height:400)).height)+10)
            let bg=UIView(frame:CGRect(x:pad,y:y,width:innerW,height:sh))
            bg.backgroundColor=UIColor.white.withAlphaComponent(0.62)
            bg.layer.cornerRadius=10;bg.layer.borderWidth=1;bg.layer.borderColor=UIColor.white.withAlphaComponent(0.85).cgColor
            strip.frame=CGRect(x:8,y:4,width:innerW-16,height:sh-8)
            bg.addSubview(strip);detailContent.addSubview(bg)
            y+=sh+10
        }

        primary.isHidden=false;primary.isEnabled=false
        primary.configuration?.baseBackgroundColor=MeadowPreviewPalette.primary

        // 3. Structured equipment comparison + Set bonus progress card OR Consumable effect card
        if let slot=item.slot {
            let equipped=unit.equipment[slot]==id
            let wornName=unit.equipment[slot].flatMap{try? catalog.item($0).name} ?? (slot == .weapon ? "空手":"未装备")
            do {
                let comp=try session.equipmentComparison(actor:actor,slot:slot,item:equipped ? nil:id)
                let score=comp.upgradeScore(catalog:catalog)
                let subTitle=equipped ? "卸下「\(item.name)」后的属性变化":"当前「\(wornName)」→「\(item.name)」"
                let card=MeadowEquipmentDetailUI.comparisonCard(title:equipped ? "卸下属性预览":"换装属性对比",subtitle:subTitle,comparison:comp,catalog:catalog,width:innerW)
                card.frame.origin=CGPoint(x:pad,y:y);detailContent.addSubview(card);y+=card.frame.height+10

                // Show set bonus card for candidate item's set (or replaced item's set if losing a set piece!)
                let relevantSets=Array(NSOrderedSet(array:[item.setID,unit.equipment[slot].flatMap{try? catalog.item($0).setID}].compactMap{$0})) as? [String] ?? []
                for sid in relevantSets {
                    if let setCard=MeadowEquipmentDetailUI.setBonusCard(setID:sid,beforeUnit:comp.before,afterUnit:comp.after,catalog:catalog,width:innerW) {
                        setCard.frame.origin=CGPoint(x:pad,y:y);detailContent.addSubview(setCard);y+=setCard.frame.height+10
                    }
                }

                primary.isEnabled=true
                if equipped {
                    primary.configuration?.title="卸下装备"
                    primary.configuration?.baseBackgroundColor=UIColor(red:0.46,green:0.40,blue:0.44,alpha:0.95)
                } else if score > 0.25 {
                    primary.configuration?.title="装备 · 属性提升"
                    primary.configuration?.baseBackgroundColor=UIColor(red:0.10,green:0.58,blue:0.30,alpha:1)
                } else {
                    primary.configuration?.title=unit.equipment[slot] == nil ? "装备":"替换装备"
                    primary.configuration?.baseBackgroundColor=MeadowPreviewPalette.primary
                }
            } catch {
                let errL=UILabel();errL.attributedText=MeadowGlassText.iconLine("exclamationmark.triangle.fill",error.localizedDescription,size:14,tint:.systemOrange,weight:.semibold);errL.numberOfLines=0
                let eh=max(24,ceil(errL.sizeThatFits(CGSize(width:innerW,height:200)).height))
                errL.frame=CGRect(x:pad,y:y,width:innerW,height:eh);detailContent.addSubview(errL);y+=eh+10
            }
        } else {
            let who=UILabel(frame:CGRect(x:pad,y:y,width:innerW,height:20))
            who.attributedText=MeadowGlassText.iconLine("person.fill","使用目标",size:14,tint:MeadowPreviewPalette.muted,weight:.bold)
            detailContent.addSubview(who);y+=24

            let targets=UISegmentedControl(items:session.playerIDs.map{session.engine.state.units[$0]?.shortName ?? $0.uppercased()})
            targets.selectedSegmentIndex=session.playerIDs.firstIndex(of:target) ?? 0
            targets.setTitleTextAttributes([.font:MeadowPreviewPalette.font(14.5,.bold),.foregroundColor:MeadowPreviewPalette.ink],for:.normal)
            targets.setTitleTextAttributes([.font:MeadowPreviewPalette.font(14.5,.heavy),.foregroundColor:UIColor.white],for:.selected)
            targets.selectedSegmentTintColor=MeadowPreviewPalette.primary
            targets.frame=CGRect(x:pad,y:y,width:innerW,height:34);detailContent.addSubview(targets);y+=42
            targets.addAction(UIAction{[weak self,weak targets] _ in
                guard let self else{return}
                self.target=self.session.playerIDs[max(0,targets?.selectedSegmentIndex ?? 0)]
                self.view.setNeedsLayout()
            },for:.valueChanged)

            primary.configuration?.title=item.kind == .revivalStone ? "复活队友":"使用补给"
            if let receiver=session.engine.state.units[target],let a=try? GameRules.attributes(receiver,catalog:catalog){
                let afterHP=item.kind == .revivalStone ? (a.maximumHealth+1)/2 : min(a.maximumHealth,receiver.health+item.heal)
                let afterShield=max(receiver.shield,item.shield)
                let effectBox=UIView()
                effectBox.backgroundColor=UIColor.white.withAlphaComponent(0.68)
                effectBox.layer.cornerRadius=12;effectBox.layer.borderWidth=1;effectBox.layer.borderColor=UIColor.white.cgColor
                var ey:CGFloat=10
                if afterHP != receiver.health {
                    let l=UILabel(frame:CGRect(x:12,y:ey,width:innerW-24,height:22))
                    l.attributedText=MeadowGlassText.iconLine("heart.fill","生命  \(receiver.health) → \(afterHP)/\(a.maximumHealth)  (+\(afterHP-receiver.health))",size:15,tint:UIColor(red:0.08,green:0.56,blue:0.25,alpha:1),weight:.heavy)
                    effectBox.addSubview(l);ey+=26
                }
                if afterShield != receiver.shield {
                    let l=UILabel(frame:CGRect(x:12,y:ey,width:innerW-24,height:22))
                    l.attributedText=MeadowGlassText.iconLine("shield.fill","护盾  \(receiver.shield) → \(afterShield)  (+\(afterShield-receiver.shield))",size:15,tint:UIColor(red:0.10,green:0.46,blue:0.80,alpha:1),weight:.heavy)
                    effectBox.addSubview(l);ey+=26
                }
                if ey > 10 {
                    effectBox.frame=CGRect(x:pad,y:y,width:innerW,height:ey+6)
                    detailContent.addSubview(effectBox);y+=effectBox.frame.height+10
                }
            }
            do {
                let command=try session.inventoryItemCommand(actor:actor,item:id,target:target),preview=session.engine.preview(command)
                primary.isEnabled=preview.allowed
                if !preview.allowed {
                    let l=UILabel();l.attributedText=MeadowGlassText.iconLine("exclamationmark.circle",preview.message,size:14,tint:.systemOrange,weight:.semibold);l.numberOfLines=0
                    let lh=max(22,ceil(l.sizeThatFits(CGSize(width:innerW,height:200)).height))
                    l.frame=CGRect(x:pad,y:y,width:innerW,height:lh);detailContent.addSubview(l);y+=lh+8
                }
            } catch {
                let l=UILabel();l.attributedText=MeadowGlassText.iconLine("exclamationmark.circle",error.localizedDescription,size:14,tint:.systemOrange,weight:.semibold);l.numberOfLines=0
                let lh=max(22,ceil(l.sizeThatFits(CGSize(width:innerW,height:200)).height))
                l.frame=CGRect(x:pad,y:y,width:innerW,height:lh);detailContent.addSubview(l);y+=lh+8
            }
        }
        primary.alpha=primary.isEnabled ? 1:0.45

        // 4. Compact Teammate Gift Panel (outside battle)
        let mates=session.teammates(of:actor)
        if !mates.isEmpty,session.engine.state.battle==nil {
            let giftBox=UIView()
            giftBox.backgroundColor=UIColor.white.withAlphaComponent(0.55)
            giftBox.layer.cornerRadius=12;giftBox.layer.borderWidth=1;giftBox.layer.borderColor=UIColor.white.withAlphaComponent(0.8).cgColor
            var gy:CGFloat=8
            let header=UILabel(frame:CGRect(x:10,y:gy,width:innerW-20,height:20))
            header.attributedText=MeadowGlassText.iconLine("gift.fill","赠送队友",size:14,tint:MeadowPreviewPalette.primary,weight:.heavy)
            giftBox.addSubview(header);gy+=26
            let nameW:CGFloat=68,btnGap:CGFloat=6,bw=max(62,(innerW-20-nameW-btnGap*2)/2)
            for mate in mates {
                let name=MeadowPreviewPalette.label(mate.shortName,size:14.5,weight:.bold);name.lineBreakMode = .byTruncatingTail
                name.frame=CGRect(x:10,y:gy,width:nameW,height:34);giftBox.addSubview(name)
                let thing=MeadowPreviewPalette.iconButton("shippingbox.fill","送这件"),coins=MeadowPreviewPalette.iconButton("bitcoinsign.circle.fill","10金币")
                thing.isEnabled=owned>0;coins.isEnabled=unit.coins>=10
                for (i,b) in [thing,coins].enumerated() {
                    b.alpha=b.isEnabled ? 1:0.42
                    b.frame=CGRect(x:10+nameW+btnGap+CGFloat(i)*(bw+btnGap),y:gy,width:bw,height:34)
                    giftBox.addSubview(b)
                }
                thing.addAction(UIAction{[weak self] _ in self?.gift(to:mate,item:id,coins:0)},for:.touchUpInside)
                coins.addAction(UIAction{[weak self] _ in self?.gift(to:mate,item:nil,coins:10)},for:.touchUpInside)
                gy+=40
            }
            if owned==0,worn {
                let hint=UILabel(frame:CGRect(x:10,y:gy,width:innerW-20,height:18))
                hint.attributedText=MeadowGlassText.iconLine("info.circle","穿着中的装备需先卸下才能赠送",size:12,tint:MeadowPreviewPalette.muted,weight:.semibold)
                giftBox.addSubview(hint);gy+=22
            }
            giftBox.frame=CGRect(x:pad,y:y,width:innerW,height:gy+4)
            detailContent.addSubview(giftBox);y+=giftBox.frame.height+8
        }

        detailContent.frame=CGRect(x:0,y:0,width:width,height:y+8)
        detail.contentSize=detailContent.bounds.size
    }

    private func gift(to mate:GameUnit,item:String?,coins:Int) {
        do{
            try session.give(from:actor,to:mate.id,coins:coins,item:item,count:item==nil ? 0:1)
            flash("已送给 "+mate.shortName);onChange?();refresh()
        }catch{let alert=UIAlertController(title:"赠送未完成",message:error.localizedDescription,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"知道了",style:.default));present(alert,animated:true)}
    }
    private func activate(){
        guard let id=selected,let item=try? session.engine.catalog.item(id) else{return}
        do{
            if let slot=item.slot {
                guard let performEquip else{throw GameError("装备入口不可用。")}
                try performEquip(actor,slot,session.engine.state.units[actor]?.equipment[slot]==id ? nil:id)
            }else{try session.useInventory(actor:actor,item:id,target:target)}
            flash("已保存");onChange?();refresh()
        }catch{refresh();let alert=UIAlertController(title:"操作未完成",message:error.localizedDescription,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"知道了",style:.default));present(alert,animated:true)}
    }
}
