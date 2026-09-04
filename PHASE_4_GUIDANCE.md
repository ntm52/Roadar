# Phase 4 guidance checkpoint

Implemented 2026-09-03. Foreground prototype; physical journeys and production navigation acceptance remain open.

September 4 continuation: route lifecycle regression tests, startup/location fixes,
app-owned shared services and persistent route preferences are documented in
PHASE_6_FOUNDATION.md. Thresholds now persist across launches; session-only wording
below describes the original checkpoint.

## Delivered

Select a walking or driving route in the existing preview and choose **Start guidance**. The app follows position, displays the upcoming Apple instruction and distance, shows trip progress, and provides **End trip** / **Done**. Search and travel mode changes are disabled during a trip so destination, geometry and transport mode stay consistent. Ending a trip restores the destination-free minimap.

`TripStore` owns the active destination, route, guidance state and cancellable route checks separately from preview and UI. `GuidanceEngine` operates on value-based geometry for repeatable tests. No precise trip history is stored. No paid services, accounts, external SDKs, background tracking, CarPlay or Live Activities were added.

Guidance requires a location no older than 15 seconds with horizontal accuracy of 35 meters or better. Poor, stale, future or out-of-order fixes cannot advance progress. Projection uses a route corridor and continuity bounds; ambiguous distant legs withhold guidance. Three off-corridor samples spanning at least eight seconds confirm off-route status. A replacement request then chooses Apple's fastest returned route; requests are at least 30 seconds apart, including network retries. **Recalculate from here** also permits explicit recovery when continuity cannot be established after moving while paused.

Arrival requires progress near the route end, proximity to the endpoint, accuracy within 20 meters, and two distinct slow-moving fixes. The endpoint is the end of the routed geometry, which can differ from a building entrance. Unknown speed does not automatically confirm arrival; End trip remains available.

Alternative checks run every two minutes while following a route. A proposal must save both 60 seconds and 5%, with a two-minute cooldown after starting or switching. Settings allow larger thresholds and cooldowns for the current app session. Faster alternatives are offered for selection rather than automatically adopted. Proposals expire after 30 seconds or 75 meters of movement from their origin. Off-route recovery uses its own 30-second retry interval because a route already left needs replacement regardless of time savings. Cancelled/backgrounded/ended trips reject late route responses.

## ETA and provider limits

Remaining time scales the selected route's original `expectedTravelTime` by the fraction of geometry remaining. Arrival time is based on the most recent accepted fix. This is explicitly labeled **Based on distance remaining**; it is not a fresh traffic model, segment-specific timing, or measured improvement over Apple Maps. Alternative savings compare a newly returned route with that estimated baseline, so proposals require user selection. Route choices are limited to Apple's returned alternatives; Roadar does not control Apple's route cost function.

Maneuver text and geometry come from [Apple MKRoute](https://developer.apple.com/documentation/mapkit/mkroute); route requests use [MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections). Step instructions are associated with their step geometry's start and shown as upcoming maneuvers. This checkpoint provides visual instructions, not spoken guidance.

Guidance pauses when the app becomes inactive. Returning requires a fresh fix. Live road matching remains Phase 5 work: route-polyline proximity cannot reliably identify a parallel road, road level, legal access, or travel direction. Sharp reversals, long gaps and ambiguous geometry may require **Recalculate from here**. Road replay reports remain separate from active trips; there is still no live hazard feed or production route-corridor reporting.

## Verification

- Debug iOS simulator build passed on iPhone 17 Pro / iOS 26.5.
- All 20 unit tests passed: the existing 13 plus seven new deterministic guidance/policy scenarios covering progression and ETA, missed-route confirmation and recovery, poor/stale/future/duplicate fixes, arrival requirements, a loop ending near its start, savings/cooldown behavior, and foreground recovery state.
- Simulator walkthrough used a synthetic Ann Arbor location and real Apple search/routes to Michigan Stadium. It confirmed three walking alternatives, a stale-location start refusal, successful fresh-location start, the first Apple instruction, distance/ETA/progress display, and policy defaults (60 seconds / 5% / two minutes).
- Unit journey fixtures validate logic; they do not establish real-road navigation accuracy or observed ETA performance. Live network failure, in-flight cancellation, proposal acceptance/expiry and automatic off-route route replacement still need integrated journey validation.

## Next acceptance work

1. On the iPhone, walk a short known route and verify the instruction timing at several turns, endpoint behavior, pan/recenter, large text and VoiceOver.
2. As a passenger, replay a known driving journey with a missed turn, a parallel road and a loop; confirm that ambiguous position never produces a confident incorrect instruction.
3. Test lock/unlock, permission loss, stale GPS, connection loss/recovery, ending during a route request, and returning after significant movement.
4. Compare predicted and observed arrival times on repeatable Ann Arbor–Detroit journeys before accepting ETA quality or claiming better route selection.
5. Validate actual alternate-route proposals, expiry, custom thresholds and cooldown behavior during integrated journeys. Complete physical-device acceptance from prior phases alongside this work.
