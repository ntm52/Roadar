import SwiftUI
import CoreLocation
import MapKit

struct TripPanel: View {
    @Bindable var trip: TripStore
    let location: CLLocation?
    let onEnd: () -> Void
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(trip.engine?.state == .arrived ? "Arrived" : "To \(trip.destination?.name ?? "destination")")
                    .font(.headline).lineLimit(1)
                Spacer()
                Button(trip.engine?.state == .arrived ? "Done" : "End trip", action: onEnd)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trip.engine?.state == .arrived ? RoadarTheme.accent : Color(red: 1, green: 0.57, blue: 0.52))
                    .frame(minHeight: 44)
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
                        Text(maneuver.instruction).font(.title2.bold()).lineLimit(3)
                        Text(max(0, maneuver.distance - engine.progress) < 15 ? "Now" : "In \(distance(maneuver.distance - engine.progress))")
                            .font(.title3.weight(.semibold)).foregroundStyle(RoadarTheme.accent)
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
                        .buttonStyle(RoadarPrimaryButtonStyle())
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
                    Button { showsSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .accessibilityLabel("Reroute policy")
                }.font(.subheadline)
            }
        }
        .sheet(isPresented: $showsSettings) {
            RoutePolicyView(trip: trip)
        }
    }

    private func distance(_ meters: Double) -> String {
        Measurement(value: max(0, meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
