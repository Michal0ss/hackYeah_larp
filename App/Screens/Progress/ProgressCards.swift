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

/// What to follow in a chart: a few named options, picked from a compact menu.
private struct ChoiceMenu: View {
    let options: [(id: String, name: String)]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { option in
                Button(option.name) { selection = option.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.id == selection }?.name ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(FormaColor.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(FormaColor.well, in: Capsule())
        }
    }
}

/// Technique over time for one exercise: the person picks the exercise and the overall score or one part of it.
struct TechniqueCard: View {
    @Environment(AppStore.self) private var store
    let results: [TechniqueResult]
    let simulated: Bool
    let onAnalyse: () -> Void

    @State private var chosenExercise = ""
    @State private var chosenComponent = ""

    private var exercises: [String] { TechniqueSeries.exerciseIds(in: results) }
    private var exerciseId: String? { exercises.contains(chosenExercise) ? chosenExercise : exercises.first }
    private var components: [String] { exerciseId.map { TechniqueSeries.components(in: results, exerciseId: $0) } ?? [] }
    private var component: String? { components.contains(chosenComponent) ? chosenComponent : nil }

    private func name(_ id: String) -> String { store.exercise(id: id)?.name ?? "Ćwiczenie" }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel("Technika")
                Spacer()
                if simulated { SimulatedBadge() }
            }
            if let exerciseId {
                let points = TechniqueSeries.points(results, exerciseId: exerciseId, component: component)
                HStack(spacing: FormaSpacing.s) {
                    ChoiceMenu(options: exercises.map { (id: $0, name: name($0)) },
                               selection: Binding(get: { exerciseId }, set: { chosenExercise = $0 }))
                    ChoiceMenu(options: [(id: "", name: "Wynik ogólny")] + components.map { (id: $0, name: Self.partName($0)) },
                               selection: Binding(get: { component ?? "" }, set: { chosenComponent = $0 }))
                }
                if let first = points.first, let last = points.last {
                    HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.m) {
                        NumberText("\(Int(last.value))", size: 52, unit: "/100", color: FormaColor.voltText)
                        if points.count > 1 {
                            DeltaChip(delta: last.value - first.value) { "\(Int($0.rounded()))" }
                        }
                    }
                    TechniqueChart(points: points)
                        .frame(height: 150)
                }
                if component == nil,
                   let summary = ProgressReport.techniqueProgress(results.filter { $0.exerciseId == exerciseId })?.summary {
                    Text(summary)
                        .formaStyle(.subheadline)
                        .foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    private static func partName(_ key: String) -> String {
        let name = ProgressReport.componentNames[key] ?? key
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// "+14 od startu". Never color alone: arrow and sign carry the meaning too.
private struct DeltaChip: View {
    let delta: Double
    let format: (Double) -> String

    var body: some View {
        let up = delta > 0.01, down = delta < -0.01
        let color = up ? FormaColor.goText : down ? FormaColor.moderateText : FormaColor.ink2
        HStack(spacing: 4) {
            Image(systemName: up ? "arrow.up.right" : down ? "arrow.down.right" : "equal")
                .font(.system(size: 12, weight: .bold))
            Text(up ? "+\(format(abs(delta))) od startu" : down ? "−\(format(abs(delta))) od startu" : "bez zmian")
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
    let points: [SeriesPoint]

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Data", p.date), y: .value("Wynik", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(FormaColor.volt)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            PointMark(x: .value("Data", p.date), y: .value("Wynik", p.value))
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
        .accessibilityValue(points.map { "\(Int($0.value))" }.joined(separator: ", "))
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

// MARK: Load

/// Weight or repetitions over time for one exercise. Two menus, like the technique chart: the exercise (everything in
/// the plan, plus anything else that was logged) and what to follow. Real data only: an exercise with nothing logged
/// yet says what is missing.
struct LoadCard: View {
    @Environment(AppStore.self) private var store
    let sets: [LoggedLoad]

    @State private var chosenMetric = LoadMetric.weight.rawValue
    @State private var chosenExercise = ""

    private var metric: LoadMetric { LoadMetric(rawValue: chosenMetric) ?? .weight }
    private var plannedIds: [String] { store.plan.sessions.flatMap(\.exercises).map(\.exerciseId) }
    private var exercises: [String] { LoadSeries.exerciseIds(in: sets, planned: plannedIds) }
    private var exerciseId: String? { exercises.contains(chosenExercise) ? chosenExercise : exercises.first }

    private func name(_ id: String) -> String { store.exercise(id: id)?.name ?? "Ćwiczenie" }

    private func format(_ value: Double) -> String {
        metric == .weight ? WorkoutFormat.weight(value) : "\(Int(value.rounded())) powt."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel(metric == .weight ? "Ciężar w czasie" : "Powtórzenia w czasie")
            if let exerciseId {
                let points = LoadSeries.points(sets, exerciseId: exerciseId, metric: metric)
                HStack(spacing: FormaSpacing.s) {
                    ChoiceMenu(options: exercises.map { (id: $0, name: name($0)) },
                               selection: Binding(get: { exerciseId }, set: { chosenExercise = $0 }))
                    ChoiceMenu(options: [(id: LoadMetric.weight.rawValue, name: "Ciężar"),
                                         (id: LoadMetric.reps.rawValue, name: "Powtórzenia")],
                               selection: $chosenMetric)
                }
                if let first = points.first, let last = points.last {
                    HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.m) {
                        NumberText(format(last.value), size: 36, color: FormaColor.voltText)
                        if points.count > 1 {
                            DeltaChip(delta: last.value - first.value, format: format)
                        }
                    }
                    if points.count > 1 {
                        LoadChart(points: points, metric: metric)
                            .frame(height: 150)
                    }
                    Text(points.count > 1 ? "Najlepsza seria każdego dnia treningowego."
                                          : "Pierwszy zapis. Kolejne treningi narysują wykres.")
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                } else {
                    Text(metric == .weight ? "Brak zapisanego ciężaru dla tego ćwiczenia. Wpisz go po serii (Edytuj wynik) albo po treningu."
                                           : "Brak zapisanych powtórzeń dla tego ćwiczenia. Pojawią się po pierwszej serii.")
                        .formaStyle(.subheadline)
                        .foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Plan nie ma jeszcze ćwiczeń. Gdy je dostaniesz i zrobisz serie, pojawi się tu wykres ciężaru i powtórzeń.")
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct LoadChart: View {
    let points: [SeriesPoint]
    let metric: LoadMetric

    private var range: ClosedRange<Double> {
        let values = points.map(\.value)
        let top = values.max() ?? 0
        if metric == .reps { return 0...(top + 2) }
        let bottom = max(0, (values.min() ?? 0) - 5)
        return bottom...(top + 5)
    }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Data", p.date), y: .value("Wartość", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(FormaColor.volt)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            PointMark(x: .value("Data", p.date), y: .value("Wartość", p.value))
                .foregroundStyle(FormaColor.volt)
                .symbolSize(p.id == points.last?.id ? 90 : 36)
        }
        .chartYScale(domain: range)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(FormaColor.line)
                AxisValueLabel().foregroundStyle(FormaColor.ink3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(FormaColor.ink3)
            }
        }
        .accessibilityLabel(metric == .weight ? "Ciężar w czasie" : "Powtórzenia w czasie")
        .accessibilityValue(points.map { "\(Int($0.value.rounded()))" }.joined(separator: ", "))
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
