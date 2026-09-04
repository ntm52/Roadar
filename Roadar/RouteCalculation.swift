import MapKit

/// A cancellable request boundary so trip lifecycle races can be replayed without a network.
@MainActor
protocol RouteCalculation: AnyObject {
    func calculateRoutes() async throws -> [MKRoute]
    func cancel()
}

extension MKDirections: RouteCalculation {
    func calculateRoutes() async throws -> [MKRoute] {
        try await calculate().routes
    }
}
