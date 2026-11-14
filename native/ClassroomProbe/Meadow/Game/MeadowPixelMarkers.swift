import SpriteKit
import UIKit

/// Pixel-art badges that float and turn above map nodes (in place of the old Chinese-character markers).
/// Each icon is a 12×12 pixel grid drawn at an integer scale with nearest filtering, so it stays crisp.
enum MeadowPixelMarker: String {
    case combat, boss, reward, empty, shop, spring, event, quiz, done, camp, unknown

    /// From the marker text the map already computes ("战" "首" "奖" "空" "商" "泉" "事" "题" "✓").
    init(symbol: String) {
        switch symbol {
        case "战": self = .combat; case "首": self = .boss; case "奖": self = .reward; case "空": self = .empty
        case "商": self = .shop; case "泉": self = .spring; case "事": self = .event; case "题": self = .quiz; case "✓": self = .done
        default: self = .unknown
        }
    }

    private static let palette: [Character: UIColor] = [
        "k": UIColor(red: 0.13, green: 0.10, blue: 0.09, alpha: 1),   // outline
        "w": UIColor(red: 0.96, green: 0.95, blue: 0.90, alpha: 1),   // white
        "s": UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1),   // steel
        "S": UIColor(red: 0.46, green: 0.52, blue: 0.58, alpha: 1),   // steel shade
        "b": UIColor(red: 0.55, green: 0.33, blue: 0.18, alpha: 1),   // wood / leather
        "B": UIColor(red: 0.36, green: 0.21, blue: 0.11, alpha: 1),   // dark wood
        "y": UIColor(red: 0.98, green: 0.80, blue: 0.27, alpha: 1),   // gold
        "Y": UIColor(red: 0.78, green: 0.55, blue: 0.13, alpha: 1),   // gold shade
        "r": UIColor(red: 0.89, green: 0.27, blue: 0.24, alpha: 1),   // red
        "R": UIColor(red: 0.60, green: 0.13, blue: 0.15, alpha: 1),   // dark red
        "c": UIColor(red: 0.45, green: 0.80, blue: 0.98, alpha: 1),   // water light
        "C": UIColor(red: 0.18, green: 0.48, blue: 0.86, alpha: 1),   // water
        "g": UIColor(red: 0.47, green: 0.84, blue: 0.43, alpha: 1),   // green
        "G": UIColor(red: 0.20, green: 0.55, blue: 0.27, alpha: 1),   // dark green
        "p": UIColor(red: 0.70, green: 0.50, blue: 0.95, alpha: 1),   // purple
        "P": UIColor(red: 0.42, green: 0.27, blue: 0.70, alpha: 1),   // dark purple
    ]

    private var grid: [String] {
        switch self {
        case .combat: return [   // crossed swords
            "kk........kk", "ksk......ksk", ".ksk....ksk.", "..ksk..ksk..", "...kskksk...", "....kssk....",
            "....kssk....", "...kSkkSk...", "..kbbk.kbbk.", ".kybk...kbyk", ".kkk.....kkk", "............"]
        case .boss: return [     // crown
            "............", ".k...kk...k.", "kyk.kyyk.kyk", "kyykyyyykyyk", "kyyyyrryyyyk", "kyyyyrryyyyk",
            "kyYyyyyyyYyk", "kyyyYyyYyyyk", "kYYYYYYYYYYk", "kyyrYyyYryyk", "kkkkkkkkkkkk", "............"]
        case .reward: return [   // treasure chest
            "............", "..kkkkkkkk..", ".kbbbbbbbbk.", "kbbBbbbbBbbk", "kyyyyyyyyyyk", "kbbbbkkbbbbk",
            "kbbbbkykbbbk", "kbbbbkkbbbbk", "kBbbbbbbbbBk", "kBBBBBBBBBBk", "kkkkkkkkkkkk", "............"]
        case .shop: return [     // gold coin
            "....kkkk....", "..kkyyyykk..", ".kyyyYYyyyk.", ".kyyYyyYyyk.", "kyyyYyyyyyyk", "kyyyyYYyyyyk",
            "kyyyyyyYyyyk", "kyyyYyyYyyyk", ".kyyyYYyyyk.", ".kYyyyyyyYk.", "..kkYYYYkk..", "....kkkk...."]
        case .spring: return [   // water drop
            ".....kk.....", "....kcck....", "....kcck....", "...kcccck...", "..kcwccCck..", "..kcwcccCk..",
            ".kccccccCCk.", ".kcccccCCCk.", ".kCcccCCCCk.", "..kCCCCCCk..", "...kkkkkk...", "............"]
        case .event: return [    // exclamation
            "....kkkk....", "....kyyk....", "....kyyk....", "....kyyk....", "....kyyk....", "....kyyk....",
            "....kYYk....", ".....kk.....", "....kkkk....", "....kyyk....", "....kkkk....", "............"]
        case .quiz: return [     // question bubble
            "..kkkkkkkk..", ".kppppppppk.", "kpppwwwwpppk", "kppwkppkwppk", "kpppppkwwppk", "kppppkwwpppk",
            "kppppkwkpppk", "kpppppppPppk", ".kPppkwkPPk.", "..kkk.kkkk..", "...kk.......", "............"]
        case .done: return [     // check mark
            "............", "..........kk", ".........kgk", "........kggk", "kk.....kggk.", "kgk...kggk..",
            "kggk.kggk...", ".kggkggk....", "..kgggGk....", "...kGGk.....", "....kk......", "............"]
        case .empty: return [    // leaf sprout
            "............", ".......kkk..", "......kgggk.", ".....kggGgk.", "..kk.kgGggk.", ".kggkkGggk..",
            ".kgGgkkkk...", "..kgGgk.....", "...kkkGk....", "......kGk...", ".....kkkkk..", "............"]
        case .camp: return [     // flag on a pole
            "..kk........", "..kwkkkk....", "..kwrrrrkk..", "..kwrrrrrrk.", "..kwrrrrkk..", "..kwkkkk....",
            "..kwk.......", "..kwk.......", "..kwk.......", ".kkwkk......", "kbbbbbk.....", "kkkkkkk....."]
        case .unknown: return [
            "............", "...kkkkkk...", "..kwwwwwwk..", "..kwkkkkwk..", "......kwwk..", ".....kwwk...",
            ".....kwk....", ".....kkk....", ".....kwk....", ".....kkk....", "............", "............"]
        }
    }

    private static var cache: [MeadowPixelMarker: SKTexture] = [:]
    var texture: SKTexture {
        if let hit = Self.cache[self] { return hit }
        // The icon sits on a round pixel badge (dark face, gold rim) so it reads as a map marker, never as scenery.
        let rows = grid, scale = 3, plate = 18, inset = 3
        let face = UIColor(red: 0.12, green: 0.15, blue: 0.13, alpha: 0.92), rim = UIColor(red: 0.93, green: 0.76, blue: 0.38, alpha: 1)
        let rimShade = UIColor(red: 0.55, green: 0.40, blue: 0.16, alpha: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: plate * scale, height: plate * scale), format: format).image { ctx in
            let c = Double(plate - 1) / 2
            for y in 0..<plate {
                for x in 0..<plate {
                    let d = ((Double(x) - c) * (Double(x) - c) + (Double(y) - c) * (Double(y) - c)).squareRoot()
                    guard d <= c + 0.5 else { continue }
                    (d > c - 0.8 ? (y > plate / 2 ? rimShade : rim) : face).setFill()
                    ctx.fill(CGRect(x: x * scale, y: y * scale, width: scale, height: scale))
                }
            }
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let color = Self.palette[ch] else { continue }
                    color.setFill(); ctx.fill(CGRect(x: (x + inset) * scale, y: (y + inset) * scale, width: scale, height: scale))
                }
            }
        }
        let texture = SKTexture(image: image); texture.filteringMode = .nearest
        Self.cache[self] = texture
        return texture
    }
}

extension SKNode {
    /// Gives a map node a floating, turning pixel icon (once); later calls only swap the picture.
    func setPixelMarker(_ marker: MeadowPixelMarker) {
        // Plain empty ground carries no marker; finished places keep a small, still, dimmer badge.
        let hidden = marker == .empty, settled = marker == .done
        for child in children where child.userData?["marker"] != nil || child.name == "pixel-shadow" { child.isHidden = hidden }
        if let icon = children.first(where: { $0.userData?["marker"] != nil }) as? SKSpriteNode {
            if icon.userData?["marker"] as? String != marker.rawValue {
                icon.texture = marker.texture; icon.userData = NSMutableDictionary(dictionary: ["marker": marker.rawValue])
                icon.alpha = settled ? 0.7 : 1; icon.setScale(settled ? 0.75 : 1)
                if !settled { icon.run(.sequence([.scale(to: 1.3, duration: 0.12), .scale(to: 1, duration: 0.22)])) }
            }
            return
        }
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 20, height: 6))
        shadow.fillColor = SKColor(white: 0, alpha: 0.28); shadow.strokeColor = .clear; shadow.position = CGPoint(x: 0, y: -18); shadow.name = "pixel-shadow"; shadow.isHidden = hidden
        addChild(shadow)
        let icon = SKSpriteNode(texture: marker.texture, size: CGSize(width: 32, height: 32))
        icon.name = name; icon.userData = NSMutableDictionary(dictionary: ["marker": marker.rawValue])
        icon.isHidden = hidden; if settled { icon.alpha = 0.7; icon.setScale(0.75) }
        addChild(icon)
        // Float up and down, and turn like a coin (the width breathes through a cosine, never quite to zero).
        let phase = CGFloat.random(in: 0..<(2 * .pi))
        func still(_ node: SKNode) -> Bool { (node.userData?["marker"] as? String) == MeadowPixelMarker.done.rawValue }
        let bob = SKAction.customAction(withDuration: 2.6) { node, t in node.position.y = still(node) ? 0 : 3 + 3 * sin(2 * .pi * t / 2.6 + phase) }
        let turn = SKAction.customAction(withDuration: 3.2) { node, t in
            guard let sprite = node as? SKSpriteNode else { return }
            if still(node) { sprite.xScale = 0.75; sprite.yScale = 0.75; return }
            let c = cos(2 * .pi * t / 3.2 + phase); sprite.xScale = max(0.18, abs(c)) * (c < 0 ? -1 : 1); sprite.yScale = 1
        }
        icon.run(.repeatForever(.group([bob, turn])))
        shadow.run(.repeatForever(.customAction(withDuration: 2.6) { node, t in node.setScale(0.85 + 0.15 * (1 - sin(2 * .pi * t / 2.6 + phase)) / 2) }))
    }
}
