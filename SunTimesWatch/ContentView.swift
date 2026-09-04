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
    @Published var isLoading = false

    private let fetcher = OneShotLocationFetcher()

    init() {
        authorization = fetcher.authorizationStatus
        if let stored = LocationStore.load() {
            coordinate = stored.coordinate
            locationDate = stored.date
            recompute()
        }
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
            recompute()
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            authorization = fetcher.authorizationStatus
        }
    }

    func recompute() {
        guard let coordinate else { return }
        let schedule = SunEventSchedule(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let now = Date()
        let all = schedule.events(around: now, daysAhead: 1)
        events = all.filter { Calendar.current.isDateInToday($0.date) }
        phase = schedule.phase(at: now, in: all)
    }

    var nextEvent: SunEvent? {
        events.first { $0.date > Date() }
    }
}

struct ContentView: View {
    @StateObject private var model = SunModel()

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
        Section("Next") {
            HStack {
                Circle().fill(model.phase.color).frame(width: 10, height: 10)
                Text("Now: \(model.phase.title)")
                    .font(.caption)
                Spacer()
            }
            if let next = model.nextEvent {
                HStack(alignment: .center) {
                    Image(systemName: next.kind.symbolName)
                        .foregroundStyle(next.kind.color)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(next.kind.title)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("in \(next.date, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(next.date, style: .time)
                        .monospacedDigit()
                        .font(.caption)
                }
            } else {
                Text("No more events today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                .opacity(event.date < Date() ? 0.5 : 1)
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
