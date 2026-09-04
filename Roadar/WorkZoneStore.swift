import Foundation
import Observation

@MainActor
@Observable
final class WorkZoneStore {
    private(set) var feed: WorkZoneFeed?
    private(set) var isLoading = false
    private(set) var hasKey = MDOTCredential.read() != nil
    private(set) var message = "Connect MDOT RIDE to load work zones."
    private(set) var lastChecked: Date?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastAttempt = Date.distantPast
    private var session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    init() {
        if hasKey { message = "MDOT connected. Waiting for an update." }
    }

    func saveKey(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            message = "Enter a valid API key."; return
        }
        guard MDOTCredential.save(key) else { message = "Could not save the key securely. Try again."; return }
        pause()
        hasKey = true
        feed = nil
        lastAttempt = .distantPast
        message = "MDOT key saved on this device."
        refresh()
    }

    func disconnect() {
        pause()
        guard MDOTCredential.remove() else { message = "Could not remove the saved key."; return }
        hasKey = false
        feed = nil
        lastChecked = nil
        message = "MDOT disconnected. Saved key removed from this device."
    }

    func pause() {
        generation = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }

    func refresh(at now: Date = .now) {
        guard hasKey, !isLoading else { return }
        guard now.timeIntervalSince(lastAttempt) >= 300 else { return }
        guard let key = MDOTCredential.read() else {
            message = "Unlock the device to access the saved MDOT key."; return
        }
        lastAttempt = now
        isLoading = true
        let id = UUID()
        generation = id
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(key, forHTTPHeaderField: "api_key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == id { self.isLoading = false; self.task = nil } }
            do {
                let (data, response) = try await self.session.data(for: request)
                guard self.generation == id else { return }
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard http.statusCode == 200 else {
                    self.feed = nil
                    self.message = http.statusCode == 401 || http.statusCode == 403
                        ? "MDOT rejected this key. Check your API key and access."
                        : "MDOT is unavailable. Retry after five minutes."
                    return
                }
                let decoded = try WorkZoneFeed.decode(data)
                self.lastChecked = .now
                self.feed = decoded
                self.message = decoded.isFresh(at: .now)
                    ? "MDOT work-zone feed received."
                    : "MDOT data is stale or has an invalid time. Work zones are withheld."
            } catch {
                guard self.generation == id else { return }
                self.feed = nil
                // Never interpolate errors: network errors may contain credential-bearing request details.
                self.message = "Could not load a valid MDOT feed. Work zones are unavailable; retry after five minutes."
            }
        }
    }

    static let endpoint = URL(string: "https://mdotridedata.state.mi.us/api/v1/organization/michigan_department_of_transportation/dataset/work_zone_information/query?limit=1&_format=json")!
}

/// Never forward the API-key header to a redirect destination.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
