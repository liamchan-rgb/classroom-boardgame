import XCTest
import UIKit
@testable import MeadowJourney

/// 人物像素精灵：Swift 烘焙器的测试。
/// 最重要的是 testBakedAtlasesMatchWebExport：游戏里现场烘焙的图集必须和网页制作工具
/// （hd2d-walk-demo）导出、放进 Assets 的 HeroNDirections 基本一致，两端算法一旦走偏就会失败。
final class CharacterSpriteTests: XCTestCase {
    private let catalog = CharacterCatalog.shared

    func testSharedHairAndFaceDataAreBundledAndDecoded() {
        for id in ["hair_messy", "hair_neat"] { XCTAssertEqual(catalog.item(id)?.slot, .hair, id) }
        for id in ["face_round", "face_smile"] { XCTAssertEqual(catalog.item(id)?.slot, .face, id) }
        XCTAssertEqual(catalog.item("hair_messy")?.variants.map(\.id).contains("blonde"), true)
        XCTAssertEqual(catalog.item("face_round")?.variants.map(\.id).contains("amber"), true)
    }

    func testEveryPresetBuildsAndMissingItemsAreReported() {
        for preset in CharacterCatalog.characters {
            XCTAssertNoThrow(try catalog.equipment(for: preset), preset.id)
        }
        var broken = CharacterCatalog.characters[0]
        broken.hair = "hair_missing"
        XCTAssertThrowsError(try catalog.equipment(for: broken))
    }

    func testAtlasUsesTheGameFormat() throws {
        let eq = try catalog.equipment(for: CharacterCatalog.characters[0])
        let atlas = try XCTUnwrap(SpriteBaker.atlas(eq))
        XCTAssertEqual(atlas.width, 1536)
        XCTAssertEqual(atlas.height, 1536)
        XCTAssertEqual(Rig.sprW, 42)
        XCTAssertEqual(Rig.sprH, 62)
        let sheet = try XCTUnwrap(SpriteBaker.sheet(eq))
        XCTAssertEqual(sheet.width, 42 * 8)
        XCTAssertEqual(sheet.height, 62 * 5)
    }

    func testSwappingHairFaceAndSkinChangesTheSprite() throws {
        let base = CharacterCatalog.characters[0]
        var swapped = base
        swapped.hair = "hair_neat"
        swapped.face = "face_smile"
        swapped.skin = "deep"
        let a = try XCTUnwrap(SpriteBaker.atlas(try catalog.equipment(for: base)))
        let b = try XCTUnwrap(SpriteBaker.atlas(try catalog.equipment(for: swapped)))
        XCTAssertGreaterThan(Self.difference(Self.rgba(a), Self.rgba(b)).mismatched, 500)
    }

    func testBakedAtlasesMatchWebExport() throws {
        for (index, preset) in CharacterCatalog.characters.enumerated() {
            let baked = try XCTUnwrap(SpriteBaker.atlas(try catalog.equipment(for: preset)))
            let exported = try XCTUnwrap(UIImage(named: "Hero\(index + 1)Directions")?.cgImage)
            let diff = Self.difference(Self.rgba(baked), Self.rgba(exported))
            print("[character-parity] \(preset.id): \(diff.mismatched) / \(diff.opaque) pixels differ from the web export")
            let attachment = XCTAttachment(image: UIImage(cgImage: baked))
            attachment.name = "baked-\(preset.id)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // 两端浮点数学函数在最后一位上可能有出入，允许极少数像素落到相邻的明暗阶
            XCTAssertLessThan(Double(diff.mismatched), Double(diff.opaque) * 0.02,
                              "\(preset.id): \(diff.mismatched) / \(diff.opaque) 个像素与网页端导出不一致")
        }
    }

    // MARK: - 工具

    private static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        out.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    /// 不一致的像素：透明度不同，或任一通道相差超过 6
    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> (mismatched: Int, opaque: Int) {
        var mismatched = 0, opaque = 0
        for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
            if a[i + 3] > 0 || b[i + 3] > 0 { opaque += 1 }
            let alphaDiffers = (a[i + 3] > 127) != (b[i + 3] > 127)
            let colorDiffers = abs(Int(a[i]) - Int(b[i])) > 6 || abs(Int(a[i + 1]) - Int(b[i + 1])) > 6
                || abs(Int(a[i + 2]) - Int(b[i + 2])) > 6
            if alphaDiffers || (a[i + 3] > 127 && colorDiffers) { mismatched += 1 }
        }
        return (mismatched, opaque)
    }
}
