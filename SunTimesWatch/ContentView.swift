import SwiftUI
import CoreLocation
import WidgetKit

@MainActor
final class SunModel: ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var locationDate: Date?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var events: [SunEvent] = []
    @Published var phase: SunPhase = .day
    /// The event that most recently happened, shown as "… ago".
    @Published var previousEvent: SunEvent?
    /// The event coming up next, shown as "in …".
    @Published var nextEvent: SunEvent?
    /// The instant the values above describe; views compare against this, not `Date()`,
    /// so everything on screen stays consistent with one snapshot.
    @Published var referenceDate: Date = Date()
    @Published var isLoading = false

    private let fetcher = OneShotLocationFetcher()
    /// Fires when the next event is due so the snapshot rolls over while the app is open.
    private var rolloverTask: Task<Void, Never>?

    init() {
        authorization = fetcher.authorizationStatus
        if let stored = LocationStore.load() {
            coordinate = stored.coordinate
            locationDate = stored.date
        }
        recompute()
    }

    func requestPermissionIfNeeded() {
        if fetcher.authorizationStatus == .notDetermined {
            fetcher.requestWhenInUseAuthorization()
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        authorization = fetcher.authorizationStatus
        if let fresh = await fetcher.fetch(timeout: 10) {
            coordinate = fresh
            locationDate = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            authorization = fetcher.authorizationStatus
        }
        // Recompute either way: without a fix we still want the cached location's
        // times brought up to the current instant.
        recompute()
    }

    func recompute(at now: Date = Date()) {
        referenceDate = now
        guard let coordinate else { return }
        let schedule = SunEventSchedule(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let all = schedule.events(around: now, daysAhead: 1)
        let calendar = Calendar.current
        events = all.filter { calendar.isDate($0.date, inSameDayAs: now) }
        phase = schedule.phase(at: now, in: all)
        // Taken from the full range, so the previous event can be yesterday's
        // and the next one tomorrow's.
        let surrounding = schedule.surroundingEvents(at: now, in: all)
        previousEvent = surrounding.previous
        nextEvent = surrounding.next
        scheduleRollover(to: surrounding.next?.date)
    }

    /// Recomputes just after `date` so a passed event moves from "next" to "previous"
    /// while the app is on screen.
    private func scheduleRollover(to date: Date?) {
        rolloverTask?.cancel()
        rolloverTask = nil
        guard let date else { return }
        let delay = date.timeIntervalSinceNow + 1
        guard delay > 0 else { return }
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.recompute()
        }
    }
}

struct ContentView: View {
    @StateObject private var model = SunModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if model.coordinate == nil {
                    noLocationSection
                } else {
                    headerSection
                    eventsSection
                    footerSection
                }
            }
            .navigationTitle("Sun Times")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "location.fill")
                        }
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .task {
            model.requestPermissionIfNeeded()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the complication or the wrist-down state: the snapshot
            // may be minutes or hours old, so rebuild it before anything is drawn.
            if phase == .active { model.recompute() }
        }
    }

    private var noLocationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Location needed", systemImage: "location.slash")
                    .font(.headline)
                Text(model.authorization == .denied
                     ? "Location access is denied. Enable it in Settings > Privacy > Location Services > SunTimes."
                     : "Allow location access so sunrise, sunset, golden and blue hour can be calculated.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if model.authorization != .denied {
                    Button("Get Location") {
                        model.requestPermissionIfNeeded()
                        Task { await model.refresh() }
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        Section("Now") {
            HStack {
                Circle().fill(model.phase.color).frame(width: 10, height: 10)
                Text(model.phase.title)
                    .font(.caption)
                Spacer()
            }
            if let previous = model.previousEvent {
                eventRow(previous, isPast: true)
            }
            if let next = model.nextEvent {
                eventRow(next, isPast: false)
            } else {
                Text("No more events today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One "what just happened / what happens next" row. `isPast` picks the wording,
    /// so a passed event reads "10 min ago" instead of counting up as "in 10 min".
    private func eventRow(_ event: SunEvent, isPast: Bool) -> some View {
        HStack(alignment: .center) {
            Image(systemName: event.kind.symbolName)
                .foregroundStyle(event.kind.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.kind.title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if isPast {
                        Text("\(event.date, style: .relative) ago")
                    } else {
                        Text("in \(event.date, style: .relative)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(event.date, style: .time)
                .monospacedDigit()
                .font(.caption)
        }
        .opacity(isPast ? 0.6 : 1)
    }

    private var eventsSection: some View {
        Section("Today") {
            if model.events.isEmpty {
                Text("Sun doesn't cross these thresholds today (polar day/night).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.events) { event in
                HStack {
                    Image(systemName: event.kind.symbolName)
                        .foregroundStyle(event.kind.color)
                        .frame(width: 20)
                    Text(event.kind.title)
                        .font(.caption)
                    Spacer()
                    Text(event.date, style: .time)
                        .monospacedDigit()
                        .font(.caption)
                }
                .opacity(event.date < model.referenceDate ? 0.5 : 1)
            }
        }
    }

    private var footerSection: some View {
        Section {
            if let c = model.coordinate {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.3f°, %.3f°", c.latitude, c.longitude))
                    if let d = model.locationDate {
                        Text("Updated \(d, style: .relative) ago")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Text("Add the SunTimes complication to a watch face to see the next event at a glance.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
