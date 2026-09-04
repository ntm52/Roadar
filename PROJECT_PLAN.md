# Roadar project plan

Created: 2026-09-03  
Status: Phase 5 Southern Michigan offline road context implemented; first package built (83.9 MB download / 182.6 MB installed), file import and public GitHub download verified. MDOT work-zone connection prototype implemented; authenticated live refresh and full downloaded-payload decoding verified; full Phase 5 road relevance and physical acceptance remain. Phase 4 foreground guidance prototype is implemented and simulator-checked; integrated journeys and physical-device acceptance remain.

Purpose: Shared product plan and durable handoff between development sessions.

Phase 0 findings, free-service comparison, build audit, and remaining access gates: [PHASE_0_FEASIBILITY.md](PHASE_0_FEASIBILITY.md).

Confirmed target: Ann Arbor–Detroit, Michigan; iPhone 16 Pro; 2020 Subaru WRX Limited. The user already has Apple Developer Program membership and wants free options evaluated before budgeting any additional money. Current additional service budget: $0.

## Product vision

Build a personal iPhone maps app that combines place search, navigation, and a video-game-style minimap. It should be useful every time someone walks or drives, even without entering a destination. Apple CarPlay is a required eventual capability. App Store release is optional.

Routing should actively consider faster alternatives, including smaller roads when they save time, rather than unnecessarily preferring congested major roads. “More aggressively fast” means pursuing lower travel time through better route selection and timely rerouting. It does not mean assuming speeding. The perception that Google Maps sometimes favors congested roads is the motivation to investigate, not a verified explanation of its routing algorithm or a promise that Roadar will always beat it.

## Core experiences

| Experience | Required behavior |
| --- | --- |
| Search | Find businesses, named places, and addresses; inspect results and choose a destination. |
| Navigate | Compare routes and ETAs, start guidance, follow progress, reroute when appropriate, and clearly indicate arrival. |
| Walking minimap | Follow position and heading; show nearby businesses with useful names/categories and tappable details. No destination required. |
| Driving minimap | Show current road, available speed limit, and reported police or hazards ahead on the road being traveled. No destination required. |
| Driving with navigation | Use the selected route to determine which upcoming reports matter, including after planned turns. |
| CarPlay | Support a glanceable driving map, destination search/selection, guidance, and relevant road information through permitted CarPlay interfaces. |
| Live ETA | Show the user's own active-trip ETA through a Live Activity where supported. Sharing with others is a later option. |

### Minimap behavior

- Provide explicit walking/driving mode selection initially. Consider automatic switching later, with a manual override.
- Support heading-up and north-up views, recentering, readable day/night styling, and speed-appropriate zoom.
- Walking prioritizes businesses and nearby discovery; driving prioritizes road context and upcoming information.
- Match location to a road segment and direction, rather than treating every nearby map point as relevant.
- Without navigation, look ahead along the current road's plausible continuation. At ambiguous forks, reduce confidence instead of pretending to know the driver's intended turn.
- Avoid alerts for adjacent roads, overpasses, opposite directions, and reports already passed. Deduplicate repeated alerts.
- Display unknown speed limits as unknown. Show report age and uncertainty; no reports must not imply a clear road.

### Route selection behavior

- Primary objective: lowest credible estimated travel time among valid available routes.
- Account for traffic, closures, legal access, turn restrictions, and user preferences such as toll avoidance.
- Consider alternate roads when estimated savings justify them. A blanket preference for low-traffic roads can still produce a slower trip.
- Show alternative ETAs and explain meaningful tradeoffs, such as a small time saving for many extra turns.
- Add configurable reroute thresholds and a cooldown so tiny ETA changes do not cause constant route switching.
- Distinguish selecting among a provider's alternatives from controlling its underlying routing algorithm. True custom routing may require another provider or an engine with configurable costs and suitable traffic data.
- Validate performance using repeatable local journeys, predicted-versus-observed arrival times, and comparable departure conditions. Set improvement targets after collecting a baseline.

## Scope and release boundaries

**First usable milestone:** an iPhone map with location, search, route preview, and a destination-free walking/driving minimap. This milestone may use clearly labeled simulated road metadata/reports while data sources are evaluated.

**Eventual personal-use release:** working guidance, validated route selection, real road data where available, relevant ahead-of-driver reports, CarPlay, and own-trip Live Activities.

**Later options:** public crowdsourcing, ETA sharing, offline maps/routing, automatic mode detection, richer business discovery, and App Store distribution.

Do not expand initial scope to Android, social features, a worldwide reporting network, or operating a custom global routing service.

## Current repository

- Repository root: the directory containing this file and `Roadar.xcodeproj`.
- `Roadar/ContentView.swift`: native map, walking/driving selector, recenter and orientation controls, location status and Settings access.
- `Roadar/LocationStore.swift`: foreground location lifecycle, permission state, accuracy and stale-location reporting.
- `Roadar/RoadarApp.swift`: launches the map directly; starter SwiftData container removed.
- `Roadar/Item.swift`: unused starter model retained; no trip history is persisted.
- `RoadarTests/`: route-preview recovery and road-replay behavior tests. `RoadarUITests/` retains starter tests.
- Phase 1: Debug arm64 simulator build and manual simulator checks passed. Existing local project settings now target iOS 26.0 and portrait orientation; phone OS/signing not verified. These settings are included in a separate commit at the user’s request.
- Phase 2: place/address search, destination details, walking/driving route alternatives, geometry, distance and ETA are implemented using MapKit.
- `Roadar/RoutePreviewStore.swift`: cancellable search and route requests, fastest-ETA ordering and location-quality gates.
- Phase 3: nearby walking places, speed-aware following, and a labeled synthetic driving-road replay. See [PHASE_3_MINIMAP.md](PHASE_3_MINIMAP.md).
- Phase 4: foreground visual guidance, progress/arrival, off-route recovery and conservative alternative-route proposals are implemented. See [PHASE_4_GUIDANCE.md](PHASE_4_GUIDANCE.md).
- Southern Michigan offline road matching and explicit OSM speed limits are implemented; MDOT work-zone data is live. Broad speed-limit coverage, confirmed ahead-of-driver reports, spoken guidance, CarPlay and Live Activities remain incomplete.

## Proposed architecture — provisional

Keep shared trip and road state independent of the iPhone and CarPlay interfaces. Start with a small native implementation and introduce separate services where provider differences or testing justify them.

| Component | Responsibility |
| --- | --- |
| Map and search | Map display, business/place search, details, and destination selection. |
| Location and road context | Permissions, location quality, heading, travel mode, road matching, and forward road/route corridor. |
| Routing and guidance | Route alternatives, selection policy, maneuvers, progress, off-route detection, ETA, and rerouting. |
| Road data and reports | Speed limits, incidents, report freshness, direction, confidence, and relevance. |
| Trip state | One authoritative active trip shared by phone, CarPlay, and Live Activity presentation. |
| Storage | Preferences and saved places; optional trip diagnostics with deliberate retention. |
| Optional backend | External-data aggregation, shared reports, abuse controls, or push updates when actually needed. |

Phase 0 prototype choice: Swift/SwiftUI, Core Location, and MapKit for Phases 1–2. Mapbox Navigation's free tier is the preferred candidate to evaluate before Phase 3 real road matching; TomTom APIs and MDOT RIDE are additional routing/incident candidates. This is not a final full-product provider decision. Do not assume map rendering includes all the data needed for speed limits, traffic, police reports, or custom route costs.

## Feasibility and provider decisions

Resolve these early enough to avoid building the product around unavailable data.

| Decision | Evidence needed before committing |
| --- | --- |
| Map/search provider | Local business coverage, map customization, attribution, pricing, and compatible data-display terms. |
| Routing provider/engine | Alternate-route quality, traffic freshness, turn-by-turn support, rerouting, customizable costs, and coverage on smaller roads. |
| Speed limits and road graph | Coverage and update frequency; segment/direction identifiers; treatment of conditional limits and missing data. |
| Police and hazard reports | An accessible, licensed source or a realistic reporting plan; timestamps, direction, expiry, coverage, and operating cost. Do not assume Google/Waze reports are available through an API. |
| CarPlay | Developer account, navigation entitlement request, permitted interfaces, provisioning, simulator path, and real-car testing. |
| ETA/background operation | Supported devices/OS, background location behavior, Live Activity lifecycle and freshness, and whether remote updates are needed. |
| Private distribution | A supported signing/install route and its maintenance requirements. Optional App Store release is a separate decision. |

Compare candidates against the same local test routes and data checklist. Research current SDKs, terms, and prices at selection time; record sources and the decision here. No paid services or provider choice are approved by this plan alone.

Apple provides an entitlement request process for CarPlay apps and a simulator for development. Treat access as an external dependency to investigate early; private installation is not a substitute for that process. See [Apple CarPlay resources](https://developer.apple.com/carplay/) and [CarPlay framework documentation](https://developer.apple.com/documentation/carplay/).

MapKit's `MKDirections` requests walking/driving routes from Apple servers. It can support the initial route prototype, but we must separately establish whether a chosen provider gives enough control for Roadar's routing goals. See [MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections).

ActivityKit provides Live Activities and supports app-driven updates as well as push-based updates. The ETA surface must reflect real trip state; it must not be treated as a mechanism that guarantees continuous background execution. Verify background behavior on device. See [ActivityKit](https://developer.apple.com/documentation/activitykit) and [displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

## Development sessions and completion criteria

Each phase can occupy more than one session. End sessions at a coherent checkpoint and update the handoff below.

| Phase | Work | Complete when |
| --- | --- | --- |
| 0 — Requirements and feasibility | Confirm target devices/region, data budget, routing expectations, and report sources; inspect build setup; investigate CarPlay entitlement. | Decisions and unresolved dependencies are recorded; an achievable prototype scope is chosen. |
| 1 — Map and location | Replace starter interface with map; add location permissions, recentering, heading, and explicit travel modes. | Map works on a real iPhone; denied permission and poor location quality have usable states. |
| 2 — Search and route preview | Search places/addresses, show details, choose destination, and compare available routes. | A user can select a real place and see route geometry, distance, and ETA. |
| 3 — Destination-free minimap | Add walking businesses and driving road context; implement road/direction matching and ahead-only report filtering. | Replay scenarios distinguish current roads from parallel roads/overpasses and work with no destination; simulated data remains clearly labeled. |
| 4 — Guidance and route policy | Add maneuver guidance, progress, off-route handling, arrival, alternatives, and reroute thresholds. | Repeatable journeys validate guidance and ETA behavior; switching routes does not oscillate. |
| 5 — Live road information | Integrate selected speed-limit/report sources; add freshness, expiry, deduplication, and fallback states. | Real data is distinguishable from unavailable/stale data; unrelated-road and expired reports are excluded. |
| 6 — CarPlay | Connect shared trip state to permitted CarPlay UI; support driving minimap and navigation. | Approved/provisioned capability is exercised in simulator and a real car, including connect/disconnect and no active route. |
| 7 — Live ETA and resilience | Add Live Activity; validate lock-screen/background behavior, interruptions, offline handling, and battery use. | ETA starts, updates, becomes stale visibly when needed, and ends with the trip; lifecycle behavior is checked on device. |
| 8 — Personal release / optional store | Finish install workflow, usability, accessibility, privacy settings, and any chosen distribution requirements. | Personal-use acceptance checklist passes; App Store work proceeds only if separately chosen. |

CarPlay feasibility begins in Phase 0 even though full integration is later. Phase 5 depends on securing usable data; a seeded demonstration does not satisfy the real-data milestone.

## Verification priorities

- Location: stationary heading, weak GPS, tunnels, denied/reduced permissions, and recovery.
- Road relevance: divided highways, parallel frontage roads, overpasses, intersections, forks, U-turns, and direction changes.
- Routing: heavy traffic, closures, small-road alternatives, missed turns, ETA drift, and repeated reroute proposals.
- Reports: opposite direction, already passed, duplicates, expired entries, sparse coverage, and source failure.
- Lifecycle: locked phone, background trip, interrupted network, phone/CarPlay reconnection, trip cancellation, and arrival.
- Performance: map readability, response time, battery/thermal behavior, and query cost on representative journeys.
- Use location replay and fixtures for repeatable logic checks; distinguish simulated checks from actual road/device validation. Perform interactive road testing as a passenger or while parked.

Keep precise trip history local by default if retained at all. Define retention and deletion before adding telemetry or shared reporting. If public reports are added, include expiry, duplicate handling, and abuse controls as part of that feature.

## Remaining questions and integration gates

These do not block Phase 1; resolve them before the relevant integration.

1. Check the iPhone's installed iOS against the current app iOS 26.0 deployment target; verify device signing.
2. Verify/request CarPlay navigation entitlement for Roadar using the existing membership; test the actual WRX head unit later.
3. Verify free-tier account access, cost controls, terms, and regional coverage before enabling external services. No additional spending is authorized.
4. Obtain an authorized hazard feed, with MDOT RIDE and TomTom as candidates. A free police-report feed remains unconfirmed; demo reports cannot satisfy the production requirement.
5. Decide whether personal/community reports should supplement external sources; no public backend in the initial scope.
6. Evaluate provisional reroute thresholds (60 seconds and 5% saved, two-minute cooldown) against local journeys and user preference.
7. Choose minimap visual references; offline maps and automatic mode switching remain later options.

## Decision log

| Date | Decision | State / reason |
| --- | --- | --- |
| 2026-09-03 | iPhone maps app with search, navigation, and walking/driving minimap | Confirmed product direction. |
| 2026-09-03 | Driving minimap must work without navigation | Confirmed core requirement. |
| 2026-09-03 | CarPlay is an eventual requirement | Confirmed; feasibility/access remains to be established. |
| 2026-09-03 | Own-trip live ETA is planned | Requested direction; ActivityKit approach provisional. |
| 2026-09-03 | Personal use first; App Store optional | Confirmed scope. |
| 2026-09-03 | Native prototype with replaceable data/routing services | Proposed; provider selection remains open. |
| 2026-09-03 | Ann Arbor–Detroit; iPhone 16 Pro; 2020 Subaru WRX Limited | Confirmed by user in Phase 0. |
| 2026-09-03 | Existing Apple Developer Program membership; free services first | Confirmed by user. No additional spend approved. |
| 2026-09-03 | MapKit/Core Location for Phases 1–2 | Phase 0 prototype choice; avoids external credentials and service spending. |
| 2026-09-03 | Evaluate Mapbox free drive before Phase 3; investigate MDOT RIDE for incidents | Research recommendation; SDK/feed access and regional quality unverified. |
| 2026-09-03 | Police-report source remains unresolved | Waze partner feed is not established as accessible to Roadar. |
| 2026-09-03 | Investigate unofficial Waze Live Map GeoRSS endpoint | User-suggested lead supported by public implementations filtering POLICE alerts; current access, reuse terms, and local coverage unverified. See Phase 0 report. |

## Session handoff — update before ending each work session

**Last completed session:** Southern Michigan data release published and in-app download verified, September 4, 2026. See [PHASE_5_OFFLINE_ROADS.md](PHASE_5_OFFLINE_ROADS.md) for the newest checkpoint; the MDOT notes below describe the preceding checkpoint.

**Current phase:** Phase 5 — Live road information. User selected OSM regional downloads, initially Lansing and south with a northern buffer; additional incident sources deferred. Offline road context and the first public download are built and simulator-verified; physical-device acceptance remains. Continue in order; CarPlay is phase 6. UI redesign preserving functionality remains requested and pending.

**Completed:** Southern Michigan road package, streaming validated Files import, persistent local storage/removal, conservative offline road matching and explicit directional speed limits. The package is 83.9 MB compressed / 182.6 MB installed. Existing authenticated MDOT work zones remain separate. Additional incident sources are deferred. No paid service, map SDK or account enabled.

**Files changed:** `ContentView.swift`; new `OfflineRoadDatabase.swift`, `OfflineRoadMatcher.swift`, `OfflineRoadStore.swift`, `OfflineRoadPanel.swift`, bundled catalog, `OfflineRoadTests.swift`, builder/validation tools, package manifest/notice, Files-sharing configuration, and project handoff documentation. Binary packages are generated local artifacts ignored by git.

**Verification:** All 45 unit tests passed on the iPhone 17 Pro simulator; three builder tests passed. Full-size checksum/decompression/installation and real-geometry synthetic replay passed, including South Main Street and East Hoover Avenue in Ann Arbor. Manual simulator Files import displayed Ready offline, source date and package sizes. The rebuilt app also downloaded the published archive, validated it and installed a fresh 182,566,912-byte database, returning to Ready offline. The public manifest matches the bundled catalog. No physical driving validation performed.

**Unresolved:** Public downloading and Files import work. About 18.2% of included road distance has usable explicit limits. Close/stacked roads and weak location remain ambiguous, and the new local matcher does not make existing MDOT geometry candidates confirmed road matches. Physical journeys and integrated reroute acceptance remain. No offline basemap/search/routing or spoken hazard alerts; guidance is foreground-only.

**Next concrete action:** Perform physical-device and MDOT route-relevance acceptance, including ahead-of-driver filtering without a destination and reliable work-zone road identity. Do not advance to CarPlay yet.

**Implementation authorization:** User approved OSM-based southern Michigan downloadable road information, with future incident sources deferred. No additional spending authorized. User entered the MDOT key directly into the app; do not extract or print it. Prior commit/push authorization applied to the preceding MDOT checkpoint, already committed as `9a94618`. User explicitly approved public hosting of the package, manifest and license notice; these are published at https://github.com/ntm52/Roadar/releases/tag/roads-southern-michigan-2026-09-03. The release tag references the existing MDOT checkpoint. User subsequently authorized committing and pushing the offline app checkpoint.

### Phase 2 acceptance checklist

- [ ] Search a named business and a street address in Ann Arbor–Detroit; inspect and select results.
- [ ] With a fresh location, preview walking and driving routes; confirm geometry, distance and ETA.
- [ ] Compare alternatives where Apple returns them; confirm selected route and travel mode are clear.
- [ ] Change destination or mode during a request; clear and refresh the preview.
- [ ] Check no results, network failure, denied location and weak/stale location; recover and retry.
- [ ] Check portrait, landscape, larger text and VoiceOver on iPhone.

### Phase 1 device acceptance checklist

- [ ] Confirm iPhone runs iOS 26.0 or later and validate the current deployment settings; install through the existing signing team.
- [ ] Allow location and verify initial recenter, walking updates, north-up/heading-up, manual pan and recenter.
- [ ] Check driving mode while parked or as a passenger; confirm map readability in portrait/landscape and light/dark appearance.
- [ ] Deny location, return from Settings, and disable Precise Location; confirm usable map and accurate messages.
- [ ] Check weak GPS/stale updates and recovery, and foreground/background transitions. Phase 1 requests foreground location only.
- [ ] Check larger text and VoiceOver labels on the physical device.

For subsequent sessions, replace the handoff above with the current checkpoint and append a short entry below. Record completed work, exact files, build/device checks and outcomes, decisions, blockers, and next action. Keep this plan current rather than relying on conversation history. Link larger investigations or designs from here if this file becomes unwieldy.

### Session history

- **2026-09-03 — Planning:** Created this document. No application implementation changes.
- **2026-09-03 — Phase 0:** Completed feasibility assessment and baseline build. Confirmed target hardware/region and free-first approach; chose native map prototype; recorded report/data and CarPlay gates in `PHASE_0_FEASIBILITY.md`.

- **2026-09-03 — Phase 1:** Built and simulator-checked the map/location foundation. Physical-device acceptance remains open; no later-phase features added.

- **2026-09-03 — Phase 2:** Implemented search, place details and route comparison. Simulator build and four state/recovery tests passed; live-service simulator walkthrough passed; physical-device and multiple-alternative acceptance remain.

- **2026-09-03 — Phase 3:** Pushed Phase 2 (`b3d87fd`) and built the destination-free minimap prototype. Added actual nearby places and a clearly simulated directed-road replay; provider gates remain.

- **2026-09-03 — Phase 4:** Implemented and simulator-checked foreground visual guidance and conservative route policy. Added seven repeatable guidance tests; physical and integrated journey acceptance remains. See `PHASE_4_GUIDANCE.md`.

### Resume prompt

> Read `PROJECT_PLAN.md` in the Roadar repository. Inspect the current code and repository instructions, then use the session handoff and decision log to identify the next step. Preserve confirmed requirements, distinguish proposals from decisions, and update the plan with the work and verification completed this session.

- **2026-09-03 — Phase 5 investigation:** Confirmed user instruction to retain phase order. Reverted premature CarPlay edits. Checked official live-data source documentation and recorded account/schema gates in `PHASE_5_LIVE_DATA.md`. UI redesign remains requested and pending. No runtime changes or new test results this session.

- **Phase 5 account follow-up:** Mapbox console login verified; no usage in the displayed Aug 5–Sep 4 period. Free-tier personal-use approach and limitations recorded in `PHASE_5_LIVE_DATA.md`. MDOT RIDE awaits user MiLogin agreement/sign-in; Mapbox Navigation download credentials are not configured. No live SDK integration or paid service enabled.

- **Phase 5 MDOT inspection:** Accepted the separately approved RIDE agreement and verified portal access. Incident samples are stale (Aug 5); work-zone WZDx 4.0 samples are current (Sep 4 UTC). API requires a key (401 without it); key generation deferred to avoid replacing an existing credential. Real work-zone JSON downloaded, but terminal file reads hang. Details and next steps in `PHASE_5_LIVE_DATA.md`; runtime integration remains incomplete.

- **Phase 5 connection checkpoint:** User-approved MDOT key generation succeeded. Approval review blocked extracting the secret into tool output; key stays on its one-time browser page for direct user entry. Implemented Keychain connection form, throttled MDOT client, WZDx decoder and nearby work-zone display. Authenticated live response, real-payload validation and road/direction matching remain incomplete. See `PHASE_5_LIVE_DATA.md`.

- **2026-09-04 — Offline roads:** Built Southern Michigan OSM road package (83.9 MB download, 182.6 MB installed), Files import/validation/removal, and local road/limit matching. Actual data revealed 18.2% explicit-limit coverage by included road distance. Full-package checks and simulator tests passed; public GitHub downloading subsequently passed in the simulator; physical acceptance remains. See `PHASE_5_OFFLINE_ROADS.md`. No paid services or new incident providers.

- **2026-09-04 — Public road download:** Published the user-approved Southern Michigan package, manifest and ODbL notice. Confirmed anonymous manifest retrieval, matching release SHA-256, successful app rebuild and actual in-app archive download/validation/installation. No app source commit or push performed.
