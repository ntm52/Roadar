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
    @State private var offlineRoads = OfflineRoadStore()
    @State private var showsReplay = false
    @State private var showsSearch = false
    @State private var showsRoadDetails = false
    @State private var visibleRegion = Self.startRegion
    @State private var mode: TravelMode = .walking
    @State private var followsHeading = false
    @State private var position: MapCameraPosition = .region(Self.startRegion)

    private static let startRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.30, longitude: -83.39),
        span: MKCoordinateSpan(latitudeDelta: 0.38, longitudeDelta: 0.85)
    )

    var body: some View {
        GeometryReader { geometry in
        Map(position: $position) {
            if location.isAuthorized { UserAnnotation() }
            if mode == .walking && preview.destination == nil {
                ForEach(Array(nearby.places.enumerated()), id: \.offset) { _, place in
                    Annotation(place.name ?? "Nearby place", coordinate: place.location.coordinate) {
                        Button { selectPlace(place) } label: {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2).foregroundStyle(RoadarTheme.accent)
                                .padding(5).background(RoadarTheme.surface, in: Circle())
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
                MapPolyline(route.polyline).stroke(RoadarTheme.accent, lineWidth: 7)
            }
            ForEach(Array((trip.isActive ? [] : preview.routes).enumerated()), id: \.offset) { index, route in
                MapPolyline(route.polyline)
                    .stroke(index == preview.selectedRoute ? RoadarTheme.accent : .gray.opacity(0.5), lineWidth: index == preview.selectedRoute ? 7 : 4)
            }
        }
        .mapStyle(.standard(
            elevation: .flat,
            pointsOfInterest: mode == .walking ? .all : .excludingAll,
            showsTraffic: mode == .driving
        ))
        .mapControls { MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
        .sheet(isPresented: $showsSearch) {
            searchSheet
        }
        .sheet(isPresented: $showsRoadDetails) { roadDetailsSheet }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: 14) {
                mapControls
                controls(maxHeight: geometry.size.height * 0.46)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        }
        .background(RoadarTheme.background)
        .preferredColorScheme(.dark)
        .tint(RoadarTheme.accent)
        .task { await offlineRoads.load() }
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
            trip.setForeground(scenePhase == .active)
            location.setDriving(mode == .driving)
            location.setActive(scenePhase == .active)
            if location.isAuthorized { recenter() }
        }
        .onChange(of: scenePhase) { _, phase in
            location.setActive(phase == .active)
            trip.setForeground(phase == .active)
            if phase != .active { nearby.reset(); workZones.pause(); offlineRoads.update(nil) }
            else { refreshNearby() }
        }
        .onChange(of: location.authorization) { _, _ in
            if location.isAuthorized {
                recenter()
            } else {
                position = .region(Self.startRegion)
                nearby.reset()
                trip.update(nil)
                offlineRoads.update(nil)
            }
        }
        .onChange(of: location.location == nil) { wasMissing, isMissing in
            if wasMissing && !isMissing && preview.destination == nil {
                recenter()
            }
        }
        .onChange(of: location.location) { _, _ in
            trip.update(location.isAuthorized ? location.location : nil)
            offlineRoads.update(mode == .driving && scenePhase == .active && location.isAuthorized ? location.location : nil)
            if !position.positionedByUser && (preview.destination == nil || trip.isActive) { followLocation() }
            if preview.isWaitingForLocation, preview.destination != nil { loadRoutes() }
            refreshNearby()
        }
        .onChange(of: location.heading) { _, _ in
            if followsHeading && !position.positionedByUser && (preview.destination == nil || trip.isActive) { followLocation() }
        }
        .onChange(of: mode) { _, newMode in
            location.setDriving(newMode == .driving)
            offlineRoads.update(newMode == .driving && scenePhase == .active && location.isAuthorized ? location.location : nil)
            if newMode != .driving { workZones.pause() }
            preview.clearRoutes()
            if newMode == .driving { nearby.reset() } else { refreshNearby() }
            if preview.destination != nil { loadRoutes() }
            else if !position.positionedByUser { followLocation() }
        }
        .onChange(of: trip.isActive) { _, active in
            location.setNavigating(active)
            if active { nearby.reset() }
            else { refreshNearby() }
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 29)).foregroundStyle(RoadarTheme.accent)
                Text("roadar").font(.system(.title, design: .rounded, weight: .bold)).tracking(-1)
                Spacer()
                Text(trip.isActive ? "GUIDANCE" : "EXPLORE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(RoadarTheme.secondary)
            }
            Button { showsSearch = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(RoadarTheme.accent)
                    Text(trip.isActive ? "Enjoy the journey" : "Where to?")
                        .font(.body.weight(.medium)).foregroundStyle(.white)
                    Spacer()
                    if !trip.isActive {
                        Image(systemName: "arrow.up.right").foregroundStyle(RoadarTheme.secondary)
                    }
                }
                .padding(.horizontal, 18).frame(minHeight: 56)
                .roadarSurface(radius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("searchPlaces")
            .accessibilityLabel("Search places and addresses")
            .disabled(trip.isActive)
        }
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 18)
        .background {
            LinearGradient(colors: [RoadarTheme.background, RoadarTheme.background.opacity(0.9), .clear],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top)
        }
    }

    private var mapControls: some View {
        HStack(spacing: 10) {
            Spacer()
            Button {
                followsHeading.toggle()
                recenter()
            } label: {
                Image(systemName: followsHeading ? "location.north.line.fill" : "safari")
            }
            .accessibilityLabel(followsHeading ? "Heading up" : "North up")
            .accessibilityHint("Changes map orientation and resumes following your location")
            .disabled(!location.isAuthorized)
            Button(action: recenter) { Image(systemName: "location.fill") }
                .accessibilityLabel("Recenter")
                .accessibilityIdentifier("recenter")
        }
        .buttonStyle(RoadarIconButtonStyle())
    }

    private func controls(maxHeight: CGFloat) -> some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            travelModePicker
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
            if mode == .driving && (trip.isActive || preview.destination != nil) { roadDetailsButton }
            TimelineView(.periodic(from: .now, by: 5)) { context in
                if let message = location.status(at: context.date) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "location.circle")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if location.authorization == .notDetermined {
                            Button("Enable location", action: location.requestAccess)
                                .buttonStyle(RoadarPrimaryButtonStyle())
                                .accessibilityIdentifier("enableLocation")
                        } else if location.authorization == .denied || location.accuracy == .reducedAccuracy {
                            Button("Open Settings", action: openSettings)
                                .buttonStyle(RoadarPrimaryButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label(trip.isActive ? "Keep Roadar open for guidance" : preview.destination != nil ? "Preview · Choose a route to begin" : (position.positionedByUser ? "Exploring · Recenter to follow" : "Explore freely. No destination needed."), systemImage: trip.isActive ? "location.fill" : "arrow.up.right")
                        .font(.caption).foregroundStyle(RoadarTheme.secondary)
                }
            }
        }
        .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .roadarSurface()
    }

    private var travelModePicker: some View {
        HStack(spacing: 4) {
            ForEach(TravelMode.allCases, id: \.self) { option in
                Button { mode = option } label: {
                    Label(option.rawValue, systemImage: option.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(mode == option ? RoadarTheme.background : RoadarTheme.secondary)
                        .background(mode == option ? RoadarTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(option == .walking ? "walkingMode" : "drivingMode")
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoadarTheme.background, in: RoundedRectangle(cornerRadius: 17))
        .disabled(trip.isActive)
    }

    private var roadDetailsButton: some View {
        Button { showsRoadDetails = true } label: {
            HStack {
                Label("Road details", systemImage: "square.stack.3d.up")
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
        .accessibilityIdentifier("roadDetails")
    }

    private var roadDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Know the road ahead.").font(.largeTitle.bold())
                    Text("Offline road context and connected work-zone information, in one place.")
                        .foregroundStyle(RoadarTheme.secondary)
                    OfflineRoadPanel(store: offlineRoads).padding(20).roadarSurface(radius: 22)
                    WorkZonePanel(store: workZones, location: location.isAuthorized ? location.location : nil, engine: trip.engine)
                        .padding(20).roadarSurface(radius: 22)
                    Button { showsReplay = true } label: {
                        Label("Explore simulated road replay", systemImage: "play.circle")
                            .frame(minHeight: 44)
                    }
                    .sheet(isPresented: $showsReplay) { RoadReplayView() }
                }.padding(24)
            }
            .roadarSheet()
            .navigationTitle("Road details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsRoadDetails = false } } }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
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
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "location.magnifyingglass")
                            .font(.system(size: 42, weight: .light)).foregroundStyle(RoadarTheme.accent)
                        Text("Your next stop.").font(.title.bold())
                        Text("Find a favorite spot, a new corner of town, or the way home.")
                            .foregroundStyle(RoadarTheme.secondary)
                    }
                    .padding(.vertical, 28).listRowBackground(Color.clear)
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
            .roadarSheet()
            .navigationTitle("Where to?")
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.name ?? "Destination").font(.title2.bold())
                    Text(destination.address?.fullAddress ?? "Address unavailable")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button {
                    preview.clearDestination()
                    if location.isAuthorized { recenter() }
                } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
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
                                .padding(16)
                                .foregroundStyle(index == preview.selectedRoute ? RoadarTheme.accent : RoadarTheme.secondary)
                                .background(RoadarTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(index == preview.selectedRoute ? RoadarTheme.accent : .clear))
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
                Button("Navigate") {
                    trip.start(route: route, destination: destination, driving: mode == .driving,
                               location: location.isAuthorized ? location.location : nil)
                    if trip.isActive { followsHeading = true; recenter() }
                }
                .buttonStyle(RoadarPrimaryButtonStyle())
                .accessibilityIdentifier("startGuidance")
            }
            if !preview.isRouting {
                if preview.routes.isEmpty {
                    Button(preview.isWaitingForLocation ? "Waiting for location…" : "Show \(mode.rawValue.lowercased()) routes", action: loadRoutes)
                        .buttonStyle(RoadarPrimaryButtonStyle())
                        .accessibilityIdentifier("showRoutes")
                } else {
                    Button("Refresh routes", action: loadRoutes)
                        .frame(minHeight: 44)
                }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Around you").font(.title2.bold()).tracking(-0.5)
                    Text("Good places. A short walk away.")
                        .font(.caption).foregroundStyle(RoadarTheme.secondary)
                }
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
            if !nearby.places.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(nearby.places.enumerated()), id: \.offset) { _, place in
                        Button { selectPlace(place) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse").foregroundStyle(RoadarTheme.accent)
                                    Spacer()
                                    if let fix = location.location {
                                        Text(Measurement(value: place.location.distance(from: fix), unit: UnitLength.meters)
                                            .formatted(.measurement(width: .abbreviated, usage: .road)))
                                            .font(.caption2.weight(.medium)).foregroundStyle(RoadarTheme.secondary)
                                    }
                                }
                                Text(place.name ?? "Place").font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                Text(NearbyPlacesStore.category(for: place)).font(.caption).foregroundStyle(RoadarTheme.secondary)
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(16).background(RoadarTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            }
        }
    }

    private var drivingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THE ROAD AHEAD").font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.5).foregroundStyle(RoadarTheme.accent)
                        let fresh = offlineRoads.match.timestamp.map { context.date.timeIntervalSince($0) <= 15 } ?? false
                        Text(fresh ? (offlineRoads.match.road ?? "Finding your road") : "Finding your road")
                            .font(.title2.bold()).lineLimit(2)
                        Text("Speed limit · \(fresh ? (offlineRoads.match.speedLimit ?? "Unknown") : "Unknown")")
                            .font(.caption).foregroundStyle(RoadarTheme.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                    if let fix = location.location, context.date.timeIntervalSince(fix.timestamp) <= 30,
                       fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 65, fix.speed >= 0 {
                        Text(Measurement(value: fix.speed, unit: UnitSpeed.metersPerSecond)
                            .formatted(.measurement(width: .abbreviated, usage: .general)))
                            .font(.title3.bold()).monospacedDigit()
                    } else { Text("—").font(.title.bold()) }
                        Text("SPEED").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1).foregroundStyle(RoadarTheme.secondary)
                    }.padding(12).background(RoadarTheme.background, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            roadDetailsButton
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
