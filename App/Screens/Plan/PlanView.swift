import SwiftUI

/// Owner: Maciek (Michał takes the UI if Maciek is busy with the generator).
struct PlanView: View {
    var body: some View {
        PlaceholderScreen(title: "Plan", owner: "Maciek",
                          summary: "Tydzień z sesjami, szczegóły sesji, oznaczanie wykonania.",
                          symbol: "calendar")
    }
}
