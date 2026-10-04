import SwiftUI
import Contracts
import DesignSystem

/// Step 1: find the exercise to analyse. All exercises of the app can be searched; the ones with analysis come first,
/// the others open a panel that says what is missing.
struct ExerciseStepView: View {
    @Environment(AppStore.self) private var store
    let model: AnalysisModel

    @State private var query = ""

    private var matches: [ExerciseItem] {
        let words = Self.key(query).split(separator: " ").map(String.init)
        let found = store.catalog.filter { exercise in
            let haystack = Self.key("\(exercise.name) \(exercise.muscleGroup)")
            return words.allSatisfy { haystack.contains($0) }
        }
        // Analysis first, then by name.
        return found.sorted { a, b in
            if a.supportsAnalysis != b.supportsAnalysis { return a.supportsAnalysis }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            Text("Co dziś analizujemy?")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)
            Text("Wyszukaj ćwiczenie. Technikę oceniamy dziś w przysiadzie, pompce, podciąganiu i dipach, resztę dochodzimy.")
                .formaStyle(.callout)
                .foregroundStyle(FormaColor.ink2)

            FormaSearchField(placeholder: "Szukaj ćwiczenia lub partii mięśni", text: $query)

            if matches.isEmpty {
                Text(store.catalog.isEmpty ? "Katalog ćwiczeń jest pusty." : "Nie ma takiego ćwiczenia. Spróbuj innej nazwy albo partii mięśni.")
                    .formaStyle(.callout)
                    .foregroundStyle(FormaColor.ink3)
                    .padding(FormaSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                LazyVStack(spacing: FormaSpacing.m) {
                    ForEach(matches) { exercise in
                        Button {
                            if exercise.supportsAnalysis { model.choose(exercise) } else { model.chooseUnavailable(exercise) }
                        } label: { row(exercise) }
                        .buttonStyle(.formaPress)
                    }
                }
            }
        }
    }

    private func row(_ exercise: ExerciseItem) -> some View {
        HStack(spacing: FormaSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text(exercise.muscleGroup).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
            Spacer()
            if exercise.supportsAnalysis {
                Text("Analiza")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(FormaColor.onVolt)
                    .padding(.horizontal, 10).frame(height: 24).background(FormaColor.volt, in: Capsule())
            } else {
                Text("Wkrótce")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(FormaColor.ink3)
                    .padding(.horizontal, 10).frame(height: 24).background(FormaColor.well, in: Capsule())
            }
            Image(systemName: "chevron.right").foregroundStyle(FormaColor.ink3)
        }
        .padding(FormaSpacing.l)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint(exercise.supportsAnalysis ? "Otwiera analizę techniki" : "Analiza tego ćwiczenia jeszcze nie jest gotowa")
    }

    /// Lower case without accents (ł counts as l), so "przysiad", "Pośladki" and "posladki" all find what they should.
    static func key(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl"))
            .replacingOccurrences(of: "ł", with: "l")
    }
}
