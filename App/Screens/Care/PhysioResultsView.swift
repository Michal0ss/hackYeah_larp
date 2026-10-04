import SwiftUI
import MapKit
import DesignSystem
import Insights

/// "Fizjoterapeuci w pobliżu": real results from Apple Maps within 5 km. We do not recommend any practice.
/// Owner: Wiktor.
struct PhysioResultsView: View {
    @State private var search = PhysioSearch()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AmbientBackground()
            VerticalScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    VStack(alignment: .leading, spacing: FormaSpacing.s) {
                        SectionLabel("Opieka")
                        Text("Fizjoterapeuci w pobliżu")
                            .formaStyle(.largeTitle)
                            .foregroundStyle(FormaColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Wyszukiwanie w Mapach Apple w promieniu 5 km. Nie polecamy konkretnych gabinetów. Twoja lokalizacja służy tylko do tego wyszukiwania i nie trafia do nas.")
                            .formaStyle(.subheadline)
                            .foregroundStyle(FormaColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                    Text("Na wizytę możesz pokazać wynik analizy: zapisujemy tylko liczby, nie film.")
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CarePathway.disclaimer)
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { if case .idle = search.state { search.start() } }
    }

    @ViewBuilder
    private var content: some View {
        switch search.state {
        case .idle, .locating:
            statusCard(icon: "location.fill", title: "Ustalam, gdzie jesteś",
                       text: "Jeśli system zapyta o lokalizację, wybierz „Podczas używania aplikacji”.", showSpinner: true)
        case .searching:
            statusCard(icon: "magnifyingglass", title: "Szukam w pobliżu", text: "To potrwa chwilę.", showSpinner: true)
        case let .results(places, userLocation):
            ResultsMap(places: places, userLocation: userLocation)
            VStack(spacing: FormaSpacing.m) {
                ForEach(places) { place in PlaceRow(place: place) }
            }
            Button {
                MKMapItem.openMaps(with: places.map(\.mapItem))
            } label: {
                Label("Otwórz w Mapach", systemImage: "map").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
        case .empty:
            statusCard(icon: "mappin.slash", title: "Nic nie znaleziono w promieniu 5 km",
                       text: "Spróbuj wyszukać szerzej w aplikacji Mapy.")
            openInMapsButton
        case .denied:
            statusCard(icon: "location.slash", title: "Brak dostępu do lokalizacji",
                       text: "Możesz zmienić zgodę w Ustawieniach albo wyszukać fizjoterapeutę bezpośrednio w aplikacji Mapy.")
            openInMapsButton
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Otwórz Ustawienia", systemImage: "gearshape").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
        case .failed:
            statusCard(icon: "wifi.exclamationmark", title: "Nie udało się wyszukać",
                       text: "Sprawdź połączenie z internetem i spróbuj ponownie.")
            Button {
                search.start()
            } label: {
                Label("Spróbuj ponownie", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
            openInMapsButton
        }
    }

    private var openInMapsButton: some View {
        Button {
            if let url = URL(string: "https://maps.apple.com/?q=\(PhysioSearch.query)") { openURL(url) }
        } label: {
            Label("Szukaj w Mapach", systemImage: "map").frame(maxWidth: .infinity)
        }
        .buttonStyle(.formaGlass)
    }

    private func statusCard(icon: String, title: String, text: String, showSpinner: Bool = false) -> some View {
        HStack(alignment: .top, spacing: FormaSpacing.m) {
            IconBadge(systemImage: icon, fill: FormaColor.rest, icon: FormaColor.restText, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text(text)
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if showSpinner { ProgressView() }
        }
        .padding(FormaSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

private struct ResultsMap: View {
    let places: [PhysioPlace]
    let userLocation: CLLocationCoordinate2D

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: userLocation, latitudinalMeters: 11_000,
                                                        longitudinalMeters: 11_000))) {
            UserAnnotation()
            ForEach(places) { place in
                Marker(place.name, coordinate: place.coordinate)
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: FormaRadius.lg, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: FormaRadius.lg, style: .continuous).strokeBorder(FormaColor.line, lineWidth: 1) }
        .accessibilityLabel("Mapa z wynikami wyszukiwania, \(places.count) miejsc w pobliżu")
    }
}

private struct PlaceRow: View {
    let place: PhysioPlace

    var body: some View {
        HStack(alignment: .center, spacing: FormaSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .formaStyle(.headline)
                    .foregroundStyle(FormaColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(place.distanceText + (place.address.map { " · \($0)" } ?? ""))
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                place.mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
            } label: {
                Label("Trasa", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FormaColor.voltText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Trasa do \(place.name)")
        }
        .padding(FormaSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: FormaRadius.md)
    }
}
