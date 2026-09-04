// Verification script: compiles the shared solar code on macOS and prints
// events for a few well-known locations/dates so they can be checked against
// timeanddate.com / NOAA.
//
// Run:  swift Scripts/verify.swift   (from the SunTimes directory) -- or use Scripts/verify.sh
import Foundation

struct Case {
    let name: String
    let lat: Double
    let lon: Double
    let tz: String
    let year: Int, month: Int, day: Int
    let expectedSunrise: String
    let expectedSunset: String
}

let cases = [
    // Reference values from timeanddate.com (rounded to the minute).
    Case(name: "London, 21 Jun 2024", lat: 51.5074, lon: -0.1278, tz: "Europe/London",
         year: 2024, month: 6, day: 21, expectedSunrise: "04:43", expectedSunset: "21:21"),
    Case(name: "Berlin, 21 Dec 2024", lat: 52.52, lon: 13.405, tz: "Europe/Berlin",
         year: 2024, month: 12, day: 21, expectedSunrise: "08:15", expectedSunset: "15:54"),
    Case(name: "Sydney, 15 Mar 2024", lat: -33.8688, lon: 151.2093, tz: "Australia/Sydney",
         year: 2024, month: 3, day: 15, expectedSunrise: "06:54", expectedSunset: "19:13"),
    Case(name: "New York, 4 Jul 2024", lat: 40.7128, lon: -74.0060, tz: "America/New_York",
         year: 2024, month: 7, day: 4, expectedSunrise: "05:31", expectedSunset: "20:30"),
    Case(name: "Tromsø, 21 Jun 2024 (polar day)", lat: 69.6492, lon: 18.9553, tz: "Europe/Oslo",
         year: 2024, month: 6, day: 21, expectedSunrise: "—", expectedSunset: "—"),
]

for c in cases {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: c.tz)!
    let day = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!

    let fmt = DateFormatter()
    fmt.timeZone = cal.timeZone
    fmt.dateFormat = "HH:mm"

    let schedule = SunEventSchedule(latitude: c.lat, longitude: c.lon, calendar: cal)
    let events = schedule.events(on: day)

    print("== \(c.name)  (expected sunrise \(c.expectedSunrise), sunset \(c.expectedSunset))")
    if events.isEmpty {
        print("   no events (sun never crosses thresholds)")
    }
    for e in events {
        print(String(format: "   %-24@ %@", e.kind.rawValue as NSString, fmt.string(from: e.date)))
    }
    if let noon = schedule.calculator.solarNoon(on: day, calendar: cal) {
        print("   solar noon              \(fmt.string(from: noon))  elevation \(String(format: "%.1f", schedule.calculator.elevation(at: noon)))°")
    }
    print()
}
