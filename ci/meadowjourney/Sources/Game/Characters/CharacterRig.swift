import Foundation

// 人物像素精灵：骨架。与 hd2d-walk-demo/src/character/rig.ts 对应。
// 角色有一套局部 3D 坐标（side 左右、up 上下、fwd 前后），按朝向旋转后投影到精灵平面，
// 5 个方向的动作只写一份。所有坐标都是单位坐标（64×96 的画布），像素 = 单位 × 倍率。

/// 三角函数的别名：CharacterPose 有同名的 sin / cos 属性，在它附近调用数学函数时用这两个，避免歧义
@inline(__always) func msin(_ x: Double) -> Double { sin(x) }
@inline(__always) func mcos(_ x: Double) -> Double { cos(x) }

enum Dir5: String, CaseIterable, Codable {
    case S, SE, E, NE, N
}

/// 握持方式：up 竖举在身侧（法杖），down 剑尖朝下垂在身前（剑）
enum Hold: String {
    case up, down
}

enum Rig {
    static let unitW = 64.0
    static let unitH = 96.0
    /// 身体中轴（镜像轴）
    static let cx = 32.0
    /// 脚底所在高度
    static let footY = 90.0
    /// 精灵倍率：0.65 → 每帧 42×62 像素
    static let spriteScale = 0.65
    static var sprW: Int { Int(jsRound(unitW * spriteScale)) }
    static var sprH: Int { Int(jsRound(unitH * spriteScale)) }
    /// 5 行 × 8 列：0–1 待机，2–7 行走
    static let framesPerDir = 8

    // 身体比例（从脚底往上的高度）。Q 版约 2.1 头身。
    static let hip = 16.0
    static let hand = 17.0
    static let shoulder = 29.0
    static let neck = 30.0
    static let head = 41.8
    static let headRX = 11.6
    static let headRY = 10.9
    /// 俯视带来的纵向错位：离镜头近的点在屏幕上更低
    static let tilt = 0.35

    static func trig(_ d: Dir5) -> (Double, Double) {
        let r = 0.5.squareRoot()
        switch d {
        case .S: return (0, 1)
        case .SE: return (r, r)
        case .E: return (1, 0)
        case .NE: return (r, -r)
        case .N: return (0, -1)
        }
    }
}

struct Joint {
    var x: Double
    var y: Double
    /// > 0 表示比身体中轴更靠近镜头
    var near: Double
}

struct HandAnchor {
    var x: Double
    var y: Double
    var near: Double
    /// 手臂所在图层：近侧手臂画在躯干前
    var front: Bool
    /// 武器指向（屏幕空间弧度，y 向下）
    var angle: Double
    /// 手持武器应画在身前还是身后
    var weaponFront: Bool
    /// 竖握的长柄武器是否画在头前面
    var weaponOverHead: Bool
}

struct Arm {
    var shoulder: Joint
    var elbow: Joint
    var hand: HandAnchor
}

struct Leg {
    var hip: Joint
    var foot: Joint
}

struct CharacterPose {
    let dir: Dir5
    let sin: Double
    let cos: Double
    let frame: Int
    let walking: Bool
    /// 动画内的帧序号（待机 0-1，行走 0-5）
    let t: Int
    /// 行走相位（弧度），待机为 0
    let phase: Double
    /// 上半身下沉的量（呼吸 / 走路弹跳）
    let bob: Double
    let head: Joint
    let neckY: Double
    let neckUp: Double
    let torsoHalf: Double
    let armR: Arm
    let armL: Arm
    /// 两条腿，已按远 → 近排序
    let legs: [Leg]

    var handR: HandAnchor { armR.hand }
    var handL: HandAnchor { armL.hand }

    /// 局部坐标 → 精灵坐标
    func proj(_ side: Double, _ up: Double, _ fwd: Double, _ tilt: Double = Rig.tilt) -> Joint {
        let near = fwd * cos - side * sin
        return Joint(x: Rig.cx + side * cos + fwd * sin, y: Rig.footY - up + near * tilt, near: near)
    }

    init(dir: Dir5, frame: Int, armedR: Hold? = nil, armedL: Hold? = nil) {
        let (sn, cs) = Rig.trig(dir)
        self.dir = dir
        self.sin = sn
        self.cos = cs
        self.frame = frame
        let walking = frame >= 2
        self.walking = walking
        let t = walking ? frame - 2 : frame
        self.t = t

        var s = 0.0, c = 0.0, bob = 0.0, phase = 0.0
        if walking {
            phase = ((Double(t) + 0.5) / 6) * Double.pi * 2
            s = msin(phase)
            c = mcos(phase)
            bob = t % 3 == 1 ? 1 : 0
        } else {
            bob = t == 1 ? 1 : 0
        }
        self.phase = phase
        self.bob = bob
        let lean = walking ? 1.0 : 0.0

        func proj(_ side: Double, _ up: Double, _ fwd: Double, _ tilt: Double = Rig.tilt) -> Joint {
            let near = fwd * cs - side * sn
            return Joint(x: Rig.cx + side * cs + fwd * sn, y: Rig.footY - up + near * tilt, near: near)
        }

        head = proj(walking ? 0 : -0.3, Rig.head - bob, lean)

        func arm(_ sign: Double, _ hold: Hold?) -> Arm {
            let shoulder = proj(7.2 * sign, Rig.shoulder - bob, lean * 0.6, 0.12)
            var j: Joint, elbow: Joint
            var ls = 0.14 * sign, lu = 0.95, lf = 0.1
            switch hold {
            case .up?:
                elbow = proj(8.6 * sign, Rig.hand + 7 - bob, -1)
                j = proj(9.6 * sign, Rig.hand + 5 - bob, 3.2 + 1.2 * s * sign)
                if abs(cs) < 0.5 { lf = 0.62 }
            case .down?:
                elbow = proj(8.5 * sign, Rig.hand + 6.5 - bob, 0.5 * s * sign)
                j = proj(8.8 * sign, Rig.hand + 1.5 - bob, 2.6 + 1.6 * s * sign)
                ls = 0.5 * sign; lu = -0.55; lf = 0.65
            case nil:
                let swing = walking ? 4.5 * s * sign : sign < 0 ? 1.4 : -0.6
                elbow = proj(8.3 * sign, (Rig.shoulder + Rig.hand) / 2 + 0.5 - bob, swing * 0.35 - 1.2)
                j = proj(7.8 * sign, Rig.hand - bob + abs(swing) * 0.15, swing + 0.8)
            }
            let dx = ls * cs + lf * sn
            let nr = lf * cs - ls * sn
            let dy = -lu + nr * Rig.tilt
            return Arm(shoulder: shoulder, elbow: elbow, hand: HandAnchor(
                x: j.x, y: j.y, near: j.near,
                front: shoulder.near >= -0.01,
                angle: atan2(dy, dx),
                weaponFront: -7.8 * sign * sn + nr * 14 >= -0.5,
                weaponOverHead: abs(cs) < 0.5))
        }
        armR = arm(-1, armedR)
        armL = arm(1, armedL)

        func leg(_ sign: Double) -> Leg {
            let hip = proj(2.8 * sign, Rig.hip - bob, 0, 0)
            if !walking {
                return Leg(hip: hip, foot: sign < 0 ? proj(-3.6, 0, 1.5) : proj(3, 0, -0.4))
            }
            let swing = -s * sign
            let lift = max(0, -c * sign) * 2.6
            return Leg(hip: hip, foot: proj(3 * sign, lift, 5 * swing))
        }
        let legR = leg(-1), legL = leg(1)
        legs = legR.foot.near <= legL.foot.near ? [legR, legL] : [legL, legR]

        neckY = Rig.footY - Rig.neck + bob
        neckUp = Rig.neck - bob
        torsoHalf = 6.5 - 1.9 * abs(sn)
    }
}
