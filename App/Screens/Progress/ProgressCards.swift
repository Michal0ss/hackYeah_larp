import SwiftUI
import Charts
import Contracts
import DesignSystem
import Insights

// MARK: Empty state

/// Nothing to show yet: say what to do next (an analysis or a check-in).
struct EmptyProgressCard: View {
    let onAnalyse: () -> Void
    let onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            IconBadge(systemImage: "chart.line.uptrend.xyaxis", size: 48)
            Text("Jeszcze nic do pokazania")
                .formaStyle(.title2)
                .foregroundStyle(FormaColor.ink)
            Text("Po pierwszej analizie przysiadu i kilku check-inach zobaczysz tu wynik techniki, regenerację i nastrój w czasie. Treningi pojawią się tu jako kalendarz aktywności.")
                .formaStyle(.body)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Sen, tętno i HRV z Apple Health pojawią się tu same, gdy przyznasz dostęp.")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAnalyse) {
                Label("Nagraj pierwszą analizę", systemImage: "video.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
            Button(action: onCheckIn) {
                Label("Zrób check-in", systemImage: "face.smiling").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: Care teaser

/// "Warto rozważyć konsultację": opens the care screen. Shown only when `CarePathway` raised a signal.
struct CareTeaserCard: View {
    let assessment: CareAssessment
    let simulated: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: FormaSpacing.m) {
                IconBadge(systemImage: "cross.case.fill", fill: FormaColor.rest, icon: FormaColor.restText, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Warto rozważyć konsultację")
                        .formaStyle(.headline)
                        .foregroundStyle(FormaColor.ink)
                    Text(assessment.shortSummary())
                        .formaStyle(.subheadline)
                        .foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if simulated { SimulatedBadge().padding(.top, 4) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FormaColor.ink3)
                    .accessibilityHidden(true)
            }
            .padding(FormaSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.formaPress)
        .accessibilityHint("Pokazuje, skąd ten sygnał i co możesz zrobić")
    }
}

// MARK: Technique

struct TechniqueCard: View {
    let progress: TechniqueProgress?
    let simulated: Bool
    let onAnalyse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel("Wynik techniki · przysiad")
                Spacer()
                if simulated { SimulatedBadge() }
            }
            if let progress {
                HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.m) {
                    NumberText("\(progress.latest)", size: 52, unit: "/100", color: FormaColor.voltText)
                    if progress.points.count > 1 {
                        DeltaChip(delta: progress.deltaFromStart)
                    }
                }
                TechniqueChart(points: progress.points)
                    .frame(height: 150)
                Text(progress.summary)
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nagraj przysiad, a pokażemy, jak zmienia się wynik techniki.")
                    .formaStyle(.body)
                    .foregroundStyle(FormaColor.ink2)
                Button(action: onAnalyse) {
                    Label("Nagraj pierwszą analizę", systemImage: "video.fill")
                }
                .buttonStyle(.formaGlass)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// "+14 od startu". Never color alone: arrow and sign carry the meaning too.
private struct DeltaChip: View {
    let delta: Int

    var body: some View {
        let up = delta > 0, down = delta < 0
        let color = up ? FormaColor.goText : down ? FormaColor.moderateText : FormaColor.ink2
        HStack(spacing: 4) {
            Image(systemName: up ? "arrow.up.right" : down ? "arrow.down.right" : "equal")
                .font(.system(size: 12, weight: .bold))
            Text(up ? "+\(delta) od startu" : down ? "\(delta) od startu" : "bez zmian")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(color.opacity(0.14), in: Capsule())
        .overlay { Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

private struct TechniqueChart: View {
    let points: [ScorePoint]

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Data", p.date), y: .value("Wynik", p.score))
                .interpolationMethod(.monotone)
                .foregroundStyle(FormaColor.volt)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            PointMark(x: .value("Data", p.date), y: .value("Wynik", p.score))
                .foregroundStyle(FormaColor.volt)
                .symbolSize(p.id == points.last?.id ? 90 : 36)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(FormaColor.line)
                AxisValueLabel().foregroundStyle(FormaColor.ink3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(FormaColor.ink3)
            }
        }
        .accessibilityLabel("Wynik techniki w czasie")
        .accessibilityValue(points.map { "\($0.score)" }.joined(separator: ", "))
    }
}

// MARK: Activity

/// A GitHub-style calendar of training days ("kwadraciki") plus a short analysis of the last week. Real
/// data only, like the recent-sets card: an all-empty grid just means nothing has been logged yet.
struct ActivityCard: View {
    @Environment(AppStore.self) private var store
    let activity: ActivityLog

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel("Aktywność")
                Spacer()
                if activity.currentStreakDays > 0 {
                    Label("\(activity.currentStreakDays) dni z rzędu", systemImage: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FormaColor.emberText)
                }
            }
            ActivityGrid(days: activity.days)
            Text(activity.summary)
                .formaStyle(.subheadline)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let topExerciseId = activity.topExerciseId {
                Text("Najczęściej: \(store.exercise(id: topExerciseId)?.name ?? "ćwiczenie")")
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Weeks as columns, weekdays (Mon...Sun) as rows, darker = more sets that day. Scrolls horizontally so
/// older weeks are reachable without shrinking the squares.
private struct ActivityGrid: View {
    let days: [ActivityDay]
    private static let cell: CGFloat = 13
    private static let gap: CGFloat = 3

    private var weeks: [[ActivityDay]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private var maxCount: Int { days.compactMap(\.setCount).max() ?? 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: Self.gap) {
                        ForEach(week) { day in square(day) }
                    }
                }
            }
        }
        .accessibilityLabel("Dni treningowe w ostatnich \(weeks.count) tygodniach")
        .accessibilityValue("\(days.filter { ($0.setCount ?? 0) > 0 }.count) dni z treningiem")
    }

    @ViewBuilder
    private func square(_ day: ActivityDay) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: day.setCount))
            .frame(width: Self.cell, height: Self.cell)
            .opacity(day.setCount == nil ? 0 : 1)
    }

    private func color(for setCount: Int?) -> Color {
        guard let setCount, setCount > 0 else { return FormaColor.well }
        guard maxCount > 0 else { return FormaColor.well }
        let level = min(1, Double(setCount) / Double(maxCount))
        return FormaColor.volt.opacity(0.25 + 0.75 * level)
    }
}

// MARK: Recovery and mood

struct RecoveryMoodCard: View {
    let report: ProgressReport
    let simulated: Bool
    let onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel("Regeneracja i nastrój")
                Spacer()
                if simulated { SimulatedBadge() }
            }
            if report.recovery.isEmpty && report.mood.isEmpty {
                Text("Sen, tętno i HRV z Apple Health oraz check-iny pojawią się tu, gdy będzie z czego policzyć wykres.")
                    .formaStyle(.body)
                    .foregroundStyle(FormaColor.ink2)
                Button(action: onCheckIn) {
                    Label("Zrób check-in", systemImage: "face.smiling")
                }
                .buttonStyle(.formaGlass)
            } else {
                RecoveryMoodChart(recovery: report.recovery, mood: report.mood)
                    .frame(height: 170)
                HStack(spacing: FormaSpacing.l) {
                    if !report.recovery.isEmpty {
                        LegendItem(title: "Regeneracja (sen, HRV, tętno)", color: FormaColor.volt, dashed: false)
                    }
                    if !report.mood.isEmpty {
                        LegendItem(title: "Nastrój", color: FormaColor.rest, dashed: true)
                    }
                }
                if report.recovery.isEmpty {
                    Text("Brak danych regeneracji. Sen, tętno i HRV pojawią się tu, gdy Apple Health je zapisze.")
                        .formaStyle(.subheadline)
                        .foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if report.mood.isEmpty {
                    Button(action: onCheckIn) {
                        Label("Zrób check-in, żeby zobaczyć nastrój", systemImage: "face.smiling")
                    }
                    .buttonStyle(.formaGlass)
                }
                if let sentence = report.trendSentence {
                    Text(sentence)
                        .formaStyle(.subheadline)
                        .foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Wskaźnik regeneracji to pomocnicze podsumowanie snu, HRV i tętna na wykres, a nie ocena zdrowia.")
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Two lines on one 0...100 axis. They differ in color *and* in dash, so the chart reads without color.
private struct RecoveryMoodChart: View {
    let recovery: [DayValue]
    let mood: [DayValue]

    private static let recoveryName = "Regeneracja"
    private static let moodName = "Nastrój"

    var body: some View {
        Chart {
            ForEach(recovery) { d in
                LineMark(x: .value("Dzień", d.date), y: .value("Wartość", d.value),
                         series: .value("Wskaźnik", Self.recoveryName))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(FormaColor.volt)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(mood) { d in
                LineMark(x: .value("Dzień", d.date), y: .value("Wartość", d.value),
                         series: .value("Wskaźnik", Self.moodName))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(FormaColor.rest)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
                PointMark(x: .value("Dzień", d.date), y: .value("Wartość", d.value))
                    .foregroundStyle(FormaColor.rest)
                    .symbolSize(22)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in
                AxisGridLine().foregroundStyle(FormaColor.line)
                AxisValueLabel().foregroundStyle(FormaColor.ink3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(FormaColor.ink3)
            }
        }
        .accessibilityLabel("Regeneracja i nastrój w ostatnich 14 dniach")
        .accessibilityValue("Regeneracja: \(recovery.map { "\($0.value)" }.joined(separator: ", ")). Nastrój: \(mood.map { "\($0.value)" }.joined(separator: ", "))")
    }
}

private struct LegendItem: View {
    let title: String
    let color: Color
    let dashed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [4, 3] : []))
                .frame(width: 22, height: 3)
                .accessibilityHidden(true)
            Text(title)
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Recent sets

/// Sets done with the live coach, newest first. Real data only (the app records sets, not whole sessions).
struct RecentSetsCard: View {
    @Environment(AppStore.self) private var store
    let sets: [SetSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel("Ostatnie serie z trenerem")
                Spacer()
                Text("ostatnie \(sets.count)")
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
            }
            VStack(spacing: 0) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    row(set)
                    if index < sets.count - 1 { Divider().overlay(FormaColor.line) }
                }
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ set: SetSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.exercise(id: set.exerciseId)?.name ?? "Ćwiczenie") · seria \(set.setIndex)")
                    .formaStyle(.body)
                    .foregroundStyle(FormaColor.ink)
                if set.isSimulated { SimulatedBadge() }
                Text(set.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Tempo \(set.tempoScore)")
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink2)
                if let technique = set.techniqueScore {
                    Text("Technika \(technique)")
                        .formaStyle(.subheadline)
                        .foregroundStyle(FormaColor.ink2)
                }
            }
        }
        .padding(.vertical, FormaSpacing.s)
        .accessibilityElement(children: .combine)
    }
}
