import Coaching
import Contracts
import DesignSystem
import SwiftUI

/// "Trener": chat with the AI trainer. It knows the plan and the technique results, and, after the user agreed,
/// the health summaries. It does not diagnose. Owner: Maciek.
struct CoachView: View {
    /// Set when the coach is opened from a workout: where the user is and what the last set was.
    var workout: WorkoutContext?
    /// Asked once, right after the conversation loads (the "Przeprowadź mnie" buttons of a workout).
    var initialQuestion: String?
    /// Set when shown as a sheet over a workout: adds a close button.
    var onClose: (() -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var model: CoachViewModel?
    @State private var voice: VoiceChatController?
    @State private var confirmClear = false
    @State private var askedInitialQuestion = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            AmbientBackground()
            if let model {
                content(model)
            } else {
                ProgressView().tint(FormaColor.voltText)
            }
        }
        .task {
            if model == nil {
                let model = CoachViewModel.make(store: store)
                self.model = model
                voice = VoiceChatController(viewModel: model)
            }
            model?.workout = workout
            await model?.load()
            if let initialQuestion, !askedInitialQuestion {
                askedInitialQuestion = true
                model?.send(initialQuestion)
            }
        }
        .onDisappear { voice?.endSession() }
    }

    private func content(_ model: CoachViewModel) -> some View {
        VStack(spacing: 0) {
            header(model)
            if let workout { contextCard(workout) }
            conversation(model)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let voice, voice.isAvailable { VoiceMicRow(controller: voice) }
                CoachInputBar(model: model, focused: $inputFocused)
            }
            // In the Trener tab the floating tab bar sits right under the field: leave air between them.
            .padding(.bottom, onClose == nil ? FormaSpacing.l : 0)
        }
        .confirmationDialog("Wyczyścić rozmowę z trenerem?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Wyczyść rozmowę", role: .destructive) { Task { await model.clearConversation() } }
        } message: {
            Text("Rozmowa jest zapisana tylko na tym telefonie. Po wyczyszczeniu znika.")
        }
    }

    // MARK: header

    private func header(_ model: CoachViewModel) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: FormaSpacing.s) {
                Text(workout == nil ? "Twój doradca" : "W trakcie treningu").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                Text(workout == nil ? "Trener" : "Zapytaj trenera").formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
            }
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FormaColor.ink)
                        .frame(width: 44, height: 44)
                        .background(FormaColor.well, in: Circle())
                }
                .accessibilityLabel("Wróć do treningu")
            }
            Menu {
                if model.consent.granted {
                    Button("Wycofaj zgodę i wyczyść rozmowę", systemImage: "hand.raised") { model.setConsent(false) }
                } else {
                    Button("Zezwól na dane zdrowotne", systemImage: "heart.text.square") { model.setConsent(true) }
                }
                Button("Wyczyść rozmowę", systemImage: "trash", role: .destructive) { confirmClear = true }
                    .disabled(model.messages.isEmpty)
                if let voice, voice.isAvailable {
                    Toggle("Czytaj odpowiedzi", systemImage: "speaker.wave.2", isOn: Bindable(voice).readRepliesAloud)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(FormaColor.well, in: Circle())
                    .foregroundStyle(FormaColor.ink)
            }
            .accessibilityLabel("Opcje trenera")
        }
        .padding(.horizontal, FormaSpacing.screen)
        .padding(.top, FormaSpacing.l)
        .padding(.bottom, FormaSpacing.s)
    }

    /// Where the coach was opened from, and what it was told about that moment.
    private func contextCard(_ workout: WorkoutContext) -> some View {
        let summary = WorkoutContextSummary.make(
            for: workout,
            sessionTitle: workout.sessionId.flatMap { id in store.plan.sessions.first { $0.id == id }?.title },
            exerciseName: workout.exerciseId.flatMap { store.exercise(id: $0)?.name })
        return InfoBanner(systemImage: "scope") {
            VStack(alignment: .leading, spacing: FormaSpacing.xs) {
                Text(summary.title).formaStyle(.subheadline).foregroundStyle(FormaColor.ink)
                ForEach(summary.lines, id: \.self) { line in
                    Text(line).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                }
            }
        }
        .padding(.horizontal, FormaSpacing.screen)
        .padding(.bottom, FormaSpacing.s)
        .accessibilityElement(children: .combine)
    }

    // MARK: conversation

    private func conversation(_ model: CoachViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // A plain VStack: the lazy one estimates the height of long answers, and scrolling to "bottom" then
                // landed past the content (a blank screen). The history is capped, so building it all is cheap.
                VStack(alignment: .leading, spacing: FormaSpacing.m) {
                    consentArea(model)
                    if model.messages.isEmpty, !model.isResponding {
                        CoachEmptyState(questions: CoachChat.quickQuestions(for: model.workout)) { model.send($0) }
                    }
                    ForEach(model.messages) { message in
                        CoachBubble(message: message)
                        if message.suggestsConsultation { ConsultationCard() }
                        ForEach(message.proposals) { proposal in
                            PlanProposalCard(proposal: proposal, error: model.proposalErrors[proposal.id],
                                             onApply: { model.applyProposal(proposal.id) },
                                             onDismiss: { model.dismissProposal(proposal.id) },
                                             onUndo: { model.undoProposal(proposal.id) },
                                             onShowPlan: { if let onClose { onClose() } else { router.tab = .plan } })
                        }
                    }
                    if model.isResponding {
                        CoachWritingBubble(text: model.streamingText, checking: model.checking)
                    }
                    if let error = model.error {
                        CoachErrorCard(error: error, onRetry: { model.retry() }, onEnableConsent: { model.setConsent(true) })
                    }
                    Text("To nie jest porada medyczna. Trener nie diagnozuje i nie zastępuje lekarza. Przy bólu lub niepokojących objawach skontaktuj się ze specjalistą.")
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                        .padding(.top, FormaSpacing.s)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.bottom, FormaSpacing.l)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Messages fade out above the field (the field itself has no background of its own).
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.95),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            // Opens at the newest message; an empty conversation starts at the top (the starter questions).
            .defaultScrollAnchor(model.messages.isEmpty ? .top : .bottom)
            .onAppear { scrollToEndSoon(proxy) }
            .onChange(of: model.messages.count) { old, _ in
                // The saved conversation arriving is not a new message: jump, do not scroll through it.
                if old == 0 { scrollToEndSoon(proxy) } else { scrollToEnd(proxy) }
            }
            .onChange(of: model.streamingText) { scrollToEnd(proxy, animated: false) }
            .onChange(of: model.isResponding) { scrollToEnd(proxy) }
            .onChange(of: model.error) { scrollToEnd(proxy) }
            .onChange(of: inputFocused) { scrollToEnd(proxy) }
        }
    }

    @ViewBuilder
    private func consentArea(_ model: CoachViewModel) -> some View {
        if !model.consent.granted, model.consent.date == nil {
            CoachConsentCard(onAllow: { model.setConsent(true) }, onDecline: { model.setConsent(false) })
        } else if !model.consent.granted {
            InfoBanner(systemImage: "hand.raised.fill") {
                VStack(alignment: .leading, spacing: FormaSpacing.xs) {
                    Text("Trener odpowiada bez danych zdrowotnych")
                        .formaStyle(.subheadline).foregroundStyle(FormaColor.ink)
                    Button("Zezwól na dane zdrowotne") { model.setConsent(true) }
                        .formaStyle(.footnote).foregroundStyle(FormaColor.voltText)
                }
            }
        }
    }

    /// After the layout of what just appeared, so the jump lands on the real end of a long conversation.
    private func scrollToEndSoon(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
