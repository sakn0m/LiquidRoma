import SwiftUI
import SwiftData

/// The home screen showing the user's favourite stops and lines with real-time
/// arrival information. Replaces the previous map-based home view.
struct HomeView: View {

    // MARK: - Environment & State

    @Environment(GTFSRealtimeService.self) private var realtimeService
    @Environment(FavoritesService.self) private var favoritesService

    @Query private var allStops: [Stop]

    @State private var homeViewModel = HomeViewModel()
    @State private var showAlerts = false
    @State private var selectedStop: Stop?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if favoritesService.favorites.isEmpty {
                    emptyState
                } else {
                    favoritesList
                }
            }
            .navigationTitle("Preferiti")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAlerts = true
                    } label: {
                        Image(systemName: "bell.fill")
                    }
                }
            }
            .sheet(isPresented: $showAlerts) {
                NavigationStack {
                    AlertsView()
                }
            }
            .sheet(item: $selectedStop) { stop in
                StopDetailSheet(stop: stop)
            }
            .navigationDestination(for: String.self) { routeId in
                LineDetailView(routeId: routeId)
            }
            .onAppear {
                refreshArrivals()
            }
            .onChange(of: favoritesService.favorites) {
                refreshArrivals()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nessun preferito", systemImage: "heart.slash")
        } description: {
            Text("Aggiungi fermate e linee ai preferiti per vederli qui")
        }
    }

    // MARK: - Favorites List

    private var favoritesList: some View {
        List {
            if !favoritesService.favoriteStops.isEmpty {
                Section("Fermate") {
                    ForEach(favoritesService.favoriteStops) { item in
                        Button {
                            selectedStop = stopForFavorite(item)
                        } label: {
                            favoriteStopRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let stopFavs = favoritesService.favoriteStops
                        for offset in offsets {
                            favoritesService.remove(stopFavs[offset])
                        }
                    }
                }
            }

            if !favoritesService.favoriteLines.isEmpty {
                Section("Linee") {
                    ForEach(favoritesService.favoriteLines) { item in
                        NavigationLink(value: lineRouteId(for: item)) {
                            favoriteLineRow(item: item)
                        }
                    }
                    .onDelete { offsets in
                        let lineFavs = favoritesService.favoriteLines
                        for offset in offsets {
                            favoritesService.remove(lineFavs[offset])
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Favourite Stop Row

    private func favoriteStopRow(item: FavoriteItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.atacRed)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            Spacer()

            ArrivalTimeView(arrivalInfo: homeViewModel.favoriteArrivals[item.id] ?? .unavailable)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Favourite Line Row

    private func favoriteLineRow(item: FavoriteItem) -> some View {
        HStack(spacing: 12) {
            Text(item.displayName)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(minWidth: 44)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.atacRed, in: Capsule())

            Spacer()

            ArrivalTimeView(arrivalInfo: homeViewModel.favoriteArrivals[item.id] ?? .unavailable)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func stopForFavorite(_ item: FavoriteItem) -> Stop? {
        guard case .stop(let stopId, _) = item else { return nil }
        return allStops.first { $0.stopId == stopId }
    }

    private func lineRouteId(for item: FavoriteItem) -> String {
        if case .line(let routeId, _) = item {
            return routeId
        }
        return ""
    }

    private func refreshArrivals() {
        homeViewModel.refreshFavoriteArrivals(
            favorites: favoritesService.favorites,
            realtimeService: realtimeService
        )
    }
}

// MARK: - Preview

#Preview {
    HomeView()
}
