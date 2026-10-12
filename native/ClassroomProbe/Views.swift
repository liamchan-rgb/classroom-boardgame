import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomProbeCore

@MainActor
struct PublicSurface: View {
    @ObservedObject var model: PublicDisplayModel
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("英语课堂 · 公开画面").font(.title2.bold())
                Spacer()
                Text(model.snapshot.paused ? "已暂停" : "计时中")
                Text("\(Int(ceil(model.snapshot.remainingSeconds)))秒").monospacedDigit()
                Text("\(model.snapshot.pageCount == 0 ? 0 : model.snapshot.pageIndex + 1) / \(model.snapshot.pageCount)")
            }
            if let image = model.image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 64))
                    Text("学生公开画面").font(.largeTitle.bold())
                    Text("教师端导入绘本后，在此显示公开页面。")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(model.snapshot.players) { player in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.name).font(.headline)
                        Text("生命 \(player.health)/\(player.maxHealth)")
                        Text("护盾 \(player.shield)")
                        Text("金币 \(player.coins) · 积分 \(player.score)")
                        Text(player.team)
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.padding(20).foregroundStyle(.white).background(Color(red: 0.02, green: 0.24, blue: 0.22))
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
    @FocusState private var notesFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("教师端 · 原生阶段0 v0.6", systemImage: "book.closed.fill").font(.title2.bold())
                    Spacer()
                    Text("公开场景 \(session.connectionCount)").font(.headline)
                }
                Text(session.registrationStatus).foregroundStyle(.secondary)
                Text(session.message).font(.callout)
                HStack(spacing: 8) {
                    ForEach(session.state.players) { player in
                        Button(player.name) { session.select(player.id) }
                            .buttonStyle(.bordered)
                            .tint(player.id == session.state.selectedPlayerID ? .blue : .gray)
                    }
                }
                HStack {
                    Button("发10金币（G）") { session.award() }.buttonStyle(.borderedProminent)
                    Button("暂停／继续（空格）") { session.togglePause() }.buttonStyle(.bordered)
                    Button("重置30秒") { session.resetClock() }.buttonStyle(.bordered)
                    Text("奖励对象：\(session.selectedName)")
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 10) {
                        PublicSurface(model: session.display).frame(minHeight: 380)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        HStack {
                            Button("上一页") { session.turnPage(-1) }.buttonStyle(.bordered)
                            Button("下一页") { session.turnPage(1) }.buttonStyle(.bordered)
                            Button("导入报告") { showReport = true; session.pause(.filePicker, enabled: true) }.buttonStyle(.bordered)
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
                }.buttonStyle(.bordered)
                Text("本样例仅用于阶段0能力验证；绘本基础渲染的限制详见导入报告。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Color(uiColor: .systemGroupedBackground))
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
