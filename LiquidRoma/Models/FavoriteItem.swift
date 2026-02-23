import Foundation

enum FavoriteItem: Codable, Identifiable, Hashable {
    case stop(stopId: String, name: String)
    case line(routeId: String, shortName: String)

    var id: String {
        switch self {
        case .stop(let stopId, _):
            return "stop_\(stopId)"
        case .line(let routeId, _):
            return "line_\(routeId)"
        }
    }

    var displayName: String {
        switch self {
        case .stop(_, let name):
            return name
        case .line(_, let shortName):
            return shortName
        }
    }
}
