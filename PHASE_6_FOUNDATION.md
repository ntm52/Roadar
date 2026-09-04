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

## Remaining limitations

Verification of the repair checkpoint: Debug simulator build, all 51 unit tests,
and the redesigned map/search/driving/road-download interface walkthrough passed.
All three builder tests passed using `/private/tmp/roadar-osm-tools/bin/python`.
Result bundle: `/tmp/RoadarAudit/Logs/Test/Test-Roadar-2026.09.04_18-28-18--0400.xcresult`.
The initial parallel test run was interrupted after diagnosing the startup block;
the passing rerun uses one simulator.

Physical iPhone and passenger journeys remain necessary to assess real GPS,
maneuver timing, arrival, signing, accessibility, battery and thermal performance.
Guidance remains foreground-only. ETA is distance-based, not continuously updated
traffic. MDOT route matches cannot establish exact road identity; destination-free
ahead-only filtering remains incomplete. Explicit OSM limits cover about 18.2% of
included road distance. Extra incident/police feeds remain deferred.

The pending entitlement does not prevent refactoring shared trip state or local
preferences. CarPlay vehicle testing requires the approved capability and a signed
device build. No App Store submission or entitlement request is performed here.
