import MapKit
import Observation

@MainActor
@Observable
final class NearbyPlacesStore {
    private(set) var places: [MKMapItem] = []
    private(set) var isLoading = false
    private(set) var message: String?
    private var operation: MKLocalSearch?
    private var generation = UUID()
    private var lastLocation: CLLocation?
    private var lastAttempt: Date?

    func reset() {
        generation = UUID()
        operation?.cancel()
        places = []
        message = nil
        isLoading = false
        lastLocation = nil
        lastAttempt = nil
    }

    func refresh(near location: CLLocation?, now: Date = .now, force: Bool = false) async {
        guard let location, abs(now.timeIntervalSince(location.timestamp)) <= 30,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else {
            reset()
            message = "A fresh location is needed to find places near you."
            return
        }
        if !force, let lastAttempt {
            guard now.timeIntervalSince(lastAttempt) >= 60 else { return }
            if let lastLocation, location.distance(from: lastLocation) < 250, !places.isEmpty { return }
        }
        operation?.cancel()
        let id = UUID()
        generation = id
        lastAttempt = now
        lastLocation = location
        isLoading = true
        message = nil
        // Never retain places from a previous area while a new request is pending.
        places = []
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 750)
        let search = MKLocalSearch(request: request)
        operation = search
        do {
            let response = try await search.start()
            guard generation == id else { return }
            places = Array(response.mapItems.filter { $0.location.distance(from: location) <= 750 }
                .sorted { $0.location.distance(from: location) < $1.location.distance(from: location) }.prefix(12))
            if places.isEmpty { message = "No nearby places found. You can still search by name." }
        } catch {
            guard generation == id else { return }
            message = "Nearby places are unavailable. Check your connection and retry."
        }
        if generation == id { isLoading = false }
    }

    static func category(for place: MKMapItem) -> String {
        guard let category = place.pointOfInterestCategory else { return "Place" }
        switch category {
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .bakery: return "Bakery"
        case .store: return "Shop"
        case .library: return "Library"
        case .park: return "Park"
        case .museum: return "Museum"
        case .school, .university: return "Education"
        case .hotel: return "Hotel"
        case .hospital, .pharmacy: return "Health"
        case .parking: return "Parking"
        case .gasStation: return "Gas station"
        case .bank, .atm: return "Bank / ATM"
        default: return "Nearby place"
        }
    }
}
