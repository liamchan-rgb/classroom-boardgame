import SwiftUI
import ClassroomGameCore

enum GameTheme {
    private struct Tokens: Decodable { var colors: [String:String] }
    private static let colors: [String:String] = {
        guard let url = Bundle.main.url(forResource:"design-tokens",withExtension:"json"),
              let bytes = try? Data(contentsOf:url), let tokens = try? JSONDecoder().decode(Tokens.self,from:bytes) else { return [:] }
        return tokens.colors
    }()
    static func color(_ name:String, fallback:UInt32) -> Color {
        let value = colors[name].flatMap { UInt32($0.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) } ?? fallback
        return Color(red:Double((value >> 16) & 255)/255,green:Double((value >> 8) & 255)/255,blue:Double(value & 255)/255)
    }
    static let background = color("background",fallback:0xF5FAFC)
    static let ink = color("ink",fallback:0x173F50)
    static let muted = color("muted",fallback:0x4C6875)
    static let primary = color("primary",fallback:0x176A86)
    static let accent = color("accent",fallback:0x995207)
    static let danger = color("danger",fallback:0xB93838)
    static let shield = color("shield",fallback:0x315E9C)
    static let action = color("action",fallback:0x6650A4)
}
extension GamePhase {
    var displayName:String {
        switch self { case .preparation:return "准备"; case .exploration:return "探索"; case .pve:return "PVE战斗"; case .teamPvp:return "团队PVP"; case .freeForAll:return "混战"; case .settlement:return "结算" }
    }
}
extension GamePause {
    var displayName:String {
        switch self {
        case .manual:return "手动暂停"; case .book:return "绘本"; case .editor:return "教师面板"; case .history:return "历史"; case .background:return "后台"; case .allPlayersDown:return "全员倒地"; case .noSurvivors:return "无存活阵营"
        }
    }
}
struct GamePanel<Content:View>:View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let content:Content
    let inset:CGFloat
    init(inset:CGFloat = 16,@ViewBuilder _ content:()->Content) { self.content = content(); self.inset = inset }
    var body:some View { content.padding(inset)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius:16).fill(.white) }
            else { RoundedRectangle(cornerRadius:16).fill(.regularMaterial) }
        }
        .overlay(RoundedRectangle(cornerRadius:16).stroke(GameTheme.primary.opacity(0.12),lineWidth:1)) }
}
func nodeIcon(_ kind:NodeKind?) -> String {
    switch kind { case .start:return "house.fill"; case .combat:return "flame.fill"; case .boss:return "crown.fill"; case .reward:return "gift.fill"; case .empty:return "leaf.fill"; case nil:return "questionmark" }
}

struct ClassroomButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.padding(.horizontal,10).frame(minWidth:44,minHeight:44)
            .foregroundStyle(primary && enabled ? .white : GameTheme.ink)
            .background(primary && enabled ? GameTheme.primary : Color.white.opacity(enabled ? 0.9 : 0.45),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(GameTheme.primary.opacity(0.2),lineWidth:1))
            .opacity(configuration.isPressed ? 0.7 : enabled ? 1 : 0.55)
    }
}

struct PlayerSelectionStyle:ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.foregroundStyle(GameTheme.ink).opacity(configuration.isPressed ? 0.8 : 1)
    }
}
