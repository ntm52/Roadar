import Foundation
import CoreLocation
import Testing
@testable import Roadar

@MainActor
struct WorkZoneTests {
    let now = ISO8601DateFormatter().date(from: "2026-09-04T02:00:00Z")!

    func feature(id: String = "zone-1", end: String = "2026-10-01T00:00:00Z", longitude: Double = -83.74) -> [String: Any] {
        ["type": "Feature", "id": id,
         "geometry": ["type": "LineString", "coordinates": [[longitude,42.28],[longitude,42.281]]],
         "properties": ["start_date": "2026-09-01T00:00:00Z", "end_date": end,
                        "core_details": ["event_type": "work-zone", "road_names": ["Test Road"],
                                         "direction": "northbound", "description": "Test work zone"]]]
    }
    func data(features: [[String: Any]], updated: String = "2026-09-04T01:55:00.637223157Z", stringify: Bool = false) throws -> Data {
        let value: Any = stringify ? String(data: try JSONSerialization.data(withJSONObject: features), encoding: .utf8)! : features
        return try JSONSerialization.data(withJSONObject: [["type": "FeatureCollection",
            "road_event_feed_info": ["version": "4.0", "update_date": updated], "features": value]])
    }
    var location: CLLocation {
        CLLocation(coordinate: .init(latitude: 42.28, longitude: -83.74), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
    }

    @Test func decodesRIDEEnvelopeAndStringEncodedFeatures() throws {
        for stringify in [false, true] {
            let feed = try WorkZoneFeed.decode(data(features: [feature()], stringify: stringify))
            #expect(feed.zones.count == 1)
            #expect(feed.isFresh(at: now))
            #expect(feed.nearby(location, at: now).count == 1)
        }
    }
    @Test func staleAndFutureFeedsWithholdEveryRecord() throws {
        for timestamp in ["2026-08-05T22:58:47Z", "2026-09-04T02:02:00Z"] {
            let feed = try WorkZoneFeed.decode(data(features: [feature()], updated: timestamp))
            #expect(!feed.isFresh(at: now))
            #expect(feed.nearby(location, at: now).isEmpty)
        }
        let feed = try WorkZoneFeed.decode(data(features: [feature()]))
        #expect(!feed.isFresh(at: now.addingTimeInterval(901)))
    }
    @Test func endedDistantAndMissingLocationDoNotAppear() throws {
        let feed = try WorkZoneFeed.decode(data(features: [feature(end: "2026-09-04T02:00:00Z"), feature(id: "far", longitude: -85)]))
        #expect(feed.nearby(location, at: now).isEmpty)
        #expect(feed.nearby(nil, at: now).isEmpty)
    }
    @Test func conflictingDuplicateIDsAndBadCoordinatesAreWithheld() throws {
        let feed = try WorkZoneFeed.decode(data(features: [feature(), feature(), feature(id: "invalid", longitude: 999)]))
        #expect(feed.zones.isEmpty)
        #expect(feed.rejectedCount == 2)
    }
    @Test func completedAndPendingEventsAreWithheldEvenBeforeTheirEndDate() throws {
        var records: [[String: Any]] = []
        for status in ["completed", "pending", "cancelled", "unexpected"] {
            var record = feature(id: status)
            var properties = record["properties"] as! [String: Any]
            properties["event_status"] = status
            record["properties"] = properties
            records.append(record)
        }
        let feed = try WorkZoneFeed.decode(data(features: records))
        #expect(feed.zones.isEmpty)
    }

    @Test func malformedEnvelopeFailsInsteadOfClaimingNoWorkZones() {
        #expect(throws: (any Error).self) { try WorkZoneFeed.decode(Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try WorkZoneFeed.decode(Data("{}".utf8)) }
    }
    @Test func staleAndWeakPositionsWithholdNearbyRecords() throws {
        let feed = try WorkZoneFeed.decode(data(features: [feature()]))
        for (age, accuracy) in [(31.0, 5.0), (0.0, 100.0), (0.0, -1.0)] {
            let fix = CLLocation(coordinate: location.coordinate, altitude: 0,
                                 horizontalAccuracy: accuracy, verticalAccuracy: 5,
                                 timestamp: now.addingTimeInterval(-age))
            #expect(feed.nearby(fix, at: now).isEmpty)
        }
    }
}
