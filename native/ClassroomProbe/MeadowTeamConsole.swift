import SwiftUI
import ClassroomGameCore

/// A private teacher sheet. Draft grouping commits once; public output contains
/// only the resulting game state and never this form or its resource controls.
struct MeadowTeamConsole:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var onClose:(()->Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var names:[String:String]=[:]
    @State private var members:[String:String]=[:]
    @State private var newName=""
    @State private var source="party"
    @State private var destination="party"
    private var teams:[GameTeam] {game.campaign?.engine.state.teams ?? []}
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    var body:some View {
        NavigationStack {
            Form {
                Section("队伍与成员 · 学生 \(players.filter{!$0.host}.count)/6") {
                    Text("换队保留个人背包、装备、生命、行动点与技能次数；队伍分实时相加。").font(.callout)
                    ForEach(players){unit in
                        Picker(unit.name,selection:Binding(get:{members[unit.id] ?? unit.teamID ?? "party"},set:{members[unit.id]=$0})){
                            ForEach(names.keys.sorted(),id:\.self){id in Text(names[id] ?? id).tag(id)}
                        }
                    }
                    HStack(spacing:8) {
                        GlassField(icon:"flag.fill",placeholder:"新队伍名",text:$newName,limit:20)
                        Button{
                            let clean=newName.trimmingCharacters(in:.whitespacesAndNewlines)
                            names["team-"+UUID().uuidString]=clean.isEmpty ? nextTeamName:clean;newName=""
                        }label:{Label("添加",systemImage:"plus.circle.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true))
                    }
                    ForEach(names.keys.sorted(),id:\.self){id in
                        GlassField(icon:"flag",placeholder:"队伍名称",text:Binding(get:{names[id] ?? ""},set:{names[id]=$0}),limit:20)
                    }
                    Button{
                        game.teamCommand(.configureTeams(names:names,members:members));reload()
                    }label:{Label("保存分组",systemImage:"checkmark.seal.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(locked)
                    if locked {Label("先让各队抵达地点再调整分组",systemImage:"figure.walk.motion").font(.caption).foregroundStyle(.secondary)}
                }.glassRow()
                Section("合并队伍") {
                    teamPicker("原队伍",selection:$source);teamPicker("合并到",selection:$destination)
                    Text("成员合并到目标队；原队保留为空队，个人资产不变。").font(.caption)
                    Button("执行合并"){
                        game.teamCommand(.mergeTeams(source:source,destination:destination));reload()
                    }.disabled(source==destination || locked)
                }.glassRow()
                Section("实时队伍积分") {
                    ForEach(teams){team in
                        let score=players.filter{$0.teamID==team.id}.reduce(0){$0+$1.score}
                        let coins=players.filter{$0.teamID==team.id}.reduce(0){$0+$1.coins}
                        Label("\(team.name) · 积分 \(score) · 金币 \(coins)",systemImage:"flag.fill").bold()
                    }
                    Label("队友之间赠送物品与金币请在行囊里操作（选中物品后下方「赠送给队友」）。",systemImage:"bag").font(.caption)
                }.glassRow()
                Section{Text(game.message).foregroundStyle(.secondary)}.glassRow()
            }.glassSheet().navigationTitle("队伍").toolbar{Button{if let onClose{onClose()}else{dismiss()}}label:{Image(systemName:"checkmark.circle.fill").font(.title2)}.accessibilityLabel("完成")}.onAppear{reload()}
        }
    }
    /// Grouping and merging change who walks together, so they wait until no team is on a road.
    private var locked:Bool {game.busy || game.campaign?.travel != nil || game.campaign?.parkedTravels.isEmpty==false}
    private var nextTeamName:String {
        let used=Set(names.values);let pool=["红队","蓝队","绿队","金队","紫队","橙队"]
        return pool.first{!used.contains($0)} ?? "第\(names.count+1)队"
    }
    private func reload(){names=Dictionary(uniqueKeysWithValues:teams.map{($0.id,$0.name)});members=Dictionary(uniqueKeysWithValues:players.map{($0.id,$0.teamID ?? "party")})}
    private func teamPicker(_ title:String,selection:Binding<String>)->some View {
        Picker(title,selection:selection){ForEach(teams){Text($0.name).tag($0.id)}}
    }
}
