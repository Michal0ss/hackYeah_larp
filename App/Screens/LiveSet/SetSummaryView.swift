import SwiftUI
import Contracts
import DesignSystem
import LiveSet

/// Shown between sets: technique, recording quality and tempo. Owner: Michał.
struct SetSummaryView: View {
    let summary: SetSummary
    let exerciseName: String
    let totalSets: Int
    /// False when the summary is shown as details on top of the screen after a set (it has its own buttons).
    var showsActions = true
    /// What the assessment adapted to the person. Nil when the summary is opened later from a stored set, where the
    /// context of that moment is no longer known (nothing is shown then).
    var contextNotes: [String]?
    let onNextSet: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    techniqueCard
                    framingCard
                    tempoCard
                    repsCard
                    if showsActions { actions }
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            SectionLabel("Seria \(summary.setIndex) z \(totalSets)")
            Text(exerciseName).formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
            HStack(spacing: FormaSpacing.s) {
                Text(repsLabel(summary.reps.count))
                    .formaStyle(.headline).foregroundStyle(FormaColor.ink2)
                if summary.isSimulated { SimulatedBadge() }
            }
        }
    }

    // MARK: - Cards

    private var techniqueCard: some View {
        card(title: "Technika", symbol: "figure.strengthtraining.traditional") {
            if let score = summary.techniqueScore {
                scoreRow(score: score, caption: "z 100")
                findings(summary.techniqueFindings)
                if let contextNotes { ContextNoteView(notes: contextNotes) }
            } else {
                Text("Nie udało się ocenić techniki. Sprawdź ustawienie telefonu.")
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
            }
        }
    }

    private var framingCard: some View {
        card(title: "Jakość nagrania", symbol: "camera.viewfinder") {
            HStack {
                Text(summary.framing.rating.title)
                    .font(.formaNumber(28))
                    .foregroundStyle(color(for: summary.framing.rating))
                Spacer()
                Text("\(Int((summary.framing.goodFrameRatio * 100).rounded()))% klatek z pełną sylwetką")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
            if let hint = summary.framing.hint {
                Label(hint, systemImage: "arrow.right.circle.fill")
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.moderateText)
            }
        }
    }

    private var tempoCard: some View {
        card(title: "Szybkość i tempo", symbol: "metronome") {
            scoreRow(score: summary.tempoScore, caption: "cel \(summary.targetTempo.label)")
            tempoBars
            findings(summary.tempoFindings)
        }
    }

    private var tempoBars: some View {
        let reps = summary.reps
        func avg(_ key: KeyPath<RepTempo, Double>) -> Double {
            reps.isEmpty ? 0 : reps.map { $0[keyPath: key] }.reduce(0, +) / Double(reps.count)
        }
        return VStack(spacing: FormaSpacing.s) {
            tempoRow("W dół", actual: avg(\.eccentric), target: summary.targetTempo.eccentric)
            tempoRow("Pauza", actual: avg(\.bottomPause), target: summary.targetTempo.bottomPause)
            tempoRow("W górę", actual: avg(\.concentric), target: summary.targetTempo.concentric)
        }
    }

    private func tempoRow(_ label: String, actual: Double, target: Double) -> some View {
        let maxValue = max(actual, target, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
                Spacer()
                Text("\(format(actual)) s / cel \(format(target)) s")
                    .font(.formaNumber(13)).monospacedDigit().foregroundStyle(FormaColor.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(FormaColor.well)
                    Capsule().fill(FormaColor.volt.opacity(0.9))
                        .frame(width: geo.size.width * actual / maxValue)
                    Rectangle().fill(FormaColor.ink)
                        .frame(width: 2)
                        .offset(x: geo.size.width * target / maxValue)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var repsCard: some View {
        card(title: "Powtórzenia", symbol: "list.number") {
            ForEach(summary.reps) { rep in
                HStack {
                    Text("\(rep.index)").font(.formaNumber(17)).foregroundStyle(FormaColor.ink).frame(width: 28, alignment: .leading)
                    Text("\(format(rep.eccentric)) · \(format(rep.bottomPause)) · \(format(rep.concentric)) s")
                        .font(.formaNumber(14)).monospacedDigit().foregroundStyle(FormaColor.ink2)
                    Spacer()
                    if !rep.isFullRange {
                        Label("płytko", systemImage: "arrow.up.to.line")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(FormaColor.moderateText)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: FormaSpacing.m) {
            if summary.setIndex < totalSets {
                Button(action: onNextSet) { Text("Następna seria").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaPrimary)
            }
            Button(action: onClose) {
                Text(summary.setIndex < totalSets ? "Zakończ trening" : "Gotowe").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
        }
    }

    // MARK: - Pieces

    private func card<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            Label(title, systemImage: symbol)
                .formaStyle(.caption)
                .foregroundStyle(FormaColor.ink3)
            content()
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func scoreRow(score: Int, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.s) {
            NumberText("\(score)", size: 56, color: scoreColor(score))
            Text(caption).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
        }
    }

    private func findings(_ items: [TechniqueFinding]) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: FormaSpacing.s) {
                    Image(systemName: item.severity == .good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.severity == .good ? FormaColor.goText : item.severity == .major ? FormaColor.emberText : FormaColor.moderateText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                        Text(item.detail).formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.severity != .good, item.repsTotal > 0 {
                            Text("w \(item.repsAffected) z \(item.repsTotal) powtórzeń")
                                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                        }
                    }
                }
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 80 ? FormaColor.goText : score >= 60 ? FormaColor.moderateText : FormaColor.emberText
    }

    private func color(for rating: FramingRating) -> Color {
        switch rating {
        case .good: return FormaColor.goText
        case .fair: return FormaColor.moderateText
        case .poor: return FormaColor.emberText
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "pl_PL"), value)
    }
}
