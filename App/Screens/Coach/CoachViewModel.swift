import Coaching
import Contracts
import Observation
import Insights
import SwiftUI

/// State of the coach screen: the conversation, the answer being written, errors and the data consent.
/// The conversation logic itself lives in `Coaching.CoachChat` (tested without UI).
@MainActor
@Observable
final class CoachViewModel {
    private(set) var messages: [ChatMessage] = []
    /// The answer as it arrives.
    private(set) var streamingText = ""
    /// What the coach is reading right now, e.g. "plan treningowy".
    private(set) var checking: String?
    private(set) var isResponding = false
    private(set) var error: CoachChatError?
    private(set) var consent: DataConsent
    var draft = ""

    private let chat: CoachChat
    private let history: CoachHistoryStore
    private let consentStore: ConsentStore
    private var task: Task<Void, Never>?
    /// Bumped when the conversation is cleared, so an answer still in flight cannot reappear afterwards.
    private var generation = 0
    /// The question that failed, so "Spróbuj ponownie" asks it again without adding it twice.
    private var failed: (text: String, history: [ChatMessage])?

    static let maxQuestionLength = 1000

    /// Runs after consent is withdrawn, besides clearing the conversation (e.g. drops cached model texts).
    private let onConsentWithdrawn: (@Sendable () async -> Void)?

    init(chat: CoachChat, history: CoachHistoryStore, consentStore: ConsentStore,
         onConsentWithdrawn: (@Sendable () async -> Void)? = nil) {
        self.onConsentWithdrawn = onConsentWithdrawn
        self.chat = chat
        self.history = history
        self.consentStore = consentStore
        consent = consentStore.current
    }

    /// Builds the coach on the real services of the app.
    static func make(store: AppStore) -> CoachViewModel {
        let services = store.services
        let recommendation = StoreRecommendationProvider(store: store)
        let tools = CoachTools(plan: StorePlanProvider(store: store), catalog: services.catalog, recovery: services.recovery,
                               checkIns: services.checkIns, technique: services.technique, recommendation: recommendation,
                               hasHealthConsent: { [consent = services.consent] in consent.isGranted })
        let chat = CoachChat(backend: services.api, tools: tools,
                             profile: { await MainActor.run { store.profile } },
                             recommendation: recommendation,
                             hasHealthConsent: { [consent = services.consent] in consent.isGranted })
        let texter = services.recommendationText
        return CoachViewModel(chat: chat, history: services.coachHistory, consentStore: services.consent,
                              onConsentWithdrawn: { await (texter as? RecommendationTexter)?.clearCache() })
    }

    // MARK: lifecycle

    func load() async {
        consent = consentStore.current
        messages = await history.all()
    }

    // MARK: asking

    func send(_ text: String) {
        let question = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxQuestionLength))
        guard !question.isEmpty, !isResponding else { return }
        let before = messages
        let message = ChatMessage(role: .user, text: question)
        messages.append(message)
        draft = ""
        Task { await history.append([message]) }
        ask(question, history: before)
    }

    func retry() {
        guard let failed, !isResponding else { return }
        ask(failed.text, history: failed.history)
    }

    /// Stops an answer in progress. What already arrived stays on screen.
    func stop() {
        task?.cancel()
    }

    private func ask(_ question: String, history before: [ChatMessage]) {
        isResponding = true
        error = nil
        failed = nil
        streamingText = ""
        checking = nil
        let current = generation
        task = Task { [chat] in
            do {
                for try await event in chat.reply(to: question, history: before) {
                    switch event {
                    case .delta(let piece):
                        checking = nil
                        streamingText += piece
                    case .checking(let label):
                        checking = label
                    case .finished(let reply):
                        if current == generation { await finish(reply) }
                    }
                }
                if Task.isCancelled, current == generation { await keepPartialAnswer() }
            } catch let failure as CoachChatError {
                if current == generation { fail(failure, question: question, history: before) }
            } catch {
                if current == generation { fail(.api(.transport(error.localizedDescription)), question: question, history: before) }
            }
            guard current == generation else { return }
            isResponding = false
            checking = nil
            streamingText = ""
        }
    }

    private func finish(_ reply: CoachReply) async {
        var sources = reply.sources
        if reply.isSimulated { sources.append(CoachChat.simulatedSourceLabel) }
        let answer = ChatMessage(role: .coach, text: reply.text, sources: sources)
        messages.append(answer)
        await history.append([answer])
    }

    /// The user pressed stop: keep what was written.
    private func keepPartialAnswer() async {
        let partial = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }
        let answer = ChatMessage(role: .coach, text: partial)
        messages.append(answer)
        await history.append([answer])
    }

    private func fail(_ failure: CoachChatError, question: String, history before: [ChatMessage]) {
        error = failure
        failed = (question, before)
    }

    // MARK: consent and housekeeping

    /// Withdrawing consent also clears the conversation: earlier answers may quote health summaries, and the whole
    /// history is sent to the model with every question, so keeping them would pass that data on without consent.
    func setConsent(_ granted: Bool) {
        let wasGranted = consent.granted
        consentStore.setGranted(granted)
        consent = consentStore.current
        if wasGranted, !granted {
            Task {
                await clearConversation()
                await onConsentWithdrawn?()
            }
        }
    }

    func clearConversation() async {
        generation += 1
        task?.cancel()
        await history.clear()
        messages = []
        error = nil
        failed = nil
        streamingText = ""
        isResponding = false
    }
}
