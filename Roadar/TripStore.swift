import MapKit
import Observation

@MainActor
@Observable
final class TripStore {
    private(set) var destination: MKMapItem?
    private(set) var route: MKRoute?
    private(set) var engine: GuidanceEngine?
    private(set) var isRefreshing = false
    private(set) var proposal: MKRoute?
    private(set) var message: String?
    private(set) var estimateDate: Date?
    var policy = ReroutePolicy()
    private var driving = false
    private var foreground = true
    private var requestID = UUID()
    private var directions: MKDirections?
    private var lastRequest = Date.distantPast
    private var lastSwitch = Date.distantPast
    private var proposalOrigin: CLLocation?
    private var proposalDate: Date?
    var isActive: Bool { route != nil }

    func start(route: MKRoute, destination: MKMapItem, driving: Bool, location: CLLocation?, at now: Date = .now) {
        guard GuidanceEngine.accepts(location, at: now), let location else {
            message = "Wait for a fresh, precise location before starting guidance."; return
        }
        let geometry = GuidanceRoute(route)
        guard geometry.length > 0,
              let start = geometry.coordinates.first,
              location.distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)) <= 100 else {
            message = "Your starting position has changed. Refresh the route before starting."; return
        }
        end()
        self.destination = destination
        self.driving = driving
        install(route, at: now)
        lastRequest = now
        update(location, at: now)
    }

    func end() {
        cancelRequest()
        destination = nil
        route = nil
        engine = nil
        proposal = nil
        message = nil
        estimateDate = nil
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if !active {
            cancelRequest()
            proposal = nil
            engine?.invalidate()
            message = "Guidance paused. Return to Roadar for a fresh location."
        } else if isActive { message = nil }
    }

    func update(_ location: CLLocation?, at now: Date = .now) {
        guard isActive, foreground else { return }
        engine?.update(location, at: now)
        if let origin = proposalOrigin, let location,
           location.distance(from: origin) > 75 || now.timeIntervalSince(proposalDate ?? .distantPast) > 30 {
            proposal = nil
        }
        if engine?.state == .arrived {
            cancelRequest()
            proposal = nil
            message = nil
        }
    }

    /// Called on a timer so stale fixes also invalidate guidance when updates stop.
    func tick(_ location: CLLocation?, at now: Date = .now) async {
        update(location, at: now)
        guard foreground, let engine, engine.state != .arrived,
              GuidanceEngine.accepts(location, at: now), !isRefreshing else { return }
        let delay = engine.state == .offRoute ? 30.0 : 120.0
        guard now.timeIntervalSince(lastRequest) >= delay,
              engine.state == .following || engine.state == .offRoute else { return }
        await refresh(from: location, at: now)
    }

    func refresh(from location: CLLocation?, at now: Date = .now, forceRecovery: Bool = false) async {
        guard foreground, isActive, engine?.state != .arrived, !isRefreshing,
              let destination, GuidanceEngine.accepts(location, at: now), let location else { return }
        // Manual requests also observe a short retry limit.
        guard now.timeIntervalSince(lastRequest) >= 30 else {
            message = "Route checks are spaced at least 30 seconds apart."; return
        }
        lastRequest = now
        proposal = nil
        let recovery = forceRecovery || engine?.state == .offRoute
        let id = UUID()
        requestID = id
        let request = MKDirections.Request()
        request.source = MKMapItem(location: location, address: nil)
        request.destination = destination
        request.transportType = driving ? .automobile : .walking
        request.requestsAlternateRoutes = true
        request.departureDate = now
        let operation = MKDirections(request: request)
        directions = operation
        isRefreshing = true
        message = recovery ? "Off route · Finding a new route…" : "Checking available routes…"
        defer { if requestID == id { isRefreshing = false } }
        do {
            let response = try await operation.calculate()
            guard requestID == id, foreground, let current = engine, current.state != .arrived else { return }
            guard
                  GuidanceEngine.accepts(current.lastFix, at: .now),
                  let latest = current.lastFix, latest.distance(from: location) <= 75 else {
                message = "Position changed during the route check. Waiting for a fresh check."; return
            }
            guard let fastest = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                message = "No replacement route available. Retry when connected."; return
            }
            if recovery && (forceRecovery || current.state == .offRoute) {
                install(fastest, at: .now)
                update(latest)
                message = "Route updated after leaving the previous route."
            } else if current.state == .following && policy.allows(current: current.remainingTime,
                       candidate: fastest.expectedTravelTime, sinceSwitch: now.timeIntervalSince(lastSwitch)) {
                proposal = fastest
                proposalOrigin = location
                proposalDate = .now
                message = "A potentially faster route is available. Savings compare with the current distance-based estimate."
            } else {
                message = "Keeping your route. No alternative met the savings threshold and cooldown."
            }
        } catch {
            guard requestID == id else { return }
            message = "Route check unavailable. Existing route retained; retry when connected."
        }
    }

    func acceptProposal(location: CLLocation?, at now: Date = .now) {
        guard let proposal, let origin = proposalOrigin, let proposalDate,
              GuidanceEngine.accepts(location, at: now), let location,
              location.distance(from: origin) <= 75, now.timeIntervalSince(proposalDate) <= 30,
              engine?.state == .following else {
            self.proposal = nil
            message = "This alternative is out of date. Check routes again."; return
        }
        install(proposal, at: now)
        update(location, at: now)
        message = "Alternative selected. Route-switch cooldown started."
    }

    func keepRoute() { proposal = nil; message = "Keeping your selected route." }

    private func install(_ route: MKRoute, at now: Date) {
        self.route = route
        engine = GuidanceEngine(route: GuidanceRoute(route), driving: driving)
        lastSwitch = now
        estimateDate = now
        proposal = nil
    }

    private func cancelRequest() {
        requestID = UUID()
        directions?.cancel()
        directions = nil
        isRefreshing = false
    }
}
