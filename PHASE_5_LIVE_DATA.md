# Phase 5 — Live road information

Current status: User accepted Phase 5 as substantially complete on September 4, 2026 and authorized Phase 6 preparation. MDOT work-zone connection, authenticated live decoding and conservative route relevance are implemented. Remaining limitations below are retained acceptance debt. Earlier instructions in this historical report to wait before Phase 6 are superseded by this decision; see PHASE_6_FOUNDATION.md.

## Scope and sequence

Live road information is phase 5; CarPlay is phase 6. The UI redesign was subsequently completed and pushed. Earlier premature CarPlay changes were reverted; no CarPlay entitlements or background modes were added. Phase 6 preparation is now authorized while approval is pending.

## Implemented checkpoint

- `WorkZoneFeed.swift`: reads MDOT's single-element WZDx 4.0 envelope; supports a native features array or JSON-encoded features string. Validates timestamps, feature type, work-zone type, LineString coordinates and event dates. Conflicting duplicate IDs and malformed records are withheld.
- `WorkZoneStore.swift`: ephemeral HTTPS requests to the documented work-zone endpoint with an `api_key` header. Refreshes at most every five minutes, cancels on leaving driving mode/backgrounding, prevents late results from replacing newer state, and refuses redirects so the credential cannot be forwarded to another host. HTTP and decoding failures clear displayed work-zone data. Errors never interpolate credential-bearing request descriptions.
- `MDOTCredential.swift`: direct in-app key entry is saved in device-only, when-unlocked Keychain storage. No key is bundled, logged, committed or placed in UserDefaults.
- `WorkZonePanel.swift`: driving-mode Connection sheet with Save and connect, refresh and disconnect. Displays up to three nearby scheduled work zones from a fresh feed, source timestamp, and coverage limitations. Available both with and without an active driving trip.
- Feed age limit is 15 minutes; future timestamps beyond one minute are withheld. Ended/future events and stale/weak location samples are excluded. Nearby means a geometry vertex within 5 km, not a road or route match; a long segment with no nearby vertices can be omitted. No ahead-of-driver alerts, current speed-limit claims or worker-presence claims are made.

## MDOT account and actual-data findings

User authorized the separate Data Extract Terms of Use, and portal access succeeded through third-party MiLogin SSO. Six datasets were visible. No payment or subscription was enabled.

**Incidents:** https://mdotridediscovery.state.mi.us/dataset/michigan_department_of_transportation/incidents

Sample has three records with closure ID, roadway, location description, coordinates, action, action/start/end dates, numeric travel direction and both-direction indicator. Nested incident details are null in the visible samples. Numeric direction meanings and timezone of unzoned dates were not documented in the visible dictionary; do not infer them from three examples.

All visible action dates and Data Last Ingested (`2026-08-05T22:58:47.923625Z`) were about a month old at inspection. The advertised five-minute frequency does not establish freshness. This source remains excluded from live incident reporting. A credential-free endpoint request returned HTTP 401.

**Work zones:** https://mdotridediscovery.state.mi.us/dataset/michigan_department_of_transportation/work_zone_information

Documented endpoint: `https://mdotridedata.state.mi.us/api/v1/organization/michigan_department_of_transportation/dataset/work_zone_information/query?limit=1&_format=json`. MDOT describes a single-element array containing a WZDx 4.0 FeatureCollection. Visible fields: `road_event_feed_info`, `type`, `features`. Source update: `2026-09-04T01:50:00.637223157Z`; ingestion: `2026-09-04T01:52:36.825945Z`. Advertised frequency: five minutes. Sample geometry includes the Ann Arbor/Ypsilanti area.

Real JSON downloaded through the authorized portal to `~/Downloads/51682057-3e70-4e0b-bdc5-1f245e08fbe3.json` (1,372,404 bytes). Terminal file reads hung, including an approved escalated read; those commands were interrupted. The downloaded full payload has not been decoded by the implementation. Parser tests use synthetic fixtures based on the observed envelope and WZDx specification, not that full download.

WZDx reference: https://github.com/usdot-jpo-ode/wzdx/blob/develop/spec-content/objects/WorkZoneRoadEvent.md

## Generated credential and user handoff

The user confirmed there was no saved MDOT API key and explicitly authorized generation. Generation succeeded; the key is displayed once in the Chrome MDOT API Key tab. Automatic approval review rejected extracting the secret into tool output. No attempt was made to bypass that rejection, and the key was not copied into code, files or the app.

User action: save the key securely, then enter it directly into Roadar's Driving > MDOT work zones > Connection > MDOT API key field and choose Save and connect. This sends the key only to MDOT's documented HTTPS host. Do not paste it into chat. The simulator Keychain is separate from the physical phone's Keychain.

## Mapbox free-tier findings

Authenticated console access succeeded. Statistics for Aug 5–Sep 4, 2026 reported no activity, including navigation, free-drive trips and Map Matching API. The overview showed zero map usage and a 25,000 monthly-user allowance for Maps SDKs for Mobile. No Mapbox request or SDK integration was enabled.

Published default Navigation SDK v3 metered pricing includes 100 monthly users and 1,000 trips. Four separate drives of at most one hour each daily would be approximately 124 trips over 31 days. Longer free-drive sessions roll over hourly; restarts, test devices and reinstallations affect counts. Account-specific contract and billing-period boundaries still need verification.

A conservative local budget (proposed 500 trip units per verified period) plus careful SDK lifecycle management should keep personal use below published allowances, but cannot guarantee account-wide zero spend. Mapbox has no hard spending cap; other apps, exposed tokens, reinstalls and future pricing remain outside a local budget. The budget has not been implemented.

Map Matching API results must be displayed using a Mapbox map; do not overlay them on the current Apple map. Mapbox SDK download requires a Downloads:Read secret token, and no ~/.netrc is configured. Confirm mixed-provider display terms before migration. Sources:

- https://www.mapbox.com/pricing
- https://docs.mapbox.com/ios/navigation/guides/pricing/
- https://docs.mapbox.com/accounts/faq/can-i-set-up-a-cap-for-monthly-spending/
- https://docs.mapbox.com/api/navigation/map-matching/
- https://docs.mapbox.com/ios/navigation/guides/install/

## Remaining acceptance

1. User enters the generated MDOT credential directly; validate authenticated HTTP response, real WZDx decoding, freshness and nearby display. Inspect rejection counts, unsupported geometry/types and real data coverage before claiming source acceptance.
2. Verify credential rejection, source outages, cancellation and stale-data behavior with the integrated app; inspect iPhone UI and device Keychain persistence. No automated real-key tests were run.
3. Integrate actual road matching, speed limits and conservative direction/route relevance. Nearby work zones alone do not satisfy ahead-of-driver filtering.
4. Resolve stale incident ingestion, incident direction/timezone semantics, and police-report source. No unsupported assumption that MDOT supplies police reports.
5. Complete Mapbox cost-control and installation checks before enabling the SDK; TomTom remains optional. A local OSM road-data alternative remains a candidate if strict avoidance of metered services is required.
6. Keep Phase 3/4 device/journey acceptance open. Do not advance to CarPlay on the strength of this partial checkpoint.

## Verification — September 4 continuation

Simulator build and the 26-test unit suite passed. After replacing a superficial endpoint assertion with stale/weak-location coverage, all six WorkZoneTests passed again. Tests cover native/string-encoded feature arrays, stale/future source times, expired/distant records, malformed envelopes, duplicate IDs, bad coordinates and poor location samples. These are fixture tests, not authenticated live-response validation.

Launched the build on the existing iPhone 17 Pro simulator and interactively opened Driving > MDOT work zones > Connection. Verified the secure key field, disabled empty Save and connect button, and coverage/refresh explanations. The form is ready for direct user entry. The app reports no saved key; no authenticated request has been initiated. Automatic approval review previously rejected extracting the generated key into tool output; this handoff avoids that disclosure.

## Authenticated live-data verification — September 4

User entered the generated key directly into Roadar. Reopening the app showed a successfully decoded live feed updated September 4 at 6:35 AM local time. The key remains in the app’s Keychain; it was not extracted or read by tools.

The previously blocked downloaded file is now readable. Ran the production decoder against the entire 710-feature MDOT snapshot: 703 work-zone records accepted and seven excluded (four detours, two pending, one completed). Added explicit event-status filtering so completed/pending/cancelled/unknown-status entries cannot appear just because their scheduled end time has not elapsed. Records without the optional status extension still use required date checks.

At the snapshot’s own update time, synthetic Ann Arbor coordinates returned three nearby scheduled records: US-23 BR / Main St at Ann St, eastbound M-14 and southbound US-23. This replay verifies real source decoding and geographic discovery, not the current status of those particular records. No exact-user location or credential was used by the standalone validation executable.

Improved missing/stale/weak-location presentation: the panel now asks for a fresh, precise position rather than saying there are no nearby records. Existing source-age withholding is preserved.

Remaining: road/direction matching, speed limits and ahead-only route relevance; incident freshness; Mapbox SDK download credential and $0 cost controls; physical-device acceptance. CarPlay remains phase 6.

Final September 4 checks: all 27 unit tests passed. The subsequent lifecycle and layout fixes built successfully. Manual authenticated refresh succeeded after the user's Wi-Fi interruption; the saved key persisted across installs. Entering driving mode now starts an independent refresh task keyed to scene activity, avoiding stale captured scene state and coupling to route-refresh work. Verified automatic refresh displays current US-23 BR, M-14 and US-23 records at the synthetic Ann Arbor location. Added an explicit vertical layout inside TimelineView after the visual check exposed overlapping records.


## Free route relevance — September 4

Implemented on-device comparison of WZDx work-zone lines with the existing Apple driving route. Only fresh feeds, currently scheduled records and fresh following-state driving guidance qualify. Candidate lines must have a known cardinal direction, measure 60 m–25 km, and match their entire sampled length to a unique route stretch within 12 m and 30 degrees in the same travel direction. Samples are at most 25 m apart; route projection must be continuous and monotonic. Repeated route stretches with separated projections are withheld. Passed events and starts beyond 5 km ahead are withheld; a zone already entered may appear as near the current route section.

These are **possible geometry matches**, not confirmed road matches. Entire-line matching intentionally misses partially shared routes and some long or curved zones. Sampling cannot establish road identity, elevation, lane, or exact local geometry between source points. Closely parallel/stacked roads may still appear; no spoken alerts are emitted. Cardinal labels gate unknown directions; actual alignment uses the ordered WZDx geometry, not an assumption that an entire curving road always points at its nominal compass direction.

Source for coordinate ordering: https://github.com/usdot-jpo-ode/wzdx/blob/develop/spec-content/objects/RoadEventFeature.md — first coordinate is upstream in travel direction.

Nearby discovery now measures distance to the line rather than only its vertices. Tapping a record opens its full description, direction, scheduled dates in device-local time, feed update and source record ID. The detail sheet distinguishes feed update time from event confirmation and does not claim workers are present or supply a current speed limit.

Validation: simulator build and all 34 tests passed (`/tmp/roadar-phase5-route-test.log`). Seven new tests exercise the relevance and line-distance cases listed in the project plan. No new provider calls are made by this matcher; it consumes existing route and MDOT data. No Mapbox SDK, TomTom, paid subscription, or backend was added. Phase 5 remains partial, and physical driving acceptance is still required.

Manual UI check: the updated simulator app loaded the authenticated MDOT feed (6:55 AM source timestamp), withheld nearby records while the simulated location was stale, then displayed records after refreshing the synthetic Ann Arbor fix. Opened US-23 BR details and visually verified the full closure/detour description, readable schedule, source time and Done control. Route relevance is covered by deterministic tests; a live route with a positive MDOT overlap and a physical driving journey have not yet been manually verified.
