import CoreLocation
import Observation

@MainActor
@Observable
final class LocationStore: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var isActive = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var accuracy: CLAccuracyAuthorization = .fullAccuracy
    private(set) var location: CLLocation?
    private(set) var errorMessage: String?

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        authorization = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func setActive(_ active: Bool) {
        isActive = active
        refreshAuthorization()
    }

    func setDriving(_ driving: Bool) {
        manager.activityType = driving ? .automotiveNavigation : .fitness
        manager.distanceFilter = driving ? 10 : 5
    }

    private func refreshAuthorization() {
        authorization = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization
        if isAuthorized && isActive {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
        if !isAuthorized {
            location = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        errorMessage = nil
        refreshAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last(where: { $0.horizontalAccuracy >= 0 }),
              abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        location = latest
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .denied {
            refreshAuthorization()
        }
        errorMessage = "Location is temporarily unavailable. You can still explore the map."
    }

    func status(at date: Date) -> String? {
        switch authorization {
        case .notDetermined:
            return "Use your location to keep the minimap centered on you."
        case .denied:
            return "Location access is off. Enable it in Settings to follow your position."
        case .restricted:
            return "Location access is restricted on this device. You can still explore the map."
        default:
            break
        }
        if let errorMessage { return errorMessage }
        if accuracy == .reducedAccuracy {
            return "Approximate location. Enable Precise Location in Settings for a closer view."
        }
        guard let location else { return "Finding your location… You can explore while we wait." }
        if date.timeIntervalSince(location.timestamp) > 30 {
            return "Location hasn't updated recently. Your position may be out of date."
        }
        if location.horizontalAccuracy > 65 {
            return "Weak location signal. Your position may be approximate."
        }
        return nil
    }
}
