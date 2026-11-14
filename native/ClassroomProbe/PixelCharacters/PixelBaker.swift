import CryptoKit
import Foundation
import JavaScriptCore

/// 像素人物烘焙器。
///
/// Resources/pixel-baker.js 是网页制作工具（experiment 仓库 hd2d-walk-demo，`npm run runtime`）打出来的同一份代码，
/// 这里用 JavaScriptCore 执行：游戏里的像素和网页预览一模一样，改发型、衣服、动作只要重新打包这个 JS 文件。
///
/// JavaScriptCore 在 App 里没有 JIT，一整张 5 方向 × 34 帧的 sheet 约 2.5 秒，所以游戏只烘需要的部分
/// （地图：5 个方向的待机 + 8 相位行走；战斗：右侧的战斗帧），结果按「脚本版本 + 规格」缓存到 Caches，第二次起直接读盘。
/// 所有调用都在一条串行队列上（JSContext 不能多线程同时用）。
final class PixelBaker {
    static let shared = PixelBaker()

    struct Info: Decodable {
        struct Variant: Decodable { let id: String; let name: String }
        struct Item: Decodable {
            let id: String
            let name: String
            let gameItem: String?
            let hold: String?
            let attack: String?
            let variants: [Variant]
        }
        let sprW: Int
        let sprH: Int
        let framesPerDir: Int
        let dirs: [String]
        /// 脚底中心在一帧里的像素坐标（x, y）
        let footPx: [Double]
        /// 动画名 → sheet 列号
        let frames: [String: [Int]]
        /// 槽位 → 可选装备
        let items: [String: [Item]]
        let skins: [String]
    }

    let info: Info
    /// 脚本内容的摘要：缓存键的一部分，换了 JS 自动作废旧缓存
    let scriptVersion: String
    private let queue = DispatchQueue(label: "pixel-baker.js", qos: .userInitiated)
    private let context: JSContext
    private let api: JSValue

    private init() {
        guard let url = Bundle.main.url(forResource: "pixel-baker", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { fatalError("Missing pixel-baker.js") }
        scriptVersion = SHA256.hash(data: Data(source.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        guard let context = JSContext() else { fatalError("JavaScriptCore unavailable") }
        context.exceptionHandler = { _, exception in NSLog("[pixel-baker] %@", exception?.toString() ?? "unknown error") }
        context.evaluateScript("var console = { log: function () {}, warn: function () {}, error: function () {} };")
        context.evaluateScript(source)
        guard let api = context.objectForKeyedSubscript("PixelBaker"), api.isObject,
              let text = api.invokeMethod("info", withArguments: [])?.toString(),
              let info = try? JSONDecoder().decode(Info.self, from: Data(text.utf8)) else { fatalError("pixel-baker.js failed to load") }
        self.context = context
        self.api = api
        self.info = info
    }

    /// 烘一块：dirs 行 × frames 列，每格 sprW × sprH，RGBA（alpha 只有 0 / 255，预乘与否结果相同）。
    /// spec = ["slots": [槽位: 装备 id], "variants": [槽位: 换色 id], "skin": 肤色]。先查磁盘缓存。
    func bake(spec: [String: Any], dirs: [String], frames: [Int]) -> Data? {
        var full = spec
        full["dirs"] = dirs
        full["frames"] = frames
        guard let json = try? JSONSerialization.data(withJSONObject: full, options: [.sortedKeys]),
              let text = String(data: json, encoding: .utf8) else { return nil }
        let expected = info.sprW * info.sprH * 4 * dirs.count * frames.count
        let key = SHA256.hash(data: Data((scriptVersion + text).utf8)).map { String(format: "%02x", $0) }.joined()
        let file = Self.cacheDirectory.appendingPathComponent(key + ".rgba")
        if let cached = try? Data(contentsOf: file), cached.count == expected { return cached }
        let bytes: Data? = queue.sync {
            guard let value = api.invokeMethod("bake", withArguments: [text]), value.isObject else { return nil }
            let ctx = context.jsGlobalContextRef
            var exception: JSValueRef?
            guard let object = JSValueToObject(ctx, value.jsValueRef, &exception) else { return nil }
            let length = JSObjectGetTypedArrayByteLength(ctx, object, &exception)
            guard length == expected, let pointer = JSObjectGetTypedArrayBytesPtr(ctx, object, &exception) else { return nil }
            return Data(bytes: pointer, count: length)
        }
        if let bytes { try? bytes.write(to: file, options: .atomic) }
        return bytes
    }

    /// 某个方向几帧的两只脚（像素坐标）
    func feet(hold: String?, dir: String, frames: [Int]) -> [[CGPoint]] {
        guard let data = try? JSONSerialization.data(withJSONObject: frames),
              let arg = String(data: data, encoding: .utf8) else { return [] }
        let text: String? = queue.sync { api.invokeMethod("feetAt", withArguments: [hold ?? "", dir, arg])?.toString() }
        guard let text, let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[[Double]]] else { return [] }
        return value.map { $0.map { CGPoint(x: $0[0], y: $0[1]) } }
    }

    /// 某个方向某一帧武器手：像素坐标、武器指向（弧度）、缩短比例、精灵倍率
    func hand(hold: String?, dir: String, frame: Int) -> (point: CGPoint, angle: CGFloat, reach: CGFloat, scale: CGFloat)? {
        let text: String? = queue.sync { api.invokeMethod("handAt", withArguments: [hold ?? "", dir, frame])?.toString() }
        guard let text, let v = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Double], v.count == 5 else { return nil }
        return (CGPoint(x: v[0], y: v[1]), CGFloat(v[2]), CGFloat(v[3]), CGFloat(v[4]))
    }

    /// 武器的握持方式（down / shoulder / bow / up，空手 nil）
    func hold(ofSpriteWeapon id: String?) -> String? {
        guard let id else { return nil }
        return info.items["weapon_main"]?.first { $0.id == id }?.hold ?? "up"
    }

    /// 普通攻击用哪个动作
    func attackAnimation(ofSpriteWeapon id: String?) -> String {
        guard let id, let item = info.items["weapon_main"]?.first(where: { $0.id == id }) else { return "slash" }
        if let attack = item.attack { return attack }
        switch item.hold ?? "up" {
        case "down": return "slash"
        case "shoulder": return "heavy"
        case "bow": return "shoot"
        default: return "cast"
        }
    }

    static let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PixelHeroes", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
}
