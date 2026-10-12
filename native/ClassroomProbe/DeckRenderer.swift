import UIKit
import ClassroomProbeCore

@MainActor
enum DeckRenderer {
    struct Result {
        var image: UIImage
        var warnings: [String]
    }

    static func render(_ slide: ParsedSlide) throws -> Result {
        let width: CGFloat = 1280
        let scale = width / CGFloat(slide.width)
        let size = CGSize(width: width, height: CGFloat(slide.height) * scale)
        var warnings = slide.warnings
        for element in slide.elements {
            if case .image(_, let data) = element {
                guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0,
                      image.size.width * image.size.height <= 32_000_000 else {
                    throw ProbeError("图片格式不支持或图片像素数超限。")
                }
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color(slide.background).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            func rectangle(_ frame: SlideRect) -> CGRect {
                CGRect(x: CGFloat(frame.x) * scale, y: CGFloat(frame.y) * scale,
                       width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
            }
            for element in slide.elements {
                switch element {
                case .image(let frame, let bytes):
                    UIImage(data: bytes)?.draw(in: rectangle(frame))
                case .shape(let frame, let kind, let fill):
                    color(fill).setFill()
                    let path = kind == "ellipse" ? UIBezierPath(ovalIn: rectangle(frame)) : UIBezierPath(rect: rectangle(frame))
                    path.fill()
                case .text(let frame, let paragraphs, let fill):
                    let rect = rectangle(frame)
                    if let fill { color(fill).setFill(); context.fill(rect) }
                    let text = NSMutableAttributedString(string: "")
                    for (index, paragraph) in paragraphs.enumerated() {
                        let style = NSMutableParagraphStyle()
                        style.alignment = paragraph.alignment == "ctr" ? .center : paragraph.alignment == "r" ? .right : .left
                        for run in paragraph.runs {
                            let points = CGFloat(run.points) * scale * 914400 / 72
                            var font = UIFont.systemFont(ofSize: points)
                            if let name = run.fontName, let requested = UIFont(name: name, size: points) { font = requested }
                            else if let name = run.fontName { warnings.append("字体\(name)不可用，使用系统字体。") }
                            var traits: UIFontDescriptor.SymbolicTraits = []
                            if run.bold { traits.insert(.traitBold) }
                            if run.italic { traits.insert(.traitItalic) }
                            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: descriptor, size: points) }
                            text.append(NSAttributedString(string: run.text, attributes: [
                                .font: font, .foregroundColor: color(run.color), .paragraphStyle: style
                            ]))
                        }
                        if index < paragraphs.count - 1 { text.append(NSAttributedString(string: "\n")) }
                    }
                    let inset = CGFloat(91440) * scale
                    let box = rect.insetBy(dx: inset, dy: inset / 2)
                    let measured = text.boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    if measured.height > box.height + 2 { warnings.append("文字可能超出文本框，需视觉核对。") }
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: box)
                    text.draw(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    context.cgContext.restoreGState()
                }
            }
        }
        return Result(image: image, warnings: Array(Set(warnings)).sorted())
    }

    private static func color(_ hex: String) -> UIColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
