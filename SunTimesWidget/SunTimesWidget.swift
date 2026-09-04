import WidgetKit
import SwiftUI
import CoreLocation

// MARK: - Timeline entry

struct SunEntry: TimelineEntry {
    let date: Date
    /// Current lighting phase at `date`.
    let phase: SunPhase
    /// The event that just happened (used for the gauge's start).
    let previous: SunEvent?
    /// The event coming up next (the main thing the complication shows).
    let next: SunEvent?
    /// Today's full list, for the rectangular family.
    let todayEvents: [SunEvent]
    let hasLocation: Bool

    static let placeholder = SunEntry(
        date: Date(),
        phase: .day,
        previous: nil,
        next: SunEvent(kind: .sunset, date: Date().addingTimeInterval(3600 * 3)),
        todayEvents: [],
        hasLocation: true
    )
}

// MARK: - Provider

struct SunTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> SunEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SunEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            let entries = await buildEntries(now: Date(), maxCount: 1)
            completion(entries.first ?? .placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunEntry>) -> Void) {
        Task {
            let now = Date()
            let entries = await buildEntries(now: now, maxCount: 40)
            // Refresh after the last entry, or in 12h if we couldn't compute anything
            // (e.g. no location yet) so we pick up a location once the app has one.
            let refresh = entries.last?.date.addingTimeInterval(60) ?? now.addingTimeInterval(12 * 3600)
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

    /// Builds entries: one for "now" plus one for every upcoming event boundary.
    private func buildEntries(now: Date, maxCount: Int) async -> [SunEntry] {
        // Widgets get very little runtime; keep the location timeout short and fall back to cache.
        guard let coordinate = await LocationResolver.resolve(timeout: 4) else {
            return [SunEntry(date: now, phase: .day, previous: nil, next: nil, todayEvents: [], hasLocation: false)]
        }

        let schedule = SunEventSchedule(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let all = schedule.events(around: now, daysAhead: 2)
        let calendar = Calendar.current

        func entry(at date: Date) -> SunEntry {
            let (prev, next) = schedule.surroundingEvents(at: date, in: all)
            let today = all.filter { calendar.isDate($0.date, inSameDayAs: date) }
            return SunEntry(
                date: date,
                phase: schedule.phase(at: date, in: all),
                previous: prev,
                next: next,
                todayEvents: today,
                hasLocation: true
            )
        }

        var entries = [entry(at: now)]
        for event in all where event.date > now {
            if entries.count >= maxCount { break }
            // Tiny offset so "previous" resolves to this event, not the one before it.
            entries.append(entry(at: event.date.addingTimeInterval(1)))
        }
        return entries
    }
}

// MARK: - Views

struct SunComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SunEntry

    var body: some View {
        switch family {
        case .accessoryCorner:
            CornerView(entry: entry)
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        default:
            CircularView(entry: entry)
        }
    }
}

private extension SunEntry {
    var nextTimeText: Text {
        guard let next else { return Text("--:--") }
        return Text(next.date, style: .time)
    }

    var nextSymbol: String {
        guard hasLocation else { return "location.slash" }
        return next?.kind.symbolName ?? "sun.max.fill"
    }

    var nextColor: Color {
        next?.kind.color ?? phase.color
    }
}

/// Corner: icon in the middle, next event time curved along the edge.
struct CornerView: View {
    let entry: SunEntry

    var body: some View {
        Image(systemName: entry.nextSymbol)
            .font(.title2)
            .foregroundStyle(entry.nextColor)
            .widgetLabel {
                if entry.hasLocation, let next = entry.next {
                    Text("\(next.kind.shortTitle) \(next.date, style: .time)")
                } else {
                    Text("No location")
                }
            }
            .widgetAccentable()
            .containerBackground(for: .widget) { Color.clear }
    }
}

/// Circular: icon on top, next event time below.
struct CircularView: View {
    let entry: SunEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.nextSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(entry.nextColor)
                entry.nextTimeText
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// Inline: "Sunset 19:12 · Blue 19:40"
struct InlineView: View {
    let entry: SunEntry

    var body: some View {
        if entry.hasLocation, let next = entry.next {
            let following = entry.todayEvents.first { $0.date > next.date }
            if let following {
                Text("\(Image(systemName: next.kind.symbolName)) \(next.kind.shortTitle) \(next.date, style: .time) · \(following.kind.shortTitle) \(following.date, style: .time)")
            } else {
                Text("\(Image(systemName: next.kind.symbolName)) \(next.kind.shortTitle) \(next.date, style: .time)")
            }
        } else {
            Text("\(Image(systemName: "location.slash")) Open SunTimes")
        }
    }
}

/// Rectangular: the next three events.
struct RectangularView: View {
    let entry: SunEntry

    private var upcoming: [SunEvent] {
        guard let next = entry.next else { return [] }
        let later = entry.todayEvents.filter { $0.date > next.date }
        return Array(([next] + later).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !entry.hasLocation {
                Label("No location", systemImage: "location.slash")
                    .font(.headline)
                Text("Open SunTimes to allow location access.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if upcoming.isEmpty {
                Label(entry.phase.title, systemImage: "moon.stars.fill")
                    .font(.headline)
                Text("No more events today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming) { event in
                    HStack(spacing: 4) {
                        Image(systemName: event.kind.symbolName)
                            .foregroundStyle(event.kind.color)
                            .frame(width: 16)
                        Text(event.kind.title)
                        Spacer(minLength: 2)
                        Text(event.date, style: .time)
                            .monospacedDigit()
                    }
                    .font(.system(.footnote, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget definition

struct SunTimesWidget: Widget {
    let kind = "SunTimesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SunTimelineProvider()) { entry in
            SunComplicationView(entry: entry)
        }
        .configurationDisplayName("Sun Times")
        .description("Next sunrise, sunset, golden hour or blue hour.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Previews

#Preview("Corner", as: .accessoryCorner) {
    SunTimesWidget()
} timeline: {
    SunEntry.placeholder
}

#Preview("Circular", as: .accessoryCircular) {
    SunTimesWidget()
} timeline: {
    SunEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    SunTimesWidget()
} timeline: {
    SunEntry.placeholder
}
