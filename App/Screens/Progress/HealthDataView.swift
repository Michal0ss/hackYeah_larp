import SwiftUI
import Charts
import Contracts
import Health
import DesignSystem

/// What the panel shows besides the Health numbers: the step goal and the mood.
struct HealthPanelData {
    var overview: HealthOverview
    var goal: StepGoal
    var mood: MoodSummary
}

/// Mood from the check-ins (1 to 5): the latest one in the last week and the average of that week.
struct MoodSummary: Equatable {
    var latest: CheckIn?
    var average: Double?
    var count: Int

    init(checkIns: [CheckIn]) {
        latest = checkIns.max { $0.date < $1.date }
        count = checkIns.count
        average = checkIns.isEmpty ? nil : Double(checkIns.map(\.mood).reduce(0, +)) / Double(checkIns.count)
    }

    static func word(for mood: Int) -> String {
        switch mood {
        case ...1: return "niski"
        case 2: return "słaby"
        case 3: return "średni"
        case 4: return "dobry"
        default: return "świetny"
        }
    }
}

/// "Dane zdrowotne": what Apple Health knows about you in general (steps, active energy, distance, exercise minutes,
/// flights, sleep, resting heart rate, HRV), with the last days as a chart. Opens as a sheet from the card on Dziś.
/// Numbers only, no conclusions: this is a look at the data, not advice. Owner: Wiktor.
struct HealthDataView: View {
    /// Asks for access to the activity types when needed and reads the last days.
    let load: () async -> HealthPanelData
    @Environment(\.dismiss) private var dismiss
    @State private var panel: HealthPanelData?
    private var overview: HealthOverview? { panel?.overview }
    @State private var metric: ActivityMetric = .steps

    private static let days = 7

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    topBar
                    header
                    if let panel {
                        summary(panel)
                        content(panel.overview)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, FormaSpacing.xxl)
                    }
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
            // Pull to refresh must work on the short "no data" page too.
            .scrollBounceBehavior(.always)
            .refreshable { panel = await load() }
        }
        .task { panel = await load() }
    }

    // MARK: Header

    private var topBar: some View {
        HStack {
            SectionLabel("Apple Health")
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FormaColor.ink)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: true)
            }
            .accessibilityLabel("Zamknij")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text("Dane zdrowotne")
                .formaStyle(.largeTitle)
                .foregroundStyle(FormaColor.ink)
                .accessibilityAddTraits(.isHeader)
            if overview?.isSimulated == true {
                SimulatedBadge()
            } else {
                Text("Z aplikacji Zdrowie na tym telefonie")
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink3)
            }
        }
    }

    // MARK: Summary

    /// The four things asked for first: sleep, steps, the step goal (set by the trainer) and the mood.
    private func summary(_ panel: HealthPanelData) -> some View {
        let sleep = panel.overview.recovery.first?.sleepText
        let steps = panel.overview.today?.value(for: .steps).map { Int($0.rounded()) }
        let goal = panel.goal
        return VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Dziś w skrócie")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: FormaSpacing.m), GridItem(.flexible())], spacing: FormaSpacing.m) {
                SummaryTile(title: "Sen", systemImage: "bed.double.fill", value: sleep ?? "–",
                            note: sleep == nil ? "brak danych" : "ostatnia noc")
                SummaryTile(title: "Kroki", systemImage: "figure.walk", value: steps.map(Self.number) ?? "–",
                            note: steps == nil ? "brak danych" : "dziś")
                SummaryTile(title: "Cel kroków", systemImage: "target", value: Self.number(goal.steps),
                            note: goal.source == .coach ? "ustalony przez trenera" : "cel startowy")
                SummaryTile(title: "Nastrój", systemImage: "face.smiling",
                            value: panel.mood.latest.map { "\($0.mood)/5" } ?? "–",
                            note: moodNote(panel.mood))
            }
            goalCard(goal, steps: steps)
        }
    }

    private func moodNote(_ mood: MoodSummary) -> String {
        guard let latest = mood.latest else { return "brak check-inu" }
        let word = MoodSummary.word(for: latest.mood)
        let day = Calendar.current.isDateInToday(latest.date) ? "dziś" : Self.dayLabel(latest.date)
        return "\(word), \(day)"
    }

    /// Progress of today's steps against the goal, and what the trainer said about it.
    private func goalCard(_ goal: StepGoal, steps: Int?) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            if let steps {
                ProgressView(value: min(1, goal.progress(steps: steps)))
                    .tint(FormaColor.volt)
                Text(steps >= goal.steps ? "Cel na dziś osiągnięty: \(Self.number(steps)) z \(Self.number(goal.steps)) kroków."
                                         : "\(Self.number(steps)) z \(Self.number(goal.steps)) kroków, zostało \(Self.number(goal.steps - steps)).")
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
            }
            if goal.source == .coach {
                Text(goal.reason.map { "Trener: „\($0)”" } ?? "Cel ustalił trener.")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            } else {
                Text("To cel startowy dopasowany do Twojego poziomu. Poproś trenera w czacie o własny, np. „ustaw mi cel kroków”.")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FormaSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: FormaRadius.md)
    }

    private static func number(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "pl_PL")))
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ overview: HealthOverview) -> some View {
        if overview.hasData {
            activityToday(overview)
            recovery(overview)
            trend(overview)
        } else {
            emptyCard
        }
        InfoBanner(systemImage: "lock.shield.fill") {
            Text("Dane zostają na telefonie. To liczby z aplikacji Zdrowie, a nie porada medyczna. Dostęp zmienisz w Ustawieniach: Zdrowie, Dostęp do danych i urządzenia.")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func activityToday(_ overview: HealthOverview) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Aktywność dziś")
            MetricTile(metric: .steps, value: overview.today?.value(for: .steps), large: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: FormaSpacing.m), GridItem(.flexible())],
                      spacing: FormaSpacing.m) {
                ForEach([ActivityMetric.activeEnergy, .distance, .exercise, .flights]) { metric in
                    MetricTile(metric: metric, value: overview.today?.value(for: metric), large: false)
                }
            }
        }
    }

    @ViewBuilder
    private func recovery(_ overview: HealthOverview) -> some View {
        if let day = overview.recovery.first {
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                HStack {
                    SectionLabel("Sen i serce")
                    Spacer()
                    Text(Self.dayLabel(day.date))
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                }
                HStack(alignment: .top, spacing: FormaSpacing.m) {
                    HeartStat(title: "Sen", systemImage: "bed.double.fill", value: day.sleepText ?? "–", unit: nil,
                              note: nil, spoken: nil)
                    HeartStat(title: "Tętno spocz.", systemImage: "heart.fill",
                              value: day.restingHeartRate.map { "\($0)" } ?? "–", unit: "bpm",
                              note: day.restingHeartRateDelta.map(Self.signed),
                              spoken: day.restingHeartRateDelta.map { "\(abs($0)) uderzeń \($0 < 0 ? "poniżej" : "powyżej") średniej" })
                    HeartStat(title: "HRV", systemImage: "waveform.path.ecg", value: day.hrvMs.map { "\($0)" } ?? "–",
                              unit: "ms", note: day.hrvDeltaPercent.map { Self.signed($0) + "%" },
                              spoken: day.hrvDeltaPercent.map { "\(abs($0)) procent \($0 < 0 ? "poniżej" : "powyżej") średniej" })
                }
            }
            .padding(FormaSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func trend(_ overview: HealthOverview) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Ostatnie \(Self.days) dni")
            ScrollView(.horizontal) {
                HStack(spacing: FormaSpacing.s) {
                    ForEach(ActivityMetric.allCases) { option in
                        PillOption(option.shortTitle, isSelected: option == metric) { metric = option }
                    }
                }
            }
            .scrollIndicators(.hidden)
            if overview.activity.contains(where: { $0.value(for: metric) != nil }) {
                ActivityChart(days: overview.activity, metric: metric)
                    .frame(height: 180)
                if let average = overview.average(of: metric) {
                    Text("\(metric.title): średnio \(metric.formattedWithUnit(average)) dziennie, z dni z danymi.")
                        .formaStyle(.subheadline)
                        .foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Brak danych: \(metric.title.lowercased()) z ostatnich \(Self.days) dni. Część z nich zapisuje tylko zegarek.")
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(FormaColor.ink3)
                .accessibilityHidden(true)
            Text("Brak danych w Apple Health")
                .formaStyle(.headline)
                .foregroundStyle(FormaColor.ink)
            Text("Aplikacja czyta kroki, kalorie aktywne, dystans, minuty ćwiczeń, piętra, sen, tętno spoczynkowe i HRV. Część z nich zapisuje tylko zegarek. Gdy pojawią się w aplikacji Zdrowie, zobaczysz je tutaj. Pociągnij w dół, żeby odświeżyć.")
                .formaStyle(.subheadline)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Helpers

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "dziś" }
        if calendar.isDateInYesterday(date) { return "wczoraj" }
        return date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "pl_PL")))
    }

    private static func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : value < 0 ? "−\(abs(value))" : "0" }
}

/// A tile of the summary: a title, one value and a short note under it.
private struct SummaryTile: View {
    let title: String
    let systemImage: String
    let value: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(FormaColor.voltText).accessibilityHidden(true)
                Text(title).formaStyle(.footnote).foregroundStyle(FormaColor.ink3).lineLimit(1).minimumScaleFactor(0.8)
            }
            NumberText(value, size: 28).minimumScaleFactor(0.6).lineLimit(1)
            Text(note).formaStyle(.footnote).foregroundStyle(FormaColor.ink3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(FormaSpacing.l)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .glassCard(radius: FormaRadius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(note)")
    }
}

/// One number with its name and icon, e.g. steps today.
private struct MetricTile: View {
    let metric: ActivityMetric
    let value: Double?
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .foregroundStyle(FormaColor.voltText)
                    .accessibilityHidden(true)
                Text(metric.title)
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            NumberText(value.map(metric.formatted) ?? "–", size: large ? 44 : 28, unit: metric.unit)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(FormaSpacing.l)
        .frame(maxWidth: .infinity, minHeight: large ? nil : 100, alignment: .topLeading)
        .glassCard(radius: FormaRadius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(value.map(metric.formattedWithUnit) ?? "brak danych")
    }
}

/// Sleep, resting heart rate or HRV with its deviation from your own average.
private struct HeartStat: View {
    let title: String
    let systemImage: String
    let value: String
    let unit: String?
    let note: String?
    let spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FormaColor.voltText)
                .accessibilityHidden(true)
            NumberText(value, size: 20, unit: unit)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(minHeight: 34, alignment: .bottomLeading)
            Text(title)
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note {
                Text(note + " od średniej")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FormaColor.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, unit, spoken].compactMap { $0 }.joined(separator: " "))
    }
}

/// Bars per day for one metric; today is the bright one, the dashed line is the average of the days with data.
private struct ActivityChart: View {
    let days: [DailyActivity]
    let metric: ActivityMetric

    private var average: Double? {
        let values = days.compactMap { $0.value(for: metric) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let value = day.value(for: metric) {
                    BarMark(x: .value("Dzień", day.date, unit: .day), y: .value(metric.title, value))
                        .foregroundStyle(Calendar.current.isDateInToday(day.date) ? FormaColor.volt : FormaColor.volt.opacity(0.45))
                        .cornerRadius(5)
                }
            }
            if let average {
                RuleMark(y: .value("Średnia", average))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(FormaColor.rest)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow).locale(Locale(identifier: "pl_PL")))
                    .foregroundStyle(FormaColor.ink3)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(FormaColor.line)
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(metric.formatted(number)) }
                }
                .foregroundStyle(FormaColor.ink3)
            }
        }
        .accessibilityLabel("\(metric.title) w ostatnich \(days.count) dniach")
        .accessibilityValue(days.reversed().compactMap { day in
            day.value(for: metric).map { metric.formattedWithUnit($0) }
        }.joined(separator: ", "))
    }
}
