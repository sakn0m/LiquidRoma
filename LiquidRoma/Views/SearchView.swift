import SwiftUI
import SwiftData

/// A search sheet that lets the user find stops and lines by name or code.
///
/// Queries SwiftData for both Stop and Route models, presenting results
/// in two sections: "Fermate" (stops) and "Linee" (lines). Tapping a
/// stop shows its arrival detail; tapping a line opens the line detail.
struct SearchView: View {

    // MARK: - Environment & State

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allStops: [Stop]
    @Query private var allRoutes: [Route]

    @State private var searchText = ""
    @State private var selectedStop: Stop?
    @State private var selectedRouteId: String?

    // MARK: - Computed Results

    private var filteredStops: [Stop] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return allStops
            .filter {
                $0.stopName.lowercased().contains(query) ||
                $0.stopCode.lowercased().contains(query)
            }
            .prefix(20)
            .map { $0 }
    }

    private var filteredRoutes: [Route] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return allRoutes
            .filter {
                $0.routeShortName.lowercased().contains(query) ||
                $0.routeLongName.lowercased().contains(query)
            }
            .prefix(20)
            .map { $0 }
    }

    private var hasNoResults: Bool {
        !searchText.isEmpty && filteredStops.isEmpty && filteredRoutes.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    promptView
                } else if hasNoResults {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .navigationTitle("Cerca")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Fermata o linea...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: String.self) { routeId in
                LineDetailView(routeId: routeId)
            }
            .sheet(item: $selectedStop) { stop in
                StopDetailSheet(stop: stop)
            }
        }
    }

    // MARK: - Prompt View

    private var promptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Cerca una fermata o una linea")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Nessun risultato per \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            if !filteredStops.isEmpty {
                Section("Fermate") {
                    ForEach(filteredStops, id: \.stopId) { stop in
                        Button {
                            selectedStop = stop
                        } label: {
                            stopResultRow(stop: stop)
                        }
                    }
                }
            }

            if !filteredRoutes.isEmpty {
                Section("Linee") {
                    ForEach(filteredRoutes, id: \.routeId) { route in
                        NavigationLink(value: route.routeId) {
                            lineResultRow(route: route)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Stop Result Row

    private func stopResultRow(stop: Stop) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.stopName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text("Palina \(stop.stopCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Line Result Row

    private func lineResultRow(route: Route) -> some View {
        HStack(spacing: 12) {
            Text(route.routeShortName)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(routeTextColor(route))
                .frame(minWidth: 36)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(routeBadgeColor(route))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(route.routeLongName.isEmpty ? route.routeShortName : route.routeLongName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(routeTypeLabel(route.routeType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func routeBadgeColor(_ route: Route) -> Color {
        guard !route.routeColor.isEmpty else { return .accentColor }
        return Color(hex: route.routeColor) ?? .accentColor
    }

    private func routeTextColor(_ route: Route) -> Color {
        guard !route.routeTextColor.isEmpty else { return .white }
        return Color(hex: route.routeTextColor) ?? .white
    }

    private func routeTypeLabel(_ type: Int) -> String {
        switch type {
        case 0: return "Tram"
        case 1: return "Metro"
        case 2: return "Treno"
        case 3: return "Bus"
        default: return "Trasporto"
        }
    }
}

// MARK: - Preview

#Preview {
    SearchView()
}
