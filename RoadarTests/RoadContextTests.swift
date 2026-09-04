import Foundation
import MapKit
import Testing
@testable import Roadar

@MainActor
struct RoadContextTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parallelOverpassAndOppositeReportsAreExcluded() {
        for scenario in [RoadReplay.Scenario.parallel, .overpass, .opposite] {
            let replay = RoadReplay(scenario: scenario, progress: 80, now: now)
            #expect(replay.context.road?.id == "east")
            #expect(Set(replay.context.reports.map(\.id)) == ["hazard", "continuation"])
        }
    }

    @Test func directionSelectsTheOppositeDirectedEdge() {
        let replay = RoadReplay(scenario: .opposite, progress: 350, now: now)
        var sample = replay.sample
        sample.course = 270
        let context = RoadMatcher().evaluate(sample: sample, roads: replay.roads, reports: replay.reports, now: now)
        #expect(context.road?.id == "west")
        #expect(context.reports.map(\.id) == ["opposite"])
    }

    @Test func unknownForkStopsLookAheadBeforeBothBranches() {
        let context = RoadReplay(scenario: .fork, progress: 80, now: now).context
        #expect(context.endsAtFork)
        #expect(context.reports.map(\.id) == ["hazard"])
    }

    @Test func ambiguousWeakAndStationarySamplesWithholdReports() {
        for scenario in [RoadReplay.Scenario.ambiguous, .weak, .stopped] {
            let context = RoadReplay(scenario: scenario, progress: 80, now: now).context
            #expect(context.road == nil)
            #expect(context.reports.isEmpty)
        }
    }

    @Test func passingReportRemovesItAndDuplicatesOnlyAppearOnce() {
        let before = RoadReplay(scenario: .passed, progress: 80, now: now).context
        #expect(before.reports.filter { $0.id == "hazard" }.count == 1)
        let after = RoadReplay(scenario: .passed, progress: 300, now: now).context
        #expect(after.reports.map(\.id) == ["continuation"])
        #expect(after.reports.first?.distance == 200)
    }

    @Test func staleFutureAndExpiredReportsAreRejected() {
        let replay = RoadReplay(scenario: .parallel, progress: 80, now: now)
        var sample = replay.sample
        sample.timestamp = now.addingTimeInterval(-31)
        #expect(RoadMatcher().evaluate(sample: sample, roads: replay.roads, reports: replay.reports, now: now).road == nil)
        let future = RoadReport(id: "future", edgeID: "east", offset: 300, title: "Future", createdAt: now.addingTimeInterval(10))
        let expired = RoadReport(id: "expired", edgeID: "east", offset: 300, title: "Expired", createdAt: now.addingTimeInterval(-60), lifetime: 60)
        let context = RoadMatcher().evaluate(sample: replay.sample, roads: replay.roads, reports: [future, expired], now: now)
        #expect(context.reports.isEmpty)
    }

    @Test func stackedRoadsRequireElevationEvidence() {
        let ground = RoadEdge(id: "ground", name: "Ground", start: .init(x: 0, y: 0), end: .init(x: 400, y: 0), elevation: 0)
        let bridge = RoadEdge(id: "bridge", name: "Bridge", start: .init(x: 0, y: 0), end: .init(x: 400, y: 0), elevation: 10)
        var sample = RoadSample(point: .init(x: 80, y: 0), course: 90, timestamp: now)
        #expect(RoadMatcher().evaluate(sample: sample, roads: [ground, bridge], reports: [], now: now).road == nil)
        sample.elevation = 10
        sample.verticalAccuracy = 1
        #expect(RoadMatcher().evaluate(sample: sample, roads: [ground, bridge], reports: [], now: now).road?.id == "bridge")
    }

    @Test func missingConnectionAndCyclesDoNotLeakReports() {
        let a = RoadEdge(id: "a", name: "A", start: .init(x: 0, y: 0), end: .init(x: 100, y: 0), successors: ["b"])
        let disconnected = RoadEdge(id: "b", name: "B", start: .init(x: 500, y: 0), end: .init(x: 600, y: 0), successors: ["a"])
        let sample = RoadSample(point: .init(x: 80, y: 0), course: 90, timestamp: now)
        let report = RoadReport(id: "b", edgeID: "b", offset: 50, title: "Disconnected", createdAt: now)
        #expect(RoadMatcher().evaluate(sample: sample, roads: [a, disconnected], reports: [report], now: now).reports.isEmpty)
        let loop = RoadEdge(id: "b", name: "B", start: .init(x: 100, y: 0), end: .init(x: 0, y: 0), successors: ["a"])
        let result = RoadMatcher().evaluate(sample: sample, roads: [a, loop], reports: [report], now: now)
        #expect(result.reports.isEmpty)
        #expect(result.endsAtFork)
    }

    @Test func nearbyPlacesRejectStaleLocationWithoutNetwork() async {
        let store = NearbyPlacesStore()
        let stale = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 42.28, longitude: -83.74), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now.addingTimeInterval(-60))
        await store.refresh(near: stale, now: now)
        #expect(store.places.isEmpty)
        #expect(store.message != nil)
        #expect(!store.isLoading)
        store.reset()
        #expect(store.message == nil)
    }
}
