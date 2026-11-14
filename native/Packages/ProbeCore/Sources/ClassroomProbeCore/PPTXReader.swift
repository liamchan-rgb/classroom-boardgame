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
    /// `progress(done, total)` is called after each slide is read (from the calling thread).
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
            // Placeholders (title, body, subtitle...) usually carry no position on the slide itself: it is inherited from
            // the slide layout, then the master. Resolve it there instead of dropping the text.
            var inherited: [XMLNode] = []
            if let layout = slideLinks.values.first(where: { $0.kind == "slideLayout" && !$0.external }) {
                if let tree = try? xml(layout.target).first("spTree") { inherited += tree.children }
                if let master = (try? relationships(layout.target))?.values.first(where: { $0.kind == "slideMaster" && !$0.external }),
                   let tree = try? xml(master.target).first("spTree") { inherited += tree.children }
            }
            func placeholderFrame(_ node: XMLNode) -> SlideRect? {
                guard let ph = node.first("ph") else { return nil }
                let type = ph.attributes["type"] ?? "body", idx = ph.attributes["idx"]
                func matches(_ other: XMLNode) -> Bool {
                    guard let o = other.first("ph") else { return false }
                    if let idx, o.attributes["idx"] == idx { return true }
                    let otherType = o.attributes["type"] ?? "body"
                    return otherType == type || (["title", "ctrTitle"].contains(type) && ["title", "ctrTitle"].contains(otherType))
                }
                for candidate in inherited where matches(candidate) { if let f = frame(candidate) { return f } }
                // Last resort: the usual place of that kind of placeholder on the page.
                switch type {
                case "title", "ctrTitle": return SlideRect(x: width * 0.06, y: height * 0.05, width: width * 0.88, height: height * 0.18)
                case "subTitle": return SlideRect(x: width * 0.12, y: height * 0.45, width: width * 0.76, height: height * 0.2)
                default: return SlideRect(x: width * 0.06, y: height * 0.26, width: width * 0.88, height: height * 0.66)
                }
            }
            var plainTexts: [String] = []
            let tree = slide.first("spTree")
            for node in tree?.children ?? [] {
                if node.name == "nvGrpSpPr" || node.name == "grpSpPr" { continue }
                guard node.name == "sp" || node.name == "pic" else {
                    warnings.append("不支持对象：\(node.name)（包括组合、表格或图表等）")
                    continue
                }
                guard let frame = frame(node) ?? placeholderFrame(node) else {
                    warnings.append("有对象没有位置信息，已跳过。")
                    continue
                }
                if let transform = node.first("xfrm"), transform.attributes["rot"] != nil {
                    warnings.append("旋转／翻转效果尚未支持。")
                }
                if node.name == "pic" {
                    guard let imageID = node.first("blip")?.attribute("embed"),
                          let imageLink = slideLinks[imageID], !imageLink.external else {
                        warnings.append("图片引用缺失或为外部图片；没有发起网络请求。")
                        continue
                    }
                    if node.first("srcRect") != nil { warnings.append("图片裁剪尚未支持。") }
                    elements.append(.image(frame, try bytes(imageLink.target)))
                } else {
                    let fill = node.first("spPr")?.first("solidFill")?.first("srgbClr")?.attributes["val"]
                    if let body = node.first("txBody") {
                        let paragraphs = body.children.filter { $0.name == "p" }.map { paragraph -> SlideParagraph in
                            let alignment = paragraph.first("pPr")?.attributes["algn"] ?? "l"
                            let runs = paragraph.children.compactMap { child -> SlideRun? in
                                if child.name == "br" {
                                    return SlideRun(text: "\n", points: 18, fontName: nil, bold: false, italic: false, color: "17212B")
                                }
                                guard child.name == "r" || child.name == "fld" else { return nil }
                                let properties = child.first("rPr")
                                let points = Double(properties?.attributes["sz"] ?? "1800") ?? 1800
                                return SlideRun(text: child.paragraphText(), points: min(300, max(1, points / 100)),
                                                fontName: properties?.first("latin")?.attributes["typeface"],
                                                bold: properties?.attributes["b"] == "1", italic: properties?.attributes["i"] == "1",
                                                color: properties?.first("srgbClr")?.attributes["val"] ?? "17212B")
                            }
                            return SlideParagraph(runs: runs, alignment: alignment)
                        }
                        plainTexts.append(body.descendants("p").map { $0.paragraphText() }.joined(separator: "\n"))
                        elements.append(.text(frame, paragraphs, fill: fill))
                    } else if let fill {
                        let kind = node.first("prstGeom")?.attributes["prst"] ?? "rect"
                        if kind != "rect" && kind != "ellipse" { warnings.append("\(kind)形状暂以矩形显示。") }
                        elements.append(.shape(frame, kind: kind, fill: fill))
                    } else { warnings.append("无法渲染的无文字形状。") }
                }
            }
            if slide.first("timing") != nil { warnings.append("动画被忽略；只支持静态页。") }
            warnings.append("阶段0基础渲染：母版、主题、字体替换和复杂排版需要视觉核对。")
            let background = slide.first("bg")?.first("srgbClr")?.attributes["val"] ?? "FFFFFF"
            // A page made only of unsupported objects still keeps its place (and its notes) as a plain page.
            if elements.isEmpty { warnings.append("第\(index + 1)页没有可显示的对象（可能是组合、表格或图表），显示为空白页。") }
            slides.append(ParsedSlide(partName: link.target, width: width, height: height, background: background,
                                      elements: elements, notes: notes, warnings: warnings,
                                      plainText: plainTexts.joined(separator: "\n")))
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
            let text = shape.descendants("p").map { $0.paragraphText() }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.joined(separator: "\n\n")
    }

    private static func frame(_ node: XMLNode) -> SlideRect? {
        guard let transform = node.first("xfrm"), let offset = transform.first("off"),
              let size = transform.first("ext"),
              let x = Double(offset.attributes["x"] ?? ""), let y = Double(offset.attributes["y"] ?? ""),
              let width = Double(size.attributes["cx"] ?? ""), let height = Double(size.attributes["cy"] ?? ""),
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        return SlideRect(x: x, y: y, width: width, height: height)
    }
}
