import CoreLocation
import MapKit
import Testing
@testable import Roadar

private final class TestRoute: MKRoute {
    let line: MKPolyline
    let seconds: TimeInterval
    init(seconds: TimeInterval) {
        self.seconds = seconds
        let points = [CLLocationCoordinate2D(latitude: 42, longitude: -83),
                      CLLocationCoordinate2D(latitude: 42.01, longitude: -83)]
        line = MKPolyline(coordinates: points, count: points.count)
        super.init()
    }
    override var polyline: MKPolyline { line }
    override var expectedTravelTime: TimeInterval { seconds }
    override var steps: [MKRoute.Step] { [] }
}

@MainActor
private final class PendingRoutes: RouteCalculation {
    var continuation: CheckedContinuation<[MKRoute], Error>?
    var wasCancelled = false
    func calculateRoutes() async throws -> [MKRoute] {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func cancel() { wasCancelled = true }
    func finish(_ result: Result<[MKRoute], Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
struct TripStoreTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func fix(at date: Date, latitude: Double = 42) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: -83), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 0, timestamp: date)
    }

    private func startTrip(_ store: TripStore) {
        let location = fix(at: start)
        store.start(route: TestRoute(seconds: 600), destination: MKMapItem(location: location, address: nil),
                    driving: true, location: location, at: start)
    }

    @Test func endedAndBackgroundedTripsIgnoreLateRouteResponses() async {
        for endTrip in [true, false] {
            let request = PendingRoutes()
            let now = start.addingTimeInterval(130)
            let store = TripStore(makeDirections: { _ in request }, clock: { now })
            startTrip(store)
            store.update(fix(at: now), at: now)
            let task = Task { await store.refresh(from: fix(at: now), at: now) }
            while request.continuation == nil { await Task.yield() }
            if endTrip { store.end() } else { store.setForeground(false) }
            #expect(request.wasCancelled)
            request.finish(.success([TestRoute(seconds: 100)]))
            await task.value
            #expect(store.proposal == nil)
            #expect(!store.isRefreshing)
            #expect(store.isActive == !endTrip)
            if !endTrip { #expect(store.engine?.state == .uncertain) }
        }
    }

    @Test func alternativeCanBeAcceptedAndStartsNewCooldown() async {
        let request = PendingRoutes()
        var now = start.addingTimeInterval(130)
        let store = TripStore(makeDirections: { _ in request }, clock: { now })
        startTrip(store)
        store.update(fix(at: now), at: now)
        let task = Task { await store.refresh(from: fix(at: now), at: now) }
        while request.continuation == nil { await Task.yield() }
        request.finish(.success([TestRoute(seconds: 300)]))
        await task.value
        #expect(store.proposal != nil)
        store.acceptProposal(location: fix(at: now), at: now)
        #expect(store.route?.expectedTravelTime == 300)
        #expect(store.proposal == nil)
        let later = now.addingTimeInterval(31)
        now = later
        store.update(fix(at: later), at: later)
        let retry = Task { await store.refresh(from: fix(at: later), at: later) }
        while request.continuation == nil { await Task.yield() }
        request.finish(.success([TestRoute(seconds: 100)]))
        await retry.value
        #expect(store.proposal == nil)
        #expect(store.route?.expectedTravelTime == 300)
    }

    @Test func proposalExpiresOnTimeMovementOrLostPosition() async {
        for reason in 0..<3 {
            let request = PendingRoutes()
            let now = start.addingTimeInterval(130)
            let store = TripStore(makeDirections: { _ in request }, clock: { now })
            startTrip(store)
            store.update(fix(at: now), at: now)
            let task = Task { await store.refresh(from: fix(at: now), at: now) }
            while request.continuation == nil { await Task.yield() }
            request.finish(.success([TestRoute(seconds: 300)]))
            await task.value
            #expect(store.proposal != nil)
            let later = now.addingTimeInterval(reason == 0 ? 31 : 5)
            store.update(reason == 2 ? nil : fix(at: later, latitude: reason == 1 ? 42.001 : 42), at: later)
            #expect(store.proposal == nil)
            #expect(store.message?.contains("out of date") == true)
            #expect(store.route?.expectedTravelTime == 600)
        }
    }

    @Test func networkFailureKeepsRouteAndManualRecoveryCanReplaceIt() async {
        let request = PendingRoutes()
        var now = start.addingTimeInterval(35)
        let store = TripStore(makeDirections: { _ in request }, clock: { now })
        startTrip(store)
        store.update(fix(at: now), at: now)
        let task = Task { await store.refresh(from: fix(at: now), at: now) }
        while request.continuation == nil { await Task.yield() }
        request.finish(.failure(URLError(.notConnectedToInternet)))
        await task.value
        #expect(store.route?.expectedTravelTime == 600)
        #expect(!store.isRefreshing)
        #expect(store.message?.contains("unavailable") == true)
        now = now.addingTimeInterval(35)
        store.update(nil, at: now)
        store.update(fix(at: now), at: now)
        let retry = Task { await store.refresh(from: fix(at: now), at: now, forceRecovery: true) }
        while request.continuation == nil { await Task.yield() }
        request.finish(.success([TestRoute(seconds: 400)]))
        await retry.value
        #expect(store.route?.expectedTravelTime == 400)
        #expect(store.engine?.state == .following)
    }

    @Test func backgroundWithoutTripDoesNotCreateGuidanceMessage() {
        let store = TripStore()
        store.setForeground(false)
        store.setForeground(true)
        #expect(store.message == nil)
    }
}
