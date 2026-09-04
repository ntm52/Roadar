import MapKit
import Observation

@MainActor
@Observable
final class RoutePreviewStore {
    var query = ""
    private(set) var results: [MKMapItem] = []
    private(set) var destination: MKMapItem?
    private(set) var routes: [MKRoute] = []
    var selectedRoute = 0
    private(set) var isSearching = false
    private(set) var isRouting = false
    private(set) var isWaitingForLocation = false
    private(set) var searchMessage: String?
    private(set) var routeMessage: String?
    private var search: MKLocalSearch?
    private var directions: MKDirections?
    private var searchID = UUID()
    private var routeID = UUID()

    var activeRoute: MKRoute? {
        routes.indices.contains(selectedRoute) ? routes[selectedRoute] : nil
    }

    func searchPlaces(in region: MKCoordinateRegion) async {
        search?.cancel()
        let id = UUID()
        searchID = id
        results = []
        searchMessage = nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { isSearching = false; return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = region
        let operation = MKLocalSearch(request: request)
        search = operation
        do {
            let response = try await operation.start()
            guard searchID == id else { return }
            results = response.mapItems
            if results.isEmpty { searchMessage = "No places found. Try a different name or address." }
        } catch {
            guard searchID == id else { return }
            searchMessage = "Search is unavailable. Check your connection and try again."
        }
        if searchID == id { isSearching = false }
    }

    func select(_ place: MKMapItem) {
        clearRoutes()
        destination = place
    }

    func clearRoutes() {
        routeID = UUID()
        directions?.cancel()
        routes = []
        selectedRoute = 0
        isRouting = false
        isWaitingForLocation = false
        routeMessage = nil
    }

    func clearDestination() {
        clearRoutes()
        destination = nil
    }

    func preview(from location: CLLocation?, driving: Bool) async {
        clearRoutes()
        guard let destination else { return }
        guard GuidanceEngine.accepts(location, at: .now), let location else {
            isWaitingForLocation = true
            routeMessage = Self.locationWaitMessage(location, at: .now)
            return
        }
        isWaitingForLocation = false
        let id = routeID
        let request = MKDirections.Request()
        request.source = MKMapItem(location: location, address: nil)
        request.destination = destination
        request.transportType = driving ? .automobile : .walking
        request.requestsAlternateRoutes = true
        request.departureDate = .now
        let operation = MKDirections(request: request)
        directions = operation
        isRouting = true
        do {
            let response = try await operation.calculate()
            guard routeID == id else { return }
            routes = response.routes.sorted { $0.expectedTravelTime < $1.expectedTravelTime }
            if routes.isEmpty { routeMessage = "No routes are available for this travel mode." }
        } catch {
            guard routeID == id else { return }
            routeMessage = "Couldn’t load routes. Check your connection or try another destination."
        }
        if routeID == id { isRouting = false }
    }

    static func locationWaitMessage(_ location: CLLocation?, at now: Date) -> String {
        guard let location, CLLocationCoordinate2DIsValid(location.coordinate) else {
            return "Finding your position for this route. Routes will appear automatically."
        }
        guard (-5...15).contains(now.timeIntervalSince(location.timestamp)) else {
            return "Refreshing your previous position. Routes will appear when a fresh location arrives."
        }
        return "Improving location accuracy for this route. If you’re indoors, try moving near a window or outside."
    }
}
