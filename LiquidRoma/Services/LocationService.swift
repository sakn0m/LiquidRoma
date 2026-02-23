import Foundation
import CoreLocation

// MARK: - LocationService

/// An observable wrapper around CLLocationManager that provides the user's current location,
/// authorization status, and convenience methods for distance calculations and nearest-stop lookups.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: - Published Properties

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus

    // MARK: - Private

    private let locationManager: CLLocationManager

    // MARK: - Initialization

    override init() {
        locationManager = CLLocationManager()
        authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 25 // Update when user moves at least 25 meters.
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Public API

    /// Requests "when in use" location authorization from the user.
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Starts receiving location updates.
    func startUpdating() {
        guard authorizationStatus == .authorizedWhenInUse ||
              authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }

    /// Stops receiving location updates.
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - Haversine Distance

    /// Computes the Haversine great-circle distance between two geographic coordinates.
    ///
    /// - Parameters:
    ///   - lat1: Latitude of the first point in degrees.
    ///   - lon1: Longitude of the first point in degrees.
    ///   - lat2: Latitude of the second point in degrees.
    ///   - lon2: Longitude of the second point in degrees.
    /// - Returns: Distance in meters.
    static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0 // Earth's mean radius in meters.

        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0

        let radLat1 = lat1 * .pi / 180.0
        let radLat2 = lat2 * .pi / 180.0

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(radLat1) * cos(radLat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadius * c
    }

    // MARK: - Nearest Stop

    /// Finds the nearest stop to the user's current location from an array of stops.
    ///
    /// - Parameter stops: An array of `Stop` model objects to search.
    /// - Returns: The `stopId` of the nearest stop, or `nil` if no location is available or stops is empty.
    func nearestStopId(from stops: [Stop]) -> String? {
        guard let location = currentLocation else { return nil }
        guard !stops.isEmpty else { return nil }

        let userLat = location.coordinate.latitude
        let userLon = location.coordinate.longitude

        var nearestId: String?
        var nearestDistance = Double.infinity

        for stop in stops {
            let distance = Self.haversineDistance(
                lat1: userLat, lon1: userLon,
                lat2: stop.stopLat, lon2: stop.stopLon
            )
            if distance < nearestDistance {
                nearestDistance = distance
                nearestId = stop.stopId
            }
        }

        return nearestId
    }

    /// Computes the distance in meters from the user's current location to a given coordinate.
    ///
    /// - Parameters:
    ///   - latitude: Target latitude in degrees.
    ///   - longitude: Target longitude in degrees.
    /// - Returns: Distance in meters, or `nil` if the user's location is not available.
    func distanceTo(latitude: Double, longitude: Double) -> Double? {
        guard let location = currentLocation else { return nil }
        return Self.haversineDistance(
            lat1: location.coordinate.latitude,
            lon1: location.coordinate.longitude,
            lat2: latitude,
            lon2: longitude
        )
    }

    /// Returns a human-readable distance string (e.g., "350 m" or "2.1 km").
    static func formattedDistance(meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            let km = meters / 1000.0
            return String(format: "%.1f km", km)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        // Only accept locations that are reasonably recent and accurate.
        let age = -latest.timestamp.timeIntervalSinceNow
        guard age < 60, latest.horizontalAccuracy >= 0, latest.horizontalAccuracy < 100 else { return }
        currentLocation = latest
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location failures are non-fatal. The service retains the last known location.
        // In a production app, you might log this for diagnostics.
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                // User denied location access. Update the status.
                authorizationStatus = .denied
            case .locationUnknown:
                // Temporary inability to determine location. Will retry automatically.
                break
            default:
                break
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            currentLocation = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
