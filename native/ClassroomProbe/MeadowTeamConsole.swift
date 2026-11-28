import SwiftUI
import ClassroomGameCore

/// A private teacher sheet. Draft grouping commits once; public output contains
/// only the resulting game state and never this form or its resource controls.
struct MeadowTeamConsole:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var onClose:(()->Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var names:[String:String]=[:]
    @State private var removing:GameUnit?
    @State private var newName=""
    @State private var source="party"
    @State private var destination="party"
    private var teams:[GameTeam] {game.campaign?.engine.state.teams ?? []}
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    var body:some View {
        NavigationStack {
            Form {
                Section("玩家 · 学生 \(players.filter{!$0.host}.count)/6") {
                    Text("换队立即生效：玩家走到新队伍所在地点，保留个人背包、装备、生命、行动点与技能次数。退场会把他移出这局（作答记录保留在报告里），可在 存档 → 历史 里撤销。地图不会重新加载。").font(.callout)
                    ForEach(players){unit in
                        HStack(spacing:10) {
                            Text(unit.shortName).font(.body.bold()).frame(minWidth:90,alignment:.leading)
                            Picker("队伍",selection:Binding(get:{unit.teamID ?? "party"},set:{team in if team != unit.teamID {game.movePlayer(unit.id,toTeam:team)}})){
                                ForEach(teams){Text($0.name).tag($0.id)}
                            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:300)
                            Spacer()
                                .disabled(locked)
                            Button(role:.destructive){removing=unit}label:{Label("退场",systemImage:"person.fill.xmark")}
                                .buttonStyle(GlassIconButtonStyle()).disabled(game.busy || (!unit.host && players.filter{!$0.host}.count<=1) || game.campaign?.engine.state.battle?.current==unit.id)
                        }
                    }
                    if locked {Label("换队要等各队抵达地点、打完这场；退场和加入随时可以（战斗中也行）。",systemImage:"figure.walk.motion").font(.caption).foregroundStyle(.secondary)}
                }.glassRow()
                StudentJoinForm(game:game)
                Section("队伍名称") {
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
                        game.teamCommand(.configureTeams(names:names,members:[:]));reload()
                    }label:{Label("保存队名",systemImage:"checkmark.seal.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(locked)
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
            .confirmationDialog("让这名玩家退场？",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}}),titleVisibility:.visible,presenting:removing){unit in
                Button("\(unit.shortName) 退场",role:.destructive){game.removePlayer(unit.id);reload()}
                Button("取消",role:.cancel){}
            } message:{unit in Text("\(unit.shortName) 将离开这局游戏（金币、积分、背包随之移除；作答记录保留）。可在 存档 → 历史 里撤销。")}
        }
    }
    /// Changing teams or removing players changes who walks together, so it waits until no team is on a road or fighting.
    private var locked:Bool {game.busy || game.campaign?.travel != nil || game.campaign?.parkedTravels.isEmpty==false || game.campaign?.engine.state.battle != nil}
    private var nextTeamName:String {
        let used=Set(names.values);let pool=["红队","蓝队","绿队","金队","紫队","橙队"]
        return pool.first{!used.contains($0)} ?? "第\(names.count+1)队"
    }
    private func reload(){names=Dictionary(uniqueKeysWithValues:teams.map{($0.id,$0.name)})}
    private func teamPicker(_ title:String,selection:Binding<String>)->some View {
        Picker(title,selection:selection){ForEach(teams){Text($0.name).tag($0.id)}}
    }
}
