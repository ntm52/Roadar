import CoreLocation
import MapKit
import Testing
@testable import Roadar

@MainActor
struct RoadarTests {
    private func place() -> MKMapItem {
        MKMapItem(location: CLLocation(latitude: 42.28, longitude: -83.74), address: nil)
    }

    @Test func missingLocationKeepsDestinationAndExplainsRecovery() async {
        let store = RoutePreviewStore()
        let destination = place()
        store.select(destination)
        await store.preview(from: nil, driving: false)
        #expect(store.destination === destination)
        #expect(store.routes.isEmpty)
        #expect(store.routeMessage != nil)
        #expect(!store.isRouting)
    }

    @Test func staleAndInaccurateLocationsDoNotRequestRoutes() async {
        for (age, accuracy) in [(60.0, 10.0), (0.0, 500.0), (0.0, -1.0)] {
            let store = RoutePreviewStore()
            store.select(place())
            let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 42.28, longitude: -83.74), altitude: 0,
                horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: Date().addingTimeInterval(-age))
            await store.preview(from: location, driving: true)
            #expect(store.routeMessage != nil)
            #expect(!store.isRouting)
        }
    }

    @Test func clearingDestinationResetsPreview() async {
        let store = RoutePreviewStore()
        store.select(place())
        await store.preview(from: nil, driving: false)
        store.clearDestination()
        #expect(store.destination == nil)
        #expect(store.routeMessage == nil)
        #expect(store.activeRoute == nil)
    }

    @Test func whitespaceSearchDoesNotStartRequest() async {
        let store = RoutePreviewStore()
        store.query = "   \n"
        await store.searchPlaces(in: MKCoordinateRegion())
        #expect(!store.isSearching)
        #expect(store.results.isEmpty)
        #expect(store.searchMessage == nil)
    }
}
