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
}
