import Observation

enum TravelMode: String, CaseIterable {
    case walking = "Walking"
    case driving = "Driving"
    var symbol: String { self == .walking ? "figure.walk" : "car.fill" }
}

/// Services shared by the phone and CarPlay, including CarPlay-only launches.
/// Camera positions, sheets and other presentation state stay with their views.
@MainActor
@Observable
final class AppSession {
    static let shared = AppSession()
    private(set) var phoneActive = false
    private(set) var carPlayConnected = false
    private var guidanceTask: Task<Void, Never>?

    var guidanceEnabled: Bool { phoneActive || carPlayConnected }

    func setPhoneActive(_ active: Bool) {
        phoneActive = active
        updateActivity()
    }

    func setCarPlayConnected(_ connected: Bool) {
        carPlayConnected = connected
        if connected {
            if trip.engine?.driving == false { trip.end() }
            mode = .driving
        }
        updateActivity()
    }

    private func updateActivity() {
        location.setCarPlayConnected(carPlayConnected)
        location.setActive(guidanceEnabled)
        trip.setForeground(guidanceEnabled)
        if guidanceEnabled && guidanceTask == nil {
            guidanceTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.location.setDriving(self.mode == .driving)
                    self.location.setNavigating(self.trip.isActive)
                    await self.trip.tick(self.location.isAuthorized ? self.location.location : nil)
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        } else if !guidanceEnabled {
            guidanceTask?.cancel()
            guidanceTask = nil
        }
    }
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
