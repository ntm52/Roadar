import CoreLocation
import Testing
@testable import Roadar

@MainActor
struct GuidanceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func coordinate(_ meters: Double, east: Double = 0) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 42 + meters / 111_111, longitude: -83 + east / 82_500)
    }
    private func fix(_ meters: Double, east: Double = 0, second: Double = 0, accuracy: Double = 5, speed: Double = 2) -> CLLocation {
        CLLocation(coordinate: coordinate(meters, east: east), altitude: 0, horizontalAccuracy: accuracy,
                   verticalAccuracy: 5, course: 0, speed: speed, timestamp: now.addingTimeInterval(second))
    }
    private func engine() -> GuidanceEngine {
        GuidanceEngine(route: GuidanceRoute(coordinates: [coordinate(0), coordinate(100), coordinate(300)],
            maneuvers: [.init(instruction: "Head north", distance: 0), .init(instruction: "Turn right", distance: 100)],
            expectedTravelTime: 120), driving: false)
    }

    @Test func journeyAdvancesManeuversDistanceAndETA() {
        var trip = engine()
        trip.update(fix(0), at: now)
        #expect(trip.nextManeuver?.instruction == "Head north")
        trip.update(fix(70, second: 20), at: now.addingTimeInterval(20))
        #expect(trip.state == .following)
        #expect(trip.nextManeuver?.instruction == "Turn right")
        #expect(abs(trip.remainingDistance - 230) < 5)
        #expect(abs(trip.remainingTime - 92) < 3)
        trip.update(fix(140, second: 40), at: now.addingTimeInterval(40))
        #expect(trip.nextManeuver == nil)
    }

    @Test func missedRouteRequiresSustainedEvidenceAndRecovers() {
        var trip = engine()
        trip.update(fix(0), at: now)
        trip.update(fix(10, east: 80, second: 4), at: now.addingTimeInterval(4))
        #expect(trip.state == .uncertain)
        trip.update(fix(20, east: 80, second: 8), at: now.addingTimeInterval(8))
        #expect(trip.state == .uncertain)
        trip.update(fix(30, east: 80, second: 12), at: now.addingTimeInterval(12))
        #expect(trip.state == .offRoute)
        trip.update(fix(35, second: 16), at: now.addingTimeInterval(16))
        #expect(trip.state == .following)
    }

    @Test func poorStaleFutureAndDuplicateFixesCannotAdvanceTrip() {
        var trip = engine()
        trip.update(fix(0), at: now)
        for sample in [fix(100, accuracy: 200), fix(100, second: -30), fix(100, second: 30)] {
            trip.update(sample, at: now)
            #expect(trip.state == .uncertain)
            #expect(trip.progress == 0)
        }
        trip.update(fix(100), at: now)
        #expect(trip.progress == 0)
        trip.update(fix(30, second: 10), at: now.addingTimeInterval(10))
        #expect(trip.state == .following)
        trip.update(fix(30, second: 10), at: now.addingTimeInterval(40))
        #expect(trip.state == .uncertain)
    }

    @Test func arrivalNeedsEndProgressSlowSpeedAndDistinctAccurateSamples() {
        var trip = engine()
        for (meters, second) in [(0.0, 0.0), (100, 20), (200, 40), (290, 60)] {
            trip.update(fix(meters, second: second, speed: 12), at: now.addingTimeInterval(second))
        }
        #expect(trip.state == .following)
        trip.update(fix(295, second: 65), at: now.addingTimeInterval(65))
        #expect(trip.state != .arrived)
        trip.update(fix(295, second: 65), at: now.addingTimeInterval(65))
        #expect(trip.state != .arrived)
        trip.update(fix(298, second: 70), at: now.addingTimeInterval(70))
        #expect(trip.state == .arrived)
        #expect(trip.remainingDistance == 0)
    }

    @Test func proximityToEndCannotSkipLoop() {
        let route = GuidanceRoute(coordinates: [coordinate(0), coordinate(300), coordinate(300, east: 100), coordinate(0, east: 10)],
                                  maneuvers: [], expectedTravelTime: 300)
        var trip = GuidanceEngine(route: route, driving: false)
        trip.update(fix(0), at: now)
        trip.update(fix(0, east: 10, second: 5), at: now.addingTimeInterval(5))
        trip.update(fix(0, east: 10, second: 10), at: now.addingTimeInterval(10))
        #expect(trip.state != .arrived)
        #expect(trip.progress < 30)
    }

    @Test func savingsAndCooldownPreventOscillation() {
        let policy = ReroutePolicy()
        #expect(!policy.allows(current: 600, candidate: 550, sinceSwitch: 200))
        #expect(!policy.allows(current: 3000, candidate: 2900, sinceSwitch: 200))
        #expect(!policy.allows(current: 600, candidate: 400, sinceSwitch: 119))
        #expect(policy.allows(current: 600, candidate: 500, sinceSwitch: 120))
        #expect(!policy.allows(current: 500, candidate: 600, sinceSwitch: 240))
        #expect(!policy.allows(current: 0, candidate: 0, sinceSwitch: 240))
        #expect(!policy.allows(current: .infinity, candidate: 100, sinceSwitch: 240))
    }

    @Test func invalidCoordinatesCannotStartOrAdvanceGuidance() {
        let invalid = CLLocation(coordinate: .init(latitude: 100, longitude: -83), altitude: 0,
            horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        #expect(!GuidanceEngine.accepts(invalid, at: now))
        var trip = engine()
        trip.update(invalid, at: now)
        #expect(trip.state == .uncertain)
        #expect(trip.progress == 0)
    }

    @Test func backgroundInvalidationResetsOffRouteEvidence() {
        var trip = engine()
        trip.update(fix(0), at: now)
        trip.update(fix(0, east: 100, second: 5), at: now.addingTimeInterval(5))
        trip.invalidate()
        trip.update(fix(0, east: 100, second: 30), at: now.addingTimeInterval(30))
        #expect(trip.state == .uncertain)
        trip.update(fix(20, second: 35), at: now.addingTimeInterval(35))
        #expect(trip.state == .following)
    }
}
