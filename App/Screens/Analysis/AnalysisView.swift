import SwiftUI
import DesignSystem
import Onboarding

/// Analysis flow: exercise, framing instructions, capture, quality gate, processing, result.
/// Owner: Bartek.
struct AnalysisView: View {
    @State private var model = AnalysisModel()

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    stepContent
                        .padding(.top, FormaSpacing.l)
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
            .id(model.step)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: model.step)
    }

    private var topBar: some View {
        HStack {
            if model.canGoBack {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FormaColor.ink)
                        .frame(width: 44, height: 44)
                        .glassCapsule(interactive: true)
                }
                .accessibilityLabel("Wstecz")
            } else {
                SectionLabel("Analiza")
            }
            Spacer()
        }
        .padding(.top, FormaSpacing.l)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .exercise:
            ExerciseStepView(model: model)
        case .framing:
            FramingStepView(model: model)
        case .capture:
            CaptureStepView(model: model)
        case .quality:
            QualityStepView(model: model)
        case .processing:
            ProcessingStepView()
        case .result:
            ResultStepView(model: model)
        }
    }
}

#Preview {
    AnalysisView()
        .environment(AppStore(onboardingStorage: InMemoryOnboardingStorage()))
        .preferredColorScheme(.dark)
}
