import SwiftUI
import MapKit
import CoreLocation

private enum TravelMode: String, CaseIterable {
    case walking = "Walking"
    case driving = "Driving"

    var symbol: String { self == .walking ? "figure.walk" : "car.fill" }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var location = LocationStore()
    @State private var mode: TravelMode = .walking
    @State private var followsHeading = false
    @State private var position: MapCameraPosition = .region(Self.startRegion)

    private static let startRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.30, longitude: -83.39),
        span: MKCoordinateSpan(latitudeDelta: 0.38, longitudeDelta: 0.85)
    )

    var body: some View {
        Map(position: $position) {
            if location.isAuthorized { UserAnnotation() }
        }
        .mapStyle(.standard(
            elevation: .flat,
            pointsOfInterest: mode == .walking ? .all : .excludingAll,
            showsTraffic: mode == .driving
        ))
        .mapControls { MapScaleView() }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
        }
        .onAppear {
            location.setDriving(mode == .driving)
            location.setActive(scenePhase == .active)
            if location.isAuthorized { recenter() }
        }
        .onChange(of: scenePhase) { _, phase in
            location.setActive(phase == .active)
        }
        .onChange(of: location.authorization) { _, _ in
            if location.isAuthorized {
                recenter()
            } else {
                position = .region(Self.startRegion)
            }
        }
        .onChange(of: location.location == nil) { wasMissing, isMissing in
            if wasMissing && !isMissing && !position.positionedByUser {
                recenter()
            }
        }
        .onChange(of: mode) { _, newMode in
            location.setDriving(newMode == .driving)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Roadar").font(.title2.bold())
                Text("Explore as you go")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: mode.symbol)
                .font(.title2).foregroundStyle(.teal)
                .accessibilityHidden(true)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    followsHeading.toggle()
                    recenter()
                } label: {
                    Label(followsHeading ? "Heading up" : "North up",
                          systemImage: followsHeading ? "location.north.line.fill" : "safari")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityHint("Changes map orientation and resumes following your location")
                .disabled(!location.isAuthorized)

                Button(action: recenter) {
                    Label("Recenter", systemImage: "location.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("recenter")
            }
            .buttonStyle(.bordered)
            .tint(.teal)

            Picker("Travel mode", selection: $mode) {
                ForEach(TravelMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("travelMode")

            TimelineView(.periodic(from: .now, by: 5)) { context in
                if let message = location.status(at: context.date) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "location.circle")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if location.authorization == .notDetermined {
                            Button("Enable location", action: location.requestAccess)
                                .accessibilityIdentifier("enableLocation")
                        } else if location.authorization == .denied || location.accuracy == .reducedAccuracy {
                            Button("Open Settings", action: openSettings)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(position.positionedByUser ? "Exploring map · Tap Recenter to follow" : "Minimap · No destination needed")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func recenter() {
        guard location.isAuthorized else {
            if location.authorization == .notDetermined {
                location.requestAccess()
            } else if location.authorization == .denied {
                openSettings()
            }
            return
        }
        withAnimation {
            position = .userLocation(followsHeading: followsHeading, fallback: .region(Self.startRegion))
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview {
    ContentView()
}
