import CarPlay
import MapKit
import SwiftUI

/// A native CarPlay template above an app-rendered MapKit surface.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate, CPSearchTemplateDelegate {
    private let session = AppSession.shared
    private let preview = RoutePreviewStore()
    private let mapTemplate = CPMapTemplate()
    private var interface: CPInterfaceController?
    private var mapController: CarPlayMapController?
    private var updateTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var search: MKLocalSearch?
    private var navigation: CPNavigationSession?
    private var activeRoute: MKRoute?
    private var activeTrip: CPTrip?
    private var maneuvers: [CPManeuver] = []
    private var statusManeuver: CPManeuver?
    private var finished = false
    private var previewTrip: CPTrip?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController, to window: CPWindow) {
        interface = interfaceController
        session.setCarPlayConnected(true)
        let controller = CarPlayMapController()
        mapController = controller
        window.rootViewController = controller
        mapTemplate.mapDelegate = self
        mapTemplate.automaticallyHidesNavigationBar = false
        mapTemplate.leadingNavigationBarButtons = [CPBarButton(title: "Search") { [weak self] _ in
            self?.showSearch()
        }, CPBarButton(title: "Phone route") { [weak self] _ in
            guard let self else { return }
            guard let destination = self.session.preview.destination else {
                self.showMessage("Choose a destination on your phone or use Search.")
                return
            }
            self.prepare(destination)
        }]
        mapTemplate.trailingNavigationBarButtons = [CPBarButton(title: "End") { [weak self] _ in
            self?.endTrip()
        }]
        let recenter = CPMapButton { [weak self] _ in self?.mapController?.recenter() }
        recenter.image = UIImage(systemName: "location.fill")
        let zoomIn = CPMapButton { [weak self] _ in self?.mapController?.zoom(by: 0.7) }
        zoomIn.image = UIImage(systemName: "plus.magnifyingglass")
        let zoomOut = CPMapButton { [weak self] _ in self?.mapController?.zoom(by: 1.4) }
        zoomOut.image = UIImage(systemName: "minus.magnifyingglass")
        mapTemplate.mapButtons = [recenter, zoomIn, zoomOut]
        interfaceController.setRootTemplate(mapTemplate, animated: false, completion: nil)
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.synchronize()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController, from window: CPWindow) {
        updateTask?.cancel()
        updateTask = nil
        selectionTask?.cancel()
        selectionTask = nil
        search?.cancel()
        preview.clearDestination()
        navigation?.cancelTrip()
        navigation = nil
        activeRoute = nil
        activeTrip = nil
        previewTrip = nil
        window.rootViewController = nil
        mapController = nil
        interface = nil
        session.setCarPlayConnected(false)
    }

    private func showSearch() {
        let template = CPSearchTemplate()
        template.delegate = self
        interface?.pushTemplate(template, animated: true, completion: nil)
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
                        completionHandler: @escaping ([CPListItem]) -> Void) {
        search?.cancel()
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completionHandler([])
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        if let fix = session.location.location {
            request.region = MKCoordinateRegion(center: fix.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        let operation = MKLocalSearch(request: request)
        search = operation
        Task { @MainActor in
            do {
                let response = try await operation.start()
                guard self.search === operation, self.interface != nil else { completionHandler([]); return }
                completionHandler(response.mapItems.prefix(5).map { place in
                    let item = CPListItem(text: place.name ?? "Destination", detailText: place.address?.fullAddress)
                    item.userInfo = place
                    return item
                })
            } catch {
                let item = CPListItem(text: "Search unavailable", detailText: "Check your connection and try again.")
                item.isEnabled = false
                completionHandler(self.search === operation ? [item] : [])
            }
        }
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem,
                        completionHandler: @escaping () -> Void) {
        if let place = item.userInfo as? MKMapItem { prepare(place) }
        completionHandler()
    }

    private func prepare(_ destination: MKMapItem) {
        guard session.location.isAuthorized else {
            showMessage("Open Roadar on your iPhone and allow Precise Location before starting a route.")
            return
        }
        selectionTask?.cancel()
        preview.select(destination)
        selectionTask = Task { [weak self] in
            guard let self else { return }
            await self.preview.preview(from: self.session.location.location, driving: true)
            guard !Task.isCancelled, self.interface != nil else { return }
            guard !self.preview.routes.isEmpty, let fix = self.session.location.location else {
                self.showMessage(self.preview.routeMessage ?? "No route available.")
                return
            }
            let choices = self.preview.routes.map { route in
                let choice = CPRouteChoice(summaryVariants: ["\(max(1, Int(ceil(route.expectedTravelTime / 60)))) min"],
                    additionalInformationVariants: [route.name], selectionSummaryVariants: [route.name])
                choice.userInfo = route
                return choice
            }
            let trip = CPTrip(origin: MKMapItem(location: fix, address: nil), destination: destination, routeChoices: choices)
            self.previewTrip = trip
            self.interface?.popToRootTemplate(animated: true, completion: { [weak self] success, _ in
                guard success, let self, self.previewTrip === trip else { return }
                self.mapTemplate.showTripPreviews([trip], textConfiguration: nil)
                if let route = choices.first?.userInfo as? MKRoute {
                    self.mapController?.show(route: route, overview: true)
                    self.mapTemplate.updateEstimates(Self.estimates(distance: route.distance, time: route.expectedTravelTime), for: trip)
                }
            })
        }
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        guard let route = routeChoice.userInfo as? MKRoute else { return }
        mapController?.show(route: route, overview: true)
        mapTemplate.updateEstimates(Self.estimates(distance: route.distance, time: route.expectedTravelTime), for: trip)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        guard let route = routeChoice.userInfo as? MKRoute else { return }
        session.mode = .driving
        session.trip.start(route: route, destination: trip.destination, driving: true, location: session.location.location)
        guard session.trip.route === route else {
            showMessage(session.trip.message ?? "Refresh the route before starting.")
            return
        }
        previewTrip = nil
        preview.clearDestination()
        mapTemplate.hideTripPreviews()
        mapController?.recenter()
        synchronize()
    }

    func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) { endTrip() }

    private func endTrip() {
        selectionTask?.cancel()
        previewTrip = nil
        preview.clearDestination()
        mapTemplate.hideTripPreviews()
        session.trip.end()
        synchronize()
    }

    private func synchronize() {
        guard interface != nil else { return }
        mapController?.update(location: session.location.location)
        guard let route = session.trip.route, let destination = session.trip.destination,
              let engine = session.trip.engine, engine.driving else {
            navigation?.cancelTrip()
            navigation = nil
            activeRoute = nil
            activeTrip = nil
            if previewTrip == nil { mapController?.show(route: nil) }
            return
        }
        if activeRoute !== route {
            navigation?.cancelTrip()
            activeRoute = route
            finished = false
            statusManeuver = nil
            let choice = CPRouteChoice(summaryVariants: [route.name], additionalInformationVariants: [], selectionSummaryVariants: [route.name])
            let origin = MKMapItem(location: CLLocation(latitude: engine.route.coordinates[0].latitude,
                longitude: engine.route.coordinates[0].longitude), address: nil)
            let trip = CPTrip(origin: origin, destination: destination, routeChoices: [choice])
            activeTrip = trip
            navigation = mapTemplate.startNavigationSession(for: trip)
            maneuvers = CarPlayGuidance.maneuvers(for: engine.route)
            navigation?.add(maneuvers)
            if previewTrip == nil { mapController?.show(route: route) }
        }
        guard let navigation, let activeTrip, !finished else { return }
        if engine.state == .arrived {
            navigation.finishTrip()
            finished = true
            return
        }
        guard engine.state == .following else {
            // Never display stale turn distances while GPS is uncertain or we are off route.
            let text = engine.state == .offRoute ? "Off route · Finding a new route" : "Waiting for an accurate location"
            if statusManeuver?.instructionVariants != [text] {
                let status = CPManeuver()
                status.instructionVariants = [text]
                navigation.add([status])
                statusManeuver = status
            }
            navigation.upcomingManeuvers = statusManeuver.map { [$0] } ?? []
            return
        }
        statusManeuver = nil
        let indices = CarPlayGuidance.upcomingIndices(route: engine.route, progress: engine.progress)
        navigation.upcomingManeuvers = indices.map { maneuvers[$0] }
        for index in indices {
            let distance = max(0, engine.route.maneuvers[index].distance - engine.progress)
            navigation.updateEstimates(Self.estimates(distance: distance,
                time: CarPlayGuidance.time(for: distance, route: engine.route)), for: maneuvers[index])
        }
        mapTemplate.updateEstimates(Self.estimates(distance: engine.remainingDistance, time: engine.remainingTime), for: activeTrip)
    }

    private func showMessage(_ text: String) {
        let alert = CPAlertTemplate(titleVariants: [text], actions: [CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.interface?.dismissTemplate(animated: true, completion: nil)
        }])
        interface?.presentTemplate(alert, animated: true, completion: nil)
    }

    static func estimates(distance: Double, time: TimeInterval) -> CPTravelEstimates {
        CPTravelEstimates(distanceRemaining: Measurement(value: max(0, distance), unit: UnitLength.meters), timeRemaining: max(0, time))
    }
}

@MainActor
enum CarPlayGuidance {
    static func time(for distance: Double, route: GuidanceRoute) -> TimeInterval {
        route.length > 0 ? route.expectedTravelTime * max(0, distance) / route.length : 0
    }

    static func upcomingIndices(route: GuidanceRoute, progress: Double) -> [Int] {
        Array(route.maneuvers.indices.filter { route.maneuvers[$0].distance >= progress - 10 }.prefix(2))
    }

    static func maneuvers(for route: GuidanceRoute) -> [CPManeuver] {
        route.maneuvers.enumerated().map { index, step in
            let maneuver = CPManeuver()
            maneuver.instructionVariants = [step.instruction]
            // MapKit provides localized instructions, not typed turn semantics. Do not guess arrows from text.
            let distance = max(0, step.distance - (index > 0 ? route.maneuvers[index - 1].distance : 0))
            maneuver.initialTravelEstimates = CarPlaySceneDelegate.estimates(distance: distance, time: time(for: distance, route: route))
            return maneuver
        }
    }
}

@MainActor
private final class CarPlayMapController: UIViewController, MKMapViewDelegate {
    private let map = MKMapView()
    private var route: MKRoute?
    private var location: CLLocation?
    private var cameraPolicy = ForwardMapCamera()
    private var overview = false
    private var zoom = 1.0

    override func loadView() {
        map.delegate = self
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        view = map
    }

    func show(route: MKRoute?, overview: Bool = false) {
        loadViewIfNeeded()
        if self.route !== route {
            map.removeOverlays(map.overlays)
            if let route { map.addOverlay(route.polyline, level: .aboveRoads) }
            self.route = route
        }
        self.overview = overview
        if overview, let route {
            map.setVisibleMapRect(route.polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 100, left: 100, bottom: 100, right: 100), animated: true)
        }
    }

    func update(location: CLLocation?) {
        loadViewIfNeeded()
        self.location = location
        guard !overview, GuidanceEngine.accepts(location, at: .now), let location else { return }
        let camera = cameraPolicy.camera(for: location, heading: nil, driving: true, forward: true)
        map.setCamera(MKMapCamera(lookingAtCenter: camera.centerCoordinate, fromDistance: camera.distance * zoom,
                                 pitch: 45, heading: camera.heading), animated: true)
    }

    func recenter() { overview = false; zoom = 1; update(location: location) }
    func zoom(by factor: Double) { overview = false; zoom = min(5, max(0.3, zoom * factor)); update(location: location) }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = .systemBlue
        renderer.lineWidth = 7
        return renderer
    }
}
