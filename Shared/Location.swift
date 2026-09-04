import Foundation
import CoreLocation

/// Shared persistence of the last known location between the app and the widget.
enum LocationStore {
    static let appGroup = "group.com.marcowarm.SunTimes"
    private static let latKey = "lastLatitude"
    private static let lonKey = "lastLongitude"
    private static let dateKey = "lastLocationDate"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    struct Stored {
        let coordinate: CLLocationCoordinate2D
        let date: Date
    }

    static func load() -> Stored? {
        let d = defaults
        guard d.object(forKey: latKey) != nil, d.object(forKey: lonKey) != nil else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: d.double(forKey: latKey), longitude: d.double(forKey: lonKey))
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let date = (d.object(forKey: dateKey) as? Date) ?? .distantPast
        return Stored(coordinate: coordinate, date: date)
    }

    static func save(_ coordinate: CLLocationCoordinate2D, date: Date = Date()) {
        let d = defaults
        d.set(coordinate.latitude, forKey: latKey)
        d.set(coordinate.longitude, forKey: lonKey)
        d.set(date, forKey: dateKey)
    }
}

/// One-shot async location fetch with a timeout. Works in both the app and the widget
/// (the widget needs `NSWidgetWantsLocation` and the app must already hold when-in-use authorization).
final class OneShotLocationFetcher: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var finished = false

    override init() {
        super.init()
        manager.delegate = self
        // Sun times change negligibly within a few km; coarse accuracy is plenty and saves battery.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Returns a fresh coordinate, or nil on timeout / denial / error.
    func fetch(timeout: TimeInterval = 8) async -> CLLocationCoordinate2D? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            self.continuation = cont
            self.finished = false
            self.manager.requestLocation()

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        guard !finished else { return }
        finished = true
        manager.stopUpdatingLocation()
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        LocationStore.save(loc.coordinate, date: loc.timestamp)
        finish(with: loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}

/// Resolves the best coordinate to use: fresh fix if quickly available, otherwise cached.
enum LocationResolver {
    static func resolve(timeout: TimeInterval = 8) async -> CLLocationCoordinate2D? {
        let fetcher = OneShotLocationFetcher()
        if let fresh = await fetcher.fetch(timeout: timeout) {
            return fresh
        }
        return LocationStore.load()?.coordinate
    }
}
