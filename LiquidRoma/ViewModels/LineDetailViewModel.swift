import Foundation
import SwiftUI
import SwiftData
import MapKit
import CoreLocation

// MARK: - LineDetailViewModel

@Observable
@MainActor
final class LineDetailViewModel {

    // MARK: - Published State

    /// The currently selected direction (0 or 1).
    var selectedDirection: Int = 0

    /// Ordered stops for the selected direction.
    var lineStops: [Stop] = []

    /// Shape coordinates for drawing the polyline on the map.
    var shapeCoordinates: [CLLocationCoordinate2D] = []

    /// Real-time vehicle positions on this line.
    var vehicles: [VehiclePosition] = []

    /// Direction labels extracted from trip headsigns (e.g. [0: "Termini", 1: "Anagnina"]).
    var directionLabels: [Int: String] = [:]

    /// The route being displayed.
    private(set) var route: Route?

    /// Whether a load operation is in progress.
    var isLoading = false

    // MARK: - Easter Egg

    /// Returns true if the route short name is "495" (easter egg line).
    var isEasterEggLine: Bool {
        route?.routeShortName == "495"
    }

    // MARK: - Load Line Detail

    /// Loads the full detail for a route in the currently selected direction.
    ///
    /// 1. Finds trips for this route with the matching directionId.
    /// 2. Gets shape coordinates from the Shape table ordered by sequence.
    /// 3. Gets ordered stops from stop_times for a representative trip.
    /// 4. Filters live vehicle positions for this route.
    ///
    /// - Parameters:
    ///   - route: The route to display.
    ///   - modelContext: The SwiftData model context.
    ///   - realtimeService: The GTFS-RT service for live vehicle positions.
    func loadLineDetail(
        route: Route,
        modelContext: ModelContext,
        realtimeService: GTFSRealtimeService
    ) {
        self.route = route
        isLoading = true

        // Load direction labels for both directions if not already loaded.
        if directionLabels.isEmpty {
            loadDirectionLabels(routeId: route.routeId, modelContext: modelContext)
        }

        Task {
            defer { isLoading = false }

            print("[LineDetail] Loading detail for route \(route.routeId) (\(route.routeShortName)), direction \(selectedDirection)")

            // 1) Find trips for this route in the selected direction.
            let routeId = route.routeId
            let direction = selectedDirection

            var tripDescriptor = FetchDescriptor<Trip>(
                predicate: #Predicate<Trip> { trip in
                    trip.routeId == routeId && trip.directionId == direction
                }
            )
            tripDescriptor.fetchLimit = 500

            let matchingTrips: [Trip]
            do {
                matchingTrips = try modelContext.fetch(tripDescriptor)
            } catch {
                print("[LineDetail] Error fetching trips: \(error)")
                matchingTrips = []
            }

            print("[LineDetail] Found \(matchingTrips.count) trips for route \(routeId), direction \(direction)")

            guard let representativeTrip = matchingTrips.first else {
                print("[LineDetail] No trips found — clearing stops and shape")
                lineStops = []
                shapeCoordinates = []
                vehicles = realtimeService.vehiclesForRoute(routeId: routeId)
                return
            }

            print("[LineDetail] Representative trip: \(representativeTrip.tripId), shapeId: '\(representativeTrip.shapeId)'")

            // 2) Load shape coordinates for the representative trip's shape.
            await loadShapeCoordinates(
                shapeId: representativeTrip.shapeId,
                modelContext: modelContext
            )

            print("[LineDetail] Shape coordinates loaded: \(shapeCoordinates.count) points")

            // 3) Load ordered stops from stop_times for the representative trip.
            await loadOrderedStops(
                tripId: representativeTrip.tripId,
                modelContext: modelContext
            )

            print("[LineDetail] Ordered stops loaded: \(lineStops.count) stops")

            // 4) Get live vehicles for this route.
            vehicles = realtimeService.vehiclesForRoute(routeId: routeId)
            print("[LineDetail] Live vehicles: \(vehicles.count)")
        }
    }

    // MARK: - Toggle Direction

    /// Flips the selected direction and reloads line detail.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData model context.
    ///   - realtimeService: The GTFS-RT service for live vehicle positions.
    func toggleDirection(modelContext: ModelContext, realtimeService: GTFSRealtimeService) {
        selectedDirection = selectedDirection == 0 ? 1 : 0

        guard let route else { return }
        loadLineDetail(route: route, modelContext: modelContext, realtimeService: realtimeService)
    }

    // MARK: - Refresh Vehicles

    /// Refreshes only the real-time vehicle positions without reloading static data.
    ///
    /// - Parameter realtimeService: The GTFS-RT service.
    func refreshVehicles(realtimeService: GTFSRealtimeService) {
        guard let route else { return }
        vehicles = realtimeService.vehiclesForRoute(routeId: route.routeId)
    }

    // MARK: - Direction Labels

    /// Loads trip headsigns for both directions of this route.
    func loadDirectionLabels(routeId: String, modelContext: ModelContext) {
        for dir in [0, 1] {
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate<Trip> { trip in
                    trip.routeId == routeId && trip.directionId == dir
                }
            )
            descriptor.fetchLimit = 1

            if let trip = try? modelContext.fetch(descriptor).first,
               !trip.tripHeadsign.isEmpty {
                directionLabels[dir] = trip.tripHeadsign
            }
        }
    }

    // MARK: - Private Helpers

    /// Loads shape coordinates from the Shape table ordered by sequence.
    private func loadShapeCoordinates(shapeId: String, modelContext: ModelContext) async {
        guard !shapeId.isEmpty else {
            print("[LineDetail] shapeId is empty — cannot load polyline coordinates")
            shapeCoordinates = []
            return
        }

        let descriptor = FetchDescriptor<Shape>(
            predicate: #Predicate<Shape> { shape in
                shape.shapeId == shapeId
            },
            sortBy: [SortDescriptor(\Shape.sequence, order: .forward)]
        )

        let shapes: [Shape]
        do {
            shapes = try modelContext.fetch(descriptor)
        } catch {
            print("[LineDetail] Error fetching shapes for shapeId '\(shapeId)': \(error)")
            shapes = []
        }

        if shapes.isEmpty {
            print("[LineDetail] No shapes found for shapeId '\(shapeId)' — shape data may not be imported yet")
        }

        shapeCoordinates = shapes.map { shape in
            CLLocationCoordinate2D(latitude: shape.lat, longitude: shape.lon)
        }
    }

    /// Loads ordered stops for a given trip from stop_times.
    private func loadOrderedStops(tripId: String, modelContext: ModelContext) async {
        // Fetch stop_times for this trip, ordered by sequence.
        let stopTimeDescriptor = FetchDescriptor<StopTime>(
            predicate: #Predicate<StopTime> { st in
                st.tripId == tripId
            },
            sortBy: [SortDescriptor(\StopTime.stopSequence, order: .forward)]
        )

        let times: [StopTime]
        do {
            times = try modelContext.fetch(stopTimeDescriptor)
        } catch {
            print("[LineDetail] Error fetching stop_times for tripId '\(tripId)': \(error)")
            times = []
        }

        guard !times.isEmpty else {
            print("[LineDetail] No stop_times found for tripId '\(tripId)'")
            lineStops = []
            return
        }

        // Extract ordered stop IDs.
        let orderedStopIds = times.map(\.stopId)

        // Fetch the Stop objects for these IDs.
        let stopIdSet = Set(orderedStopIds)
        let allStopsDescriptor = FetchDescriptor<Stop>()
        let allStops: [Stop]
        do {
            allStops = try modelContext.fetch(allStopsDescriptor)
        } catch {
            print("[LineDetail] Error fetching stops: \(error)")
            allStops = []
        }

        let stopById = Dictionary(uniqueKeysWithValues:
            allStops.filter { stopIdSet.contains($0.stopId) }.map { ($0.stopId, $0) }
        )

        // Reassemble in the correct sequence order.
        lineStops = orderedStopIds.compactMap { stopById[$0] }
    }
}
