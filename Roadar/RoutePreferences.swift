import Foundation

/// Only reroute thresholds are persisted; destinations and location history are not stored here.
@MainActor
final class RoutePreferences {
    private let defaults: UserDefaults
    private static let key = "routePolicy.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> ReroutePolicy {
        guard let values = defaults.dictionary(forKey: Self.key),
              let seconds = values["seconds"] as? Double,
              let fraction = values["fraction"] as? Double,
              let cooldown = values["cooldown"] as? Double,
              (30...300).contains(seconds), (0.05...0.3).contains(fraction),
              (120...600).contains(cooldown) else { return ReroutePolicy() }
        return ReroutePolicy(minimumSecondsSaved: seconds, minimumFractionSaved: fraction, cooldown: cooldown)
    }

    func save(_ policy: ReroutePolicy) {
        guard (30...300).contains(policy.minimumSecondsSaved),
              (0.05...0.3).contains(policy.minimumFractionSaved),
              (120...600).contains(policy.cooldown) else { return }
        defaults.set(["seconds": policy.minimumSecondsSaved, "fraction": policy.minimumFractionSaved,
                      "cooldown": policy.cooldown], forKey: Self.key)
    }
}
