# Phase 5 — Southern Michigan offline road context

Implemented September 4, 2026 following the user's selection of OpenStreetMap,
Lansing-and-south coverage, and deferral of additional incident providers.

## Delivered

- Repeatable builder crops actual Michigan OSM road data to 42.90°N and packages
  names, direction and explicit speed limits in an indexed SQLite database.
- On-device local spatial queries and conservative direction-aware matching.
  Three fresh distinct moving fixes must establish continuity. Missing limits,
  unsupported directions, close parallel/stacked candidates, poor or stale GPS,
  disconnected jumps and crop boundaries withhold road/limit claims.
- Road downloads sheet shows region, compressed size, installed size, data date,
  Files import, removal, cancellation and error recovery. Files sharing permits
  transferring packages into the app's Documents folder; the working database
  lives in Application Support, excluded from backup. Credentials stay in Keychain.
- Streaming gzip installation, checksum/size verification, read-only SQLite
  validation and atomic replacement preserve a working package on failed imports.
  Database connections reopen at the final path to avoid SQLite moved-file I/O
  failures found with the full-size package.
- Wi-Fi-only HTTPS downloading is enabled with the published GitHub release URL.
  The package, pinned manifest and license notice are publicly available at
  https://github.com/ntm52/Roadar/releases/tag/roads-southern-michigan-2026-09-03.
  File import remains available.
- Driving shows offline road context with or without a navigation destination.
  MDOT behavior remains separate and unchanged. No claim of confirmed road-level
  MDOT relevance is introduced by this checkpoint.

## Measured data

83.9 MB compressed; 182.6 MB installed. Source date September 3, 2026, 20:21:51 UTC.
805,037 cropped way sections; explicit usable limits cover about 18.2% of included
road distance. Service roads/driveways/tracks contribute to the denominator.
See `OfflinePackages/README.md` and the manifest for exact sizes and provenance.

## Validation

The final 45-test iPhone simulator suite passed, including compressed-file corruption and cancellation recovery.
Three builder tests passed for units, directional overrides, conditional limits
and one-way semantics. The production installer verified the entire archive and
its SHA-256, then synthetic movement over real Ann Arbor geometry returned South
Main Street (30 mph) and East Hoover Avenue (25 mph). Outside-region withholding
also passed. This replay made no network calls and is not physical road acceptance. Manual simulator Files import of the actual 83.9 MB archive displayed Ready offline, 805,037 sections and the September 3 source date; the sheet clearly separated 83.9 MB download size from 182.6 MB installed storage.

The public manifest downloaded without authentication and matched the bundled catalog.
After a successful rebuild, the simulator's Download current package action downloaded,
validated and installed the public archive, returning to Ready offline without an error.

## Remaining

- The public data release’s automatic source archives point to the earlier MDOT
  checkpoint. The offline-capable app source is in the subsequent source checkpoint.
  No paid service was enabled.
- Physical iPhone driving/passenger checks: mis-matches, divided roads, overpasses,
  turn transitions, GPS gaps, thermal/battery use and memory use.
- Investigate missing OSM speed-limit coverage before promising broad coverage.
- Online package discovery/update catalog, more regions, cross-border packages and
  partial/differential downloads are future work.
- Basemap rendering, place search and route requests still use existing online
  Apple services. This is not full offline navigation.
- Ahead-of-driver MDOT filtering without a destination, more robust road identity
  for route work zones, and remaining Phase 4/5 acceptance remain open.
- Additional incident/police sources are deferred by the user's current direction.
  CarPlay stays Phase 6; UI redesign remains separately pending.
