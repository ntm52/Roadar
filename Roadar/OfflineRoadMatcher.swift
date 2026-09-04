import Foundation
import CoreLocation

nonisolated struct OfflineRoadFix: Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let course: Double
    let speed: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        accuracy = location.horizontalAccuracy
        course = location.course
        speed = location.speed
        timestamp = location.timestamp
    }
}

nonisolated struct OfflineRoadMatch: Sendable {
    var road: String? = nil
    var speedLimit: String? = nil
    var message: String
    var osmID: Int64? = nil
    var timestamp: Date? = nil
}

nonisolated struct OfflineRoadMatcher: Sendable {
    private var previous: (fix: OfflineRoadFix, osmID: Int64, nodes: Set<Double>, streak: Int)?

    mutating func reset() { previous = nil }

    mutating func match(_ fix: OfflineRoadFix, roads: [OfflineRoad], now: Date) -> OfflineRoadMatch {
        func unknown(_ message: String) -> OfflineRoadMatch { OfflineRoadMatch(message: message) }
        guard fix.latitude.isFinite, fix.longitude.isFinite, fix.accuracy.isFinite,
              fix.accuracy >= 0, fix.accuracy <= 20,
              now.timeIntervalSince(fix.timestamp) >= -1, now.timeIntervalSince(fix.timestamp) <= 15 else {
            reset(); return unknown("Waiting for a fresh, precise location.")
        }
        guard fix.course.isFinite, (0..<360).contains(fix.course), fix.speed >= 2 else {
            reset(); return unknown("Move along the road to establish travel direction.")
        }
        if let previous, fix.timestamp <= previous.fix.timestamp {
            return unknown("Waiting for a new location sample.")
        }
        struct Candidate {
            let road: OfflineRoad
            let score: Double
            let limit: String?
            let offset: Double
        }
        let scale = 111_195.0
        let eastScale = scale * cos(fix.latitude * .pi / 180)
        var candidates: [Candidate] = []
        var unknownDirectionNearby = false
        for road in roads {
            var matches: [Candidate] = []
            var distanceAlong = 0.0
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                let ax = (a[0] - fix.longitude) * eastScale, ay = (a[1] - fix.latitude) * scale
                let bx = (b[0] - fix.longitude) * eastScale, by = (b[1] - fix.latitude) * scale
                let dx = bx - ax, dy = by - ay, length = hypot(dx, dy)
                guard length > 0.1 else { continue }
                defer { distanceAlong += length }
                let t = min(1, max(0, -(ax * dx + ay * dy) / (length * length)))
                let distance = hypot(ax + t * dx, ay + t * dy)
                guard distance <= max(12, fix.accuracy) else { continue }
                let bearing = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                func difference(_ heading: Double) -> Double {
                    let delta = abs(heading - fix.course).truncatingRemainder(dividingBy: 360)
                    return min(delta, 360 - delta)
                }
                if road.direction == 0 { unknownDirectionNearby = true; continue }
                let forward = difference(bearing)
                let backward = difference((bearing + 180).truncatingRemainder(dividingBy: 360))
                let reverse = road.direction == -1 || (road.direction == 2 && backward < forward)
                let angle = reverse ? backward : forward
                guard angle <= 35 else { continue }
                matches.append(Candidate(road: road, score: distance + angle * 0.2,
                    limit: reverse ? road.backwardLimit : road.forwardLimit, offset: distanceAlong + t * length))
            }
            if let best = matches.min(by: { $0.score < $1.score }) {
                // Adjacent shape segments are one candidate; separated legs of a loop are not.
                if matches.contains(where: { abs($0.offset - best.offset) > 100 && $0.score <= best.score + max(6, fix.accuracy) }) {
                    reset(); return unknown("Road geometry is ambiguous here.")
                }
                candidates.append(best)
            }
        }
        candidates.sort { $0.score < $1.score }
        guard !unknownDirectionNearby, let best = candidates.first else {
            reset(); return unknown("No confident match in the downloaded roads.")
        }
        if candidates.dropFirst().contains(where: { $0.road.osmID != best.road.osmID && $0.score - best.score <= max(6, fix.accuracy) }) {
            reset(); return unknown("Several roads fit this position. Road and limit are withheld.")
        }
        let nodes = Set(best.road.points.map { $0[2] })
        var streak = 1
        if let old = previous {
            let elapsed = fix.timestamp.timeIntervalSince(old.fix.timestamp)
            let movement = hypot((fix.longitude - old.fix.longitude) * eastScale, (fix.latitude - old.fix.latitude) * scale)
            let connected = old.osmID == best.road.osmID || !nodes.isDisjoint(with: old.nodes)
            if elapsed <= 15, movement <= max(60, fix.speed * elapsed * 2 + fix.accuracy), connected {
                streak = old.streak + 1
            }
        }
        previous = (fix, best.road.osmID, nodes, streak)
        guard streak >= 3 else { return unknown("Confirming the road from your movement…") }
        return OfflineRoadMatch(road: best.road.name, speedLimit: best.limit,
            message: "Offline OSM road estimate · Limits may be missing or outdated",
            osmID: best.road.osmID, timestamp: fix.timestamp)
    }
}
