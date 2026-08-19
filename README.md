# world_clock

World clock app: a dot-matrix world map with real solar illumination
(places in daylight are bright orange, night places fade into the dark
gray background). The day/night terminator moves with the sun — refreshed
every 30 minutes.

- Flutter app (`lib/`): dot grid from `assets/world_dots.json` (Natural
  Earth, public domain), solar shading computed in `lib/world_sun.dart`,
  adaptive decimation so dots stay well separated on small windows.
- macOS widget (`macos/WorldClockWidget/`): WidgetKit extension that
  renders the same map natively (Swift port of the shading and renderer,
  parity-checked against the Dart code). Fully autonomous: the dot
  dataset is bundled with the extension and the timeline carries one
  entry every 30 minutes, so the widget's terminator moves in sync with
  the app.

## Add the widget to your desktop

1. Build/run the app once: `flutter run -d macos` (or open the built app).
2. Right-click the desktop → **Edit Widgets…** → search **World Clock** →
   drag it to the desktop.

## Notes

- The widget requires macOS 14+ (desktop widgets); the app itself still
  builds for older macOS.
- If the dot dataset changes (`assets/world_dots.json`), copy it to
  `macos/WorldClockWidget/world_dots.json` to keep the widget in sync.
- Tests: `flutter analyze` (no issues) + `flutter test` (10/10).

## Getting Started

A new Flutter project. For help getting started with Flutter development,
view the [online documentation](https://docs.flutter.dev/), which offers
tutorials, samples, guidance on mobile development, and a full API
reference.
