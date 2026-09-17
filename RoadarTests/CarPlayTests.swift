import CarPlay
import CoreLocation
import Testing
@testable import Roadar

@MainActor
struct CarPlayTests {
    private var route: GuidanceRoute {
        GuidanceRoute(coordinates: [.init(latitude: 42, longitude: -83), .init(latitude: 42.01, longitude: -83)],
            maneuvers: [.init(instruction: "Start", distance: 0), .init(instruction: "Turn onto Main Street", distance: 300),
                        .init(instruction: "Arrive", distance: 1000)], expectedTravelTime: 120)
    }

    @Test func carPlayKeepsGuidanceEnabledWhenPhoneLocks() {
        let session = AppSession()
        session.setPhoneActive(true)
        session.setCarPlayConnected(true)
        session.setPhoneActive(false)
        #expect(session.guidanceEnabled)
        #expect(session.mode == .driving)
        session.setCarPlayConnected(false)
        #expect(!session.guidanceEnabled)
    }

    @Test func disconnectPreservesForegroundPhoneActivity() {
        let session = AppSession()
        session.setPhoneActive(true)
        session.setCarPlayConnected(true)
        session.setCarPlayConnected(false)
        #expect(session.guidanceEnabled)
        session.setPhoneActive(false)
    }

    @Test func maneuversAdvanceWithSameToleranceAsPhone() {
        #expect(CarPlayGuidance.upcomingIndices(route: route, progress: 0) == [0, 1])
        #expect(CarPlayGuidance.upcomingIndices(route: route, progress: 11) == [1, 2])
        #expect(CarPlayGuidance.upcomingIndices(route: route, progress: 310) == [1, 2])
        #expect(CarPlayGuidance.upcomingIndices(route: route, progress: 311) == [2])
    }

    @Test func estimatesSeparateStepDistanceFromRemainingDistance() {
        let maneuvers = CarPlayGuidance.maneuvers(for: route)
        #expect(maneuvers[1].instructionVariants == ["Turn onto Main Street"])
        #expect(maneuvers[1].initialTravelEstimates?.distanceRemaining.value == 300)
        #expect(maneuvers[2].initialTravelEstimates?.distanceRemaining.value == 700)
        #expect(maneuvers[1].symbolImage == nil)
        #expect(CarPlayGuidance.time(for: -10, route: route) == 0)
    }
}
