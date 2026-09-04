import Observation

enum TravelMode: String, CaseIterable {
    case walking = "Walking"
    case driving = "Driving"
    var symbol: String { self == .walking ? "figure.walk" : "car.fill" }
}

/// App-owned services that future phone and CarPlay scenes can share.
/// Camera positions, sheets and other presentation state stay with their views.
@MainActor
@Observable
final class AppSession {
    let location = LocationStore()
    let preview = RoutePreviewStore()
    let nearby = NearbyPlacesStore()
    let workZones = WorkZoneStore()
    let offlineRoads = OfflineRoadStore()
    let trip: TripStore
    var mode: TravelMode = .walking

    init(preferences: RoutePreferences? = nil) {
        trip = TripStore(preferences: preferences ?? RoutePreferences())
    }
}
