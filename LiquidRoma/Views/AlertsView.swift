import SwiftUI
import SwiftData

/// Displays up to 20 nearby service alerts, sorted by proximity.
///
/// Each alert card has a colored left border indicating severity,
/// expandable content for the full description, and an optional
/// link button if the alert includes a URL.
struct AlertsView: View {

    // MARK: - Environment & State

    @Environment(LocationService.self) private var locationService
    @Environment(GTFSRealtimeService.self) private var realtimeService

    @Query private var stops: [Stop]

    @State private var viewModel = AlertsViewModel()

    /// Tracks which alert IDs are currently expanded.
    @State private var expandedAlerts: Set<String> = []

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.nearbyAlerts.isEmpty {
                emptyStateView
            } else {
                alertsList
            }
        }
        .navigationTitle("Avvisi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.loadAlerts(
                realtimeService: realtimeService,
                location: locationService.currentLocation,
                stops: stops
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Nessun avviso")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Non ci sono avvisi di servizio nelle vicinanze.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Alerts List

    private var alertsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.nearbyAlerts) { alert in
                    alertCard(alert: alert)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Alert Card

    /// An expandable card with a colored severity border on the left side.
    private func alertCard(alert: ServiceAlert) -> some View {
        let isExpanded = expandedAlerts.contains(alert.alertId)

        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                if isExpanded {
                    expandedAlerts.remove(alert.alertId)
                } else {
                    expandedAlerts.insert(alert.alertId)
                }
            }
        } label: {
            HStack(spacing: 0) {
                // Colored severity border on the left edge.
                RoundedRectangle(cornerRadius: 2)
                    .fill(severityColor(for: alert.effect))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 8) {
                    // Header row with severity icon and title.
                    HStack(spacing: 8) {
                        Image(systemName: severityIcon(for: alert.effect))
                            .font(.subheadline)
                            .foregroundStyle(severityColor(for: alert.effect))

                        Text(alert.headerText)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isExpanded ? nil : 2)

                        Spacer(minLength: 4)

                        // Expand/collapse chevron.
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Effect label badge.
                    Text(effectLabel(for: alert.effect))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(severityColor(for: alert.effect))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(severityColor(for: alert.effect).opacity(0.12))
                        )

                    // Expanded content: full description and optional link.
                    if isExpanded {
                        if !alert.descriptionText.isEmpty {
                            Text(alert.descriptionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(.top, 4)
                        }

                        // External URL link button, if the alert provides one.
                        if let urlString = alert.url, let url = URL(string: urlString) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("Maggiori informazioni")
                                }
                                .font(.caption)
                                .foregroundStyle(.blue)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Severity Helpers

    /// Maps alert effect severity to a color for the left border and icon.
    private func severityColor(for effect: AlertEffect) -> Color {
        switch effect {
        case .noService:
            return .red
        case .detour, .stopMoved:
            return .orange
        case .significantDelays:
            return .yellow
        case .reducedService:
            return .orange
        default:
            return .blue
        }
    }

    /// Returns an SF Symbol icon based on the alert severity.
    private func severityIcon(for effect: AlertEffect) -> String {
        switch effect {
        case .noService:
            return "xmark.octagon.fill"
        case .detour, .stopMoved:
            return "arrow.triangle.turn.up.right.diamond.fill"
        case .significantDelays:
            return "clock.badge.exclamationmark"
        case .reducedService:
            return "exclamationmark.triangle.fill"
        default:
            return "info.circle.fill"
        }
    }

    /// Returns the Italian label for each alert effect type.
    private func effectLabel(for effect: AlertEffect) -> String {
        switch effect {
        case .noService: return "Servizio soppresso"
        case .reducedService: return "Servizio ridotto"
        case .significantDelays: return "Ritardi significativi"
        case .detour: return "Deviazione"
        case .additionalService: return "Servizio aggiuntivo"
        case .modifiedService: return "Servizio modificato"
        case .stopMoved: return "Fermata spostata"
        case .otherEffect: return "Avviso"
        case .unknownEffect: return "Avviso"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AlertsView()
    }
}
