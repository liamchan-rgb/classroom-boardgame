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
    static let background = color("background",fallback:0xF5F1E8)
    static let ink = color("ink",fallback:0x183B36)
    static let muted = color("muted",fallback:0x526B64)
    static let primary = color("primary",fallback:0x176B5B)
    static let accent = color("accent",fallback:0xB76A08)
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
    let content:Content
    init(@ViewBuilder _ content:()->Content) { self.content = content() }
    var body:some View { content.padding(16).background(.white,in:RoundedRectangle(cornerRadius:16)) }
}
func nodeIcon(_ kind:NodeKind?) -> String {
    switch kind { case .start:return "house.fill"; case .combat:return "flame.fill"; case .boss:return "crown.fill"; case .reward:return "gift.fill"; case .empty:return "leaf.fill"; case nil:return "questionmark" }
}
