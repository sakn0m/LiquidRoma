import Foundation
import SwiftUI
import SwiftData
import CoreLocation

// MARK: - LinesViewModel

@Observable
@MainActor
final class LinesViewModel {

    // MARK: - Published State

    /// Routes sorted by numeric route name.
    var sortedLines: [Route] = []

    /// Whether a load operation is in progress.
    var isLoading = false

    // MARK: - Load Lines

    /// Loads all routes from SwiftData and sorts them by numeric route name.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData model context.
    ///   - location: The user's current location (reserved for future proximity sorting).
    func loadLines(
        modelContext: ModelContext,
        location: CLLocation?
    ) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }

            // Fetch all routes.
            let descriptor = FetchDescriptor<Route>()
            let allRoutes: [Route]
            do {
                allRoutes = try modelContext.fetch(descriptor)
            } catch {
                allRoutes = []
            }

            guard !allRoutes.isEmpty else {
                sortedLines = []
                return
            }

            // Sort by route type first (metro/tram before bus), then by numeric name.
            sortedLines = allRoutes.sorted { a, b in
                if a.routeType != b.routeType {
                    return a.routeType < b.routeType
                }
                return numericAwareCompare(a.routeShortName, b.routeShortName)
            }
        }
    }

    // MARK: - Private Helpers

    /// Compares two strings with numeric awareness: "3" < "10" < "100" < "A".
    private func numericAwareCompare(_ a: String, _ b: String) -> Bool {
        // If both are purely numeric, compare as integers.
        if let numA = Int(a), let numB = Int(b) {
            return numA < numB
        }
        // If only one is numeric, numbers come first.
        if Int(a) != nil { return true }
        if Int(b) != nil { return false }
        // Both non-numeric: lexicographic comparison.
        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }
}
