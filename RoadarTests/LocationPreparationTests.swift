import CoreLocation
import Testing
@testable import Roadar

@MainActor
struct LocationPreparationTests {
    @Test func stationaryRoutePreparationDoesNotRequireMovement() {
        for driving in [false, true] {
            #expect(LocationStore.distanceFilter(navigating: false, preparingRoute: true, driving: driving) == kCLDistanceFilterNone)
            #expect(LocationStore.distanceFilter(navigating: true, preparingRoute: false, driving: driving) == kCLDistanceFilterNone)
            #expect(LocationStore.distanceFilter(navigating: false, preparingRoute: false, driving: driving) == (driving ? 10 : 5))
        }
    }

    @Test func waitingExplainsAgeSeparatelyFromAccuracy() async {
        let now = Date.now
        func fix(age: Double, accuracy: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: 42.28, longitude: -83.74), altitude: 0,
                horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: now.addingTimeInterval(-age))
        }
        #expect(RoutePreviewStore.locationWaitMessage(nil, at: now).contains("Finding"))
        #expect(RoutePreviewStore.locationWaitMessage(fix(age: 20, accuracy: 5), at: now).contains("Refreshing"))
        #expect(RoutePreviewStore.locationWaitMessage(fix(age: 0, accuracy: 80), at: now).contains("accuracy"))
        // A fresh fix at the same coordinates becomes eligible without requiring movement.
        #expect(!GuidanceEngine.accepts(fix(age: 20, accuracy: 5), at: now))
        #expect(GuidanceEngine.accepts(fix(age: 0, accuracy: 5), at: now))
    }
}
