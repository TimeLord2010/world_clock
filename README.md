# world_clock

World clock app: a dot-matrix world map with real solar illumination
(places in daylight are bright orange, night places fade into the dark
gray background). The day/night terminator moves with the sun — refreshed
every 5 minutes.

- Flutter app (`lib/`): dot grid from `assets/world_dots.json` (Natural
  Earth, public domain), solar shading computed in `lib/world_sun.dart`,
  adaptive decimation so dots stay well separated on small windows.
- Saved cities (`lib/city_*.dart`): a searchable catalog
  (`assets/cities.json`) whose time zones are resolved **offline** from the
  IANA tzdb, so each saved city gets a dot on the map with its name and
  local time always in view.
- macOS widget (`macos/WorldClockWidget/`): WidgetKit extension that
  renders the same map natively (Swift port of the shading and renderer,
  parity-checked against the Dart code). Fully autonomous: the dot
  dataset is bundled with the extension and the timeline carries one
  entry every 30 minutes, so the widget's terminator keeps moving on its
  own (twice as coarse as the app's 5-minute refresh).

## Add the widget to your desktop

1. Build/run the app once: `flutter run -d macos` (or open the built app).
2. Right-click the desktop → **Edit Widgets…** → search **World Clock** →
   drag it to the desktop.

## Saved cities

Menu (top right) → **Cidades**: search the catalog in Portuguese, without
needing the accents (`sao paulo`, `tokio`), and tap a row to put that city
on the map or take it off.

- Every saved city shows a **ring on its exact coordinate** — not snapped
  to the 1° dot grid, since a city is not a land dot (Fortaleza, for one,
  falls on an *ocean* cell of the grid).
- Alongside the ring, the city's **name and local time are always in
  view**. There is no click to open and nothing to switch on: a city that
  is on the map is on the map with its clock showing. `+1 dia` appears next
  to the time when the date over there is not the date here.
- The label is **bare text, no card**: no background, no border, no country
  line, no UTC offset. What separates it from the dot matrix is a dark halo
  around the glyphs, and the two lines are set small on purpose so they sit
  in the map rather than on top of it.
- Times come from the IANA tzdb, so daylight saving is right by
  construction: Sydney reads `UTC+11` in January and `UTC+10` in July, and
  the 45- and 30-minute zones (Chatham, Kathmandu, St. John's) are not
  rounded to the hour.
- The clock ticks on the minute boundary and rebuilds only its own layer:
  the map's tens of thousands of dots are never repainted by it (there are
  tests asserting exactly that).
- Only the catalog **ids** are persisted, via `shared_preferences`. An id
  that disappears from the catalog after a regeneration is dropped
  silently rather than blocking the app.

Worth knowing: with `Cidades` carrying a long list, the labels can overlap
where cities are close together — there is no collision avoidance yet.

## City catalog

`assets/cities.json` is generated, never hand-edited:

```sh
dart run tool/build_cities.dart <path>/ne_10m_populated_places.geojson
```

- **Places** — Natural Earth 5.1.2 `ne_10m_populated_places` (public
  domain, the same data family as the dot grid): 7,341 places with the
  Portuguese name (`NAME_PT`), state, ISO country, coordinates and
  population.
- **Time zones** — Timezone Boundary Builder polygons (© OpenStreetMap
  contributors, ODbL), resolved at generation time by
  `package:timezone_finder`. The Natural Earth `TIMEZONE` field is **not**
  used as an answer: it is corrupt — it puts Lagos in `Europe/Athens`,
  Prague in `America/Chicago`, Cardiff in `Australia/Sydney` and Macau in
  `America/Fortaleza`. Adjudicated against Open-Meteo as a third source,
  the polygons won 13 of 14 cases (the 14th was the polygons being *newer*
  than Open-Meteo: `America/Coyhaique`, added in tzdb 2025b). 564 of the
  7,342 entries disagree with the polygons, 86 of them with a real offset
  difference. The generator prints this count on every run.
- The input GeoJSON is not versioned (19 MB); the output (581 KB) is.
- The generator is **deterministic**: two runs over the same input produce
  byte-identical output.

The app never resolves polygons at runtime: the zones travel inside the
asset, and the app only needs `package:timezone` for offsets and DST rules.
So saved cities work with no network, no API key and no rate limit.

## Notes

- The widget requires macOS 14+ (desktop widgets); the app itself still
  builds for older macOS.
- If the dot dataset changes (`assets/world_dots.json`), copy it to
  `macos/WorldClockWidget/world_dots.json` to keep the widget in sync.
- The desktop widget does **not** show saved cities: it stays fully
  autonomous (no App Group, no shared state with the app). `cities.json`
  is therefore app-only — do not copy it into the widget bundle.
- Tests: `flutter analyze` (no issues) + `flutter test` (all green).

## Getting Started

A new Flutter project. For help getting started with Flutter development,
view the [online documentation](https://docs.flutter.dev/), which offers
tutorials, samples, guidance on mobile development, and a full API
reference.
