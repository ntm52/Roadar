import SwiftUI
import CoreLocation
import MapKit

struct TripPanel: View {
    @Bindable var trip: TripStore
    let location: CLLocation?
    let onEnd: () -> Void
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trip.engine?.state == .arrived ? "Arrived" : "To \(trip.destination?.name ?? "destination")")
                    .font(.headline).lineLimit(1)
                Spacer()
                Button(trip.engine?.state == .arrived ? "Done" : "End trip", action: onEnd)
                    .accessibilityIdentifier("endGuidance")
            }
            if let engine = trip.engine {
                switch engine.state {
                case .arrived:
                    Label("You’ve reached the route endpoint.", systemImage: "flag.checkered")
                case .locating, .uncertain:
                    Label("Confirming your position… Guidance and ETA are paused.", systemImage: "location.slash")
                case .offRoute:
                    Label("Off route · Waiting for a replacement route", systemImage: "arrow.triangle.turn.up.right.diamond")
                case .following:
                    if let maneuver = engine.nextManeuver {
                        Text(maneuver.instruction).font(.title3.bold()).lineLimit(3)
                        Text(max(0, maneuver.distance - engine.progress) < 15 ? "Now" : "In \(distance(maneuver.distance - engine.progress))")
                            .font(.subheadline)
                    } else {
                        Text("Continue to the route endpoint").font(.title3.bold())
                    }
                    HStack {
                        Text(distance(engine.remainingDistance))
                        Text("· About \(max(1, Int(ceil(engine.remainingTime / 60)))) min")
                        Spacer()
                    }.font(.subheadline).monospacedDigit()
                    ProgressView(value: engine.progress, total: max(1, engine.route.length))
                    if let fix = engine.lastFix {
                        Text("Estimated arrival \(fix.timestamp.addingTimeInterval(engine.remainingTime).formatted(date: .omitted, time: .shortened)) · Based on distance remaining")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if trip.isRefreshing { ProgressView("Checking routes…") }
            if let message = trip.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let proposal = trip.proposal {
                Text("\(proposal.name) · \(max(1, Int(ceil(proposal.expectedTravelTime / 60)))) min · \(proposal.steps.filter { !$0.instructions.isEmpty }.count) steps")
                    .font(.subheadline)
                HStack {
                    Button("Use alternative") { trip.acceptProposal(location: location) }
                        .buttonStyle(.borderedProminent)
                    Button("Keep route") { trip.keepRoute() }
                }
            }
            if trip.engine?.state != .arrived {
                HStack {
                    Button(trip.engine?.state == .following ? "Check alternatives" : "Recalculate from here") {
                        Task { await trip.refresh(from: location, forceRecovery: trip.engine?.state != .following) }
                    }
                        .disabled(trip.isRefreshing || !GuidanceEngine.accepts(location, at: .now))
                    Spacer()
                    Button { showsSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Reroute policy")
                }.font(.subheadline)
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                Form {
                    Section("Alternative route thresholds") {
                        Stepper("Save at least \(Int(trip.policy.minimumSecondsSaved)) seconds", value: $trip.policy.minimumSecondsSaved, in: 30...300, step: 30)
                        Stepper("Save at least \(Int((trip.policy.minimumFractionSaved * 100).rounded()))%", value: $trip.policy.minimumFractionSaved, in: 0.05...0.3, step: 0.05)
                        Stepper("Cooldown: \(Int(trip.policy.cooldown / 60)) minutes", value: $trip.policy.cooldown, in: 120...600, step: 60)
                    }
                    Text("Both savings thresholds must pass. Alternatives require your selection. Confirmed off-route recovery chooses the fastest returned route and retries no more than every 30 seconds. Settings apply for this app session.")
                    Text("Apple supplies the available routes. Remaining ETA is estimated from distance and the route’s original travel time; it is not continuously refreshed traffic data.")
                }
                .navigationTitle("Route policy")
                .toolbar { Button("Done") { showsSettings = false } }
            }
        }
    }

    private func distance(_ meters: Double) -> String {
        Measurement(value: max(0, meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
