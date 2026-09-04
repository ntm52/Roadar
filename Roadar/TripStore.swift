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
    private var directions: (any RouteCalculation)?
    private let makeDirections: (MKDirections.Request) -> any RouteCalculation
    private let clock: () -> Date
    private var lastRequest = Date.distantPast
    private var lastSwitch = Date.distantPast
    private var proposalOrigin: CLLocation?
    private var proposalDate: Date?
    var isActive: Bool { route != nil }

    init(makeDirections: @escaping (MKDirections.Request) -> any RouteCalculation = { MKDirections(request: $0) },
         clock: @escaping () -> Date = { .now }) {
        self.makeDirections = makeDirections
        self.clock = clock
    }

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
            if isActive { message = "Guidance paused. Return to Roadar for a fresh location." }
        } else if isActive { message = nil }
    }

    func update(_ location: CLLocation?, at now: Date = .now) {
        guard isActive, foreground else { return }
        engine?.update(location, at: now)
        if proposal != nil, !proposalIsValid(location: location, at: now) {
            proposal = nil
            message = "This alternative is out of date. Check routes again."
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
        let operation = makeDirections(request)
        directions = operation
        isRefreshing = true
        message = recovery ? "Off route · Finding a new route…" : "Checking available routes…"
        defer { if requestID == id { isRefreshing = false; directions = nil } }
        do {
            let routes = try await operation.calculateRoutes()
            let completedAt = clock()
            guard requestID == id, foreground, let current = engine, current.state != .arrived else { return }
            guard
                  GuidanceEngine.accepts(current.lastFix, at: completedAt),
                  let latest = current.lastFix, latest.distance(from: location) <= 75 else {
                message = "Position changed during the route check. Waiting for a fresh check."; return
            }
            guard let fastest = routes.filter({ $0.expectedTravelTime.isFinite && $0.expectedTravelTime > 0 && GuidanceRoute($0).length > 0 })
                .min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                message = "No replacement route available. Retry when connected."; return
            }
            if recovery && (forceRecovery || current.state == .offRoute) {
                install(fastest, at: completedAt)
                update(latest, at: completedAt)
                message = "Route updated after leaving the previous route."
            } else if current.state == .following && policy.allows(current: current.remainingTime,
                       candidate: fastest.expectedTravelTime, sinceSwitch: completedAt.timeIntervalSince(lastSwitch)) {
                proposal = fastest
                proposalOrigin = location
                proposalDate = completedAt
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
        guard let proposal, proposalIsValid(location: location, at: now), let location else {
            self.proposal = nil
            message = "This alternative is out of date. Check routes again."; return
        }
        install(proposal, at: now)
        update(location, at: now)
        message = "Alternative selected. Route-switch cooldown started."
    }

    func keepRoute() { proposal = nil; message = "Keeping your selected route." }

    private func proposalIsValid(location: CLLocation?, at now: Date) -> Bool {
        guard foreground, let origin = proposalOrigin, let proposalDate,
              GuidanceEngine.accepts(location, at: now), let location,
              engine?.state == .following else { return false }
        return location.distance(from: origin) <= 75 && (0...30).contains(now.timeIntervalSince(proposalDate))
    }

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
