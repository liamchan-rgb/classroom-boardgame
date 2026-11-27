import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomProbeCore

struct TeacherConsole:View {
    @ObservedObject var session:TeacherSession
    @State private var tab=0
    var body:some View {
        TabView(selection:$tab) {
            MeadowTeacherDashboard(game:session.game).tabItem{Label("游戏",systemImage:"gamecontroller.fill")}.tag(0)
            TeacherBookConsole(session:session,game:session.game,showGame:{tab=0}).tabItem{Label("绘本",systemImage:"book.pages.fill")}.tag(1)
        }.preferredColorScheme(.light)
        .overlay(alignment:.top){ClassroomGrantCaptureBanner(game:session.game).padding(.top,8)}
        // Opening the game tab while the book is on the TV brings the game back to the TV as well.
        // A deck opened from the game tab's 课件 list shows on the book tab.
        .onChange(of:session.bookTabRequest){_,_ in tab=1}
        .onChange(of:tab){_,value in
            session.game.bookTabActive = value==1
            if value==0 {
                KeyHostingController<EmptyView>.endEditing()
                session.concealNotes()
                if session.game.surface == .book {session.game.project(.exploration)}
            }
            // Opening the book tab puts the picture book on the TV straight away.
            if value==1,session.game.surface != .book,!session.game.busy {session.game.project(.book)}
        }
    }
}

private struct TeacherBookConsole:View {
    @ObservedObject var session:TeacherSession
    @ObservedObject var game:MeadowTeacherCoordinator
    var showGame:()->Void={}
    @State private var importingBackup=false
    @State private var notesSelection:NotesSelectionTarget?
    @State private var report=false
    @State private var exportingURL:URL?
    @State private var decks=false
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            HStack(spacing:8){
                Label("绘本",systemImage:"book.pages.fill").font(.system(size:20,weight:.bold,design:.rounded))
                GlassChip(icon:"tv",text:session.registrationStatus.contains("连接") ? "TV":"—",tint:GameTheme.muted).lineLimit(1)
                #if targetEnvironment(macCatalyst)
                MacPublicWindowButton(connected:game.externalConnected)
                MacMirrorWarning()
                #else
                IPadPublicScreenButton(session:TeacherSession.shared,connected:game.externalConnected)
                #endif
                Spacer()
                ClassroomToolbarTools(game:game,prepare:{KeyHostingController<EmptyView>.endEditing()})
                ToolbarGap()
                Button{KeyHostingController<EmptyView>.endEditing();decks=true}label:{Label("课件",systemImage:"rectangle.stack")}
                // Like the game tab: the less used things in one grouped menu.
                Menu {
                    Section("课件文件") {
                        Button{importingBackup=false;openImporter()}label:{Label("导入 PPTX",systemImage:"square.and.arrow.down")}
                        Button{report=true}label:{Label("上次导入报告",systemImage:"list.bullet.clipboard")}
                        Button{session.loadSample()}label:{Label("内置示例课件",systemImage:"doc.richtext")}
                        Menu {
                            Button{session.save()}label:{Label("保存",systemImage:"externaldrive.badge.checkmark")}
                            Button{session.restoreLocal()}label:{Label("恢复上次保存",systemImage:"clock.arrow.circlepath")}
                            Button{exportingURL=session.exportedURL()}label:{Label("导出备份",systemImage:"square.and.arrow.up")}
                            Button{importingBackup=true;openImporter()}label:{Label("导入备份",systemImage:"tray.and.arrow.down")}
                        }label:{Label("备份与恢复",systemImage:"externaldrive")}
                    }
                    Section("行程") {
                        Button{KeyHostingController<EmptyView>.endEditing();game.openArchives()}label:{Label("存档与历史",systemImage:"archivebox")}.disabled(game.busy)
                    }
                    Section("工具") {
                        Button{KeyHostingController<EmptyView>.endEditing();game.openGM()}label:{Label("GM 修改数值",systemImage:"wand.and.stars")}.disabled(game.busy || game.campaign==nil)
                        Button{KeyHostingController<EmptyView>.endEditing();game.openCharacterStudio()}label:{Label("人物形象",systemImage:"person.crop.circle.badge.plus")}.disabled(game.busy)
                    }
                    Menu {
                        Button{KeyHostingController<EmptyView>.endEditing();game.openShortcutEditor()}label:{Label("快捷键",systemImage:"keyboard")}
                    }label:{Label("设置",systemImage:"gearshape")}
                }label:{Label("更多",systemImage:"ellipsis.circle")}
            }.buttonStyle(ToolbarIconStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            // The deck list sits on the toolbar (not beside the other sheets: two sheets on one view conflict).
            .sheet(isPresented:$decks){
                DeckLibraryPanel(session:session,onImport:{decks=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.5){importingBackup=false;openImporter()}},onClose:{decks=false})
                    .presentationDetents([.large])
            }
            .onChange(of:session.importRequest){_,_ in importingBackup=false;openImporter()}
            HStack(spacing:8){
                // No 投放 / 游戏 buttons here: opening this tab already puts the book on the TV, and the 游戏 tab
                // brings the game back (both did exactly what the tabs do).
                Button{session.turnPage(-1)}label:{Label("上页",systemImage:"chevron.left")}
                PageJumpChip(session:session)
                DeckBuildChip(model:session.display)
                Button{session.turnPage(1)}label:{Label("下页",systemImage:"chevron.right")}
                Spacer(minLength:0)
            }.buttonStyle(GlassIconButtonStyle()).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            HStack(alignment:.top,spacing:12){
                VStack(spacing:8){
                    PublicBookPage(model:session.display,players:game.backend.bookPlayers,draggable:true).frame(minWidth:0,maxWidth:.infinity,maxHeight:.infinity)
                        // The teacher's preview shows the same countdown / scoreboard as the TV.
                        .overlay{ClassroomTVOverlays(timer:game.classTimer,overlays:game.overlays,game:game,teacherPreview:true)}
                        .overlay{MiniGameTapLayer(game:game)}
                        .overlay{QuizCardDragLayer(game:game)}
                        .overlay{QuizRevealTapCatcher(game:game)}
                        .overlay{LaserCapture(laser:game.laser)}
                        .clipShape(RoundedRectangle(cornerRadius:18,style:.continuous)).overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(.white.opacity(0.5),lineWidth:1))
                    MiniGameBar(game:game)
                    // Right under the page, next to the players' cards the boxes are dragged onto (drawn over the page while dragging).
                    TeacherBookGrantBar(game:game,draft:game.grantDraft,prepare:{KeyHostingController<EmptyView>.endEditing()}).zIndex(1)
                }
                QuizDock(game:game,book:true)
                VStack(alignment:.leading,spacing:8){
                    // Always shown and directly editable with live bold / underline formatting (no lock button or raw markers).
                    HStack{
                        Label("备注",systemImage:"note.text").font(.headline)
                        Spacer()
                    }
                    ZStack(alignment:.topLeading) {
                        if session.currentNote.isEmpty {
                            Text(session.state.pageCount > 0 ? "点击输入备注（⌘B 粗体，⌘U 下划线）" : "先导入或打开课件后再编辑备注")
                                .font(.system(size:17))
                                .foregroundStyle(.secondary.opacity(0.6))
                                .padding(.horizontal,11).padding(.vertical,16)
                                .allowsHitTesting(false)
                        }
                        NotesWordText(
                            raw:session.currentNote,
                            editable:session.state.pageCount > 0,
                            onEdit:{session.editNote($0)},
                            onFocus:{session.notesFocus($0)},
                            onPick:{pick,rect,view in game.openWordCard(pick,rect:rect,in:view)},
                            onPickSelection:{selection,rect,view in game.openSelectionCard(selection,rect:rect,in:view)},
                            onSelectionChange:{notesSelection=$0}
                        )
                        .onAppear{NotesDictionary.shared.prewarm()}
                    }
                    .overlay {
                        if let target=notesSelection,session.state.pageCount > 0 {
                            NotesSelectionBubble(
                                target:target,
                                inDeck:game.existingSelectionCard(target.term) != nil,
                                replacing:game.quiz != nil,
                                onTrigger:{target.trigger()}
                            )
                        }
                    }
                    .zIndex(2)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                    .padding(6)
                    .background(.white.opacity(0.35),in:RoundedRectangle(cornerRadius:12,style:.continuous))
                    Text("双击单词出闪卡 · 框选按 K · ⌘B 粗体 · ⌘U 下划线")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
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
        // Book tab opened while the game was busy: put the book on the TV once it is free (this used to need 投放).
        .onChange(of:game.busy){_,busy in if !busy,game.bookTabActive,game.surface != .book {game.project(.book)}}
        .sheet(isPresented:$report){NavigationStack{ScrollView{Text(session.importReport).padding()}.navigationTitle("PPTX导入报告").toolbar{Button("完成"){report=false}}}}
        .sheet(isPresented:Binding(get:{exportingURL != nil},set:{if !$0{exportingURL=nil}})){if let url=exportingURL{ExportDocument(url:url)}}
    }
    /// 选文件改用 UIKit 的文档选择器，从最上层的界面弹出。原来的 SwiftUI .fileImporter 从「文件」菜单里点时，
    /// 菜单还在收起就要弹窗，和同一视图上的两个 .sheet 冲突，会静默弹不出来（点了导入没反应）。
    private func openImporter(){
        KeyHostingController<EmptyView>.endEditing();session.pause(.filePicker,enabled:true)
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

/// Speaker-notes markup from the PPT import: **bold** and __underline__ (they can nest).
enum NotesMarkup {
    static func attributed(_ raw:String)->AttributedString {
        var out=AttributedString()
        for span in NotesMarkupCodec.parse(raw) {
            var piece=AttributedString(span.text)
            if span.bold {piece.inlinePresentationIntent = .stronglyEmphasized;piece.font = .system(size:17,weight:.bold)}
            if span.underline {piece.underlineStyle = .single}
            out.append(piece)
        }
        return out
    }
}

/// Animations left on this slide: "下页" plays the next one before turning the page.
/// The page counter; tap it (or press P) to type a page number and press Return to jump there.
private struct PageJumpChip:View {
    @ObservedObject var session:TeacherSession
    @State private var editing=false
    @State private var text=""
    var body:some View {
        Group {
            if editing {
                HStack(spacing:5){
                    Image(systemName:"arrow.right.doc.on.clipboard").font(.system(size:13,weight:.bold)).foregroundStyle(GameTheme.primary)
                    ClassroomTextField(placeholder:"页码",text:$text,limit:4,keyboard:.numberPad,alignment:.center,
                                       onSubmit:jump,autoFocus:true,onEndEditing:{editing=false}).frame(width:56,height:22)
                    Text("/ \(session.state.pageCount)").font(.system(size:14,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(GameTheme.ink)
                }
                .padding(.horizontal,10).padding(.vertical,6)
                .background(GlassFill.field,in:Capsule())
                .overlay(Capsule().stroke(GameTheme.primary.opacity(0.8),lineWidth:1.5))
            } else {
                Button{open()}label:{GlassChip(icon:"doc.plaintext",text:"\(session.state.pageCount==0 ? 0:session.state.pageIndex+1) / \(session.state.pageCount)")}
                    .buttonStyle(.plain).help("跳到指定页 (P)").accessibilityLabel("跳到指定页")
            }
        }
        .onChange(of:session.pageJumpRequest){_,_ in open()}
    }
    private func open() {guard session.state.pageCount>0 else{return};text="";editing=true}
    private func jump() {
        // Full-width digits (Chinese keyboard) count too.
        let digits=text.unicodeScalars.compactMap{s->Character? in
            if ("0"..."9").contains(Character(s)) {return Character(s)}
            if (0xFF10...0xFF19).contains(s.value) {return Character(UnicodeScalar(s.value-0xFF10+48)!)}
            return nil}
        if let number=Int(String(digits)),number>0 {session.goToPage(number)}
        editing=false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
    }
}
private struct DeckBuildChip:View {
    @ObservedObject var model:PublicDisplayModel
    var body:some View {
        if let page=model.page,!page.clicks.isEmpty {
            GlassChip(icon:"sparkles",text:"动画 \(model.buildStep)/\(page.clicks.count)")
        }
    }
}
