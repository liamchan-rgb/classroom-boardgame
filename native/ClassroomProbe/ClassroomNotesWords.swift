import SwiftUI
import UIKit
import NaturalLanguage
import ClassroomGameCore
import ClassroomProbeCore
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
    static let fontSize: CGFloat = 17

    /// The notes with **bold** / __underline__ applied, as UIKit text (for the rich-text notes editor).
    static func uiText(_ raw: String, size: CGFloat = fontSize) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for span in NotesMarkupCodec.parse(raw) {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: span.bold ? .bold : .regular),
                .foregroundColor: UIColor.label
            ]
            if span.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: span.text, attributes: attrs))
        }
        return out
    }

    /// Serializes rich UIKit text back into `**bold**` / `__underline__` markup without exposing syntax tokens.
    static func raw(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        let ns = attributed.string as NSString
        var spans: [NotesMarkupSpan] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            let sub = ns.substring(with: range)
            let bold = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
            let underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            spans.append(NotesMarkupSpan(text: sub, bold: bold, underline: underline))
        }
        return NotesMarkupCodec.encode(spans)
    }
}

/// Editable rich-text UITextView supporting Cmd+B / Cmd+U formatting, double-click word cards, and K on selection.
final class NotesTextView: UITextView {
    var onTriggerSelection: ((String, CGRect, UIView) -> Void)?
    var suppressKUntil: TimeInterval = 0

    override var keyCommands: [UIKeyCommand]? {
        var cmds = (super.keyCommands ?? []).filter {
            !($0.modifierFlags == .command && ["b", "u"].contains(($0.input ?? "").lowercased()))
        }
        let bold = UIKeyCommand(title: "粗体", action: #selector(toggleBoldface(_:)), input: "b", modifierFlags: .command)
        let underline = UIKeyCommand(title: "下划线", action: #selector(toggleUnderline(_:)), input: "u", modifierFlags: .command)
        bold.wantsPriorityOverSystemBehavior = true
        underline.wantsPriorityOverSystemBehavior = true
        cmds.append(contentsOf: [bold, underline])
        return cmds
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleBoldface(_:)) || action == #selector(toggleUnderline(_:)) { return isEditable }
        if action == #selector(toggleItalics(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc override func toggleBoldface(_ sender: Any?) { applyStyleToggle(bold: true) }
    @objc override func toggleUnderline(_ sender: Any?) { applyStyleToggle(bold: false) }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        normalizeFormatting()
        delegate?.textViewDidChange?(self)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if selectedRange.length > 0, markedTextRange == nil, presses.count == 1,
           let key = presses.first?.key,
           key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty,
           key.charactersIgnoringModifiers.lowercased() == "k",
           triggerSelectionFlashcard() {
            suppressKUntil = ProcessInfo.processInfo.systemUptime + 0.08
            return
        }
        super.pressesBegan(presses, with: event)
    }

    private func triggerSelectionFlashcard() -> Bool {
        let range = selectedRange
        guard range.length > 0, NSMaxRange(range) <= (text as NSString).length else { return false }
        let selected = (text as NSString).substring(with: range)
        let cleaned = ClassroomDictionary.normalizedTerm(selected)
        guard !cleaned.isEmpty else { return false }
        var rect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        if let textRange = selectedTextRange {
            let first = firstRect(for: textRange)
            if !first.isNull && !first.isEmpty { rect = first }
        }
        let hostWindow = window
        selectedRange = NSRange(location: range.location, length: 0)
        resignFirstResponder()
        if hostWindow?.rootViewController?.presentedViewController == nil {
            hostWindow?.rootViewController?.becomeFirstResponder()
        }
        onTriggerSelection?(cleaned, rect, self)
        DispatchQueue.main.async { [weak self, weak hostWindow] in
            self?.resignFirstResponder()
            if hostWindow?.rootViewController?.presentedViewController == nil {
                hostWindow?.rootViewController?.becomeFirstResponder()
            }
        }
        return true
    }

    private func applyStyleToggle(bold: Bool) {
        let len = textStorage.length
        let range = selectedRange
        if range.length > 0, NSMaxRange(range) <= len {
            var allOn = true
            textStorage.enumerateAttributes(in: range, options: []) { attrs, _, stop in
                let has = bold
                    ? ((attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
                    : (((attrs[.underlineStyle] as? Int) ?? 0) != 0)
                if !has { allOn = false; stop.pointee = true }
            }
            let targetOn = !allOn
            textStorage.beginEditing()
            textStorage.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
                var next = attrs
                let curBold = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
                let nextBold = bold ? targetOn : curBold
                next[.font] = UIFont.systemFont(ofSize: NotesMarkup.fontSize, weight: nextBold ? .bold : .regular)
                next[.foregroundColor] = UIColor.label
                if !bold {
                    if targetOn { next[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    else { next.removeValue(forKey: .underlineStyle) }
                }
                textStorage.setAttributes(next, range: subRange)
            }
            textStorage.endEditing()
            selectedRange = range
            if range.location < textStorage.length {
                let head = textStorage.attributes(at: range.location, effectiveRange: nil)
                var typing: [NSAttributedString.Key: Any] = [
                    .font: head[.font] ?? UIFont.systemFont(ofSize: NotesMarkup.fontSize),
                    .foregroundColor: UIColor.label
                ]
                if let u = head[.underlineStyle] { typing[.underlineStyle] = u }
                typingAttributes = typing
            }
            delegate?.textViewDidChange?(self)
        } else {
            var attrs = typingAttributes
            let curBold = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
            let curUnderline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            let nextBold = bold ? !curBold : curBold
            let nextUnderline = bold ? curUnderline : !curUnderline
            attrs[.font] = UIFont.systemFont(ofSize: NotesMarkup.fontSize, weight: nextBold ? .bold : .regular)
            attrs[.foregroundColor] = UIColor.label
            if nextUnderline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            else { attrs.removeValue(forKey: .underlineStyle) }
            typingAttributes = attrs
        }
    }

    func normalizeFormatting() {
        guard markedTextRange == nil, textStorage.length > 0 else { return }
        let saved = selectedRange
        let full = NSRange(location: 0, length: textStorage.length)
        var needsFix = false
        textStorage.enumerateAttributes(in: full, options: []) { attrs, _, stop in
            let font = attrs[.font] as? UIFont
            let color = attrs[.foregroundColor] as? UIColor
            if font?.pointSize != NotesMarkup.fontSize || color != UIColor.label || attrs[.backgroundColor] != nil || attrs[.link] != nil || attrs[.strikethroughStyle] != nil {
                needsFix = true
                stop.pointee = true
            }
        }
        guard needsFix else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttributes(in: full, options: []) { attrs, subRange, _ in
            let isBold = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
            let isUnderline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            var clean: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: NotesMarkup.fontSize, weight: isBold ? .bold : .regular),
                .foregroundColor: UIColor.label
            ]
            if isUnderline { clean[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            textStorage.setAttributes(clean, range: subRange)
        }
        textStorage.endEditing()
        if NSMaxRange(saved) <= textStorage.length { selectedRange = saved }
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

/// The teacher's notes: directly editable rich text (bold / underline) without exposing raw markers;
/// double-click an English word (or any word of a compound card) or highlight a phrase and press K to summon a flashcard.
struct NotesWordText: UIViewRepresentable {
    let raw: String
    var editable: Bool = true
    var onEdit: (String) -> Void
    var onFocus: (Bool) -> Void
    var onPick: (NotesWordPick, CGRect, UIView) -> Void
    var onPickSelection: (String, CGRect, UIView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> NotesTextView {
        let v = NotesTextView()
        v.isEditable = editable
        v.isSelectable = true
        v.allowsEditingTextAttributes = true
        v.backgroundColor = .clear
        v.font = .systemFont(ofSize: NotesMarkup.fontSize)
        v.textColor = .label
        v.typingAttributes = [.font: UIFont.systemFont(ofSize: NotesMarkup.fontSize), .foregroundColor: UIColor.label]
        v.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        v.delegate = context.coordinator
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2; double.delegate = context.coordinator
        v.addGestureRecognizer(double)
        return v
    }
    func updateUIView(_ v: NotesTextView, context: Context) {
        if v.isEditable != editable { v.isEditable = editable }
        context.coordinator.onEdit = onEdit
        context.coordinator.onFocus = onFocus
        context.coordinator.onPick = onPick
        v.onTriggerSelection = onPickSelection
        if context.coordinator.raw != raw {
            context.coordinator.raw = raw
            v.attributedText = NotesMarkup.uiText(raw)
            v.typingAttributes = [.font: UIFont.systemFont(ofSize: NotesMarkup.fontSize), .foregroundColor: UIColor.label]
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var raw = ""
        var onEdit: ((String) -> Void)?
        var onFocus: ((Bool) -> Void)?
        var onPick: ((NotesWordPick, CGRect, UIView) -> Void)?

        func textViewDidBeginEditing(_ textView: UITextView) { onFocus?(true) }
        func textViewDidEndEditing(_ textView: UITextView) { onFocus?(false) }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if let notesView = textView as? NotesTextView, range.length > 0, text.lowercased() == "k",
               ProcessInfo.processInfo.systemUptime < notesView.suppressKUntil {
                return false
            }
            return true
        }
        func textViewDidChange(_ textView: UITextView) {
            if let notesView = textView as? NotesTextView { notesView.normalizeFormatting() }
            let encoded = NotesMarkup.raw(from: textView.attributedText)
            raw = encoded
            onEdit?(encoded)
        }

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
            let hostWindow = v.window
            v.selectedRange = NSRange(location: location, length: 0)
            v.resignFirstResponder()
            if hostWindow?.rootViewController?.presentedViewController == nil {
                hostWindow?.rootViewController?.becomeFirstResponder()
            }
            onPick?(pick, rect, v)
            DispatchQueue.main.async { [weak v, weak hostWindow] in
                guard let v else { return }
                v.selectedRange = NSRange(location: min(location, (v.text as NSString).length), length: 0)
                v.resignFirstResponder()
                if hostWindow?.rootViewController?.presentedViewController == nil {
                    hostWindow?.rootViewController?.becomeFirstResponder()
                }
            }
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
    let pick: NotesWordPick?
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

    init(selection: String, dictionary: ClassroomDictionary?) {
        self.pick = nil
        let cleaned = ClassroomDictionary.normalizedTerm(selection)
        let entry = dictionary?.entry(cleaned)
        var list: [WordCandidate] = []
        if !cleaned.contains(" "), let base = dictionary?.base(of: cleaned) {
            list.append(WordCandidate(front: base, phrase: false))
        }
        if let entryWord = entry?.word, !list.contains(where: { $0.front.lowercased() == entryWord.lowercased() }) {
            list.append(WordCandidate(front: entryWord, phrase: entryWord.contains(" ")))
        }
        if !cleaned.isEmpty, !list.contains(where: { $0.front.lowercased() == cleaned.lowercased() }) {
            list.append(WordCandidate(front: cleaned, phrase: cleaned.contains(" ")))
        }
        if list.isEmpty { list = [WordCandidate(front: cleaned, phrase: cleaned.contains(" "))] }
        candidates = list
        choice = list[0]
        course = QuizLibrary.shared.active ?? QuizLibrary.lessonWords
        refill()
    }

    private func refill() {
        front = choice.front
        let d = NotesDictionary.shared.dictionary
        let entry = d?.entry(choice.front)
        let prefer = (choice.phrase || pick == nil) ? nil : pick?.lexicalClass
        senses = ClassroomDictionary.ranked(entry?.senses ?? [], preferring: prefer)
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
    /// Double-click in the notes: the word card (or switch straight to it if another flashcard is already showing).
    func openWordCard(_ pick: NotesWordPick, rect: CGRect, in view: UIView) {
        NotesDictionary.shared.prewarm()
        // Already a flash card of the current course: call it up for the class straight away.
        if let index = existingNoteCard(pick) { askNoteCard(at: index, englishFront: true); return }
        let model = WordCardModel(pick: pick, dictionary: NotesDictionary.shared.ready())
        presentWordCardModel(model)
    }

    /// Highlighted text in the notes + K: opens existing flashcard or builds one for a compound/phrase not in the bank.
    func openSelectionCard(_ selection: String, rect: CGRect, in view: UIView) {
        let cleaned = ClassroomDictionary.normalizedTerm(selection)
        guard !cleaned.isEmpty else { return }
        NotesDictionary.shared.prewarm()
        if let index = existingSelectionCard(cleaned) { askNoteCard(at: index, englishFront: true); return }
        let model = WordCardModel(selection: cleaned, dictionary: NotesDictionary.shared.ready())
        presentWordCardModel(model)
    }

    private func presentWordCardModel(_ model: WordCardModel) {
        guard let host = presentationHost else { return }
        // New word / phrase: the meaning the context calls for, ★, asked right away; unknown terms open WordCardPopup.
        model.difficulty = 1
        if let card = model.card {
            addNoteCard(card, ask: true, picked: true)
            message += "（意思按上下文自动选的；不对可在“闪卡 → 选卡 → 编辑”里改，作答记录保留）"
            revision += 1
            return
        }
        let dismiss = { [weak host] in
            KeyHostingController<EmptyView>.endEditing()
            host?.presentedViewController?.dismiss(animated: true)
        }
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

    private func courseFlashcards(_ c: MeadowCampaignSession) -> [(index: Int, english: String)] {
        c.classFlashDeck.map { i in (i, QuizReport.word(c.quizBank[i], part: 0)?.word ?? c.quizBank[i].prompt) }
    }

    /// The current course's flash card for the double-clicked word (prioritizing matching compound phrases like "ice cream"
    /// over their single-word parts), if the notes/quiz state allows opening or switching a flashcard.
    func existingNoteCard(_ pick: NotesWordPick) -> Int? {
        guard let c = campaign, canSwitchNotesFlashcard else { return nil }
        return ClassroomDictionary.matchingFlashcard(tokens: pick.tokens, at: pick.index, cards: courseFlashcards(c), dictionary: NotesDictionary.shared.ready())
    }

    /// The current course's flash card for an explicitly highlighted word/phrase selection.
    func existingSelectionCard(_ selection: String) -> Int? {
        guard let c = campaign, canSwitchNotesFlashcard else { return nil }
        return ClassroomDictionary.matchingFlashcard(selection: selection, cards: courseFlashcards(c), dictionary: NotesDictionary.shared.ready())
    }

    /// Puts the card in the current course (the same front replaces its old card), and with `ask` shows it to the
    /// class right away as a shared question (or switches an already displayed flashcard).
    func addNoteCard(_ card: QuizQuestion, ask: Bool, picked fromDictionary: Bool) {
        let library = QuizLibrary.shared
        let course = card.course ?? QuizLibrary.lessonWords
        library.addCard(card, to: course)
        if !fromDictionary { NotesDictionary.shared.remember(card.prompt, card.parts[0].options[0]) }
        applyQuizCourse()
        message = "已加入「\(course)」：\(card.prompt) → \(card.parts[0].options[0])"
        guard ask else { revision += 1; return }
        guard let c = campaign else { message += "（还没有打开行程，未出题）"; revision += 1; return }
        guard canSwitchNotesFlashcard else { message += "（正在答题，稍后在全班题里出）"; revision += 1; return }
        guard let index = c.quizBank.lastIndex(where: { $0 == card }) else { revision += 1; return }
        askNoteCard(at: index, englishFront: true)
    }
}

