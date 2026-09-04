import SwiftUI
import CoreLocation

struct WorkZonePanel: View {
    let store: WorkZoneStore
    let location: CLLocation?
    let engine: GuidanceEngine?
    @State private var selectedZone: WorkZoneFeed.Zone?
    @State private var showsConnection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MDOT work zones").font(.subheadline.bold())
                Spacer()
                Button("Connection") { showsConnection = true }.font(.caption.weight(.semibold)).frame(minHeight: 44)
            }
            TimelineView(.periodic(from: .now, by: 5)) { context in
                VStack(alignment: .leading, spacing: 6) {
                if let feed = store.feed {
                    Text("Source updated \(feed.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                    if feed.isFresh(at: context.date) {
                        if let engine {
                            Text("Possible work zones along route").font(.caption.bold())
                            if engine.state == .following && GuidanceEngine.accepts(engine.lastFix, at: context.date) {
                                let candidates = feed.alongRoute(engine, at: context.date)
                                if candidates.isEmpty {
                                    Text("No confident geometry matches in the next 5 km. Coverage may be incomplete.").font(.caption)
                                }
                                ForEach(Array(candidates.prefix(3))) { candidate in
                                    zoneButton(candidate.zone, subtitle: candidate.distance < 30 ? "Near this route section" : "About \(Int(candidate.distance.rounded())) m along route")
                                }
                            } else {
                                Text("Route matches paused until your position on the route is reliable.").font(.caption)
                            }
                            Text("Possible matches only · Nearby parallel or stacked roads may be indistinguishable. No spoken work-zone alerts.")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            let zones = feed.nearby(location, at: context.date)
                            if let location, abs(context.date.timeIntervalSince(location.timestamp)) <= 30,
                               location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65 {
                                if zones.isEmpty {
                                    Text("No nearby work zones to display. Coverage may be incomplete.").font(.caption)
                                }
                            } else {
                                Text("Waiting for a fresh, precise location to find nearby work zones.").font(.caption)
                            }
                            ForEach(Array(zones.prefix(3))) { zone in
                                zoneButton(zone, subtitle: nil)
                            }
                            Text("Within 5 km · May be on another road or behind you. Start a trip to filter against its route.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if feed.rejectedCount > 0 {
                            Text("Some source records could not be verified and are withheld.").font(.caption2)
                        }
                    } else {
                        Text("Source data is out of date. Work zones are withheld.").font(.caption)
                    }
                } else {
                    Text(store.message).font(.caption).foregroundStyle(.secondary)
                }
                }
            }
            if store.isLoading { ProgressView("Updating work zones…").font(.caption) }
        }
        .sheet(isPresented: $showsConnection) { MDOTConnectionView(store: store) }
        .sheet(item: $selectedZone) { zone in
            WorkZoneDetails(zone: zone, sourceUpdated: store.feed?.updatedAt)
        }
    }

    private func zoneButton(_ zone: WorkZoneFeed.Zone, subtitle: String?) -> some View {
        Button { selectedZone = zone } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(zone.roads) · \(zone.direction)").font(.caption.bold())
                if let subtitle { Text(subtitle).font(.caption2) }
                Text(zone.details).font(.caption).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityHint("Show full work zone details and scheduled dates")
    }

}

private struct MDOTConnectionView: View {
    let store: WorkZoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("MDOT RIDE") {
                    Text("Paste your MDOT API key here. It stays in this device’s Keychain and is sent only to MDOT’s data service.")
                    SecureField("MDOT API key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("mdotAPIKey")
                    Button("Save and connect") {
                        store.saveKey(key)
                        key = ""
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if store.hasKey {
                        Button("Refresh work zones") { store.refresh() }.disabled(store.isLoading)
                        Button("Disconnect and remove saved key", role: .destructive) { store.disconnect() }
                    }
                    Text(store.message).font(.caption)
                }
                Section("Coverage") {
                    Text("Refreshes at most once every five minutes while driving with Roadar open. Data older than 15 minutes is withheld. This feed supplies work zones, not police reports or current speed limits.")
                    Text("During a driving trip, work-zone geometry is compared with the route. Possible matches require sustained alignment in the same direction; passed records and ambiguous matches are withheld. This cannot confirm road identity. No spoken work-zone alerts are emitted.")
                    Link("MDOT RIDE datasets", destination: URL(string: "https://mdotridediscovery.state.mi.us/")!)
                }
            }
            .roadarSheet()
            .navigationTitle("Road information")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onDisappear { key = "" }
        }
    }
}


private struct WorkZoneDetails: View {
    let zone: WorkZoneFeed.Zone
    let sourceUpdated: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(zone.roads) {
                    Text(zone.direction.capitalized)
                    Text(zone.details)
                }
                Section("Reported schedule") {
                    LabeledContent("Starts", value: zone.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Ends", value: zone.end.formatted(date: .abbreviated, time: .shortened))
                    Text("Dates are shown in your device’s time zone. Scheduled dates do not confirm workers are present.").font(.caption)
                }
                Section("Source") {
                    Text("MDOT RIDE · WZDx work-zone feed")
                    if let sourceUpdated {
                        Text("Feed updated \(sourceUpdated.formatted(date: .abbreviated, time: .shortened))")
                        Text("This is the feed refresh time, not a confirmation of this event.").font(.caption)
                    }
                    Text("Record: \(zone.id)").font(.caption)
                    Text("This record does not establish your current road, speed limit, or the presence of workers.").font(.caption)
                }
            }
            .roadarSheet()
            .navigationTitle("Work zone")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
