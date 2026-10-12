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

public enum PPTXReader {
    private struct Relationship {
        var kind: String
        var target: String
        var external: Bool
    }
    public static func read(_ source: Data) throws -> ParsedDeck {
        guard source.count <= 32 * 1024 * 1024 else { throw ProbeError("阶段0支持最多32 MiB的PPTX。") }
        let archive = try Archive(data: source, accessMode: .read)
        let entries = Array(archive)
        let names = entries.map(\.path)
        guard entries.count <= 10_000, Set(names).count == names.count,
              entries.allSatisfy({ UInt64($0.uncompressedSize) <= 16 * 1024 * 1024 }),
              entries.reduce(UInt64(0), { $0 + UInt64($1.uncompressedSize) }) <= 128 * 1024 * 1024 else {
            throw ProbeError("PPTX解压大小超限或包含重复部件。")
        }
        func bytes(_ name: String) throws -> Data {
            guard let entry = archive[name], entry.type == .file else { throw ProbeError("PPTX缺少部件：\(name)") }
            var result = Data()
            let checksum = try archive.extract(entry, consumer: { chunk in
                guard result.count + chunk.count <= 16 * 1024 * 1024 else { throw ProbeError("PPTX部件解压超限：\(name)") }
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
        guard (1...60).contains(ids.count) else { throw ProbeError("阶段0支持1—60页PPTX。") }
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
            var plainTexts: [String] = []
            let tree = slide.first("spTree")
            for node in tree?.children ?? [] {
                if node.name == "nvGrpSpPr" || node.name == "grpSpPr" { continue }
                guard node.name == "sp" || node.name == "pic" else {
                    warnings.append("不支持对象：\(node.name)（包括组合、表格或图表等）")
                    continue
                }
                guard let frame = frame(node) else {
                    warnings.append("对象没有直接定位，母版／布局继承尚未支持。")
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
            guard !elements.isEmpty else { throw ProbeError("第\(index + 1)页没有可渲染内容。\(warnings.joined(separator: "；"))") }
            slides.append(ParsedSlide(partName: link.target, width: width, height: height, background: background,
                                      elements: elements, notes: notes, warnings: warnings,
                                      plainText: plainTexts.joined(separator: "\n")))
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
