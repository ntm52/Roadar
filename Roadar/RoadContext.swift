import Foundation

/// Provider-independent local geometry in meters. Directed edges must follow legal travel direction.
struct RoadPoint: Equatable {
    var x: Double
    var y: Double
}

struct RoadEdge: Identifiable {
    let id: String
    let name: String
    let start: RoadPoint
    let end: RoadPoint
    var elevation: Double? = nil
    var speedLimitMPH: Int? = nil
    var successors: [String] = []

    var length: Double { hypot(end.x - start.x, end.y - start.y) }
    var bearing: Double { (atan2(end.x - start.x, end.y - start.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }

    func point(at offset: Double) -> RoadPoint {
        let t = length > 0 ? min(1, max(0, offset / length)) : 0
        return RoadPoint(x: start.x + t * (end.x - start.x), y: start.y + t * (end.y - start.y))
    }

    func projection(of point: RoadPoint) -> (offset: Double, distance: Double) {
        guard length > 0 else { return (0, .infinity) }
        let t = min(1, max(0, ((point.x - start.x) * (end.x - start.x) + (point.y - start.y) * (end.y - start.y)) / (length * length)))
        let projected = self.point(at: t * length)
        return (t * length, hypot(point.x - projected.x, point.y - projected.y))
    }
}

struct RoadSample {
    var point: RoadPoint
    var course: Double
    var accuracy: Double = 5
    var speed: Double = 12
    var elevation: Double? = nil
    var verticalAccuracy: Double = -1
    var timestamp: Date
}

struct RoadReport: Identifiable {
    let id: String
    let edgeID: String
    let offset: Double
    let title: String
    let createdAt: Date
    var lifetime: TimeInterval = 1800
}

struct AheadReport: Identifiable {
    let report: RoadReport
    let distance: Double
    var id: String { report.id }
}

struct RoadContext {
    var road: RoadEdge?
    var offset: Double = 0
    var message: String
    var reports: [AheadReport] = []
    var endsAtFork = false
}

struct RoadMatcher {
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    func evaluate(sample: RoadSample, roads: [RoadEdge], reports: [RoadReport], now: Date) -> RoadContext {
        guard abs(now.timeIntervalSince(sample.timestamp)) <= 30,
              sample.accuracy >= 0, sample.accuracy <= 35 else {
            return RoadContext(message: "Location is too old or imprecise to match a road.")
        }
        guard sample.course >= 0, sample.course < 360, sample.speed >= 1.5 else {
            return RoadContext(message: "Travel direction is uncertain. Reports are withheld.")
        }
        let candidates = roads.compactMap { road -> (RoadEdge, Double, Double)? in
            guard road.length > 0 else { return nil }
            let projection = road.projection(of: sample.point)
            let angle = Self.angleDifference(road.bearing, sample.course)
            guard projection.distance <= max(15, sample.accuracy), angle <= 45 else { return nil }
            if let elevation = sample.elevation, let roadElevation = road.elevation,
               sample.verticalAccuracy >= 0, sample.verticalAccuracy <= 4,
               abs(elevation - roadElevation) > max(4, sample.verticalAccuracy * 2) { return nil }
            return (road, projection.offset, projection.distance + angle / 10)
        }.sorted { $0.2 < $1.2 }
        guard let best = candidates.first else { return RoadContext(message: "No confident road match. Reports are withheld.") }
        if candidates.count > 1, candidates[1].2 - best.2 <= max(5, sample.accuracy) {
            return RoadContext(message: "Several roads fit this position. Reports are withheld.")
        }

        var result = RoadContext(road: best.0, offset: best.1, message: "Matched road and travel direction")
        let horizon = min(1500, max(300, sample.speed * 40))
        var corridor: [String: Double] = [best.0.id: -best.1]
        var edge = best.0
        var distance = edge.length - best.1
        var visited: Set<String> = [edge.id]
        while distance < horizon {
            guard edge.successors.count == 1 else {
                result.endsAtFork = edge.successors.count > 1
                break
            }
            guard let next = roads.first(where: { $0.id == edge.successors[0] }),
                  !visited.contains(next.id),
                  hypot(edge.end.x - next.start.x, edge.end.y - next.start.y) < 2 else { break }
            // A lone graph connection is not evidence that the driver intends a sharp turn or U-turn.
            guard Self.angleDifference(edge.bearing, next.bearing) <= 60 else {
                result.endsAtFork = true
                break
            }
            visited.insert(next.id)
            corridor[next.id] = distance
            distance += next.length
            edge = next
        }
        var seen = Set<String>()
        result.reports = reports.sorted { $0.createdAt > $1.createdAt }.compactMap { report in
            guard let start = corridor[report.edgeID],
                  let reportEdge = roads.first(where: { $0.id == report.edgeID }),
                  report.offset >= 0, report.offset <= reportEdge.length,
                  now >= report.createdAt, now.timeIntervalSince(report.createdAt) < min(1800, report.lifetime),
                  seen.insert(report.id).inserted else { return nil }
            let ahead = start + report.offset
            // A GPS-sized exclusion zone avoids presenting a passed report as still ahead.
            guard ahead > max(10, sample.accuracy), ahead <= horizon else { return nil }
            return AheadReport(report: report, distance: ahead)
        }.sorted { $0.distance < $1.distance }
        if result.endsAtFork { result.message = "Turn uncertain · Look-ahead stops before the unknown turn" }
        return result
    }
}
