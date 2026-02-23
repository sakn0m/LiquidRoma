import Foundation
import SwiftUI
import SwiftData
import CoreLocation

// MARK: - AlertsViewModel

@Observable
@MainActor
final class AlertsViewModel {

    // MARK: - Published State

    /// Service alerts sorted by proximity to the user, capped at 20.
    var nearbyAlerts: [ServiceAlert] = []

    /// Whether a load operation is in progress.
    var isLoading = false

    /// Maximum number of alerts to display.
    private let maxAlerts = 20

    // MARK: - Load Alerts

    /// Loads service alerts, sorts them by proximity to the user's location, and caps at 20.
    ///
    /// For each alert, we examine its informed entities to find the closest affected stop
    /// to the user. Alerts are then sorted by that minimum distance.
    ///
    /// - Parameters:
    ///   - realtimeService: The GTFS-RT service providing live service alerts.
    ///   - location: The user's current location.
    ///   - stops: All stops (pre-fetched from SwiftData).
    func loadAlerts(
        realtimeService: GTFSRealtimeService,
        location: CLLocation?,
        stops: [Stop]
    ) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }

            let allAlerts = realtimeService.serviceAlerts

            guard !allAlerts.isEmpty else {
                nearbyAlerts = []
                return
            }

            guard let userLocation = location else {
                // No location: just take the first 20 alerts as-is.
                nearbyAlerts = Array(allAlerts.prefix(maxAlerts))
                return
            }

            let userLat = userLocation.coordinate.latitude
            let userLon = userLocation.coordinate.longitude

            // Build a quick lookup of stops by ID.
            let stopById = Dictionary(uniqueKeysWithValues: stops.map { ($0.stopId, $0) })

            // For each alert, compute the distance to the closest informed stop.
            var alertDistances: [(alert: ServiceAlert, distance: Double)] = []

            for alert in allAlerts {
                var minDistance = Double.greatestFiniteMagnitude

                for entity in alert.informedEntities {
                    // If the entity references a specific stop, compute distance to it.
                    if let stopId = entity.stopId, let stop = stopById[stopId] {
                        let dist = LocationService.haversineDistance(
                            lat1: userLat, lon1: userLon,
                            lat2: stop.stopLat, lon2: stop.stopLon
                        )
                        if dist < minDistance {
                            minDistance = dist
                        }
                    }

                    // If the entity references a route, find the nearest stop on that route.
                    // This is a heavier operation; for performance we check if we already have
                    // a close stop match before scanning routes.
                    if let routeId = entity.routeId, minDistance > 500 {
                        // Find stops that might serve this route. Since we don't have
                        // trip/stop_time data here, we use the RT service's nearby alerts
                        // as a supplementary check. For now, route-only entities get a
                        // large default distance unless we find a direct stop match.
                        let routeVehicles = realtimeService.vehiclesForRoute(routeId: routeId)
                        for vehicle in routeVehicles {
                            let dist = LocationService.haversineDistance(
                                lat1: userLat, lon1: userLon,
                                lat2: vehicle.latitude, lon2: vehicle.longitude
                            )
                            if dist < minDistance {
                                minDistance = dist
                            }
                        }
                    }
                }

                alertDistances.append((alert: alert, distance: minDistance))
            }

            // Sort by distance ascending, cap at maxAlerts.
            alertDistances.sort { $0.distance < $1.distance }

            nearbyAlerts = Array(alertDistances.prefix(maxAlerts).map(\.alert))
        }
    }

    // MARK: - Display Helpers

    /// Returns the display color for a given AlertEffect.
    static func displayColor(for effect: AlertEffect) -> Color {
        switch effect {
        case .noService:
            return .red
        case .reducedService:
            return .orange
        case .significantDelays:
            return .yellow
        case .detour:
            return .orange
        case .additionalService:
            return .green
        case .modifiedService:
            return .blue
        case .stopMoved:
            return .purple
        case .otherEffect:
            return .gray
        case .unknownEffect:
            return .gray
        }
    }

    /// Returns a localized short label for a given AlertEffect.
    static func displayLabel(for effect: AlertEffect) -> String {
        switch effect {
        case .noService:
            return "Sospeso"
        case .reducedService:
            return "Ridotto"
        case .significantDelays:
            return "Ritardi"
        case .detour:
            return "Deviazione"
        case .additionalService:
            return "Servizio Aggiuntivo"
        case .modifiedService:
            return "Modificato"
        case .stopMoved:
            return "Fermata Spostata"
        case .otherEffect:
            return "Altro"
        case .unknownEffect:
            return "Sconosciuto"
        }
    }
}
