import Foundation

// 人物像素精灵：纸娃娃合成。与 hd2d-walk-demo/src/character/paperdoll.ts 对应。
// 每个部件先画到临时层 → 背光反光 → 自动描边 → 对下层投接触阴影 → 按 z 从后到前叠到输出层。

enum Paperdoll {
    /// 部件之间的内描边用哪一阶（0.75 = 介于描边色和暗部之间）
    static let innerLine = 0.75

    /// 同一图层内的先后：身体最底，其余按槽位
    private static let slotOrder: [Slot?] = [nil, .face, .bottom, .shoes, .top, .bag, .scarf, .hair, .weaponOff, .weaponMain]

    /// 接触阴影的采样点：[dx, dy, 压暗多少阶]，朝右下投约 2 像素
    static func shadowTaps(scale: Double) -> [(Int, Int, Double)] {
        let reach = max(2, Int(jsRound(2.8 * scale)))
        var taps: [(Int, Int, Double)] = []
        for dy in 0...reach {
            for dx in 0...reach {
                if dx == 0 && dy == 0 { continue }
                let d = hypot(Double(dx) * 0.8, Double(dy))
                if d > Double(reach) { continue }
                taps.append((dx, dy, 0.85 * (1 - (d - 1) / Double(reach))))
            }
        }
        return taps
    }

    private static func holdOf(_ entries: [LoadoutEntry], _ slot: Slot) -> Hold? {
        guard let e = entries.first(where: { $0.slot == slot }) else { return nil }
        return e.item.hold ?? .up
    }

    /// 把一组装备合成为某方向某帧的一张像素图
    static func composeFrame(_ entries: [LoadoutEntry], dir: Dir5, frame: Int, into out: PixelLayer) {
        let S = SpriteRig.spriteScale
        let tmp = PixelLayer(out.w, out.h)
        let brush = SpriteBrush(tmp, S)
        let taps = shadowTaps(scale: S)
        let pose = CharacterPose(dir: dir, frame: frame,
                                 armedR: holdOf(entries, .weaponMain), armedL: holdOf(entries, .weaponOff))
        let bodyPalettes = entries.first(where: { $0.slot == nil })?.palettes ?? [:]

        struct Cmd {
            let z: Int
            let order: Int
            let part: PartDef
            let ctx: DrawContext
        }
        var cmds: [Cmd] = []

        for (ei, entry) in entries.enumerated() {
            let hand: HandAnchor? = entry.slot == .weaponMain ? pose.handR : entry.slot == .weaponOff ? pose.handL : nil
            let override = entry.item.layerOverride?(dir) ?? [:]
            for (pi, part) in entry.item.parts.enumerated() {
                let ctx = DrawContext(dir: dir, frame: frame, pose: pose, L: tmp, g: brush, hand: hand,
                                      palettes: entry.palettes, bodyPalettes: bodyPalettes,
                                      fallback: entry.palettes.values.first)
                let layer: LayerId
                switch part.layer {
                case .fixed(let id): layer = id
                case .dynamic(let fn): layer = fn(ctx)
                case .weapon:
                    if let h = hand, !h.weaponFront { layer = .weaponBack }
                    else if (entry.item.hold ?? .up) == .up && !(hand?.weaponOverHead ?? false) { layer = .weaponMid }
                    else { layer = .weaponFront }
                }
                let z = override[layer] ?? layer.z
                let slotIndex = slotOrder.firstIndex(where: { $0 == entry.slot }) ?? 0
                cmds.append(Cmd(z: z, order: slotIndex * 1000 + ei * 50 + pi, part: part, ctx: ctx))
            }
        }
        cmds.sort { $0.z != $1.z ? $0.z < $1.z : $0.order < $1.order }

        for cmd in cmds {
            let part = cmd.part, ctx = cmd.ctx
            tmp.clear()
            brush.clip = false
            brush.grit = 0.16
            brush.dither = true
            brush.anchor(SpriteRig.cx, pose.neckY)
            if let frames = part.frames, let rows = frames[dir] {
                ctx.pal(part.paletteKey)
                let a = part.anchor?(ctx) ?? SpritePoint(x: pose.proj(0, 0, 0).x, y: pose.neckY)
                brush.cells(rows, a.x + part.offset.0, a.y + part.offset.1)
            }
            part.draw?(ctx)
            if part.maskBelow {
                tmp.draw(onto: out, maskBelow: true)
                continue
            }
            if part.outline {
                tmp.bounce()
                tmp.outline()
                out.castShadow(tmp, taps: taps)
            }
            tmp.draw(onto: out, innerLine: innerLine)
        }
    }
}
