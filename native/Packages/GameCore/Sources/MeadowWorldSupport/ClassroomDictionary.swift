import Foundation

/// The offline English–Chinese dictionary behind "double-click a word in the notes → flash card": words with their
/// senses by part of speech, word forms (went → go), and phrases (look after, pick … up) found around a word.
/// Data: a trimmed ECDICT (MIT), one line per entry: `word \t senses joined by " | " \t exchange`.
public final class ClassroomDictionary {
    /// One part-of-speech line: "v." and its meanings ("登记", "预订").
    public struct Sense: Equatable {
        public var pos: String?
        public var meanings: [String]
    }
    public struct Entry: Equatable {
        public var word: String
        public var senses: [Sense]
    }
    /// A phrase found in the sentence: its dictionary form and the token positions it covers.
    public struct PhraseMatch: Equatable {
        public var phrase: String
        public var tokens: [Int]
    }

    private var raw: [String: (word: String, senses: String)] = [:]
    /// Word form → base form (went → go, apples → apple).
    private var bases: [String: String] = [:]
    /// First word of a phrase → the phrases' words.
    private var phrasesByFirst: [String: [[String]]] = [:]

    public init(tsv: String) {
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard cols.count >= 2 else { continue }
            let word = String(cols[0]), key = word.lowercased()
            if raw[key] == nil { raw[key] = (word, String(cols[1])) }
            if key.contains(" ") {
                let toks = key.split(separator: " ").map(String.init)
                phrasesByFirst[toks[0], default: []].append(toks)
            }
            if cols.count == 3 {
                // exchange: p:went/d:gone/i:going/3:goes/s:… (forms of this word); 0:go = this word's base.
                for item in cols[2].split(separator: "/") {
                    let kv = item.split(separator: ":", maxSplits: 1)
                    guard kv.count == 2 else { continue }
                    let tag = kv[0], value = String(kv[1]).lowercased()
                    if tag == "0" { if bases[key] == nil { bases[key] = value } }
                    else if ["p", "d", "i", "3", "s", "r", "t"].contains(tag), value != key, bases[value] == nil { bases[value] = key }
                }
            }
        }
    }
    public convenience init(contentsOf url: URL) throws { self.init(tsv: try String(contentsOf: url, encoding: .utf8)) }

    /// The base form of a word ("went" → "go"), or nil when it is already a base form / unknown.
    public func base(of word: String) -> String? {
        let key = word.lowercased()
        guard let b = bases[key], b != key, raw[b] != nil else { return nil }
        return b
    }
    /// Looks a word or phrase up as written, then by its base form.
    public func entry(_ text: String) -> Entry? {
        let key = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let r = raw[key] { return Entry(word: r.word, senses: Self.senses(r.senses)) }
        if let b = base(of: key), let r = raw[b] { return Entry(word: r.word, senses: Self.senses(r.senses)) }
        return nil
    }
    /// "n. 书, 书籍 | v. 登记, 预订" → [n.: 书, 书籍], [v.: 登记, 预订].
    static func senses(_ s: String) -> [Sense] {
        s.components(separatedBy: " | ").compactMap { line in
            var text = line.trimmingCharacters(in: .whitespaces), pos: String?
            if let r = text.range(of: #"^[a-z]+\.(\s*&\s*[a-z]+\.)?\s*"#, options: .regularExpression) {
                pos = String(text[r]).trimmingCharacters(in: .whitespaces); text = String(text[r.upperBound...])
            }
            let meanings = text.components(separatedBy: CharacterSet(charactersIn: ",，;；"))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !isUnfit($0) }
            return meanings.isEmpty ? nil : Sense(pos: pos, meanings: meanings)
        }
    }
    /// Sexual / vulgar meanings are never offered in a children's classroom: the meaning is dropped (the word keeps
    /// its other meanings: cock → 公鸡, seed → 种子), and a word or phrase with nothing else left is not offered at all.
    static let unfitTerms = ["阴茎", "阳物", "阳具", "阴道", "阴户", "阴部", "阴蒂", "阴毛", "阴囊", "生殖器", "性器", "睾丸", "精液", "射精",
                             "勃起", "性交", "交媾", "交合", "做爱", "性行为", "性欲", "手淫", "自慰", "卖淫", "妓女", "娼妓", "嫖", "淫",
                             "色情", "春药", "鸡巴", "屌", "肏", "操你", "他妈", "妈的", "婊子", "狗娘养", "贱人", "荡妇", "鸡奸", "奶子",
                             "屄", "私处", "下体", "口交", "肛交", "乱伦", "强奸", "性高潮"]
    static func isUnfit(_ meaning: String) -> Bool { unfitTerms.contains { meaning.contains($0) } }

    /// Phrases in the dictionary that include token `index` of the sentence, longest first. Tokens match as written
    /// or by base form (looked → look); up to two words may sit inside a phrase before its last word (pick it up).
    public func phrases(in tokens: [String], at index: Int) -> [PhraseMatch] {
        guard tokens.indices.contains(index) else { return [] }
        let forms = tokens.map { t -> Set<String> in
            let l = t.lowercased(); var s: Set<String> = [l]; if let b = base(of: l) { s.insert(b) }; return s
        }
        var found: [PhraseMatch] = []
        for start in max(0, index - 4)...index {
            for first in forms[start] {
                for phrase in phrasesByFirst[first] ?? [] {
                    if let used = match(phrase, forms: forms, from: start), used.contains(index) {
                        let r = raw[phrase.joined(separator: " ")]
                        // A phrase whose only meanings are unfit for class is not suggested.
                        if let r, Self.senses(r.senses).isEmpty { continue }
                        let m = PhraseMatch(phrase: r?.word ?? phrase.joined(separator: " "), tokens: used)
                        if !found.contains(m) { found.append(m) }
                    }
                }
            }
        }
        return found.sorted { $0.tokens.count == $1.tokens.count ? $0.tokens[0] < $1.tokens[0] : $0.tokens.count > $1.tokens.count }
    }
    private func match(_ phrase: [String], forms: [Set<String>], from start: Int) -> [Int]? {
        var used = [start], at = start + 1
        for (k, word) in phrase.enumerated().dropFirst() {
            // The last word may come after up to two others (separable verbs: pick it up, turn the light off).
            let gap = k == phrase.count - 1 ? 2 : 0
            let upper = min(at + gap, forms.count - 1)
            guard at <= upper, let hit = (at...upper).first(where: { forms[$0].contains(word) }) else { return nil }
            used.append(hit); at = hit + 1
        }
        return used
    }

    /// Senses ordered for a part of speech found in the sentence ("verb" first for "book a room").
    public static func ranked(_ senses: [Sense], preferring lexicalClass: String?) -> [Sense] {
        guard let lexicalClass, let tags = posTags[lexicalClass] else { return senses }
        let hit = senses.filter { s in s.pos.map { p in tags.contains { p.hasPrefix($0) } } ?? false }
        return hit + senses.filter { !hit.contains($0) }
    }
    /// NaturalLanguage lexical classes → ECDICT part-of-speech prefixes.
    static let posTags: [String: [String]] = [
        "Noun": ["n."], "Verb": ["v.", "vt.", "vi."], "Adjective": ["a.", "adj."], "Adverb": ["ad.", "adv."],
        "Preposition": ["prep."], "Pronoun": ["pron."], "Conjunction": ["conj."], "Interjection": ["int.", "interj."],
        "Determiner": ["art.", "det."], "Number": ["num."],
    ]
}
