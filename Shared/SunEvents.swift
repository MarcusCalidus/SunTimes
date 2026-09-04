import Foundation
import SwiftUI

/// The lighting phase the sky is currently in.
enum SunPhase: String, Codable, CaseIterable {
    case night
    case blueHour
    case goldenHour
    case day

    var title: String {
        switch self {
        case .night: return "Night"
        case .blueHour: return "Blue Hour"
        case .goldenHour: return "Golden Hour"
        case .day: return "Day"
        }
    }

    var color: Color {
        switch self {
        case .night: return Color(red: 0.35, green: 0.40, blue: 0.70)
        case .blueHour: return Color(red: 0.30, green: 0.55, blue: 1.00)
        case .goldenHour: return Color(red: 1.00, green: 0.65, blue: 0.20)
        case .day: return Color(red: 1.00, green: 0.85, blue: 0.30)
        }
    }
}

/// A single transition of the sun across an elevation threshold.
enum SunEventKind: String, Codable, CaseIterable {
    case morningBlueHourStart   // -6°, rising  → blue hour begins
    case morningGoldenHourStart // -4°, rising  → golden hour begins (blue ends)
    case sunrise                // -0.833°, rising
    case morningGoldenHourEnd   // +6°, rising  → day begins
    case eveningGoldenHourStart // +6°, setting
    case sunset                 // -0.833°, setting
    case eveningBlueHourStart   // -4°, setting → blue hour begins (golden ends)
    case eveningBlueHourEnd     // -6°, setting → night

    var elevation: Double {
        switch self {
        case .morningBlueHourStart, .eveningBlueHourEnd: return SolarCalculator.blueHourLower
        case .morningGoldenHourStart, .eveningBlueHourStart: return SolarCalculator.goldenHourLower
        case .sunrise, .sunset: return SolarCalculator.horizon
        case .morningGoldenHourEnd, .eveningGoldenHourStart: return SolarCalculator.goldenHourUpper
        }
    }

    var isRising: Bool {
        switch self {
        case .morningBlueHourStart, .morningGoldenHourStart, .sunrise, .morningGoldenHourEnd: return true
        case .eveningGoldenHourStart, .sunset, .eveningBlueHourStart, .eveningBlueHourEnd: return false
        }
    }

    /// Phase that begins once this event happens.
    var phaseAfter: SunPhase {
        switch self {
        case .morningBlueHourStart: return .blueHour
        case .morningGoldenHourStart: return .goldenHour
        case .sunrise: return .goldenHour
        case .morningGoldenHourEnd: return .day
        case .eveningGoldenHourStart: return .goldenHour
        case .sunset: return .goldenHour
        case .eveningBlueHourStart: return .blueHour
        case .eveningBlueHourEnd: return .night
        }
    }

    /// Short label suitable for a corner/circular complication.
    var shortTitle: String {
        switch self {
        case .morningBlueHourStart: return "Blue"
        case .morningGoldenHourStart: return "Golden"
        case .sunrise: return "Sunrise"
        case .morningGoldenHourEnd: return "Day"
        case .eveningGoldenHourStart: return "Golden"
        case .sunset: return "Sunset"
        case .eveningBlueHourStart: return "Blue"
        case .eveningBlueHourEnd: return "Night"
        }
    }

    var title: String {
        switch self {
        case .morningBlueHourStart: return "Blue Hour"
        case .morningGoldenHourStart: return "Golden Hour"
        case .sunrise: return "Sunrise"
        case .morningGoldenHourEnd: return "Golden Hour Ends"
        case .eveningGoldenHourStart: return "Golden Hour"
        case .sunset: return "Sunset"
        case .eveningBlueHourStart: return "Blue Hour"
        case .eveningBlueHourEnd: return "Blue Hour Ends"
        }
    }

    var symbolName: String {
        switch self {
        case .sunrise: return "sunrise.fill"
        case .sunset: return "sunset.fill"
        case .morningGoldenHourStart, .eveningGoldenHourStart: return "sun.horizon.fill"
        case .morningGoldenHourEnd: return "sun.max.fill"
        case .morningBlueHourStart, .eveningBlueHourStart: return "sun.haze.fill"
        case .eveningBlueHourEnd: return "moon.stars.fill"
        }
    }

    var color: Color { phaseAfter.color }
}

struct SunEvent: Identifiable, Codable, Hashable {
    let kind: SunEventKind
    let date: Date

    var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
}

/// Produces ordered sun events for a location across a range of days.
struct SunEventSchedule {
    let calculator: SolarCalculator
    var calendar: Calendar = .current

    init(latitude: Double, longitude: Double, calendar: Calendar = .current) {
        self.calculator = SolarCalculator(latitude: latitude, longitude: longitude)
        self.calendar = calendar
    }

    /// All events for a single local day, in chronological order.
    /// Events the sun never reaches that day (polar regions) are omitted.
    func events(on day: Date) -> [SunEvent] {
        SunEventKind.allCases.compactMap { kind in
            calculator.time(elevation: kind.elevation, rising: kind.isRising, on: day, calendar: calendar)
                .map { SunEvent(kind: kind, date: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Events from yesterday through `daysAhead` days into the future, sorted.
    func events(around date: Date, daysAhead: Int = 2) -> [SunEvent] {
        let start = calendar.startOfDay(for: date)
        return (-1...daysAhead).flatMap { offset -> [SunEvent] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return [] }
            return events(on: day)
        }
        .sorted { $0.date < $1.date }
    }

    /// The event that most recently occurred before `date`, and the next one after it.
    func surroundingEvents(at date: Date, in events: [SunEvent]) -> (previous: SunEvent?, next: SunEvent?) {
        let previous = events.last { $0.date <= date }
        let next = events.first { $0.date > date }
        return (previous, next)
    }

    /// Current phase at `date`, derived from the last event that happened.
    /// Falls back to elevation when no events exist (polar day/night).
    func phase(at date: Date, in events: [SunEvent]) -> SunPhase {
        if let previous = surroundingEvents(at: date, in: events).previous {
            return previous.kind.phaseAfter
        }
        let elevation = calculator.elevation(at: date)
        switch elevation {
        case ..<SolarCalculator.blueHourLower: return .night
        case ..<SolarCalculator.goldenHourLower: return .blueHour
        case ..<SolarCalculator.goldenHourUpper: return .goldenHour
        default: return .day
        }
    }
}
