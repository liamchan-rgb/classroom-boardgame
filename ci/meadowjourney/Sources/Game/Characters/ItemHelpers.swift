import Foundation

// 人物像素精灵：装备共用的小工具（手臂、躯干、袖子）。与 items/shared.ts 对应。

enum Side { case R, L }

enum ItemHelpers {
    /// 侧向时远侧的肢体整体压暗
    static func farBias(_ c: DrawContext, _ near: Double) -> Double {
        abs(c.pose.sin) > 0.5 && near < 0 ? -0.6 : 0
    }

    static func arm(_ c: DrawContext, _ side: Side) -> Arm { side == .R ? c.pose.armR : c.pose.armL }

    /// 手臂所在图层：近侧手臂在躯干前，远侧在后
    static func armLayer(_ side: Side) -> PartLayer {
        .dynamic { c in arm(c, side).hand.front ? .armFront : .armBack }
    }

    /// 带肘弯的手臂（肩 → 肘 → 手）。r = [肩, 肘, 腕] 半径；upto = 前臂画到多长。返回末端坐标。
    @discardableResult
    static func drawArm(_ c: DrawContext, _ side: Side, _ r: [Double], upto: Double = 1, bias: Double = 0) -> SpritePoint {
        let g = c.g
        let a = arm(c, side)
        let fb = farBias(c, a.hand.near) + bias
        let ex = a.elbow.x + (a.hand.x - a.elbow.x) * upto
        let ey = a.elbow.y + (a.hand.y - a.elbow.y) * upto
        g.anchor(a.elbow.x, a.elbow.y)
        g.capsule(a.shoulder.x, a.shoulder.y, a.elbow.x, a.elbow.y, r[0], r[1]) { lam, _, _, _, _ in g.t(lam, fb) }
        g.capsule(a.elbow.x, a.elbow.y, ex, ey, r[1], r[1] + (r[2] - r[1]) * upto) { lam, _, _, _, _ in g.t(lam, fb) }
        return SpritePoint(x: ex, y: ey)
    }

    /// 躯干形状：从颈部往下 rows 个单位，肩部收圆，下摆张开。shade(lam, nx, r, u, v)
    static func torsoShape(_ c: DrawContext, rows: Double, flare: Double = 1, pad: Double = 0,
                           _ shade: (Double, Double, Double, Double, Double) -> Double) {
        let g = c.g, pose = c.pose
        let ny = pose.neckY, hw0 = pose.torsoHalf + pad
        g.fill(Rig.cx - hw0 - flare - 1, ny, Rig.cx + hw0 + flare + 1, ny + rows) { u, v in
            let r = v - ny
            if r < 0 || r > rows { return -1 }
            var hw = hw0
            if r < 2.4 { hw -= (2.4 - r) * (2.4 - r) * 0.35 }
            if r > rows - 7 { hw += (flare * (r - (rows - 7))) / 7 }
            let nx = (u - Rig.cx) / hw
            if abs(nx) > 1 { return -1 }
            return shade(nx * Light.x + (1 - nx * nx).squareRoot() * Light.z + 0.05, nx, r, u, v)
        }
    }

    /// 能看到正面时，门襟 / 领口中线所在的横坐标
    static func frontX(_ c: DrawContext) -> Double { Rig.cx + c.pose.torsoHalf * 0.72 * c.pose.sin }

    /// 两只袖子（各占一个部件，近侧手臂压在躯干前、远侧被挡住）
    static func sleeveParts(key: String = "main", cuffKey: String?, length: Double = 0.72, radius: Double = 2) -> [PartDef] {
        func make(_ side: Side) -> PartDef {
            PartDef(layer: armLayer(side), draw: { c in
                let g = c.g
                let a = arm(c, side)
                let fb = farBias(c, a.hand.near)
                let r = radius, len = length
                c.pal(key)
                g.anchor(a.elbow.x, a.elbow.y)
                g.ellipse(a.shoulder.x, a.shoulder.y + 0.4, r + 0.5, r + 0.3) { lam, _, _, _, _ in g.t(lam, fb) }
                let end = drawArm(c, side, [r, r - 0.1, r + 0.25], upto: len)
                g.fold(a.elbow.x - 1.5, a.elbow.y - 0.3, a.elbow.x + 1.6, a.elbow.y + 0.5)
                if let cuffKey {
                    c.pal(cuffKey)
                    let k = (len - 0.2) / len
                    let sx = a.elbow.x + (end.x - a.elbow.x) * k, sy = a.elbow.y + (end.y - a.elbow.y) * k
                    g.capsule(sx, sy, end.x, end.y, r + 0.15, r + 0.3) { lam, _, t, _, _ in t > 1 ? -1 : g.t(lam, fb + 0.1) }
                }
            })
        }
        return [make(.L), make(.R)]
    }
}
