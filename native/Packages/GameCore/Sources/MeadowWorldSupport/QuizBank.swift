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
    public static func parse(_ data:Data)throws->[QuizQuestion] {
        guard data.count<=2*1024*1024 else{throw GameError("题库文件超过2 MB。")}
        var text=String(decoding:data,as:UTF8.self)
        if text.hasPrefix("\u{FEFF}"){text.removeFirst()}
        let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
        let questions=trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ? try json(Data(trimmed.utf8)):try plain(trimmed)
        guard !questions.isEmpty else{throw GameError("没有读到题目，请对照题库格式说明。")}
        guard questions.count<=500 else{throw GameError("题库最多500题。")}
        for q in questions{try q.validate()}
        return questions
    }
    private struct JSONQuestion:Decodable {
        let prompt:String;let options:[String];let answer:Answer;let coins:Int?;let explanation:String?
        enum Answer:Decodable {
            case index(Int),letter(String)
            init(from decoder:Decoder)throws {
                let c=try decoder.singleValueContainer()
                if let i=try? c.decode(Int.self){self = .index(i)} else {self = .letter(try c.decode(String.self))}
            }
        }
    }
    private struct JSONBank:Decodable {let questions:[JSONQuestion]}
    private static func json(_ data:Data)throws->[QuizQuestion] {
        let list:[JSONQuestion]
        do {
            if let bank=try? JSONDecoder().decode(JSONBank.self,from:data){list=bank.questions}
            else {list=try JSONDecoder().decode([JSONQuestion].self,from:data)}
        } catch {throw GameError("JSON 题库格式不对：需要 prompt、options、answer 字段。")}
        return try list.map{q in
            let answer:Int
            switch q.answer {
            case .index(let i):answer=i
            case .letter(let l):guard let i=letterIndex(l) else{throw GameError("答案应为 A–F：「\(q.prompt.prefix(20))」")};answer=i
            }
            return QuizQuestion(prompt:q.prompt,options:q.options,answer:answer,coins:q.coins,explanation:q.explanation)
        }
    }
    static func letterIndex(_ raw:String)->Int? {
        let s=raw.trimmingCharacters(in:.whitespaces).uppercased()
        let map:[String:Int]=["A":0,"B":1,"C":2,"D":3,"E":4,"F":5,"Ａ":0,"Ｂ":1,"Ｃ":2,"Ｄ":3,"Ｅ":4,"Ｆ":5]
        return s.first.flatMap{map[String($0)]}
    }
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
    private static func question(_ block:[String],number:Int)throws->QuizQuestion {
        var prompt=[String](),options=[(Int,String)](),answer:Int?,coins:Int?,explanation:String?
        for line in block {
            if let v=value(line,keys:["答案","正确答案","Answer","answer"]) {answer=letterIndex(v)}
            else if let v=value(line,keys:["金币","奖励","Coins","coins"]) {coins=Int(v.filter(\.isNumber))}
            else if let v=value(line,keys:["解析","说明","Explanation","explanation"]) {explanation=v}
            else if options.isEmpty,let v=value(line,keys:["题目","问题","Q","q"]) {prompt.append(v)}
            else if let o=option(line) {options.append(o)}
            else if options.isEmpty {prompt.append(line)}
            else {throw GameError("第\(number)题：无法识别「\(line.prefix(20))」")}
        }
        var first=prompt.joined(separator:"\n")
        // Leading numbering such as "1." / "1、" / "第1题" is not part of the question.
        if let r=first.range(of:#"^(第?\d+题?[\.．、:：)）]?\s*)"#,options:.regularExpression) {first.removeSubrange(r)}
        guard !first.isEmpty else{throw GameError("第\(number)题：缺少题目。")}
        guard options.count>=2,options.enumerated().allSatisfy({$0.offset==$0.element.0}) else{throw GameError("第\(number)题：选项需从 A 开始依次排列，至少两项。")}
        guard let answer,answer<options.count else{throw GameError("第\(number)题：缺少「答案：」或答案超出选项。")}
        return QuizQuestion(prompt:first,options:options.map(\.1),answer:answer,coins:coins,explanation:explanation)
    }
}

public extension MeadowCampaignSession {
    var quizBank:[QuizQuestion] {snapshot.quizBank ?? []}
    /// The question of a quiz event at this node: roadside-find events become quizzes when a bank was imported.
    /// Each quiz node takes the next question in order (starting from a place set by the map seed).
    func quizQuestion(node:Int)->QuizQuestion? {
        let bank=quizBank
        guard !bank.isEmpty,siteKind(node:node) == .satchel else{return nil}
        let quizNodes=engine.state.map.nodes.filter{$0.kind == .empty && siteKind(node:$0.id) == .satchel}.map(\.id).sorted()
        guard let position=quizNodes.firstIndex(of:node) else{return nil}
        let start=Int(engine.state.map.seed % UInt64(bank.count))
        return bank[(start+position)%bank.count]
    }
    /// The class answered (choice = option index) or skipped (nil, no reward). Returns whether it was right.
    @discardableResult func answerQuiz(actor:String,choice:Int?,id:String=UUID().uuidString)throws->Bool {
        guard canManageInventory,travel==nil else{throw GameError("请抵达地点、结束战斗后答题。")}
        guard let unit=engine.state.units[actor],let q=quizQuestion(node:unit.nodeID) else{throw GameError("这里没有题目。")}
        let correct=choice==q.answer
        try engine.apply(.answerCampaignQuiz(actor:actor,correct:correct,coins:correct ? q.reward:0),id:id)
        return correct
    }
}
