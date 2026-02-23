import Foundation
import MapKit

// MARK: - SpatialPoint Protocol

/// A protocol for objects that can be placed in a QuadTree based on geographic coordinates.
protocol SpatialPoint: Sendable {
    var coordinate: CLLocationCoordinate2D { get }
    var pointId: String { get }
}

// MARK: - StopPoint

/// A lightweight, Sendable representation of a Stop for use in the QuadTree.
/// Extracted from the SwiftData model so the tree can live outside the main actor.
struct StopPoint: SpatialPoint, Sendable {
    let stopId: String
    let stopName: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var pointId: String { stopId }
}

// MARK: - MapAnnotationItem

/// Represents either a single stop or a cluster of stops for map display.
enum MapAnnotationItem: Identifiable, Sendable, Equatable {
    case stop(StopPoint)
    case cluster(latitude: Double, longitude: Double, count: Int, stopIds: [String])

    var id: String {
        switch self {
        case .stop(let point):
            return "stop_\(point.stopId)"
        case .cluster(let lat, let lon, let count, _):
            return "cluster_\(lat)_\(lon)_\(count)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .stop(let point):
            return point.coordinate
        case .cluster(let lat, let lon, _, _):
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    static func == (lhs: MapAnnotationItem, rhs: MapAnnotationItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BoundingBox

/// An axis-aligned bounding box defined by its center and half-dimensions.
struct BoundingBox: Sendable {
    let centerX: Double // longitude
    let centerY: Double // latitude
    let halfWidth: Double
    let halfHeight: Double

    var minX: Double { centerX - halfWidth }
    var maxX: Double { centerX + halfWidth }
    var minY: Double { centerY - halfHeight }
    var maxY: Double { centerY + halfHeight }

    /// Returns true if this box contains the given coordinate.
    func contains(x: Double, y: Double) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }

    /// Returns true if this box intersects with the other box.
    func intersects(_ other: BoundingBox) -> Bool {
        !(other.minX > maxX || other.maxX < minX ||
          other.minY > maxY || other.maxY < minY)
    }

    /// Creates a BoundingBox from an MKMapRect.
    static func from(mapRect: MKMapRect) -> BoundingBox {
        let topLeft = MKMapPoint(x: mapRect.origin.x, y: mapRect.origin.y)
        let bottomRight = MKMapPoint(x: mapRect.maxX, y: mapRect.maxY)

        let topLeftCoord = topLeft.coordinate
        let bottomRightCoord = bottomRight.coordinate

        let centerLat = (topLeftCoord.latitude + bottomRightCoord.latitude) / 2.0
        let centerLon = (topLeftCoord.longitude + bottomRightCoord.longitude) / 2.0
        let halfHeight = abs(topLeftCoord.latitude - bottomRightCoord.latitude) / 2.0
        let halfWidth = abs(bottomRightCoord.longitude - topLeftCoord.longitude) / 2.0

        return BoundingBox(
            centerX: centerLon,
            centerY: centerLat,
            halfWidth: halfWidth,
            halfHeight: halfHeight
        )
    }

    /// A bounding box covering the entire Rome metro area with generous padding.
    static let rome = BoundingBox(
        centerX: 12.4964,
        centerY: 41.9028,
        halfWidth: 0.35,
        halfHeight: 0.25
    )
}

// MARK: - QuadTreeNode

/// A node in the QuadTree. Each node either holds points (leaf) or has four children.
final class QuadTreeNode<Point: SpatialPoint>: @unchecked Sendable {
    let boundary: BoundingBox
    let capacity: Int

    private(set) var points: [Point] = []

    private(set) var northWest: QuadTreeNode?
    private(set) var northEast: QuadTreeNode?
    private(set) var southWest: QuadTreeNode?
    private(set) var southEast: QuadTreeNode?

    private var isSubdivided: Bool { northWest != nil }

    init(boundary: BoundingBox, capacity: Int = 16) {
        self.boundary = boundary
        self.capacity = capacity
    }

    // MARK: - Insert

    /// Inserts a point into the QuadTree. Returns true if the point was successfully inserted.
    @discardableResult
    func insert(_ point: Point) -> Bool {
        let x = point.coordinate.longitude
        let y = point.coordinate.latitude

        guard boundary.contains(x: x, y: y) else {
            return false
        }

        if !isSubdivided && points.count < capacity {
            points.append(point)
            return true
        }

        if !isSubdivided {
            subdivide()
        }

        if northWest!.insert(point) { return true }
        if northEast!.insert(point) { return true }
        if southWest!.insert(point) { return true }
        if southEast!.insert(point) { return true }

        // Should not happen if boundary logic is correct, but add as fallback.
        return false
    }

    // MARK: - Query

    /// Returns all points within the given bounding box.
    func query(range: BoundingBox) -> [Point] {
        guard boundary.intersects(range) else {
            return []
        }

        var found: [Point] = []

        for point in points {
            let x = point.coordinate.longitude
            let y = point.coordinate.latitude
            if range.contains(x: x, y: y) {
                found.append(point)
            }
        }

        if isSubdivided {
            found.append(contentsOf: northWest!.query(range: range))
            found.append(contentsOf: northEast!.query(range: range))
            found.append(contentsOf: southWest!.query(range: range))
            found.append(contentsOf: southEast!.query(range: range))
        }

        return found
    }

    /// Returns the total number of points stored in this node and all descendants.
    var totalPointCount: Int {
        var count = points.count
        if isSubdivided {
            count += northWest!.totalPointCount
            count += northEast!.totalPointCount
            count += southWest!.totalPointCount
            count += southEast!.totalPointCount
        }
        return count
    }

    // MARK: - Subdivide

    private func subdivide() {
        let cx = boundary.centerX
        let cy = boundary.centerY
        let hw = boundary.halfWidth / 2.0
        let hh = boundary.halfHeight / 2.0

        northWest = QuadTreeNode(
            boundary: BoundingBox(centerX: cx - hw, centerY: cy + hh, halfWidth: hw, halfHeight: hh),
            capacity: capacity
        )
        northEast = QuadTreeNode(
            boundary: BoundingBox(centerX: cx + hw, centerY: cy + hh, halfWidth: hw, halfHeight: hh),
            capacity: capacity
        )
        southWest = QuadTreeNode(
            boundary: BoundingBox(centerX: cx - hw, centerY: cy - hh, halfWidth: hw, halfHeight: hh),
            capacity: capacity
        )
        southEast = QuadTreeNode(
            boundary: BoundingBox(centerX: cx + hw, centerY: cy - hh, halfWidth: hw, halfHeight: hh),
            capacity: capacity
        )

        // Re-distribute existing points into children.
        let existing = points
        points.removeAll(keepingCapacity: true)
        for point in existing {
            _ = northWest!.insert(point)
                || northEast!.insert(point)
                || southWest!.insert(point)
                || southEast!.insert(point)
        }
    }
}

// MARK: - QuadTree

/// A thread-safe QuadTree wrapper built once from all stops and reused for spatial queries.
final class QuadTree<Point: SpatialPoint>: Sendable {
    let root: QuadTreeNode<Point>

    /// Builds a QuadTree from an array of points within the given boundary.
    /// This is designed to be called once on a background thread.
    init(points: [Point], boundary: BoundingBox = .rome) {
        self.root = QuadTreeNode(boundary: boundary, capacity: 16)
        for point in points {
            root.insert(point)
        }
    }

    /// Queries the tree for all points within the given bounding box.
    func query(range: BoundingBox) -> [Point] {
        root.query(range: range)
    }

    /// Total number of points in the tree.
    var count: Int {
        root.totalPointCount
    }
}

// MARK: - ClusterEngine

/// Performs grid-based clustering of spatial points for map display.
/// All heavy computation runs off the main thread via async methods.
actor ClusterEngine {

    /// The QuadTree built from all transit stops. Set once after initial data load.
    private var quadTree: QuadTree<StopPoint>?

    /// Minimum number of points in a grid cell to form a cluster.
    /// At high zoom levels, we show individual stops; at low zoom, we cluster aggressively.
    private let minimumClusterSize = 2

    // MARK: - Build Tree

    /// Builds the QuadTree from an array of StopPoints. Call this once after loading GTFS data.
    func buildTree(from stops: [StopPoint]) {
        quadTree = QuadTree(points: stops, boundary: .rome)
    }

    /// Returns true if the tree has been built.
    var isTreeBuilt: Bool {
        quadTree != nil
    }

    // MARK: - Cluster

    /// Given the visible map rect and a zoom level, returns clustered annotation items.
    ///
    /// - Parameters:
    ///   - mapRect: The currently visible MKMapRect.
    ///   - zoomLevel: A value representing the map's zoom. Higher = more zoomed in.
    ///     Typically derived from `MKMapView.region.span` or camera distance.
    ///   - screenWidth: The width of the map view in points (for grid cell sizing).
    /// - Returns: An array of `MapAnnotationItem` representing stops and clusters.
    func cluster(
        in mapRect: MKMapRect,
        zoomLevel: Double,
        screenWidth: Double = 390.0
    ) -> [MapAnnotationItem] {
        guard let quadTree else { return [] }

        let range = BoundingBox.from(mapRect: mapRect)
        let visiblePoints = quadTree.query(range: range)

        guard !visiblePoints.isEmpty else { return [] }

        // At very high zoom levels, skip clustering and return individual stops.
        if zoomLevel >= 17.0 {
            return visiblePoints.map { .stop($0) }
        }

        // Determine grid cell size based on zoom level.
        // Lower zoom = larger cells = more aggressive clustering.
        let cellSize = gridCellSize(for: zoomLevel, visibleRange: range, screenWidth: screenWidth)

        // Build grid: key is (column, row), value is array of points in that cell.
        var grid: [GridKey: [StopPoint]] = [:]

        for point in visiblePoints {
            let col = Int((point.coordinate.longitude - range.minX) / cellSize.width)
            let row = Int((point.coordinate.latitude - range.minY) / cellSize.height)
            let key = GridKey(col: col, row: row)
            grid[key, default: []].append(point)
        }

        // Convert grid cells to annotation items.
        var annotations: [MapAnnotationItem] = []
        annotations.reserveCapacity(grid.count)

        for (_, cellPoints) in grid {
            if cellPoints.count < minimumClusterSize {
                // Show individual stops.
                for point in cellPoints {
                    annotations.append(.stop(point))
                }
            } else {
                // Create cluster at the centroid of the cell's points.
                var sumLat = 0.0
                var sumLon = 0.0
                var ids: [String] = []
                ids.reserveCapacity(cellPoints.count)

                for point in cellPoints {
                    sumLat += point.coordinate.latitude
                    sumLon += point.coordinate.longitude
                    ids.append(point.stopId)
                }

                let centerLat = sumLat / Double(cellPoints.count)
                let centerLon = sumLon / Double(cellPoints.count)

                annotations.append(.cluster(
                    latitude: centerLat,
                    longitude: centerLon,
                    count: cellPoints.count,
                    stopIds: ids
                ))
            }
        }

        return annotations
    }

    // MARK: - Grid Helpers

    /// A hashable key for the clustering grid.
    private struct GridKey: Hashable {
        let col: Int
        let row: Int
    }

    /// Computes the grid cell dimensions in coordinate degrees based on zoom level.
    private struct CellSize {
        let width: Double  // degrees longitude
        let height: Double // degrees latitude
    }

    private func gridCellSize(
        for zoomLevel: Double,
        visibleRange: BoundingBox,
        screenWidth: Double
    ) -> CellSize {
        // Number of grid columns across the screen.
        // Fewer columns at low zoom (bigger cells), more at high zoom (smaller cells).
        let columns: Double
        switch zoomLevel {
        case ..<10:
            columns = 4
        case 10..<12:
            columns = 6
        case 12..<14:
            columns = 8
        case 14..<16:
            columns = 12
        default:
            columns = 16
        }

        let totalWidth = visibleRange.halfWidth * 2.0
        let totalHeight = visibleRange.halfHeight * 2.0

        let cellWidth = max(totalWidth / columns, 0.0001)
        // Maintain roughly square cells by using aspect ratio.
        let aspectRatio = totalHeight / max(totalWidth, 0.0001)
        let rows = columns * aspectRatio
        let cellHeight = max(totalHeight / max(rows, 1.0), 0.0001)

        return CellSize(width: cellWidth, height: cellHeight)
    }
}
