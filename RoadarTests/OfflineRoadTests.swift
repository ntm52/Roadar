import Foundation
import CoreLocation
import SQLite3
import zlib
import Testing
@testable import Roadar

struct OfflineRoadTests {
    let now = Date()

    func fix(_ east: Double = 0, north: Double = 0, course: Double = 90, speed: Double = 10,
             accuracy: Double = 5, time: Date? = nil) -> OfflineRoadFix {
        OfflineRoadFix(CLLocation(coordinate: .init(latitude: 42.28 + north / 111_195,
            longitude: -83.74 + east / (111_195 * cos(42.28 * .pi / 180))), altitude: 0,
            horizontalAccuracy: accuracy, verticalAccuracy: 5, course: course, speed: speed, timestamp: time ?? now))
    }

    func road(_ id: Int64 = 1, north: Double = 0, direction: Int = 2, forward: String? = "35 mph",
              backward: String? = "25 mph") -> OfflineRoad {
        let lat = 42.28 + north / 111_195
        return OfflineRoad(id: id, osmID: id, name: "Test Road", direction: direction,
            forwardLimit: forward, backwardLimit: backward,
            points: [[-83.75, lat, Double(id * 10)], [-83.73, lat, Double(id * 10 + 1)]])
    }

    @Test func threeFreshFixesConfirmDirectionalLimit() {
        for (course, expected) in [(90.0, "35 mph"), (270.0, "25 mph")] {
            var matcher = OfflineRoadMatcher()
            for i in 0..<3 {
                let time = now.addingTimeInterval(Double(i) * 2)
                let result = matcher.match(fix(Double(i) * (course == 90 ? 10 : -10), course: course, time: time), roads: [road()], now: time)
                #expect((result.road != nil) == (i == 2))
                if i == 2 { #expect(result.speedLimit == expected) }
            }
        }
    }

    @Test func parallelAndStackedRoadsAreAmbiguous() {
        for separation in [0.0, 4.0] {
            var matcher = OfflineRoadMatcher()
            for i in 0..<4 {
                let time = now.addingTimeInterval(Double(i) * 2)
                #expect(matcher.match(fix(time: time), roads: [road(), road(2, north: separation)], now: time).road == nil)
            }
        }
    }

    @Test func oppositeOneWayAndUnknownDirectionNeverConfirm() {
        for direction in [-1, 0] {
            var matcher = OfflineRoadMatcher()
            for i in 0..<4 {
                let time = now.addingTimeInterval(Double(i) * 2)
                #expect(matcher.match(fix(time: time), roads: [road(direction: direction)], now: time).road == nil)
            }
        }
    }

    @Test func staleWeakStoppedAndDuplicateFixesCannotConfirm() {
        for bad in [fix(accuracy: 50), fix(time: now.addingTimeInterval(-30)), fix(speed: 0),
                    fix(time: now.addingTimeInterval(20)), fix(course: -1)] {
            var matcher = OfflineRoadMatcher()
            for _ in 0..<4 { #expect(matcher.match(bad, roads: [road()], now: now).road == nil) }
        }
        var matcher = OfflineRoadMatcher()
        for _ in 0..<5 { #expect(matcher.match(fix(), roads: [road()], now: now).road == nil) }
    }

    @Test func missingLimitStaysUnknownAndDisconnectedRoadNeedsNewConfirmation() {
        var matcher = OfflineRoadMatcher()
        for i in 0..<3 {
            let time = now.addingTimeInterval(Double(i))
            let result = matcher.match(fix(time: time), roads: [road(forward: nil)], now: time)
            #expect(result.speedLimit == nil)
            if i == 2 { #expect(result.road != nil) }
        }
        let time = now.addingTimeInterval(4)
        #expect(matcher.match(fix(time: time), roads: [road(9)], now: time).road == nil)
    }

    @Test func adjacentShapeSegmentsDoNotCreateFalseAmbiguity() {
        var matcher = OfflineRoadMatcher()
        let curved = OfflineRoad(id: 1, osmID: 1, name: "Continuous", direction: 2,
            forwardLimit: "30 mph", backwardLimit: "30 mph",
            points: [[-83.75,42.28,1],[-83.74,42.28,2],[-83.73,42.28,3]])
        for i in 0..<3 {
            let time = now.addingTimeInterval(Double(i))
            let result = matcher.match(fix(time: time), roads: [curved], now: time)
            if i == 2 { #expect(result.road == "Continuous") }
        }
    }

    @Test func regionCropWithholdsBoundaryAndNorthOfLansing() throws {
        let region = try JSONDecoder().decode(OfflineRegion.self, from: manifest().data(using: .utf8)!)
        #expect(region.contains(.init(latitude: 42.28, longitude: -83.74)))
        #expect(region.contains(.init(latitude: 42.74, longitude: -84.55)))
        #expect(!region.contains(.init(latitude: 42.899, longitude: -84.55)))
        #expect(!region.contains(.init(latitude: 43, longitude: -84.55)))
    }

    private func manifest() -> String {
        """
        {"schema":1,"regionID":"southern-michigan","name":"Southern Michigan","bounds":[-87,41.65,-82.1,42.90],"sourceDate":"2026-09-02T20:20:51Z","roadCount":1,"knownLimitRoadCount":1,"attribution":"© OpenStreetMap contributors","license":"ODbL-1.0"}
        """
    }

    private func package(_ url: URL) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        PRAGMA application_id=1380925764; PRAGMA user_version=1;
        CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);
        INSERT INTO metadata VALUES('manifest','\(manifest())');
        CREATE TABLE roads(id INTEGER PRIMARY KEY,osm_id INTEGER,name TEXT,direction INTEGER,forward_limit TEXT,backward_limit TEXT,points TEXT,layer TEXT,highway TEXT);
        INSERT INTO roads VALUES(1,1,'Test Road',2,'35 mph','25 mph',X'a0c314ce806a33190100000000000000e0d017ce806a33190200000000000000','0','residential');
        CREATE VIRTUAL TABLE bounds USING rtree(id,min_lon,max_lon,min_lat,max_lat);
        INSERT INTO bounds VALUES(1,-83.75,-83.73,42.28,42.28);
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test func installPersistQueryReplaceAndRemovePackage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.roadar")
        try package(source)
        let directory = root.appendingPathComponent("saved")
        let worker = OfflineRoadWorker(directory: directory)
        #expect(try await worker.install(source, catalog: nil).roadCount == 1)
        let reopened = OfflineRoadWorker(directory: directory)
        #expect(try await reopened.load()?.name == "Southern Michigan")
        for i in 0..<3 {
            let time = now.addingTimeInterval(Double(i))
            let result = try await reopened.match(fix(time: time), now: time)
            if i == 2 { #expect(result.speedLimit == "35 mph") }
        }
        #expect(try await worker.install(source, catalog: nil).roadCount == 1)
        try await worker.remove()
        #expect(try await worker.load() == nil)
    }

    @Test func corruptAndWrongChecksumUpdatesPreserveSavedRoads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.roadar")
        try package(source)
        let worker = OfflineRoadWorker(directory: root.appendingPathComponent("saved"))
        _ = try await worker.install(source, catalog: nil)
        let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        let wrong = OfflineRoadCatalog(bytes: Int64(bytes), sha256: String(repeating: "0", count: 64), sourceDate: "", downloadURL: nil)
        await #expect(throws: (any Error).self) { try await worker.install(source, catalog: wrong) }
        try Data("not a database".utf8).write(to: source)
        await #expect(throws: (any Error).self) { try await worker.install(source, catalog: nil) }
        #expect(try await worker.load()?.roadCount == 1)
    }
    @Test func compressedImportAndTruncatedUpdate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.roadar")
        try package(source)
        let compressed = root.appendingPathComponent("source.roadar.gz")
        let data = try Data(contentsOf: source)
        let output = try #require(gzopen(compressed.path, "wb"))
        let written = data.withUnsafeBytes { gzwrite(output, $0.baseAddress, UInt32(data.count)) }
        #expect(written == data.count)
        #expect(gzclose(output) == Z_OK)
        let worker = OfflineRoadWorker(directory: root.appendingPathComponent("saved"))
        _ = try await worker.install(compressed, catalog: nil)
        for i in 0..<3 {
            let time = now.addingTimeInterval(Double(i))
            let result = try await worker.match(fix(time: time), now: time)
            if i == 2 { #expect(result.road == "Test Road") }
        }
        let archive = try Data(contentsOf: compressed)
        try archive.prefix(archive.count / 2).write(to: compressed)
        await #expect(throws: (any Error).self) { try await worker.install(compressed, catalog: nil) }
        #expect(try await worker.load()?.roadCount == 1)
    }

    @Test func cancelledInstallationPreservesCurrentPackage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.roadar")
        try package(source)
        let worker = OfflineRoadWorker(directory: root.appendingPathComponent("saved"))
        _ = try await worker.install(source, catalog: nil)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.install(source, catalog: nil)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try await worker.load()?.roadCount == 1)
    }

}
