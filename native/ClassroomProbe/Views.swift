import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TeacherConsole:View {
    @ObservedObject var session:TeacherSession
    var body:some View {
        TabView {
            MeadowTeacherDashboard(game:session.game).tabItem{Label("游戏",systemImage:"gamecontroller.fill")}
            TeacherBookConsole(session:session,game:session.game).tabItem{Label("绘本",systemImage:"book.pages.fill")}
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
            HStack(spacing:8){
                Label("绘本",systemImage:"book.pages.fill").font(.system(size:20,weight:.bold,design:.rounded))
                GlassChip(icon:"tv",text:session.registrationStatus.contains("连接") ? "TV":"—",tint:GameTheme.muted).lineLimit(1)
                Spacer()
                Button{notesFocused=false;game.openGM()}label:{Label("GM",systemImage:"wand.and.stars")}.disabled(game.busy || game.campaign==nil)
                Button{notesFocused=false;game.openArchives()}label:{Label("存档",systemImage:"archivebox")}.disabled(game.busy)
                Button{notesFocused=false;game.openCharacterStudio()}label:{Label("形象",systemImage:"person.crop.circle.badge.plus")}.disabled(game.busy)
                Menu {
                    Button{session.loadSample()}label:{Label("内置示例",systemImage:"doc.richtext")}
                    Button{importingBackup=false;openImporter()}label:{Label("导入 PPTX",systemImage:"square.and.arrow.down")}
                    Button{report=true}label:{Label("导入报告",systemImage:"list.bullet.clipboard")}
                    Divider()
                    Button{session.save()}label:{Label("保存",systemImage:"externaldrive.badge.checkmark")}
                    Button{session.restoreLocal()}label:{Label("恢复",systemImage:"clock.arrow.circlepath")}
                    Button{exportingURL=session.exportedURL()}label:{Label("导出备份",systemImage:"square.and.arrow.up")}
                    Button{importingBackup=true;openImporter()}label:{Label("导入备份",systemImage:"tray.and.arrow.down")}
                }label:{Label("文件",systemImage:"folder")}
            }.buttonStyle(GlassIconButtonStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            HStack(spacing:8){
                Button{notesFocused=false;game.project(.book)}label:{Label("投放",systemImage:"tv.and.mediabox")}.buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(game.busy)
                Button{notesFocused=false;session.concealNotes();game.project(.exploration)}label:{Label("游戏",systemImage:"gamecontroller.fill")}
                Divider().frame(height:36)
                Button{session.turnPage(-1)}label:{Label("上页",systemImage:"chevron.left")}
                GlassChip(icon:"doc.plaintext",text:"\(session.state.pageCount==0 ? 0:session.state.pageIndex+1) / \(session.state.pageCount)")
                Button{session.turnPage(1)}label:{Label("下页",systemImage:"chevron.right")}
                Spacer(minLength:0)
            }.buttonStyle(GlassIconButtonStyle()).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            TeacherBookGrantBar(game:game,prepare:{notesFocused=false})
            HStack(alignment:.top,spacing:12){
                PublicBookPage(model:session.display,players:game.backend.bookPlayers).frame(maxWidth:.infinity,maxHeight:.infinity)
                    .clipShape(RoundedRectangle(cornerRadius:18,style:.continuous)).overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(.white.opacity(0.5),lineWidth:1))
                VStack(alignment:.leading,spacing:8){
                    Toggle(isOn:$session.showNotes){Label("备注",systemImage:"note.text")}.font(.headline)
                    if session.showNotes {
                        TextEditor(text:Binding(get:{session.currentNote},set:{session.editNote($0)})).focused($notesFocused)
                            .scrollContentBackground(.hidden).padding(6).background(.white.opacity(0.35),in:RoundedRectangle(cornerRadius:12,style:.continuous))
                    }else{Label("仅本机可见",systemImage:"eye.slash").font(.caption).foregroundStyle(.secondary);Spacer()}
                }.frame(width:280).frame(maxHeight:.infinity,alignment:.top).glassPanel()
            }.frame(maxHeight:.infinity)
            HStack(spacing:6){Image(systemName:"info.circle").foregroundStyle(GameTheme.primary);Text(game.message+" · "+session.message).lineLimit(1)}
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal,14).frame(height:28).glassPanel(radius:14,padding:0)
        }.padding(12).background(GlassBackdrop()).foregroundStyle(GameTheme.ink)
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
