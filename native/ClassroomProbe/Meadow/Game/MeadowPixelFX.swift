import UIKit
import MeadowBattleSupport

/// 像素特效（pixelfx，MIT，二次创作见实验仓库 scripts/vfx-export.ts）：预渲染好的帧图 + 配方，贴在战斗舞台上播放。
///
/// 配方（素材目录里的 PixelFXRecipes）按游戏特效 id（`MeadowSkillProcedural.skillIDs`）列出要放的片段：什么时候放、贴在谁身上
/// （施法者 / 每个目标 / 目标中心 / 从施法者飞到目标）、偏移多少像素。片段分 back / front 两层：back 画在那个单位后面，front 画在前面，
/// 和人物、怪物一样按脚的 y 排前后。镜头（技能镜头、震屏、导演镜头、压暗）还是游戏原来那套，这里只换画面。
/// 片段按「往右打」画；特效方向是 -1（往左）时整段水平镜像。
enum MeadowPixelFX {
    /// 总开关（默认开）：关掉就回到原来的程序化特效
    static var enabled: Bool { UserDefaults.standard.object(forKey: "meadow.pixelFX") as? Bool ?? true }

    struct Clip: Decodable { let id: String; let w, h, ox, oy, n, cols: Int; let back, front: Bool; let loop: Bool? }
    struct Event: Decodable {
        let clip: String, at: Double, anchor: String
        let dx, dy, stagger, flight, arc, lift: Double?
        let behind: Bool?
    }
    struct Book: Decodable { let fps: Double; let clips: [Clip]; let recipes: [String: [Event]] }

    static let book: Book? = NSDataAsset(name: "PixelFXRecipes").flatMap { try? JSONDecoder().decode(Book.self, from: $0.data) }
    static let clips: [String: Clip] = Dictionary(uniqueKeysWithValues: (book?.clips ?? []).map { ($0.id, $0) })
    /// 游戏里这个特效 id 由像素特效接管（原来的程序化画面不再画）
    static func covers(_ skill: String) -> Bool { enabled && book?.recipes[skill] != nil }
    /// 常驻护盾也由像素特效画
    static var drawsShields: Bool { enabled && clips["shieldIdle"] != nil }

    /// 1 个特效像素 = 人物的 1 个像素 = 4 × heroScale 个布局单位
    static let unit = 4 * PartyVisual.heroScale

    private static var frames: [String: [CGImage]] = [:]
    /// 片段的全部帧（先 back 层再 front 层），第一次用到时从网格图切出来
    static func images(_ clip: Clip) -> [CGImage] {
        if let hit = frames[clip.id] { return hit }
        guard let sheet = UIImage(named: "PixelFX_" + clip.id)?.cgImage else { return [] }
        let count = clip.n * ((clip.back ? 1 : 0) + (clip.front ? 1 : 0))
        let list = (0..<count).compactMap { k in sheet.cropping(to: CGRect(x: (k % clip.cols) * clip.w, y: (k / clip.cols) * clip.h, width: clip.w, height: clip.h)) }
        frames[clip.id] = list
        return list
    }

    /// 预先切好一批常用片段，避免第一次放技能时卡一下
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            let list = Array(MeadowPixelFX.clips.values)
            DispatchQueue.main.async { for c in list.prefix(12) { _ = MeadowPixelFX.images(c) } }
        }
    }
}

/// 一个正在放的特效来源：游戏特效 id、开始时间、方向、此刻的站位（会跟着单位移动）
struct MeadowPixelFXSource {
    let key: String, skill: String, start: Double, direction: Double
    let geo: MeadowSkillProcedural.Geometry
}

/// 常驻护盾：单位脚底、宽度系数（怪物大一点）、护盾出现多久了、多久前挨过打（负数：没有）
struct MeadowPixelShield { let id: String; let foot: PartyPoint; let wide: Double; let age: Double; let hitAge: Double }

/// 舞台上的像素特效层：每帧按来源生成 / 更新 / 回收 CALayer（加在世界视图的 layer 上，和人物同一个坐标系）
final class MeadowPixelFXPlayer {
    private weak var host: CALayer?
    private struct Instance {
        let clip: MeadowPixelFX.Clip, event: MeadowPixelFX.Event, start: Double, target: Int, sourceKey: String
        var direction: Double, geo: MeadowSkillProcedural.Geometry
        let back: CALayer?, front: CALayer?
    }
    private var live: [Instance] = []
    private var seen: Set<String> = []
    private var shields: [String: (CALayer, CALayer)] = [:]

    init(host: CALayer) { self.host = host }

    func reset() {
        for i in live { i.back?.removeFromSuperlayer(); i.front?.removeFromSuperlayer() }
        for (a, b) in shields.values { a.removeFromSuperlayer(); b.removeFromSuperlayer() }
        live = []; seen = []; shields = [:]
    }

    private func makeLayer() -> CALayer {
        let l = CALayer()
        l.magnificationFilter = .nearest; l.minificationFilter = .nearest
        l.isHidden = true
        host?.addSublayer(l)
        return l
    }

    func update(time: Double, sources: [MeadowPixelFXSource], shields shieldList: [MeadowPixelShield]) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let book = MeadowPixelFX.book else { return }
        // 新来源：按配方生成实例
        var byKey: [String: MeadowPixelFXSource] = [:]
        for s in sources {
            byKey[s.key] = s
            guard !seen.contains(s.key), let recipe = book.recipes[s.skill] else { continue }
            seen.insert(s.key)
            for e in recipe {
                guard let clip = MeadowPixelFX.clips[e.clip] else { continue }
                let n = e.anchor == "target" ? max(1, s.geo.targets.count) : 1
                for k in 0..<n {
                    live.append(Instance(clip: clip, event: e, start: s.start + e.at + Double(k) * (e.stagger ?? 0), target: k, sourceKey: s.key,
                                         direction: s.direction, geo: s.geo,
                                         back: clip.back ? makeLayer() : nil, front: clip.front ? makeLayer() : nil))
                }
            }
        }
        if seen.count > 400 { seen = Set(sources.map(\.key)) }
        // 更新每个实例
        let fps = book.fps, U = MeadowPixelFX.unit
        var keep: [Instance] = []
        for var i in live {
            if let s = byKey[i.sourceKey] { i.geo = s.geo; i.direction = s.direction }
            let t = time - i.start, clip = i.clip, e = i.event
            let flight = e.anchor == "fly" ? (e.flight ?? 0.2) : 0
            let ended = clip.loop == true ? (e.anchor == "fly" ? t > flight : t > 6) : t * fps >= Double(clip.n)
            if ended || i.geo.targets.isEmpty && e.anchor != "caster" {
                i.back?.removeFromSuperlayer(); i.front?.removeFromSuperlayer(); continue
            }
            keep.append(i)
            guard t >= 0 else { i.back?.isHidden = true; i.front?.isHidden = true; continue }
            var f = Int(t * fps)
            f = clip.loop == true ? f % clip.n : min(clip.n - 1, f)
            let dir = i.direction < 0 ? -1.0 : 1.0
            // 锚点（脚底，布局单位）
            let g = i.geo
            let tgt = g.targets.isEmpty ? g.casterFoot : g.targets[min(i.target, g.targets.count - 1)].foot
            var ax: Double, ay: Double
            switch e.anchor {
            case "caster": ax = g.casterFoot.x; ay = g.casterFoot.y
            case "center":
                let c = Double(max(1, g.targets.count))
                ax = g.targets.reduce(0) { $0 + $1.foot.x } / c; ay = g.targets.reduce(0) { $0 + $1.foot.y } / c
            case "fly":
                // 和预览一样：从施法者胸前（离地 lift 像素、往前 12 像素）飞到目标胸口，略带抛物线
                let k = min(1, max(0, t / max(0.01, flight))), lift = (e.lift ?? 26) * U, arc = (e.arc ?? 4) * U
                let a = g.casterFoot, b = tgt
                ax = a.x + dir * 12 * U + (b.x - a.x - dir * 22 * U) * k
                ay = a.y - lift + (b.y - a.y + lift - 14 * U) * k - sin(k * .pi) * arc
            default: ax = tgt.x; ay = tgt.y
            }
            ax += dir * (e.dx ?? 0) * U; let footY = e.anchor == "fly" ? tgt.y : ay
            ay += (e.dy ?? 0) * U
            let images = MeadowPixelFX.images(clip)
            let w = Double(clip.w) * U, h = Double(clip.h) * U
            let x = dir > 0 ? ax - Double(clip.ox) * U : ax - (Double(clip.w - clip.ox)) * U
            let frame = CGRect(x: x, y: ay - Double(clip.oy) * U, width: w, height: h)
            let behind = e.behind == true
            for (layer, idx, z) in [(i.back, f, footY - 0.5), (i.front, (clip.back ? clip.n : 0) + f, behind ? footY - 0.5 : footY + 0.5)] {
                guard let layer else { continue }
                layer.isHidden = idx >= images.count
                guard idx < images.count else { continue }
                layer.contents = images[idx]
                // 镜像绕图块中心翻转（frame 已经按镜像后的位置算好）
                layer.bounds = CGRect(origin: .zero, size: frame.size)
                layer.position = CGPoint(x: frame.midX, y: frame.midY)
                layer.transform = dir > 0 ? CATransform3DIdentity : CATransform3DMakeScale(-1, 1, 1)
                layer.zPosition = CGFloat(z)
            }
        }
        live = keep
        updateShields(time: time, list: shieldList)
    }

    /// 常驻护盾：刚出现时播生成（0.6 秒），挨打后播 0.6 秒的涟漪，其余时间循环待机
    private func updateShields(time: Double, list: [MeadowPixelShield]) {
        let fps = MeadowPixelFX.book?.fps ?? 20, U = MeadowPixelFX.unit
        var alive = Set<String>()
        for s in list {
            let clipID = s.hitAge >= 0 && s.hitAge < 0.6 ? "shieldHit" : s.age < 0.6 ? "shieldForm" : "shieldIdle"
            guard let clip = MeadowPixelFX.clips[clipID] else { continue }
            alive.insert(s.id)
            let pair = shields[s.id] ?? (makeLayer(), makeLayer())
            shields[s.id] = pair
            let t = clipID == "shieldHit" ? s.hitAge : s.age
            let f = clip.loop == true ? Int(t * fps) % clip.n : min(clip.n - 1, Int(t * fps))
            let images = MeadowPixelFX.images(clip), k = U * s.wide
            let frame = CGRect(x: s.foot.x - Double(clip.ox) * k, y: s.foot.y - Double(clip.oy) * k, width: Double(clip.w) * k, height: Double(clip.h) * k)
            for (layer, idx, z) in [(pair.0, f, s.foot.y - 0.5), (pair.1, (clip.back ? clip.n : 0) + f, s.foot.y + 0.5)] {
                let ok = idx < images.count && (idx < clip.n ? clip.back : clip.front)
                layer.isHidden = !ok
                guard ok else { continue }
                layer.contents = images[idx]; layer.bounds = CGRect(origin: .zero, size: frame.size)
                layer.position = CGPoint(x: frame.midX, y: frame.midY); layer.zPosition = CGFloat(z)
            }
        }
        for (id, pair) in shields where !alive.contains(id) { pair.0.removeFromSuperlayer(); pair.1.removeFromSuperlayer(); shields[id] = nil }
    }
}
