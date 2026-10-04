import SwiftUI
import Contracts
import DesignSystem

/// The panel of an exercise that has no analysis yet: the same clean layout as the others (what it is, which muscles it
/// works) and an honest note that the technique check is not ready, with a way back to the search.
struct UnavailableStepView: View {
    let model: AnalysisModel

    var body: some View {
        if let exercise = model.selectedExercise {
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                Text(exercise.name)
                    .formaStyle(.title)
                    .foregroundStyle(FormaColor.ink)
                Text(exercise.muscleGroup)
                    .formaStyle(.caption)
                    .foregroundStyle(FormaColor.ink3)

                Label("Analiza techniki tego ćwiczenia jest w przygotowaniu", systemImage: "hourglass")
                    .formaStyle(.headline)
                    .foregroundStyle(FormaColor.moderateText)
                    .padding(FormaSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                if !exercise.summary.isEmpty {
                    Text(exercise.summary)
                        .formaStyle(.callout)
                        .foregroundStyle(FormaColor.ink2)
                        .padding(FormaSpacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }

                MuscleMapCard(exercise: exercise)

                Text("Dziś oceniamy technikę przysiadu, pompki, podciągania i dipów. To ćwiczenie możesz nadal robić w planie i z trenerem; wynik techniki pojawi się, gdy dodamy jego analizę.")
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)

                Button { model.back() } label: {
                    Label("Wybierz inne ćwiczenie", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            }
        }
    }
}
