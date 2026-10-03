import SwiftUI
import DesignSystem
import Insights

/// "Warto rozważyć konsultację": why the signal appeared, what to do, and a way to find a physiotherapist.
/// A signal, never a diagnosis. Present it as a sheet from any screen. Owner: Wiktor.
struct CareView: View {
    let assessment: CareAssessment
    /// True when the evidence comes from sample data; shows the "Dane przykładowe" badge.
    var simulated = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: FormaSpacing.l) {
                        topBar
                        hero
                        evidence
                        steps
                        InfoBanner(systemImage: "info.circle.fill") {
                            Text(CarePathway.disclaimer)
                                .formaStyle(.footnote)
                                .foregroundStyle(FormaColor.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        NavigationLink {
                            PhysioResultsView()
                        } label: {
                            Label("Znajdź fizjoterapeutę w pobliżu", systemImage: "mappin.and.ellipse")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.formaPrimary)
                        Button {
                            dismiss()
                        } label: {
                            Text("Wróć").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.formaGlass)
                    }
                    .padding(.horizontal, FormaSpacing.screen)
                    .padding(.top, FormaSpacing.l)
                    .padding(.bottom, FormaSpacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Opieka")
                if simulated { SimulatedBadge() }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FormaColor.ink)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: true)
            }
            .accessibilityLabel("Zamknij")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 13, weight: .bold))
                Text("Sygnał, nie diagnoza").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(FormaColor.restText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(FormaColor.rest.opacity(0.16), in: Capsule())
            .overlay { Capsule().strokeBorder(FormaColor.rest.opacity(0.4), lineWidth: 1) }
            .accessibilityElement(children: .combine)

            Text("Warto rozważyć konsultację")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(assessment.flag.reason)
                .formaStyle(.body)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var evidence: some View {
        if !assessment.evidence.isEmpty {
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                SectionLabel("Skąd ten sygnał")
                VStack(spacing: 0) {
                    ForEach(Array(assessment.evidence.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.m) {
                            Text(item.date, format: .dateTime.day().month(.abbreviated))
                                .formaStyle(.subheadline)
                                .foregroundStyle(FormaColor.ink3)
                                .frame(width: 56, alignment: .leading)
                            Text(item.text)
                                .formaStyle(.body)
                                .foregroundStyle(FormaColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if let score = item.score {
                                NumberText("\(score)", size: 22, color: FormaColor.ink2)
                            }
                        }
                        .padding(.vertical, FormaSpacing.s)
                        .accessibilityElement(children: .combine)
                        if index < assessment.evidence.count - 1 { Divider().overlay(FormaColor.line) }
                    }
                }
            }
            .padding(FormaSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Co możesz zrobić")
            ForEach(Array(assessment.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: FormaSpacing.m) {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FormaColor.voltText)
                        .frame(width: 28, height: 28)
                        .background(FormaColor.volt.opacity(0.15), in: Circle())
                        .overlay { Circle().strokeBorder(FormaColor.volt.opacity(0.36), lineWidth: 1) }
                        .accessibilityHidden(true)
                    Text(step)
                        .formaStyle(.body)
                        .foregroundStyle(FormaColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Krok \(index + 1): \(step)")
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
