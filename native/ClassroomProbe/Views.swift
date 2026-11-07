import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TeacherConsole:View {
    @ObservedObject var session:TeacherSession
    var body:some View {
        TabView {
            MeadowTeacherDashboard(game:session.game).tabItem{Label("游戏后台",systemImage:"slider.horizontal.3")}
            TeacherBookConsole(session:session,game:session.game).tabItem{Label("绘本与备注",systemImage:"book.closed")}
        }.preferredColorScheme(.light)
    }
}

private struct TeacherBookConsole:View {
    @ObservedObject var session:TeacherSession
    @ObservedObject var game:MeadowTeacherCoordinator
    @State private var importer=false
    @State private var importingBackup=false
    @State private var report=false
    @State private var exportingURL:URL?
    @FocusState private var notesFocused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            HStack {
                Text("教师绘本后台").font(.title2.bold())
                Text(session.registrationStatus).font(.caption).lineLimit(1)
                Spacer()
                Button("GM窗口"){notesFocused=false;game.openGM()}.disabled(game.busy || game.campaign==nil)
                Button("存档与历史"){notesFocused=false;game.openArchives()}.disabled(game.busy)
                Menu("绘本文件") {
                    Button("加载内置测试PPTX"){session.loadSample()}
                    Button("导入PPTX"){importingBackup=false;openImporter()}
                    Button("导入报告"){report=true}
                    Button("保存绘本"){session.save()}
                    Button("恢复绘本"){session.restoreLocal()}
                    Button("导出绘本备份"){exportingURL=session.exportedURL()}
                    Button("导入绘本备份"){importingBackup=true;openImporter()}
                }
            }
            HStack {
                Button("投放绘本"){notesFocused=false;game.project(.book)}.disabled(game.busy)
                Button("返回游戏画面"){notesFocused=false;session.concealNotes();game.project(.exploration)}
                Button("上一页"){session.turnPage(-1)}
                Button("下一页"){session.turnPage(1)}
                Text("\(session.state.pageCount==0 ? 0:session.state.pageIndex+1) / \(session.state.pageCount)")
            }.buttonStyle(ClassroomButtonStyle(primary:true))
            TeacherBookGrantBar(game:game,prepare:{notesFocused=false})
            HStack(alignment:.top,spacing:16){
                PublicBookPage(model:session.display,players:game.backend.bookPlayers).frame(maxWidth:.infinity,maxHeight:.infinity)
                VStack(alignment:.leading,spacing:8){
                    Toggle("显示教师备注",isOn:$session.showNotes)
                    if session.showNotes {
                        TextEditor(text:Binding(get:{session.currentNote},set:{session.editNote($0)})).focused($notesFocused)
                    }else{Text("备注不会投放到游戏窗口。").foregroundStyle(.secondary);Spacer()}
                }.frame(width:280)
            }.frame(maxHeight:.infinity)
            Text(game.message+" · "+session.message).font(.caption).lineLimit(1).foregroundStyle(.secondary)
        }.padding(16).background(GameTheme.background).foregroundStyle(GameTheme.ink)
        .onChange(of:notesFocused){_,active in session.notesFocus(active)}
        .onChange(of:session.showNotes){_,value in if !value{notesFocused=false}}
        .fileImporter(isPresented:$importer,allowedContentTypes:importingBackup ? [.json]:[UTType(filenameExtension:"pptx") ?? .data]){result in
            defer{session.pause(.filePicker,enabled:false)}
            switch result{case .success(let url):if importingBackup{session.importBackup(url)}else{session.loadPPTX(url)};case .failure(let error):session.fileSelectionFailed(error)}
        }
        .sheet(isPresented:$report){NavigationStack{ScrollView{Text(session.importReport).padding()}.navigationTitle("PPTX导入报告").toolbar{Button("完成"){report=false}}}}
        .sheet(isPresented:Binding(get:{exportingURL != nil},set:{if !$0{exportingURL=nil}})){if let url=exportingURL{ExportDocument(url:url)}}
    }
    private func openImporter(){notesFocused=false;session.pause(.filePicker,enabled:true);importer=true}
}

struct ExportDocument:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIDocumentPickerViewController{UIDocumentPickerViewController(forExporting:[url],asCopy:true)}
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context){}
}
