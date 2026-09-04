import MapKit

extension WorkZoneFeed {
    struct RouteCandidate: Identifiable {
        let zone: Zone
        let distance: Double
        var id: String { zone.id }
    }

    func alongRoute(_ engine: GuidanceEngine, at now: Date) -> [RouteCandidate] {
        guard isFresh(at: now), engine.driving, engine.state == .following,
              GuidanceEngine.accepts(engine.lastFix, at: now) else { return [] }
        return routeCandidates(route: engine.route, progress: engine.progress, at: now)
    }

    /// Geometry candidates only: no road identity or elevation is available.
    /// WZDx LineString order follows travel direction. Require the entire reported
    /// line to agree with a unique stretch of route, accepting false negatives.
    func routeCandidates(route: GuidanceRoute, progress: Double, at now: Date) -> [RouteCandidate] {
        guard isFresh(at: now) else { return [] }
        let segments = route.segments
        return zones.compactMap { zone -> RouteCandidate? in
            guard zone.start <= now, now < zone.end,
                  ["northbound", "southbound", "eastbound", "westbound"].contains(zone.direction) else { return nil }
            let line = GuidanceRoute(coordinates: zone.coordinates, maneuvers: [], expectedTravelTime: 0).segments
            let length = line.reduce(0) { $0 + $1.length }
            guard length >= 60, length <= 25_000 else { return nil }
            let points = zone.coordinates.map(MKMapPoint.init)
            let margin = 20 / MKMetersPerMapPointAtLatitude(zone.coordinates[0].latitude)
            let minX = points.map(\.x).min()! - margin, maxX = points.map(\.x).max()! + margin
            let minY = points.map(\.y).min()! - margin, maxY = points.map(\.y).max()! + margin
            let nearbySegments = segments.filter {
                max($0.start.x, $0.end.x) >= minX && min($0.start.x, $0.end.x) <= maxX &&
                max($0.start.y, $0.end.y) >= minY && min($0.start.y, $0.end.y) <= maxY
            }
            guard !nearbySegments.isEmpty else { return nil }
            var first: Double?
            var previous: Double?
            for piece in line {
                let steps = max(1, Int(ceil(piece.length / 25)))
                for index in 0...steps {
                    let t = Double(index) / Double(steps)
                    let dx = piece.end.x - piece.start.x, dy = piece.end.y - piece.start.y
                    let point = MKMapPoint(x: piece.start.x + t * dx, y: piece.start.y + t * dy)
                    var offsets: [Double] = []
                    for segment in nearbySegments {
                        let sx = segment.end.x - segment.start.x, sy = segment.end.y - segment.start.y
                        let fraction = min(1, max(0, ((point.x - segment.start.x) * sx + (point.y - segment.start.y) * sy) / (sx * sx + sy * sy)))
                        let projected = MKMapPoint(x: segment.start.x + fraction * sx, y: segment.start.y + fraction * sy)
                        guard point.distance(to: projected) <= 12 else { continue }
                        // Within 30 degrees of the same travel direction.
                        guard (dx * sx + dy * sy) / (hypot(dx, dy) * hypot(sx, sy)) >= cos(.pi / 6) else { continue }
                        offsets.append(segment.offset + fraction * segment.length)
                    }
                    guard let low = offsets.min(), let high = offsets.max(), high - low <= 40 else { return nil }
                    let offset = (low + high) / 2
                    if let previous, offset < previous - 5 || offset - previous > 60 { return nil }
                    if first == nil { first = offset }
                    previous = offset
                }
            }
            guard let first, let last = previous, last - first >= 60,
                  last > progress + 20, first <= progress + 5000 else { return nil }
            return RouteCandidate(zone: zone, distance: max(0, first - progress))
        }.sorted { $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance }
    }
}
