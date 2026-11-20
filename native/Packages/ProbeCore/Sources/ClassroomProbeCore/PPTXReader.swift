import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ZIPFoundation

public struct SlideRect {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}

public struct SlideRun {
    public var text: String
    public var points: Double
    public var fontName: String?
    public var bold: Bool
    public var italic: Bool
    public var color: String
}

public struct SlideParagraph {
    public var runs: [SlideRun]
    public var alignment: String
}

public enum SlideElement {
    case text(SlideRect, [SlideParagraph], fill: String?)
    case image(SlideRect, Data)
    case shape(SlideRect, kind: String, fill: String)
}

public struct ParsedSlide {
    public var partName: String
    public var width: Double
    public var height: Double
    public var background: String
    public var elements: [SlideElement]
    public var notes: String
    public var warnings: [String]
    public var plainText: String
    /// `cNvPr id` of each element (same order as `elements`), which animations refer to.
    public var elementIDs: [Int] = []
    public var build = SlideBuild()
    public var transition: PageTransitionEffect?
    /// Box styles by element index (geometry, fill, line, text anchor and insets).
    public var styles: [Int: SlideShapeStyle] = [:]
    /// A picture background (from the slide, layout or master), drawn over `background`.
    public var backgroundImage: Data?
}

public struct ParsedDeck {
    public var slides: [ParsedSlide]
}

final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""
    init(name: String, attributes: [String: String]) {
        self.name = name.split(separator: ":").last.map(String.init) ?? name
        self.attributes = attributes
    }
    func descendants(_ name: String) -> [XMLNode] {
        (self.name == name ? [self] : []) + children.flatMap { $0.descendants(name) }
    }
    func first(_ name: String) -> XMLNode? { descendants(name).first }
    func attribute(_ name: String) -> String? {
        attributes[name] ?? attributes.first(where: { $0.key.hasSuffix(":" + name) })?.value
    }
    func paragraphText() -> String {
        if name == "t" { return text }
        if name == "br" { return "\n" }
        return children.map { $0.paragraphText() }.joined()
    }
    /// A notes paragraph with its run formatting kept as light markup: **bold** and __underline__
    /// (adjacent runs with the same style are merged so the markers do not pile up).
    func formattedParagraphText() -> String {
        var segments: [(text: String, bold: Bool, underline: Bool)] = []
        for child in children {
            switch child.name {
            case "r", "fld":
                let props = child.children.first { $0.name == "rPr" }?.attributes ?? [:]
                let bold = ["1", "true"].contains(props["b"] ?? "")
                let underline = (props["u"].map { $0 != "none" }) ?? false
                let text = child.children.filter { $0.name == "t" }.map(\.text).joined()
                guard !text.isEmpty else { continue }
                if let last = segments.last, last.bold == bold, last.underline == underline { segments[segments.count - 1].text += text }
                else { segments.append((text, bold, underline)) }
            case "br": segments.append(("\n", false, false))
            default: continue
            }
        }
        return segments.map { s in
            // Keep the spaces outside the markers, so "**word** " stays well formed.
            let core = s.text.trimmingCharacters(in: .whitespaces)
            guard (s.bold || s.underline), !core.isEmpty else { return s.text }
            let lead = String(s.text.prefix { $0 == " " }), trail = String(String(s.text.reversed()).prefix { $0 == " " })
            var marked = core
            if s.bold { marked = "**" + marked + "**" }
            if s.underline { marked = "__" + marked + "__" }
            return lead + marked + trail
        }.joined()
    }
}

final class XMLTree: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        let node = XMLNode(name: qualifiedName ?? name, attributes: attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
    static func read(_ data: Data, part: String) throws -> XMLNode {
        let probe = String(decoding: data.filter { $0 != 0 }, as: UTF8.self).uppercased()
        guard !probe.contains("<!DOCTYPE"), !probe.contains("<!ENTITY") else {
            throw ProbeError("不支持DTD或XML实体：\(part)")
        }
        let delegate = XMLTree()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw ProbeError("XML解析失败：\(part)，\(parser.parserError?.localizedDescription ?? "空XML")")
        }
        return root
    }
}

/// Size limits for classroom decks (photo-heavy lesson slides are often well over 32 MiB).
public enum PPTXLimits {
    public static let fileBytes = 150 * 1024 * 1024
    public static let partBytes = 64 * 1024 * 1024
    public static let totalBytes: UInt64 = 512 * 1024 * 1024
    public static let slides = 300
    /// A JSON backup carries the deck base64-encoded.
    public static let backupBytes = 220 * 1024 * 1024
    public static var fileLabel: String { "\(fileBytes / 1024 / 1024) MiB" }
}

public enum PPTXReader {
    private struct Relationship {
        var kind: String
        var target: String
        var external: Bool
    }
    /// A slide, layout or master part with its relationships (for pictures).
    private struct Part {
        var root: XMLNode
        var links: [String: Relationship]
    }
    /// Maps a group's child coordinates onto the page (nested groups compose).
    struct GroupPlacement {
        var offsetX = 0.0, offsetY = 0.0, scaleX = 1.0, scaleY = 1.0
        func apply(_ r: SlideRect) -> SlideRect {
            SlideRect(x: offsetX + r.x * scaleX, y: offsetY + r.y * scaleY, width: r.width * scaleX, height: r.height * scaleY)
        }
        func entering(_ transform: XMLNode?) -> GroupPlacement {
            func value(_ child: String, _ key: String) -> Double? { Double(transform?.child(child)?.attributes[key] ?? "") }
            guard let x = value("off", "x"), let y = value("off", "y"), let cx = value("ext", "cx"), let cy = value("ext", "cy") else { return self }
            let chX = value("chOff", "x") ?? x, chY = value("chOff", "y") ?? y
            let chCX = value("chExt", "cx") ?? cx, chCY = value("chExt", "cy") ?? cy
            let sx = chCX > 0 ? cx / chCX : 1, sy = chCY > 0 ? cy / chCY : 1
            // child point p → group space: off + (p − chOff)·s → page: self.apply
            return GroupPlacement(offsetX: offsetX + (x - chX * sx) * scaleX, offsetY: offsetY + (y - chY * sy) * scaleY,
                                  scaleX: scaleX * sx, scaleY: scaleY * sy)
        }
    }
    /// `progress(done, total)` is called after each slide is read (from the calling thread).
    /// The cover picture PowerPoint stores in the file (docProps/thumbnail.*), for the deck list; nil if absent.
    public static func thumbnail(_ source: Data) -> Data? {
        guard let archive = try? Archive(data: source, accessMode: .read) else { return nil }
        for name in ["docProps/thumbnail.jpeg", "docProps/thumbnail.jpg", "docProps/thumbnail.png"] {
            guard let entry = archive[name], entry.type == .file, entry.uncompressedSize <= 4_000_000 else { continue }
            var result = Data()
            if (try? archive.extract(entry, consumer: { result.append($0) })) != nil, !result.isEmpty { return result }
        }
        return nil
    }
    public static func read(_ source: Data, progress: ((Int, Int) -> Void)? = nil) throws -> ParsedDeck {
        guard source.count <= PPTXLimits.fileBytes else { throw ProbeError("PPTX超过\(PPTXLimits.fileLabel)，请压缩图片后再导入。") }
        let archive = try Archive(data: source, accessMode: .read)
        let entries = Array(archive)
        let names = entries.map(\.path)
        guard entries.count <= 10_000, Set(names).count == names.count,
              entries.allSatisfy({ UInt64($0.uncompressedSize) <= UInt64(PPTXLimits.partBytes) }),
              entries.reduce(UInt64(0), { $0 + UInt64($1.uncompressedSize) }) <= PPTXLimits.totalBytes else {
            throw ProbeError("PPTX解压大小超限或包含重复部件。")
        }
        func bytes(_ name: String) throws -> Data {
            guard let entry = archive[name], entry.type == .file else { throw ProbeError("PPTX缺少部件：\(name)") }
            var result = Data()
            let checksum = try archive.extract(entry, consumer: { chunk in
                guard result.count + chunk.count <= PPTXLimits.partBytes else { throw ProbeError("PPTX部件解压超限：\(name)") }
                result.append(chunk)
            })
            guard checksum == entry.checksum, result.count == Int(entry.uncompressedSize) else {
                throw ProbeError("PPTX部件校验失败：\(name)")
            }
            return result
        }
        func xml(_ name: String) throws -> XMLNode { try XMLTree.read(bytes(name), part: name) }
        func relationships(_ owner: String) throws -> [String: Relationship] {
            let file = (owner as NSString).lastPathComponent
            let directory = (owner as NSString).deletingLastPathComponent
            let name = directory + "/_rels/" + file + ".rels"
            guard archive[name] != nil else { return [:] }
            var result: [String: Relationship] = [:]
            for node in try xml(name).descendants("Relationship") {
                guard let id = node.attributes["Id"], let rawTarget = node.attributes["Target"],
                      result[id] == nil else { throw ProbeError("无效部件关系：\(name)") }
                let external = node.attributes["TargetMode"] == "External"
                let kind = (node.attributes["Type"] ?? "").split(separator: "/").last.map(String.init) ?? ""
                let target = external ? rawTarget : try resolve(owner: owner, target: rawTarget)
                result[id] = Relationship(kind: kind, target: target, external: external)
            }
            return result
        }
        let presentationName = "ppt/presentation.xml"
        let presentation = try xml(presentationName)
        let links = try relationships(presentationName)
        guard let size = presentation.first("sldSz"),
              let width = Double(size.attributes["cx"] ?? ""),
              let height = Double(size.attributes["cy"] ?? ""),
              width.isFinite, height.isFinite, width > 0, height > 0, width / height >= 0.2, width / height <= 5 else {
            throw ProbeError("PPTX页面比例无效。")
        }
        let ids = presentation.first("sldIdLst")?.children.filter { $0.name == "sldId" } ?? []
        guard (1...PPTXLimits.slides).contains(ids.count) else { throw ProbeError("支持1—\(PPTXLimits.slides)页的PPTX。") }
        var partCache: [String: Part] = [:]
        func part(_ name: String) throws -> Part {
            if let cached = partCache[name] { return cached }
            let loaded = Part(root: try xml(name), links: try relationships(name))
            partCache[name] = loaded
            return loaded
        }
        let defaultTextStyle = presentation.child("defaultTextStyle")
        var slides: [ParsedSlide] = []
        for (index, id) in ids.enumerated() {
            let relationshipID = id.attributes.first { $0.key.hasSuffix(":id") }?.value ?? ""
            guard let link = links[relationshipID], link.kind == "slide", !link.external else {
                throw ProbeError("第\(index + 1)页关系无效。")
            }
            let slide = try xml(link.target)
            let slideLinks = try relationships(link.target)
            var notes = ""
            let noteLinks = slideLinks.values.filter { $0.kind == "notesSlide" }
            guard noteLinks.count <= 1, !noteLinks.contains(where: \.external) else {
                throw ProbeError("第\(index + 1)页备注关系无效。")
            }
            if let noteLink = noteLinks.first {
                notes = try extractNotes(xml(noteLink.target))
            }
            guard notes.count <= 40_000 else { throw ProbeError("第\(index + 1)页备注超过阶段0的40000字符限制。") }
            var warnings: [String] = []
            var elements: [SlideElement] = []
            var elementIDs: [Int] = []
            var styles: [Int: SlideShapeStyle] = [:]
            // The slide inherits from its layout, which inherits from its master; the master names the theme.
            let layoutName = slideLinks.values.first(where: { $0.kind == "slideLayout" && !$0.external })?.target
            let layout = layoutName.flatMap { try? part($0) }
            let masterName = layout?.links.values.first(where: { $0.kind == "slideMaster" && !$0.external })?.target
            let master = masterName.flatMap { try? part($0) }
            var palette = SlidePalette()
            if let themeName = master?.links.values.first(where: { $0.kind == "theme" && !$0.external })?.target,
               let theme = try? part(themeName).root { palette.load(theme: theme) }
            palette.remap(master?.root.child("clrMap"))
            palette.remap(layout?.root.child("clrMapOvr")?.child("overrideClrMapping"))
            palette.remap(slide.child("clrMapOvr")?.child("overrideClrMapping"))
            let slidePart = Part(root: slide, links: slideLinks)
            func shapes(_ p: Part?) -> [XMLNode] { p?.root.child("cSld")?.child("spTree")?.children ?? [] }
            let layoutShapes = shapes(layout), masterShapes = shapes(master)
            /// The layout and master placeholders a slide placeholder inherits position, text style and box settings from.
            func inheritedPlaceholders(_ node: XMLNode) -> [XMLNode] {
                guard let ph = node.first("ph") else { return [] }
                let type = ph.attributes["type"] ?? "body", idx = ph.attributes["idx"]
                func sameKind(_ otherType: String) -> Bool {
                    otherType == type || (["title", "ctrTitle"].contains(type) && ["title", "ctrTitle"].contains(otherType))
                        || (type == "subTitle" && otherType == "body")
                }
                func find(in list: [XMLNode], byIndex: Bool) -> XMLNode? {
                    let candidates = list.filter { $0.first("ph") != nil }
                    if byIndex, let idx, let hit = candidates.first(where: { $0.first("ph")?.attributes["idx"] == idx }) { return hit }
                    return candidates.first { sameKind($0.first("ph")?.attributes["type"] ?? "body") }
                }
                return [find(in: layoutShapes, byIndex: true), find(in: masterShapes, byIndex: false)].compactMap { $0 }
            }
            func placeholderFrame(_ node: XMLNode) -> SlideRect? {
                for candidate in inheritedPlaceholders(node) { if let f = frame(candidate) { return f } }
                // Last resort: the usual place of that kind of placeholder on the page.
                switch node.first("ph")?.attributes["type"] ?? "body" {
                case "title", "ctrTitle": return SlideRect(x: width * 0.06, y: height * 0.05, width: width * 0.88, height: height * 0.18)
                case "subTitle": return SlideRect(x: width * 0.12, y: height * 0.45, width: width * 0.76, height: height * 0.2)
                default: return SlideRect(x: width * 0.06, y: height * 0.26, width: width * 0.88, height: height * 0.66)
                }
            }
            let txStyles = master?.root.child("txStyles")
            var plainTexts: [String] = []
            func add(_ element: SlideElement, id: Int, style: SlideShapeStyle?) {
                if let style { styles[elements.count] = style }
                elements.append(element); elementIDs.append(id)
            }
            /// Draws one shape tree node. `decorative` nodes come from the layout or master (their placeholders are only
            /// templates and are skipped); `place` maps child coordinates of enclosing groups onto the page.
            func emit(_ node: XMLNode, owner: Part, place: GroupPlacement, decorative: Bool) throws {
                switch node.name {
                case "nvGrpSpPr", "grpSpPr", "extLst": return
                case "AlternateContent":
                    for child in node.child("Fallback")?.children ?? [] { try emit(child, owner: owner, place: place, decorative: decorative) }
                    return
                case "grpSp":
                    let inner = place.entering(node.child("grpSpPr")?.child("xfrm"))
                    for child in node.children { try emit(child, owner: owner, place: inner, decorative: decorative) }
                    return
                case "sp", "pic", "cxnSp": break
                default:
                    if !decorative { warnings.append("不支持对象：\(node.name)（包括表格或图表等）") }
                    return
                }
                let isPlaceholder = node.first("ph") != nil
                if decorative && isPlaceholder { return }
                let inherited = decorative ? [] : inheritedPlaceholders(node)
                guard let raw = frame(node) ?? (decorative ? nil : placeholderFrame(node)) else {
                    if !decorative { warnings.append("有对象没有位置信息，已跳过。") }
                    return
                }
                let rect = place.apply(raw)
                let shapeID = decorative ? -1 : (Int(node.first("cNvPr")?.attributes["id"] ?? "") ?? -1)
                let transform = node.first("xfrm")
                if transform?.attributes["rot"] != nil, !decorative { warnings.append("旋转效果尚未支持。") }
                if node.name == "pic" {
                    guard let imageID = node.first("blip")?.attribute("embed"),
                          let imageLink = owner.links[imageID], !imageLink.external else {
                        if !decorative { warnings.append("图片引用缺失或为外部图片；没有发起网络请求。") }
                        return
                    }
                    if node.first("srcRect").map({ !$0.attributes.isEmpty }) ?? false { warnings.append("图片裁剪尚未支持。") }
                    add(.image(rect, try bytes(imageLink.target)), id: shapeID, style: nil)
                    return
                }
                // Box: geometry, fill and line from the shape, else its placeholder, else its theme style reference.
                let properties = node.child("spPr")
                var style = SlideShapeStyle()
                let geometry = ([properties] + inherited.map { $0.child("spPr") }).lazy.compactMap { $0?.child("prstGeom") }.first
                style.kind = geometry?.attributes["prst"] ?? (properties?.child("custGeom") != nil ? "rect" : "rect")
                if properties?.child("custGeom") != nil, !decorative { warnings.append("自定义形状暂以矩形显示。") }
                style.adjust = geometry?.child("avLst")?.children.first.flatMap { gd in
                    (gd.attributes["fmla"] ?? "").split(separator: " ").last.flatMap { Double($0) } }
                style.flipH = transform?.attributes["flipH"] == "1"; style.flipV = transform?.attributes["flipV"] == "1"
                let shapeStyle = node.child("style")
                var fill: SlidePalette.Fill = .unspecified
                for candidate in [properties] + inherited.map({ $0.child("spPr") }) {
                    if case .unspecified = fill { fill = palette.fill(candidate) }
                }
                if case .colour(let c) = fill { style.fill = c }
                else if case .unspecified = fill, let ref = shapeStyle?.child("fillRef"), (Int(ref.attributes["idx"] ?? "0") ?? 0) > 0 {
                    style.fill = palette.colour(in: ref)
                }
                let lineNode = ([properties] + inherited.map { $0.child("spPr") }).lazy.compactMap { $0?.child("ln") }.first
                if let lineNode, lineNode.child("noFill") == nil {
                    style.line = palette.solid(lineNode) ?? palette.colour(in: lineNode.child("gradFill")?.child("gsLst")?.children.first)
                    if style.line == nil, let ref = shapeStyle?.child("lnRef"), (Int(ref.attributes["idx"] ?? "0") ?? 0) > 0 { style.line = palette.colour(in: ref) }
                    if let w = Double(lineNode.attributes["w"] ?? "") { style.lineWidth = w }
                } else if lineNode == nil, let ref = shapeStyle?.child("lnRef"), (Int(ref.attributes["idx"] ?? "0") ?? 0) > 0 {
                    style.line = palette.colour(in: ref)
                }
                if node.name == "cxnSp" || ["line", "straightConnector1"].contains(style.kind) { style.kind = "line"; style.fill = nil }
                let body = node.child("txBody")
                let hasText = body.map { !$0.descendants("t").map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
                guard let body, hasText else {
                    if style.fill != nil || style.line != nil {
                        add(.shape(rect, kind: style.kind, fill: style.fill ?? ""), id: shapeID, style: style)
                    } else if !decorative && !isPlaceholder && body == nil { warnings.append("无法渲染的无文字形状。") }
                    return
                }
                // Text box: anchor and insets from the shape's bodyPr, else its placeholder's.
                let bodies = [body.child("bodyPr")] + inherited.map { $0.child("txBody")?.child("bodyPr") }
                func bodyAttribute(_ name: String) -> String? { bodies.lazy.compactMap { $0?.attributes[name] }.first }
                style.anchor = bodyAttribute("anchor") ?? "t"
                style.insets = zip(["lIns", "tIns", "rIns", "bIns"], style.insets).map { Double(bodyAttribute($0) ?? "") ?? $1 }
                let autofit = bodies.lazy.compactMap { $0?.child("normAutofit") }.first
                let fontScale = (Double(autofit?.attributes["fontScale"] ?? "") ?? 100000) / 100000
                // Where run formatting comes from, nearest first.
                let type = node.first("ph")?.attributes["type"] ?? "body"
                let masterStyle = !isPlaceholder ? txStyles?.child("otherStyle")
                    : ["title", "ctrTitle"].contains(type) ? txStyles?.child("titleStyle")
                    : ["body", "subTitle", "obj", "tx"].contains(type) || node.first("ph")?.attributes["type"] == nil ? txStyles?.child("bodyStyle")
                    : txStyles?.child("otherStyle")
                let lists = [body.child("lstStyle")] + inherited.map { $0.child("txBody")?.child("lstStyle") } + [masterStyle, isPlaceholder ? nil : defaultTextStyle]
                let fontRefColour = palette.colour(in: shapeStyle?.child("fontRef"))
                let paragraphs = body.children.filter { $0.name == "p" }.map { paragraph -> SlideParagraph in
                    let pPr = paragraph.child("pPr")
                    let level = min(9, max(1, (Int(pPr?.attributes["lvl"] ?? "0") ?? 0) + 1))
                    var base = SlideTextProps()
                    base.align = pPr?.attributes["algn"]
                    base.take(run: pPr?.child("defRPr"), palette: palette)
                    base.take(level: lists[0]?.child("lvl\(level)pPr"), palette: palette)
                    if base.colour == nil { base.colour = fontRefColour }
                    for list in lists.dropFirst() { base.take(level: list?.child("lvl\(level)pPr"), palette: palette) }
                    let runs = paragraph.children.compactMap { child -> SlideRun? in
                        var props = SlideTextProps()
                        switch child.name {
                        case "br": props.take(run: child.child("rPr"), palette: palette)
                        case "r", "fld": props.take(run: child.child("rPr"), palette: palette)
                        default: return nil
                        }
                        props.size = props.size ?? base.size; props.bold = props.bold ?? base.bold; props.italic = props.italic ?? base.italic
                        props.colour = props.colour ?? base.colour; props.font = props.font ?? base.font
                        let points = min(300, max(1, (props.size ?? 18) * fontScale))
                        let text = child.name == "br" ? "\n" : child.paragraphText()
                        return SlideRun(text: text, points: points, fontName: props.font, bold: props.bold ?? false, italic: props.italic ?? false,
                                        color: props.colour ?? palette.scheme[palette.map["tx1"] ?? "dk1"] ?? "17212B")
                    }
                    return SlideParagraph(runs: runs, alignment: base.align ?? "l")
                }
                if !decorative { plainTexts.append(body.descendants("p").map { $0.paragraphText() }.joined(separator: "\n")) }
                add(.text(rect, paragraphs, fill: style.fill), id: shapeID, style: style)
            }
            // Template artwork first: the master's (unless the layout or slide hides it), then the layout's.
            let showMaster = slide.attributes["showMasterSp"] != "0" && layout?.root.attributes["showMasterSp"] != "0"
            if showMaster, let master { for node in masterShapes { try emit(node, owner: master, place: GroupPlacement(), decorative: true) } }
            if slide.attributes["showMasterSp"] != "0", let layout { for node in layoutShapes { try emit(node, owner: layout, place: GroupPlacement(), decorative: true) } }
            for node in slide.child("cSld")?.child("spTree")?.children ?? [] { try emit(node, owner: slidePart, place: GroupPlacement(), decorative: false) }
            var build = PPTXAnimations.build(slide, warnings: &warnings)
            // Effects on objects that are not drawn (tables, charts) have nothing to move.
            let known = Set(elementIDs)
            let dropped = build.all.filter { !known.contains($0.target.shapeID) }.count
            if dropped > 0 {
                warnings.append("有\(dropped)个动画作用在不支持的对象上，已跳过。")
                build.entry.removeAll { !known.contains($0.target.shapeID) }
                build.clicks = build.clicks.map { $0.filter { known.contains($0.target.shapeID) } }.filter { !$0.isEmpty }
            }
            warnings.append("基础渲染：特殊字体、复杂形状与排版需要视觉核对。")
            // Background: the slide's, else its layout's, else its master's.
            var background = "FFFFFF", backgroundImage: Data?
            for owner in [slidePart, layout, master].compactMap({ $0 }) {
                guard let bg = owner.root.child("cSld")?.child("bg") else { continue }
                if let properties = bg.child("bgPr") {
                    if case .colour(let c) = palette.fill(properties) { background = c }
                    if let id = properties.child("blipFill")?.first("blip")?.attribute("embed"), let link = owner.links[id], !link.external {
                        backgroundImage = try? bytes(link.target)
                    }
                } else if let ref = bg.child("bgRef"), let c = palette.colour(in: ref) { background = c }
                break
            }
            // A page made only of unsupported objects still keeps its place (and its notes) as a plain page.
            if elements.isEmpty && backgroundImage == nil { warnings.append("第\(index + 1)页没有可显示的对象（可能是表格或图表），显示为空白页。") }
            var parsed = ParsedSlide(partName: link.target, width: width, height: height, background: background,
                                     elements: elements, notes: notes, warnings: warnings,
                                     plainText: plainTexts.joined(separator: "\n"),
                                     elementIDs: elementIDs, build: build, transition: PPTXAnimations.transition(slide))
            parsed.styles = styles; parsed.backgroundImage = backgroundImage
            slides.append(parsed)
            progress?(slides.count, ids.count)
        }
        return ParsedDeck(slides: slides)
    }

    static func resolve(owner: String, target: String) throws -> String {
        let decoded = target.removingPercentEncoding ?? target
        guard !decoded.contains("\\"), !decoded.isEmpty else { throw ProbeError("部件路径无效。") }
        var parts = decoded.hasPrefix("/") ? [] : Array(owner.split(separator: "/").dropLast()).map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw ProbeError("部件路径越过PPTX包根目录。") }
                parts.removeLast()
            } else { parts.append(part) }
        }
        return parts.joined(separator: "/")
    }

    static func extractNotes(_ root: XMLNode) -> String {
        root.descendants("sp").compactMap { shape -> String? in
            let placeholders = shape.descendants("ph")
            if !placeholders.isEmpty && !placeholders.contains(where: { $0.attributes["type"] == "body" }) { return nil }
            let text = shape.descendants("p").map { $0.formattedParagraphText() }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.joined(separator: "\n\n")
    }

    private static func frame(_ node: XMLNode) -> SlideRect? {
        let own = node.child("spPr")?.child("xfrm") ?? node.child("grpSpPr")?.child("xfrm") ?? node.child("xfrm")
        guard let transform = own ?? node.first("xfrm"), let offset = transform.first("off"),
              let size = transform.first("ext"),
              let x = Double(offset.attributes["x"] ?? ""), let y = Double(offset.attributes["y"] ?? ""),
              let width = Double(size.attributes["cx"] ?? ""), let height = Double(size.attributes["cy"] ?? ""),
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        return SlideRect(x: x, y: y, width: width, height: height)
    }
}
