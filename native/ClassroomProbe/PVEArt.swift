import SwiftUI
import UIKit
import ClassroomGameCore

/// Lazy local lookup by manifest entity ID. Hidden entities never request an image.
enum GameArt {
    struct Binding: Decodable { var entityType: String; var entityID: String; var file: String }
    struct Bindings: Decodable { var assets: [Binding] }
    static let bindings: [String:String] = {
        guard let data = data("bindings"), let doc = try? JSONDecoder().decode(Bindings.self,from:data) else { return [:] }
        return Dictionary(uniqueKeysWithValues:doc.assets.map { ($0.entityType+":"+$0.entityID,$0.file) })
    }()
    static func data(_ name:String) -> Data? {
        Bundle.main.url(forResource:name,withExtension:"json",subdirectory:"Art").flatMap { try? Data(contentsOf:$0) }
    }
    private static let cache = NSCache<NSString,UIImage>()
    static func image(_ type:String,_ id:String) -> UIImage? {
        let key = type+":"+id
        if let cached = cache.object(forKey:key as NSString) { return cached }
        guard let file = bindings[key], let url = Bundle.main.url(forResource:file,withExtension:nil,subdirectory:"Art"), let image = UIImage(contentsOfFile:url.path) else { return nil }
        cache.setObject(image,forKey:key as NSString); return image
    }
}
struct ArtImage:View {
    let type:String
    let id:String
    var body:some View {
        if let image = GameArt.image(type,id) { Image(uiImage:image).resizable().interpolation(.high).scaledToFit() }
        else { Image(systemName:"sparkles").resizable().scaledToFit().foregroundStyle(GameTheme.muted) }
    }
}
struct ResourceValue:View {
    let id:String
    let text:String
    var iconSize:Double = 22
    var body:some View {
        HStack(spacing:4) { ArtImage(type:"uiResource",id:id).frame(width:iconSize,height:iconSize); Text(text).monospacedDigit() }
            .accessibilityElement(children:.combine)
            .accessibilityLabel((["health":"生命","shield":"护盾","action":"行动点","coin":"金币","score":"积分"][id] ?? id)+" "+text)
    }
}
struct TeamMark:View {
    let id:String?
    private var index:Int { (id ?? "").utf8.reduce(0) { ($0+Int($1))%3 } }
    var body:some View {
        Image(systemName:["circle.fill","diamond.fill","triangle.fill"][index])
            .foregroundStyle([GameTheme.shield,GameTheme.accent,GameTheme.action][index])
    }
}
private struct MotionFrame:Decodable {
    var t:Double; var x:Double?; var y:Double?; var rotationDeg:Double?; var opacity:Double?; var saturation:Double?; var scaleX:Double?; var scaleY:Double?
}
private struct Motion:Decodable { var durationMs:Double; var loop:Bool; var keyframes:[MotionFrame] }
private struct Profile:Decodable { var entityID:String; var anchor:[Double]; var amplitudeMultiplier:Double; var facingDirection:Double }
private struct MotionDocument:Decodable { var motions:[String:Motion]; var entityProfiles:[Profile] }
private struct FXDocument:Decodable {
    struct FX:Decodable { var effectID:String; var durationMs:Double; var frameCount:Int; var frameWidthPx:Int; var frameHeightPx:Int }
    var effects:[FX]
}
private enum MotionLibrary {
    static let doc = GameArt.data("character-motion").flatMap { try? JSONDecoder().decode(MotionDocument.self,from:$0) }
    static let fx = GameArt.data("animation-manifest").flatMap { try? JSONDecoder().decode(FXDocument.self,from:$0) }?.effects ?? []
    static func value(_ frames:[MotionFrame],_ t:Double,_ key:KeyPath<MotionFrame,Double?>,_ fallback:Double) -> Double {
        let a = frames.last { $0.t <= t } ?? frames[0]
        let b = frames.first { $0.t >= t } ?? frames[frames.count-1]
        let mix = b.t == a.t ? 0 : (t-a.t)/(b.t-a.t)
        let av = a[keyPath:key] ?? fallback, bv = b[keyPath:key] ?? fallback
        return av+(bv-av)*mix
    }
}
struct UnitPortrait:View {
    let unit:PublicGameUnit
    var event:CommittedPresentation? = nil
    var animate = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.presentationReduceMotion) private var forcedReduceMotion
    private var reduceMotion:Bool { systemReduceMotion || forcedReduceMotion }
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:!animate || reduceMotion)) { context in
            GeometryReader { geometry in
                let row = event?.units.first { $0.id == unit.id }
                let age = context.date.timeIntervalSince(event?.start ?? context.date)
                let active = age >= 0 && age < 1.3
                let state = active ? (row?.motion ?? (unit.health == 0 ? "down" : "idle")) : (unit.health == 0 ? "down" : "idle")
                let motion = MotionLibrary.doc?.motions[state]
                let profile = MotionLibrary.doc?.entityProfiles.first { $0.entityID == unit.templateID }
                let duration = (motion?.durationMs ?? 1000)/1000
                let t = reduceMotion || !animate ? (["down","revive"].contains(state) ? 1.0 : 0.0) : state == "idle" ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:duration)/duration : min(1,max(0,age/duration))
                let frames = motion?.keyframes ?? []
                let x = frames.isEmpty ? 0 : MotionLibrary.value(frames,t,\.x,0)
                let y = frames.isEmpty ? 0 : MotionLibrary.value(frames,t,\.y,0)
                let rotation = frames.isEmpty ? 0 : MotionLibrary.value(frames,t,\.rotationDeg,0)
                let opacity = frames.isEmpty ? 1 : MotionLibrary.value(frames,t,\.opacity,1)
                let saturation = frames.isEmpty ? 1 : MotionLibrary.value(frames,t,\.saturation,1)
                let sx = frames.isEmpty ? 1 : MotionLibrary.value(frames,t,\.scaleX,1)
                let sy = frames.isEmpty ? 1 : MotionLibrary.value(frames,t,\.scaleY,1)
                ZStack {
                    ArtImage(type:unit.player ? "classes" : "monsters",id:unit.templateID)
                        .scaleEffect(x:sx,y:sy,anchor:UnitPoint(x:profile?.anchor.first ?? 0.5,y:profile?.anchor.last ?? 0.82))
                        .rotationEffect(.degrees(rotation)).opacity(opacity).saturation(saturation)
                        .offset(x:x*geometry.size.width*(profile?.amplitudeMultiplier ?? 1)*(profile?.facingDirection ?? 1),y:y*geometry.size.height*(profile?.amplitudeMultiplier ?? 1))
                    if active, let row { ForEach(row.effects,id:\.self) { effect in FXImage(effect:effect,age:age,reduced:reduceMotion) } }
                }
            }
        }.accessibilityLabel(unit.name + (unit.health == 0 ? "，倒地" : ""))
    }
}
private struct FXImage:View {
    let effect:String
    let age:Double
    let reduced:Bool
    var body:some View {
        if let fx = MotionLibrary.fx.first(where: { $0.effectID == effect }), age < fx.durationMs/1000,
           let cg = GameArt.image("effect",effect)?.cgImage {
            let index = reduced ? 3 : min(fx.frameCount-1,Int(age/(fx.durationMs/1000)*Double(fx.frameCount)))
            if let frame = cg.cropping(to:CGRect(x:index*fx.frameWidthPx,y:0,width:fx.frameWidthPx,height:fx.frameHeightPx)) {
                Image(uiImage:UIImage(cgImage:frame)).resizable().scaledToFit()
            }
        }
    }
}
struct CommittedFeedback:View {
    let events:[CommittedPresentation]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.presentationReduceMotion) private var forcedReduceMotion
    private var reduceMotion:Bool { systemReduceMotion || forcedReduceMotion }
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:events.isEmpty)) { context in
            if let event = events.first(where: { $0.isVisible(at:context.date) }) {
                let age = context.date.timeIntervalSince(event.start)
                let alpha = reduceMotion ? 1 : min(1,age/0.15,max(0,(1.3-age)/0.25))
                VStack(spacing:4) {
                    if !event.text.isEmpty { Text(event.text).fixedSize(horizontal:false,vertical:true) }
                    if !event.dice.isEmpty {
                        HStack {
                            ForEach(Array(event.dice.enumerated()),id:\.offset) { _,dice in
                                FXImage(effect:dice.formula.sides == 20 ? "dice20" : "dice6",age:age,reduced:reduceMotion).frame(width:36,height:36)
                                Text(dice.formula.label + "：" + dice.values.map(String.init).joined(separator:"、") + "＝\(dice.total)")
                            }
                        }
                    }
                }.font(.system(size:24,weight:.semibold)).padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14)).opacity(alpha)
            }
        }.allowsHitTesting(false)
    }
}

/// Keep complete item names and quantities; never overflow a television card.
struct InlineFlow:Layout {
    var spacing:CGFloat = 8
    private func positions(_ subviews:Subviews,width:CGFloat) -> (CGSize,[CGPoint]) {
        var points:[CGPoint] = [], x:CGFloat = 0, y:CGFloat = 0, rowHeight:CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x+size.width > width { y += rowHeight+spacing; x = 0; rowHeight = 0 }
            points.append(CGPoint(x:x,y:y)); x += size.width+spacing; rowHeight = max(rowHeight,size.height)
        }
        return (CGSize(width:width,height:y+rowHeight),points)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {
        positions(subviews,width:proposal.width ?? 1000).0
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let points = positions(subviews,width:bounds.width).1
        for index in subviews.indices { subviews[index].place(at:CGPoint(x:bounds.minX+points[index].x,y:bounds.minY+points[index].y),anchor:.topLeading,proposal:.unspecified) }
    }
}

private struct PresentationReduceMotionKey:EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Writable fixture override; production always also honors the system setting.
    var presentationReduceMotion:Bool {
        get { self[PresentationReduceMotionKey.self] }
        set { self[PresentationReduceMotionKey.self] = newValue }
    }
}
