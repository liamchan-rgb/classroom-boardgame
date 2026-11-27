import UIKit
import ClassroomGameCore

/// The picture of an item, wherever items are listed (shop, backpack, gains). Items with their own art use it (weapons, armour,
/// accessories, potions, revival stone); the rest (set pieces without art yet) get a drawn badge: a framed tile in the colour of
/// their set with a symbol for their kind, so every row still has a recognisable picture.
enum MeadowItemIcon {
    private static var cache:[String:UIImage]=[:]

    static func image(_ id:String,item:ItemDefinition?=nil)->UIImage {
        if let image=cache[id] { return image }
        // 像素图标（和人物同一套像素画法）：稀有以上带发光动画（PixelIconFX<Id>，24 帧横排，12 帧 / 秒），其余是静态图
        let cap=id.prefix(1).uppercased()+id.dropFirst()
        if let animated=animatedPixelIcon(cap) ?? UIImage(named:"PixelIcon"+cap) { cache[id]=animated;return animated }
        let asset=HeroFrames.weaponVisual(id)?.iconAsset ?? HeroFrames.armorVisual(id)?.iconAsset ?? HeroFrames.accessoryVisual(id)?.iconAsset
            ?? ["smallPotion":"MeadowPartySmallPotion","largePotion":"MeadowPartyLargePotion","shieldPotion":"MeadowPartyShieldPotion","revivalStone":"MeadowPartyRevivalStone"][id]
        let image=asset.flatMap { UIImage(named:$0) } ?? badge(id,item:item)
        cache[id]=image
        return image
    }

    private static func badge(_ id:String,item:ItemDefinition?)->UIImage {
        let set=item?.setID ?? (id.hasPrefix("starlight") ? "starlight":id.hasPrefix("dragon") ? "dragonMark":id.hasPrefix("wildwood") ? "wildwood":id.hasPrefix("gale") ? "galeHunter":id.hasPrefix("oak") ? "oakBastion":id.hasPrefix("ember") ? "emberArcana":id.hasPrefix("aegis") ? "aegisSeraph":id.hasPrefix("astral") ? "astralSovereign":nil)
        let tint:UIColor = {
            switch set {
            case "wildwood": return UIColor(red:0.42,green:0.80,blue:0.46,alpha:1)
            case "galeHunter": return UIColor(red:0.35,green:0.82,blue:0.92,alpha:1)
            case "oakBastion": return UIColor(red:0.62,green:0.74,blue:0.38,alpha:1)
            case "starlight": return UIColor(red:0.45,green:0.78,blue:1,alpha:1)
            case "emberArcana": return UIColor(red:0.95,green:0.48,blue:0.25,alpha:1)
            case "dragonMark": return UIColor(red:0.95,green:0.38,blue:0.30,alpha:1)
            case "aegisSeraph": return UIColor(red:1.0,green:0.82,blue:0.38,alpha:1)
            case "astralSovereign": return UIColor(red:0.76,green:0.52,blue:1.0,alpha:1)
            default: return MeadowPreviewPalette.gold
            }
        }()
        let symbol:String
        switch item?.slot {
        case .weapon?: symbol="bolt.fill"
        case .armor?: symbol="shield.lefthalf.filled"
        case .accessory?: symbol="seal.fill"
        default: symbol=item?.kind == .revivalStone ? "heart.circle.fill":"cross.vial.fill"
        }
        let size=CGSize(width:128,height:128)
        return UIGraphicsImageRenderer(size:size).image { r in
            let c=r.cgContext,box=CGRect(origin:.zero,size:size).insetBy(dx:8,dy:8)
            let path=UIBezierPath(roundedRect:box,cornerRadius:22)
            c.saveGState();path.addClip()
            let colors=[tint.withAlphaComponent(0.55).cgColor,UIColor(red:0.10,green:0.22,blue:0.28,alpha:1).cgColor] as CFArray
            if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) { c.drawRadialGradient(g,startCenter:CGPoint(x:64,y:50),startRadius:4,endCenter:CGPoint(x:64,y:64),endRadius:80,options:[]) }
            c.restoreGState()
            tint.setStroke();path.lineWidth=5;path.stroke()
            let config=UIImage.SymbolConfiguration(pointSize:52,weight:.bold)
            if let glyph=UIImage(systemName:symbol,withConfiguration:config)?.withTintColor(.white,renderingMode:.alwaysOriginal) {
                glyph.draw(in:CGRect(x:64-glyph.size.width/2,y:64-glyph.size.height/2,width:glyph.size.width,height:glyph.size.height))
            }
        }
    }

    /// The image scaled to a square of `side` points (for button images). Animated icons stay animated.
    /// Scaled icons are kept: menus are rebuilt on every battle refresh and an animated icon has 24 frames to redraw.
    private static var scaledCache:[String:UIImage]=[:]
    static func image(_ id:String,item:ItemDefinition?=nil,side:CGFloat)->UIImage {
        let key="\(id)|\(side)"
        if let hit=scaledCache[key] {return hit}
        let made=makeScaled(id,item:item,side:side)
        if scaledCache.count>200 {scaledCache.removeAll()}
        scaledCache[key]=made
        return made
    }
    private static func makeScaled(_ id:String,item:ItemDefinition?,side:CGFloat)->UIImage {
        let source=image(id,item:item)
        func scaled(_ frame:UIImage)->UIImage {
            UIGraphicsImageRenderer(size:CGSize(width:side,height:side)).image { r in
                r.cgContext.interpolationQuality = .none
                let k=min(side/frame.size.width,side/frame.size.height),w=frame.size.width*k,h=frame.size.height*k
                frame.draw(in:CGRect(x:(side-w)/2,y:(side-h)/2,width:w,height:h))
            }
        }
        if let frames=source.images,frames.count>1 { return UIImage.animatedImage(with:frames.map(scaled),duration:source.duration) ?? scaled(frames[0]) }
        return scaled(source)
    }

    /// 发光动画：素材是一条横排的帧，切开做成会动的 UIImage（UIImageView / 按钮直接播放）
    private static func animatedPixelIcon(_ cap:String)->UIImage? {
        guard let strip=UIImage(named:"PixelIconFX"+cap)?.cgImage,strip.height>0 else { return nil }
        let side=strip.height,count=strip.width/side
        guard count>1 else { return nil }
        let frames=(0..<count).compactMap { k in strip.cropping(to:CGRect(x:k*side,y:0,width:side,height:side)).map { UIImage(cgImage:$0) } }
        return UIImage.animatedImage(with:frames,duration:Double(count)/12)
    }
}

/// 物品品级（和像素图标的特效一致）：普通 灰白 / 稀有 蓝 / 史诗 紫 / 传说 橙金。
/// 掉落动画、获得物品的确认框、背包卡片、商店卡片与转盘扇面统一按它分级呈现。
enum MeadowItemRarity: Int, Comparable, CaseIterable {
    case common = 0, rare, epic, legendary

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    static func of(_ id: String, item: ItemDefinition? = nil) -> MeadowItemRarity {
        switch id {
        case "greatSword", "runeArmor", "actionRing", "revivalStone",
             "frostWand", "knightHalberd", "chainmailCoat", "windrunnerGarb", "eagleEyeLens",
             "galeLongbow", "galeArmor", "galeCharm", "oakHammer", "oakArmor", "oakCharm",
             "ironbarkElixir", "honeySalve":
            return .rare
        case "starlightBlade", "starlightArmor", "starlightCharm",
             "flameAxe", "thunderCrossbow", "emeraldScepter", "shadowTwinblades",
             "mithrilPlate", "arcaneMantle", "rubyHeartPendant", "chronoPocketwatch",
             "emberStaff", "emberArmor", "emberCharm",
             "superPotion", "crystalBarrierFlask":
            return .epic
        case "legendaryStaff", "dragonFangSword", "dragonArmor", "dragonCharm",
             "sunbreakerBlade", "astralGreatbow", "titanFortressArmor", "phoenixFeatherRobe",
             "crownOfValor", "infinityHourglass",
             "aegisLance", "aegisArmor", "aegisCharm", "astralCodex", "astralArmor", "astralCharm",
             "phoenixNectar", "starlightElixir", "aegisCrystal":
            return .legendary
        default:
            switch item?.setID {
            case "galeHunter"?, "oakBastion"?: return .rare
            case "starlight"?, "emberArcana"?: return .epic
            case "dragonMark"?, "aegisSeraph"?, "astralSovereign"?: return .legendary
            default: return .common
            }
        }
    }

    var title: String { ["普通", "稀有", "史诗", "传说"][rawValue] }
    var stars: String { ["★", "★★", "★★★", "★★★★"][rawValue] }

    /// 暗底/发光特效色（用于粒子、光柱、转盘高亮与深色舞台）
    var color: UIColor {
        switch self {
        case .common: return UIColor(white: 0.93, alpha: 1)
        case .rare: return UIColor(red: 0.36, green: 0.68, blue: 1.0, alpha: 1)
        case .epic: return UIColor(red: 0.74, green: 0.48, blue: 1.0, alpha: 1)
        case .legendary: return UIColor(red: 1.0, green: 0.66, blue: 0.2, alpha: 1)
        }
    }

    /// 浅色毛玻璃底上的高对比度文字色（普通改为深岩灰，彻底解决白字隐身问题）
    var inkColor: UIColor {
        switch self {
        case .common: return UIColor(red: 0.32, green: 0.39, blue: 0.45, alpha: 1)
        case .rare: return UIColor(red: 0.07, green: 0.38, blue: 0.78, alpha: 1)
        case .epic: return UIColor(red: 0.46, green: 0.17, blue: 0.78, alpha: 1)
        case .legendary: return UIColor(red: 0.74, green: 0.36, blue: 0.02, alpha: 1)
        }
    }

    /// 实心品质标签胶囊底色（配纯白粗字，教室远距投影一眼可辨）
    var badgeColor: UIColor {
        switch self {
        case .common: return UIColor(red: 0.44, green: 0.51, blue: 0.57, alpha: 1)
        case .rare: return UIColor(red: 0.12, green: 0.49, blue: 0.90, alpha: 1)
        case .epic: return UIColor(red: 0.56, green: 0.25, blue: 0.88, alpha: 1)
        case .legendary: return UIColor(red: 0.87, green: 0.48, blue: 0.05, alpha: 1)
        }
    }

    /// 卡片浅底色（低饱和品质底晕，保持界面通透且不喧宾夺主）
    var surfaceTint: UIColor {
        switch self {
        case .common: return UIColor(red: 0.96, green: 0.98, blue: 0.99, alpha: 0.84)
        case .rare: return UIColor(red: 0.89, green: 0.95, blue: 1.00, alpha: 0.88)
        case .epic: return UIColor(red: 0.94, green: 0.89, blue: 1.00, alpha: 0.89)
        case .legendary: return UIColor(red: 1.00, green: 0.95, blue: 0.83, alpha: 0.92)
        }
    }

    /// 卡片与槽位描边色
    var borderColor: UIColor {
        switch self {
        case .common: return UIColor(red: 0.72, green: 0.79, blue: 0.84, alpha: 0.88)
        case .rare: return UIColor(red: 0.22, green: 0.56, blue: 0.96, alpha: 0.92)
        case .epic: return UIColor(red: 0.62, green: 0.34, blue: 0.94, alpha: 0.95)
        case .legendary: return UIColor(red: 0.92, green: 0.58, blue: 0.08, alpha: 1.0)
        }
    }

    /// 像素特效片段名的后缀（lootBeamRare / collectEpic …）；普通物品没有光柱
    var clipSuffix: String? { [nil, "Rare", "Epic", "Legendary"][rawValue] }

    /// 卡片上一眼可读的 1 行核心属性摘要（用于背包卡片、商店卡片与奖池列表）
    static func shortStat(_ item: ItemDefinition) -> String {
        var parts: [String] = []
        if let attack = item.attack {
            parts.append("\(attack.dice.label) 距\(attack.range)")
        }
        let a = item.attributes
        if a.maximumHealth != 0 { parts.append("生命+\(a.maximumHealth)") }
        if a.damage != 0 { parts.append("伤害+\(a.damage)") }
        if a.baseAP != 0 { parts.append("行动+\(a.baseAP)") }
        if a.maximumAP != 0 { parts.append("上限+\(a.maximumAP)") }
        if a.range != 0 { parts.append("射程+\(a.range)") }
        if item.heal > 0 { parts.append("回血+\(item.heal)") }
        if item.shield > 0 { parts.append("护盾\(item.shield)") }
        if item.kind == .revivalStone { parts.append("复活半血") }
        return parts.prefix(2).joined(separator: " · ")
    }
}

/// 统一的高可读性物品卡片（供背包与商店复用）：顶部品质彩条、实心品质胶囊、套装标、装备/数量/提升角标、
/// 像素图标底座、粗体物品名与一行核心属性或价格，彻底告别白板按钮。
final class MeadowItemCardButton: UIControl {
    private let accentBar = UIView()
    private let rarityPill = UILabel()
    private let setBadge = UILabel()
    private let statusPill = UILabel()
    private let iconHalo = UIView()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let footerLabel = UILabel()
    private let upgradePill = UILabel()
    private let selectionRing = CAShapeLayer()

    private var currentRarity: MeadowItemRarity = .common
    private var isChosenState = false
    private var isEquippedState = false
    private var hasSetBadge = false
    private var hasUpgradeBadge = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous

        accentBar.isUserInteractionEnabled = false
        addSubview(accentBar)

        rarityPill.font = MeadowPreviewPalette.font(10.5, .heavy)
        rarityPill.textColor = .white
        rarityPill.textAlignment = .center
        rarityPill.layer.cornerRadius = 6
        rarityPill.layer.cornerCurve = .continuous
        rarityPill.clipsToBounds = true
        rarityPill.isUserInteractionEnabled = false

        setBadge.text = "套"
        setBadge.font = MeadowPreviewPalette.font(10.5, .heavy)
        setBadge.textColor = .white
        setBadge.textAlignment = .center
        setBadge.backgroundColor = UIColor(red: 0.45, green: 0.24, blue: 0.78, alpha: 1)
        setBadge.layer.cornerRadius = 6
        setBadge.layer.cornerCurve = .continuous
        setBadge.clipsToBounds = true
        setBadge.isUserInteractionEnabled = false

        statusPill.font = MeadowPreviewPalette.font(10.5, .heavy)
        statusPill.textAlignment = .center
        statusPill.layer.cornerRadius = 6
        statusPill.layer.cornerCurve = .continuous
        statusPill.clipsToBounds = true
        statusPill.isUserInteractionEnabled = false

        iconHalo.layer.cornerRadius = 14
        iconHalo.layer.cornerCurve = .continuous
        iconHalo.isUserInteractionEnabled = false

        iconView.contentMode = .scaleAspectFit
        iconView.layer.magnificationFilter = .nearest
        iconView.layer.minificationFilter = .nearest
        iconView.isUserInteractionEnabled = false

        nameLabel.font = MeadowPreviewPalette.font(14.5, .heavy)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.76
        nameLabel.isUserInteractionEnabled = false

        footerLabel.font = MeadowPreviewPalette.font(12, .bold)
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 1
        footerLabel.adjustsFontSizeToFitWidth = true
        footerLabel.minimumScaleFactor = 0.78
        footerLabel.isUserInteractionEnabled = false

        upgradePill.font = MeadowPreviewPalette.font(10, .heavy)
        upgradePill.textColor = .white
        upgradePill.textAlignment = .center
        upgradePill.backgroundColor = UIColor(red: 0.11, green: 0.62, blue: 0.30, alpha: 1)
        upgradePill.layer.cornerRadius = 6
        upgradePill.clipsToBounds = true
        upgradePill.isUserInteractionEnabled = false

        [rarityPill, setBadge, statusPill, iconHalo, iconView, nameLabel, footerLabel, upgradePill].forEach(addSubview)

        selectionRing.fillColor = UIColor.clear.cgColor
        selectionRing.lineWidth = 3
        layer.addSublayer(selectionRing)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        item: ItemDefinition,
        rarity: MeadowItemRarity,
        chosen: Bool,
        equipped: Bool = false,
        statusText: String? = nil,
        statusColor: UIColor? = nil,
        footerText: String,
        footerColor: UIColor? = nil,
        upgradeTag: String? = nil,
        dimmed: Bool = false
    ) {
        currentRarity = rarity
        isChosenState = chosen
        isEquippedState = equipped
        hasSetBadge = item.setID != nil
        hasUpgradeBadge = (upgradeTag != nil && !(upgradeTag?.isEmpty ?? true))

        backgroundColor = chosen ? rarity.surfaceTint.withAlphaComponent(0.98) : rarity.surfaceTint
        accentBar.backgroundColor = rarity.badgeColor

        rarityPill.text = rarity.title
        rarityPill.backgroundColor = rarity.badgeColor
        setBadge.isHidden = !hasSetBadge

        if equipped {
            statusPill.text = "已装备"
            statusPill.textColor = .white
            statusPill.backgroundColor = UIColor(red: 0.08, green: 0.48, blue: 0.42, alpha: 1)
            statusPill.isHidden = false
        } else if let statusText, !statusText.isEmpty {
            statusPill.text = statusText
            statusPill.textColor = statusColor == nil ? MeadowPreviewPalette.ink : .white
            statusPill.backgroundColor = statusColor ?? UIColor.white.withAlphaComponent(0.75)
            statusPill.isHidden = false
        } else {
            statusPill.isHidden = true
        }

        iconHalo.backgroundColor = rarity == .common
            ? UIColor.white.withAlphaComponent(0.68)
            : rarity.badgeColor.withAlphaComponent(0.14)
        iconHalo.layer.borderWidth = rarity == .common ? 1 : 1.2
        iconHalo.layer.borderColor = rarity.borderColor.withAlphaComponent(0.45).cgColor
        iconView.image = MeadowItemIcon.image(item.id, item: item, side: 64)

        nameLabel.text = item.name
        nameLabel.textColor = rarity >= .epic ? rarity.inkColor : MeadowPreviewPalette.ink

        footerLabel.text = footerText.isEmpty ? (item.slot.map { $0 == .weapon ? "武器" : ($0 == .armor ? "护甲" : "饰品") } ?? "补给") : footerText
        footerLabel.textColor = footerColor ?? (rarity >= .rare ? rarity.inkColor : MeadowPreviewPalette.muted)

        upgradePill.text = upgradeTag
        upgradePill.isHidden = !hasUpgradeBadge

        layer.borderColor = (chosen ? MeadowPreviewPalette.primary : (equipped ? MeadowPreviewPalette.gold : rarity.borderColor)).cgColor
        layer.borderWidth = chosen ? 2.6 : (equipped ? 2.0 : 1.3)
        selectionRing.strokeColor = chosen ? MeadowPreviewPalette.primary.cgColor : UIColor.clear.cgColor
        alpha = (dimmed && !chosen) ? 0.62 : 1.0
        accessibilityLabel = "\(rarity.title) \(item.name) \(footerText)"
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        accentBar.frame = CGRect(x: 0, y: 0, width: w, height: 4.5)
        selectionRing.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 12.5).cgPath

        let topY: CGFloat = 8
        rarityPill.frame = CGRect(x: 7, y: topY, width: 32, height: 17)
        if hasSetBadge {
            setBadge.frame = CGRect(x: rarityPill.frame.maxX + 3, y: topY, width: 17, height: 17)
        }
        if !statusPill.isHidden {
            let sw = min(w - 50, max(30, statusPill.intrinsicContentSize.width + 10))
            statusPill.frame = CGRect(x: w - sw - 7, y: topY, width: sw, height: 17)
        }

        let bottomReserve: CGFloat = 42
        let iconAreaTop = topY + 20
        let iconSide = max(36, min(56, h - iconAreaTop - bottomReserve - 4, w - 26))
        let haloSide = iconSide + 8
        let haloY = iconAreaTop + max(0, (h - iconAreaTop - bottomReserve - haloSide) / 2)
        iconHalo.frame = CGRect(x: (w - haloSide) / 2, y: haloY, width: haloSide, height: haloSide)
        iconView.frame = iconHalo.frame.insetBy(dx: 4, dy: 4)

        if hasUpgradeBadge {
            let uw = max(36, upgradePill.intrinsicContentSize.width + 8)
            let uy = statusPill.isHidden ? topY : (topY + 20)
            upgradePill.frame = CGRect(x: w - uw - 7, y: uy, width: uw, height: 17)
        }

        nameLabel.frame = CGRect(x: 6, y: h - 39, width: w - 12, height: 19)
        footerLabel.frame = CGRect(x: 6, y: h - 20, width: w - 12, height: 16)
    }
}
