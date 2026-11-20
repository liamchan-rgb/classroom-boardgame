import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Question bank prompts (for a language model)

/// Builds the prompts the teacher gives a language model: one to write a new course's bank to plan (how many of each
/// kind at each difficulty), one to fix problems found in a bank. Both carry the same format and difficulty rules
/// (Resources/quiz-prompt-rules.txt, taken from docs/question-bank-llm-prompt.md).
enum QuizPrompts {
    static var rules: String {
        guard let url = Bundle.main.url(forResource: "quiz-prompt-rules", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    struct Plan {
        var course = ""
        var subject = ""
        var level = ""
        var easy = 15
        var medium = 15
        var sentences = 4
        var fills = 3
        var choices = 2
        var readings = 1
        var readingQuestions = 3
        var englishFront = true
        var extra = ""
        var material = ""
        var total: Int { easy + medium + sentences + fills + choices + readings }
        var challenge: Int { sentences + fills + choices + readings }
    }
    static func plan(_ p: Plan) -> String {
        func or(_ s: String, _ fallback: String) -> String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? fallback : t }
        var lines = [
            "你是一名课堂题库编写助手。请按下面的「本次要求」**直接出题（不要先提问）**，并**严格**按「输出格式」输出一份纯文本题库，供课堂游戏 App 直接导入。",
            "",
            "### 本次要求",
            "",
            "- 课程名：\(or(p.course, "（请按课文内容命名）"))（输出第一行写 `# 课程：\(or(p.course, "课程名"))`）",
            "- 学科与主题：\(or(p.subject, "见下面的课文材料"))",
            "- 学生水平：\(or(p.level, "按课文难度判断"))",
            "- 题量：共 \(p.total) 题，各难度的题型与数量如下（必须一题不差）：",
            "  - ★ 基础（`难度：1`）：单词闪卡 \(p.easy) 张",
            "  - ★★ 提高（`难度：2`）：单词闪卡 \(p.medium) 张",
            "  - ★★★ 挑战（`难度：3`）：句子闪卡 \(p.sentences) 张、填空 \(p.fills) 题、选择 \(p.choices) 题、阅读 \(p.readings) 篇" + (p.readings > 0 ? "（每篇 \(p.readingQuestions) 个小题）" : ""),
            "- 闪卡方向：" + (p.englishFront ? "正面英文、背面中文（句子闪卡也一样：正面英文句子、背面中文）" : "正面中文、背面英文（句子闪卡：正面中文句子、背面英文句子，学生说出英文整句）"),
        ]
        let extra = p.extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { lines.append("- 其他要求：" + extra) }
        let material = p.material.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("")
        if material.isEmpty {
            lines.append("课文或单词表我会在这条消息之后发给你；收到后直接按要求出题。")
        } else {
            lines += ["### 课文材料", "", material]
        }
        return lines.joined(separator: "\n") + "\n\n" + rules
    }

    /// 简短版: for later messages in the same chat, after the full prompt has set the rules once. Only what this
    /// round asks for, so the conversation does not pay for the rules again.
    static func briefPlan(_ p: Plan) -> String {
        func or(_ s: String, _ fallback: String) -> String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? fallback : t }
        var lines = [
            "按前面的规则（输出格式、难度与题型、输出前自检）再出一套新题库，直接出题，只输出题库正文。",
            "- 课程名：\(or(p.course, "（按课文命名）"))（第一行 `# 课程：\(or(p.course, "课程名"))`）",
        ]
        let subject = p.subject.trimmingCharacters(in: .whitespacesAndNewlines), level = p.level.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty { lines.append("- 主题：" + subject) }
        if !level.isEmpty { lines.append("- 学生水平：" + level) }
        lines.append("- 共 \(p.total) 题：★ 单词闪卡 \(p.easy)；★★ 单词闪卡 \(p.medium)；★★★ 句子闪卡 \(p.sentences)、填空 \(p.fills)、选择 \(p.choices)、阅读 \(p.readings) 篇"
                     + (p.readings > 0 ? "（每篇 \(p.readingQuestions) 小题）" : ""))
        lines.append("- 闪卡：" + (p.englishFront ? "正面英文、背面中文" : "正面中文、背面英文"))
        let extra = p.extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { lines.append("- 其他要求：" + extra) }
        let material = p.material.trimmingCharacters(in: .whitespacesAndNewlines)
        lines += material.isEmpty ? ["", "课文或单词表在下一条消息。"] : ["", "### 课文材料", "", material]
        return lines.joined(separator: "\n")
    }
    static func briefFeedback(_ f: Feedback) -> String {
        let course = f.course.isEmpty ? "本课" : f.course
        var lines = ["按前面的规则修改课程「\(course)」的题库：只改下面的问题，其余题原样；★/★★ 仍只能是单词闪卡。"]
        let kinds = problems.filter(f.problems.contains)
        if !kinds.isEmpty { lines.append("- 问题：" + kinds.joined(separator: "、")) }
        let note = f.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append("- 说明：" + note) }
        let error = f.importError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty { lines.append("- 导入报错：" + error) }
        if !f.picked.isEmpty { lines += ["- 有问题的题：", QuizBankParser.text(f.picked).trimmingCharacters(in: .whitespacesAndNewlines)] }
        if kinds.isEmpty && note.isEmpty && error.isEmpty && f.picked.isEmpty { lines.append("- 请通读检查答案、歧义、难度和格式。") }
        lines.append(f.fullBank ? "输出修改后的完整题库（第一行 `# 课程：\(course)`），只输出题库正文。"
                                : "只输出改过或新增的题，每题前一行 `# 改：原第 n 题` 或 `# 新增`。")
        if f.attachBank {
            lines += ["", "### 现有题库（\(f.bank.count) 题，以这份为准）", "", QuizBankParser.text(f.bank, course: f.course.isEmpty ? nil : f.course).trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return lines.joined(separator: "\n")
    }

    static let problems = ["答案错误", "题目有歧义", "超纲或太难", "太简单", "难度标错", "题型与难度不符", "单词重复", "中文意思不准", "干扰项不合理", "题量不够", "导入格式报错"]
    struct Feedback {
        var course = ""
        var problems = Set<String>()
        var picked: [QuizQuestion] = []
        var note = ""
        var importError = ""
        var fullBank = true
        var bank: [QuizQuestion] = []
        /// 简短版 only: attach the bank as the app has it (when it was changed in the app since the chat saw it).
        var attachBank = false
    }
    static func feedback(_ f: Feedback) -> String {
        let course = f.course.isEmpty ? "本课" : f.course
        var lines = [
            "你是一名课堂题库编写助手。下面是课程「\(course)」现有的题库（课堂 App 导出的原文）和老师发现的问题。请按「修改要求」改好，并**严格**按「输出格式」输出纯文本题库。",
            "",
            "### 老师发现的问题",
            "",
        ]
        let kinds = problems.filter(f.problems.contains)
        if !kinds.isEmpty { lines.append("- 问题类型：" + kinds.joined(separator: "、")) }
        let note = f.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append("- 老师的说明：" + note) }
        let error = f.importError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty { lines.append("- App 导入时的报错：" + error) }
        if !f.picked.isEmpty {
            lines += ["- 有问题的题（共 \(f.picked.count) 题，原文如下）：", "", QuizBankParser.text(f.picked).trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        if kinds.isEmpty && note.isEmpty && error.isEmpty && f.picked.isEmpty { lines.append("- （老师还没有写具体问题：请通读题库，找出并改正答案错误、歧义、超纲、难度或题型标错、重复和格式问题。）") }
        lines += [
            "",
            "### 修改要求",
            "",
            "- 只改有问题的题和老师说明里提到的内容；没有问题的题保持原样（题目、答案、难度、顺序都不变）。",
            "- 改动后仍须遵守「难度与题型」：★/★★ 只能是单词（短语）闪卡，★★★ 才是句子闪卡、填空、选择、阅读。题量不够时按同样的规则补齐。",
        ]
        if f.fullBank {
            lines.append("- 输出**修改后的完整题库**（包括没改动的题），第一行写 `# 课程：\(course)`。老师会把它存成「\(course).txt」重新导入，替换这门课。")
        } else {
            lines.append("- 只输出**改过或新增的题**，每题前加一行注释，例如 `# 改：原第 3 题` 或 `# 新增`；不要输出没改的题。")
        }
        lines.append("- 输出前按「输出前自检」检查一遍，不要输出修改说明以外的任何解释（可以用 `#` 开头的注释行简短说明改了什么）。")
        if f.fullBank {
            lines += ["", "### 现有题库（\(f.bank.count) 题）", "", QuizBankParser.text(f.bank, course: f.course.isEmpty ? nil : f.course).trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return lines.joined(separator: "\n") + "\n\n" + rules
    }
}

/// The plan, kept on this device between uses.
@MainActor final class QuizPromptModel: ObservableObject {
    @Published var tab = 0
    @Published var plan: QuizPrompts.Plan
    @Published var feedback = QuizPrompts.Feedback()
    @Published var copied = false
    /// 简短版 (later messages in the same chat). Kept on this device.
    @Published var brief = UserDefaults.standard.bool(forKey: "classroom.promptBrief") {
        didSet { UserDefaults.standard.set(brief, forKey: "classroom.promptBrief") }
    }
    init() {
        var p = QuizPrompts.Plan()
        let d = UserDefaults.standard
        if let saved = d.dictionary(forKey: "classroom.promptPlan") {
            p.subject = saved["subject"] as? String ?? ""; p.level = saved["level"] as? String ?? ""
            p.easy = saved["easy"] as? Int ?? p.easy; p.medium = saved["medium"] as? Int ?? p.medium
            p.sentences = saved["sentences"] as? Int ?? p.sentences; p.fills = saved["fills"] as? Int ?? p.fills
            p.choices = saved["choices"] as? Int ?? p.choices; p.readings = saved["readings"] as? Int ?? p.readings
            p.readingQuestions = saved["readingQuestions"] as? Int ?? p.readingQuestions
            p.englishFront = saved["englishFront"] as? Bool ?? true; p.extra = saved["extra"] as? String ?? ""
        }
        plan = p
        let course = QuizLibrary.shared.active ?? ""
        feedback.course = course
        feedback.bank = course.isEmpty ? [] : QuizLibrary.shared.questions(of: course)
    }
    func save() {
        let p = plan
        UserDefaults.standard.set(["subject": p.subject, "level": p.level, "easy": p.easy, "medium": p.medium, "sentences": p.sentences, "fills": p.fills,
                                   "choices": p.choices, "readings": p.readings, "readingQuestions": p.readingQuestions, "englishFront": p.englishFront, "extra": p.extra],
                                  forKey: "classroom.promptPlan")
    }
    func selectCourse(_ name: String) {
        feedback.course = name; feedback.bank = QuizLibrary.shared.questions(of: name); feedback.picked = []
    }
    var prompt: String {
        tab == 0 ? (brief ? QuizPrompts.briefPlan(plan) : QuizPrompts.plan(plan))
                 : (brief ? QuizPrompts.briefFeedback(feedback) : QuizPrompts.feedback(feedback))
    }
    func copy() {
        save()
        UIPasteboard.general.string = prompt
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.copied = false }
    }
}

/// 题库 → 出题提示词: 出题规划 (a new course) and 修改反馈 (fix a course's problems). Copy the prompt to the
/// language model, save its answer as 课程名.txt and import it in 题库.
struct QuizPromptEditor: View {
    @ObservedObject var model: QuizPromptModel
    @ObservedObject var library = QuizLibrary.shared
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("出题提示词", systemImage: "wand.and.stars").font(.title2.bold())
                Picker("", selection: $model.tab) { Text("出题规划").tag(0); Text("修改反馈").tag(1) }.pickerStyle(.segmented).frame(width: 220)
                Spacer()
                Button { model.copy() } label: { Label(model.copied ? "已复制" : "复制提示词", systemImage: model.copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(GlassIconButtonStyle(prominent: true))
                Button { model.save(); onClose() } label: { Label("完成 (Esc)", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle())
            }
            HStack(spacing: 10) {
                Picker("", selection: $model.brief) { Text("完整版").tag(false); Text("简短版").tag(true) }.pickerStyle(.segmented).frame(width: 170)
                Text(model.brief
                     ? "简短版：在同一个 AI 对话里接着用（第一次已发过完整版），不再重复规则和格式，只写这次的要求，省字数。新开对话请用完整版。"
                     : "完整版：新开 AI 对话时用，带全部规则、格式和自检要求。之后在同一对话里接着出题或改题，切到简短版。")
                    .font(.caption).foregroundStyle(GameTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Text(model.tab == 0
                 ? "填好题量，复制提示词发给 AI（连同课文或单词表），把它输出的题库存成「课程名.txt」，在题库里“导入课程”。★/★★ 只出单词闪卡，★★★ 才出句子类题。"
                 : "勾出有问题的题、选问题类型并写说明，复制提示词发给 AI；它输出修改后的完整题库，存成同名「课程名.txt」再导入即可替换这门课（已作答的记录不受影响）。")
                .font(.caption).foregroundStyle(GameTheme.muted)
            HStack(alignment: .top, spacing: 14) {
                ScrollView { if model.tab == 0 { planForm } else { feedbackForm } }
                    .frame(width: 420)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("提示词预览").font(.headline)
                        Spacer()
                        Text("\(model.prompt.count) 字").font(.caption).foregroundStyle(GameTheme.muted)
                    }
                    ScrollView {
                        Text(model.prompt).font(.system(size: 11, design: .monospaced)).foregroundStyle(GameTheme.ink)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.55)))
                }
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
        .onDisappear { model.save() }
    }

    // MARK: 出题规划

    private var planForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("课程名（也是文件名）", text: $model.plan.course, placeholder: "例：爱丽丝第二章")
            field("学科与主题", text: $model.plan.subject, placeholder: "例：小学三年级英语 · 衣物与身体部位")
            field("学生水平", text: $model.plan.level, placeholder: "例：三年级，学过 Unit 1–4")
            group("★ 基础 · ★★ 提高（只出单词闪卡，即本课高频词）") {
                counter("★ 单词闪卡", value: $model.plan.easy, range: 0...60)
                counter("★★ 单词闪卡", value: $model.plan.medium, range: 0...60)
            }
            group("★★★ 挑战（句子类题目）") {
                counter("句子闪卡（口头造句）", value: $model.plan.sentences, range: 0...40)
                counter("填空", value: $model.plan.fills, range: 0...40)
                counter("选择", value: $model.plan.choices, range: 0...40)
                counter("阅读（篇）", value: $model.plan.readings, range: 0...10)
                if model.plan.readings > 0 { counter("每篇小题", value: $model.plan.readingQuestions, range: 1...12) }
            }
            HStack {
                Text("共 \(model.plan.total) 题").font(.headline)
                Text("高频词 \(model.plan.easy + model.plan.medium) · 挑战 \(model.plan.challenge)").font(.caption).foregroundStyle(GameTheme.muted)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("闪卡方向").font(.caption.bold()).foregroundStyle(GameTheme.muted)
                Picker("", selection: $model.plan.englishFront) { Text("正面英文 → 说中文").tag(true); Text("正面中文 → 说英文").tag(false) }.pickerStyle(.segmented)
            }
            editor("其他要求（可选）", text: $model.plan.extra, height: 60, placeholder: "例：单词题加标签“单词”；不要超纲词")
            editor("课文或单词表（可选，也可在对话里另外发）", text: $model.plan.material, height: 110, placeholder: "粘贴课文、单词表或 PPT 备注")
        }.padding(.trailing, 6)
    }

    // MARK: 修改反馈

    private var feedbackForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("课程").font(.caption.bold()).foregroundStyle(GameTheme.muted)
                Picker("", selection: Binding(get: { model.feedback.course }, set: { model.selectCourse($0) })) {
                    ForEach(library.courses, id: \.self) { Text("\($0)（\(library.questions(of: $0).count) 题）").tag($0) }
                }.labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("问题类型（可多选）").font(.caption.bold()).foregroundStyle(GameTheme.muted)
                FlowRow(spacing: 6) {
                    ForEach(QuizPrompts.problems, id: \.self) { p in
                        let on = model.feedback.problems.contains(p)
                        Button { KeyHostingController<EmptyView>.endEditing(); if on { model.feedback.problems.remove(p) } else { model.feedback.problems.insert(p) } } label: {
                            Text(p).font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(on ? Color.white : GameTheme.ink)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                        }.buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("有问题的题（勾选，可不选）").font(.caption.bold()).foregroundStyle(GameTheme.muted)
                    Spacer()
                    if !model.feedback.picked.isEmpty { Button("清空") { model.feedback.picked = [] }.font(.caption) }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.feedback.bank.enumerated()), id: \.offset) { k, q in
                            let on = model.feedback.picked.contains(q)
                            Button {
                                if on { model.feedback.picked.removeAll { $0 == q } } else { model.feedback.picked.append(q) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? GameTheme.primary : GameTheme.muted)
                                    Text("\(k + 1)").font(.caption2.bold()).foregroundStyle(GameTheme.muted).frame(width: 22, alignment: .trailing)
                                    Text(String(repeating: "★", count: q.level)).font(.caption2.bold()).foregroundStyle(Color(red: 0.85, green: 0.6, blue: 0.12)).frame(width: 30, alignment: .leading)
                                    Text(q.type.title).font(.caption2.bold()).foregroundStyle(GameTheme.primary)
                                    Text(q.type == .flashcard ? q.prompt + " → " + (q.parts.first.map { $0.options[$0.answer] } ?? "") : QuizReport.summary(q))
                                        .font(.caption).foregroundStyle(GameTheme.ink).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(6)
                }
                .frame(height: 190)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.45)))
            }
            editor("具体说明", text: $model.feedback.note, height: 70, placeholder: "例：第 12 题答案应为 B；★★ 里 dress 和 dresses 重复")
            field("App 导入报错（可选）", text: $model.feedback.importError, placeholder: "粘贴导入失败时的提示")
            VStack(alignment: .leading, spacing: 4) {
                Text("让 AI 输出").font(.caption.bold()).foregroundStyle(GameTheme.muted)
                Picker("", selection: $model.feedback.fullBank) { Text("修改后的完整题库").tag(true); Text("只输出改过的题").tag(false) }.pickerStyle(.segmented)
                Text(model.brief ? (model.feedback.fullBank ? "AI 按对话里已有的题库改完输出整套，存成同名文件重新导入即可。" : "只拿回改过的题，需要你自己替换进原文件。")
                     : model.feedback.fullBank ? "提示词会附上这门课的全部原题，AI 改完输出整套，存成同名文件重新导入即可。" : "只拿回改过的题，需要你自己替换进原文件。")
                    .font(.caption2).foregroundStyle(GameTheme.muted)
                if model.brief {
                    Toggle(isOn: $model.feedback.attachBank) {
                        Text("附上 App 里的现有题库（\(model.feedback.bank.count) 题）").font(.caption.bold())
                    }.toggleStyle(.switch).tint(GameTheme.primary)
                    Text("在 App 里改过题、或不确定 AI 那边是不是最新版时打开；否则省掉，AI 用对话里已有的那份。")
                        .font(.caption2).foregroundStyle(GameTheme.muted)
                }
            }
        }.padding(.trailing, 6)
    }

    // MARK: Pieces

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(GameTheme.muted)
            ClassroomTextField(placeholder: placeholder, text: text, limit: 200).frame(height: 32)
                .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    private func editor(_ title: String, text: Binding<String>, height: CGFloat, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(GameTheme.muted)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text).scrollContentBackground(.hidden).font(.callout).frame(height: height).padding(4)
                if text.wrappedValue.isEmpty { Text(placeholder).font(.callout).foregroundStyle(GameTheme.muted.opacity(0.7)).padding(.horizontal, 9).padding(.vertical, 12).allowsHitTesting(false) }
            }
            .background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(GameTheme.muted)
            content()
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.4)))
    }
    private func counter(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: { Image(systemName: "minus") }.buttonStyle(GlassIconButtonStyle())
            Text("\(value.wrappedValue)").font(.body.bold()).monospacedDigit().frame(minWidth: 30)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) } label: { Image(systemName: "plus") }.buttonStyle(GlassIconButtonStyle())
        }
    }
}

extension MeadowTeacherCoordinator {
    /// 题库 → 出题提示词 (replaces the bank panel and goes back to it when done).
    func openQuizPrompts() {
        let model = QuizPromptModel()
        closePanel { [weak self] in
            guard let self else { return }
            let done = { [weak self] in self?.closePanel { self?.openQuizBank() }; return }
            let screen = KeyHostingController(rootView: QuizPromptEditor(model: model, onClose: done))
            screen.onKey = { key in if key == "⎋" { done(); return true }; return false }
            self.presentPanel(screen, size: CGSize(width: 980, height: 720))
        }
    }
}
