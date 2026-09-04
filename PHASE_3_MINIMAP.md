# Phase 3 minimap checkpoint

## Delivered behavior

Walking mode discovers up to 12 nearby places within 750 meters of a fresh location using Apple's point-of-interest search. Cards and map pins open the existing place details and destination preview. Names, categories and straight-line distances support discovery without entering a destination. Requests are cancelled when leaving walking mode or backgrounding. Automatic requests are separated by at least 60 seconds and normally require 250 meters of movement; manual refresh is available.

The following camera uses a close walking view and a driving view that widens with measured speed. Heading-up uses travel course while driving, with device compass heading as a fallback. Manual map exploration pauses following until Recenter. Foreground compass/location updates stop when the app is inactive.

The live driving panel shows measured speed when fresh, explicitly unknown speed limits, and unavailable road matching/reports. It does not infer the current road from a nearby street address or show fabricated live reports.

The **Road replay** screen uses invented geometry, speed limits, reports and driver samples. It is labeled simulated and does not use the device's location. Its reusable matcher operates on directed road edges and explicit graph connectivity:

- Projects the driver onto candidate road segments, checks travel direction, and rejects stale, weak or stationary samples.
- Withholds road context when parallel or stacked roads cannot be distinguished. Reliable altitude evidence can distinguish vertically stacked roads; altitude alone is not assumed reliable.
- Looks ahead through connected edges up to a speed-dependent horizon, stopping at branches, unknown connections or sharp turns.
- Filters reports by directed edge, forward distance, valid position, creation time and expiry; removes duplicate report IDs. Reports already passed or inside the location-error exclusion zone are hidden.
- Presents uncertainty and report age. An empty report list never promises a clear road.

No spoken or repeated proximity alerts are emitted. This prototype filters display records; production alert cooldowns and event identity across data sources remain future work. Real road matching needs a provider that supplies suitable graph geometry, direction and connectivity; the straight-edge fixture matcher is not a production navigation engine.

## Provider review — 2026-09-03

Mapbox remains a candidate for real destination-free matching. Its [iOS free-drive guide](https://docs.mapbox.com/ios/navigation/guides/free-drive/user-interface/) describes road snapping and speed-limit state. The [pricing page](https://www.mapbox.com/pricing) distinguishes free-drive and active-guidance trips: “free drive” describes navigation without a destination, not a guarantee of zero cost. The [Map Matching API](https://docs.mapbox.com/api/navigation/map-matching/) requires an access token and documents speed-limit annotations.

No account or token was provisioned, SDK installed, billing enabled, or live report feed connected. The $0 additional-service budget remains in force. Account access, cost controls, local coverage and display terms must be established before real provider integration. Phase 3 therefore uses real Apple nearby-place search plus an explicitly simulated driving-road prototype.

## Verification and remaining checks

Automated scenarios cover parallel roads, overpasses, opposite travel, unknown forks, ambiguous/weak/stationary samples, passed and duplicate reports, stale samples, future/expired reports, vertically stacked roads, and invalid graph connections/sharp turns. Nearby-place stale-location recovery also has a network-independent test. The existing four Phase 2 tests remain in the suite.

Simulator build and all 13 unit tests passed. Interactive checks verified actual Ann Arbor nearby results, card-to-place details, walking recenter, live driving unknown/unavailable states, labeled replay reports and ambiguous-road withholding. First-location centering was corrected and confirmed in a fresh simulator launch.

Physical iPhone checks remain: compass stability, manual pan/recenter, speed-dependent zoom while moving, location quality, foreground/background recovery, large text and VoiceOver. Evaluate multiple actual local streets before accepting any future live matching provider. The route preview is not an active guided trip and is not used as evidence of the driver's intended turn.
