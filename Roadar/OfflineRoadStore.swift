import Foundation
import Observation
import CoreLocation
import CryptoKit
import zlib

nonisolated struct OfflineRoadCatalog: Decodable, Sendable {
    let bytes: Int64
    var installedBytes: Int64? = nil
    let sha256: String
    let sourceDate: String
    let downloadURL: URL?

    static func bundled() -> Self? {
        guard let url = Bundle.main.url(forResource: "southern-michigan", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

actor OfflineRoadWorker {
    private var database: OfflineRoadDatabase?
    private var matcher = OfflineRoadMatcher()
    private let directory: URL
    private var packageURL: URL { directory.appendingPathComponent("southern-michigan.roadar") }

    init(directory: URL) { self.directory = directory }

    func load() throws -> OfflineRegion? {
        guard FileManager.default.fileExists(atPath: packageURL.path) else { return nil }
        database = try OfflineRoadDatabase(url: packageURL)
        matcher.reset()
        return database?.region
    }

    func install(_ source: URL, catalog: OfflineRoadCatalog?) throws -> OfflineRegion {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(UUID().uuidString + ".roadar")
        defer { try? manager.removeItem(at: staged) }
        let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0, bytes <= 200_000_000 else { throw OfflineRoadError.tooLarge }
        if let catalog {
            guard Int64(bytes) == catalog.bytes else { throw OfflineRoadError.invalidPackage }
            let file = try FileHandle(forReadingFrom: source)
            defer { try? file.close() }
            var hash = SHA256()
            while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == catalog.sha256 else {
                throw OfflineRoadError.invalidPackage
            }
        }
        guard let compressed = gzopen(source.path, "rb") else { throw OfflineRoadError.invalidPackage }
        defer { gzclose(compressed) }
        guard manager.createFile(atPath: staged.path, contents: nil) else { throw OfflineRoadError.unavailable }
        let output = try FileHandle(forWritingTo: staged)
        defer { try? output.close() }
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        var expanded: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = gzread(compressed, &buffer, UInt32(buffer.count))
            guard count >= 0 else { throw OfflineRoadError.invalidPackage }
            if count == 0 { break }
            expanded += Int64(count)
            guard expanded <= 500_000_000 else { throw OfflineRoadError.tooLarge }
            try output.write(contentsOf: Data(buffer.prefix(Int(count))))
        }
        try output.synchronize()
        if let expected = catalog?.installedBytes, expanded != expected { throw OfflineRoadError.invalidPackage }
        var candidate: OfflineRoadDatabase? = try OfflineRoadDatabase(url: staged, verify: true)
        guard let region = candidate?.region else { throw OfflineRoadError.invalidPackage }
        if let old = database?.region.date, let new = region.date, new < old {
            throw OfflineRoadError.invalidPackage
        }
        // Confirm the spatial query/schema before replacing a working package.
        _ = try candidate?.nearby(latitude: 42.28, longitude: -83.74)
        candidate = nil
        try Task.checkCancellation()
        if manager.fileExists(atPath: packageURL.path) {
            _ = try manager.replaceItemAt(packageURL, withItemAt: staged)
        } else {
            try manager.moveItem(at: staged, to: packageURL)
        }
        // Reopen at the permanent path: SQLite may reject uncached reads after a file moves.
        database = try OfflineRoadDatabase(url: packageURL)
        matcher.reset()
        var fileURL = packageURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? fileURL.setResourceValues(values)
        return region
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: packageURL.path) {
            try FileManager.default.removeItem(at: packageURL)
        }
        database = nil
        matcher.reset()
    }

    func reset() { matcher.reset() }

    func match(_ fix: OfflineRoadFix, now: Date) throws -> OfflineRoadMatch {
        guard let database else { return OfflineRoadMatch(message: "Import a Southern Michigan road download to get started.") }
        guard database.region.contains(CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)) else {
            matcher.reset()
            return OfflineRoadMatch(message: "Outside the downloaded area, or too close to its edge.")
        }
        return matcher.match(fix, roads: try database.nearby(latitude: fix.latitude, longitude: fix.longitude), now: now)
    }
}

@MainActor @Observable
final class OfflineRoadStore {
    private(set) var region: OfflineRegion?
    private(set) var match = OfflineRoadMatch(message: "Add a road download for offline road information.")
    private(set) var isBusy = false
    private(set) var progress: String?
    private(set) var errorMessage: String?
    let catalog = OfflineRoadCatalog.bundled()
    private let worker: OfflineRoadWorker
    private var operation: Task<Void, Never>?
    private var matchTask: Task<Void, Never>?
    private var revision = UUID()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineRoads", isDirectory: true)
        worker = OfflineRoadWorker(directory: base)
    }

    func load() async {
        do { region = try await worker.load() }
        catch { errorMessage = "The saved road package could not be opened. Import it again." }
    }

    func update(_ location: CLLocation?) {
        if isBusy && location != nil { return }
        matchTask?.cancel()
        revision = UUID()
        let requested = revision
        guard let location else {
            match = OfflineRoadMatch(message: "Road information is paused until location is available.")
            matchTask = Task { await worker.reset() }
            return
        }
        let fix = OfflineRoadFix(location)
        matchTask = Task {
            do {
                let result = try await worker.match(fix, now: .now)
                guard !Task.isCancelled, revision == requested else { return }
                match = result
            } catch {
                guard !Task.isCancelled, revision == requested else { return }
                match = OfflineRoadMatch(message: "Downloaded roads could not be read. Import the package again.")
            }
        }
    }

    func importFile(_ url: URL) {
        guard !isBusy else { return }
        isBusy = true
        progress = "Checking and saving roads…"
        errorMessage = nil
        update(nil)
        operation = Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() }; finish() }
            do {
                region = try await worker.install(url, catalog: catalog)
                match = OfflineRoadMatch(message: "Roads saved. Move along a road to establish your position.")
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func download() {
        guard !isBusy, let catalog, let url = catalog.downloadURL, url.scheme == "https" else { return }
        isBusy = true
        progress = "Downloading \(ByteCountFormatter.string(fromByteCount: catalog.bytes, countStyle: .file))…"
        errorMessage = nil
        operation = Task {
            defer { finish() }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 900
            config.allowsCellularAccess = false
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            do {
                let (temporary, response) = try await session.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.url?.scheme == "https" else { throw OfflineRoadError.unavailable }
                try Task.checkCancellation()
                progress = "Checking and saving roads…"
                update(nil)
                region = try await worker.install(temporary, catalog: catalog)
                match = OfflineRoadMatch(message: "Roads saved. Move along a road to establish your position.")
            } catch is CancellationError { }
            catch let error as URLError where error.code == .cancelled { }
            catch { errorMessage = "Download did not complete. Use Wi-Fi and try again. Your existing roads are kept." }
        }
    }

    func cancel() { operation?.cancel() }

    func remove() {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        update(nil)
        operation = Task {
            defer { finish() }
            do {
                try await worker.remove()
                region = nil
                match = OfflineRoadMatch(message: "Add a road download for offline road information.")
            } catch { errorMessage = "The download could not be removed. Try again." }
        }
    }

    private func finish() { isBusy = false; progress = nil; operation = nil }
}
