import Foundation
import SwiftUI
import SwiftData
import CoreLocation

// MARK: - StopsViewModel

@Observable
@MainActor
final class StopsViewModel {

    // MARK: - Published State

    /// The paginated list of nearby stops currently displayed.
    var nearbyStops: [Stop] = []

    /// Whether an initial or pagination load is in progress.
    var isLoading = false

    /// Whether the current sort order is by distance (i.e. location was available).
    private(set) var hasSortedByDistance = false

    // MARK: - Pagination

    /// Number of stops per page.
    let pageSize = 20

    /// Current page index (0-based).
    private(set) var currentPage = 0

    /// All stops sorted by distance, cached after the first fetch.
    private var sortedAllStops: [Stop] = []

    /// Whether all pages have been loaded.
    var hasMorePages: Bool {
        let totalLoaded = (currentPage + 1) * pageSize
        return totalLoaded < sortedAllStops.count
    }

    // MARK: - Load Initial Stops

    /// Fetches all stops from SwiftData, sorts them by Haversine distance from the user,
    /// and loads the first page of results.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData model context.
    ///   - location: The user's current location for distance sorting.
    func loadInitialStops(modelContext: ModelContext, location: CLLocation?) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }

            // Fetch all stops from SwiftData.
            let descriptor = FetchDescriptor<Stop>()
            let allStops: [Stop]
            do {
                allStops = try modelContext.fetch(descriptor)
            } catch {
                allStops = []
            }

            // Sort by Haversine distance from the user.
            if let userLocation = location {
                let userLat = userLocation.coordinate.latitude
                let userLon = userLocation.coordinate.longitude

                sortedAllStops = allStops.sorted { a, b in
                    let distA = LocationService.haversineDistance(
                        lat1: userLat, lon1: userLon,
                        lat2: a.stopLat, lon2: a.stopLon
                    )
                    let distB = LocationService.haversineDistance(
                        lat1: userLat, lon1: userLon,
                        lat2: b.stopLat, lon2: b.stopLon
                    )
                    return distA < distB
                }
                hasSortedByDistance = true
            } else {
                // No location available; sort alphabetically by name as fallback.
                sortedAllStops = allStops.sorted { $0.stopName.localizedCaseInsensitiveCompare($1.stopName) == .orderedAscending }
                hasSortedByDistance = false
            }

            // Reset pagination and load first page.
            currentPage = 0
            let endIndex = min(pageSize, sortedAllStops.count)
            nearbyStops = Array(sortedAllStops[0..<endIndex])
        }
    }

    // MARK: - Load More Stops (Pagination)

    /// Loads the next page of stops appended to the existing list.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData model context (unused if cache is valid, kept for API consistency).
    ///   - location: The user's current location (unused if cache is valid).
    func loadMoreStops(modelContext: ModelContext, location: CLLocation?) {
        guard !isLoading, hasMorePages else { return }
        isLoading = true

        Task {
            defer { isLoading = false }

            // If the sorted cache was invalidated, rebuild it.
            if sortedAllStops.isEmpty {
                loadInitialStops(modelContext: modelContext, location: location)
                return
            }

            currentPage += 1
            let startIndex = currentPage * pageSize
            let endIndex = min(startIndex + pageSize, sortedAllStops.count)

            guard startIndex < sortedAllStops.count else { return }

            let nextPage = Array(sortedAllStops[startIndex..<endIndex])
            nearbyStops.append(contentsOf: nextPage)
        }
    }

    // MARK: - Refresh

    /// Clears the cache and reloads from scratch (e.g. when user location changes significantly).
    func refresh(modelContext: ModelContext, location: CLLocation?) {
        sortedAllStops = []
        nearbyStops = []
        currentPage = 0
        loadInitialStops(modelContext: modelContext, location: location)
    }
}
