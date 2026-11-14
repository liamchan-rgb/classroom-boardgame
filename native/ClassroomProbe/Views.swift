import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TeacherConsole:View {
    @ObservedObject var session:TeacherSession
    @State private var tab=0
    var body:some View {
        TabView(selection:$tab) {
            MeadowTeacherDashboard(game:session.game).tabItem{Label("游戏",systemImage:"gamecontroller.fill")}.tag(0)
            TeacherBookConsole(session:session,game:session.game,showGame:{tab=0}).tabItem{Label("绘本",systemImage:"book.pages.fill")}.tag(1)
        }.preferredColorScheme(.light)
        // Opening the game tab while the book is on the TV brings the game back to the TV as well.
        .onChange(of:tab){_,value in
            if value==0,session.game.surface == .book {session.concealNotes();session.game.project(.exploration)}
        }
    }
}

private struct TeacherBookConsole:View {
    @ObservedObject var session:TeacherSession
    @ObservedObject var game:MeadowTeacherCoordinator
    var showGame:()->Void={}
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
                Button{notesFocused=false;game.openTimer()}label:{Label("计时",systemImage:"timer")}
                ClassroomScoreboardButton(overlays:game.overlays){game.toggleScoreboard()}
                Button{notesFocused=false;game.openShortcutEditor()}label:{Label("快捷键",systemImage:"keyboard")}
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
                Button{notesFocused=false;session.concealNotes();game.project(.exploration);showGame()}label:{Label("游戏",systemImage:"gamecontroller.fill")}
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
        .overlay {
            if let progress=session.importProgress {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(alignment:.leading,spacing:14){
                        Label("正在导入 PPTX",systemImage:"doc.badge.arrow.up").font(.headline)
                        ProgressView(value:progress.fraction).progressViewStyle(.linear).tint(GameTheme.primary)
                        HStack{Text(progress.stage);Spacer();Text("\(Int((progress.fraction*100).rounded()))%").monospacedDigit()}
                            .font(.callout).foregroundStyle(GameTheme.muted)
                    }.frame(width:420).glassPanel(radius:22,padding:22)
                }.transition(.opacity)
            }
        }
        .animation(.easeOut(duration:0.2),value:session.importProgress?.fraction)
        .alert("PPTX 导入",isPresented:Binding(get:{session.importOutcome != nil},set:{if !$0{session.importOutcome=nil}})){
            Button("好"){session.importOutcome=nil}
            Button("导入报告"){session.importOutcome=nil;report=true}
        }message:{Text(session.importOutcome ?? "")}
        .onChange(of:notesFocused){_,active in session.notesFocus(active)}
        .onChange(of:session.showNotes){_,value in if !value{notesFocused=false}}
        .sheet(isPresented:$report){NavigationStack{ScrollView{Text(session.importReport).padding()}.navigationTitle("PPTX导入报告").toolbar{Button("完成"){report=false}}}}
        .sheet(isPresented:Binding(get:{exportingURL != nil},set:{if !$0{exportingURL=nil}})){if let url=exportingURL{ExportDocument(url:url)}}
    }
    /// 选文件改用 UIKit 的文档选择器，从最上层的界面弹出。原来的 SwiftUI .fileImporter 从「文件」菜单里点时，
    /// 菜单还在收起就要弹窗，和同一视图上的两个 .sheet 冲突，会静默弹不出来（点了导入没反应）。
    private func openImporter(){
        notesFocused=false;session.pause(.filePicker,enabled:true)
        let backup=importingBackup
        let types:[UTType]=backup ? [.json]:[UTType("org.openxmlformats.presentationml.presentation"),UTType(filenameExtension:"pptx")].compactMap{$0}
        DocumentImportPresenter.shared.present(types:types.isEmpty ? [.data]:types){url in
            session.pause(.filePicker,enabled:false)
            guard let url else{return}
            if backup{session.importBackup(url)}else{session.loadPPTX(url)}
        }
    }
}

/// 用 UIKit 弹出系统的文件选择器：等「文件」菜单收起后，从当前最上层的界面弹出；选中的文件复制一份到本 App 再读，不依赖外部授权。
@MainActor
final class DocumentImportPresenter:NSObject,UIDocumentPickerDelegate {
    static let shared=DocumentImportPresenter()
    private var completion:((URL?)->Void)?
    func present(types:[UTType],completion:@escaping (URL?)->Void) {
        self.completion?(nil)
        self.completion=completion
        // 菜单收起的动画结束后再弹
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35){[weak self] in
            guard let self else{return}
            guard let top=Self.topController() else{self.finish(nil);return}
            let picker=UIDocumentPickerViewController(forOpeningContentTypes:types,asCopy:true)
            picker.delegate=self
            picker.allowsMultipleSelection=false
            picker.modalPresentationStyle = .formSheet
            top.present(picker,animated:true)
        }
    }
    private func finish(_ url:URL?){let done=completion;completion=nil;done?(url)}
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){finish(urls.first)}
    func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){finish(nil)}
    /// 本机交互窗口（不是电视投放窗口）里最上层、没有正在消失的界面
    static func topController()->UIViewController? {
        let scenes=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.filter{$0.session.role == .windowApplication}
        let window=scenes.flatMap(\.windows).first{$0.isKeyWindow} ?? scenes.flatMap(\.windows).first
        var top=window?.rootViewController
        while let next=top?.presentedViewController,!next.isBeingDismissed{top=next}
        return top
    }
}

struct ExportDocument:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIDocumentPickerViewController{UIDocumentPickerViewController(forExporting:[url],asCopy:true)}
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context){}
}
