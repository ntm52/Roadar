# Phase 6 — Reliability and CarPlay preparation

September 4, 2026. Phase 5 is accepted by the user as substantially complete.
Apple CarPlay navigation approval is pending. The project does not have the
CarPlay capability or a CarPlay scene. The user authorized an app audit, fixes,
verification, commit/push, and further development that can proceed without approval.

## Reliability audit

- Removed synchronous permission reads from screen construction. A process sample
  captured startup blocked in Core Location while reading authorization in the
  location-store initializer. Permission state now arrives through the delegate
  callback; foreground changes reuse the cached state.

- Route previews now require the same fresh, precise, valid-coordinate location
  as guidance. Previously a 20-second-old or 50-meter-accuracy fix could generate
  a preview that guidance immediately refused to start.
- Invalid coordinates cannot enter guidance. Location delivery ignores old,
  invalid, inactive, and unauthorized samples and selects the newest valid fix
  from a batch.
- Active guidance removes the location distance filter so stationary arrival
  confirmation is not prevented by requiring another 5–10 meters of movement.
- Alternatives expire on loss of reliable location, time, movement, or pause;
  their availability message is cleared with the proposal. Backgrounding without
  an active trip no longer creates a misleading paused-guidance message.
- A cancellable route-calculation boundary and injected clock permit deterministic
  integration tests for late responses after ending/backgrounding, alternative
  acceptance and cooldown, expiry, network failure, and manual recovery.
- Offline road details use an explicit vertical layout inside their timed view,
  matching the layout fix already used by the MDOT panel.

## Verification — repair checkpoint

Verification of the repair checkpoint: Debug simulator build, all 51 unit tests,
and the redesigned map/search/driving/road-download interface walkthrough passed.
All three builder tests passed using `/private/tmp/roadar-osm-tools/bin/python`.
Result bundle: `/tmp/RoadarAudit/Logs/Test/Test-Roadar-2026.09.04_18-28-18--0400.xcresult`.
The initial parallel test run was interrupted after diagnosing the startup block;
the passing rerun uses one simulator.

## Continued development without CarPlay approval

- `RoadarApp` now owns `AppSession`. Phone views receive its shared location,
  route-preview, active-trip, nearby-place, work-zone and offline-road services.
  Travel mode also belongs to the session. View reconstruction no longer creates
  new service instances. Camera and sheet state remain local to the phone view.
  Future CarPlay scene integration still needs to connect to this owner and
  coordinate lifecycle; adding the shared owner alone does not implement CarPlay.
- Route preferences can be opened before starting a trip from the main-map
  sliders button, or during a trip. Savings and cooldown thresholds are saved
  on this device, and Restore defaults resets them. Invalid saved values fall
  back to the conservative defaults. No destinations or trip history are saved.
- Added the required-reason UserDefaults entry for app-local preferences in
  `PrivacyInfo.xcprivacy`. This is not a full App Store privacy review.
- Deterministic persistence tests and an interface relaunch test cover saved
  values, malformed data and restoring defaults.

Final verification: the shared-state/preferences build passed all 53 unit tests
and the map/search/driving/road-download UI walkthrough. The new persistence UI
test initially used the wrong stepper button identifier; after correcting that
test selector, it passed a full terminate/relaunch, saved-value check and reset.
No production changes followed the passing unit suite. Final UI result:
`/tmp/RoadarAudit/Logs/Test/Test-Roadar-2026.09.04_18-34-22--0400.xcresult`.

References: [Apple model ownership](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app),
[UserDefaults and privacy](https://developer.apple.com/documentation/foundation/userdefaults),
[required API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## Stationary route preparation fix

After physical-phone feedback that a previously located position left route
previews waiting, route preparation now disables the movement-based GPS filter
as soon as a destination is selected. Requesting routes also resumes location
monitoring. This stays enabled through preview and guidance, then returns to the
exploration distance filter when the destination/trip is cleared. Foreground and
permission gates remain in force. Waiting messages now distinguish a missing fix,
an old fix, and insufficient accuracy. Regression tests cover stationary
preparation, restoration of exploration filtering, and age/accuracy messages.
Physical-phone confirmation is still needed; Core Location timing is not guaranteed.

Verification: simulator build and all 55 unit tests passed. Result bundle:
`/tmp/RoadarAudit/Logs/Test/Test-Roadar-2026.09.04_19-17-44--0400.xcresult`.

## Remaining limitations

Physical iPhone and passenger journeys remain necessary to assess real GPS,
maneuver timing, arrival, signing, accessibility, battery and thermal performance.
Guidance remains foreground-only. ETA is distance-based, not continuously updated
traffic. MDOT route matches cannot establish exact road identity; destination-free
ahead-only filtering remains incomplete. Explicit OSM limits cover about 18.2% of
included road distance. Extra incident/police feeds remain deferred.

The pending entitlement does not prevent refactoring shared trip state or local
preferences. CarPlay vehicle testing requires the approved capability and a signed
device build. No App Store submission or entitlement request is performed here.
