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
  IANA tzdb, so each saved city gets a clickable dot on the map with a
  discreet overlay (city, country, local time) and an "always visible"
  toggle.
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
