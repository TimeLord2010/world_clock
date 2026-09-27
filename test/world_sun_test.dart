import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/world_sun.dart';

void main() {
  group('SunShading', () {
    // 2026-03-20 ≈ vernal equinox: sun over the equator, declination ≈ 0.
    test('solar noon at the equator is full daylight', () {
      final noon = DateTime.utc(2026, 3, 20, 12);
      expect(SunShading.intensity(0, 0, noon), closeTo(1.0, 0.01));
    });

    test('solar midnight at the equator is night', () {
      final midnight = DateTime.utc(2026, 3, 20, 0);
      expect(SunShading.intensity(0, 0, midnight), closeTo(0.0, 0.01));
    });

    test('the terminator crosses the equator at sunrise/sunset', () {
      // 05:30 UTC on the prime meridian is still night...
      final preDawn = DateTime.utc(2026, 3, 20, 5, 30);
      expect(SunShading.intensity(0, 0, preDawn), closeTo(0.0, 0.01));
      // ...06:30 UTC is mid-twilight...
      final sunrise = DateTime.utc(2026, 3, 20, 6, 30);
      final t = SunShading.intensity(0, 0, sunrise);
      expect(t, inInclusiveRange(0.05, 0.95));
      // ...and 07:30 UTC is already full daylight.
      final afterSunrise = DateTime.utc(2026, 3, 20, 7, 30);
      expect(SunShading.intensity(0, 0, afterSunrise), closeTo(1.0, 0.01));
    });

    test('polar day at the north pole on the June solstice', () {
      final solstice = DateTime.utc(2026, 6, 21, 0);
      expect(SunShading.intensity(90, 0, solstice), greaterThan(0.9));
    });

    test('polar night at the south pole on the June solstice', () {
      final solstice = DateTime.utc(2026, 6, 21, 0);
      expect(SunShading.intensity(-90, 0, solstice), lessThan(0.1));
    });

    test('it gets darker away from solar noon', () {
      // At 12:00 UTC the prime meridian is at noon; 90°E is already 18:00.
      final noon = DateTime.utc(2026, 3, 20, 12);
      expect(
        SunShading.intensity(0, 0, noon),
        greaterThan(SunShading.intensity(0, 90, noon)),
      );
    });
  });

  group('SunShading with the twilight option', () {
    // Anchors measured for Florianópolis on 2026-09-27 by running the repo's
    // own formula (see the scratch probe): at 18:30 local the sky outside
    // still has light, 18:19:22 is the moment the ORIGINAL ramp reaches zero
    // (sun at the horizon) and 18:46:32 is the end of civil twilight (sun
    // 6° below the horizon).
    const lat = -27.5967;
    const lon = -48.5492;

    test('the default ramp is untouched: night starts at the horizon', () {
      final dusk = DateTime.utc(2026, 9, 27, 21, 30); // 18:30 local
      expect(SunShading.intensity(lat, lon, dusk), 0.0);
    });

    test('with the twilight, 18:30 (11 min into dusk) still has light', () {
      // Sun altitude at that instant: −2,354° → (−2,354 + 6) / 18 = 0,2026.
      final dusk = DateTime.utc(2026, 9, 27, 21, 30);
      expect(
        SunShading.intensity(lat, lon, dusk, includeTwilight: true),
        closeTo(0.2026, 0.003),
      );
    });

    test('the horizon crossing turns full dark into one third of light', () {
      final horizon = DateTime.utc(2026, 9, 27, 21, 19, 22); // 18:19:22 local
      expect(SunShading.intensity(lat, lon, horizon), 0.0);
      expect(
        SunShading.intensity(lat, lon, horizon, includeTwilight: true),
        closeTo(1 / 3, 0.003),
      );
    });

    test('full dark only at the end of the civil twilight', () {
      final civilEnd = DateTime.utc(2026, 9, 27, 21, 46, 32); // 18:46:32 local
      expect(
        SunShading.intensity(lat, lon, civilEnd, includeTwilight: true),
        closeTo(0.0, 0.001),
      );
    });

    test('full daylight is full daylight in both ramps', () {
      final noon = DateTime.utc(2026, 9, 27, 15); // 12:00 local
      expect(SunShading.intensity(lat, lon, noon), 1.0);
      expect(SunShading.intensity(lat, lon, noon, includeTwilight: true), 1.0);
    });
  });
}
