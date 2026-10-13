import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomProbeCore

@MainActor
struct PublicSurface: View {
    @ObservedObject var model: PublicDisplayModel
    var body: some View {
        if let frame = model.playFrame {
            PVEPublicView(frame: frame, image: model.playBook ? model.image : nil, showingBook: model.playBook)
        } else if let example = model.ruleExample {
            GameExamplePublicView(snapshot: example)
        } else {
            LegacyPublicBook(snapshot:model.snapshot,image:model.image)
        }
    }
}

/// The retained stage0 book entry uses the same local theme and six public fields.
private struct LegacyPublicBook:View {
    let snapshot:PublicSnapshot
    let image:UIImage?
    var body:some View {
        GeometryReader { geometry in
            let width = geometry.size.width/geometry.size.height > 1.5 ? 1920.0 : 1440.0
            let scale = min(geometry.size.width/width,geometry.size.height/1080)
            VStack(spacing:16) {
                HStack {
                    Text("英语课堂 · 绘本").font(.system(size:30,weight:.bold))
                    Spacer()
                    Text(snapshot.paused ? "已暂停" : "计时中")
                    Text("\(Int(ceil(snapshot.remainingSeconds)))秒").monospacedDigit()
                    Text("\(snapshot.pageCount == 0 ? 0 : snapshot.pageIndex+1) / \(snapshot.pageCount)")
                }.font(.system(size:28)).frame(height:60)
                if let image { Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity) }
                else { Text("教师正在准备绘本").font(.system(size:36)).frame(maxWidth:.infinity,maxHeight:.infinity) }
                HStack(alignment:.top,spacing:8) {
                    ForEach(snapshot.players) { player in
                        VStack(alignment:.leading,spacing:4) {
                            Text(player.name).bold().fixedSize(horizontal:false,vertical:true).frame(height:62,alignment:.top)
                            ResourceValue(id:"health",text:"\(player.health)/\(player.maxHealth)")
                            ResourceValue(id:"shield",text:String(player.shield))
                            ResourceValue(id:"coin",text:String(player.coins))
                            ResourceValue(id:"score",text:String(player.score))
                            HStack(spacing:4) { TeamMark(id:player.team); Text(player.team) }
                        }.font(.system(size:26)).padding(10).frame(maxWidth:.infinity,alignment:.leading)
                            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                    }
                }.frame(height:244)
            }.padding(.horizontal,width*0.05).padding(.vertical,54).frame(width:width,height:1080).scaleEffect(scale)
                .frame(width:geometry.size.width,height:geometry.size.height)
        }.foregroundStyle(GameTheme.ink).background(GameTheme.background).preferredColorScheme(.light)
    }
}

@MainActor
struct TeacherConsole: View {
    @ObservedObject var session: TeacherSession
    @State private var showImporter = false
    @State private var importingBackup = false
    @State private var showReport = false
    @State private var exportingURL: URL?
    @State private var showExporter = false
    @State private var showRules = false
    @State private var showPlay = false
    @FocusState private var notesFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("晴空学园 · v0.9", systemImage: "book.closed.fill").font(.title2.bold())
                    Spacer()
                    Text("公开场景 \(session.connectionCount)").font(.headline)
                }
                Text(session.registrationStatus).foregroundStyle(.secondary)
                Text(session.message).font(.callout)
                Button("进入PVE课堂") {
                    notesFocused = false
                    session.beginPlay()
                    showPlay = true
                }.buttonStyle(ClassroomButtonStyle(primary:true))
                Button("规则示例与初始资料") {
                    notesFocused = false
                    session.beginRules()
                    showRules = true
                }.buttonStyle(ClassroomButtonStyle(primary:true))
                HStack(spacing: 8) {
                    ForEach(session.state.players) { player in
                        Button(player.name) { session.select(player.id) }
                            .buttonStyle(ClassroomButtonStyle())
                            .tint(player.id == session.state.selectedPlayerID ? .blue : .gray)
                    }
                }
                HStack {
                    Button("发10金币（G）") { session.award() }.buttonStyle(ClassroomButtonStyle(primary:true))
                    Button("暂停／继续（空格）") { session.togglePause() }.buttonStyle(ClassroomButtonStyle())
                    Button("重置30秒") { session.resetClock() }.buttonStyle(ClassroomButtonStyle())
                    Text("奖励对象：\(session.selectedName)")
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 10) {
                        PublicSurface(model: session.display).frame(minHeight: 380)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        HStack {
                            Button("上一页") { session.turnPage(-1) }.buttonStyle(ClassroomButtonStyle())
                            Button("下一页") { session.turnPage(1) }.buttonStyle(ClassroomButtonStyle())
                            Button("导入报告") { showReport = true; session.pause(.filePicker, enabled: true) }.buttonStyle(ClassroomButtonStyle())
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("教师测试备注", isOn: $session.showNotes)
                            .disabled(session.connectionCount == 0 || session.state.pageCount == 0)
                        if session.showNotes && session.connectionCount > 0 {
                            TextEditor(text: Binding(get: { session.currentNote }, set: { session.editNote($0) }))
                                .focused($notesFocused).frame(minHeight: 320)
                                .padding(8).background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            Text("确认电视显示独立公开画面后，再开启测试备注。")
                                .foregroundStyle(.secondary).frame(minHeight: 160)
                        }
                        Text("暂停原因：" + session.state.pauseReasons.map(\.rawValue).sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 280)
                }
                HStack {
                    Button("加载内置测试PPTX") { session.loadSample() }
                    Button("导入本地PPTX") { importingBackup = false; openImporter() }
                    Button("保存") { session.save() }
                    Button("恢复") { session.restoreLocal() }
                    Button("导出备份") {
                        if let url = session.exportedURL() { exportingURL = url; showExporter = true; session.pause(.filePicker, enabled: true) }
                    }
                    Button("导入备份") { importingBackup = true; openImporter() }
                }.buttonStyle(ClassroomButtonStyle())
                Text("阶段1新增规则示例与初始资料；下方保留阶段0验证功能。绘本基础渲染的限制详见导入报告。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.background(GameTheme.background).foregroundStyle(GameTheme.ink).tint(GameTheme.primary).preferredColorScheme(.light)
            .onChange(of: notesFocused) { _, active in session.notesFocus(active) }
            .onChange(of: session.showNotes) { _, visible in if !visible { notesFocused = false } }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: importingBackup ? [.json] : [UTType(filenameExtension: "pptx") ?? .data]) { result in
                defer { session.pause(.filePicker, enabled: false) }
                switch result {
                case .success(let url):
                    if importingBackup { session.importBackup(url) } else { session.loadPPTX(url) }
                case .failure(let error): session.fileSelectionFailed(error)
                }
            }
            .sheet(isPresented: $showReport, onDismiss: { session.pause(.filePicker, enabled: false) }) {
                NavigationStack {
                    ScrollView { Text(session.importReport).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                        .navigationTitle("PPTX导入报告")
                        .toolbar { Button("完成") { showReport = false } }
                }
            }
            .sheet(isPresented: $showExporter, onDismiss: { session.pause(.filePicker, enabled: false) }) {
                if let url = exportingURL { ExportDocument(url: url) }
            }
            .sheet(isPresented: $showRules, onDismiss: { session.endRules() }) {
                RulesLabView(session: session)
            }
            .fullScreenCover(isPresented: $showPlay, onDismiss: { session.endPlay() }) {
                PVEPlayView(model: session.pve, teacher: session)
            }
    }
    private func openImporter() { notesFocused = false; session.pause(.filePicker, enabled: true); showImporter = true }
}

@MainActor
struct ExportDocument: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
