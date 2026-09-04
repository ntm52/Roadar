import SwiftUI

struct RoutePolicyView: View {
    @Bindable var trip: TripStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Alternative route thresholds") {
                    Stepper("Save at least \(Int(trip.policy.minimumSecondsSaved)) seconds", value: $trip.policy.minimumSecondsSaved, in: 30...300, step: 30)
                        .accessibilityIdentifier("secondsThreshold")
                    Stepper("Save at least \(Int((trip.policy.minimumFractionSaved * 100).rounded()))%", value: $trip.policy.minimumFractionSaved, in: 0.05...0.3, step: 0.05)
                    Stepper("Cooldown: \(Int(trip.policy.cooldown / 60)) minutes", value: $trip.policy.cooldown, in: 120...600, step: 60)
                    Button("Restore defaults") { trip.policy = ReroutePolicy() }
                        .accessibilityIdentifier("restoreRouteDefaults")
                }
                Section("How route checks work") {
                    Text("Both savings thresholds must pass. Faster alternatives require your selection. Confirmed off-route recovery chooses the fastest returned route and retries no more than every 30 seconds.")
                    Text("Your preferences are saved on this iPhone and apply to future trips.")
                    Text("Apple supplies the available routes. Remaining ETA is estimated from distance and the route’s original travel time; it is not continuously refreshed traffic data.")
                }
            }
            .roadarSheet()
            .navigationTitle("Route preferences")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
