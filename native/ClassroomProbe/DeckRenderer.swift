import UIKit
import ImageIO
import ClassroomProbeCore

/// Renders one slide to a 1280-wide picture. Thread-safe (UIGraphicsImageRenderer / text drawing), so imports can
/// render the first page in the background.
enum DeckRenderer {
    struct Result {
        var page: DeckPage
        var warnings: [String]
    }

    static func render(_ slide: ParsedSlide) throws -> Result {
        let width: CGFloat = 1280
        let scale = width / CGFloat(slide.width)
        let size = CGSize(width: width, height: CGFloat(slide.height) * scale)
        var warnings = slide.warnings
        // Decode each picture once, downsampled to what the page needs: huge photos no longer fail the import, and
        // formats iOS cannot draw (EMF/WMF from Office) are skipped with a note instead of rejecting the whole deck.
        var pictures: [Int: UIImage] = [:]
        for (index, element) in slide.elements.enumerated() {
            guard case .image(let frame, let data) = element else { continue }
            let longest = max(CGFloat(frame.width), CGFloat(frame.height)) * scale
            if let picture = downsampled(data, maxPixels: max(64, min(2560, longest * 2))) { pictures[index] = picture }
            else { warnings.append("有图片格式不支持（例如 EMF/WMF 矢量图），已跳过。") }
        }
        func rectangle(_ frame: SlideRect) -> CGRect {
            CGRect(x: CGFloat(frame.x) * scale, y: CGFloat(frame.y) * scale,
                   width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
        }
        func frameOf(_ element: SlideElement) -> CGRect {
            switch element { case .image(let f, _), .shape(let f, _, _), .text(let f, _, _): return rectangle(f) }
        }
        /// Draws element `index`; for text, `paragraphs` limits which paragraphs show (the others keep their place,
        /// drawn clear) and `fill` whether the box background is drawn.
        func draw(_ index: Int, in context: UIGraphicsImageRendererContext, paragraphs: Set<Int>? = nil, fill drawFill: Bool = true) {
            switch slide.elements[index] {
            case .image(let frame, _):
                pictures[index]?.draw(in: rectangle(frame))
            case .shape(let frame, let kind, let fill):
                color(fill).setFill()
                let path = kind == "ellipse" ? UIBezierPath(ovalIn: rectangle(frame)) : UIBezierPath(rect: rectangle(frame))
                path.fill()
            case .text(let frame, let list, let fill):
                let rect = rectangle(frame)
                if let fill, drawFill { color(fill).setFill(); context.fill(rect) }
                let text = NSMutableAttributedString(string: "")
                for (index, paragraph) in list.enumerated() {
                    let style = NSMutableParagraphStyle()
                    style.alignment = paragraph.alignment == "ctr" ? .center : paragraph.alignment == "r" ? .right : .left
                    let shown = paragraphs?.contains(index) ?? true
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
                            .font: font, .foregroundColor: shown ? color(run.color) : UIColor.clear, .paragraphStyle: style
                        ]))
                    }
                    if index < list.count - 1 { text.append(NSAttributedString(string: "\n")) }
                }
                let inset = CGFloat(91440) * scale
                let box = rect.insetBy(dx: inset, dy: inset / 2)
                let measured = text.boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                if measured.height > box.height + 2, paragraphs == nil { warnings.append("文字可能超出文本框，需视觉核对。") }
                context.cgContext.saveGState()
                context.cgContext.clip(to: box)
                text.draw(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                context.cgContext.restoreGState()
            }
        }
        // Which elements (or which of their paragraphs) animations move. A whole-shape effect takes the whole shape.
        let effects = slide.build.all
        var whole = Set<Int>(), paragraphGroups: [Int: [ClosedRange<Int>]] = [:]
        for effect in effects {
            guard let index = slide.elementIDs.firstIndex(of: effect.target.shapeID) else { continue }
            if let range = effect.target.paragraphs, case .text(_, let list, _) = slide.elements[index] {
                let clamped = range.lowerBound...min(range.upperBound, max(range.lowerBound, list.count - 1))
                if !(paragraphGroups[index]?.contains(clamped) ?? false) { paragraphGroups[index, default: []].append(clamped) }
            } else { whole.insert(index) }
        }
        for index in whole { paragraphGroups[index] = nil }
        // Pieces in drawing order: runs of still elements merge into one full-page picture; each animated part is
        // its own picture cropped to its box, so the display can move it.
        enum Item { case still(Int, Set<Int>?, Bool), layer(Int, Set<Int>?, Bool, DeckLayerKey) }
        var items: [Item] = []
        for index in slide.elements.indices {
            if whole.contains(index) { items.append(.layer(index, nil, true, DeckLayerKey(element: index, paragraphs: nil))); continue }
            guard let groups = paragraphGroups[index], case .text(_, let list, _) = slide.elements[index] else { items.append(.still(index, nil, true)); continue }
            let moving = Set(groups.flatMap { Array($0) })
            items.append(.still(index, Set(list.indices).subtracting(moving), true))
            // Overlapping ranges: each paragraph goes to the first group that names it.
            var taken = Set<Int>()
            for group in groups {
                let own = Set(group).subtracting(taken); taken.formUnion(own)
                items.append(.layer(index, own, false, DeckLayerKey(element: index, paragraphs: group)))
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var pieces: [DeckPiece] = [], layers: [DeckLayer] = []
        var pending: [Item] = []
        func flushStill() {
            guard !pending.isEmpty || pieces.isEmpty else { return }
            let first = pieces.isEmpty
            format.opaque = first
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                if first { color(slide.background).setFill(); context.fill(CGRect(origin: .zero, size: size)) }
                for item in pending { if case .still(let i, let p, let f) = item { draw(i, in: context, paragraphs: p, fill: f) } }
            }
            pieces.append(.still(image)); pending = []
        }
        for item in items {
            guard case .layer(let index, let paragraphs, let fill, let key) = item else { pending.append(item); continue }
            flushStill()
            let box = frameOf(slide.elements[index]).integral
            guard box.width >= 1, box.height >= 1 else { continue }
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: box.size, format: format).image { context in
                context.cgContext.translateBy(x: -box.minX, y: -box.minY)
                draw(index, in: context, paragraphs: paragraphs, fill: fill)
            }
            pieces.append(.layer(layers.count)); layers.append(DeckLayer(key: key, image: image, frame: box))
        }
        flushStill()
        func layerIndex(_ effect: SlideEffect) -> Int? {
            guard let element = slide.elementIDs.firstIndex(of: effect.target.shapeID) else { return nil }
            if whole.contains(element) { return layers.firstIndex { $0.key.element == element && $0.key.paragraphs == nil } }
            guard let range = effect.target.paragraphs, case .text(_, let list, _) = slide.elements[element] else { return nil }
            let clamped = range.lowerBound...min(range.upperBound, max(range.lowerBound, list.count - 1))
            return layers.firstIndex { $0.key.element == element && $0.key.paragraphs == clamped }
        }
        func steps(_ list: [SlideEffect]) -> [DeckStep] { list.compactMap { e in layerIndex(e).map { DeckStep(layer: $0, effect: e) } } }
        let clicks = slide.build.clicks.map(steps).filter { !$0.isEmpty }
        let page = DeckPage(size: size, background: color(slide.background), pieces: pieces, layers: layers,
                            entry: steps(slide.build.entry), clicks: clicks, transition: slide.transition)
        return Result(page: page, warnings: Array(Set(warnings)).sorted())
    }

    private static func downsampled(_ data: Data, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: Int(maxPixels)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    static func color(_ hex: String) -> UIColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
