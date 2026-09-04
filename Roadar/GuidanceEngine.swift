import CoreLocation
import MapKit

/// Value-based trip geometry also used by deterministic journey replays.
struct GuidanceRoute {
    struct Maneuver {
        let instruction: String
        let distance: Double
    }
    let coordinates: [CLLocationCoordinate2D]
    let maneuvers: [Maneuver]
    let expectedTravelTime: TimeInterval
    var length: Double { segments.reduce(0) { $0 + $1.length } }

    struct Segment {
        let start: MKMapPoint
        let end: MKMapPoint
        let offset: Double
        let length: Double
    }
    var segments: [Segment] {
        guard coordinates.count > 1 else { return [] }
        var offset = 0.0
        return zip(coordinates, coordinates.dropFirst()).compactMap { a, b in
            let start = MKMapPoint(a), end = MKMapPoint(b)
            let length = start.distance(to: end)
            guard length > 0 else { return nil }
            defer { offset += length }
            return Segment(start: start, end: end, offset: offset, length: length)
        }
    }

    struct Projection {
        let distance: Double
        let lateral: Double
    }
    func projections(of coordinate: CLLocationCoordinate2D) -> [Projection] {
        let point = MKMapPoint(coordinate)
        return segments.map { segment in
            let dx = segment.end.x - segment.start.x, dy = segment.end.y - segment.start.y
            let fraction = min(1, max(0, ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / (dx * dx + dy * dy)))
            let projected = MKMapPoint(x: segment.start.x + dx * fraction, y: segment.start.y + dy * fraction)
            return Projection(distance: segment.offset + segment.length * fraction, lateral: point.distance(to: projected))
        }
    }

    init(coordinates: [CLLocationCoordinate2D], maneuvers: [Maneuver], expectedTravelTime: TimeInterval) {
        self.coordinates = coordinates
        self.maneuvers = maneuvers
        self.expectedTravelTime = expectedTravelTime
    }

    init(_ route: MKRoute) {
        coordinates = (0..<route.polyline.pointCount).map { route.polyline.points()[$0].coordinate }
        expectedTravelTime = route.expectedTravelTime
        // Step instructions describe the maneuver at the beginning of each step.
        let geometry = GuidanceRoute(coordinates: coordinates, maneuvers: [], expectedTravelTime: route.expectedTravelTime)
        var previous = 0.0
        maneuvers = route.steps.compactMap { step in
            guard !step.instructions.isEmpty, step.polyline.pointCount > 0 else { return nil }
            let candidates = geometry.projections(of: step.polyline.points()[0].coordinate)
                .filter { $0.distance >= previous - 5 }
            guard let match = candidates.min(by: { $0.lateral < $1.lateral }) else { return nil }
            previous = max(previous, match.distance)
            return Maneuver(instruction: step.instructions, distance: previous)
        }
    }
}

struct ReroutePolicy {
    var minimumSecondsSaved = 60.0
    var minimumFractionSaved = 0.05
    var cooldown = 120.0

    func allows(current: TimeInterval, candidate: TimeInterval, sinceSwitch: TimeInterval) -> Bool {
        current.isFinite && candidate.isFinite && current > 0 && candidate > 0 && sinceSwitch >= cooldown &&
        current - candidate >= minimumSecondsSaved &&
        (current - candidate) / current >= minimumFractionSaved
    }
}

struct GuidanceEngine {
    enum State: Equatable { case locating, following, uncertain, offRoute, arrived }
    let route: GuidanceRoute
    let driving: Bool
    private(set) var state: State = .locating
    private(set) var progress = 0.0
    private(set) var lastFix: CLLocation?
    private var offRouteSince: Date?
    private var offRouteSamples = 0
    private var arrivalSamples = 0
    var remainingDistance: Double { max(0, route.length - progress) }
    /// Distance-proportional estimate; not a fresh traffic prediction.
    var remainingTime: TimeInterval { route.length > 0 ? route.expectedTravelTime * remainingDistance / route.length : 0 }
    var nextManeuver: GuidanceRoute.Maneuver? {
        route.maneuvers.first { $0.distance >= progress - 10 }
    }

    init(route: GuidanceRoute, driving: Bool) {
        self.route = route
        self.driving = driving
    }

    static func accepts(_ fix: CLLocation?, at now: Date) -> Bool {
        guard let fix else { return false }
        return CLLocationCoordinate2DIsValid(fix.coordinate) &&
            now.timeIntervalSince(fix.timestamp) >= -5 && now.timeIntervalSince(fix.timestamp) <= 15 &&
            fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 35
    }

    mutating func invalidate() {
        guard state != .arrived else { return }
        state = .uncertain
        offRouteSince = nil
        offRouteSamples = 0
        arrivalSamples = 0
    }

    mutating func update(_ fix: CLLocation?, at now: Date) {
        guard state != .arrived else { return }
        guard Self.accepts(fix, at: now), let fix else { invalidate(); return }
        guard lastFix == nil || fix.timestamp > lastFix!.timestamp else { return }
        let prior = lastFix
        lastFix = fix
        let candidates = route.projections(of: fix.coordinate)
        guard let nearest = candidates.min(by: { $0.lateral < $1.lateral }) else { invalidate(); return }
        let corridor = max(driving ? 35.0 : 20.0, fix.horizontalAccuracy * 1.5)
        if nearest.lateral > corridor {
            arrivalSamples = 0
            offRouteSamples += 1
            if offRouteSince == nil { offRouteSince = fix.timestamp }
            state = offRouteSamples >= 3 && fix.timestamp.timeIntervalSince(offRouteSince!) >= 8 ? .offRoute : .uncertain
            return
        }
        offRouteSince = nil
        offRouteSamples = 0
        // At crossings or hairpins prefer continuity; do not jump to a distant leg.
        let elapsed = prior.map { fix.timestamp.timeIntervalSince($0.timestamp) } ?? 0
        let maximumAdvance = prior == nil ? 150 : max(80, min(elapsed, 30) * (driving ? 55 : 5))
        let plausible = candidates.filter {
            $0.lateral <= corridor && $0.lateral <= nearest.lateral + 10 &&
            $0.distance >= progress - 40 && $0.distance <= progress + maximumAdvance
        }
        guard let matched = plausible.min(by: { abs($0.distance - progress) < abs($1.distance - progress) }) else {
            invalidate(); return
        }
        if plausible.contains(where: { abs($0.distance - matched.distance) > 100 && $0.lateral <= matched.lateral + 5 }) {
            invalidate(); return
        }
        progress = max(progress, matched.distance)
        state = .following
        let radius = driving ? 25.0 : 15.0
        let endDistance = route.coordinates.last.map { fix.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) } ?? .infinity
        if remainingDistance <= radius && endDistance <= radius && fix.horizontalAccuracy <= 20 && fix.speed >= 0 && fix.speed <= 3 {
            arrivalSamples += 1
            if arrivalSamples >= 2 { state = .arrived; progress = route.length }
        } else { arrivalSamples = 0 }
    }
}
