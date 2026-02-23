import SwiftUI
import SwiftData

/// Liquid Transit Roma — iOS 26 Liquid Glass transit app for Rome
@main
struct LiquidRomaApp: App {

    @State private var locationService = LocationService()
    @State private var realtimeService = GTFSRealtimeService()
    @State private var favoritesService = FavoritesService()
    @State private var isImportingData = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Stop.self,
            Route.self,
            Trip.self,
            StopTime.self,
            Shape.self,
            CalendarDate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(locationService)
                    .environment(realtimeService)
                    .environment(favoritesService)

                // Loading overlay while essential GTFS data is being imported.
                if isImportingData {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Caricamento dati...")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Prima apertura")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(32)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .task {
                // Start location tracking.
                locationService.requestPermission()
                locationService.startUpdating()

                // Import GTFS data (essential tables first).
                await importGTFSDataIfNeeded()

                // Start real-time polling.
                realtimeService.startPolling()
            }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Imports essential GTFS data (routes, stops, trips) using direct bundle file lookups.
    /// Only imports if the database is not already populated.
    /// Heavy tables (stop_times, shapes) are imported in the background afterward.
    private func importGTFSDataIfNeeded() async {
        let dataService = GTFSDataService(modelContainer: sharedModelContainer)

        do {
            // Check if essential data already exists.
            let hasRoutes = try await dataService.hasRoutes()
            if hasRoutes { return }

            // Import essential tables (routes, stops, trips, calendar_dates).
            // These are small and fast (~11MB total).
            isImportingData = true
            try await dataService.importEssentialFromBundle()
            isImportingData = false

            // Import heavy tables in the background (stop_times ~232MB, shapes ~22MB).
            // The app is usable immediately; these enable detailed features.
            Task.detached(priority: .background) {
                do {
                    try await dataService.importHeavyFromBundle()
                    print("[GTFSDataService] Heavy data import completed.")
                } catch {
                    print("[GTFSDataService] Heavy data import failed: \(error)")
                }
            }
        } catch {
            isImportingData = false
            print("[GTFSDataService] Essential import failed: \(error)")
        }
    }
}
