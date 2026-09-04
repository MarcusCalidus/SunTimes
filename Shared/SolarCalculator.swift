import Foundation

/// Solar position / event calculator based on the NOAA Solar Calculator equations.
/// Computes the instants at which the sun's geometric centre crosses a given
/// elevation angle, which lets us derive sunrise/sunset as well as golden and blue hour.
struct SolarCalculator {

    let latitude: Double   // degrees, north positive
    let longitude: Double  // degrees, east positive

    // MARK: - Elevation thresholds (degrees)

    /// Standard sunrise/sunset: -0.833° accounts for refraction + solar disc radius.
    static let horizon: Double = -0.833
    /// Golden hour: sun between -4° and +6°.
    static let goldenHourUpper: Double = 6.0
    static let goldenHourLower: Double = -4.0
    /// Blue hour: sun between -6° and -4°.
    static let blueHourLower: Double = -6.0

    // MARK: - Public API

    /// The instant on the given local day when the sun crosses `elevation`, either rising or setting.
    /// Returns nil if the sun never reaches that elevation on that day (polar regions).
    func time(elevation: Double, rising: Bool, on day: Date, calendar: Calendar = .current) -> Date? {
        guard let localNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { return nil }

        // UTC midnight of the UTC date that contains local noon.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let utcMidnight = utc.startOfDay(for: localNoon)

        // Iterate: first estimate using noon, then refine using the estimated event time.
        var estimate = localNoon
        for _ in 0..<3 {
            guard let minutes = eventMinutesUTC(elevation: elevation, rising: rising, at: estimate) else { return nil }
            estimate = utcMidnight.addingTimeInterval(minutes * 60)
        }
        return estimate
    }

    /// Solar noon for the given local day.
    func solarNoon(on day: Date, calendar: Calendar = .current) -> Date? {
        guard let localNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let utcMidnight = utc.startOfDay(for: localNoon)
        var estimate = localNoon
        for _ in 0..<2 {
            let t = julianCentury(for: estimate)
            let minutes = 720 - 4 * longitude - equationOfTime(t)
            estimate = utcMidnight.addingTimeInterval(minutes * 60)
        }
        return estimate
    }

    /// Sun elevation angle (degrees, refraction not applied) at a given instant.
    func elevation(at date: Date) -> Double {
        let t = julianCentury(for: date)
        let decl = Self.deg2rad(declination(t))
        let lat = Self.deg2rad(latitude)

        // True solar time in minutes
        let minutesSinceMidnightUTC = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 60
        let trueSolarTime = (minutesSinceMidnightUTC + equationOfTime(t) + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }
        let ha = Self.deg2rad(hourAngle)

        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
        let zenith = Self.rad2deg(acos(max(-1, min(1, cosZenith))))
        return 90 - zenith
    }

    // MARK: - Internals

    /// Minutes after UTC midnight at which the sun crosses `elevation`, using the
    /// declination and equation of time evaluated at `reference`.
    private func eventMinutesUTC(elevation: Double, rising: Bool, at reference: Date) -> Double? {
        let t = julianCentury(for: reference)
        guard let ha = hourAngle(elevation: elevation, t: t) else { return nil }
        let noon = 720 - 4 * longitude - equationOfTime(t)
        return rising ? noon - 4 * ha : noon + 4 * ha
    }

    /// Hour angle (degrees) at which the sun is at `elevation`. Nil if never reached.
    private func hourAngle(elevation: Double, t: Double) -> Double? {
        let lat = Self.deg2rad(latitude)
        let decl = Self.deg2rad(declination(t))
        let zenith = Self.deg2rad(90 - elevation)
        let cosHA = (cos(zenith) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
        guard cosHA >= -1, cosHA <= 1 else { return nil }
        return Self.rad2deg(acos(cosHA))
    }

    private func julianDay(for date: Date) -> Double {
        date.timeIntervalSince1970 / 86400 + 2440587.5
    }

    private func julianCentury(for date: Date) -> Double {
        (julianDay(for: date) - 2451545.0) / 36525.0
    }

    private func geomMeanLongSun(_ t: Double) -> Double {
        var l = 280.46646 + t * (36000.76983 + t * 0.0003032)
        l = l.truncatingRemainder(dividingBy: 360)
        return l < 0 ? l + 360 : l
    }

    private func geomMeanAnomSun(_ t: Double) -> Double {
        357.52911 + t * (35999.05029 - 0.0001537 * t)
    }

    private func eccentricityEarthOrbit(_ t: Double) -> Double {
        0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    }

    private func sunEqOfCenter(_ t: Double) -> Double {
        let m = Self.deg2rad(geomMeanAnomSun(t))
        return sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
    }

    private func sunTrueLong(_ t: Double) -> Double {
        geomMeanLongSun(t) + sunEqOfCenter(t)
    }

    private func sunApparentLong(_ t: Double) -> Double {
        let omega = 125.04 - 1934.136 * t
        return sunTrueLong(t) - 0.00569 - 0.00478 * sin(Self.deg2rad(omega))
    }

    private func meanObliquityOfEcliptic(_ t: Double) -> Double {
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        return 23.0 + (26.0 + seconds / 60.0) / 60.0
    }

    private func obliquityCorrection(_ t: Double) -> Double {
        let omega = 125.04 - 1934.136 * t
        return meanObliquityOfEcliptic(t) + 0.00256 * cos(Self.deg2rad(omega))
    }

    /// Solar declination in degrees.
    private func declination(_ t: Double) -> Double {
        let e = Self.deg2rad(obliquityCorrection(t))
        let lambda = Self.deg2rad(sunApparentLong(t))
        return Self.rad2deg(asin(sin(e) * sin(lambda)))
    }

    /// Equation of time in minutes.
    private func equationOfTime(_ t: Double) -> Double {
        let epsilon = Self.deg2rad(obliquityCorrection(t))
        let l0 = Self.deg2rad(geomMeanLongSun(t))
        let e = eccentricityEarthOrbit(t)
        let m = Self.deg2rad(geomMeanAnomSun(t))

        var y = tan(epsilon / 2)
        y *= y

        let eTime = y * sin(2 * l0)
            - 2 * e * sin(m)
            + 4 * e * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * e * e * sin(2 * m)
        return Self.rad2deg(eTime) * 4
    }

    private static func deg2rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func rad2deg(_ r: Double) -> Double { r * 180 / .pi }
}
