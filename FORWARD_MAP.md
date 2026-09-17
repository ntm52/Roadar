# Forward map and compact controls

The phone map now starts in forward-facing mode. Walking uses the compass;
driving uses valid GPS course above 1.5 m/s and retains that course at a stop.
Until a direction is available, the map faces north and still places the user below center. North-up remains
available through the orientation button, and manual map exploration is preserved.

ForwardMapCamera provides an initial forward offset. The phone then uses the actual
map projection and measured header/menu heights to place the user 74% down the
unobstructed map. This also applies when stationary, heading is unavailable, or
north-up is selected. Changes in menu size or screen size reapply the anchor
while following; manual exploration and route previews remain free of corrections. Driving zoom still scales
with speed. This policy is reusable, but no CarPlay scene or entitlement exists
in this project yet; CarPlay integration and screen-specific tuning remain future work.

The bottom panel has a More map / Show details control, also draggable vertically.
Its compact state persists across launches. Compact exploration retains mode
selection; compact guidance retains the next instruction and distance or guidance
status. Selecting a destination expands the full route controls.

The basemap uses MapKit's muted dark standard style with existing charcoal/mint
controls and mint destination markers. This uses native map styling rather than
a custom tile theme, retaining map labels, traffic, and attribution.

Apple reference: https://developer.apple.com/documentation/mapkit/mapstyle/standardemphasis

Verification: Debug simulator build, 59 unit tests, compact-menu persistence and
layout UI check, and map/search/road-details UI walkthrough passed. Simulator
screenshots reviewed for compact and expanded layouts. Physical compass and
moving-vehicle feel still need an on-device check.

## Stronger Roadar styling

A second styling pass adds a green map color multiplier and reduces saturation
to 45%, replaces the system location graphic with a mint dot and halo, replaces
the destination pin with a charcoal flag label, and removes the system scale.
The color treatment applies to the map content only, before attaching the phone
panels and sheets. Road geometry, labels, and attribution still come from Apple;
this is a visual treatment, not a replacement map provider or custom vector style.
The fixed-size location halo is decorative and does not indicate GPS accuracy.


The camera also accepts MapKit's displayed location for framing when Roadar's
separate GPS service is still acquiring a fix. This fallback is camera-only and
does not relax route or guidance validation. Screen coordinates are measured in
the global coordinate space; panel animation settles before reframing.

Final location-anchor verification: five camera tests and two simulator UI tests
passed, including direct rendered-marker checks with expanded and compact menus.
Both screenshots were visually reviewed. Result bundle is in
`/tmp/RoadarForward/Logs/Test` (September 5, 2026, 03:26 run).
