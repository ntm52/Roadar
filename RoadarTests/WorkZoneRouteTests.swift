import CoreLocation
import MapKit
import Testing
@testable import Roadar

@MainActor
struct WorkZoneRouteTests {
    let now = Date(timeIntervalSince1970: 1_788_487_200)
    func point(_ east: Double, _ north: Double) -> CLLocationCoordinate2D {
        let base = MKMapPoint(CLLocationCoordinate2D(latitude: 42.28, longitude: -83.74))
        let scale = MKMetersPerMapPointAtLatitude(42.28)
        return MKMapPoint(x: base.x + east / scale, y: base.y - north / scale).coordinate
    }
    func route(_ points: [CLLocationCoordinate2D]) -> GuidanceRoute {
        GuidanceRoute(coordinates: points, maneuvers: [], expectedTravelTime: 300)
    }
    func feed(_ points: [CLLocationCoordinate2D], direction: String = "northbound", end: Date? = nil) -> WorkZoneFeed {
        WorkZoneFeed(updatedAt: now, zones: [.init(id: "test", roads: "Test Road", direction: direction,
            details: "Construction", start: now.addingTimeInterval(-600), end: end ?? now.addingTimeInterval(600),
            coordinates: points)], rejectedCount: 0)
    }
    var straight: GuidanceRoute { route([point(0, 0), point(0, 2000)]) }

    @Test func aheadAndCurrentSectionsAppearButPassedAndBeyondHorizonDoNot() {
        let feed = feed([point(0, 300), point(0, 500)])
        let ahead = feed.routeCandidates(route: straight, progress: 0, at: now)
        #expect(ahead.count == 1)
        #expect(abs((ahead.first?.distance ?? 0) - 300) < 2)
        #expect(feed.routeCandidates(route: straight, progress: 350, at: now).first?.distance == 0)
        #expect(feed.routeCandidates(route: straight, progress: 520, at: now).isEmpty)
        #expect(self.feed([point(0, 6000), point(0, 6200)]).routeCandidates(
            route: route([point(0, 0), point(0, 7000)]), progress: 0, at: now).isEmpty)
    }

    @Test func oppositeParallelCrossingShortAndUnknownGeometryAreWithheld() {
        for points in [[point(0, 500), point(0, 300)],
                       [point(25, 300), point(25, 500)],
                       [point(-100, 400), point(100, 400)],
                       [point(0, 300), point(0, 330)]] {
            #expect(feed(points).routeCandidates(route: straight, progress: 0, at: now).isEmpty)
        }
        #expect(feed([point(0, 300), point(0, 500)], direction: "unknown")
            .routeCandidates(route: straight, progress: 0, at: now).isEmpty)
    }

    @Test func futureTurnUsesFutureRouteDirection() {
        let turning = route([point(0, 0), point(0, 1000), point(1000, 1000)])
        let result = feed([point(200, 1000), point(500, 1000)], direction: "eastbound")
            .routeCandidates(route: turning, progress: 0, at: now)
        #expect(result.count == 1)
        #expect(abs((result.first?.distance ?? 0) - 1200) < 3)
    }

    @Test func repeatedRouteSectionIsAmbiguous() {
        let loop = route([point(0, 0), point(0, 1000), point(200, 1000), point(200, 0), point(0, 0), point(0, 1000)])
        #expect(feed([point(0, 300), point(0, 500)]).routeCandidates(route: loop, progress: 0, at: now).isEmpty)
    }

    @Test func expiredAndStaleFeedAreWithheld() {
        #expect(feed([point(0, 300), point(0, 500)], end: now).routeCandidates(route: straight, progress: 0, at: now).isEmpty)
        #expect(feed([point(0, 300), point(0, 500)]).routeCandidates(route: straight, progress: 0, at: now.addingTimeInterval(901)).isEmpty)
    }

    @Test func liveGuidanceAndFreshFixAreRequired() {
        let feed = feed([point(0, 300), point(0, 500)])
        var engine = GuidanceEngine(route: straight, driving: true)
        #expect(feed.alongRoute(engine, at: now).isEmpty)
        let fix = CLLocation(coordinate: point(0, 0), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        engine.update(fix, at: now)
        #expect(feed.alongRoute(engine, at: now).count == 1)
        #expect(feed.alongRoute(engine, at: now.addingTimeInterval(16)).isEmpty)
        engine.invalidate()
        #expect(feed.alongRoute(engine, at: now).isEmpty)
        var walking = GuidanceEngine(route: straight, driving: false)
        walking.update(fix, at: now)
        #expect(feed.alongRoute(walking, at: now).isEmpty)
    }

    @Test func sparseLineFindsNearbyMiddleInsteadOfOnlyEndpoints() {
        let feed = feed([point(0, -6000), point(0, 6000)])
        let fix = CLLocation(coordinate: point(10, 0), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        #expect(feed.nearby(fix, at: now).count == 1)
        #expect(abs(feed.zones[0].distance(from: fix) - 10) < 1)
    }
}
