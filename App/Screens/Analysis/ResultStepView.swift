import SwiftUI
import Charts
import Analysis
import Contracts
import DesignSystem

/// Step 6: score, knee-angle chart, skeleton on the deepest frame, findings and a substitute exercise
/// (PROJECT.md 5.3.5). Saving writes through `AppServices.localHistory`, same place the live set does.
struct ResultStepView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let model: AnalysisModel

    var body: some View {
        if let result = model.result {
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                scoreCard(result)
                if result.isSimulated {
                    SimulatedBadge()
                }
                chartCard
                componentScoresCard(result)
                findingsCard(result)
                substituteCard(result)

                Button {
                    save(result)
                } label: {
                    Text("Zapisz i przejdź do rekomendacji").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaPrimary)

                Button { model.startOver() } label: {
                    Text("Nowa analiza").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            }
        } else {
            Text("Brak wyniku.").formaStyle(.callout).foregroundStyle(FormaColor.ink3)
        }
    }

    private func scoreCard(_ result: TechniqueResult) -> some View {
        VStack(spacing: FormaSpacing.s) {
            SectionLabel(store.exercise(id: result.exerciseId)?.name ?? "Wynik")
            NumberText("\(result.score)", size: 64, unit: "/ 100")
        }
        .frame(maxWidth: .infinity)
        .padding(FormaSpacing.xl)
        .glassCard()
    }

    @ViewBuilder
    private var chartCard: some View {
        let series = RepAnalyzer.kneeAngleSeries(in: model.frames)
        if !series.isEmpty {
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                SectionLabel("Kąt kolana w czasie")
                Chart(series, id: \.time) { point in
                    LineMark(x: .value("Czas", point.time), y: .value("Kąt", point.angle))
                        .foregroundStyle(FormaColor.volt)
                        .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("stopnie")
                .chartXAxisLabel("sekundy")
                .frame(height: 160)

                if let deepest = RepAnalyzer.deepestFrame(in: model.frames) {
                    SectionLabel("Najniższy punkt")
                    ZStack {
                        RoundedRectangle(cornerRadius: FormaRadius.md, style: .continuous)
                            .fill(FormaColor.well)
                        SkeletonOverlay(frame: deepest)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: FormaRadius.md, style: .continuous))
                }
            }
            .padding(FormaSpacing.l)
            .glassCard()
        }
    }

    private func componentScoresCard(_ result: TechniqueResult) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Składowe")
            ForEach(componentOrder, id: \.key) { key, title in
                if let score = result.componentScores[key] {
                    HStack {
                        Text(title).formaStyle(.callout).foregroundStyle(FormaColor.ink2)
                        Spacer()
                        Text("\(score)").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                    }
                }
            }
        }
        .padding(FormaSpacing.l)
        .glassCard()
    }

    private var componentOrder: [(key: String, title: String)] {
        [("depth", "Głębokość"), ("torso", "Tułów"), ("repeatability", "Powtarzalność"), ("tempo", "Kontrola tempa")]
    }

    private func findingsCard(_ result: TechniqueResult) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Uwagi")
            ForEach(result.findings) { finding in
                HStack(alignment: .top, spacing: FormaSpacing.m) {
                    Image(systemName: finding.severity == .good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(finding.severity == .good ? FormaColor.goText : FormaColor.moderateText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).formaStyle(.callout).fontWeight(.semibold).foregroundStyle(FormaColor.ink)
                        Text(finding.detail).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                    }
                }
            }
        }
        .padding(FormaSpacing.l)
        .glassCard()
    }

    @ViewBuilder
    private func substituteCard(_ result: TechniqueResult) -> some View {
        if let substituteId = result.substituteExerciseId, let substitute = store.exercise(id: substituteId) {
            VStack(alignment: .leading, spacing: FormaSpacing.s) {
                SectionLabel("Zamiennik")
                Text(substitute.name).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text(substitute.summary).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                if let url = substitute.videoURL {
                    Link("Film wzorcowy", destination: url)
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.voltText)
                }
            }
            .padding(FormaSpacing.l)
            .glassCard()
        }
    }

    private func save(_ result: TechniqueResult) {
        store.services.localHistory.record(result)
        store.lastTechnique = result
        Task { await store.refreshRecommendation() }
        model.startOver()
        router.tab = .today
    }
}
