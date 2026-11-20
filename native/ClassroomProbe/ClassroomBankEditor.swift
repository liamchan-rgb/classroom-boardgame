import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Editing a whole course's questions

/// One question as the teacher edits it: the text of every field, turned back into a question on save.
struct QuestionDraft: Equatable {
    struct Part: Equatable { var prompt: String; var options: [String]; var answer: Int }
    var kind: QuizKind
    var prompt: String
    var passage: String
    var front: String
    var back: String
    var parts: [Part]
    var difficulty: Int
    var tags: String
    var explanation: String

    init(_ q: QuizQuestion) {
        kind = q.type; prompt = q.prompt; passage = q.passage ?? ""
        difficulty = q.level; tags = (q.tags ?? []).joined(separator: ", "); explanation = q.explanation ?? ""
        parts = q.parts.map { Part(prompt: $0.prompt ?? "", options: $0.options, answer: $0.answer) }
        front = q.prompt; back = q.parts.first.map { $0.options[$0.answer] } ?? ""
    }
    /// The edited question; everything not edited here (course, time limit…) stays as it was.
    func question(from old: QuizQuestion) -> QuizQuestion {
        var q = old
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        q.difficulty = difficulty
        let t = tags.split(whereSeparator: { ",，、".contains($0) }).map { clean(String($0)) }.filter { !$0.isEmpty }
        q.tags = t.isEmpty ? nil : t
        q.explanation = clean(explanation).isEmpty ? nil : clean(explanation)
        switch kind {
        case .flashcard:
            q.prompt = clean(front)
            q.items = [QuizItem(options: [clean(back)], answer: 0)]
        case .choice:
            q.prompt = clean(prompt)
            if let p = parts.first { q.options = p.options.map(clean); q.answer = p.answer }
        case .fill:
            q.prompt = clean(prompt)
            q.items = parts.map { QuizItem(options: $0.options.map(clean), answer: $0.answer) }
        case .reading:
            q.prompt = clean(prompt).isEmpty ? "阅读短文，回答问题" : clean(prompt)
            q.passage = clean(passage)
            q.items = parts.map { QuizItem(prompt: clean($0.prompt), options: $0.options.map(clean), answer: $0.answer) }
        }
        return q
    }
}

@MainActor final class BankEditorModel: ObservableObject {
    @Published var course: String
    @Published var search = ""
    @Published var kind: QuizKind?
    @Published var selected: Int?
    @Published var draft: QuestionDraft?
    @Published var note: String?
    /// What saving does (the coordinator: course + the open trip in place); returns a problem, if any.
    let save: (QuizQuestion, QuizQuestion) -> String?
    init(course: String?, save: @escaping (QuizQuestion, QuizQuestion) -> String?) {
        self.course = course ?? QuizLibrary.shared.active ?? QuizLibrary.shared.courses.first ?? ""
        self.save = save
    }
    var questions: [QuizQuestion] { QuizLibrary.shared.questions(of: course) }
    var shown: [(offset: Int, element: QuizQuestion)] {
        let key = search.trimmingCharacters(in: .whitespaces).lowercased()
        return Array(questions.enumerated()).filter { _, q in
            (kind == nil || q.type == kind) && (key.isEmpty || QuizBankParser.text([q]).lowercased().contains(key))
        }
    }
    func pick(_ k: Int) {
        guard questions.indices.contains(k) else { return }
        selected = k; draft = QuestionDraft(questions[k]); note = nil
    }
    func commit() {
        guard let k = selected, questions.indices.contains(k), let draft else { return }
        let old = questions[k], new = draft.question(from: old)
        guard new != old else { note = "没有改动。"; return }
        if let problem = save(old, new) { note = problem; if questions.indices.contains(k), questions[k] == new { self.draft = QuestionDraft(new) }; return }
        note = "✓ 已保存（这道题的作答记录保留）"
        self.draft = QuestionDraft(new)
    }
    func delete() {
        guard let k = selected, questions.indices.contains(k) else { return }
        QuizLibrary.shared.remove(questions[k]); selected = nil; draft = nil
        note = "✓ 已删除（已作答的记录仍在报告里）"
    }
    func addCard() {
        let card = QuizBankParser.flashcard(front: "new word", back: "意思", distractors: [])
        var c = card; c.difficulty = 1; c.tags = ["单词"]
        QuizLibrary.shared.addCard(c, to: course)
        if let k = questions.lastIndex(of: { var x = c; x.course = course; return x }()) { pick(k) }
    }
}

/// 编辑题目: every question of a course; pick one, change it, save. Opened from 题库, the course menu, the report.
struct QuizBankEditor: View {
    @ObservedObject var model: BankEditorModel
    @ObservedObject var library = QuizLibrary.shared
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("编辑题目", systemImage: "square.and.pencil").font(.title2.bold())
                Picker("", selection: Binding(get: { model.course }, set: { model.course = $0; model.selected = nil; model.draft = nil })) {
                    ForEach(library.courses, id: \.self) { Text("\($0)（\(library.questions(of: $0).count) 题）").tag($0) }
                }.labelsHidden().frame(maxWidth: 260)
                Spacer()
                Button { model.addCard() } label: { Label("新增闪卡", systemImage: "plus.rectangle.on.rectangle") }.buttonStyle(GlassIconButtonStyle())
                Button { onClose() } label: { Label("完成 (Esc)", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle())
            }
            Text("改好点“保存”：这门课里的题会更新；打开着的行程里，这道题原位更新、已作答的记录保留（报告显示改后的内容）。").font(.caption).foregroundStyle(GameTheme.muted)
            HStack(alignment: .top, spacing: 14) {
                list.frame(width: 380)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClassroomTextField(placeholder: "搜索（单词、意思、题目）", text: $model.search, limit: 60).frame(height: 30)
                .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Picker("", selection: $model.kind) {
                Text("全部").tag(QuizKind?.none)
                ForEach(QuizKind.allCases, id: \.self) { Text($0.title).tag(QuizKind?.some($0)) }
            }.pickerStyle(.segmented)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(model.shown, id: \.offset) { k, q in
                        let on = model.selected == k
                        Button { KeyHostingController<EmptyView>.endEditing(); model.pick(k) } label: {
                            HStack(spacing: 6) {
                                Text("\(k + 1)").font(.caption2.bold()).foregroundStyle(on ? .white.opacity(0.8) : GameTheme.muted).frame(width: 24, alignment: .trailing)
                                Text(String(repeating: "★", count: q.level)).font(.caption2.bold()).lineLimit(1).fixedSize().foregroundStyle(on ? .white : Color(red: 0.85, green: 0.6, blue: 0.12)).frame(width: 34, alignment: .leading)
                                Text(q.type.title).font(.caption2.bold()).foregroundStyle(on ? .white : GameTheme.primary)
                                Text(q.type == .flashcard ? q.prompt + " → " + (q.parts.first.map { $0.options[$0.answer] } ?? "") : QuizReport.summary(q))
                                    .font(.caption).lineLimit(1).foregroundStyle(on ? .white : GameTheme.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5).padding(.horizontal, 6).contentShape(Rectangle())
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? GameTheme.primary : Color.clear))
                        }.buttonStyle(.plain)
                    }
                }.padding(6)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.45)))
            Text("共 \(model.shown.count) 题").font(.caption).foregroundStyle(GameTheme.muted)
        }
    }

    @ViewBuilder private var editor: some View {
        if model.draft == nil {
            Label("在左边点一道题来编辑。", systemImage: "hand.point.left").foregroundStyle(GameTheme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 30)
        } else {
            let draft = Binding(get: { model.draft! }, set: { model.draft = $0 })
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("第 \((model.selected ?? 0) + 1) 题 · \(model.draft!.kind.title)").font(.headline)
                        Spacer()
                        stars(draft.difficulty)
                    }
                    switch model.draft!.kind {
                    case .flashcard: flashcard(draft)
                    case .choice:
                        textEditor("题干", text: draft.prompt, height: 60)
                        partEditor(draft, 0, title: "选项（点圆圈设正确答案）")
                    case .fill:
                        textEditor("句子（{{1}}、{{2}} 是空的位置，不要删）", text: draft.prompt, height: 60)
                        ForEach(model.draft!.parts.indices, id: \.self) { i in partEditor(draft, i, title: "第 \(i + 1) 空的候选词") }
                    case .reading:
                        textEditor("文章", text: draft.passage, height: 110)
                        ForEach(model.draft!.parts.indices, id: \.self) { i in
                            field("第 \(i + 1) 小题", text: Binding(get: { model.draft!.parts[i].prompt }, set: { model.draft!.parts[i].prompt = $0 }))
                            partEditor(draft, i, title: "选项")
                        }
                    }
                    field("标签（逗号分隔）", text: draft.tags)
                    field("解析（可选）", text: draft.explanation)
                    if let note = model.note { Text(note).font(.callout.bold()).foregroundStyle(note.hasPrefix("✓") ? GameTheme.primary : .orange) }
                    HStack {
                        Button(role: .destructive) { model.delete() } label: { Label("删除这题", systemImage: "trash") }.buttonStyle(GlassIconButtonStyle())
                        Spacer()
                        Button { if let k = model.selected { model.pick(k) } } label: { Label("还原", systemImage: "arrow.uturn.backward") }.buttonStyle(GlassIconButtonStyle())
                        Button { KeyHostingController<EmptyView>.endEditing(); model.commit() } label: { Label("保存", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                    }
                }.padding(.trailing, 6)
            }
        }
    }

    private func flashcard(_ draft: Binding<QuestionDraft>) -> some View {
        let english = draft.wrappedValue.front.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let word = english ? draft.wrappedValue.front : draft.wrappedValue.back
        let senses = NotesDictionary.shared.ready()?.entry(word)?.senses ?? []
        return VStack(alignment: .leading, spacing: 8) {
            field("正面", text: draft.front)
            field("背面", text: draft.back)
            if !senses.isEmpty {
                Text("词典释义（点一下填入\(english ? "背面" : "正面")）").font(.caption.bold()).foregroundStyle(GameTheme.muted)
                ForEach(Array(senses.enumerated()), id: \.offset) { _, sense in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(sense.pos ?? "").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading)
                        FlowRow(spacing: 5) {
                            ForEach(sense.meanings, id: \.self) { m in
                                let on = (english ? draft.wrappedValue.back : draft.wrappedValue.front) == m
                                Button { KeyHostingController<EmptyView>.endEditing(); if english { draft.wrappedValue.back = m } else { draft.wrappedValue.front = m } } label: {
                                    Text(m).font(.callout).padding(.horizontal, 8).padding(.vertical, 3)
                                        .foregroundStyle(on ? Color.white : GameTheme.ink)
                                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
    private func partEditor(_ draft: Binding<QuestionDraft>, _ i: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.bold()).foregroundStyle(GameTheme.muted)
            ForEach(draft.wrappedValue.parts[i].options.indices, id: \.self) { o in
                HStack(spacing: 6) {
                    Button { draft.wrappedValue.parts[i].answer = o } label: {
                        Image(systemName: draft.wrappedValue.parts[i].answer == o ? "checkmark.circle.fill" : "circle").foregroundStyle(draft.wrappedValue.parts[i].answer == o ? Color.green : GameTheme.muted)
                    }.buttonStyle(.plain)
                    Text(MeadowQuizCard.letters.indices.contains(o) ? MeadowQuizCard.letters[o] : "").font(.caption.bold()).frame(width: 14)
                    ClassroomTextField(placeholder: "选项", text: Binding(get: { draft.wrappedValue.parts[i].options[o] }, set: { draft.wrappedValue.parts[i].options[o] = $0 }), limit: 200)
                        .frame(height: 28).padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
    }
    private func stars(_ value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { d in
                let on = value.wrappedValue == d
                Button { value.wrappedValue = d } label: {
                    Text(String(repeating: "★", count: d)).font(.callout.bold()).padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(on ? Color.white : GameTheme.ink)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                }.buttonStyle(.plain)
            }
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(GameTheme.muted)
            ClassroomTextField(placeholder: title, text: text, limit: 400).frame(height: 30)
                .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    private func textEditor(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(GameTheme.muted)
            TextEditor(text: text).scrollContentBackground(.hidden).font(.callout).frame(height: height).padding(4)
                .background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

extension MeadowTeacherCoordinator {
    /// 编辑题目 (from 题库 it replaces the bank panel and goes back to it when done).
    func openBankEditor(course: String? = nil, back: Bool = false) {
        let model = BankEditorModel(course: course) { [weak self] old, new in self?.replaceQuestion(old, with: new) }
        let show = { [weak self] in
            guard let self else { return }
            let done = { [weak self] in self?.closePanel { if back { self?.openQuizBank() } }; return }
            let screen = KeyHostingController(rootView: QuizBankEditor(model: model, onClose: done))
            screen.onKey = { key in if key == "⎋" { done(); return true }; return false }
            self.presentPanel(screen, size: CGSize(width: 1000, height: 740))
        }
        closePanel(show)
    }
}
