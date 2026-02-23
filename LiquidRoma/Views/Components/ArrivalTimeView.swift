import SwiftUI

/// A reusable component for displaying arrival time information.
///
/// Renders differently based on the data source:
/// - Real-time: vibrant green text with a pulsing "LIVE" dot indicator.
/// - Scheduled: dimmed gray text with "Stimato ATAC" disclaimer label.
/// - Unavailable: a neutral placeholder dash.
struct ArrivalTimeView: View {

    let arrivalInfo: ArrivalInfo

    // MARK: - Pulsing Animation State

    @State private var isPulsing = false

    // MARK: - Body

    var body: some View {
        switch arrivalInfo {
        case .realtime(let minutes):
            realtimeView(minutes: minutes)
        case .scheduled(let time):
            scheduledView(time: time)
        case .unavailable:
            unavailableView
        }
    }

    // MARK: - Real-Time View

    /// Displays real-time arrival with a pulsing green "LIVE" indicator.
    @ViewBuilder
    private func realtimeView(minutes: Int) -> some View {
        HStack(spacing: 6) {
            // Pulsing live dot — animates continuously to signal active tracking.
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.4 : 0.8)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }

            Text(minutes <= 0 ? "In arrivo" : "\(minutes) min")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.green)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Scheduled View

    /// Displays the static schedule time with a clear "estimated" disclaimer.
    @ViewBuilder
    private func scheduledView(time: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(time)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("Stimato ATAC")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Unavailable View

    /// Neutral placeholder when no arrival data is available.
    private var unavailableView: some View {
        Text("--")
            .font(.headline)
            .foregroundStyle(.quaternary)
    }
}

// MARK: - Preview

#Preview("Real-Time") {
    VStack(spacing: 20) {
        ArrivalTimeView(arrivalInfo: .realtime(minutes: 3))
        ArrivalTimeView(arrivalInfo: .realtime(minutes: 0))
        ArrivalTimeView(arrivalInfo: .scheduled(time: "14:35"))
        ArrivalTimeView(arrivalInfo: .unavailable)
    }
    .padding()
}
