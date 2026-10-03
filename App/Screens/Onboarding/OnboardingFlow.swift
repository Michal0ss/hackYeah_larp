import SwiftUI
import Contracts
import DesignSystem
import Onboarding

/// First-run flow: goal, about you, equipment, health history, screening, Apple Health, plan generation.
/// Owner: Michał.
struct OnboardingFlow: View {
    @State private var model: OnboardingModel
    private let onFinish: (OnboardingResult) -> Void

    init(services: AppServices, onFinish: @escaping (OnboardingResult) -> Void) {
        _model = State(initialValue: OnboardingModel(health: services.healthAuthorization,
                                                     generator: services.planGenerator))
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    if let number = model.step.number, model.step != .goal {
                        SegmentedProgress(total: OnboardingStep.numberedCount, current: number)
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                    }
                    stepContent
                        .padding(.top, model.step == .goal ? 56 : 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .id(model.step)
            .transition(.opacity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .task(id: model.step) {
            if model.step == .generating { await model.startGeneration() }
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            if model.canGoBack {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { model.back() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FormaColor.ink)
                        .frame(width: 44, height: 44)
                        .glassCapsule(interactive: true)
                }
                .accessibilityLabel("Wstecz")
            } else {
                logo
            }
            Spacer()
            if model.step != .goal, let label = model.step.label {
                Text(label).formaStyle(.subheadline).fontWeight(.semibold).foregroundStyle(FormaColor.ink2)
            }
        }
        .frame(minHeight: 44)
    }

    private var logo: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FormaColor.onVolt)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [Color(hex: 0xDDFF70), FormaColor.volt], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Forma")
                .font(.formaNumber(26))
                .foregroundStyle(FormaColor.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Forma")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .goal: GoalStepView(model: model)
        case .aboutYou: AboutYouStepView(model: model)
        case .equipment: EquipmentStepView(model: model)
        case .medicalHistory: MedicalHistoryStepView(model: model)
        case .screening: ScreeningStepView(model: model)
        case .appleHealth: AppleHealthStepView(model: model)
        case .generating: GeneratingStepView(model: model)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionBar: some View {
        let content = VStack(spacing: 10) { buttons }
        if hasActions {
            content
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: FormaColor.background, location: 0.5)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
        }
    }

    private var hasActions: Bool {
        switch model.step {
        case .generating: return model.generation == .done || isFailed
        default: return true
        }
    }

    private var isFailed: Bool {
        if case .failed = model.generation { return true }
        return false
    }

    @ViewBuilder
    private var buttons: some View {
        switch model.step {
        case .appleHealth:
            Button {
                Task { await withAnimationAsync { await model.requestHealthAccess() } }
            } label: {
                HStack(spacing: 8) {
                    if model.isRequestingHealthAccess { ProgressView().tint(FormaColor.onVolt) }
                    Text("Zezwól na dostęp")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
            .disabled(model.isRequestingHealthAccess)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { model.useSampleHealthData() }
            } label: {
                Label("Użyj danych przykładowych", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
            .disabled(model.isRequestingHealthAccess)

        case .generating:
            if isFailed {
                Button {
                    Task { await model.retryGeneration() }
                } label: {
                    Text("Spróbuj ponownie").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaPrimary)
            } else {
                Button {
                    if let result = model.makeResult() { onFinish(result) }
                } label: {
                    Text("Przejdź do Dziś").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaPrimary)
            }

        default:
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { model.advance() }
            } label: {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
            .disabled(!model.canAdvance)

            if let skip = model.step.skipTitle {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { model.skip() }
                } label: {
                    Text(skip).frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            }
        }
    }

    private var primaryTitle: String {
        if model.step == .screening, case .consult = model.screeningResult { return "Rozumiem, dalej" }
        return "Dalej"
    }

    private func withAnimationAsync(_ work: () async -> Void) async {
        await work()
    }
}

#Preview {
    OnboardingFlow(services: AppServices()) { _ in }
        .preferredColorScheme(.dark)
}
