import 'dart:math';

/// Solar illumination for the world map.
///
/// Computes how bright a location is at a given moment using a standard
/// low-precision solar-position approximation (day-of-year declination plus
/// local hour angle). Returns a value in [0, 1]:
///
/// * `1.0` — full daylight (sun well above the horizon),
/// * `0.0` — night (sun below the horizon),
///
/// with a smooth twilight ramp in between (full daylight once the sun is
/// more than 12° above the horizon).
class SunShading {
  SunShading._();

  /// Sun altitude (degrees) at which daylight is considered full.
  static const double _twilightDeg = 12.0;

  /// Day of year (1..366) of [utc].
  static int _dayOfYear(DateTime utc) =>
      utc.difference(DateTime.utc(utc.year)).inDays + 1;

  /// Solar declination in radians (positive in the northern summer).
  static double _declination(int dayOfYear) =>
      23.44 * pi / 180 * sin(2 * pi * (284 + dayOfYear) / 365.25);

  /// Brightness in [0, 1] at ([latDeg], [lonDeg]) for instant [now].
  static double intensity(double latDeg, double lonDeg, DateTime now) {
    final utc = now.toUtc();
    final decl = _declination(_dayOfYear(utc));

    // Local solar hour angle (radians): how far the place is from solar noon.
    final hours = utc.hour + utc.minute / 60 + utc.second / 3600;
    final hourAngle = (hours + lonDeg / 15 - 12) * 15 * pi / 180;

    // Solar altitude above the horizon (radians).
    final lat = latDeg * pi / 180;
    final sinAlt = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle);
    final alt = asin(sinAlt.clamp(-1.0, 1.0));

    return (alt / (_twilightDeg * pi / 180)).clamp(0.0, 1.0);
  }
}
