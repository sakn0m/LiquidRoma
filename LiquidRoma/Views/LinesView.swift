import SwiftUI
import SwiftData

/// Displays a searchable, proximity-sorted list of transit lines (routes).
///
/// Lines are ordered by the geographic proximity of their stops to the user.
/// Each row shows the route short name in a colored badge plus the long name.
/// Tapping navigates to LineDetailView. Long press toggles the favorite state.
/// A search bar at the top filters lines by name or number.
struct LinesView: View {

    // MARK: - Environment & State

    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(FavoritesService.self) private var favoritesService

    @Query private var stops: [Stop]

    @State private var viewModel = LinesViewModel()

    // MARK: - Body

    var body: some View {
        List {
            ForEach(viewModel.sortedLines, id: \.routeId) { route in
                NavigationLink(value: route.routeId) {
                    lineRow(route: route)
                }
                .contextMenu {
                    favoriteContextMenu(for: route)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Linee")
        .navigationDestination(for: String.self) { routeId in
            LineDetailView(routeId: routeId)
        }
        .task {
            viewModel.loadLines(
                modelContext: modelContext,
                location: locationService.currentLocation
            )
        }
    }

    // MARK: - Line Row

    /// A single row with a colored route badge and the long name / headsign.
    private func lineRow(route: Route) -> some View {
        HStack(spacing: 12) {
            // Colored badge showing the route short name (e.g. "H", "64", "8").
            routeBadge(route: route)

            VStack(alignment: .leading, spacing: 2) {
                Text(route.routeLongName.isEmpty ? route.routeShortName : route.routeLongName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(routeTypeLabel(route.routeType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Show a heart if this line is favorited.
            if favoritesService.isFavorite(
                FavoriteItem.line(routeId: route.routeId, shortName: route.routeShortName)
            ) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Route Badge

    /// A capsule-shaped badge with the route color and short name.
    private func routeBadge(route: Route) -> some View {
        Text(route.routeShortName)
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(textColor(for: route))
            .frame(minWidth: 44)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(badgeColor(for: route))
            )
    }

    /// Parses the GTFS hex color string into a SwiftUI Color for the badge background.
    private func badgeColor(for route: Route) -> Color {
        guard !route.routeColor.isEmpty else { return .accentColor }
        return Color(hex: route.routeColor) ?? .accentColor
    }

    /// Determines the text color, using routeTextColor if available, else white.
    private func textColor(for route: Route) -> Color {
        guard !route.routeTextColor.isEmpty else { return .white }
        return Color(hex: route.routeTextColor) ?? .white
    }

    /// Returns a human-readable label for the GTFS route_type integer.
    private func routeTypeLabel(_ type: Int) -> String {
        switch type {
        case 0: return "Tram"
        case 1: return "Metro"
        case 2: return "Treno"
        case 3: return "Bus"
        case 4: return "Traghetto"
        case 5: return "Funicolare"
        case 7: return "Funicolare"
        default: return "Trasporto"
        }
    }

    // MARK: - Favorite Context Menu

    /// Long-press menu for adding/removing a line from favorites.
    @ViewBuilder
    private func favoriteContextMenu(for route: Route) -> some View {
        let item = FavoriteItem.line(routeId: route.routeId, shortName: route.routeShortName)
        let isFav = favoritesService.isFavorite(item)

        Button {
            withAnimation {
                favoritesService.toggle(item)
            }
        } label: {
            if isFav {
                Label("Rimuovi dai preferiti", systemImage: "heart.slash")
            } else {
                Label("Aggiungi ai preferiti", systemImage: "heart")
            }
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    /// ATAC brand red (#E3002B).
    static let atacRed = Color(red: 227 / 255.0, green: 0 / 255.0, blue: 43 / 255.0)

    /// Initializes a Color from a hex string (e.g. "FF6600" or "#FF6600").
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgbValue) else { return nil }

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LinesView()
    }
}
