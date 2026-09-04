# Southern Michigan road download

This package contains roads from the Geofabrik Michigan OSM extract, cropped to
longitude -87.0…-82.1 and latitude 41.65…42.90. The northern boundary is about
12 miles above Lansing. It is for road identification and recorded speed limits,
not a basemap, offline search, route calculation, or current incident reporting.

## Current measured package

- Source snapshot: 2026-09-03 20:21:51 UTC.
- Download: `southern-michigan.roadar.gz`, 83,870,944 bytes (83.9 MB).
- Installed database: 182,566,912 bytes (182.6 MB).
- 805,037 cropped OSM way sections, including service roads and tracks.
- Explicit usable speed limits on 76,479 sections, representing approximately
  28,856 of 158,146 included road-kilometers (18.2%). This is source-data coverage,
  not a measured percentage of journeys where a limit will be displayed.
- SHA-256: `a6921af5f4e11770a8780cea9e1fa87c2da5ec2192c1ecd91744974b424c2a62`.

The binary files are generated local artifacts and are excluded from git. The
manifest is retained in this directory and copied into the app to pin the first
package's size, checksum, and installed size. Import the compressed `.roadar.gz`
file through Driving > Road downloads > Import road package from Files.

The package, manifest and notice are published in the user-approved
[GitHub data release](https://github.com/ntm52/Roadar/releases/tag/roads-southern-michigan-2026-09-03).
The bundled `downloadURL` enables Wi-Fi downloading under Driving > Road downloads.
The published manifest matches the app catalog, and an actual simulator download
passed validation and installation. File import also works independently.
The release's automatic source archives reference the earlier MDOT checkpoint;
the offline-capable app source is in the subsequent source checkpoint. No paid service was enabled.
A newer package currently
requires shipping an updated catalog with the app; an online update catalog is
future work.

## Data license and source

© OpenStreetMap contributors. Contains a regional derivative database licensed
under the Open Database License 1.0 (ODbL).

- License and attribution: https://www.openstreetmap.org/copyright
- License text: https://opendatacommons.org/licenses/odbl/1-0/
- Source: https://download.geofabrik.de/north-america/us/michigan.html
- Source download: https://download.geofabrik.de/north-america/us/michigan-latest.osm.pbf

Distribute this notice and the manifest with the package. The `.roadar.gz` file
contains the full derivative road database in SQLite format with a built-in
manifest. This package is not built by bulk downloading OSM's public map tiles.

## Rebuild

Use a temporary Python environment with `osmium==4.3.1`. Download the Michigan
PBF and run:

```
python Tools/build_offline_roads.py INPUT.osm.pbf OfflinePackages/southern-michigan.roadar
python -m unittest discover -s Tools -p 'test_*.py'
```

The output path must not already exist. Retain the JSON manifest alongside the
archive; copy it to `Roadar/southern-michigan.json` when selecting a new version.
Generation runs on the developer machine, not the phone. No server-side query
runs when a driver moves. `Tools/verify_offline_package.swift` exercises the
production installer and matcher against the actual package on macOS.

## Format and limits

SQLite application ID 1380925764, schema/user version 1. Each road stores its OSM
way ID, name, travel direction, explicit per-direction limits, and coordinates.
The packed geometry has one little-endian `(Int32 longitude*1e7,
Int32 latitude*1e7, Int64 OSM_node_id)` record per point. An R-tree indexes each
road's bounds so only nearby candidates are loaded. OSM layer is retained but is
not interpreted as GPS elevation. Turn restrictions/access legality are not a
routing graph in this format. Conditional, variable, lane-specific and symbolic
speed limits are withheld; no speed limit is guessed from road class.
