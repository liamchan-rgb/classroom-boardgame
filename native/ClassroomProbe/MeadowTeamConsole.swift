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
                    HStack {
                        TextField("新队伍名称（用于建队或拆队）",text:$newName)
                        Button("添加队伍"){
                            names["team-"+UUID().uuidString]=newName.trimmingCharacters(in:.whitespacesAndNewlines);newName=""
                        }.disabled(newName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                    ForEach(names.keys.sorted(),id:\.self){id in
                        TextField("队伍名称",text:Binding(get:{names[id] ?? ""},set:{names[id]=$0}))
                    }
                    Button("保存分组"){
                        game.teamCommand(.configureTeams(names:names,members:members));reload()
                    }.disabled(game.busy || game.campaign?.travel != nil)
                }
                Section("合并队伍") {
                    teamPicker("原队伍",selection:$source);teamPicker("合并到",selection:$destination)
                    Text("成员与共享仓库一起合并到目标队；原队保留为空队，个人资产不变。").font(.caption)
                    Button("执行合并"){
                        game.teamCommand(.mergeTeams(source:source,destination:destination));reload()
                    }.disabled(source==destination || game.busy || game.campaign?.travel != nil)
                }
                Section("同队转交 / 仓库存取 · 仅探索") {
                    Picker("从",selection:$sender){ForEach(owners,id:\.0){Text($0.1).tag($0.0)}}
                    Picker("到",selection:$recipient){ForEach(owners,id:\.0){Text($0.1).tag($0.0)}}
                    HStack{Text("金币数量");TextField("0",text:$coins).keyboardType(.numberPad).multilineTextAlignment(.trailing)}
                    Picker("物品",selection:$item){
                        Text("只转金币").tag("")
                        ForEach(game.campaign?.engine.catalog.items ?? []){Text($0.name).tag($0.id)}
                    }
                    if !item.isEmpty {HStack{Text("物品数量");TextField("1",text:$quantity).keyboardType(.numberPad).multilineTextAlignment(.trailing)}}
                    Toggle("教师跨队调拨（记录后台操作）",isOn:$teacherTransfer)
                    Button(teacherTransfer ? "确认教师调拨":"确认同队转移"){
                        guard let value=Int(coins),let count=Int(quantity) else{return}
                        let command:GameCommand=teacherTransfer ? .teacherTransferTeamResource(from:owner(sender),to:owner(recipient),coins:value,item:item.isEmpty ? nil:item,count:item.isEmpty ? 0:count):.transferTeamResource(from:owner(sender),to:owner(recipient),coins:value,item:item.isEmpty ? nil:item,count:item.isEmpty ? 0:count)
                        game.teamCommand(command)
                    }.disabled(game.busy || game.campaign?.travel != nil || game.campaign?.engine.state.battle != nil || sender==recipient)
                    Text("行动点不可转移；战斗不能取仓库物品。跨队资源需显式启用教师调拨。").font(.caption)
                }
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
                }
                Section{Text(game.message).foregroundStyle(.secondary)}
            }.navigationTitle("队伍与仓库").toolbar{Button("完成"){if let onClose{onClose()}else{dismiss()}}}.onAppear{reload()}
        }
    }
    private func reload(){names=Dictionary(uniqueKeysWithValues:teams.map{($0.id,$0.name)});members=Dictionary(uniqueKeysWithValues:players.map{($0.id,$0.teamID ?? "party")})}
    private func owner(_ value:String)->TeamResourceOwner {value.hasPrefix("w:") ? .warehouse(String(value.dropFirst(2))):.player(String(value.dropFirst(2)))}
    private func teamPicker(_ title:String,selection:Binding<String>)->some View {
        Picker(title,selection:selection){ForEach(teams){Text($0.name).tag($0.id)}}
    }
}
