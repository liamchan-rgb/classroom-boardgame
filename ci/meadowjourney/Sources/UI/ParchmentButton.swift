import UIKit

/// Compact parchment and bronze controls echo the reference artwork.
final class ParchmentButton: UIButton {
    enum Symbol { case title, play, reset, zoom }
    private let symbol: Symbol
    var isPlaying = false { didSet { setNeedsDisplay() } }

    init(symbol: Symbol) {
        self.symbol = symbol
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 1, height: 2)
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.75 : 1 } }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -5, dy: -5).contains(point)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let box = bounds.insetBy(dx: 4, dy: 4)
        let cut: CGFloat = 5
        let path = UIBezierPath()
        path.move(to: CGPoint(x: box.minX + cut, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - cut, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + cut))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - cut))
        path.addLine(to: CGPoint(x: box.maxX - cut, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX + cut, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY - cut))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + cut))
        path.close()
        context.saveGState()
        path.addClip()
        let colors = [UIColor(red: 1, green: 0.95, blue: 0.78, alpha: 1).cgColor,
                      UIColor(red: 0.84, green: 0.75, blue: 0.56, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY),
                                       end: CGPoint(x: box.midX, y: box.maxY), options: [])
        }
        context.restoreGState()
        let ink = UIColor(red: 0.30, green: 0.24, blue: 0.16, alpha: 1)
        ink.setStroke()
        path.lineWidth = 2
        path.stroke()
        let inner = UIBezierPath(roundedRect: box.insetBy(dx: 3, dy: 3), cornerRadius: 2)
        UIColor(red: 0.58, green: 0.45, blue: 0.28, alpha: 0.55).setStroke()
        inner.lineWidth = 0.6
        inner.stroke()
        ink.setFill()
        ink.setStroke()
        let center = CGPoint(x: box.midX, y: box.midY)
        if symbol != .title {
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: 0.75, y: 0.75)
            context.translateBy(x: -center.x, y: -center.y)
        }
        switch symbol {
        case .title:
            let text = "安然" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "SongtiSC-Bold", size: 17) ?? UIFont.boldSystemFont(ofSize: 17),
                .foregroundColor: ink
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
            for x in [box.minX + 4, box.maxX - 4] {
                for y in [box.minY + 4, box.maxY - 4] {
                    UIBezierPath(ovalIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
                }
            }
        case .play:
            if isPlaying {
                UIBezierPath(rect: CGRect(x: center.x - 5, y: center.y - 7, width: 3, height: 14)).fill()
                UIBezierPath(rect: CGRect(x: center.x + 2, y: center.y - 7, width: 3, height: 14)).fill()
            } else {
                let triangle = UIBezierPath()
                triangle.move(to: CGPoint(x: center.x - 5, y: center.y - 8))
                triangle.addLine(to: CGPoint(x: center.x + 7, y: center.y))
                triangle.addLine(to: CGPoint(x: center.x - 5, y: center.y + 8))
                triangle.close()
                UIColor(red: 0.63, green: 0.45, blue: 0.25, alpha: 0.65).setFill()
                triangle.fill()
                triangle.lineWidth = 1.4
                triangle.stroke()
            }
        case .reset:
            let arc = UIBezierPath(arcCenter: center, radius: 7, startAngle: -.pi / 4,
                                   endAngle: .pi * 1.45, clockwise: true)
            arc.lineWidth = 1.8
            arc.stroke()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: center.x + 8, y: center.y - 8))
            arrow.addLine(to: CGPoint(x: center.x + 8, y: center.y - 2))
            arrow.addLine(to: CGPoint(x: center.x + 2, y: center.y - 2))
            arrow.lineWidth = 1.8
            arrow.stroke()
        case .zoom:
            let plus = UIBezierPath()
            plus.move(to: CGPoint(x: center.x - 7, y: center.y))
            plus.addLine(to: CGPoint(x: center.x + 7, y: center.y))
            plus.move(to: CGPoint(x: center.x, y: center.y - 7))
            plus.addLine(to: CGPoint(x: center.x, y: center.y + 7))
            plus.lineWidth = 1.8
            plus.stroke()
        }
    }
}

