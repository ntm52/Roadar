import Foundation
import SQLite3
import CoreLocation

nonisolated struct OfflineRegion: Codable, Sendable {
    let schema: Int
    let regionID: String
    let name: String
    let bounds: [Double] // west, south, east, north
    let sourceDate: String
    let roadCount: Int
    let knownLimitRoadCount: Int
    let attribution: String
    let license: String

    var date: Date? { ISO8601DateFormatter().date(from: sourceDate) }
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard bounds.count == 4 else { return false }
        // Withhold at crop edges where the candidate road set may be incomplete.
        return coordinate.longitude > bounds[0] + 0.002 && coordinate.longitude < bounds[2] - 0.002
            && coordinate.latitude > bounds[1] + 0.002 && coordinate.latitude < bounds[3] - 0.002
    }
}

nonisolated struct OfflineRoad: Sendable {
    let id: Int64
    let osmID: Int64
    let name: String
    let direction: Int
    let forwardLimit: String?
    let backwardLimit: String?
    let points: [[Double]] // longitude, latitude, OSM node ID
}

nonisolated enum OfflineRoadError: Error, LocalizedError {
    case invalidPackage, tooLarge, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidPackage: "This is not a valid Southern Michigan road package. Your existing download is unchanged."
        case .tooLarge: "This package exceeds the supported download or storage limit."
        case .unavailable: "The offline road package could not be read. Try importing it again."
        }
    }
}

/// Confined to OfflineRoadWorker. The phone reads a small spatial query, never the whole state.
nonisolated final class OfflineRoadDatabase {
    private var handle: OpaquePointer?
    let region: OfflineRegion

    init(url: URL, verify: Bool = false) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 500_000_000 else { throw OfflineRoadError.tooLarge }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            throw OfflineRoadError.invalidPackage
        }
        handle = db
        do {
            sqlite3_exec(db, "PRAGMA trusted_schema=OFF", nil, nil, nil)
            sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 2_000_000)
            guard try Self.scalar(db, "PRAGMA application_id") == "1380925764",
                  try Self.scalar(db, "PRAGMA user_version") == "1",
                  let json = try Self.scalar(db, "SELECT value FROM metadata WHERE key='manifest'"),
                  let data = json.data(using: .utf8), data.count < 16_384 else { throw OfflineRoadError.invalidPackage }
            let manifest = try JSONDecoder().decode(OfflineRegion.self, from: data)
            guard manifest.schema == 1, manifest.regionID == "southern-michigan",
                  manifest.bounds == [-87.0, 41.65, -82.1, 42.90],
                  manifest.roadCount > 0, manifest.roadCount < 2_000_000,
                  manifest.knownLimitRoadCount >= 0, manifest.knownLimitRoadCount <= manifest.roadCount,
                  manifest.license == "ODbL-1.0", let date = manifest.date,
                  date.timeIntervalSinceNow <= 86_400 else { throw OfflineRoadError.invalidPackage }
            if verify {
                guard try Self.scalar(db, "PRAGMA quick_check") == "ok",
                      try Self.scalar(db, "SELECT count(*) FROM roads") == String(manifest.roadCount),
                      try Self.scalar(db, "SELECT count(*) FROM bounds") == String(manifest.roadCount)
                else { throw OfflineRoadError.invalidPackage }
            }
            region = manifest
        } catch {
            sqlite3_close(db)
            handle = nil
            throw OfflineRoadError.invalidPackage
        }
    }

    deinit { if let handle { sqlite3_close(handle) } }

    private static func scalar(_ db: OpaquePointer, _ sql: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw OfflineRoadError.invalidPackage }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw OfflineRoadError.invalidPackage }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }

    func nearby(latitude: Double, longitude: Double) throws -> [OfflineRoad] {
        guard let handle else { throw OfflineRoadError.unavailable }
        var statement: OpaquePointer?
        let sql = """
        SELECT r.id,r.osm_id,r.name,r.direction,r.forward_limit,r.backward_limit,r.points
        FROM bounds b JOIN roads r ON r.id=b.id
        WHERE b.min_lon<=? AND b.max_lon>=? AND b.min_lat<=? AND b.max_lat>=? LIMIT 501
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw OfflineRoadError.unavailable }
        defer { sqlite3_finalize(statement) }
        let delta = 100.0 / 111_195
        for (index, value) in [longitude + delta / cos(latitude * .pi / 180), longitude - delta / cos(latitude * .pi / 180), latitude + delta, latitude - delta].enumerated() {
            sqlite3_bind_double(statement, Int32(index + 1), value)
        }
        var roads: [OfflineRoad] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw NSError(domain: "Roadar.SQLite", code: Int(result), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
            }
            guard roads.count < 500 else { throw OfflineRoadError.unavailable }
            func string(_ index: Int32) -> String? {
                sqlite3_column_text(statement, index).map { String(cString: $0) }
            }
            guard let name = string(2), name.count <= 500,
                  let blob = sqlite3_column_blob(statement, 6),
                  sqlite3_column_type(statement, 6) == SQLITE_BLOB else { throw OfflineRoadError.invalidPackage }
            let byteCount = Int(sqlite3_column_bytes(statement, 6))
            guard byteCount >= 32, byteCount <= 480_000, byteCount % 16 == 0 else { throw OfflineRoadError.invalidPackage }
            var points: [[Double]] = []
            for offset in stride(from: 0, to: byteCount, by: 16) {
                let lon = Double(Int32(littleEndian: blob.loadUnaligned(fromByteOffset: offset, as: Int32.self))) / 1e7
                let lat = Double(Int32(littleEndian: blob.loadUnaligned(fromByteOffset: offset + 4, as: Int32.self))) / 1e7
                let node = Int64(littleEndian: blob.loadUnaligned(fromByteOffset: offset + 8, as: Int64.self))
                guard (-180...180).contains(lon), (-90...90).contains(lat), node > 0 else { throw OfflineRoadError.invalidPackage }
                points.append([lon, lat, Double(node)])
            }
            let direction = Int(sqlite3_column_int(statement, 3))
            guard [-1, 0, 1, 2].contains(direction) else { throw OfflineRoadError.invalidPackage }
            func limit(_ index: Int32) throws -> String? {
                guard let value = string(index) else { return nil }
                guard value.range(of: #"^\d{1,3}(?:\.\d+)? (?:mph|km/h)$"#, options: .regularExpression) != nil else { throw OfflineRoadError.invalidPackage }
                return value
            }
            roads.append(OfflineRoad(id: sqlite3_column_int64(statement, 0), osmID: sqlite3_column_int64(statement, 1),
                name: name, direction: Int(sqlite3_column_int(statement, 3)), forwardLimit: try limit(4), backwardLimit: try limit(5), points: points))
        }
        return roads
    }
}
