import Foundation
import SwiftUI

// MARK: - ArrivalInfo

/// Represents the next arrival status for a favorited stop or line.
enum ArrivalInfo: Sendable, Equatable {
    /// Real-time data available: arrival in N minutes.
    case realtime(minutes: Int)
    /// No RT data; showing the next scheduled departure time string (e.g. "14:35").
    case scheduled(time: String)
    /// No data available at all.
    case unavailable

    var displayText: String {
        switch self {
        case .realtime(let minutes):
            return minutes <= 0 ? "In arrivo" : "\(minutes) min"
        case .scheduled(let time):
            return time
        case .unavailable:
            return "--"
        }
    }
}

// MARK: - HomeViewModel

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - Published State

    /// Arrival info keyed by FavoriteItem.id.
    var favoriteArrivals: [String: ArrivalInfo] = [:]

    // MARK: - Favorite Arrivals

    /// Refreshes arrival info for every favorite item using only real-time data.
    func refreshFavoriteArrivals(
        favorites: [FavoriteItem],
        realtimeService: GTFSRealtimeService
    ) {
        Task {
            var newArrivals: [String: ArrivalInfo] = [:]

            for favorite in favorites {
                switch favorite {
                case .stop(let stopId, _):
                    let info = realtimeArrivalInfo(
                        forStopId: stopId,
                        realtimeService: realtimeService
                    )
                    newArrivals[favorite.id] = info

                case .line(let routeId, _):
                    let info = realtimeArrivalInfoForLine(
                        routeId: routeId,
                        realtimeService: realtimeService
                    )
                    newArrivals[favorite.id] = info
                }
            }

            self.favoriteArrivals = newArrivals
        }
    }

    // MARK: - Private Helpers

    /// Returns the arrival info for a specific stop using only real-time trip updates.
    private func realtimeArrivalInfo(
        forStopId stopId: String,
        realtimeService: GTFSRealtimeService
    ) -> ArrivalInfo {
        let tripUpdates = realtimeService.tripUpdatesForStop(stopId: stopId)

        guard !tripUpdates.isEmpty else { return .unavailable }

        var bestMinutes: Int?

        for update in tripUpdates {
            for stu in update.stopTimeUpdates where stu.stopId == stopId {
                if stu.scheduleRelationship == .skipped { continue }

                if let arrivalTime = stu.arrivalTime, arrivalTime > 0 {
                    let minutes = Int((arrivalTime - Date.now.timeIntervalSince1970) / 60.0)
                    if minutes >= 0, bestMinutes == nil || minutes < bestMinutes! {
                        bestMinutes = minutes
                    }
                }
            }
        }

        if let minutes = bestMinutes {
            return .realtime(minutes: max(minutes, 0))
        }

        return .unavailable
    }

    /// For a favorite line, checks real-time trip updates for any stop on the route.
    private func realtimeArrivalInfoForLine(
        routeId: String,
        realtimeService: GTFSRealtimeService
    ) -> ArrivalInfo {
        let routeUpdates = realtimeService.tripUpdates.filter { $0.routeId == routeId }

        guard !routeUpdates.isEmpty else { return .unavailable }

        var bestMinutes: Int?

        for update in routeUpdates {
            for stu in update.stopTimeUpdates {
                if stu.scheduleRelationship == .skipped { continue }
                if let arrivalTime = stu.arrivalTime, arrivalTime > 0 {
                    let minutes = Int((arrivalTime - Date.now.timeIntervalSince1970) / 60.0)
                    if minutes >= 0, bestMinutes == nil || minutes < bestMinutes! {
                        bestMinutes = minutes
                    }
                }
            }
        }

        if let minutes = bestMinutes {
            return .realtime(minutes: max(minutes, 0))
        }

        return .unavailable
    }
}
