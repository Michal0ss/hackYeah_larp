import SwiftUI
import Contracts
import DesignSystem

/// Step 1: pick which exercise to analyze (demo: only the squat supports it).
struct ExerciseStepView: View {
    @Environment(AppStore.self) private var store
    let model: AnalysisModel

    private var analyzable: [ExerciseItem] {
        store.catalog.filter(\.supportsAnalysis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            Text("Co dziś analizujemy?")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)
            Text("Nagranie z boku, aplikacja oceni technikę i policzy powtórzenia.")
                .formaStyle(.callout)
                .foregroundStyle(FormaColor.ink2)

            if analyzable.isEmpty {
                Text("Żadne ćwiczenie w katalogu nie obsługuje jeszcze analizy.")
                    .formaStyle(.callout)
                    .foregroundStyle(FormaColor.ink3)
                    .padding(FormaSpacing.xl)
                    .glassCard()
            } else {
                VStack(spacing: FormaSpacing.m) {
                    ForEach(analyzable) { exercise in
                        Button { model.choose(exercise) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                                    Text(exercise.muscleGroup).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(FormaColor.ink3)
                            }
                            .padding(FormaSpacing.l)
                            .glassCard()
                        }
                        .buttonStyle(.formaPress)
                    }
                }
            }
        }
    }
}
