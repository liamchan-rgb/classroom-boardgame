import UIKit
import ClassroomGameCore

/// The shop's prize wheel: pick a tier (铜 / 银 / 金), spin, the wheel decelerates onto the prize the rules drew.
/// The view never decides the prize; `onSpin` performs the rule operation and returns the winning slot.
final class MeadowLotteryView: UIView {
    var onSpin: ((Int) -> Int?)?
    var onFinished: ((Int, Int) -> Void)?
    private(set) var tier = 0
    private let tiers = UISegmentedControl(items: CampaignLottery.tiers.map { "\($0.title)档 · \($0.cost)" })
    private let wheel = MeadowWheelView()
    private let pointer = UIImageView(image: UIImage(systemName: "arrowtriangle.down.fill"))
    private let spin = MeadowPreviewPalette.iconButton("sparkles", "抽一次", prominent: true)
    private let note = MeadowPreviewPalette.label("", size: 15, weight: .semibold)
    private var spinning = false
    var catalog: GameCatalog? { didSet { wheel.catalog = catalog; wheel.setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for state in [UIControl.State.normal, .selected] {
            tiers.setTitleTextAttributes([.font: MeadowPreviewPalette.font(16, .bold), .foregroundColor: MeadowPreviewPalette.ink], for: state)
        }
        tiers.selectedSegmentTintColor = UIColor(red: 0.62, green: 0.48, blue: 0.18, alpha: 1)
        tiers.selectedSegmentIndex = 0
        tiers.addAction(UIAction { [weak self] _ in self?.selectTier() }, for: .valueChanged)
        pointer.tintColor = MeadowPreviewPalette.gold; pointer.contentMode = .scaleAspectFit
        pointer.layer.shadowColor = UIColor.black.cgColor; pointer.layer.shadowOpacity = 0.5; pointer.layer.shadowRadius = 4; pointer.layer.shadowOffset = .zero
        note.textAlignment = .center; note.numberOfLines = 2; note.textColor = MeadowPreviewPalette.muted
        spin.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
        [tiers, wheel, pointer, spin, note].forEach(addSubview)
        selectTier()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func selectTier() {
        guard !spinning else { tiers.selectedSegmentIndex = tier; return }
        tier = max(0, tiers.selectedSegmentIndex)
        wheel.tier = CampaignLottery.tiers[tier]; wheel.transform = .identity; wheel.setNeedsDisplay()
        let t = CampaignLottery.tiers[tier]
        let sets = t.prizes.filter { p in p.item.flatMap { try? catalog?.item($0).setID } != nil }.map(\.weight).reduce(0, +)
        note.text = "每次 \(t.cost) 金币 · 套装部件概率约 \(Int((Double(sets) / Double(t.totalWeight) * 100).rounded()))%"
    }
    private func go() {
        guard !spinning, let slot = onSpin?(tier) else { return }
        spinning = true; spin.isEnabled = false; tiers.isEnabled = false
        let n = CGFloat(wheel.tier.prizes.count), sector = 2 * .pi / n
        // The pointer is at the top: bring the middle of the winning slice there after a few full turns.
        let jitter = CGFloat.random(in: -0.32...0.32) * sector
        let target = -(CGFloat(slot) + 0.5) * sector + jitter + 2 * .pi * 6
        let spinAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        spinAnimation.fromValue = 0; spinAnimation.toValue = target; spinAnimation.duration = 3.6
        spinAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.12, 0.8, 0.18, 1)
        wheel.transform = CGAffineTransform(rotationAngle: target)
        wheel.layer.add(spinAnimation, forKey: "spin")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) { [weak self] in
            guard let self else { return }
            self.spinning = false; self.spin.isEnabled = true; self.tiers.isEnabled = true
            self.wheel.highlight = slot; self.wheel.setNeedsDisplay()
            UIView.animate(withDuration: 0.15, animations: { self.pointer.transform = CGAffineTransform(scaleX: 1.3, y: 1.3) }) { _ in
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.8, options: []) { self.pointer.transform = .identity }
            }
            self.onFinished?(self.tier, slot)
        }
        wheel.highlight = nil
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        tiers.frame = CGRect(x: max(16, (w - 420) / 2), y: 14, width: min(420, w - 32), height: 40)
        let side = max(120, min(w - 40, h - 190))
        wheel.bounds = CGRect(x: 0, y: 0, width: side, height: side); wheel.center = CGPoint(x: w / 2, y: 74 + side / 2 + 14)
        pointer.frame = CGRect(x: w / 2 - 18, y: wheel.center.y - side / 2 - 22, width: 36, height: 36)
        spin.frame = CGRect(x: w / 2 - 110, y: wheel.center.y + side / 2 + 16, width: 220, height: 52)
        note.frame = CGRect(x: 16, y: spin.frame.maxY + 6, width: w - 32, height: 40)
    }
}

/// The wheel face: one slice per prize (slice size is equal; the odds are the rules' weights, shown in the note).
final class MeadowWheelView: UIView {
    var tier = CampaignLottery.tiers[0]
    var catalog: GameCatalog?
    var highlight: Int?
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2 - 4
        let n = tier.prizes.count, sector = 2 * CGFloat.pi / CGFloat(n)
        let palette = [UIColor(red: 0.20, green: 0.36, blue: 0.27, alpha: 1), UIColor(red: 0.27, green: 0.45, blue: 0.33, alpha: 1)]
        for (i, prize) in tier.prizes.enumerated() {
            // Slice i is centred on angle (i + 0.5) * sector measured clockwise from the top.
            let start = -CGFloat.pi / 2 + CGFloat(i) * sector, end = start + sector
            let isSet = prize.item.flatMap { try? catalog?.item($0).setID } != nil
            let fill = highlight == i ? MeadowPreviewPalette.gold : (isSet ? UIColor(red: 0.45, green: 0.30, blue: 0.62, alpha: 1) : palette[i % 2])
            ctx.move(to: c); ctx.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false); ctx.closePath()
            fill.setFill(); ctx.fillPath()
            ctx.move(to: c); ctx.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false); ctx.closePath()
            UIColor.white.withAlphaComponent(0.25).setStroke(); ctx.setLineWidth(1.5); ctx.strokePath()
            // Prize picture (or the coin amount) near the rim, upright along the slice.
            let mid = start + sector / 2, iconR = r * 0.72, side = min(r * 0.32, r * sector * 0.7)
            ctx.saveGState(); ctx.translateBy(x: c.x + cos(mid) * iconR, y: c.y + sin(mid) * iconR); ctx.rotate(by: mid + .pi / 2)
            if let id = prize.item {
                let image = MeadowItemIcon.image(id, item: try? catalog?.item(id), side: 64)
                image.draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                if prize.count > 1 { draw("×\(prize.count)", at: CGPoint(x: 0, y: side / 2 + 8), size: side * 0.32) }
            } else { draw("\(prize.coins)", at: .zero, size: side * 0.42, color: MeadowPreviewPalette.gold) }
            ctx.restoreGState()
        }
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        MeadowPreviewPalette.gold.setStroke(); ctx.setLineWidth(5); ctx.strokePath()
        ctx.addEllipse(in: CGRect(x: c.x - r * 0.16, y: c.y - r * 0.16, width: r * 0.32, height: r * 0.32))
        MeadowPreviewPalette.gold.setFill(); ctx.fillPath()
    }
    private func draw(_ text: String, at p: CGPoint, size: CGFloat, color: UIColor = .white) {
        let s = NSAttributedString(string: text, attributes: [.font: MeadowPreviewPalette.font(size, .heavy), .foregroundColor: color])
        let b = s.size(); s.draw(at: CGPoint(x: p.x - b.width / 2, y: p.y - b.height / 2))
    }
}
