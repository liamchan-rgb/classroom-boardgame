import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Correcting answer records (from the report)

/// One recorded answer as the teacher sees it in 修改作答.
struct QuizRecordRow: Identifiable, Equatable {
    let id: Int
    let student: String
    let time: Date
    let kind: String
    let summary: String
    let said: String
    let expected: String
    let right: Bool
}

/// What the report window may do with the records (the coordinator does it on the open trip).
struct QuizRecordEditing {
    let rows: () -> [QuizRecordRow]
    let setRight: (Int, Bool) -> String?
    let remove: (Int) -> String?
}

extension MeadowCampaignSession {
    /// Every recorded answer, newest first, with what was said and what was right.
    var recordRows: [QuizRecordRow] {
        let bank = quizBank
        return Array(quizLog.enumerated().compactMap { i, a -> QuizRecordRow? in
            guard bank.indices.contains(a.question) else { return nil }
            let q = bank[a.question], parts = q.parts
            let said = parts.indices.map { p -> String in
                if let pick = a.picks.indices.contains(p) ? a.picks[p] : nil, parts[p].options.indices.contains(pick) { return parts[p].options[pick] }
                if let t = a.texts.indices.contains(p) ? a.texts[p] : nil { return t }
                return a.skipped == true ? "未作答" : (q.type == .flashcard ? "答错" : "不会")
            }.joined(separator: " / ")
            let kind = a.practice == true ? (a.shared == true ? "全班闪卡" : "闪卡练习") : a.shared == true ? "全班题" : a.limit >= 600 ? "个人挑战" : "个人题"
            return QuizRecordRow(id: i, student: a.playerName, time: Date(timeIntervalSince1970: a.at), kind: kind, summary: QuizReport.summary(q),
                                 said: said, expected: parts.map { $0.options[$0.answer] }.joined(separator: " / "),
                                 right: !a.correct.isEmpty && a.correct.allSatisfy { $0 })
        }.reversed())
    }
}

@MainActor final class QuizRecordsModel: ObservableObject {
    let access: QuizRecordEditing
    @Published var rows: [QuizRecordRow] = []
    @Published var student = "全部"
    @Published var search = ""
    @Published var note: String?
    @Published var confirmRemove: QuizRecordRow?
    /// Something changed: the report is rebuilt when this window closes.
    var changed = false
    init(_ access: QuizRecordEditing) { self.access = access; reload() }
    func reload() { rows = access.rows() }
    var students: [String] { var seen = Set<String>(); return ["全部"] + rows.map(\.student).filter { seen.insert($0).inserted }.sorted() }
    var shown: [QuizRecordRow] {
        let key = search.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { (student == "全部" || $0.student == student) && (key.isEmpty || ($0.summary + $0.said + $0.expected).lowercased().contains(key)) }
    }
    func setRight(_ row: QuizRecordRow, _ right: Bool) {
        if let problem = access.setRight(row.id, right) { note = problem; return }
        changed = true; note = "✓ 已把 \(row.student) 这条改为\(right ? "答对" : "答错")"; reload()
    }
    func remove(_ row: QuizRecordRow) {
        if let problem = access.remove(row.id) { note = problem; return }
        changed = true; note = "✓ 已删除 \(row.student) 的一条作答记录"; reload()
    }
}

/// 修改作答: every recorded answer; mark one right or wrong, or take it out. The report follows the records.
struct QuizRecordsPanel: View {
    @ObservedObject var model: QuizRecordsModel
    var onClose: () -> Void
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M月d日 HH:mm"; return f }()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("修改作答记录", systemImage: "pencil.and.list.clipboard").font(.title2.bold())
                Spacer()
                Button { onClose() } label: { Label("完成", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle(prominent: true))
            }
            Text("录错了可以改成答对、答错，或删掉这条。关掉这个窗口后报告按改过的记录重新生成；已经发出的金币和积分不变（需要时用 GM 调整）。")
                .font(.caption).foregroundStyle(GameTheme.muted)
            HStack(spacing: 8) {
                Picker("同学", selection: $model.student) { ForEach(model.students, id: \.self) { Text($0).tag($0) } }.frame(width: 160)
                ClassroomTextField(placeholder: "搜索题目或答案", text: $model.search, limit: 60).frame(height: 30)
                    .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("\(model.shown.count) 条").font(.caption).foregroundStyle(GameTheme.muted)
            }
            if let note = model.note { Text(note).font(.callout.bold()).foregroundStyle(note.hasPrefix("✓") ? GameTheme.primary : .orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.shown) { row in recordRow(row) }
                }.padding(6)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.45)))
        }
        .padding(20).frame(minWidth: 760, minHeight: 600, alignment: .top).background(GlassBackdrop())
        .confirmationDialog("删除这条作答记录？", isPresented: Binding(get: { model.confirmRemove != nil }, set: { if !$0 { model.confirmRemove = nil } }), titleVisibility: .visible, presenting: model.confirmRemove) { row in
            // The dialog clears confirmRemove as it closes, so the row comes in here rather than from the model.
            Button("删除", role: .destructive) { model.remove(row) }
            Button("取消", role: .cancel) {}
        } message: { row in Text("\(row.student) · \(row.summary)") }
    }
    private func recordRow(_ row: QuizRecordRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.right ? "checkmark.circle.fill" : "xmark.circle.fill").font(.title3).foregroundStyle(row.right ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.student).font(.callout.bold())
                    Text(row.kind).font(.caption2.bold()).foregroundStyle(GameTheme.primary)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(GameTheme.primary.opacity(0.12)))
                    Text(Self.time.string(from: row.time)).font(.caption2).foregroundStyle(GameTheme.muted)
                }
                Text(row.summary).font(.callout).foregroundStyle(GameTheme.ink).lineLimit(2)
                HStack(spacing: 4) {
                    Text("所答：\(row.said)").foregroundStyle(row.right ? Color.green : Color.red)
                    Text("· 正确：\(row.expected)").foregroundStyle(GameTheme.muted)
                }.font(.caption).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { model.setRight(row, !row.right) } label: {
                Label(row.right ? "改为答错" : "改为答对", systemImage: row.right ? "xmark" : "checkmark")
            }.buttonStyle(GlassIconButtonStyle())
            Button { model.confirmRemove = row } label: { Label("删除", systemImage: "trash") }.buttonStyle(GlassIconButtonStyle())
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.55)))
    }
}

/// Wraps the records model for `.sheet(item:)`.
struct QuizRecordsBox: Identifiable {
    let model: QuizRecordsModel
    var id: ObjectIdentifier { ObjectIdentifier(model) }
}

extension MeadowTeacherCoordinator {
    /// What the report window's 修改作答 does on the open trip.
    var recordEditing: QuizRecordEditing? {
        guard campaign != nil else { return nil }
        return QuizRecordEditing(
            rows: { [weak self] in self?.campaign?.recordRows ?? [] },
            setRight: { [weak self] i, right in
                guard let self, let c = self.campaign else { return "没有打开的行程。" }
                do { try c.setQuizRecord(at: i, right: right); self.revision += 1; return nil } catch { return error.localizedDescription }
            },
            remove: { [weak self] i in
                guard let self, let c = self.campaign else { return "没有打开的行程。" }
                do { try c.removeQuizRecord(at: i); self.revision += 1; return nil } catch { return error.localizedDescription }
            })
    }
}
