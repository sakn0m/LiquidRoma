import Foundation
import SwiftUI

// MARK: - Occupancy Level

enum OccupancyLevel: String, CaseIterable, Sendable {
    case free = "Liberi"
    case busy = "Pieni"
    case packed = "Pienissimi"
    case notAccessible = "Non Accessibile"

    var color: Color {
        switch self {
        case .free:
            return .green
        case .busy:
            return .orange
        case .packed:
            return .red
        case .notAccessible:
            return .gray
        }
    }

    /// Maps GTFS-RT OccupancyStatus protobuf integer values to OccupancyLevel.
    ///
    /// Protobuf enum values:
    /// - 0: EMPTY
    /// - 1: MANY_SEATS_AVAILABLE
    /// - 2: FEW_SEATS_AVAILABLE
    /// - 3: STANDING_ROOM_ONLY
    /// - 4: CRUSHED_STANDING_ROOM_ONLY
    /// - 5: FULL
    /// - 6: NOT_ACCEPTING_PASSENGERS
    static func from(protobufValue value: Int) -> OccupancyLevel? {
        switch value {
        case 0, 1:
            return .free
        case 2, 3:
            return .busy
        case 4, 5:
            return .packed
        case 6:
            return .notAccessible
        default:
            return nil
        }
    }
}

// MARK: - Vehicle Position

struct VehiclePosition: Identifiable, Sendable {
    let vehicleId: String
    let tripId: String
    let routeId: String
    let latitude: Double
    let longitude: Double
    let timestamp: TimeInterval
    let occupancy: OccupancyLevel?
    let bearing: Float?

    var id: String { vehicleId }
}

// MARK: - Trip Update

struct TripUpdate: Identifiable, Sendable {
    let tripId: String
    let routeId: String
    let stopTimeUpdates: [StopTimeUpdate]

    var id: String { tripId }
}

// MARK: - Schedule Relationship

enum ScheduleRelationship: Int, Sendable {
    case scheduled = 0
    case skipped = 1
    case noData = 2
}

// MARK: - Stop Time Update

struct StopTimeUpdate: Identifiable, Sendable {
    let stopId: String
    let stopSequence: Int
    let arrivalDelay: Int?
    let departureDelay: Int?
    let arrivalTime: TimeInterval?
    let departureTime: TimeInterval?
    let scheduleRelationship: ScheduleRelationship

    var id: String { "\(stopId)_\(stopSequence)" }
}

// MARK: - Alert Effect

enum AlertEffect: Int, Sendable {
    case noService = 1
    case reducedService = 2
    case significantDelays = 3
    case detour = 4
    case additionalService = 5
    case modifiedService = 6
    case stopMoved = 7
    case otherEffect = 8
    case unknownEffect = 9
}

// MARK: - Informed Entity

struct InformedEntity: Sendable, Hashable {
    let agencyId: String?
    let routeId: String?
    let stopId: String?
}

// MARK: - Service Alert

struct ServiceAlert: Identifiable, Sendable {
    let alertId: String
    let headerText: String
    let descriptionText: String
    let url: String?
    let effect: AlertEffect
    let activePeriods: [ActivePeriod]
    let informedEntities: [InformedEntity]

    var id: String { alertId }

    struct ActivePeriod: Sendable {
        let start: TimeInterval
        let end: TimeInterval
    }
}
