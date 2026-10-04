import SwiftUI
import Charts
import Analysis
import Contracts
import LiveSet
import Insights
import DesignSystem

/// Step 6: score, chart of the exercise's joint angle against its reference band, the skeleton at the working end of
/// every repetition, findings and a substitute exercise (PROJECT.md 5.3.5). Saving writes through `AppServices.localHistory`, same place the live set does.
struct ResultStepView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let model: AnalysisModel

    /// Same care signal as Today (Wiktor's `ProgressModel`/`CarePathway`) — reused, not re-derived.
    @State private var careModel = ProgressModel()
    @State private var showingCare = false

    var body: some View {
        if let result = model.result {
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                scoreCard(result)
                if result.isSimulated {
                    SimulatedBadge()
                }
                if model.analysedDespiteWarnings { approximateBanner }
                chartCard
                repsCard
                if !result.componentScores.isEmpty { componentScoresCard(result) }
                findingsCard(result)
                substituteCard(result)
                if let care = careModel.care {
                    careCard(care)
                }

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
            .task { await careModel.load(services: store.services) }
            .sheet(isPresented: $showingCare) {
                if let care = careModel.care {
                    CareView(assessment: care, simulated: careModel.careSimulated)
                }
            }
        } else {
            Text("Brak wyniku.").formaStyle(.callout).foregroundStyle(FormaColor.ink3)
        }
    }

    private func careCard(_ care: CareAssessment) -> some View {
        Button {
            showingCare = true
        } label: {
            HStack(spacing: FormaSpacing.m) {
                Image(systemName: "cross.case.fill").foregroundStyle(FormaColor.restText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Warto rozważyć konsultację").formaStyle(.callout).fontWeight(.semibold).foregroundStyle(FormaColor.ink)
                    Text(care.flag.reason).formaStyle(.footnote).foregroundStyle(FormaColor.ink3).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(FormaColor.ink3)
            }
            .padding(FormaSpacing.l)
            .glassCard()
        }
        .buttonStyle(.formaPress)
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

    /// The clip failed some checks of the quality gate but was analysed on request.
    private var approximateBanner: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Label("Wynik orientacyjny", systemImage: "exclamationmark.triangle.fill")
                .formaStyle(.callout).fontWeight(.semibold)
                .foregroundStyle(FormaColor.moderateText)
            Text("Nagranie miało braki, więc kąty mogą być mniej dokładne. Dla pewniejszego wyniku nagraj ćwiczenie ponownie z boku, z całą sylwetką w kadrze.")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            ForEach((model.qualityReport?.checks ?? []).filter { !$0.passed }) { check in
                Text("• \(check.label)" + (check.detail.map { ": \($0)" } ?? ""))
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FormaSpacing.l)
        .glassCard()
    }

    /// The main angle of the exercise (knee of a squat, elbow of a push-up and a pull-up) over the whole clip, with the
    /// band the reference allows at the working end and a marker at the working end of every repetition.
    @ViewBuilder
    private var chartCard: some View {
        let kind = model.kind
        let series = model.angleSeries
        if let first = series.first, let last = series.last {
            let band = kind.targetBand(model.angleReference)
            let reps = model.analysis?.clipReps ?? []
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                SectionLabel("\(kind.primaryAngleTitle) w czasie")
                Chart {
                    RectangleMark(xStart: .value("Początek", first.time), xEnd: .value("Koniec", last.time),
                                  yStart: .value("Od", band.lowerBound), yEnd: .value("Do", band.upperBound))
                        .foregroundStyle(FormaColor.go.opacity(0.16))
                    ForEach(series, id: \.time) { point in
                        LineMark(x: .value("Czas", point.time), y: .value("Kąt", point.angle))
                            .foregroundStyle(FormaColor.volt)
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(reps) { rep in
                        if let angle = model.repAngles[rep.index] {
                            PointMark(x: .value("Czas", rep.bottomTime), y: .value("Kąt", angle))
                                .foregroundStyle(FormaColor.ember)
                                .annotation(position: .top) {
                                    Text("\(rep.index)").font(.system(size: 10, weight: .bold)).foregroundStyle(FormaColor.ink3)
                                }
                        }
                    }
                }
                .chartYScale(domain: 0...190)
                .chartYAxisLabel("stopnie")
                .chartXAxisLabel("sekundy")
                .frame(height: 180)

                Text("Zielone pasmo: zakres kąta, którego oczekujemy w \(kind == .pullup ? "górnej" : "najniższej") pozycji (\(Int(band.lowerBound))–\(Int(band.upperBound))°). Pomarańczowe punkty to kolejne powtórzenia. Kąt z obrazu 2D jest szacunkiem z błędem rzędu kilku stopni.")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
            .padding(FormaSpacing.l)
            .glassCard()
        }
    }

    /// The skeleton in the working position of every repetition, with the measured angle.
    @ViewBuilder
    private var repsCard: some View {
        let reps = model.analysis?.clipReps ?? []
        if !reps.isEmpty {
            let kind = model.kind
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                SectionLabel("Powtórzenia")
                ScrollView(.horizontal) {
                    HStack(spacing: FormaSpacing.m) {
                        ForEach(reps) { rep in
                            VStack(spacing: FormaSpacing.s) {
                                // The box has the proportions of the picture, so the angles in the drawing are true.
                                ZStack {
                                    RoundedRectangle(cornerRadius: FormaRadius.sm, style: .continuous).fill(FormaColor.well)
                                    SkeletonOverlay(frame: rep.bottomFrame)
                                }
                                .frame(width: 170 * rep.bottomFrame.aspectRatio, height: 170)
                                .clipShape(RoundedRectangle(cornerRadius: FormaRadius.sm, style: .continuous))
                                Text("Powt. \(rep.index)").formaStyle(.footnote).fontWeight(.semibold).foregroundStyle(FormaColor.ink)
                                if let angle = model.repAngles[rep.index] {
                                    Text("\(Int(angle.rounded()))°").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                                    Text(kind == .squat ? "kolano" : "łokieć").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                                } else {
                                    Text("brak kąta").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
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
