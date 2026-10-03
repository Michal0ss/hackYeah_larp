import API
import Contracts
import Foundation

/// The backend, as far as the coach needs it. `FormaAPI` is the real one; tests use a fake.
public protocol CoachBackend: Sendable {
    func chatStream(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error>
}

extension FormaAPI: CoachBackend {}

/// A finished answer of the coach.
public struct CoachReply: Equatable, Sendable {
    public var text: String
    /// Names of the data the coach used, e.g. "plan treningowy", "sen z 7 dni".
    public var sources: [String]
    /// True when any data used was sample data.
    public var isSimulated: Bool
    /// True when the model hit its length limit, so the answer may end abruptly.
    public var isTruncated: Bool
    /// Changes of the plan the coach proposed while answering. Nothing is changed until the user accepts one.
    public var proposals: [PlanChangeProposal] = []
    /// The question mentioned pain or an injury: show the "Warto rozważyć konsultację" card under the answer.
    public var suggestsConsultation: Bool = false
}

public enum CoachEvent: Equatable, Sendable {
    /// A piece of the answer, to append to what is on screen.
    case delta(String)
    /// The coach is reading one of the user's data sets (shown as "Sprawdzam plan…").
    case checking(String)
    case finished(CoachReply)
}

public enum CoachChatError: Error, Equatable, Sendable {
    /// The request failed: no network, rate limit, model unavailable, ...
    case api(APIError)
    /// The model failed after the answer had started. `partial` is what arrived.
    case interrupted(ServerError, partial: String)
    /// The model asked for tools more times than allowed.
    case tooManyToolRounds
    /// The model finished without any text.
    case emptyAnswer

    /// Polish text for the user.
    public var userMessage: String {
        switch self {
        case .api(let error): return error.userMessage
        case .interrupted(let error, _): return error.message
        case .tooManyToolRounds: return "Trener nie zdążył odpowiedzieć. Spróbuj zadać pytanie jeszcze raz."
        case .emptyAnswer: return "Trener nie odpowiedział. Spróbuj jeszcze raz."
        }
    }

    /// True when asking again can work.
    public var isRetryable: Bool {
        switch self {
        case .api(let error): return error.isRetryable
        default: return true
        }
    }

    public var isConsentProblem: Bool {
        if case .api(let error) = self { return error.code == "consent_required" }
        return false
    }
}

/// The conversation with the AI trainer: sends the history to the backend, runs the tools the model asks for on
/// the phone, and streams the answer.
///
///     user text ──► backend ──► model ──► text deltas ──► screen
///                                  │
///                                  └─ tool_use ──► CoachTools (local data) ──► tool_result ──► backend again
///
/// The server is stateless, so every request carries the whole conversation. Tool exchanges live only inside one
/// answer: between answers only the plain text is kept, so health data from an old tool call never travels again
/// (and never outlives a withdrawn consent).
public struct CoachChat: Sendable {
    /// Added to the sources of an answer that used sample data; the screen shows it as the "Dane przykładowe" badge.
    public static let simulatedSourceLabel = "Dane przykładowe"

    /// Questions offered in an empty conversation.
    public static let starterQuestions = [
        "Czy dziś ćwiczyć nogi?",
        "Czym zastąpić przysiad?",
        "Jak poprawić technikę?",
    ]

    /// More proposals than this in one answer would be a wall of cards; the coach is told to wait for the user.
    static let maxProposalsPerAnswer = 2

    /// The server accepts at most 40 messages, 4000 characters per text block and 40000 characters in total.
    static let maxHistoryMessages = 20
    static let maxTextCharacters = 3500
    static let maxHistoryCharacters = 24_000

    private let backend: CoachBackend
    private let tools: CoachToolRunning
    private let profile: @Sendable () async -> UserProfile
    private let recommendation: RecommendationProviding
    private let snapshot: CoachSnapshotProviding?
    private let hasHealthConsent: @Sendable () -> Bool
    private let maxToolRounds: Int

    /// `snapshot` tells the coach about the plan and the last technique result in every request; without it the
    /// coach has to ask for them through the tools.
    public init(backend: CoachBackend, tools: CoachToolRunning, profile: @escaping @Sendable () async -> UserProfile,
                recommendation: RecommendationProviding, snapshot: CoachSnapshotProviding? = nil,
                hasHealthConsent: @escaping @Sendable () -> Bool, maxToolRounds: Int = 4) {
        self.backend = backend
        self.tools = tools
        self.profile = profile
        self.recommendation = recommendation
        self.snapshot = snapshot
        self.hasHealthConsent = hasHealthConsent
        self.maxToolRounds = maxToolRounds
    }

    /// Answers `text` in the context of `history` (the earlier messages of this conversation, oldest first).
    /// `workout` says where in the workout the question was asked (nil: in the Trener tab, not in a workout).
    /// The stream ends with `.finished` or fails with a `CoachChatError`.
    public func reply(to text: String, history: [ChatMessage],
                      workout: WorkoutContext? = nil) -> AsyncThrowingStream<CoachEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(text: text, history: history, workout: workout, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: the loop

    private func run(text: String, history: [ChatMessage], workout: WorkoutContext?,
                     continuation: AsyncThrowingStream<CoachEvent, Error>.Continuation) async throws {
        var messages = Self.wireHistory(from: history)
        if let last = messages.last, last.role == .user {
            // The previous question never got an answer (it failed): ask both together, the server wants alternation.
            messages[messages.count - 1] = .user(Self.clip(Self.plainText(of: last) + "\n" + text))
        } else {
            messages.append(.user(Self.clip(text)))
        }
        let painMentioned = PainSignal.mentions(text)
        var answer = ""
        // The last set travels with the request, so the answer rests on it: say so under the answer.
        var sources: [String] = workout?.lastSet == nil ? [] : ["ostatnia seria"]
        var simulated = false
        var proposals: [PlanChangeProposal] = []

        for round in 0...maxToolRounds {
            try Task.checkCancellation()
            let consent = hasHealthConsent()
            let today = consent ? await recommendation.todayRecommendation() : nil
            let training = await snapshot?.snapshot(healthConsent: consent)
            // The recommendation and the snapshot travel with the request, so the answer may rest on them: mark
            // sample data as such.
            simulated = simulated || (today?.isSimulated ?? false) || (training?.containsSampleData ?? false)
            let request = ChatRequest(messages: messages,
                                      context: ChatContext(profile: await profile(), todayRecommendation: today,
                                                           snapshot: training, workout: workout),
                                      healthConsent: consent)

            var roundText = ""
            var calls: [API.ToolCall] = []
            var stopReason: String?
            do {
                for try await event in backend.chatStream(request) {
                    switch event {
                    case .delta(let piece):
                        // A new paragraph between the text before a tool call and the answer after it.
                        if roundText.isEmpty, !answer.isEmpty {
                            answer += "\n\n"
                            continuation.yield(.delta("\n\n"))
                        }
                        roundText += piece
                        answer += piece
                        continuation.yield(.delta(piece))
                    case .toolUse(let call):
                        calls.append(call)
                    case .done(let reason, _):
                        stopReason = reason
                    case .error(let serverError):
                        throw CoachChatError.interrupted(serverError, partial: answer)
                    }
                }
            } catch let error as APIError {
                throw CoachChatError.api(error)
            }

            if calls.isEmpty {
                let final = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { throw CoachChatError.emptyAnswer }
                continuation.yield(.finished(CoachReply(text: final, sources: sources, isSimulated: simulated,
                                                        isTruncated: stopReason == "max_tokens", proposals: proposals,
                                                        suggestsConsultation: painMentioned)))
                return
            }
            guard round < maxToolRounds else { throw CoachChatError.tooManyToolRounds }

            // Run what the model asked for, on the phone, and post again with the results.
            var assistant: [ChatBlock] = roundText.isEmpty ? [] : [.text(roundText)]
            var results: [ChatBlock] = []
            for call in calls {
                try Task.checkCancellation()
                assistant.append(.toolUse(id: call.id, name: call.name, input: call.input))
                var output = await tools.run(name: call.name, input: call.input)
                if let proposal = output.proposal {
                    if proposals.count < Self.maxProposalsPerAnswer {
                        proposals.append(proposal)
                    } else {
                        output = CoachToolOutput(content: "{\"error\":\"Za dużo propozycji naraz. Poczekaj na decyzję użytkownika.\"}",
                                                 isError: true)
                    }
                }
                if let label = output.sourceLabel {
                    if !sources.contains(label) { sources.append(label) }
                    continuation.yield(.checking(label))
                }
                simulated = simulated || output.isSimulated
                results.append(.toolResult(toolUseId: call.id, content: output.content, isError: output.isError))
            }
            messages.append(WireMessage(role: .assistant, blocks: assistant))
            messages.append(WireMessage(role: .user, blocks: results))
        }
    }

    // MARK: history

    /// Plain text messages, oldest first, shaped the way the server accepts them: starts with the user, no empty
    /// texts, neighbours with the same role merged, within the length limits (the newest messages win).
    static func wireHistory(from history: [ChatMessage]) -> [WireMessage] {
        var kept: [(WireRole, String)] = []
        for message in history.suffix(maxHistoryMessages) {
            let text = clip(message.text)
            guard !text.isEmpty else { continue }
            let role: WireRole = message.role == .user ? .user : .assistant
            if let last = kept.last, last.0 == role {
                kept[kept.count - 1].1 = clip(last.1 + "\n" + text)
            } else {
                kept.append((role, text))
            }
        }
        // Drop the oldest until the total fits.
        while kept.reduce(0, { $0 + $1.1.count }) > maxHistoryCharacters, !kept.isEmpty { kept.removeFirst() }
        // The conversation must start with the user.
        while let first = kept.first, first.0 != .user { kept.removeFirst() }
        return kept.map { WireMessage(role: $0.0, blocks: [.text($0.1)]) }
    }

    private static func plainText(of message: WireMessage) -> String {
        message.blocks.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined(separator: "\n")
    }

    static func clip(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > maxTextCharacters ? String(trimmed.prefix(maxTextCharacters)) : trimmed
    }
}
