import CoreLocation
import Observation

@MainActor
@Observable
final class LocationStore: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var isActive = false
    private var isNavigating = false
    private var isDriving = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var accuracy: CLAccuracyAuthorization = .fullAccuracy
    private(set) var location: CLLocation?
    private(set) var heading: Double?
    private(set) var errorMessage: String?

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func setActive(_ active: Bool) {
        isActive = active
        updateMonitoring()
    }

    func setDriving(_ driving: Bool) {
        isDriving = driving
        manager.activityType = driving ? .automotiveNavigation : .fitness
        updateDistanceFilter()
    }

    func setNavigating(_ navigating: Bool) {
        isNavigating = navigating
        updateDistanceFilter()
    }

    private func updateDistanceFilter() {
        // Arrival requires distinct fixes even when the user has stopped at the endpoint.
        manager.distanceFilter = isNavigating ? kCLDistanceFilterNone : (isDriving ? 10 : 5)
    }

    private func refreshAuthorization() {
        authorization = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization
        updateMonitoring()
    }

    private func updateMonitoring() {
        if isAuthorized && isActive {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        } else {
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            heading = nil
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
        guard isActive, isAuthorized,
              let latest = locations.filter({ CLLocationCoordinate2DIsValid($0.coordinate) &&
                  $0.horizontalAccuracy >= 0 && (-5...30).contains(Date.now.timeIntervalSince($0.timestamp)) })
                .max(by: { $0.timestamp < $1.timestamp }),
              location == nil || latest.timestamp > location!.timestamp else { return }
        location = latest
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0, newHeading.headingAccuracy <= 35 else { heading = nil; return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
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
