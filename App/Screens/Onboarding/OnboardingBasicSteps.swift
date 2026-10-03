import SwiftUI
import Contracts
import DesignSystem
import Onboarding

/// Step 1: goal.
struct GoalStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Twój trener, plan i doradca.")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(FormaColor.ink)
                    .frame(maxWidth: 290, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text("Twoje dane mówią, co masz dziś zrobić.")
                    .formaStyle(.body)
                    .foregroundStyle(FormaColor.ink2)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Jaki jest Twój cel?")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        SelectableTile(title: goal.title, subtitle: goal.subtitle, systemImage: goal.symbol,
                                       isSelected: model.draft.goal == goal) {
                            model.draft.goal = goal
                        }
                    }
                }
            }
        }
    }
}

/// Step 2: level, days per week, session length.
struct AboutYouStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(title: "Kilka pytań o Ciebie",
                             subtitle: "Dzięki temu plan będzie pasował do Twojego tygodnia.")

            OnboardingSection("Poziom") {
                HStack(spacing: 8) {
                    ForEach(TrainingLevel.allCases, id: \.self) { level in
                        PillOption(level.title, isSelected: model.draft.level == level, expands: true) {
                            model.draft.level = level
                        }
                    }
                }
            }

            OnboardingSection("Dni w tygodniu", trailing: {
                NumberText("\(model.draft.daysPerWeek)", size: 20, color: FormaColor.voltText)
            }) {
                HStack(spacing: 8) {
                    ForEach(OnboardingDraft.dayOptions, id: \.self) { days in
                        PillOption("\(days)", isSelected: model.draft.daysPerWeek == days, expands: true) {
                            model.draft.setDays(days)
                        }
                    }
                }
            }

            OnboardingSection("Czas jednej sesji", trailing: {
                Text("\(model.draft.sessionMinutes) min")
                    .formaStyle(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(FormaColor.ink2)
            }) {
                HStack(spacing: 8) {
                    ForEach(OnboardingDraft.minuteOptions, id: \.self) { minutes in
                        PillOption("\(minutes)", isSelected: model.draft.sessionMinutes == minutes, expands: true) {
                            model.draft.setMinutes(minutes)
                        }
                    }
                }
            }
        }
    }
}

/// Step 3: equipment and things to avoid.
struct EquipmentStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(title: "Czym ćwiczysz?", subtitle: "Zaznacz wszystko, co masz pod ręką.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(GearItem.allCases, id: \.self) { item in
                    SelectableTile(title: item.title, systemImage: item.symbol,
                                   isSelected: model.draft.gear.contains(item), minHeight: 104) {
                        model.draft.toggleGear(item)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Czego unikać?").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text("Opcjonalnie. Napisz własnymi słowami, nie oceniamy tego medycznie.")
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
                    .padding(.bottom, 6)
                FormaTextField("Czego unikać", placeholder: "np. skoki, głębokie wykroki", text: $model.draft.avoid)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }
}
