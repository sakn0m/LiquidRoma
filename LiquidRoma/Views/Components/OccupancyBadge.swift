import SwiftUI

/// A compact badge that visualizes vehicle occupancy level.
///
/// Displays a colored circle indicator alongside the Italian label
/// (Liberi / Pieni / Pienissimi / Non Accessibile).
/// When the occupancy data is nil (sensor unavailable or not reported),
/// the view renders as an EmptyView to avoid misleading the user.
struct OccupancyBadge: View {

    let occupancy: OccupancyLevel?

    var body: some View {
        if let occupancy {
            HStack(spacing: 4) {
                Circle()
                    .fill(occupancy.color)
                    .frame(width: 8, height: 8)

                Text(occupancy.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(occupancy.color)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(occupancy.color.opacity(0.15))
            )
        }
        // When occupancy is nil, render nothing — the data is absent or unreliable.
    }
}

// MARK: - Preview

#Preview("Occupancy Badges") {
    VStack(spacing: 12) {
        OccupancyBadge(occupancy: .free)
        OccupancyBadge(occupancy: .busy)
        OccupancyBadge(occupancy: .packed)
        OccupancyBadge(occupancy: .notAccessible)
        OccupancyBadge(occupancy: nil)
    }
    .padding()
}
