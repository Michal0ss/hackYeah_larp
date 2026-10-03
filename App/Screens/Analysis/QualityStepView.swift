import SwiftUI
import Contracts
import DesignSystem

/// Step 4: reading the clip and the quality gate result (PROJECT.md 6.2). While the clip is read the skeleton found in
/// each frame is drawn over the picture, like in the live set. A clip that fails some checks but shows repetitions can
/// still be analysed ("Analizuj mimo to"); the result is then marked as approximate.
struct QualityStepView: View {
    let model: AnalysisModel

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            Text(model.isWorking ? "Analizuję nagranie" : "Ocena jakości nagrania")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)

            if model.isWorking {
                readingCard
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
                    if model.canAnalyzeAnyway {
                        Text("Widzę w nagraniu powtórzenia, więc mogę je ocenić mimo uwag. Wynik będzie wtedy orientacyjny.")
                            .formaStyle(.footnote)
                            .foregroundStyle(FormaColor.ink3)
                        Button { model.proceedToScoring(anyway: true) } label: {
                            Text("Analizuj mimo to").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.formaPrimary)
                    }
                    retryButton
                }
            }
        }
    }

    // MARK: - Reading the clip

    /// The picture of the frame that was just analysed with its skeleton, a progress bar and the number of frames.
    private var readingCard: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: FormaRadius.md, style: .continuous).fill(FormaColor.well)
                if let frame = model.previewFrame {
                    ZStack {
                        if let image = model.previewImage {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .scaledToFit()
                        }
                        SkeletonOverlay(frame: frame)
                    }
                    .aspectRatio(frame.aspectRatio, contentMode: .fit)
                    .frame(maxHeight: 420)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: FormaRadius.md, style: .continuous))

            ProgressView(value: model.extractionFraction)
                .tint(FormaColor.volt)
            HStack {
                Text("Szukam sylwetki w klatkach…").formaStyle(.callout).foregroundStyle(FormaColor.ink2)
                Spacer()
                Text("\(model.framesAnalysed) klatek")
                    .formaStyle(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(FormaColor.ink3)
            }
            Text("Analiza dzieje się na telefonie. Nagranie nie opuszcza urządzenia i jest usuwane po odczycie.")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
        }
        .padding(FormaSpacing.l)
        .glassCard()
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
                HStack(alignment: .top, spacing: FormaSpacing.m) {
                    Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.passed ? FormaColor.goText : FormaColor.emberText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.label).formaStyle(.callout).foregroundStyle(FormaColor.ink2)
                        // The measured numbers, so a rejected clip can be explained.
                        if !check.passed, let detail = check.detail {
                            Text(detail).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(FormaSpacing.l)
        .glassCard()
    }
}
