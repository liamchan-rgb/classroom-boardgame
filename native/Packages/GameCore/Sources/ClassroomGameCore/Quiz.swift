import Foundation

/// One multiple-choice question for a quiz event on the map (a teacher-imported question bank).
public struct QuizQuestion: Codable, Equatable {
    public var prompt: String
    public var options: [String]
    /// Index of the correct option (0 = A).
    public var answer: Int
    /// Coins for a correct answer (default 10).
    public var coins: Int?
    public var explanation: String?
    public init(prompt: String, options: [String], answer: Int, coins: Int? = nil, explanation: String? = nil) {
        self.prompt = prompt; self.options = options; self.answer = answer; self.coins = coins; self.explanation = explanation
    }
    public static let defaultCoins = 10
    public var reward: Int { coins ?? Self.defaultCoins }
    public func validate() throws {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 600,
              (2...6).contains(options.count), options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }),
              options.indices.contains(answer), (0...200).contains(reward), (explanation?.count ?? 0) <= 600 else {
            throw GameError("题目格式无效：「\(prompt.prefix(20))」")
        }
    }
}

extension Evaluation {
    /// A quiz event (it takes the place of the roadside find): marks the event done and pays the class's reward for a
    /// right answer. The campaign layer checks the chosen option against its question bank.
    mutating func answerCampaignQuiz(actor id: String, correct: Bool, coins: Int) throws {
        var (actor, index, kind) = try siteActor(id)
        guard kind == .satchel, state.map.nodes[index].siteResolved != true else { throw GameError("该事件已结束。") }
        guard (0...200).contains(coins), correct || coins == 0 else { throw GameError("答题奖励无效。") }
        if correct, coins > 0 { actor.coins = try checkedAdd(actor.coins, coins) }
        if correct { actor.score = try checkedAdd(actor.score, 1) }
        state.units[id] = actor; state.map.nodes[index].siteResolved = true
        events.append(GameEvent("campaignQuiz", actor: id, amount: coins, detail: "\(actor.nodeID):\(correct ? "correct" : "wrong")"))
    }
}
