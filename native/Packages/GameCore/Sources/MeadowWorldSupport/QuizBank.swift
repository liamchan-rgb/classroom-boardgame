import Foundation
import ClassroomGameCore

/// Question-bank import for quiz events (format: docs/question-bank-format.md).
///
/// Plain text (UTF-8), one question per block, blocks separated by a blank line:
///
///     1. 光合作用主要在植物的哪个部位进行？
///     A. 根
///     B. 叶
///     C. 茎
///     D. 花
///     答案：B
///     金币：15          (optional, default 10)
///     解析：叶片含叶绿体。 (optional)
///
/// or JSON: {"questions":[{"prompt":"…","options":["…","…"],"answer":"B","coins":15,"explanation":"…"}]}
/// ("answer" may be a letter or a 0-based number; a bare array of questions also works).
public enum QuizBankParser {
    /// A bank back in the plain-text format it is imported from (docs/question-bank-format.md), so it can be handed to
    /// a language model to fix and imported again. Questions in the same order; blank lines only between questions.
    public static func text(_ list:[QuizQuestion],course:String?=nil)->String {
        let letters=Array("ABCDEFGH").map(String.init)
        func lines(_ t:String)->[String] {t.split(separator:"\n",omittingEmptySubsequences:true).map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}}
        func options(_ p:QuizItem)->[String] {p.options.enumerated().map{"\(letters[min($0.offset,letters.count-1)]). \($0.element)"}}
        var blocks:[String]=[]
        for q in list {
            var b:[String]=[]
            switch q.type {
            case .choice:
                b=["类型：选择","难度：\(q.level)"]+lines(q.prompt)+options(q.parts[0])+["答案：\(letters[min(q.answer,letters.count-1)])"]
            case .flashcard:
                let p=q.parts.first
                b=["类型：闪卡","难度：\(q.level)","正面：\(q.prompt)","背面：\(p.map{$0.options[$0.answer]} ?? "")"]
            case .fill:
                var t=q.prompt
                for (k,p) in q.parts.enumerated() {
                    let right=p.options[p.answer],others=p.options.enumerated().filter{$0.offset != p.answer}.map(\.element)
                    t=t.replacingOccurrences(of:"{{\(k+1)}}",with:"{{"+([right]+others).joined(separator:"|")+"}}")
                }
                b=["类型：填空","难度：\(q.level)",t.replacingOccurrences(of:"\n",with:" ")]
            case .reading:
                b=["类型：阅读","难度：\(q.level)"]
                if q.prompt != "阅读短文，回答问题" {b+=lines(q.prompt).map{"题目："+$0}}
                let passage=lines(q.passage ?? "")
                b.append("文章："+(passage.first ?? ""));b+=passage.dropFirst()
                for p in q.parts {b.append("问：\(p.prompt ?? "")");b+=options(p);b.append("答案：\(letters[min(p.answer,letters.count-1)])")}
            }
            if let s=q.seconds {b.append("时间：\(s)")}
            if let t=q.tags,!t.isEmpty {b.append("标签："+t.joined(separator:", "))}
            if let e=q.explanation,!e.isEmpty {b.append("解析："+e.replacingOccurrences(of:"\n",with:" "))}
            blocks.append(b.joined(separator:"\n"))
        }
        return (course.map{["# 课程：\($0)"]} ?? []).joined()+(course == nil ? "":"\n\n")+blocks.joined(separator:"\n\n")+"\n"
    }
    public static func parse(_ data:Data)throws->[QuizQuestion] {
        guard data.count<=2*1024*1024 else{throw GameError("题库文件超过2 MB。")}
        var text=String(decoding:data,as:UTF8.self)
        if text.hasPrefix("\u{FEFF}"){text.removeFirst()}
        let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
        var questions=trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ? try json(Data(trimmed.utf8)):try plain(trimmed)
        guard !questions.isEmpty else{throw GameError("没有读到题目，请对照题库格式说明。")}
        guard questions.count<=2000 else{throw GameError("题库最多2000题。")}
        for q in questions{try q.validate()}
        return questions
    }

    // MARK: Building the kinds

    /// Stable shuffle (same bank → same order on every device), so the teacher's buttons never jump around.
    static func shuffled(_ list:[String],seed text:String)->[String] {
        var h:UInt64=0xcbf29ce484222325
        for b in text.utf8 {h=(h ^ UInt64(b)) &* 0x100000001b3}
        var a=list
        for i in stride(from:a.count-1,to:0,by:-1) {h=h &* 6364136223846793005 &+ 1442695040888963407;a.swapAt(i,Int((h>>33)%UInt64(i+1)))}
        return a
    }
    static func item(_ prompt:String?,correct:String,wrong:[String])->QuizItem {
        var seen=Set<String>([correct]),others:[String]=[]
        for w in wrong where !w.isEmpty && seen.insert(w).inserted {others.append(w)}
        let options=shuffled([correct]+others.prefix(5),seed:(prompt ?? "")+correct)
        return QuizItem(prompt:prompt,options:options,answer:options.firstIndex(of:correct)!)
    }
    /// "Tom {{went|goed|go}} home." → prompt "Tom {{1}} home.", one item whose right answer is the first candidate.
    static func fill(_ raw:String)throws->(String,[QuizItem]) {
        var prompt="",items:[QuizItem]=[],rest=Substring(raw)
        while let open=rest.range(of:"{{") {
            guard let close=rest[open.upperBound...].range(of:"}}") else{throw GameError("填空的 {{ }} 没有配对：「\(raw.prefix(20))」")}
            prompt+=rest[..<open.lowerBound]
            let candidates=rest[open.upperBound..<close.lowerBound].split(whereSeparator:{"|｜/".contains($0)}).map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
            guard let correct=candidates.first else{throw GameError("填空的空格里需要写答案：「\(raw.prefix(20))」")}
            items.append(item("第\(items.count+1)空",correct:correct,wrong:Array(candidates.dropFirst())))
            prompt+="{{\(items.count)}}"
            rest=rest[close.upperBound...]
        }
        prompt+=rest
        guard !items.isEmpty else{throw GameError("填空题需要用 {{答案}} 标出空格：「\(raw.prefix(20))」")}
        return(prompt,items)
    }
    /// A flash card is graded right / wrong by the teacher: its one option is the back (distractors are ignored).
    public static func flashcard(front:String,back:String,distractors:[String])->QuizQuestion {
        QuizQuestion(prompt:front,options:[],answer:0,kind:.flashcard,items:[QuizItem(options:[back],answer:0)])
    }
    static func difficulty(_ raw:String)->Int? {
        let v=raw.trimmingCharacters(in:.whitespaces)
        if let n=Int(v.filter(\.isNumber)),(1...3).contains(n) {return n}
        let stars=v.filter{"★☆*".contains($0)}.count
        if (1...3).contains(stars) {return stars}
        if ["简单","易","容易","easy"].contains(where:v.lowercased().contains) {return 1}
        if ["中等","中","普通","medium"].contains(where:v.lowercased().contains) {return 2}
        if ["困难","难","hard"].contains(where:v.lowercased().contains) {return 3}
        return nil
    }
    /// "90", "90秒", "1:30", "2分钟", "1分30秒".
    static func seconds(_ raw:String)->Int? {
        let v=raw.replacingOccurrences(of:"：",with:":").trimmingCharacters(in:.whitespaces)
        let parts=v.split(separator:":").map{Int($0.filter(\.isNumber))}
        if parts.count==2,let m=parts[0],let s=parts[1] {return m*60+s}
        if v.contains("分") {
            let pieces=v.split(separator:"分",maxSplits:1)
            let m=Int(pieces[0].filter(\.isNumber)) ?? 0,s=pieces.count>1 ? Int(pieces[1].filter(\.isNumber)) ?? 0:0
            return m*60+s
        }
        return Int(v.filter(\.isNumber))
    }
    static func kind(_ raw:String)->QuizKind? {
        let v=raw.lowercased()
        if v.contains("闪") || v.contains("flash") || v.contains("卡") {return .flashcard}
        if v.contains("填") || v.contains("fill") || v.contains("blank") {return .fill}
        if v.contains("阅读") || v.contains("read") {return .reading}
        if v.contains("选") || v.contains("判断") || v.contains("choice") {return .choice}
        return nil
    }
    /// "第1份" / "1份" / "１" → "1"; letters stay ("A").
    static func portionName(_ raw:String)->String? {
        var v=raw.trimmingCharacters(in:.whitespaces).replacingOccurrences(of:"第",with:"").replacingOccurrences(of:"份",with:"").replacingOccurrences(of:"组",with:"")
        v=String(v.map{c in c.isNumber ? Character(String(c.wholeNumberValue ?? 0)):c}).trimmingCharacters(in:.whitespaces)
        return v.isEmpty ? nil:String(v.prefix(20))
    }
    static func list(_ raw:String)->[String] {raw.split(whereSeparator:{",，、;；/|｜".contains($0)}).map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}}

    // MARK: JSON

    private struct JSONItem:Decodable {let prompt:String?;let options:[String];let answer:JSONAnswer}
    enum JSONAnswer:Decodable {
        case index(Int),letter(String)
        init(from decoder:Decoder)throws {
            let c=try decoder.singleValueContainer()
            if let i=try? c.decode(Int.self){self = .index(i)} else {self = .letter(try c.decode(String.self))}
        }
        func index(_ prompt:String)throws->Int {
            switch self {
            case .index(let i):return i
            case .letter(let l):guard let i=letterIndex(l) else{throw GameError("答案应为 A–F：「\(prompt.prefix(20))」")};return i
            }
        }
    }
    private struct JSONQuestion:Decodable {
        let type:String?;let prompt:String?;let options:[String]?;let answer:JSONAnswer?;let coins:Int?;let explanation:String?
        let difficulty:JSONAnswer?;let seconds:Int?;let tags:[String]?;let audience:[String]?;let target:String?;let portion:JSONAnswer?
        let front:String?;let back:String?;let distractors:[String]?
        let passage:String?;let questions:[JSONItem]?
    }
    private struct JSONBank:Decodable {let questions:[JSONQuestion]}
    private static func json(_ data:Data)throws->[QuizQuestion] {
        let list:[JSONQuestion]
        do {
            if let bank=try? JSONDecoder().decode(JSONBank.self,from:data){list=bank.questions}
            else {list=try JSONDecoder().decode([JSONQuestion].self,from:data)}
        } catch {throw GameError("JSON 题库格式不对：需要 prompt、options、answer 字段（或 type 对应的字段）。")}
        return try list.map{j in
            let type=j.type.flatMap(kind) ?? (j.front != nil ? .flashcard:j.passage != nil ? .reading:(j.prompt?.contains("{{") ?? false) ? .fill:.choice)
            var q:QuizQuestion
            switch type {
            case .choice:
                guard let prompt=j.prompt,let options=j.options,let answer=j.answer else{throw GameError("选择题需要 prompt、options、answer。")}
                q=QuizQuestion(prompt:prompt,options:options,answer:try answer.index(prompt))
            case .flashcard:
                guard let front=j.front ?? j.prompt,let back=j.back else{throw GameError("闪卡需要 front 和 back。")}
                q=flashcard(front:front,back:back,distractors:j.distractors ?? [])
            case .fill:
                guard let prompt=j.prompt else{throw GameError("填空题需要 prompt。")}
                let (text,items)=try fill(prompt);q=QuizQuestion(prompt:text,options:[],answer:0,kind:.fill,items:items)
            case .reading:
                guard let passage=j.passage,let subs=j.questions,!subs.isEmpty else{throw GameError("阅读题需要 passage 和 questions。")}
                q=QuizQuestion(prompt:j.prompt ?? "阅读短文，回答问题",options:[],answer:0,kind:.reading,passage:passage,
                               items:try subs.map{QuizItem(prompt:$0.prompt,options:$0.options,answer:try $0.answer.index($0.prompt ?? ""))})
            }
            q.coins=j.coins;q.explanation=j.explanation;q.seconds=j.seconds;q.tags=j.tags
            q.audience=j.audience ?? j.target.map{QuizBankParser.list($0)}
            if let p=j.portion {switch p {case .index(let i):q.portion=String(i);case .letter(let l):q.portion=portionName(l)}}
            if let d=j.difficulty {
                switch d {case .index(let i):q.difficulty=i;case .letter(let l):q.difficulty=difficulty(l)}
            }
            if type != .choice || j.difficulty != nil || j.type != nil {q.kind=type}
            return q
        }
    }
    static func letterIndex(_ raw:String)->Int? {
        let s=raw.trimmingCharacters(in:.whitespaces).uppercased()
        let map:[String:Int]=["A":0,"B":1,"C":2,"D":3,"E":4,"F":5,"Ａ":0,"Ｂ":1,"Ｃ":2,"Ｄ":3,"Ｅ":4,"Ｆ":5]
        return s.first.flatMap{map[String($0)]}
    }

    // MARK: Plain text

    private static func plain(_ text:String)throws->[QuizQuestion] {
        let lines=text.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").components(separatedBy:"\n")
        var blocks:[[String]]=[],current:[String]=[]
        for line in lines {
            let l=line.trimmingCharacters(in:.whitespaces)
            if l.hasPrefix("#") || l.hasPrefix("//") {continue}
            if l.isEmpty {if !current.isEmpty{blocks.append(current);current=[]};continue}
            current.append(l)
        }
        if !current.isEmpty{blocks.append(current)}
        return try blocks.enumerated().map{n,block in try question(block,number:n+1)}
    }
    private static func value(_ line:String,keys:[String])->String? {
        for key in keys {
            for sep in ["：",":"] where line.hasPrefix(key+sep) {return String(line.dropFirst(key.count+sep.count)).trimmingCharacters(in:.whitespaces)}
        }
        return nil
    }
    /// "A. text", "A、text", "A) text", "A：text", "(A) text"
    private static func option(_ line:String)->(Int,String)? {
        var l=line
        if l.hasPrefix("(") || l.hasPrefix("（") {l.removeFirst()}
        guard let first=l.first,let index=letterIndex(String(first)) else{return nil}
        let rest=l.dropFirst()
        guard let sep=rest.first,".．、)）:：".contains(sep) else{return nil}
        let body=rest.dropFirst().trimmingCharacters(in:.whitespaces)
        return body.isEmpty ? nil:(index,body)
    }
    private static func stripNumber(_ text:String)->String {
        var t=text
        // Leading numbering such as "1." / "1、" / "第1题" is not part of the question.
        if let r=t.range(of:#"^(第?\d+题?[\.．、:：)）]?\s*)"#,options:.regularExpression) {t.removeSubrange(r)}
        return t
    }
    private static func question(_ block:[String],number:Int)throws->QuizQuestion {
        var prompt=[String](),options=[(Int,String)](),answer:String?,coins:Int?,explanation:String?
        var type:QuizKind?,level:Int?,limit:Int?,tags:[String]?,audience:[String]?,portion:String?,front:String?,back:String?,wrong:[String]=[]
        var passage:[String]?,subs:[(prompt:String,options:[(Int,String)],answer:String?)]=[]
        func fail(_ why:String)->GameError {GameError("第\(number)题：\(why)")}
        for line in block {
            if let v=value(line,keys:["类型","题型","Type","type"]) {type=kind(v);if type==nil{throw fail("不认识的题型「\(v)」（可写 选择 / 闪卡 / 填空 / 阅读）")}}
            else if let v=value(line,keys:["难度","Difficulty","difficulty"]) {level=difficulty(v);if level==nil{throw fail("难度应为 1–3 或 简单/中等/困难")}}
            else if let v=value(line,keys:["时间","限时","Time","time"]) {limit=seconds(v)}
            else if let v=value(line,keys:["标签","知识点","Tags","tags"]) {tags=list(v)}
            else if let v=value(line,keys:["对象","专属","给","For","for"]) {audience=list(v)}
            else if let v=value(line,keys:["份","份数","分组","组","Portion","portion","Part","part"]) {portion=portionName(v)}
            else if let v=value(line,keys:["正面","Front","front"]) {front=v}
            else if let v=value(line,keys:["背面","Back","back"]) {back=v}
            else if let v=value(line,keys:["干扰","干扰项","Distractors","distractors"]) {wrong=list(v)}
            else if let v=value(line,keys:["文章","短文","Passage","passage"]) {passage=v.isEmpty ? []:[v]}
            else if let v=value(line,keys:["问","小题","Question"]) {subs.append((stripNumber(v),[],nil))}
            else if let v=value(line,keys:["答案","正确答案","Answer","answer"]) {if subs.isEmpty{answer=v}else{subs[subs.count-1].answer=v}}
            else if let v=value(line,keys:["金币","奖励","Coins","coins"]) {coins=Int(v.filter(\.isNumber))}
            else if let v=value(line,keys:["解析","说明","Explanation","explanation"]) {explanation=v}
            else if !subs.isEmpty,let o=option(line) {subs[subs.count-1].options.append(o)}
            else if !subs.isEmpty {throw fail("无法识别「\(line.prefix(20))」")}
            else if passage != nil {passage!.append(line)}
            else if options.isEmpty,let v=value(line,keys:["题目","问题","Q","q"]) {prompt.append(v)}
            else if let o=option(line) {options.append(o)}
            else if options.isEmpty {prompt.append(line)}
            else {throw fail("无法识别「\(line.prefix(20))」")}
        }
        let first=stripNumber(prompt.joined(separator:"\n"))
        let resolved=type ?? (front != nil ? .flashcard:passage != nil ? .reading:first.contains("{{") ? .fill:.choice)
        var q:QuizQuestion
        switch resolved {
        case .choice:
            guard !first.isEmpty else{throw fail("缺少题目。")}
            guard options.count>=2,options.enumerated().allSatisfy({$0.offset==$0.element.0}) else{throw fail("选项需从 A 开始依次排列，至少两项。")}
            guard let a=answer.flatMap(letterIndex),a<options.count else{throw fail("缺少「答案：」或答案超出选项。")}
            q=QuizQuestion(prompt:first,options:options.map(\.1),answer:a)
        case .flashcard:
            guard let face=front ?? (first.isEmpty ? nil:first),let backText=back ?? answer else{throw fail("闪卡需要「正面：」和「背面：」。")}
            q=flashcard(front:face,back:backText,distractors:wrong)
        case .fill:
            let (text,items)=try fill(first);q=QuizQuestion(prompt:text,options:[],answer:0,kind:.fill,items:items)
        case .reading:
            guard let passage,!passage.isEmpty else{throw fail("阅读题需要「文章：」。")}
            guard !subs.isEmpty else{throw fail("阅读题需要至少一个「问：」小题。")}
            let items=try subs.map{sub->QuizItem in
                guard sub.options.count>=2,sub.options.enumerated().allSatisfy({$0.offset==$0.element.0}) else{throw fail("小题「\(sub.prompt.prefix(12))」的选项需从 A 开始依次排列。")}
                guard let a=sub.answer.flatMap(letterIndex),a<sub.options.count else{throw fail("小题「\(sub.prompt.prefix(12))」缺少答案。")}
                return QuizItem(prompt:sub.prompt,options:sub.options.map(\.1),answer:a)
            }
            q=QuizQuestion(prompt:first.isEmpty ? "阅读短文，回答问题":first,options:[],answer:0,kind:.reading,passage:passage.joined(separator:"\n"),items:items)
        }
        q.coins=coins;q.explanation=explanation;q.difficulty=level;q.seconds=limit;q.tags=tags;q.audience=audience;q.portion=portion
        if resolved != .choice || type != nil {q.kind=resolved}
        return q
    }
}

public extension MeadowCampaignSession {
    var quizBank:[QuizQuestion] {snapshot.quizBank ?? []}
    var quizLog:[QuizAttempt] {engine.state.quizLog ?? []}
    /// Whether a question belongs to the current course.
    func inCourse(_ q:QuizQuestion)->Bool {quizCourseQuestions.map{$0.contains(q)} ?? true}
    /// Bank indices of the current course.
    var courseIndices:[Int] {
        let bank=quizBank
        guard let course=quizCourseQuestions else{return Array(bank.indices)}
        return bank.indices.filter{course.contains(bank[$0])}
    }
    /// Switch to a course: its questions are added to the trip's bank if they are not there yet (appended, so
    /// earlier answers keep pointing at their questions), and questions are dealt from it from now on.
    func useQuizCourse(_ name:String?,questions:[QuizQuestion])throws {
        let have=quizBank
        let missing=questions.filter{q in !have.contains(q)}
        if !missing.isEmpty {try appendQuizBank(missing)}
        quizCourse=name;quizCourseQuestions=name==nil ? nil:questions
    }
    /// Whether this node is a quiz event (roadside finds become quizzes when a bank was imported).
    func isQuizNode(_ node:Int)->Bool {!courseIndices.isEmpty && siteKind(node:node) == .satchel}
    /// Questions are dealt in bank order (from a start set by the map seed): each answer takes the next one.
    var nextQuizIndex:Int? {
        let bank=quizBank
        guard !bank.isEmpty else{return nil}
        let log=quizLog
        // Events answered before per-student records existed also used up a question each.
        let old=engine.state.map.nodes.filter{n in n.siteResolved == true && isQuizNode(n.id) && !log.contains(where:{$0.node==n.id})}.count
        return (Int(engine.state.map.seed % UInt64(bank.count))+log.count+old)%bank.count
    }
    /// The question the next student at this quiz node would get (nil when it is not a quiz node).
    func quizQuestion(node:Int)->QuizQuestion? {
        guard isQuizNode(node),let i=nextQuizIndex else{return nil}
        return quizBank[i]
    }
    /// Whose turn: `actor` may answer here if the event is open and they have not answered at this node yet;
    /// they get the next question nobody has had (bank order from the map seed), else one they have not had, else any.
    func quizTurn(actor:String)->(index:Int,question:QuizQuestion)? {
        guard let unit=engine.state.units[actor],isQuizNode(unit.nodeID),
              engine.state.map.nodes.first(where:{$0.id==unit.nodeID})?.siteResolved != true,
              !quizLog.contains(where:{$0.player==actor && $0.node==unit.nodeID}) else{return nil}
        let answered=Set(quizLog.filter{$0.player==actor && $0.practice != true}.map(\.question)),order=dealingOrder
        let used=usedQuizQuestions
        guard let i=order.first(where:{!used.contains($0)}) ?? order.first(where:{!answered.contains($0)}) ?? order.first else{return nil}
        return(i,quizBank[i])
    }
    /// Bank indices in dealing order (from a start set by the map seed).
    private var dealingOrder:[Int] {
        let n=quizBank.count
        guard n>0 else{return []}
        let base=Int(engine.state.map.seed % UInt64(n))
        return (0..<n).map{(base+$0)%n}.filter{inCourse(quizBank[$0])}
    }
    /// Questions already asked (to a student or to the class; practice does not count).
    var usedQuizQuestions:Set<Int> {Set(quizLog.filter{$0.practice != true}.map(\.question))}
    /// Whether the question was asked before in this trip (it comes up again with its options shuffled).
    func quizAskedBefore(_ index:Int)->Bool {quizLog.contains{$0.question==index && $0.practice != true}}
    /// The course's questions a draw may take: all of them, or one difficulty (unmarked counts as ★), optionally one kind.
    func quizPool(_ draw:QuizDraw,kind:QuizKind?=nil)->[Int] {
        let bank=quizBank
        return courseIndices.filter{i in
            (kind==nil || bank[i].type==kind) && {if case .difficulty(let d)=draw {return (bank[i].difficulty ?? 1)==d};return true}()
        }
    }
    /// The teacher corrects record `index` to right (the right answers) or wrong (nothing said); the report follows.
    /// Rewards already paid for it stay as they were.
    func setQuizRecord(at index:Int,right:Bool)throws {
        let log=quizLog
        guard log.indices.contains(index),quizBank.indices.contains(log[index].question) else{throw GameError("没有这条作答记录。")}
        let parts=quizBank[log[index].question].parts
        guard parts.count==log[index].correct.count else{throw GameError("这条记录和题目对不上。")}
        try engine.apply(.editQuizRecord(index:index,picks:right ? parts.map{$0.answer}:parts.map{_ in nil},correct:parts.map{_ in right}))
    }
    /// Takes out an answer recorded by mistake (the report no longer shows it; rewards already paid stay).
    func removeQuizRecord(at index:Int)throws {
        guard quizLog.indices.contains(index) else{throw GameError("没有这条作答记录。")}
        try engine.apply(.removeQuizRecord(index:index))
    }
    /// Questions of the course never answered yet (by the student; nil = by anyone), flash-card practice included.
    func unaskedQuestions(for player:String?)->Set<Int> {
        let asked=Set(quizLog.filter{player == nil || $0.player==player}.map(\.question))
        return Set(courseIndices.filter{!asked.contains($0)})
    }
    /// Questions still wrong: the student's last answer to it (nil = any student's last answer) was not all right.
    func mistakenQuestions(for player:String?)->Set<Int> {
        var last:[String:QuizAttempt]=[:]
        for a in quizLog where player == nil || a.player==player {last[a.player+"#\(a.question)"]=a}
        let course=Set(courseIndices)
        return Set(last.values.filter{$0.correct.isEmpty || !$0.correct.allSatisfy{$0}}.map(\.question)).intersection(course)
    }
    /// The next question, at random from the whole course or from one difficulty. Questions not asked yet and
    /// questions still wrong come first (for the student; nil = the class); then any of them. `excluding`: not these
    /// (the question on screen, for 换一题) unless nothing else is left.
    func drawQuestion<G:RandomNumberGenerator>(_ draw:QuizDraw,for player:String?,kind:QuizKind?=nil,excluding:Set<Int>=[],using random:inout G)->Int? {
        let pool=quizPool(draw,kind:kind)
        guard !pool.isEmpty else{return nil}
        let first=unaskedQuestions(for:player).union(mistakenQuestions(for:player))
        let fresh=pool.filter{first.contains($0) && !excluding.contains($0)}
        let any=pool.filter{!excluding.contains($0)}
        return (fresh.isEmpty ? (any.isEmpty ? pool:any):fresh).randomElement(using:&random)
    }
    func drawQuestion(_ draw:QuizDraw,for player:String?,kind:QuizKind?=nil,excluding:Set<Int>=[])->Int? {
        var g=SystemRandomNumberGenerator();return drawQuestion(draw,for:player,kind:kind,excluding:excluding,using:&g)
    }
    /// Every flash card of the current course, in bank order (the same deck for every student and the class).
    func practiceDeck(for player:String)->[Int] {classFlashDeck}
    var classFlashDeck:[Int] {let bank=quizBank;return courseIndices.filter{bank[$0].type == .flashcard}}
    /// Teammates at this quiz node who still have to answer.
    func quizWaiting(node:Int,team:String?)->[GameUnit] {
        let log=quizLog
        return engine.state.players.filter{u in u.isAlive && u.nodeID==node && u.teamID==team && !log.contains(where:{$0.player==u.id && $0.node==node})}
    }
    /// Records what the student said (the option per graded item, nil = did not know; `texts` for other answers)
    /// and pays the reward. Returns the stored attempt.
    /// Records what the student said (the option per graded item, nil = did not know; `texts` for other answers)
    /// and pays the reward. `free`: called up by the teacher anywhere, not at a quiz spot. Returns the stored attempt.
    /// `shared`: asked to the whole class; `practice`: flash-card practice.
    /// `participation`: coins for a wrong answer to a class question (the teacher's 参与奖).
    @discardableResult func recordQuiz(actor:String,question index:Int,picks:[Int?],texts:[String?]?=nil,seconds:Double,at:Date=Date(),free:Bool=false,participation:Int=0,shared:Bool=false,practice:Bool=false,challenge:Bool=false,skipped:Bool=false,id:String=UUID().uuidString)throws->QuizAttempt {
        if !free {guard canManageInventory,travel==nil else{throw GameError("请抵达地点、结束战斗后答题。")}}
        guard let unit=engine.state.units[actor],quizBank.indices.contains(index) else{throw GameError("没有这道题。")}
        let q=quizBank[index],parts=q.parts
        guard picks.count==parts.count else{throw GameError("答题记录与题目不符。")}
        let texts=texts ?? Array(repeating:nil,count:parts.count)
        let correct=parts.indices.map{picks[$0]==parts[$0].answer}
        var attempt=QuizAttempt(player:actor,playerName:unit.shortName,node:free ? -1:unit.nodeID,question:index,picks:picks,texts:texts,correct:correct,
                                seconds:min(600,max(0,seconds)),limit:challenge ? 600:q.timeLimit,at:at.timeIntervalSince1970)
        if shared {attempt.shared=true}
        if practice {attempt.practice=true}
        if skipped {attempt.skipped=true}
        // A fully right answer (in time, for a student's own timed question) pays by difficulty: coins, points and one
        // movement step for the student's team (once per question per team); otherwise only the class's
        // participation prize, if any.
        let timed = !(shared || practice || challenge || skipped)
        let right = !skipped && !correct.isEmpty && correct.allSatisfy{$0} && !(timed && attempt.overtime)
        let coins=right ? q.reward:max(0,participation)
        // One movement step per question per team: once a teammate has answered this question right, more right
        // answers from the same team still pay coins and points but no further step.
        let stepTaken=quizLog.contains{a in a.question==index && a.skipped != true && !a.correct.isEmpty && a.correct.allSatisfy{$0}
            && (engine.state.units[a.player]?.teamID ?? "party")==(unit.teamID ?? "party")}
        try applyQuizRecord(QuizRecord(attempt:attempt,fullCoins:q.reward,points:right ? q.points:0,dropTier:nil,free:free,manualCoins:coins,noSpeedBonus:true),steps:right && !stepTaken ? QuizRewards.steps:0,id:id)
        return quizLog.last!
    }
    /// The class answered (choice = option index) or skipped (nil, no reward). Returns whether it was right.
    @discardableResult func answerQuiz(actor:String,choice:Int?,id:String=UUID().uuidString)throws->Bool {
        guard let turn=quizTurn(actor:actor) else{throw GameError("这里没有题目。")}
        return try recordQuiz(actor:actor,question:turn.index,picks:[choice],seconds:0,id:id).correct.allSatisfy{$0}
    }
}
