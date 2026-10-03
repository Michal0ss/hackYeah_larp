import Coaching
import Contracts
import DesignSystem
import SwiftUI

/// "Trener": chat with the AI trainer. It knows the plan and the technique results, and, after the user agreed,
/// the health summaries. It does not diagnose. Owner: Maciek.
struct CoachView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var model: CoachViewModel?
    @State private var confirmClear = false
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
            if model == nil { model = CoachViewModel.make(store: store) }
            await model?.load()
        }
    }

    private func content(_ model: CoachViewModel) -> some View {
        VStack(spacing: 0) {
            header(model)
            conversation(model)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CoachInputBar(model: model, focused: $inputFocused)
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
                Text("Twój doradca").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                Text("Trener").formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
            }
            Spacer()
            Menu {
                if model.consent.granted {
                    Button("Wycofaj zgodę i wyczyść rozmowę", systemImage: "hand.raised") { model.setConsent(false) }
                } else {
                    Button("Zezwól na dane zdrowotne", systemImage: "heart.text.square") { model.setConsent(true) }
                }
                Button("Wyczyść rozmowę", systemImage: "trash", role: .destructive) { confirmClear = true }
                    .disabled(model.messages.isEmpty)
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

    // MARK: conversation

    private func conversation(_ model: CoachViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FormaSpacing.m) {
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
                                             onShowPlan: { router.tab = .plan })
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
            .onChange(of: model.messages.count) { scrollToEnd(proxy) }
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

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
