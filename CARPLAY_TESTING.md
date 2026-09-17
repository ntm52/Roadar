# Testing Roadar on CarPlay

Roadar now registers a native navigation CarPlay scene, draws a MapKit map under CPMapTemplate, searches for destinations, previews driving routes, and shares active driving trips with the iPhone. Turn instructions, maneuver distances, trip estimates, route replacement, arrival, and cancellation are connected to the existing guidance engine. CarPlay connection keeps location and guidance running independently of the phone scene. Disconnecting leaves a trip available on the phone; with neither interface active, guidance pauses.

## iPhone and vehicle

1. Open `Roadar.xcodeproj` in Xcode. Select the Roadar scheme and your iPhone, then Run. The target uses automatic signing with team `9HJ5466NL8`, bundle ID `com.nathanmayo.Roadar`, and the navigation entitlement `com.apple.developer.carplay-maps`.
2. If signing fails, confirm Apple's approved navigation capability is enabled for that exact App ID in Certificates, Identifiers & Profiles. Refresh the development provisioning profile in Xcode. An approval email alone does not update an existing cached profile.
3. Open Roadar on the phone and allow location while using the app, with Precise Location enabled.
4. Connect the phone to CarPlay and open Roadar. Use **Search** to find a destination and choose a route, then Start. Alternatively, select a destination on the phone and tap **Phone route** on CarPlay. Driving guidance already started on the phone appears automatically.
5. Test the map and route selection while parked. Verify guidance with a passenger or controlled test route. Lock the phone, then confirm that position and turn distances keep updating on CarPlay.

Use **End** to cancel both interfaces' shared trip. The location button returns to following mode, and the plus/minus buttons adjust map zoom. Walking selection is disabled while CarPlay is connected.

## Simulator

1. Run Roadar on an iPhone simulator using Xcode.
2. In Simulator, choose **I/O > External Displays > CarPlay**. Open Roadar on the CarPlay home screen.
3. Supply a simulated location using Xcode's location simulation or Simulator's location controls. A route requires a recent fix with accuracy of 35 meters or better. A stationary simulated fix can age out; use a moving GPX replay for guidance testing.
4. Allow location in the phone app. Search for a destination near the simulated start, preview the route, and Start.

## Checks

- CarPlay launches both with the phone app open and from a cold launch.
- A phone-started driving trip appears on CarPlay, and End cancels on both screens.
- Route search failure and missing location display a recoverable message.
- Previewing route alternatives changes the map; Start uses the chosen route.
- Locking the phone does not pause a connected CarPlay trip.
- Missing or inaccurate GPS replaces turn guidance with a locating status. Off-route detection initiates route recovery through TripStore.
- Arrival finishes the CarPlay navigation session; a subsequent trip starts normally.
- Disconnect/reconnect restores a phone trip without duplicating the guidance loop.

## Current limits

This is a testable initial integration. ETA uses the app's distance-proportional estimate, not a live traffic forecast. There is no spoken guidance, CarPlay Dashboard/instrument-cluster map, lane guidance, or junction imagery. MapKit's route steps do not supply typed turn semantics; instructions are shown without guessed turn arrows. Phone-proposed faster alternatives remain selectable on the phone. Location permission must initially be granted on the phone. Vehicle and locked-phone behavior require physical testing.

Reference: [Apple's CarPlay scene documentation](https://developer.apple.com/documentation/carplay/cptemplateapplicationscene).

## Validation performed September 17, 2026

- All 64 Roadar unit tests passed, including four new CarPlay tests.
- The four CarPlay tests passed again against the final scene configuration and lifecycle changes.
- The device build succeeded with automatic signing, and the embedded provisioning profile contains the approved navigation entitlement.
- The final app was installed successfully on Nathan's paired iPhone.
- The built scene manifest was checked to ensure it retains the CarPlay scene delegate. Actual CarPlay display, route search, and locked-phone driving behavior remain to be tested with the vehicle.
