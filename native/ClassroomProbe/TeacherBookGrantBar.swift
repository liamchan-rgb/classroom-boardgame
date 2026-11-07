import SwiftUI
import ClassroomGameCore

struct TeacherBookGrantBar:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var prepare:()->Void={}
    @State private var recipients=Set<String>()
    @State private var ap="1"
    @State private var coins="10"
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var selected:[String] {players.map(\.id).filter{recipients.contains($0)}}
    var body:some View {
        HStack(spacing:10){
            Menu("奖励对象 · \(selected.count)人") {
                Button("全选"){recipients=Set(players.map(\.id))}
                Button("清空选择"){recipients=[]}
                ForEach(players){unit in
                    Button{if recipients.contains(unit.id){recipients.remove(unit.id)}else{recipients.insert(unit.id)}}label:{Label(unit.name,systemImage:recipients.contains(unit.id) ? "checkmark.circle.fill":"circle")}
                }
            }
            HStack{Text("行动点");TextField("1",text:$ap).keyboardType(.numberPad).frame(width:48)}
            HStack{Text("金币");TextField("10",text:$coins).keyboardType(.numberPad).frame(width:60)}
            Button("发放"){
                prepare();guard let a=Int(ap),let c=Int(coins) else{return}
                game.grantBookPlayers(selected,ap:a,coins:c)
            }.disabled(game.busy)
            Menu("快捷奖励") {
                Button("行动点＋1"){prepare();game.grantBookPlayers(selected,ap:1,coins:0)}.disabled(selected.isEmpty)
                Button("金币＋10"){prepare();game.grantBookPlayers(selected,ap:0,coins:10)}.disabled(selected.isEmpty)
                Divider()
                Button("撤销最近一次GM/发放"){prepare();game.undoTeacherAction()}.disabled(!game.backend.canUndoTeacherAction)
            }.disabled(game.busy)
            Spacer(minLength:0)
        }.font(.callout).buttonStyle(.bordered).padding(10).background(.white.opacity(0.75),in:RoundedRectangle(cornerRadius:10))
            .disabled(players.isEmpty || game.campaign?.isCompleted==true)
            .onAppear{if let id=game.campaign?.selectedPlayerID{recipients=[id]}}
    }
}
