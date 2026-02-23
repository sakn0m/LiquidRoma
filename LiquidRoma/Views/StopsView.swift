import SwiftUI
import SwiftData
import CoreLocation
import MapKit

/// Displays a proximity-sorted list of nearby transit stops with lazy loading.
///
/// Shows stop name, palina code, and approximate distance from the user.
/// Implements infinite scroll pagination: the first 20 stops are loaded
/// initially, then subsequent batches of 20 are appended as the user
/// scrolls to the bottom. Supports pull-to-refresh and long-press to
/// toggle favorites.
struct StopsView: View {

    // MARK: - Environment & State

    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(FavoritesService.self) private var favoritesService

    @State private var viewModel = StopsViewModel()

    /// The stop selected for a detail sheet.
    @State private var selectedStop: Stop?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.nearbyStops.enumerated()), id: \.element.stopId) { index, stop in
                        stopRow(stop: stop)
                            .onAppear {
                                if index == viewModel.nearbyStops.count - 1 {
                                    viewModel.loadMoreStops(
                                        modelContext: modelContext,
                                        location: locationService.currentLocation
                                    )
                                }
                            }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.vertical, 20)
                    }
                }
            }
            .refreshable {
                viewModel.loadInitialStops(
                    modelContext: modelContext,
                    location: locationService.currentLocation
                )
            }
            .navigationTitle("Fermate")
            .task {
                if viewModel.nearbyStops.isEmpty {
                    viewModel.loadInitialStops(
                        modelContext: modelContext,
                        location: locationService.currentLocation
                    )
                }
            }
            .onChange(of: locationService.currentLocation) {
                // Re-sort by distance when location first becomes available.
                if viewModel.nearbyStops.isEmpty || !viewModel.hasSortedByDistance {
                    viewModel.loadInitialStops(
                        modelContext: modelContext,
                        location: locationService.currentLocation
                    )
                }
            }
            .sheet(item: $selectedStop) { stop in
                StopDetailSheet(stop: stop)
            }
        }
    }

    // MARK: - Stop Row

    private func stopRow(stop: Stop) -> some View {
        let favoriteItem = FavoriteItem.stop(stopId: stop.stopId, name: stop.stopName)
        let isFavorite = favoritesService.isFavorite(favoriteItem)

        return Button {
            selectedStop = stop
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.atacRed)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.stopName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text("Palina \(stop.stopCode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let distance = formattedDistance(to: stop) {
                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text(distance)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                withAnimation {
                    favoritesService.toggle(favoriteItem)
                }
            } label: {
                if isFavorite {
                    Label("Rimuovi dai preferiti", systemImage: "heart.slash")
                } else {
                    Label("Aggiungi ai preferiti", systemImage: "heart")
                }
            }
        }
    }

    // MARK: - Distance Formatting

    private func formattedDistance(to stop: Stop) -> String? {
        guard let userLocation = locationService.currentLocation else { return nil }

        let stopLocation = CLLocation(latitude: stop.stopLat, longitude: stop.stopLon)
        let meters = userLocation.distance(from: stopLocation)

        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            let km = meters / 1000.0
            return String(format: "%.1f km", km)
        }
    }
}

// MARK: - Stop Detail Sheet (Shared)

/// A detail sheet showing real-time arrival information for a selected stop.
/// Used from StopsView, HomeView, and SearchView.
struct StopDetailSheet: View {

    let stop: Stop

    @Environment(\.dismiss) private var dismiss
    @Environment(GTFSRealtimeService.self) private var realtimeService
    @Environment(FavoritesService.self) private var favoritesService

    @State private var arrivals: [(routeId: String, tripId: String, minutes: Int?)] = []

    private var favoriteItem: FavoriteItem {
        .stop(stopId: stop.stopId, name: stop.stopName)
    }

    var body: some View {
        NavigationStack {
            List {
                // Stop info header
                Section {
                    VStack(spacing: 4) {
                        Text(stop.stopName)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Palina \(stop.stopCode)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                // Arrivals
                if arrivals.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nessun arrivo",
                            systemImage: "bus",
                            description: Text("Nessun bus in tempo reale per questa fermata")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Arrivi in tempo reale") {
                        ForEach(arrivals, id: \.tripId) { arrival in
                            NavigationLink(value: arrival.routeId) {
                                arrivalRow(arrival: arrival)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dettaglio Fermata")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { routeId in
                LineDetailView(routeId: routeId)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { favoritesService.toggle(favoriteItem) }
                    } label: {
                        Image(systemName: favoritesService.isFavorite(favoriteItem) ? "heart.fill" : "heart")
                            .foregroundStyle(.red)
                    }
                }
            }
            .task {
                loadArrivals()
            }
        }
    }

    // MARK: - Arrival Row

    private func arrivalRow(arrival: (routeId: String, tripId: String, minutes: Int?)) -> some View {
        HStack {
            Text(arrival.routeId)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(minWidth: 44)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.atacRed, in: Capsule())

            Spacer()

            if let minutes = arrival.minutes {
                // Real-time: green with live indicator
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.green)

                    if minutes <= 0 {
                        Text("In arrivo")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .fontWeight(.semibold)
                    } else {
                        Text("\(minutes) min")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .fontWeight(.semibold)
                    }
                }
            } else {
                // No real-time data
                Text("--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Load Arrivals

    private func loadArrivals() {
        let tripUpdates = realtimeService.tripUpdatesForStop(stopId: stop.stopId)
        let now = Date().timeIntervalSince1970
        var result: [(routeId: String, tripId: String, minutes: Int?)] = []

        for update in tripUpdates {
            guard let stu = update.stopTimeUpdates.first(where: { $0.stopId == stop.stopId }) else { continue }
            if stu.scheduleRelationship == .skipped { continue }
            let minutes: Int? = stu.arrivalTime.map { Int(($0 - now) / 60.0) }
            result.append((routeId: update.routeId, tripId: update.tripId, minutes: minutes))
        }

        arrivals = result.sorted { a, b in
            switch (a.minutes, b.minutes) {
            case let (am?, bm?): return am < bm
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }
}

// MARK: - Stop Identifiable Conformance

extension Stop: Identifiable {
    public var id: String { stopId }
}

// MARK: - Preview

#Preview {
    StopsView()
}
