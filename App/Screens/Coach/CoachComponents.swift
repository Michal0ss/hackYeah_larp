import Coaching
import Contracts
import DesignSystem
import SwiftUI

// Pieces of the coach screen. Look: only DesignSystem tokens and components.

/// Asked once, before the first conversation: may health summaries go to the model?
struct CoachConsentCard: View {
    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(spacing: FormaSpacing.s) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FormaColor.voltText)
                    .accessibilityHidden(true)
                Text("Trener i Twoje dane").formaStyle(.title2).foregroundStyle(FormaColor.ink)
            }
            Text("Trener AI może uwzględniać podsumowania snu, tętna spoczynkowego, HRV, check-inów i rekomendację dnia. Dzięki temu odpowie, czy dziś ćwiczyć i jak lżej.")
                .formaStyle(.callout).foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: FormaSpacing.s) {
                point("Wysyłamy tylko podsumowania (np. średni sen z 7 dni) i Twoje wiadomości do usługi AI (Google Gemini), przez nasz serwer.")
                point("Nigdy nie wysyłamy filmów, zdjęć, surowych danych z Apple Health ani notatek z check-inów.")
                point("Bez względu na zgodę trener zna Twój profil treningowy (cel, poziom, sprzęt, to, czego unikasz), plan i wyniki techniki.")
                point("Zgodę możesz cofnąć w każdej chwili w menu u góry ekranu.")
            }
            Button(action: onAllow) {
                Text("Zezwalam na dane zdrowotne").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
            Button(action: onDecline) {
                Text("Nie teraz").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
        }
        .padding(FormaSpacing.l)
        .glassCard()
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: FormaSpacing.s) {
            Circle().fill(FormaColor.voltText).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
            Text(text).formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Empty conversation: what the coach can do, and questions to start with.
struct CoachEmptyState: View {
    let onAsk: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            Text("Zapytaj o plan, ćwiczenia, zamienniki albo o to, czy dziś trenować. Trener zna Twój plan i wyniki techniki.")
                .formaStyle(.callout).foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(CoachChat.starterQuestions, id: \.self) { question in
                Button { onAsk(question) } label: {
                    HStack {
                        Text(question).formaStyle(.body).foregroundStyle(FormaColor.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(FormaColor.voltText).accessibilityHidden(true)
                    }
                    .padding(.horizontal, FormaSpacing.l)
                    .padding(.vertical, FormaSpacing.m)
                    .glassCard(radius: 22)
                }
                .buttonStyle(.formaPress)
            }
        }
        .padding(.top, FormaSpacing.s)
    }
}

/// One message. The user's on the right, the coach's on the left with the data it used under the text.
struct CoachBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }
    private var simulated: Bool { message.sources.contains(CoachChat.simulatedSourceLabel) }
    private var sources: [String] { message.sources.filter { $0 != CoachChat.simulatedSourceLabel } }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: FormaSpacing.xs) {
            Text(verbatim: message.text)
                .formaStyle(.body)
                .foregroundStyle(isUser ? FormaColor.onVolt : FormaColor.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, FormaSpacing.l)
                .padding(.vertical, FormaSpacing.m)
                .background { bubbleBackground }
            if !isUser, !sources.isEmpty || simulated {
                VStack(alignment: .leading, spacing: FormaSpacing.xs) {
                    if !sources.isEmpty {
                        Text("Na podstawie: " + sources.joined(separator: " · "))
                            .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                    }
                    if simulated { SimulatedBadge() }
                }
                .padding(.horizontal, FormaSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.leading, isUser ? 40 : 0)
        .padding(.trailing, isUser ? 0 : 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((isUser ? "Ty: " : "Trener: ") + message.text)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FormaColor.volt)
        } else {
            Color.clear.glassCard(radius: 22)
        }
    }
}

/// The answer being written: dots until the first words, then the text as it arrives.
struct CoachWritingBubble: View {
    let text: String
    let checking: String?

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.xs) {
            if text.isEmpty {
                HStack(spacing: FormaSpacing.s) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(FormaColor.voltText)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                        .accessibilityHidden(true)
                    if let checking {
                        Text("Sprawdzam: \(checking)").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                    }
                }
                .padding(.horizontal, FormaSpacing.l)
                .padding(.vertical, FormaSpacing.m)
                .glassCard(radius: 22)
            } else {
                Text(verbatim: text)
                    .formaStyle(.body).foregroundStyle(FormaColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, FormaSpacing.l)
                    .padding(.vertical, FormaSpacing.m)
                    .glassCard(radius: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
        .accessibilityLabel(text.isEmpty ? "Trener pisze" : "Trener pisze: " + text)
    }
}

/// A failed question: what happened, and a way to ask again.
struct CoachErrorCard: View {
    let error: CoachChatError
    let onRetry: () -> Void
    let onEnableConsent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(alignment: .top, spacing: FormaSpacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(FormaColor.moderateText)
                    .accessibilityHidden(true)
                Text(error.userMessage).formaStyle(.subheadline).foregroundStyle(FormaColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if error.isRetryable {
                Button(action: onRetry) {
                    Label("Spróbuj ponownie", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            } else if error.isConsentProblem {
                Button(action: onEnableConsent) {
                    Text("Zezwól na dane zdrowotne").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            }
        }
        .padding(FormaSpacing.l)
        .glassCard(radius: 22)
    }
}

/// Text field with a send button; while the coach answers the button stops the answer.
struct CoachInputBar: View {
    @Bindable var model: CoachViewModel
    var focused: FocusState<Bool>.Binding

    private var canSend: Bool { !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: FormaSpacing.s) {
            TextField("Napisz do trenera", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .focused(focused)
                .formaStyle(.body)
                .foregroundStyle(FormaColor.ink)
                .submitLabel(.send)
                .onSubmit { model.send(model.draft) }
                .padding(.horizontal, FormaSpacing.l)
                .padding(.vertical, FormaSpacing.m)
                .glassCard(radius: 24)
            Button {
                if model.isResponding { model.stop() } else { model.send(model.draft) }
            } label: {
                Image(systemName: model.isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(FormaColor.onVolt)
                    .frame(width: 48, height: 48)
                    .background(FormaColor.volt.opacity(model.isResponding || canSend ? 1 : 0.4), in: Circle())
            }
            .buttonStyle(.formaPress)
            .disabled(!model.isResponding && !canSend)
            .accessibilityLabel(model.isResponding ? "Zatrzymaj odpowiedź" : "Wyślij")
        }
        .padding(.horizontal, FormaSpacing.screen)
        .padding(.top, FormaSpacing.l)
        .padding(.bottom, FormaSpacing.s)
        // Messages fade out behind the field instead of showing through it.
        .background {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: FormaColor.background.opacity(0.94), location: 0.4)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}
