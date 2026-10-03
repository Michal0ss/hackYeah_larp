import Foundation
import CoreLocation
import MapKit
import Observation

/// One physiotherapist found in Apple Maps. Real search results, never invented.
struct PhysioPlace: Identifiable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let mapItem: MKMapItem

    /// "850 m" or "1,6 km".
    var distanceText: String {
        distanceMeters < 1000
            ? "\(Int((distanceMeters / 10).rounded()) * 10) m"
            : (distanceMeters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }
}

/// Finds physiotherapists within `radiusMeters` of the user with MapKit local search.
/// The location is read once when needed and used only for this search: the query goes to Apple Maps,
/// nothing is sent to our servers and nothing is stored.
@Observable
@MainActor
final class PhysioSearch: NSObject, CLLocationManagerDelegate {
    enum State {
        case idle
        /// Waiting for the system location prompt or for a fix.
        case locating
        case searching
        case results([PhysioPlace], userLocation: CLLocationCoordinate2D)
        case empty
        /// Location refused or restricted: the user can still search in the Maps app.
        case denied
        case failed
    }

    static let radiusMeters: Double = 5000
    static let query = "fizjoterapeuta"

    private(set) var state: State = .idle
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            state = .denied
        case .notDetermined:
            state = .locating
            manager.requestWhenInUseAuthorization()
        default:
            state = .locating
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted: self.state = .denied
            case .authorizedWhenInUse, .authorizedAlways:
                if case .locating = self.state { manager.requestLocation() }
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.search(around: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if (error as? CLError)?.code == .denied { self.state = .denied } else { self.state = .failed }
        }
    }

    /// "Foksal 16, Warszawa" instead of the full postal line with the country.
    private static func shortAddress(_ placemark: MKPlacemark) -> String? {
        let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street, placemark.locality ?? ""].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Search

    private func search(around location: CLLocation) async {
        state = .searching
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = Self.query
        request.region = MKCoordinateRegion(center: location.coordinate,
                                            latitudinalMeters: Self.radiusMeters * 2,
                                            longitudinalMeters: Self.radiusMeters * 2)
        request.resultTypes = .pointOfInterest
        do {
            let response = try await MKLocalSearch(request: request).start()
            let places = response.mapItems.compactMap { item -> PhysioPlace? in
                guard let name = item.name, let point = item.placemark.location else { return nil }
                let distance = location.distance(from: point)
                guard distance <= Self.radiusMeters else { return nil }
                return PhysioPlace(name: name, address: Self.shortAddress(item.placemark), coordinate: point.coordinate,
                                   distanceMeters: distance, mapItem: item)
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            state = places.isEmpty ? .empty : .results(Array(places.prefix(8)), userLocation: location.coordinate)
        } catch {
            state = .failed
        }
    }
}
