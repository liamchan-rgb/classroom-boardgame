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
    @State private var sender="p:p1"
    @State private var recipient="w:party"
    @State private var teacherTransfer=false
    @State private var coins="0"
    @State private var quantity="1"
    @State private var item=""
    private var teams:[GameTeam] {game.campaign?.engine.state.teams ?? []}
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var owners:[(String,String)] {players.map{("p:"+$0.id,$0.name)}+teams.map{("w:"+$0.id,$0.name+" · 共享仓库")}}
    var body:some View {
        NavigationStack {
            Form {
                Section("队伍与成员 · 学生 \(players.filter{!$0.host}.count)/6") {
                    Text("换队保留个人背包、装备、生命、行动点与技能次数；队伍分实时相加。旧队仓库不会随个人换队转走。").font(.callout)
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
                    Text("成员与共享仓库一起合并到目标队；原队保留为空队，个人资产不变。").font(.caption)
                    Button("执行合并"){
                        game.teamCommand(.mergeTeams(source:source,destination:destination));reload()
                    }.disabled(source==destination || locked)
                }.glassRow()
                Section("同队转交 / 仓库存取 · 仅探索") {
                    Picker("从",selection:$sender){ForEach(owners,id:\.0){Text($0.1).tag($0.0)}}
                    Picker("到",selection:$recipient){ForEach(owners,id:\.0){Text($0.1).tag($0.0)}}
                    GlassField(icon:"bitcoinsign.circle.fill",placeholder:"金币",text:$coins,limit:6,keyboard:.numberPad)
                    Picker("物品",selection:$item){
                        Text("只转金币").tag("")
                        ForEach(game.campaign?.engine.catalog.items ?? []){Text($0.name).tag($0.id)}
                    }
                    if !item.isEmpty {GlassField(icon:"number",placeholder:"数量",text:$quantity,limit:4,keyboard:.numberPad)}
                    Toggle("教师跨队调拨（记录后台操作）",isOn:$teacherTransfer)
                    Button(teacherTransfer ? "确认教师调拨":"确认同队转移"){
                        guard let value=Int(coins),let count=Int(quantity) else{return}
                        let command:GameCommand=teacherTransfer ? .teacherTransferTeamResource(from:owner(sender),to:owner(recipient),coins:value,item:item.isEmpty ? nil:item,count:item.isEmpty ? 0:count):.transferTeamResource(from:owner(sender),to:owner(recipient),coins:value,item:item.isEmpty ? nil:item,count:item.isEmpty ? 0:count)
                        game.teamCommand(command)
                    }.disabled(locked || game.campaign?.engine.state.battle != nil || sender==recipient)
                    Text("行动点不可转移；战斗不能取仓库物品。跨队资源需显式启用教师调拨。").font(.caption)
                }.glassRow()
                Section("仓库与实时队伍积分") {
                    ForEach(teams){team in
                        let score=players.filter{$0.teamID==team.id}.reduce(0){$0+$1.score}
                        VStack(alignment:.leading,spacing:5){
                            Text("\(team.name) · 积分 \(score) · 金币 \(team.coins)").bold()
                            ForEach(team.inventory.keys.sorted(),id:\.self){id in
                                Text("\((try? game.campaign?.engine.catalog.item(id).name) ?? id) ×\(team.inventory[id] ?? 0)")
                            }
                        }
                    }
                }.glassRow()
                Section{Text(game.message).foregroundStyle(.secondary)}.glassRow()
            }.glassSheet().navigationTitle("队伍与仓库").toolbar{Button{if let onClose{onClose()}else{dismiss()}}label:{Image(systemName:"checkmark.circle.fill").font(.title2)}.accessibilityLabel("完成")}.onAppear{reload()}
        }
    }
    /// Grouping and merging change who walks together, so they wait until no team is on a road.
    private var locked:Bool {game.busy || game.campaign?.travel != nil || game.campaign?.parkedTravels.isEmpty==false}
    private var nextTeamName:String {
        let used=Set(names.values);let pool=["红队","蓝队","绿队","金队","紫队","橙队"]
        return pool.first{!used.contains($0)} ?? "第\(names.count+1)队"
    }
    private func reload(){names=Dictionary(uniqueKeysWithValues:teams.map{($0.id,$0.name)});members=Dictionary(uniqueKeysWithValues:players.map{($0.id,$0.teamID ?? "party")})}
    private func owner(_ value:String)->TeamResourceOwner {value.hasPrefix("w:") ? .warehouse(String(value.dropFirst(2))):.player(String(value.dropFirst(2)))}
    private func teamPicker(_ title:String,selection:Binding<String>)->some View {
        Picker(title,selection:selection){ForEach(teams){Text($0.name).tag($0.id)}}
    }
}
