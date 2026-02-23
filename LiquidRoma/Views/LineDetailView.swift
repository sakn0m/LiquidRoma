import SwiftUI
import SwiftData
import MapKit

/// Displays the detailed view for a specific transit line.
///
/// Features a full map with the route polyline, sequential stop pins,
/// and animated real-time vehicle markers with occupancy badges.
/// A Liquid Glass segmented control toggles between the two directions
/// (Andata / Ritorno). Below the map, a scrollable list shows the
/// ordered stops with arrival time information.
///
/// Easter egg: if the line is route "495" (ATAC's famous articulated bus),
/// a secret snake emoji button appears that launches the SnakeBus game.
struct LineDetailView: View {

    // MARK: - Properties

    let routeId: String

    // MARK: - Environment & State

    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(GTFSRealtimeService.self) private var realtimeService
    @Environment(FavoritesService.self) private var favoritesService

    @Query private var routes: [Route]

    @State private var viewModel = LineDetailViewModel()
    @State private var showSnakeGame = false

    /// Camera position for the map, centered on Rome initially.
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Namespace for the direction toggle morphing animation.
    @Namespace private var directionNamespace

    // MARK: - Computed

    /// Retrieves the Route model for this routeId.
    private var route: Route? {
        routes.first { $0.routeId == routeId }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Map with Polyline, Stops, and Vehicles
            mapSection
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    directionToggle
                        .padding(.top, 8)
                }
                .overlay(alignment: .bottom) {
                    // Fallback message when shape data is unavailable.
                    if !viewModel.isLoading && viewModel.shapeCoordinates.isEmpty {
                        Text("Percorso non disponibile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // Easter egg button for the legendary line 495.
                    if viewModel.isEasterEggLine {
                        Button {
                            showSnakeGame = true
                        } label: {
                            Text("\u{1F40D}")
                                .font(.title)
                                .padding(8)
                        }
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .padding(.trailing, 16)
                        .padding(.top, 60)
                    }
                }

            // MARK: Stop List
            stopListSection
                .frame(height: 280)
        }
        .navigationTitle(route?.routeShortName ?? "Linea")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let route {
                    let item = FavoriteItem.line(routeId: route.routeId, shortName: route.routeShortName)
                    Button {
                        withAnimation { favoritesService.toggle(item) }
                    } label: {
                        Image(systemName: favoritesService.isFavorite(item) ? "heart.fill" : "heart")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .task {
            loadDetail()
        }
        .onChange(of: viewModel.shapeCoordinates.count) {
            fitCameraToRoute()
        }
        .onChange(of: viewModel.lineStops.count) {
            if viewModel.shapeCoordinates.isEmpty {
                fitCameraToRoute()
            }
        }
        .fullScreenCover(isPresented: $showSnakeGame) {
            SnakeBusView()
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            // Route polyline — the physical path the bus follows on the road.
            if !viewModel.shapeCoordinates.isEmpty {
                MapPolyline(coordinates: viewModel.shapeCoordinates)
                    .stroke(
                        routeColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }

            // Sequential stop pins along the route.
            ForEach(Array(viewModel.lineStops.enumerated()), id: \.element.stopId) { index, stop in
                Annotation(
                    "\(index + 1). \(stop.stopName)",
                    coordinate: CLLocationCoordinate2D(latitude: stop.stopLat, longitude: stop.stopLon)
                ) {
                    stopSequencePin(index: index + 1)
                }
            }

            // Real-time vehicle markers with occupancy badges.
            ForEach(viewModel.vehicles) { vehicle in
                Annotation(
                    "Bus \(vehicle.vehicleId)",
                    coordinate: CLLocationCoordinate2D(latitude: vehicle.latitude, longitude: vehicle.longitude)
                ) {
                    vehicleMarker(vehicle: vehicle)
                }
            }

            // User location.
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Stop Sequence Pin

    /// A numbered pin for stops along the route, showing their order.
    private func stopSequencePin(index: Int) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 24, height: 24)

            Circle()
                .fill(routeColor)
                .frame(width: 20, height: 20)

            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
    }

    // MARK: - Vehicle Marker

    /// An animated bus marker showing position and occupancy.
    private func vehicleMarker(vehicle: VehiclePosition) -> some View {
        VStack(spacing: 2) {
            // Occupancy badge floats above the bus icon.
            OccupancyBadge(occupancy: vehicle.occupancy)

            ZStack {
                Circle()
                    .fill(routeColor)
                    .frame(width: 28, height: 28)

                Image(systemName: "bus.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .rotationEffect(
                        vehicle.bearing != nil
                            ? .degrees(Double(vehicle.bearing!))
                            : .zero
                    )
            }
            .shadow(color: routeColor.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .animation(.easeInOut(duration: 1.0), value: vehicle.latitude)
        .animation(.easeInOut(duration: 1.0), value: vehicle.longitude)
    }

    // MARK: - Direction Toggle

    /// A Liquid Glass segmented control for switching between route directions.
    private var directionToggle: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                directionButton(
                    direction: 0,
                    label: viewModel.directionLabels[0] ?? "Direzione 1"
                )
                directionButton(
                    direction: 1,
                    label: viewModel.directionLabels[1] ?? "Direzione 2"
                )
            }
            .padding(4)
        }
        .frame(maxWidth: 300)
    }

    /// A single direction button within the segmented toggle.
    private func directionButton(direction: Int, label: String) -> some View {
        Button {
            withAnimation(.bouncy(duration: 0.35)) {
                viewModel.selectedDirection = direction
                loadDetail()
            }
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(viewModel.selectedDirection == direction ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if viewModel.selectedDirection == direction {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .matchedGeometryEffect(id: "directionIndicator", in: directionNamespace)
                            .glassEffect()
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stop List Section

    /// Scrollable ordered list of stops with arrival times.
    private var stopListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fermate in ordine")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.lineStops.enumerated()), id: \.element.stopId) { index, stop in
                        HStack(spacing: 12) {
                            // Sequence number in a small circle.
                            Text("\(index + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(routeColor))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(stop.stopName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Palina \(stop.stopCode)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        if index < viewModel.lineStops.count - 1 {
                            // Vertical line connector between stops.
                            HStack {
                                Rectangle()
                                    .fill(routeColor.opacity(0.3))
                                    .frame(width: 2, height: 8)
                                    .padding(.leading, 26)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    /// Derives the route display color from the GTFS hex string.
    private var routeColor: Color {
        guard let route, !route.routeColor.isEmpty else { return .accentColor }
        return Color(hex: route.routeColor) ?? .accentColor
    }

    /// Loads or reloads the line detail data from the ViewModel.
    private func loadDetail() {
        guard let route else { return }
        viewModel.loadLineDetail(
            route: route,
            modelContext: modelContext,
            realtimeService: realtimeService
        )
    }

    /// Computes a bounding region from the route coordinates and fits the map camera.
    private func fitCameraToRoute() {
        // Prefer shape coordinates; fall back to stop coordinates.
        let coords: [CLLocationCoordinate2D]
        if !viewModel.shapeCoordinates.isEmpty {
            coords = viewModel.shapeCoordinates
        } else if !viewModel.lineStops.isEmpty {
            coords = viewModel.lineStops.map {
                CLLocationCoordinate2D(latitude: $0.stopLat, longitude: $0.stopLon)
            }
        } else {
            return
        }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3,
            longitudeDelta: (maxLon - minLon) * 1.3
        )

        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LineDetailView(routeId: "495")
    }
}
