import Foundation
import Testing
@testable import Roadar

@MainActor
struct RoutePreferencesTests {
    @Test func thresholdsSurviveNewTripStoreAndResetToDefaults() throws {
        let suite = "RoadarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = TripStore(preferences: RoutePreferences(defaults: defaults))
        first.policy.minimumSecondsSaved = 180
        first.policy.minimumFractionSaved = 0.15
        first.policy.cooldown = 300
        let second = TripStore(preferences: RoutePreferences(defaults: defaults))
        #expect(second.policy.minimumSecondsSaved == 180)
        #expect(second.policy.minimumFractionSaved == 0.15)
        #expect(second.policy.cooldown == 300)
        second.policy = ReroutePolicy()
        let restored = RoutePreferences(defaults: defaults).load()
        #expect(restored.minimumSecondsSaved == 60)
        #expect(restored.minimumFractionSaved == 0.05)
        #expect(restored.cooldown == 120)
    }

    @Test func malformedOrOutOfBoundsPreferencesUseSafeDefaults() throws {
        let suite = "RoadarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for value: [String: Any] in [[:], ["seconds": -1.0, "fraction": 0.1, "cooldown": 300.0],
                                    ["seconds": 120.0, "fraction": 1.0, "cooldown": 300.0],
                                    ["seconds": 120.0, "fraction": 0.1, "cooldown": "bad"]] {
            defaults.set(value, forKey: "routePolicy.v1")
            #expect(RoutePreferences(defaults: defaults).load().minimumSecondsSaved == 60)
        }
    }
}
