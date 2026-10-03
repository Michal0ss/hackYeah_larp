import SwiftUI
import Contracts
import DesignSystem

/// Step 4: quality gate result (PROJECT.md 6.2). Blocks scoring until the recording is good enough.
struct QualityStepView: View {
    let model: AnalysisModel

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            Text("Ocena jakości nagrania")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)

            if model.isWorking {
                VStack(spacing: FormaSpacing.m) {
                    ProgressView()
                    Text("Sprawdzam nagranie…").formaStyle(.callout).foregroundStyle(FormaColor.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(FormaSpacing.xxl)
                .glassCard()
            } else if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: FormaSpacing.m) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(FormaColor.emberText)
                    retryButton
                }
                .padding(FormaSpacing.l)
                .glassCard()
            } else if let report = model.qualityReport {
                checksCard(report)
                if report.passed {
                    Button { model.proceedToScoring() } label: {
                        Text("Dalej").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.formaPrimary)
                } else {
                    if let hint = report.userHint {
                        Text(hint).formaStyle(.callout).foregroundStyle(FormaColor.moderateText)
                    }
                    retryButton
                }
            }
        }
    }

    private var retryButton: some View {
        Button { model.retryCapture() } label: {
            Text("Nagraj ponownie").frame(maxWidth: .infinity)
        }
        .buttonStyle(.formaGlass)
    }

    private func checksCard(_ report: QualityReport) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            ForEach(report.checks) { check in
                HStack(spacing: FormaSpacing.m) {
                    Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.passed ? FormaColor.goText : FormaColor.emberText)
                    Text(check.label).formaStyle(.callout).foregroundStyle(FormaColor.ink2)
                    Spacer()
                }
            }
        }
        .padding(FormaSpacing.l)
        .glassCard()
    }
}
