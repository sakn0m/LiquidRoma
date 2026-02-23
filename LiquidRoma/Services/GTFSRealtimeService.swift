import Foundation
import SwiftProtobuf
import CoreLocation

// MARK: - GTFSRealtimeService

/// An observable service that periodically fetches GTFS-Realtime protobuf feeds
/// for Rome's public transit system, providing live vehicle positions, trip updates,
/// and service alerts.
@Observable
@MainActor
final class GTFSRealtimeService {

    // MARK: - Published Properties

    var vehiclePositions: [VehiclePosition] = []
    var tripUpdates: [TripUpdate] = []
    var serviceAlerts: [ServiceAlert] = []
    var lastUpdate: Date?
    var isLoading: Bool = false
    var lastError: String?

    // MARK: - Feed URLs

    private static let tripUpdatesURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_trip_updates_feed.pb")!
    private static let vehiclePositionsURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_vehicle_positions_feed.pb")!
    private static let serviceAlertsURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_service_alerts_feed.pb")!

    // MARK: - Timer

    nonisolated(unsafe) private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 30.0

    // MARK: - Lifecycle

    deinit {
        pollingTimer?.invalidate()
    }

    // MARK: - Polling Control

    /// Starts periodic fetching of all GTFS-RT feeds every 30 seconds.
    /// Performs an immediate fetch, then schedules the timer.
    func startPolling() {
        stopPolling()

        Task {
            await fetchAllFeeds()
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchAllFeeds()
            }
        }
    }

    /// Stops the periodic fetching timer.
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Fetch All Feeds

    /// Fetches all three GTFS-RT feeds concurrently. Errors in one feed do not
    /// prevent the others from updating. On failure, the previous data is retained.
    func fetchAllFeeds() async {
        isLoading = true
        lastError = nil

        // Run all three fetches concurrently.
        async let vehicleResult = fetchVehiclePositions()
        async let tripResult = fetchTripUpdates()
        async let alertResult = fetchServiceAlerts()

        let (vehicles, trips, alerts) = await (vehicleResult, tripResult, alertResult)

        if let vehicles {
            self.vehiclePositions = vehicles
        }
        if let trips {
            self.tripUpdates = trips
        }
        if let alerts {
            self.serviceAlerts = alerts
        }

        self.lastUpdate = Date()
        self.isLoading = false
    }

    // MARK: - Individual Feed Fetchers

    /// Fetches and parses the vehicle positions feed. Returns nil on failure.
    private func fetchVehiclePositions() async -> [VehiclePosition]? {
        do {
            let data = try await fetchData(from: Self.vehiclePositionsURL)
            return try await parseVehiclePositions(data: data)
        } catch {
            await setError("Vehicle positions: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches and parses the trip updates feed. Returns nil on failure.
    private func fetchTripUpdates() async -> [TripUpdate]? {
        do {
            let data = try await fetchData(from: Self.tripUpdatesURL)
            return try await parseTripUpdates(data: data)
        } catch {
            await setError("Trip updates: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches and parses the service alerts feed. Returns nil on failure.
    private func fetchServiceAlerts() async -> [ServiceAlert]? {
        do {
            let data = try await fetchData(from: Self.serviceAlertsURL)
            return try await parseServiceAlerts(data: data)
        } catch {
            await setError("Service alerts: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches raw data from a URL.
    private nonisolated func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw RealtimeError.httpError(statusCode: httpResponse.statusCode)
        }
        return data
    }

    /// Thread-safe error accumulation.
    private func setError(_ message: String) async {
        if let existing = lastError {
            lastError = existing + "; " + message
        } else {
            lastError = message
        }
    }

    // MARK: - Protobuf Parsing (off main thread)

    /// Parses vehicle positions from protobuf data on a background thread.
    private nonisolated func parseVehiclePositions(data: Data) async throws -> [VehiclePosition] {
        let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: Array(data))
        var positions: [VehiclePosition] = []
        positions.reserveCapacity(feedMessage.entity.count)

        for entity in feedMessage.entity {
            guard entity.hasVehicle else { continue }
            let vehicle = entity.vehicle

            guard vehicle.hasPosition else { continue }
            let position = vehicle.position

            let vehicleId: String
            if vehicle.hasVehicle {
                vehicleId = vehicle.vehicle.id.isEmpty ? entity.id : vehicle.vehicle.id
            } else {
                vehicleId = entity.id
            }

            let tripId = vehicle.hasTrip ? vehicle.trip.tripID : ""
            let routeId = vehicle.hasTrip ? vehicle.trip.routeID : ""

            let occupancy: OccupancyLevel?
            if vehicle.hasOccupancyStatus {
                occupancy = OccupancyLevel.from(protobufValue: Int(vehicle.occupancyStatus.rawValue))
            } else {
                occupancy = nil
            }

            let bearing: Float? = position.hasBearing ? position.bearing : nil

            positions.append(VehiclePosition(
                vehicleId: vehicleId,
                tripId: tripId,
                routeId: routeId,
                latitude: Double(position.latitude),
                longitude: Double(position.longitude),
                timestamp: TimeInterval(vehicle.timestamp),
                occupancy: occupancy,
                bearing: bearing
            ))
        }

        return positions
    }

    /// Parses trip updates from protobuf data on a background thread.
    private nonisolated func parseTripUpdates(data: Data) async throws -> [TripUpdate] {
        let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: Array(data))
        var updates: [TripUpdate] = []
        updates.reserveCapacity(feedMessage.entity.count)

        for entity in feedMessage.entity {
            guard entity.hasTripUpdate else { continue }
            let tripUpdate = entity.tripUpdate

            let tripId = tripUpdate.hasTrip ? tripUpdate.trip.tripID : ""
            let routeId = tripUpdate.hasTrip ? tripUpdate.trip.routeID : ""

            var stopTimeUpdates: [StopTimeUpdate] = []
            stopTimeUpdates.reserveCapacity(tripUpdate.stopTimeUpdate.count)

            for stu in tripUpdate.stopTimeUpdate {
                let arrivalDelay: Int? = stu.hasArrival && stu.arrival.hasDelay
                    ? Int(stu.arrival.delay) : nil
                let departureDelay: Int? = stu.hasDeparture && stu.departure.hasDelay
                    ? Int(stu.departure.delay) : nil
                let arrivalTime: TimeInterval? = stu.hasArrival && stu.arrival.hasTime
                    ? TimeInterval(stu.arrival.time) : nil
                let departureTime: TimeInterval? = stu.hasDeparture && stu.departure.hasTime
                    ? TimeInterval(stu.departure.time) : nil

                let relationship: ScheduleRelationship
                switch stu.scheduleRelationship {
                case .scheduled:
                    relationship = .scheduled
                case .skipped:
                    relationship = .skipped
                case .noData:
                    relationship = .noData
                default:
                    relationship = .scheduled
                }

                stopTimeUpdates.append(StopTimeUpdate(
                    stopId: stu.stopID,
                    stopSequence: Int(stu.stopSequence),
                    arrivalDelay: arrivalDelay,
                    departureDelay: departureDelay,
                    arrivalTime: arrivalTime,
                    departureTime: departureTime,
                    scheduleRelationship: relationship
                ))
            }

            updates.append(TripUpdate(
                tripId: tripId,
                routeId: routeId,
                stopTimeUpdates: stopTimeUpdates
            ))
        }

        return updates
    }

    /// Parses service alerts from protobuf data on a background thread.
    private nonisolated func parseServiceAlerts(data: Data) async throws -> [ServiceAlert] {
        let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: Array(data))
        var alerts: [ServiceAlert] = []
        alerts.reserveCapacity(feedMessage.entity.count)

        for entity in feedMessage.entity {
            guard entity.hasAlert else { continue }
            let alert = entity.alert

            // Extract header text (prefer Italian "it", then first available, then empty).
            let headerText = extractTranslatedString(alert.headerText)
            let descriptionText = extractTranslatedString(alert.descriptionText)
            let url: String? = alert.hasURL ? extractTranslatedString(alert.url) : nil

            let effect: AlertEffect
            switch alert.effect {
            case .noService:
                effect = .noService
            case .reducedService:
                effect = .reducedService
            case .significantDelays:
                effect = .significantDelays
            case .detour:
                effect = .detour
            case .additionalService:
                effect = .additionalService
            case .modifiedService:
                effect = .modifiedService
            case .stopMoved:
                effect = .stopMoved
            case .otherEffect:
                effect = .otherEffect
            case .unknownEffect:
                effect = .unknownEffect
            default:
                effect = .unknownEffect
            }

            var activePeriods: [ServiceAlert.ActivePeriod] = []
            for period in alert.activePeriod {
                activePeriods.append(ServiceAlert.ActivePeriod(
                    start: TimeInterval(period.start),
                    end: TimeInterval(period.end)
                ))
            }

            var informedEntities: [InformedEntity] = []
            for ie in alert.informedEntity {
                informedEntities.append(InformedEntity(
                    agencyId: ie.agencyID.isEmpty ? nil : ie.agencyID,
                    routeId: ie.routeID.isEmpty ? nil : ie.routeID,
                    stopId: ie.stopID.isEmpty ? nil : ie.stopID
                ))
            }

            alerts.append(ServiceAlert(
                alertId: entity.id,
                headerText: headerText,
                descriptionText: descriptionText,
                url: url,
                effect: effect,
                activePeriods: activePeriods,
                informedEntities: informedEntities
            ))
        }

        return alerts
    }

    /// Extracts text from a GTFS-RT TranslatedString, preferring Italian ("it") locale.
    private nonisolated func extractTranslatedString(_ translatedString: TransitRealtime_TranslatedString) -> String {
        // Prefer Italian translation.
        if let italian = translatedString.translation.first(where: { $0.language == "it" }) {
            return italian.text
        }
        // Fall back to first available translation.
        if let first = translatedString.translation.first {
            return first.text
        }
        return ""
    }

    // MARK: - Helper / Query Methods

    /// Returns all trip updates that contain a stop time update for the given stop ID.
    func tripUpdatesForStop(stopId: String) -> [TripUpdate] {
        tripUpdates.filter { update in
            update.stopTimeUpdates.contains { $0.stopId == stopId }
        }
    }

    /// Returns all vehicle positions for a given route ID.
    func vehiclesForRoute(routeId: String) -> [VehiclePosition] {
        vehiclePositions.filter { $0.routeId == routeId }
    }

    /// Returns service alerts sorted by proximity to a given location.
    /// Alerts are scored by the minimum distance from the given coordinate to any
    /// informed entity's stop. Alerts without stop references are appended at the end.
    func alertsNearLocation(lat: Double, lon: Double, stops: [Stop]) -> [ServiceAlert] {
        // Build a lookup from stopId to (lat, lon) for fast access.
        let stopCoords: [String: (Double, Double)] = Dictionary(
            stops.map { ($0.stopId, ($0.stopLat, $0.stopLon)) },
            uniquingKeysWith: { first, _ in first }
        )

        let scored: [(alert: ServiceAlert, distance: Double)] = serviceAlerts.map { alert in
            var minDistance = Double.infinity

            for entity in alert.informedEntities {
                if let stopId = entity.stopId, let coords = stopCoords[stopId] {
                    let dist = LocationService.haversineDistance(
                        lat1: lat, lon1: lon,
                        lat2: coords.0, lon2: coords.1
                    )
                    minDistance = min(minDistance, dist)
                }
            }

            return (alert, minDistance)
        }

        return scored.sorted { $0.distance < $1.distance }.map(\.alert)
    }
}

// MARK: - RealtimeError

enum RealtimeError: LocalizedError {
    case httpError(statusCode: Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingFailed(let detail):
            return "Protobuf decoding failed: \(detail)"
        }
    }
}
