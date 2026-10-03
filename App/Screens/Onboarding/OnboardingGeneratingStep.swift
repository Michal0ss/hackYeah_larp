import SwiftUI
import Contracts
import DesignSystem
import Onboarding

/// Last step: the plan is being built.
struct GeneratingStepView: View {
    @Bindable var model: OnboardingModel

    private var isDone: Bool { model.generation == .done }
    private var failureMessage: String? {
        if case .failed(let message) = model.generation { return message }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                ProgressRing(progress: model.progress, lineWidth: 10) {
                    NumberText("\(Int((model.progress * 100).rounded()))", size: 46, unit: "%", color: FormaColor.voltText)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int((model.progress * 100).rounded()))
                }
                .frame(width: 150, height: 150)
                .padding(.top, 4)

                Text(titleText)
                    .formaStyle(.title2)
                    .foregroundStyle(FormaColor.ink)
                    .accessibilityAddTraits(.isHeader)

                Text(failureMessage ?? model.generationSummary)
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
                    .fixedSize(horizontal: false, vertical: true)

                if failureMessage == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.generationStages) { stage in
                            stageRow(stage)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .glassCard()
            .accessibilityElement(children: .contain)
            .accessibilityValue("\(Int((model.progress * 100).rounded())) procent")

            Text(footerText)
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.top, 26)
    }

    private var titleText: String {
        if failureMessage != nil { return "Coś poszło nie tak" }
        return isDone ? "Plan gotowy" : "Układam Twój plan"
    }

    private var footerText: String {
        guard isDone, let plan = model.plan else {
            return "Plan układa AI z katalogu ćwiczeń, a aplikacja go sprawdza. Gdyby coś poszło nie tak, użyję planu z szablonu."
        }
        if let notice = plan.notices.first { return notice.userMessage }
        return plan.source == .ai
            ? "Plan ułożony przez AI z katalogu ćwiczeń i sprawdzony przez aplikację."
            : "Plan z szablonu dobranego do Twojego celu, poziomu i sprzętu."
    }

    @ViewBuilder
    private func stageRow(_ stage: GenerationStage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            switch stage.state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(FormaColor.onVolt)
                    .frame(width: 24, height: 24)
                    .background(FormaColor.volt, in: Circle())
            case .current:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(FormaColor.voltText)
                    .frame(width: 24, height: 24)
            case .upcoming:
                Circle()
                    .strokeBorder(FormaColor.ink3, lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.label)
                    .formaStyle(.subheadline)
                    .fontWeight(stage.state == .current ? .semibold : .regular)
                    .foregroundStyle(stage.state == .upcoming ? FormaColor.ink3 : FormaColor.ink)
                if let detail = stage.detail, stage.state != .upcoming {
                    Text(detail).formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(stage.state == .done ? "Gotowe" : stage.state == .current ? "W toku" : "Oczekuje")
    }
}
