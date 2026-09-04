import SwiftUI
import UniformTypeIdentifiers

struct OfflineRoadPanel: View {
    let store: OfflineRoadStore
    @State private var showsDownloads = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("OFFLINE ROAD CONTEXT", systemImage: "map")
                .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(RoadarTheme.accent)
            TimelineView(.periodic(from: .now, by: 5)) { context in
                let fresh = store.match.timestamp.map { context.date.timeIntervalSince($0) <= 15 } ?? false
                Text(fresh ? (store.match.road ?? "Road uncertain") : "Road uncertain")
                    .font(.title2.bold())
                Text("Speed limit: \(fresh ? (store.match.speedLimit ?? "Unknown") : "Unknown")")
                    .font(.subheadline)
                Text(!fresh && store.match.road != nil ? "Waiting for a fresh location." : store.match.message)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if store.region != nil { Text("© OpenStreetMap contributors").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Button("Road downloads") { showsDownloads = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityIdentifier("roadDownloads")
            }
        }
        .sheet(isPresented: $showsDownloads) { OfflineRoadDownloadsView(store: store) }
    }
}

struct OfflineRoadDownloadsView: View {
    let store: OfflineRoadStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var confirmsRemoval = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Southern Michigan", systemImage: "map")
                        .font(.headline)
                    Text("Lansing and south, with a buffer about 12 miles north of Lansing. Includes Ann Arbor, Detroit, Jackson and Kalamazoo within Michigan.")
                    Text("Road names, travel direction and available speed limits work without reception. Map imagery, place search and new routes still need internet.")
                        .foregroundStyle(.secondary)
                    if let catalog = store.catalog {
                        LabeledContent("Download size", value: ByteCountFormatter.string(fromByteCount: catalog.bytes, countStyle: .file))
                    }
                    if let installed = store.catalog?.installedBytes {
                        LabeledContent("Space on iPhone", value: ByteCountFormatter.string(fromByteCount: installed, countStyle: .file))
                    }
                }
                Section("On this iPhone") {
                    if let region = store.region {
                        Label("Ready offline", systemImage: "checkmark.circle.fill").foregroundStyle(RoadarTheme.accent)
                        if let date = region.date {
                            LabeledContent("OSM data", value: date.formatted(date: .abbreviated, time: .omitted))
                            if Date().timeIntervalSince(date) > 90 * 86_400 {
                                Text("This download is over 90 days old. Check for a newer package.").foregroundStyle(.orange)
                            }
                        }
                        Text("\(region.roadCount.formatted()) road sections. Speed limits are not available on every road.")
                        Button("Remove download", role: .destructive) { confirmsRemoval = true }
                            .disabled(store.isBusy)
                    } else {
                        Text("No road package saved yet.")
                    }
                    if let progress = store.progress {
                        ProgressView(progress)
                        Button("Cancel", action: store.cancel)
                    }
                    if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                }
                Section("Add or update") {
                    if store.catalog?.downloadURL != nil {
                        Button(store.region == nil ? "Download using Wi-Fi" : "Download current package", action: store.download)
                            .disabled(store.isBusy)
                    } else {
                        Text("The first package is available as a file. Import it below; direct downloads will appear once the package is published.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Import road package from Files") { importing = true }
                        .disabled(store.isBusy).accessibilityIdentifier("importRoadPackage")
                    Text("An update replaces the saved package only after validation. Allow space for both copies while updating.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("About this data") {
                    Text("Road matching is an estimate. Ambiguous roads and uncertain speed limits are withheld. Follow posted signs. MDOT work zones refresh separately while connected.")
                    Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("Source: Geofabrik Michigan extract", destination: URL(string: "https://download.geofabrik.de/north-america/us/michigan.html")!)
                }
            }
            .roadarSheet()
            .navigationTitle("Road downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result { store.importFile(url) }
            }
            .confirmationDialog("Remove Southern Michigan roads?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove download", role: .destructive, action: store.remove)
            }
        }
    }
}
