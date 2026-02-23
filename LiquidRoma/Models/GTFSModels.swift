import Foundation
import SwiftData

// MARK: - Stop

@Model
final class Stop {
    #Unique<Stop>([\.stopId])
    #Index<Stop>([\.stopId], [\.stopLat, \.stopLon])

    var stopId: String
    var stopCode: String
    var stopName: String
    var stopDesc: String
    var stopLat: Double
    var stopLon: Double
    var locationTypeRaw: Int
    var parentStation: String

    init(
        stopId: String,
        stopCode: String = "",
        stopName: String = "",
        stopDesc: String = "",
        stopLat: Double = 0.0,
        stopLon: Double = 0.0,
        locationTypeRaw: Int = 0,
        parentStation: String = ""
    ) {
        self.stopId = stopId
        self.stopCode = stopCode
        self.stopName = stopName
        self.stopDesc = stopDesc
        self.stopLat = stopLat
        self.stopLon = stopLon
        self.locationTypeRaw = locationTypeRaw
        self.parentStation = parentStation
    }
}

// MARK: - Route

@Model
final class Route {
    #Unique<Route>([\.routeId])
    #Index<Route>([\.routeId])

    var routeId: String
    var agencyId: String
    var routeShortName: String
    var routeLongName: String
    var routeType: Int
    var routeColor: String
    var routeTextColor: String

    init(
        routeId: String,
        agencyId: String = "",
        routeShortName: String = "",
        routeLongName: String = "",
        routeType: Int = 3,
        routeColor: String = "",
        routeTextColor: String = ""
    ) {
        self.routeId = routeId
        self.agencyId = agencyId
        self.routeShortName = routeShortName
        self.routeLongName = routeLongName
        self.routeType = routeType
        self.routeColor = routeColor
        self.routeTextColor = routeTextColor
    }
}

// MARK: - Trip

@Model
final class Trip {
    #Unique<Trip>([\.tripId])
    #Index<Trip>([\.tripId], [\.routeId])

    var tripId: String
    var routeId: String
    var serviceId: String
    var tripHeadsign: String
    var directionId: Int
    var shapeId: String

    init(
        tripId: String,
        routeId: String = "",
        serviceId: String = "",
        tripHeadsign: String = "",
        directionId: Int = 0,
        shapeId: String = ""
    ) {
        self.tripId = tripId
        self.routeId = routeId
        self.serviceId = serviceId
        self.tripHeadsign = tripHeadsign
        self.directionId = directionId
        self.shapeId = shapeId
    }
}

// MARK: - StopTime

@Model
final class StopTime {
    #Unique<StopTime>([\.tripId, \.stopSequence])
    #Index<StopTime>([\.tripId], [\.stopId], [\.stopId, \.tripId])

    var tripId: String
    var arrivalTime: String
    var departureTime: String
    var stopId: String
    var stopSequence: Int
    var shapeDist: Double?

    init(
        tripId: String,
        arrivalTime: String = "",
        departureTime: String = "",
        stopId: String = "",
        stopSequence: Int = 0,
        shapeDist: Double? = nil
    ) {
        self.tripId = tripId
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.stopId = stopId
        self.stopSequence = stopSequence
        self.shapeDist = shapeDist
    }
}

// MARK: - Shape

@Model
final class Shape {
    #Unique<Shape>([\.shapeId, \.sequence])
    #Index<Shape>([\.shapeId], [\.shapeId, \.sequence])

    var shapeId: String
    var lat: Double
    var lon: Double
    var sequence: Int
    var shapeDist: Double

    init(
        shapeId: String,
        lat: Double = 0.0,
        lon: Double = 0.0,
        sequence: Int = 0,
        shapeDist: Double = 0.0
    ) {
        self.shapeId = shapeId
        self.lat = lat
        self.lon = lon
        self.sequence = sequence
        self.shapeDist = shapeDist
    }
}

// MARK: - CalendarDate

@Model
final class CalendarDate {
    #Index<CalendarDate>([\.serviceId], [\.date])

    var serviceId: String
    var date: String
    var exceptionType: Int

    init(
        serviceId: String,
        date: String = "",
        exceptionType: Int = 1
    ) {
        self.serviceId = serviceId
        self.date = date
        self.exceptionType = exceptionType
    }
}
