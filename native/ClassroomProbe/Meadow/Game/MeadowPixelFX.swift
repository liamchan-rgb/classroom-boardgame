import UIKit
import ClassroomGameCore
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

/// 怪物倒下时的掉落动画（按规则这一击实际掉了什么）：
///   物品 / 金币从怪物身上弹出来，划一道弧落地、弹一下，在地上停一会儿（稀有以上站在品级颜色的光柱里，头顶飘着「品级 · 名字」），
///   然后飞向拿到它的英雄，在英雄胸前炸开一团拾取光。金币是会转的像素金币。
final class MeadowLootShower {
    private weak var host: CALayer?
    private struct Piece {
        let start: Double, from: CGPoint, land: CGPoint, receiver: String, rest: Double
        let rarity: MeadowItemRarity?, coin: Bool
        let icon: CALayer, beam: CALayer?, label: CATextLayer?
        var collected = false
    }
    private struct Burst { let clip: MeadowPixelFX.Clip; let start: Double; let at: CGPoint; let layer: CALayer }
    private var pieces: [Piece] = []
    private var bursts: [Burst] = []

    init(host: CALayer) { self.host = host }

    func reset() {
        for p in pieces { p.icon.removeFromSuperlayer(); p.beam?.removeFromSuperlayer(); p.label?.removeFromSuperlayer() }
        for b in bursts { b.layer.removeFromSuperlayer() }
        pieces = []; bursts = []
    }

    private func layer(_ z: CGFloat) -> CALayer {
        let l = CALayer(); l.magnificationFilter = .nearest; l.minificationFilter = .linear; l.zPosition = z; l.isHidden = true
        host?.addSublayer(l); return l
    }

    /// drops：(物品 id，nil = 金币；数量)。foot：怪物脚底；receiver：拿到的英雄
    func drop(_ drops: [(item: String?, count: Int)], foot: PartyPoint, height: Double, receiver: String, at start: Double, catalog: GameCatalog?) {
        var list: [(item: String?, coin: Bool)] = []
        for d in drops {
            if let item = d.item { for _ in 0..<min(3, max(1, d.count)) { list.append((item, false)) } }
            else { for _ in 0..<min(8, max(3, d.count / 6)) { list.append((nil, true)) } }
        }
        // 稀有的最后出来、落在最前面
        list.sort { (a, b) in (a.item.map { MeadowItemRarity.of($0) }?.rawValue ?? -1) < (b.item.map { MeadowItemRarity.of($0) }?.rawValue ?? -1) }
        let n = list.count
        for (i, entry) in list.enumerated() {
            let rarity = entry.item.map { MeadowItemRarity.of($0, item: try? catalog?.item($0)) }
            let spread = Double(i) - Double(n - 1) / 2
            let jitter = sin(Double(i) * 12.9898 + foot.x) * 14
            let land = CGPoint(x: foot.x - 40 + spread * (entry.coin ? 30 : 56) + jitter, y: foot.y + 8 + Double(i % 3) * 12)
            let rest = (rarity ?? .common) >= .rare ? 2.6 : entry.coin ? 1.3 : 1.7
            let icon = layer(CGFloat(land.y + 1))
            var beam: CALayer?, label: CATextLayer?
            if let item = entry.item {
                icon.contents = MeadowItemIcon.image(item).images?.first?.cgImage ?? MeadowItemIcon.image(item).cgImage
                let side: CGFloat = (rarity ?? .common) >= .rare ? 78 : 62
                icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                if let r = rarity, r >= .rare {
                    beam = layer(CGFloat(land.y - 0.5))
                    let text = CATextLayer()
                    text.string = NSAttributedString(string: "\(r.title) · \((try? catalog?.item(item).name) ?? item)", attributes: [
                        .font: UIFont.systemFont(ofSize: r == .legendary ? 26 : 22, weight: .heavy), .foregroundColor: r.color,
                        .strokeColor: UIColor.black.withAlphaComponent(0.85), .strokeWidth: -4])
                    text.alignmentMode = .center; text.contentsScale = 3; text.zPosition = 960; text.isHidden = true
                    text.shadowColor = r.color.cgColor; text.shadowRadius = 8; text.shadowOpacity = 0.9; text.shadowOffset = .zero
                    text.bounds = CGRect(x: 0, y: 0, width: 360, height: 36)
                    host?.addSublayer(text); label = text
                }
            } else {
                icon.bounds = CGRect(x: 0, y: 0, width: 34 * MeadowPixelFX.unit, height: 35 * MeadowPixelFX.unit)
            }
            pieces.append(Piece(start: start + Double(i) * 0.07, from: CGPoint(x: foot.x, y: foot.y - height), land: land, receiver: receiver,
                                rest: rest, rarity: rarity, coin: entry.coin, icon: icon, beam: beam, label: label))
        }
    }

    func update(time: Double, live: [String: PartyPoint]) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let fps = MeadowPixelFX.book?.fps ?? 20, U = MeadowPixelFX.unit
        let coinClip = MeadowPixelFX.clips["coinSpin"]
        var keep: [Piece] = []
        for var p in pieces {
            let t = time - p.start
            guard t >= 0 else { keep.append(p); continue }
            let fly = 0.55, bounce = 0.25, collectAt = fly + bounce + p.rest, collectLen = 0.42
            let target = (live[p.receiver] ?? PartyVisual.foot(p.receiver)).map { CGPoint(x: $0.x, y: $0.y - 80 * PartyVisual.heroScale) } ?? p.from
            var pos: CGPoint, scale: CGFloat = 1
            if t < fly {
                // 弹出：抛物线，最高点比出发点高 90
                let k = t / fly
                pos = CGPoint(x: p.from.x + (p.land.x - p.from.x) * k, y: p.from.y + (p.land.y - p.from.y) * k - sin(k * .pi) * 90 - (1 - k) * 0)
            } else if t < fly + bounce {
                let k = (t - fly) / bounce
                pos = CGPoint(x: p.land.x, y: p.land.y - sin(k * .pi) * 16)
            } else if t < collectAt {
                pos = CGPoint(x: p.land.x, y: p.land.y - (1 + sin((t - fly) * 4)) * 3)
            } else if t < collectAt + collectLen {
                let k = (t - collectAt) / collectLen, e = k * k
                pos = CGPoint(x: p.land.x + (target.x - p.land.x) * e, y: p.land.y + (target.y - p.land.y) * e - sin(k * .pi) * 40)
                scale = 1 - 0.55 * k
            } else {
                if !p.collected { burst(p.coin ? "collectGold" : "collect" + (p.rarity?.clipSuffix ?? "Rare"), at: target, time: time, big: (p.rarity ?? .common) >= .rare) }
                p.icon.removeFromSuperlayer(); p.beam?.removeFromSuperlayer(); p.label?.removeFromSuperlayer()
                continue
            }
            // 图标
            p.icon.isHidden = false
            if p.coin, let clip = coinClip {
                let images = MeadowPixelFX.images(clip), f = Int(time * fps) % clip.n
                let idx = clip.back && clip.front ? clip.n + f : f
                if idx < images.count { p.icon.contents = images[idx] }
                p.icon.position = CGPoint(x: pos.x - (Double(clip.ox) - Double(clip.w) / 2) * U, y: pos.y - (Double(clip.oy) - Double(clip.h) / 2) * U)
            } else {
                // 物品图标：底边落在地面
                p.icon.position = CGPoint(x: pos.x, y: pos.y - p.icon.bounds.height / 2)
            }
            p.icon.transform = CATransform3DMakeScale(scale, scale, 1)
            p.icon.zPosition = CGFloat(t < fly ? 955 : pos.y + 1)
            // 稀有以上：落地后升起光柱、头顶飘名字
            let settled = t >= fly && t < collectAt
            if let beam = p.beam, let r = p.rarity, let suffix = r.clipSuffix, let clip = MeadowPixelFX.clips["lootBeam" + suffix] {
                beam.isHidden = !settled
                if settled {
                    let images = MeadowPixelFX.images(clip), f = Int((t - fly) * fps) % clip.n
                    let idx = f + (clip.back && clip.front ? clip.n : 0)
                    if idx < images.count { beam.contents = images[idx] }
                    beam.bounds = CGRect(x: 0, y: 0, width: Double(clip.w) * U, height: Double(clip.h) * U)
                    beam.position = CGPoint(x: p.land.x - (Double(clip.ox) - Double(clip.w) / 2) * U, y: p.land.y - (Double(clip.oy) - Double(clip.h) / 2) * U)
                    beam.opacity = Float(min(1, (t - fly) / 0.25))
                }
            }
            if let label = p.label {
                label.isHidden = !settled
                if settled {
                    let k = min(1, (t - fly) / 0.3)
                    label.position = CGPoint(x: p.land.x, y: p.land.y - p.icon.bounds.height - 34 - 10 * k)
                    let pop = 0.6 + 0.4 * k + (k < 1 ? sin(k * .pi) * 0.25 : 0)
                    label.transform = CATransform3DMakeScale(pop, pop, 1)
                }
            }
            keep.append(p)
        }
        pieces = keep
        // 拾取光
        bursts.removeAll { b in
            let f = Int((time - b.start) * fps)
            guard f < b.clip.n else { b.layer.removeFromSuperlayer(); return true }
            let images = MeadowPixelFX.images(b.clip)
            for idx in [b.clip.back && b.clip.front ? b.clip.n + f : f] where idx < images.count { b.layer.contents = images[idx] }
            b.layer.isHidden = false
            return false
        }
    }

    private func burst(_ id: String, at p: CGPoint, time: Double, big: Bool) {
        guard let clip = MeadowPixelFX.clips[id] else { return }
        let U = MeadowPixelFX.unit * (big ? 1.4 : 1), l = layer(960)
        l.bounds = CGRect(x: 0, y: 0, width: Double(clip.w) * U, height: Double(clip.h) * U)
        l.position = CGPoint(x: p.x - (Double(clip.ox) - Double(clip.w) / 2) * U, y: p.y + 40 - (Double(clip.oy) - Double(clip.h) / 2) * U)
        bursts.append(Burst(clip: clip, start: time, at: p, layer: l))
    }
}
