# Phase 0 — feasibility and prototype decisions

Reviewed: 2026-09-03. Planning assessment complete; no feature implementation. This report supports `PROJECT_PLAN.md`. Prices and allowances are a dated snapshot, not a guarantee of account eligibility or future pricing.

## Outcome

Proceed with an incremental native iPhone prototype at **$0 additional service spending**. Use MapKit and Core Location for Phases 1–2. Before implementing real road matching in Phase 3, evaluate Mapbox Navigation's free tier against the local driving requirements. Keep shared trip/location state separate from map presentation so that moving to another map SDK does not require rewriting the entire app.

The complete vision is technically plausible, but a free source of current police reports has not been established. Custom route selection can be prototyped; consistently beating Google Maps has not been demonstrated. Neither limitation prevents the map/location prototype.

## Confirmed requirements

| Item | Decision |
| --- | --- |
| Initial geography | Ann Arbor–Detroit, Michigan, including connecting roads and local streets. |
| Phone | iPhone 16 Pro; installed iOS version still to be checked before device installation. |
| Car | 2020 Subaru WRX Limited; test the actual head unit and connection during CarPlay integration. |
| Apple membership | User confirms an existing Apple Developer Program membership. |
| Spending | Investigate free options first. No additional paid services, subscriptions, or overage spending authorized. |
| Product | Personal use first, destination-free minimap essential, CarPlay eventual requirement, App Store optional. |

## Project and build audit

- Xcode 26.6, build 17F113; installed iOS and iOS Simulator SDKs report 26.5.
- App deployment target is **iOS 26.5**. The iPhone model alone does not establish that it runs this OS. Keep the project setting for now; verify the phone OS before Phase 1 device testing and deliberately adjust compatibility if necessary.
- App bundle identifier: `com.nathanmayo.Roadar`; automatic signing and a development team are configured. This does not prove current certificates, device registration, or CarPlay entitlement approval.
- App currently targets iPhone and iPad. Product/testing priority is iPhone; existing iPad targeting need not be removed to begin.
- Swift language mode is 5.0. SwiftUI and SwiftData starter files remain unchanged; no external SDK dependencies were found in the project.
- Generated Info.plist; no location usage text, background-location setup, CarPlay scene/entitlement, or Live Activity extension is implemented.
- Unit test is a placeholder. No navigation behavior exists to test yet.
- **Baseline build passed:** Debug iOS Simulator build, unsigned, for arm64 and x86_64. Output: `/tmp/Roadar-phase0-build/Build/Products/Debug-iphonesimulator/Roadar.app`; temporary log: `/tmp/Roadar-phase0-build.log`.
- Initial sandbox restrictions interfered with Xcode services; the authorized build outside the sandbox succeeded. The only notable final warning was skipped App Intents metadata extraction because the starter has no AppIntents dependency.
- This was a compile check, not a simulator launch, device test, signing check, or CarPlay test. No tests were added for this planning-only change.

Reproduce from the repository root:

```sh
xcodebuild -project Roadar.xcodeproj -scheme Roadar -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/Roadar-phase0-build CODE_SIGNING_ALLOWED=NO build
```

## Free options and limits

| Option | What it can contribute | Cost/access finding | Recommendation |
| --- | --- | --- | --- |
| Native Apple MapKit | Maps, place search, walking/driving route requests and alternatives. | Apple DTS states native MapKit has no cost beyond Developer Program membership; some APIs are throttled. This statement is older, and is distinct from web/server quotas. [Apple staff explanation](https://developer.apple.com/forums/thread/127493), [MapKit](https://developer.apple.com/documentation/mapkit/). | Select for Phases 1–2. Do not assume it exposes all Apple Maps consumer-app features or a usable speed-limit/road-graph/report feed. |
| Mapbox Navigation v3 | Destination-free road matching, road name and speed limit; custom driving UI. | Metered navigation currently lists the first 100 monthly active users and 1,000 monthly trips free. Maps and search are separately metered. [Pricing](https://www.mapbox.com/pricing), [free-drive capabilities](https://docs.mapbox.com/ios/navigation/guides/free-drive/user-interface/). | Preferred next candidate for real driving minimap, conditional on account terms and local coverage. |
| TomTom APIs | Traffic-aware routing; Snap to Roads with road attributes; traffic incidents. | Current published monthly free allowances: routing 20,000; Snap to Roads 2,500; incident details 2,500. Signup advertises no upfront credit card. [Pricing](https://docs.tomtom.com/pricing). | Secondary candidate for route comparison and hazards. API allowances do not establish free iOS Navigation SDK access. |
| TomTom iOS Navigation SDK | Free-driving mode with speed limits and street context. | Specific iOS documentation says access is available upon request, despite broader pricing-page language about SDK access. [Free-driving guide](https://docs.tomtom.com/navigation/ios/guides/navigation/free-driving). | Keep as alternative; access and price must be resolved before choosing it. |
| MDOT RIDE | Michigan traffic events and work-zone locations. | MDOT documents public real-time data access through an API after MiLogin for Business registration. No price is listed on this page; account-level conditions remain unchecked. [MDOT ITS data](https://www.michigan.gov/mdot/travel/safety/efforts/its/its-data). | First local public-data candidate. Verify schema, direction, timestamps, reuse conditions, and coverage after access. |
| Valhalla / OpenStreetMap | Open-source routing with dynamic cost controls. | The engine is available, but hosting, graph updates and traffic ingestion remain our responsibility; no ready-to-use traffic feed was established. [Project](https://github.com/valhalla/valhalla), [API schema](https://github.com/valhalla/valhalla/blob/master/docs/docs/api/openapi.yaml). | Defer. More control is attractive, but operations and data work are disproportionate for the first personal prototype. |

**Practical Mapbox estimate:** one person taking four guided trips per day is about 120 trips/month. Two additional hours of free drive per day can add roughly 60 hourly trips, plus session starts/testing. That example fits the listed navigation free allowance, but is not a complete invoice estimate. Free drive is billed in sessions with a one-hour maximum, test simulators can count as users, and maps/search are separate line items. Confirm the complete account plan and overage controls before enabling the SDK. [Navigation billing guide](https://docs.mapbox.com/ios/navigation/guides/pricing/).

**Practical TomTom limit:** one incident request every minute for one hour/day is about 1,800 requests/month; two hours/day is about 3,600, exceeding the listed 2,500 allowance. Therefore use a bounded active-session polling policy, not continuous background requests. This is request arithmetic, not a chosen production refresh interval.

Mapbox also lists Electronic Horizon in public preview for probable-path road data. Treat preview stability and access as a separate investigation before depending on it for alerts around forks. [Pricing and preview listing](https://www.mapbox.com/pricing).

No accounts were created, keys acquired, billing activated, or external SDKs installed in Phase 0. For a zero-spend implementation, use provider-enforced caps where available and disable optional integrations if zero-cost enforcement cannot be established. Usage estimates alone do not prevent charges. Check display/attribution, caching, and cross-provider use terms when selecting an integration; no mixed-provider licensing conclusion is made here.

## Police reports and hazards

Treat these as different data problems:

- **Traffic incidents/work zones:** MDOT RIDE and TomTom are credible candidates. TomTom documents incident geometry and identifiers; validate direction and timestamps with real responses before alerts. [Incident Details](https://docs.tomtom.com/traffic-api/documentation/tomtom-maps/v1/traffic-incidents/incident-details).
- **Reported police:** no unrestricted, confirmed free feed found in this assessment. Waze's documented feed is for Waze for Cities partners and data approved under their agreements, not a general consumer-app entitlement. [Waze feed specification](https://support.google.com/waze/partners/answer/13458165?hl=en).
- **Initial fallback:** explicit demo reports for development; optionally local personal reports later. Personal reports do not solve discovering reports ahead from other drivers. A community would require a backend, contributors, expiry, and abuse handling.

Keep police reports in the product plan as an unresolved feature dependency. Do not silently replace them with speed cameras or mark a mock feed as production-ready.

### Waze API follow-up

The user's suggestion led to a concrete additional lead: open-source projects query Waze Live Map's **`/live-map/api/georss`** endpoint and filter `POLICE` alerts. See [waze-police implementation](https://github.com/jossef/waze-police/blob/master/main.py) and [waze-alerts-notifier](https://github.com/guberm/waze-alerts-notifier). These are primary evidence of third-party implementations, not official Waze API documentation. The notifier itself describes the source as unofficial and unstable. Current endpoint operation and Ann Arbor–Detroit police-report coverage have not been tested.

Keep this as an **experimental candidate**, not a rejected possibility and not a confirmed dependency. Before adopting it, establish current access, permitted reuse, necessary alert fields, freshness, and behavior when unavailable. No live endpoint calls or integration were performed in Phase 0.

The official alternatives are distinct: Waze for Cities accepts government agencies/private road operators, so Roadar's personal-project use does not match its published eligibility. The Google Developers “partner data feed” documentation describes uploading alerts **to** Waze, rather than downloading community reports. [Eligibility](https://support.google.com/waze/partners/answer/10453062?hl=en), [feed direction](https://developers.google.com/waze/data-feed/overview). This assessment therefore establishes a possible unofficial technical route, but still no confirmed supported police-report feed for Roadar.

## CarPlay and own-trip ETA

Use the existing paid membership and investigate Apple's navigation entitlement for this app identifier. The entitlement key is `com.apple.developer.carplay-maps`; Apple provides a request flow and CarPlay developer resources. [Requesting entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements), [entitlement key](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.carplay-maps), [CarPlay resources](https://developer.apple.com/carplay/).

Concrete sequence:

1. Check whether the Roadar App ID already has approved CarPlay navigation capability. No authenticated portal inspection was performed here.
2. If absent, prepare/request navigation access using the product description below. Approval is external; do not treat membership as approval.
3. Once approved, configure entitlement/provisioning and CarPlay scene support. Build with Apple's permitted map controls/templates, not an arbitrary phone interface mirrored onto the car.
4. Verify destination-free map, trip preview, navigation, report presentation, reconnect, audio interruptions, and phone/car state consistency in simulator and the user's actual WRX. Exact permissible alert UI is an integration/design gate.

Draft product description for the request (not submitted):

> Roadar is an iPhone navigation app initially intended for personal use in the Ann Arbor–Detroit region. It will provide place search, route previews, turn-by-turn guidance and ETAs, plus a destination-free driving map with road context and available speed-limit information. Its CarPlay interface will use the navigation category's supported map and guidance controls. Road-event information will be included only when an appropriate data source is available.

Private device installation through Xcode is the initial distribution plan; App Store submission is unnecessary for the first phone prototype. CarPlay approval/provisioning remains separate from that installation workflow.

For Live Activities, start with app-driven own-trip ETA updates and no server. Use shared trip state and show stale information honestly; evaluate remote push only if device tests establish a need. Background location requires its own lifecycle/permission setup and device testing. [ActivityKit](https://developer.apple.com/documentation/activitykit), [background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background).

## Routing experiment and provisional policy

MapKit's route prototype will select the lowest ETA among available valid alternatives. Mapbox's Directions API is a candidate for a later traffic-aware comparison, not evidence that it will consistently beat Apple or Google. [MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections), [Mapbox Directions](https://docs.mapbox.com/api/navigation/directions/).

Use these adjustable starting values for experiments, not confirmed user preferences: rank by ETA at initial selection; consider an automatic mid-trip switch when predicted saving is at least **60 seconds and 5%** of remaining time; use a **two-minute cooldown**. Off-route recovery and a known invalid/closed route bypass the cooldown. Show smaller potential savings for manual selection. Do not penalize smaller roads solely for being smaller.

Proposed local test set (no routes or live conditions have yet been measured):

| Scenario | What it tests |
| --- | --- |
| Ann Arbor–Detroit via the I-94 corridor | Congestion alternatives and long-trip ETA. |
| Ann Arbor–Plymouth/Livonia via M-14 and connecting roads | Freeway/arterial choices and interchange matching. |
| Ann Arbor–Ypsilanti local streets | Shortcuts, extra-turn tradeoffs and short-trip rerouting. |
| Downtown Ann Arbor walking loop | Business search, heading, label clutter and GPS quality. |
| Downtown Detroit streets and freeway service roads | Parallel-road/overpass alert mistakes and ambiguous direction. |

For each selected origin/destination pair, record simultaneous provider ETAs, route geometry/distance, departure time, selected route, arrival time, and reroute count. Repeat representative journeys at peak and off-peak times. Compare ETA error for the route actually driven; untraveled alternatives are estimates, not measured savings. Google Maps comparisons can be recorded manually for equivalent departure times. No claim of superiority until repeatable evidence exists.

## Phase 0 exit and next session

- [x] Confirm region, phone, vehicle, membership, and free-first budget constraint.
- [x] Audit project settings and compile the untouched starter.
- [x] Choose achievable prototype scope and identify candidate data sources.
- [x] Establish CarPlay request path, own-trip ETA approach, and routing experiment.
- [x] Record unresolved access/coverage issues instead of assuming they are solved.

**Ready for Phase 1:** implement map display, location permission, recentering, heading, explicit walking/driving modes, and denied/poor-location states with native Apple frameworks. No backend or API key is needed for this scope.

**Before device validation:** check installed iOS and signing on the iPhone. **Before Phase 3 real data:** validate SDK free-tier access and local road matching. **Before Phase 5:** acquire an authorized incident source; police reports remain unresolved. **Before Phase 6:** obtain/verify CarPlay entitlement. These are future gates, not claims that those phases have been completed.
