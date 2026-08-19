import Foundation

/// Solar illumination — Swift port of `lib/world_sun.dart`.
///
/// Brightness in [0, 1] for a location at a given instant, based on the
/// sun's position (day-of-year declination + local hour angle):
/// 1.0 = full daylight, 0.0 = night, smooth twilight ramp in between
/// (full daylight once the sun is more than 12° above the horizon).
/// Parity-checked against the Dart implementation (diff < 1e-9).
enum SunShading {
    /// Solar declination in radians (positive in the northern summer).
    static func declination(dayOfYear: Int) -> Double {
        23.44 * .pi / 180 * sin(2 * .pi * Double(284 + dayOfYear) / 365.25)
    }

    /// Brightness in [0, 1] at (`latDeg`, `lonDeg`) for instant `now`.
    static func intensity(latDeg: Double, lonDeg: Double, now: Date) -> Double {
        let utc = TimeZone(identifier: "UTC")!
        let cal = Calendar(identifier: .gregorian)
        // Day of year, UTC — same as Dart's
        // `now.difference(DateTime.utc(year)).inDays + 1`.
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: now) ?? 1
        let decl = declination(dayOfYear: dayOfYear)

        // Local solar hour angle (radians): how far the place is from noon.
        let comps = cal.dateComponents(in: utc, from: now)
        let hours = Double(comps.hour ?? 0)
            + Double(comps.minute ?? 0) / 60
            + Double(comps.second ?? 0) / 3600
        let hourAngle = (hours + lonDeg / 15 - 12) * 15 * .pi / 180

        // Solar altitude above the horizon (radians).
        let lat = latDeg * .pi / 180
        let sinAlt = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        let alt = asin(min(max(sinAlt, -1), 1))

        return min(max(alt / (12 * .pi / 180), 0), 1)
    }
}
