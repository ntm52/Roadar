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
    @State private var preview = RoutePreviewStore()
    @State private var nearby = NearbyPlacesStore()
    @State private var trip = TripStore()
    @State private var workZones = WorkZoneStore()
    @State private var showsReplay = false
    @State private var showsSearch = false
    @State private var visibleRegion = Self.startRegion
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
            if mode == .walking && preview.destination == nil {
                ForEach(Array(nearby.places.enumerated()), id: \.offset) { _, place in
                    Annotation(place.name ?? "Nearby place", coordinate: place.location.coordinate) {
                        Button { selectPlace(place) } label: {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2).foregroundStyle(.teal)
                                .padding(4).background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("\(place.name ?? "Place"), \(NearbyPlacesStore.category(for: place))")
                    }
                }
            }
            if let destination = preview.destination {
                Marker(destination.name ?? "Destination", coordinate: destination.location.coordinate)
                    .tint(.orange)
            }
            if let route = trip.route {
                MapPolyline(route.polyline).stroke(.teal, lineWidth: 7)
            }
            ForEach(Array((trip.isActive ? [] : preview.routes).enumerated()), id: \.offset) { index, route in
                MapPolyline(route.polyline)
                    .stroke(index == preview.selectedRoute ? .teal : .gray.opacity(0.5), lineWidth: index == preview.selectedRoute ? 7 : 4)
            }
        }
        .mapStyle(.standard(
            elevation: .flat,
            pointsOfInterest: mode == .walking ? .all : .excludingAll,
            showsTraffic: mode == .driving
        ))
        .mapControls { MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
        .sheet(isPresented: $showsReplay) { RoadReplayView() }
        .sheet(isPresented: $showsSearch) {
            searchSheet
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
        }
        .task {
            while !Task.isCancelled {
                await trip.tick(location.isAuthorized ? location.location : nil)
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .task(id: scenePhase == .active && mode == .driving) {
            guard scenePhase == .active && mode == .driving else { return }
            while !Task.isCancelled {
                workZones.refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .onAppear {
            location.setDriving(mode == .driving)
            location.setActive(scenePhase == .active)
            if location.isAuthorized { recenter() }
        }
        .onChange(of: scenePhase) { _, phase in
            location.setActive(phase == .active)
            trip.setForeground(phase == .active)
            if phase != .active { nearby.reset(); workZones.pause() }
            else { refreshNearby() }
        }
        .onChange(of: location.authorization) { _, _ in
            if location.isAuthorized {
                recenter()
            } else {
                position = .region(Self.startRegion)
                nearby.reset()
                trip.update(nil)
            }
        }
        .onChange(of: location.location == nil) { wasMissing, isMissing in
            if wasMissing && !isMissing && preview.destination == nil {
                recenter()
            }
        }
        .onChange(of: location.location) { _, _ in
            trip.update(location.isAuthorized ? location.location : nil)
            if !position.positionedByUser && (preview.destination == nil || trip.isActive) { followLocation() }
            refreshNearby()
        }
        .onChange(of: location.heading) { _, _ in
            if followsHeading && !position.positionedByUser && (preview.destination == nil || trip.isActive) { followLocation() }
        }
        .onChange(of: mode) { _, newMode in
            location.setDriving(newMode == .driving)
            if newMode != .driving { workZones.pause() }
            preview.clearRoutes()
            if newMode == .driving { nearby.reset() } else { refreshNearby() }
            if preview.destination != nil { loadRoutes() }
            else if !position.positionedByUser { followLocation() }
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
            Button { showsSearch = true } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("searchPlaces")
            .disabled(trip.isActive)
            Image(systemName: mode.symbol)
                .font(.title2).foregroundStyle(.teal)
                .accessibilityHidden(true)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if trip.isActive {
                TripPanel(trip: trip, location: location.location) {
                    trip.end()
                    preview.clearDestination()
                    recenter()
                }
            } else if let destination = preview.destination {
                destinationPanel(destination)
            } else if mode == .walking {
                nearbyPanel
            } else {
                drivingPanel
            }
            if mode == .driving {
                WorkZonePanel(store: workZones, location: location.isAuthorized ? location.location : nil, engine: trip.engine)
            }
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
            .disabled(trip.isActive)

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
                    Text(trip.isActive ? "Foreground guidance · Keep Roadar open" : preview.destination != nil ? "Destination selected · Preview only" : (position.positionedByUser ? "Exploring map · Tap Recenter to follow" : "Minimap · No destination needed"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private var searchSheet: some View {
        NavigationStack {
            List {
                if preview.isSearching {
                    ProgressView("Searching places…")
                }
                if let message = preview.searchMessage {
                    Text(message).foregroundStyle(.secondary)
                }
                if preview.results.isEmpty && !preview.isSearching && preview.searchMessage == nil {
                    Text("Search for a business, place, or address near the map.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(preview.results.enumerated()), id: \.offset) { _, place in
                    Button {
                        selectPlace(place)
                        showsSearch = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name ?? "Place").foregroundStyle(.primary)
                            Text(place.address?.fullAddress ?? "Address unavailable")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Find a place")
            .searchable(text: $preview.query, prompt: "Places and addresses")
            .onSubmit(of: .search) {
                Task { await preview.searchPlaces(in: visibleRegion) }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSearch = false }
                }
            }
        }
    }

    private func destinationPanel(_ destination: MKMapItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.name ?? "Destination").font(.headline)
                    Text(destination.address?.fullAddress ?? "Address unavailable")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button {
                    preview.clearDestination()
                    if location.isAuthorized { recenter() }
                } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                .accessibilityLabel("Clear destination")
            }
            if let url = destination.url { Link("Place website", destination: url).font(.caption) }
            if let phone = destination.phoneNumber { Text(phone).font(.caption) }
            if preview.isRouting {
                ProgressView("Finding \(mode.rawValue.lowercased()) routes…")
            } else if !preview.routes.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(preview.routes.enumerated()), id: \.offset) { index, route in
                            Button {
                                preview.selectedRoute = index
                                fitRoute()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(max(1, Int(ceil(route.expectedTravelTime / 60)))) min · \(Measurement(value: route.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))")
                                        .font(.subheadline.bold())
                                    Text(route.name).font(.caption).lineLimit(1)
                                    Text(index == 0 ? "Fastest available" : "Alternative \(index)").font(.caption2)
                                }
                                .padding(10)
                                .background(index == preview.selectedRoute ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .accessibilityAddTraits(index == preview.selectedRoute ? .isSelected : [])
                        }
                    }
                }
                Text("\(mode.rawValue) preview · Estimates from Apple Maps")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let message = preview.routeMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let message = trip.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let route = preview.activeRoute {
                Button("Start guidance") {
                    trip.start(route: route, destination: destination, driving: mode == .driving,
                               location: location.isAuthorized ? location.location : nil)
                    if trip.isActive { followsHeading = true; recenter() }
                }
                .buttonStyle(.borderedProminent).tint(.teal)
                .accessibilityIdentifier("startGuidance")
            }
            if !preview.isRouting {
                Button(preview.routes.isEmpty ? "Preview \(mode.rawValue.lowercased()) routes" : "Refresh routes", action: loadRoutes)
                    .buttonStyle(.borderedProminent).tint(.teal)
            }
        }
    }

    private func loadRoutes() {
        Task {
            await preview.preview(from: location.isAuthorized ? location.location : nil, driving: mode == .driving)
            fitRoute()
        }
    }

    private func fitRoute() {
        guard let route = preview.activeRoute else { return }
        let rect = route.polyline.boundingMapRect
        withAnimation { position = .rect(rect.insetBy(dx: -max(rect.width * 0.18, 300), dy: -max(rect.height * 0.18, 300))) }
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
        followLocation()
    }

    private func followLocation() {
        guard let fix = location.location, abs(fix.timestamp.timeIntervalSinceNow) <= 30 else {
            position = .userLocation(followsHeading: followsHeading, fallback: .region(Self.startRegion))
            return
        }
        let driving = mode == .driving
        let course = driving && fix.speed > 1.5 && fix.course >= 0 ? fix.course : location.heading ?? 0
        let distance = driving ? min(2400, max(700, max(0, fix.speed) * 65)) : 550
        position = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: distance,
                                     heading: followsHeading ? course : 0, pitch: 0))
    }

    private func selectPlace(_ place: MKMapItem) {
        preview.select(place)
        position = .region(MKCoordinateRegion(center: place.location.coordinate,
            latitudinalMeters: 1800, longitudinalMeters: 1800))
    }

    private func refreshNearby(force: Bool = false) {
        guard mode == .walking, scenePhase == .active, !trip.isActive else { return }
        Task {
            guard mode == .walking, scenePhase == .active, !trip.isActive else { return }
            await nearby.refresh(near: location.isAuthorized ? location.location : nil, force: force)
        }
    }

    private var nearbyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nearby on foot").font(.headline)
                Spacer()
                Button { refreshNearby(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Refresh nearby places")
                .disabled(nearby.isLoading || !location.isAuthorized)
            }
            if nearby.isLoading { ProgressView("Finding nearby places…") }
            if let message = nearby.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if nearby.places.isEmpty && !nearby.isLoading && nearby.message == nil {
                Text("Enable location to discover nearby places, or use Search.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(nearby.places.enumerated()), id: \.offset) { _, place in
                        Button { selectPlace(place) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name ?? "Place").font(.subheadline.bold()).lineLimit(1)
                                Text(NearbyPlacesStore.category(for: place)).font(.caption)
                                if let fix = location.location {
                                    Text(Measurement(value: place.location.distance(from: fix), unit: UnitLength.meters)
                                        .formatted(.measurement(width: .abbreviated, usage: .road))).font(.caption)
                                }
                            }
                            .frame(width: 150, alignment: .leading)
                            .padding(10).background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private var drivingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Driving minimap").font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    if let fix = location.location, context.date.timeIntervalSince(fix.timestamp) <= 30,
                       fix.horizontalAccuracy <= 65, fix.speed >= 0 {
                        Text(Measurement(value: fix.speed, unit: UnitSpeed.metersPerSecond)
                            .formatted(.measurement(width: .abbreviated, usage: .general))).monospacedDigit()
                    } else { Text("Speed —").foregroundStyle(.secondary) }
                }
            }
            Text("Current road: Unavailable · Speed limit: Unknown").font(.subheadline)
            Text("Road matching and live incident reports are unavailable. No reports does not mean a clear road.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Explore simulated road replay") { showsReplay = true }
                .font(.subheadline)
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
