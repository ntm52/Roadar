import Foundation
import CoreLocation
import MapKit

/// MDOT RIDE's WZDx 4.0 response is a one-element array containing a GeoJSON feed.
struct WorkZoneFeed {
    struct Zone: Identifiable {
        let id: String
        let roads: String
        let direction: String
        let details: String
        let start: Date
        let end: Date
        let coordinates: [CLLocationCoordinate2D]

        func distance(from location: CLLocation) -> Double {
            let point = MKMapPoint(location.coordinate)
            return zip(coordinates, coordinates.dropFirst()).map { a, b in
                let start = MKMapPoint(a), end = MKMapPoint(b)
                let dx = end.x - start.x, dy = end.y - start.y
                let squared = dx * dx + dy * dy
                let t = squared > 0 ? min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squared)) : 0
                return point.distance(to: MKMapPoint(x: start.x + t * dx, y: start.y + t * dy))
            }.min() ?? .infinity
        }
    }
    let updatedAt: Date
    let zones: [Zone]
    let rejectedCount: Int
    static let maximumAge: TimeInterval = 15 * 60

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(updatedAt) >= -60 && now.timeIntervalSince(updatedAt) <= Self.maximumAge
    }

    func nearby(_ location: CLLocation?, at now: Date) -> [Zone] {
        guard isFresh(at: now), let location, abs(now.timeIntervalSince(location.timestamp)) <= 30,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65 else { return [] }
        return zones.filter { $0.start <= now && now < $0.end && $0.distance(from: location) <= 5000 }
            .sorted { $0.distance(from: location) < $1.distance(from: location) }
    }

    enum Failure: Error { case invalidEnvelope, unsupportedVersion, invalidTimestamp }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 10_000_000,
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], array.count == 1,
              let object = array.first, object["type"] as? String == "FeatureCollection",
              let info = object["road_event_feed_info"] as? [String: Any] else { throw Failure.invalidEnvelope }
        guard info["version"] as? String == "4.0" else { throw Failure.unsupportedVersion }
        guard let updated = date(info["update_date"]) else { throw Failure.invalidTimestamp }
        let rawFeatures: Any?
        if let string = object["features"] as? String {
            rawFeatures = try JSONSerialization.jsonObject(with: Data(string.utf8))
        } else { rawFeatures = object["features"] }
        guard let features = rawFeatures as? [[String: Any]] else { throw Failure.invalidEnvelope }
        var zones: [String: Zone] = [:]
        var rejected = 0
        var duplicates = Set<String>()
        for feature in features {
            guard let zone = zone(feature) else { rejected += 1; continue }
            // Conflicting duplicates are withheld rather than choosing an arbitrary event version.
            if zones[zone.id] != nil || duplicates.contains(zone.id) {
                zones[zone.id] = nil
                duplicates.insert(zone.id)
                rejected += 1
            } else { zones[zone.id] = zone }
        }
        return Self(updatedAt: updated, zones: Array(zones.values), rejectedCount: rejected)
    }

    private static func zone(_ feature: [String: Any]) -> Zone? {
        guard feature["type"] as? String == "Feature",
              let id = feature["id"] as? String, !id.isEmpty,
              let properties = feature["properties"] as? [String: Any],
              ["active", "planned"].contains(properties["event_status"] as? String ?? "active"),
              let core = properties["core_details"] as? [String: Any],
              core["event_type"] as? String == "work-zone",
              let start = date(properties["start_date"]), let end = date(properties["end_date"]), start < end,
              let geometry = feature["geometry"] as? [String: Any],
              geometry["type"] as? String == "LineString",
              let pairs = geometry["coordinates"] as? [[Double]], pairs.count >= 2 else { return nil }
        var coordinates: [CLLocationCoordinate2D] = []
        for pair in pairs {
            guard pair.count >= 2, pair[0].isFinite, pair[1].isFinite,
                  (-180...180).contains(pair[0]), (-90...90).contains(pair[1]) else { return nil }
            coordinates.append(.init(latitude: pair[1], longitude: pair[0]))
        }
        return Zone(id: id, roads: (core["road_names"] as? [String])?.joined(separator: ", ") ?? "Unnamed road",
                    direction: core["direction"] as? String ?? "unknown",
                    details: core["description"] as? String ?? "Reported work zone",
                    start: start, end: end, coordinates: coordinates)
    }

    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
