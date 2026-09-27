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
///
/// With `includeTwilight` (the menu option "Incluir crepúsculo"), the night
/// threshold drops 6° BELOW the horizon — the end of civil twilight: the map
/// only goes fully dark once the last daylight has left the sky, instead of
/// the instant the sun touches the horizon.
class SunShading {
  SunShading._();

  /// Sun altitude (degrees) at which daylight is considered full.
  static const double _twilightDeg = 12.0;

  /// Sun altitude (degrees) BELOW the horizon at which the map goes fully
  /// dark when the twilight option is on. −6° is the end of civil twilight
  /// (~25 min after sunset at these latitudes), the moment the marked
  /// darkness settles in; the sun crossing the horizon is the START of dusk,
  /// not its end.
  static const double _civilTwilightDeg = 6.0;

  /// Day of year (1..366) of [utc].
  static int _dayOfYear(DateTime utc) =>
      utc.difference(DateTime.utc(utc.year)).inDays + 1;

  /// Solar declination in radians (positive in the northern summer).
  static double _declination(int dayOfYear) =>
      23.44 * pi / 180 * sin(2 * pi * (284 + dayOfYear) / 365.25);

  /// Brightness in [0, 1] at ([latDeg], [lonDeg]) for instant [now].
  ///
  /// With [includeTwilight], night starts at civil twilight (−6° of sun
  /// altitude) instead of at the horizon; without it (the default) the ramp
  /// is the original one — 0 at the horizon, 1 at +12°.
  static double intensity(
    double latDeg,
    double lonDeg,
    DateTime now, {
    bool includeTwilight = false,
  }) {
    final utc = now.toUtc();
    final decl = _declination(_dayOfYear(utc));

    // Local solar hour angle (radians): how far the place is from solar noon.
    final hours = utc.hour + utc.minute / 60 + utc.second / 3600;
    final hourAngle = (hours + lonDeg / 15 - 12) * 15 * pi / 180;

    // Solar altitude above the horizon (radians).
    final lat = latDeg * pi / 180;
    final sinAlt = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle);
    final alt = asin(sinAlt.clamp(-1.0, 1.0));

    if (includeTwilight) {
      // The SAME ramp, shot down by the civil twilight: full daylight still
      // at +12°, but 0 only at −6° — so the point crosses the dark end while
      // the sky outside still has light.
      final altDeg = alt * 180 / pi;
      return ((altDeg + _civilTwilightDeg) /
              (_twilightDeg + _civilTwilightDeg))
          .clamp(0.0, 1.0);
    }
    return (alt / (_twilightDeg * pi / 180)).clamp(0.0, 1.0);
  }
}
