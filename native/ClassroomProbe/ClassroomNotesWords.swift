import SwiftUI
import UIKit
import NaturalLanguage
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Dictionary and the teacher's own words

/// The bundled dictionary (trimmed ECDICT), loaded once in the background, plus the teacher's own meanings
/// (我的词表: whatever was typed or picked before comes first next time).
@MainActor final class NotesDictionary {
    static let shared = NotesDictionary()
    private(set) var dictionary: ClassroomDictionary?
    private var loading = false
    private var mine: [String: String]
    private var mineURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClassroomMeadow/my-words.json")
    }
    private init() {
        mine = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClassroomMeadow/my-words.json")))) ?? [:]
    }
    /// Starts loading (the book tab calls this when it opens, so the first double-click is instant).
    func prewarm() {
        guard dictionary == nil, !loading, let url = Bundle.main.url(forResource: "ecdict-classroom", withExtension: "tsv") else { return }
        loading = true
        Task.detached(priority: .utility) {
            let d = try? ClassroomDictionary(contentsOf: url)
            await MainActor.run { NotesDictionary.shared.dictionary = d; NotesDictionary.shared.loading = false }
        }
    }
    /// Loads now if the background load has not finished (about half a second).
    func ready() -> ClassroomDictionary? {
        if dictionary == nil, let url = Bundle.main.url(forResource: "ecdict-classroom", withExtension: "tsv") { dictionary = try? ClassroomDictionary(contentsOf: url) }
        return dictionary
    }
    func myMeaning(_ front: String) -> String? { mine[front.lowercased()] }
    func remember(_ front: String, _ back: String) {
        mine[front.lowercased()] = back
        try? FileManager.default.createDirectory(at: mineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(mine).write(to: mineURL, options: .atomic)
    }
}

// MARK: - Notes text (double-click a word)

extension NotesMarkup {
    /// The notes with **bold** / __underline__ applied, as UIKit text (for the selectable notes view).
    static func uiText(_ raw: String, size: CGFloat = 17) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var bold = false, underline = false, buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular), .foregroundColor: UIColor.label]
            if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: buffer, attributes: attrs)); buffer = ""
        }
        let chars = Array(raw); var i = 0
        while i < chars.count {
            if i + 1 < chars.count, chars[i] == "*", chars[i + 1] == "*" { flush(); bold.toggle(); i += 2; continue }
            if i + 1 < chars.count, chars[i] == "_", chars[i + 1] == "_" { flush(); underline.toggle(); i += 2; continue }
            buffer.append(chars[i]); i += 1
        }
        flush()
        return out
    }
}

/// What was double-clicked: the word, its sentence split into words, which one it is, and how it is used there.
struct NotesWordPick: Identifiable {
    let id = UUID()
    var word: String
    var tokens: [String]
    var index: Int
    /// NaturalLanguage lexical class in the sentence ("Verb", "Noun"…).
    var lexicalClass: String?

    /// Finds the word around `location` in `text` and reads its sentence.
    static func at(_ location: Int, in text: String) -> NotesWordPick? {
        let ns = text as NSString
        guard location >= 0, location <= ns.length, let at = Range(NSRange(location: min(location, max(0, ns.length - 1)), length: 0), in: text) else { return nil }
        let sentences = NLTokenizer(unit: .sentence); sentences.string = text
        let sentence = sentences.tokenRange(at: at.lowerBound)
        let words = NLTokenizer(unit: .word); words.string = text; words.setLanguage(.english)
        var ranges: [Range<String.Index>] = []
        words.enumerateTokens(in: sentence) { r, _ in ranges.append(r); return true }
        guard let index = ranges.firstIndex(where: { $0.contains(at.lowerBound) || $0.upperBound == at.lowerBound }) else { return nil }
        let word = String(text[ranges[index]])
        guard word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.isASCII }) else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass]); tagger.string = text; tagger.setLanguage(.english, range: sentence)
        let tag = tagger.tag(at: ranges[index].lowerBound, unit: .word, scheme: .lexicalClass).0
        return NotesWordPick(word: word, tokens: ranges.map { String(text[$0]) }, index: index, lexicalClass: tag?.rawValue)
    }
}

/// The teacher's notes, selectable; a double-click on an English word opens the word card.
struct NotesWordText: UIViewRepresentable {
    let raw: String
    var onPick: (NotesWordPick, CGRect, UIView) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false; v.isSelectable = true; v.backgroundColor = .clear
        v.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2; double.delegate = context.coordinator
        v.addGestureRecognizer(double)
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.onPick = onPick
        if context.coordinator.raw != raw { context.coordinator.raw = raw; v.attributedText = NotesMarkup.uiText(raw) }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var raw = ""
        var onPick: ((NotesWordPick, CGRect, UIView) -> Void)?
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? UITextView, let pos = v.closestPosition(to: g.location(in: v)) else { return }
            let location = v.offset(from: v.beginningOfDocument, to: pos)
            guard let pick = NotesWordPick.at(location, in: v.text) else { return }
            // The word's rectangle, for the popover arrow.
            var rect = CGRect(origin: g.location(in: v), size: CGSize(width: 1, height: 1))
            if let r = v.tokenizer.rangeEnclosingPosition(pos, with: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue))
                ?? v.tokenizer.rangeEnclosingPosition(pos, with: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.backward.rawValue)) {
                rect = v.firstRect(for: r)
            }
            onPick?(pick, rect, v)
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Word card

/// One choice for the card's front: a phrase found around the word, or the word (base form or as written).
struct WordCandidate: Hashable {
    var front: String
    var phrase: Bool
}

@MainActor final class WordCardModel: ObservableObject {
    let pick: NotesWordPick
    let candidates: [WordCandidate]
    @Published var choice: WordCandidate { didSet { refill() } }
    @Published var front = ""
    @Published var back = ""
    @Published private(set) var senses: [ClassroomDictionary.Sense] = []
    @Published private(set) var mine: String?
    /// ★ 1–3, picked by the teacher. Starts from the card already in the course, else a guess (word ★, phrase ★★).
    @Published var difficulty = 1
    let course: String
    init(pick: NotesWordPick, dictionary: ClassroomDictionary?) {
        self.pick = pick
        let d = dictionary
        var list: [WordCandidate] = []
        // Phrases around the word (longest first), then the word: base form first when it differs (went → go).
        for m in d?.phrases(in: pick.tokens, at: pick.index).prefix(3) ?? [] { list.append(WordCandidate(front: m.phrase, phrase: true)) }
        let base = d?.base(of: pick.word)
        if let base { list.append(WordCandidate(front: base, phrase: false)) }
        let written = pick.word.first?.isUppercase == true && pick.index == 0 ? pick.word.lowercased() : pick.word
        if base?.lowercased() != written.lowercased() { list.append(WordCandidate(front: written, phrase: false)) }
        candidates = list
        // A small word (after, up, in…) usually means its phrase; otherwise the word itself.
        let small = ["Preposition", "Particle", "Adverb"].contains(pick.lexicalClass ?? "")
        choice = (small ? list.first(where: \.phrase) : nil) ?? list.first(where: { !$0.phrase }) ?? list[0]
        course = QuizLibrary.shared.active ?? QuizLibrary.lessonWords
        refill()
    }
    private func refill() {
        front = choice.front
        let d = NotesDictionary.shared.dictionary
        let entry = d?.entry(choice.front)
        senses = ClassroomDictionary.ranked(entry?.senses ?? [], preferring: choice.phrase ? nil : pick.lexicalClass)
        mine = NotesDictionary.shared.myMeaning(choice.front)
        back = mine ?? senses.first?.meanings.first ?? ""
        difficulty = QuizLibrary.shared.card(front: choice.front, in: course)?.difficulty ?? (choice.phrase ? 2 : 1)
    }
    var card: QuizQuestion? {
        let f = front.trimmingCharacters(in: .whitespaces), b = back.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, !b.isEmpty else { return nil }
        var q = QuizQuestion(prompt: String(f.prefix(120)), options: [], answer: 0, kind: .flashcard, difficulty: min(3, max(1, difficulty)), tags: [f.contains(" ") ? "短语" : "单词"], items: [QuizItem(options: [String(b.prefix(200))], answer: 0)])
        q.course = course
        return q
    }
}

struct WordCardPopup: View {
    @ObservedObject var model: WordCardModel
    var onAsk: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("做成闪卡", systemImage: "rectangle.on.rectangle.angled").font(.headline)
                Spacer()
                Text("→ \(model.course)").font(.caption).foregroundStyle(GameTheme.muted).lineLimit(1)
            }
            if model.candidates.count > 1 {
                FlowRow(spacing: 6) {
                    ForEach(model.candidates, id: \.self) { c in
                        let on = c == model.choice
                        Button { model.choice = c } label: {
                            HStack(spacing: 4) {
                                if c.phrase { Image(systemName: "link").font(.caption2.bold()) }
                                Text(c.front).font(.callout.weight(.semibold))
                            }.padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(on ? Color.white : GameTheme.ink)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.6)))
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack { Text("正面").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading); TextField("单词或短语", text: $model.front).textFieldStyle(.roundedBorder) }
            HStack { Text("背面").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading); TextField("中文意思（点下面的词义，或直接输入）", text: $model.back).textFieldStyle(.roundedBorder) }
            // Difficulty is the teacher's call (the app cannot tell what this class knows). Esc on the question
            // (nobody got it) raises it one star.
            HStack(spacing: 6) {
                Text("难度").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading)
                ForEach(1...3, id: \.self) { n in
                    let on = n == model.difficulty
                    Button { model.difficulty = n } label: {
                        Text(String(repeating: "★", count: n)).font(.callout.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 5)
                            .foregroundStyle(on ? Color.white : GameTheme.accent)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? GameTheme.accent : Color.white.opacity(0.6)))
                    }.buttonStyle(.plain).accessibilityLabel("难度\(n)")
                }
                Spacer()
                Text("没人答上来按 Esc：+1★").font(.caption2).foregroundStyle(GameTheme.muted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let mine = model.mine { senseRow("我的词表", [mine]) }
                    ForEach(Array(model.senses.enumerated()), id: \.offset) { _, s in senseRow(s.pos ?? "义", s.meanings) }
                    if model.senses.isEmpty && model.mine == nil {
                        Text(NotesDictionary.shared.dictionary == nil ? "词典加载中…" : "词典里没有，直接输入意思（会记进我的词表）").font(.caption).foregroundStyle(GameTheme.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 220)
            HStack {
                Button { onCancel() } label: { Text("取消") }.buttonStyle(GlassIconButtonStyle())
                Spacer()
                Button { onSave() } label: { Label("只加入题库", systemImage: "tray.and.arrow.down") }.buttonStyle(GlassIconButtonStyle()).disabled(model.card == nil)
                Button { onAsk() } label: { Label("出题 (⏎)", systemImage: "person.3.sequence") }.buttonStyle(GlassIconButtonStyle(prominent: true)).disabled(model.card == nil)
            }
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop()).foregroundStyle(GameTheme.ink)
    }
    private func senseRow(_ pos: String, _ meanings: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(pos).font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 52, alignment: .leading)
            FlowRow(spacing: 5) {
                ForEach(meanings.prefix(10), id: \.self) { m in
                    let on = m == model.back
                    Button { model.back = m } label: {
                        Text(m).font(.callout).padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(on ? Color.white : GameTheme.ink)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

extension QuizLibrary {
    /// Course for cards made from the notes when no course is chosen yet.
    static let lessonWords = "课堂生词"
}

extension MeadowTeacherCoordinator {
    /// Double-click in the notes: the word card.
    func openWordCard(_ pick: NotesWordPick, rect: CGRect, in view: UIView) {
        guard let host = presentationHost else { return }
        NotesDictionary.shared.prewarm()
        // Already a flash card of the current course: call it up for the class straight away.
        if let index = existingNoteCard(pick) { openClassQuiz(index: index); return }
        let model = WordCardModel(pick: pick, dictionary: NotesDictionary.shared.ready())
        let dismiss = { [weak host] in host?.presentedViewController?.dismiss(animated: true) }
        let finish = { [weak self] (ask: Bool) in
            guard let self, let card = model.card else { return }
            dismiss()
            self.addNoteCard(card, ask: ask, picked: model.senses.contains { $0.meanings.contains(card.parts[0].options[0]) })
        }
        let screen = KeyHostingController(rootView: WordCardPopup(model: model, onAsk: { finish(true) }, onSave: { finish(false) }, onCancel: { dismiss() }))
        screen.onKey = { (key: String) -> Bool in
            switch key { case "⏎": finish(true); return true; case "⎋": dismiss(); return true; default: return false }
        }
        // A sheet like the other panels (a popover at the word rendered empty on the Mac).
        screen.modalPresentationStyle = .formSheet
        screen.preferredContentSize = CGSize(width: 460, height: 500)
        host.present(screen, animated: true)
    }
    /// The current course's flash card for the double-clicked word, if the trip has it: the word as written, its
    /// base form (looked → look), then a phrase around it (look after), matched on the card's front without case.
    func existingNoteCard(_ pick: NotesWordPick) -> Int? {
        guard let c = campaign, !quizActive else { return nil }
        let d = NotesDictionary.shared.ready()
        var fronts = [pick.word]
        if let base = d?.base(of: pick.word) { fronts.append(base) }
        fronts += d?.phrases(in: pick.tokens, at: pick.index).map(\.phrase) ?? []
        let cards = c.classFlashDeck
        for f in fronts.map({ $0.lowercased() }) {
            if let i = cards.first(where: { c.quizBank[$0].prompt.lowercased() == f }) { return i }
        }
        return nil
    }
    /// Puts the card in the current course (the same front replaces its old card), and with `ask` shows it to the
    /// class right away as a shared question (pick who answered, right / wrong, rewards).
    func addNoteCard(_ card: QuizQuestion, ask: Bool, picked fromDictionary: Bool) {
        let library = QuizLibrary.shared
        let course = card.course ?? QuizLibrary.lessonWords
        library.addCard(card, to: course)
        if !fromDictionary { NotesDictionary.shared.remember(card.prompt, card.parts[0].options[0]) }
        applyQuizCourse()
        message = "已加入「\(course)」：\(card.prompt) → \(card.parts[0].options[0])"
        guard ask else { revision += 1; return }
        guard let c = campaign else { message += "（还没有打开行程，未出题）"; revision += 1; return }
        guard quiz == nil, challenge == nil else { message += "（正在答题，稍后在全班题里出）"; revision += 1; return }
        guard let index = c.quizBank.lastIndex(where: { $0 == card }) else { revision += 1; return }
        noteCardAsked = (card.prompt, course)
        openClassQuiz(index: index)
    }
}

