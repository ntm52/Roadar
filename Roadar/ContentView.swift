import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Bindable var session: AppSession
    @Bindable private var preview: RoutePreviewStore
    private var location: LocationStore { session.location }
    private var nearby: NearbyPlacesStore { session.nearby }
    private var trip: TripStore { session.trip }
    private var workZones: WorkZoneStore { session.workZones }
    private var offlineRoads: OfflineRoadStore { session.offlineRoads }
    @State private var showsReplay = false
    @State private var showsSearch = false
    @State private var showsRoadDetails = false
    @State private var showsSettings = false
    @State private var mapLocation: CLLocation?
    @State private var headerFrame: CGRect = .zero
    @State private var bottomFrame: CGRect = .zero
    @State private var visibleRegion = Self.startRegion
    private var mode: TravelMode {
        get { session.mode }
        nonmutating set { session.mode = newValue }
    }
    @State private var followsHeading = true
    @State private var forwardCamera = ForwardMapCamera()
    @AppStorage("compactMapControls") private var compactControls = false
    @State private var position: MapCameraPosition = .region(Self.startRegion)

    init(session: AppSession) {
        self.session = session
        self.preview = session.preview
    }

    private static let startRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.30, longitude: -83.39),
        span: MKCoordinateSpan(latitudeDelta: 0.38, longitudeDelta: 0.85)
    )

    var body: some View {
        GeometryReader { geometry in
        MapReader { proxy in
        Map(position: $position) {
            if location.isAuthorized {
                UserAnnotation { user in
                    RoadarLocationMarker()
                        .onChange(of: user.location, initial: true) { _, fix in
                            // Frame the same location MapKit is actually displaying, even
                            // while the separate guidance location service is acquiring GPS.
                            mapLocation = fix
                            refreshFollowingCamera()
                        }
                }
            }
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
                Annotation(destination.name ?? "Destination", coordinate: destination.location.coordinate, anchor: .bottom) {
                    RoadarDestinationMarker(name: destination.name ?? "Destination")
                }
                .annotationTitles(.hidden)
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
            emphasis: .muted,
            pointsOfInterest: mode == .walking ? .all : .excludingAll,
            showsTraffic: mode == .driving
        ))
        .mapControls { }
        // Apply only to the map, before attaching Roadar's panels and sheets.
        // Retain color in traffic and route overlays instead of making the map monochrome.
        .saturation(0.45)
        .colorMultiply(RoadarTheme.mapTint)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            anchorLocation(using: proxy, camera: context.camera, frame: geometry.frame(in: .global))
        }
        .sheet(isPresented: $showsSearch) {
            searchSheet
        }
        .sheet(isPresented: $showsRoadDetails) { roadDetailsSheet }
        .sheet(isPresented: $showsSettings) { RoutePolicyView(trip: trip) }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { headerFrame = $0 }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .trailing, spacing: 14) {
                mapControls
                controls(maxHeight: geometry.size.height * 0.46)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bottomFrame = $0 }
        }
        .task(id: CGSize(width: headerFrame.maxY, height: bottomFrame.minY)) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            refreshFollowingCamera()
        }
        .onChange(of: geometry.size) { _, _ in refreshFollowingCamera() }
        }
        }
        .background(RoadarTheme.background)
        .preferredColorScheme(.dark)
        .tint(RoadarTheme.accent)
        .task { await offlineRoads.load() }
        .task(id: scenePhase == .active && mode == .driving) {
            guard scenePhase == .active && mode == .driving else { return }
            while !Task.isCancelled {
                workZones.refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .onAppear {
            session.setPhoneActive(scenePhase == .active)
            location.setNavigating(trip.isActive)
            location.setPreparingRoute(preview.destination != nil)
            location.setDriving(mode == .driving)
            if location.isAuthorized { recenter() }
        }
        .onChange(of: scenePhase) { _, phase in
            session.setPhoneActive(phase == .active)
            if phase != .active { nearby.reset(); workZones.pause(); offlineRoads.update(nil) }
            else { refreshNearby() }
        }
        .onChange(of: location.authorization) { _, _ in
            if location.isAuthorized {
                recenter()
            } else {
                mapLocation = nil
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
            if mode == .walking && followsHeading && !position.positionedByUser && (preview.destination == nil || trip.isActive) { followLocation() }
        }
        .onChange(of: mode) { _, newMode in
            location.setDriving(newMode == .driving)
            forwardCamera = ForwardMapCamera()
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
        .onChange(of: preview.destination != nil) { _, preparing in
            location.setPreparingRoute(preparing)
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
                Button { showsSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Route preferences")
                .accessibilityIdentifier("routePreferences")
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
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { compactControls.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Capsule().fill(RoadarTheme.secondary.opacity(0.5)).frame(width: 28, height: 4)
                    Text(compactControls ? "Show details" : "More map")
                        .font(.caption.weight(.semibold))
                    Image(systemName: compactControls ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(RoadarTheme.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggleMapDetails")
            .accessibilityLabel(compactControls ? "Expand bottom menu" : "Minimize bottom menu")
            .accessibilityValue(compactControls ? "Minimized" : "Expanded")
            .gesture(DragGesture(minimumDistance: 15).onEnded { value in
                withAnimation(.easeInOut(duration: 0.25)) {
                    compactControls = value.translation.height > 0
                }
            })
            if compactControls {
                VStack(alignment: .leading, spacing: 8) {
                    if trip.isActive {
                        compactGuidance
                    } else {
                        travelModePicker
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                expandedControls(maxHeight: maxHeight - 44)
            }
        }
        .roadarSurface()
    }

    private var compactGuidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let engine = trip.engine {
                switch engine.state {
                case .following:
                    Text(engine.nextManeuver?.instruction ?? "Continue to the route endpoint")
                        .font(.headline).lineLimit(2)
                    if let maneuver = engine.nextManeuver {
                        Text("In \(Measurement(value: max(0, maneuver.distance - engine.progress), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(RoadarTheme.accent)
                    }
                case .arrived: Text("You’ve arrived").font(.headline)
                case .offRoute: Text("Off route · Finding a route").font(.headline)
                case .locating, .uncertain: Text("Confirming your position…").font(.headline)
                }
            }
            if let message = trip.message {
                Text(message).font(.caption).foregroundStyle(RoadarTheme.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandedControls(maxHeight: CGFloat) -> some View {
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
        .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
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
                .disabled(session.carPlayConnected && option == .walking)
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
        location.setPreparingRoute(preview.destination != nil)
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

    // Camera-only fallback. Route preparation and guidance still use LocationStore's
    // validated fixes and retain all their freshness and accuracy requirements.
    private var displayedLocation: CLLocation? {
        [mapLocation, location.location].compactMap { $0 }
            .filter { CLLocationCoordinate2DIsValid($0.coordinate) && $0.horizontalAccuracy >= 0 }
            .max { $0.timestamp < $1.timestamp }
    }

    private func refreshFollowingCamera() {
        if !position.positionedByUser && (preview.destination == nil || trip.isActive) {
            followLocation()
        }
    }

    private func anchorLocation(using proxy: MapProxy, camera: MapCamera, frame: CGRect) {
        guard !position.positionedByUser, preview.destination == nil || trip.isActive,
              location.isAuthorized, let fix = displayedLocation,
              headerFrame.height > 0, bottomFrame.height > 0,
              let userPoint = proxy.convert(fix.coordinate, to: .global),
              let centerPoint = proxy.convert(camera.centerCoordinate, to: .global) else { return }
        let anchor = ForwardMapCamera.anchor(in: frame.size,
            topInset: headerFrame.maxY - frame.minY, bottomInset: frame.maxY - bottomFrame.minY)
        let target = CGPoint(x: frame.minX + anchor.x, y: frame.minY + anchor.y)
        let delta = CGSize(width: userPoint.x - target.x, height: userPoint.y - target.y)
        // Correct using the actual map projection, so zoom, latitude and panel size
        // cannot change the user's screen anchor. The tolerance stops feedback loops.
        guard abs(delta.width) > 2 || abs(delta.height) > 2,
              let center = proxy.convert(CGPoint(x: centerPoint.x + delta.width,
                                                  y: centerPoint.y + delta.height), from: .global) else { return }
        position = .camera(MapCamera(centerCoordinate: center, distance: camera.distance,
                                     heading: camera.heading, pitch: camera.pitch))
    }

    private func followLocation() {
        guard let fix = displayedLocation else {
            position = .userLocation(followsHeading: followsHeading && mode == .walking, fallback: .region(Self.startRegion))
            return
        }
        position = .camera(forwardCamera.camera(for: fix, heading: location.heading,
                                                driving: mode == .driving, forward: followsHeading))
    }

    private func selectPlace(_ place: MKMapItem) {
        compactControls = false
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
    ContentView(session: AppSession())
}
