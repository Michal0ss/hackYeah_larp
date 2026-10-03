import DesignSystem
import SwiftUI

/// The voice row above the text input: a mic button that starts at rest, shows the recognized
/// words while listening, and shows "Trener mówi…" (tap to interrupt) while the reply is read
/// aloud. Hidden entirely by the caller when `controller.isAvailable` is false.
struct VoiceMicRow: View {
    @Bindable var controller: VoiceChatController

    var body: some View {
        HStack(spacing: FormaSpacing.s) {
            label
            Spacer()
            micButton
        }
        .padding(.horizontal, FormaSpacing.screen)
        .padding(.top, FormaSpacing.xs)
    }

    @ViewBuilder
    private var label: some View {
        switch controller.state {
        case .listening(let partial):
            Text(partial.isEmpty ? "Słucham…" : partial)
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .lineLimit(1)
        case .speaking:
            Text("Trener mówi…")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
        case .idle, .unavailable:
            EmptyView()
        }
    }

    private var micButton: some View {
        Button {
            controller.tapMic()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? FormaColor.onVolt : FormaColor.ink)
                .frame(width: 32, height: 32)
                .background(isActive ? FormaColor.volt : FormaColor.well, in: Circle())
        }
        .buttonStyle(.formaPress)
        .accessibilityLabel(accessibilityLabel)
    }

    private var icon: String {
        switch controller.state {
        case .idle, .unavailable: return "mic"
        case .listening: return "mic.fill"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    private var isActive: Bool {
        switch controller.state {
        case .idle, .unavailable: return false
        case .listening, .speaking: return true
        }
    }

    private var accessibilityLabel: String {
        switch controller.state {
        case .idle, .unavailable: return "Zapytaj głosem"
        case .listening: return "Zakończ słuchanie i wyślij"
        case .speaking: return "Przerwij odpowiedź"
        }
    }
}
