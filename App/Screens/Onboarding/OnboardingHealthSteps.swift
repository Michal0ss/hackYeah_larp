import SwiftUI
import Contracts
import DesignSystem
import Onboarding

/// Step 4: injuries and conditions. Optional, stays on the phone.
struct MedicalHistoryStepView: View {
    @Bindable var model: OnboardingModel
    @State private var injuriesOpen = true
    @State private var conditionsOpen = false

    private var health: HealthHistory { model.draft.health }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingHeader(overline: "Historia medyczna", title: "Twoja historia zdrowia",
                             subtitle: "Opcjonalnie. Niczego nie diagnozujemy.")

            InfoBanner(systemImage: "lock.shield.fill") {
                (Text("Zostaje na telefonie. ").fontWeight(.semibold).foregroundColor(FormaColor.ink)
                    + Text("Trener AI dostaje tylko listę ćwiczeń do pominięcia.").foregroundColor(FormaColor.ink2))
                    .formaStyle(.footnote)
            }

            DisclosureCard(title: "Kontuzje i urazy", summary: health.injurySummary, systemImage: "bandage.fill",
                           fill: FormaColor.ember, icon: FormaColor.emberText, isExpanded: $injuriesOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Zaznacz miejsca, które kiedykolwiek sprawiały problem.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                    FlowLayout(spacing: 8) {
                        ForEach(BodyArea.allCases, id: \.self) { area in
                            PillOption(area.title, isSelected: health.injuries.contains(area), showsCheck: true) {
                                model.draft.health.toggleInjury(area)
                            }
                        }
                    }
                    if !health.injuries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kiedy ostatnio?").formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                            HStack(spacing: 6) {
                                ForEach(InjuryRecency.allCases, id: \.self) { recency in
                                    PillOption(recency.title, isSelected: health.injuryRecency == recency, expands: true) {
                                        model.draft.health.injuryRecency = recency
                                    }
                                }
                            }
                        }
                    }
                }
            }

            DisclosureCard(title: "Choroby i stany", summary: health.conditionSummary, systemImage: "stethoscope",
                           fill: FormaColor.rest, icon: FormaColor.restText, isExpanded: $conditionsOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dobrowolnie. Pomaga dobrać intensywność.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                    FlowLayout(spacing: 8) {
                        ForEach(HealthCondition.allCases, id: \.self) { condition in
                            PillOption(condition.title, isSelected: health.conditions.contains(condition), showsCheck: true) {
                                model.draft.health.toggleCondition(condition)
                            }
                        }
                        PillOption("Nic z powyższych", isSelected: health.noConditions, showsCheck: true) {
                            model.draft.health.selectNoConditions()
                        }
                    }
                }
            }

            Text("Podajesz to dobrowolnie. Zmienisz to w każdej chwili w profilu. To nie jest porada medyczna.")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
        }
    }
}

/// Step 5: screening questions with a live result.
struct ScreeningStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingHeader(overline: "Przeciwwskazania", title: "Zanim zaczniesz ćwiczyć",
                             subtitle: "Czy dotyczy Cię któreś z poniższych?")

            resultCard
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.screeningResult)

            VStack(spacing: 0) {
                ForEach(Array(ScreeningQuestion.allCases.enumerated()), id: \.element) { index, question in
                    HStack(spacing: 10) {
                        Text(question.text)
                            .formaStyle(.subheadline)
                            .foregroundStyle(FormaColor.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        YesNoControl(selection: model.draft.health.answer(for: question), label: question.text) { yes in
                            model.draft.health.answer(question, yes)
                        }
                    }
                    .frame(minHeight: 56)
                    if index < ScreeningQuestion.allCases.count - 1 {
                        Divider().overlay(FormaColor.line)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .glassCard()

            Text("Standardowe pytania przesiewowe przed aktywnością. To nie jest diagnoza ani porada medyczna. Odpowiedzi zostają na telefonie.")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        switch model.screeningResult {
        case .incomplete:
            InfoBanner(systemImage: "questionmark.circle.fill", tint: FormaColor.ink2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Odpowiedz Tak lub Nie").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                    Text("Wystarczy 6 kliknięć. Możesz też odpowiedzieć później.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                }
            }
        case .clear:
            InfoBanner(systemImage: "checkmark.shield.fill", tint: FormaColor.goText) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Brak sygnałów ostrożności").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                    Text("Zaczynamy standardowo, według celu i poziomu.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                }
            }
        case .adapt(let omit):
            InfoBanner(systemImage: "slider.horizontal.3", tint: FormaColor.moderateText) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Dostosujemy plan").foregroundStyle(FormaColor.moderateText)
                    Text("Pomijamy: " + omit.map(\.displayName).joined(separator: ", "))
                        .formaStyle(.headline).foregroundStyle(FormaColor.ink)
                }
            }
        case .consult(let omit):
            VStack(alignment: .leading, spacing: 8) {
                Label("Warto rozważyć konsultację", systemImage: "stethoscope")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FormaColor.restText)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(FormaColor.rest.opacity(0.17), in: Capsule())
                    .overlay { Capsule().strokeBorder(FormaColor.rest.opacity(0.4), lineWidth: 1) }
                Text("Porozmawiaj z lekarzem przed pierwszym treningiem")
                    .formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text("To nie diagnoza, tylko ostrożność: któraś z odpowiedzi to sygnał, że warto zapytać specjalistę. Na start zaplanujemy lżejsze sesje. W nagłej sytuacji lub przy silnym bólu dzwoń pod 112.")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !omit.isEmpty {
                    Text("Pomijamy: " + omit.map(\.displayName).joined(separator: ", "))
                        .formaStyle(.footnote).fontWeight(.semibold).foregroundStyle(FormaColor.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 24)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Step 6: Apple Health.
struct AppleHealthStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(FormaColor.ember.opacity(0.16))
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(FormaColor.ember.opacity(0.4), lineWidth: 1)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(FormaColor.emberText)
                }
                .frame(width: 76, height: 76)
                .shadow(color: FormaColor.ember.opacity(0.35), radius: 18)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Opcjonalnie, ale warto")
                    Text("Połącz Apple Health")
                        .formaStyle(.title)
                        .foregroundStyle(FormaColor.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            Text("Odczytamy dane tylko po to, żeby codziennie podpowiadać, czy trenować mocniej, lżej, czy odpuścić.")
                .formaStyle(.callout)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                row(symbol: "bed.double.fill", fill: FormaColor.rest, icon: FormaColor.restText,
                    title: "Sen", text: "Krótka noc to powód, żeby dziś trenować lżej.")
                Divider().overlay(FormaColor.line)
                row(symbol: "heart.fill", fill: FormaColor.ember, icon: FormaColor.emberText,
                    title: "Tętno spoczynkowe", text: "Podwyższone względem Twojej normy bywa sygnałem zmęczenia.")
                Divider().overlay(FormaColor.line)
                row(symbol: "waveform.path.ecg", fill: FormaColor.volt, icon: FormaColor.voltText,
                    title: "Zmienność rytmu serca (HRV)", text: "Porównujemy z Twoją średnią z ostatnich dni.")
                Divider().overlay(FormaColor.line)
                row(symbol: "figure.walk", fill: FormaColor.moderate, icon: FormaColor.moderateText,
                    title: "Aktywność", text: "Kroki, kalorie i dystans pokażemy w panelu Dane zdrowotne.")
            }
            .padding(.horizontal, 16)
            .glassCard()

            InfoBanner(systemImage: "lock.shield.fill") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dane zostają na telefonie").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                    Text("Do trenera AI trafiają tylko podsumowania, i tylko za Twoją zgodą. Nie służą do reklam. Dostęp cofniesz w Ustawieniach w dowolnej chwili.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let notice = model.healthAccessNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.moderateText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(symbol: String, fill: Color, icon: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: symbol, fill: fill, icon: icon, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text(text).formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Wraps its children onto several lines (body areas, conditions).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
