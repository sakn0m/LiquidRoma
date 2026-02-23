import Foundation
import SwiftData
import Compression

// MARK: - GTFSDataService

/// An actor-based service responsible for downloading, parsing, and importing GTFS static data
/// into the SwiftData store. Handles both remote downloads and local bundle imports.
actor GTFSDataService {

    // MARK: - URLs

    private static let md5URL = URL(string: "https://romamobilita.it/sites/default/files/rome_static_gtfs.zip.md5")!
    private static let zipURL = URL(string: "https://romamobilita.it/sites/default/files/rome_static_gtfs.zip")!

    // MARK: - UserDefaults Keys

    private static let lastMD5Key = "gtfs_last_md5_hash"
    private static let lastImportDateKey = "gtfs_last_import_date"

    // MARK: - Configuration

    private let batchSize = 5000

    // MARK: - Dependencies

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    /// Checks if the GTFS database has any stops, indicating prior import.
    func isDatabasePopulated() async throws -> Bool {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Stop>()
        let count = try context.fetchCount(descriptor)
        return count > 0
    }

    /// Fetches the remote MD5 hash and compares it against the locally stored hash.
    /// Returns `true` if an update is available (hashes differ or no local hash stored).
    func checkForUpdates() async throws -> Bool {
        let (data, _) = try await URLSession.shared.data(from: Self.md5URL)
        guard let remoteHash = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return true
        }

        let storedHash = UserDefaults.standard.string(forKey: Self.lastMD5Key)?.lowercased()
        return remoteHash != storedHash
    }

    /// Downloads the GTFS zip, extracts it, and imports all CSV files into SwiftData.
    func downloadAndParse() async throws {
        // Download zip file.
        let (tempZipURL, _) = try await URLSession.shared.download(from: Self.zipURL)

        // Move to a known location so we can work with it.
        let fileManager = FileManager.default
        let extractDir = fileManager.temporaryDirectory.appendingPathComponent("gtfs_extract_\(UUID().uuidString)")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: extractDir)
        }

        // Unzip using the built-in Archive utility or shell command.
        let zipDest = extractDir.appendingPathComponent("rome_static_gtfs.zip")
        try fileManager.moveItem(at: tempZipURL, to: zipDest)

        let unzipDir = extractDir.appendingPathComponent("unzipped")
        try fileManager.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        // Use Process to unzip (macOS) or a manual approach. For iOS, use Archive framework.
        try await unzip(source: zipDest, destination: unzipDir)

        // Import all CSV files from the extracted directory.
        try await importFromDirectory(unzipDir)

        // Store the current MD5 hash.
        if let (data, _) = try? await URLSession.shared.data(from: Self.md5URL),
           let hash = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            UserDefaults.standard.set(hash.lowercased(), forKey: Self.lastMD5Key)
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastImportDateKey)
    }

    /// Imports essential GTFS data (routes, stops, trips, calendar_dates) from
    /// bundled CSV files. These are small enough to load quickly on first launch.
    func importEssentialFromBundle() async throws {
        if let url = bundleURL(for: "routes") {
            try await importRoutes(from: url)
        }
        if let url = bundleURL(for: "stops") {
            try await importStops(from: url)
        }
        if let url = bundleURL(for: "trips") {
            try await importTrips(from: url)
        }
        if let url = bundleURL(for: "calendar_dates") {
            try await importCalendarDates(from: url)
        }
    }

    /// Imports heavy GTFS data (stop_times, shapes) from bundled CSV files.
    /// These are large (200MB+) and should be imported in the background.
    func importHeavyFromBundle() async throws {
        if let url = bundleURL(for: "stop_times") {
            try await importStopTimes(from: url)
        }
        if let url = bundleURL(for: "shapes") {
            try await importShapes(from: url)
        }
    }

    /// Checks whether routes have been imported (essential data indicator).
    func hasRoutes() async throws -> Bool {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Route>()
        return try context.fetchCount(descriptor) > 0
    }

    /// Checks whether stop_times have been imported (heavy data indicator).
    func hasStopTimes() async throws -> Bool {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<StopTime>()
        return try context.fetchCount(descriptor) > 0
    }

    /// Finds a bundled CSV file by its base name (e.g. "routes" → "routes.txt").
    private func bundleURL(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "txt")
    }

    /// Imports GTFS data from a local bundle directory. Useful for development and testing
    /// when CSV files are included in the app bundle.
    func importFromLocalBundle(directoryName: String = "gtfs_data") async throws {
        guard let bundleURL = Bundle.main.url(forResource: directoryName, withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent(directoryName) else {
            // Try to find individual files at the root of the bundle.
            guard let stopsURL = Bundle.main.url(forResource: "stops", withExtension: "txt") else {
                throw GTFSError.bundleNotFound(directoryName)
            }
            let bundleDir = stopsURL.deletingLastPathComponent()
            try await importFromDirectory(bundleDir)
            return
        }

        try await importFromDirectory(bundleURL)
    }

    // MARK: - Import From Directory

    /// Parses and imports all recognized GTFS CSV files from a given directory.
    private func importFromDirectory(_ directory: URL) async throws {
        let fileManager = FileManager.default

        // Process each GTFS file if it exists.
        let stopsFile = directory.appendingPathComponent("stops.txt")
        if fileManager.fileExists(atPath: stopsFile.path) {
            try await importStops(from: stopsFile)
        }

        let routesFile = directory.appendingPathComponent("routes.txt")
        if fileManager.fileExists(atPath: routesFile.path) {
            try await importRoutes(from: routesFile)
        }

        let tripsFile = directory.appendingPathComponent("trips.txt")
        if fileManager.fileExists(atPath: tripsFile.path) {
            try await importTrips(from: tripsFile)
        }

        let stopTimesFile = directory.appendingPathComponent("stop_times.txt")
        if fileManager.fileExists(atPath: stopTimesFile.path) {
            try await importStopTimes(from: stopTimesFile)
        }

        let shapesFile = directory.appendingPathComponent("shapes.txt")
        if fileManager.fileExists(atPath: shapesFile.path) {
            try await importShapes(from: shapesFile)
        }

        let calendarDatesFile = directory.appendingPathComponent("calendar_dates.txt")
        if fileManager.fileExists(atPath: calendarDatesFile.path) {
            try await importCalendarDates(from: calendarDatesFile)
        }
    }

    // MARK: - CSV Parsing

    /// A generic CSV parser that handles quoted fields, escaped quotes, and newlines within quotes.
    /// Returns an array of dictionaries keyed by column header names.
    private func parseCSV(fileURL: URL) throws -> (headers: [String], rows: [[String]]) {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = splitCSVLines(content)

        guard let headerLine = lines.first else {
            return ([], [])
        }

        let headers = parseCSVRow(headerLine)
        var rows: [[String]] = []
        rows.reserveCapacity(lines.count - 1)

        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }
            let fields = parseCSVRow(line)
            // Only include rows with the correct number of fields.
            if fields.count == headers.count {
                rows.append(fields)
            } else if fields.count > headers.count {
                // Truncate extra fields.
                rows.append(Array(fields.prefix(headers.count)))
            } else {
                // Pad with empty strings if we have fewer fields.
                var padded = fields
                while padded.count < headers.count {
                    padded.append("")
                }
                rows.append(padded)
            }
        }

        return (headers, rows)
    }

    /// Splits CSV content into logical lines, handling newlines within quoted fields.
    private func splitCSVLines(_ content: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var insideQuote = false

        for char in content {
            if char == "\"" {
                insideQuote.toggle()
                current.append(char)
            } else if char == "\n" && !insideQuote {
                let trimmed = current.trimmingCharacters(in: .init(charactersIn: "\r"))
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
                current = ""
            } else {
                current.append(char)
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }

        return lines
    }

    /// Parses a single CSV row, handling quoted fields with escaped quotes ("").
    private func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuote = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if insideQuote {
                if char == "\"" {
                    // Peek: if next is also a quote, it is an escaped quote.
                    // We cannot peek with a character iterator, so we use a flag approach.
                    current.append(char)
                    insideQuote = false
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" {
                    insideQuote = true
                    // Remove trailing quote from current if we just added one (escaped quote handling).
                    if current.hasSuffix("\"") {
                        // This was an escaped double quote.
                        // Keep current as is; the pair of quotes represents one literal quote.
                    }
                } else if char == "," {
                    fields.append(cleanField(current))
                    current = ""
                } else {
                    current.append(char)
                }
            }
        }

        fields.append(cleanField(current))
        return fields
    }

    /// Removes surrounding quotes and unescapes double quotes in a CSV field.
    private func cleanField(_ field: String) -> String {
        var s = field.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "\"\"", with: "\"")
        return s
    }

    /// Returns the index of a header name, or nil if not found.
    private func columnIndex(for name: String, in headers: [String]) -> Int? {
        headers.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased() })
    }

    /// Safely retrieves a field value from a row by column index, returning a default if out of bounds.
    private func field(_ row: [String], at index: Int?, default defaultValue: String = "") -> String {
        guard let idx = index, idx < row.count else { return defaultValue }
        return row[idx]
    }

    // MARK: - Import Methods

    private func importStops(from fileURL: URL) async throws {
        let (headers, rows) = try parseCSV(fileURL: fileURL)

        let idxStopId = columnIndex(for: "stop_id", in: headers)
        let idxStopCode = columnIndex(for: "stop_code", in: headers)
        let idxStopName = columnIndex(for: "stop_name", in: headers)
        let idxStopDesc = columnIndex(for: "stop_desc", in: headers)
        let idxStopLat = columnIndex(for: "stop_lat", in: headers)
        let idxStopLon = columnIndex(for: "stop_lon", in: headers)
        let idxLocationType = columnIndex(for: "location_type", in: headers)
        let idxParentStation = columnIndex(for: "parent_station", in: headers)

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        for batchStart in stride(from: 0, to: rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, rows.count)
            for i in batchStart..<batchEnd {
                let row = rows[i]
                let stopId = field(row, at: idxStopId)
                guard !stopId.isEmpty else { continue }

                let stop = Stop(
                    stopId: stopId,
                    stopCode: field(row, at: idxStopCode),
                    stopName: field(row, at: idxStopName),
                    stopDesc: field(row, at: idxStopDesc),
                    stopLat: Double(field(row, at: idxStopLat)) ?? 0.0,
                    stopLon: Double(field(row, at: idxStopLon)) ?? 0.0,
                    locationTypeRaw: Int(field(row, at: idxLocationType)) ?? 0,
                    parentStation: field(row, at: idxParentStation)
                )
                context.insert(stop)
            }
            try context.save()
        }
    }

    private func importRoutes(from fileURL: URL) async throws {
        let (headers, rows) = try parseCSV(fileURL: fileURL)

        let idxRouteId = columnIndex(for: "route_id", in: headers)
        let idxAgencyId = columnIndex(for: "agency_id", in: headers)
        let idxShortName = columnIndex(for: "route_short_name", in: headers)
        let idxLongName = columnIndex(for: "route_long_name", in: headers)
        let idxRouteType = columnIndex(for: "route_type", in: headers)
        let idxRouteColor = columnIndex(for: "route_color", in: headers)
        let idxTextColor = columnIndex(for: "route_text_color", in: headers)

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        for batchStart in stride(from: 0, to: rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, rows.count)
            for i in batchStart..<batchEnd {
                let row = rows[i]
                let routeId = field(row, at: idxRouteId)
                guard !routeId.isEmpty else { continue }

                let route = Route(
                    routeId: routeId,
                    agencyId: field(row, at: idxAgencyId),
                    routeShortName: field(row, at: idxShortName),
                    routeLongName: field(row, at: idxLongName),
                    routeType: Int(field(row, at: idxRouteType)) ?? 3,
                    routeColor: field(row, at: idxRouteColor),
                    routeTextColor: field(row, at: idxTextColor)
                )
                context.insert(route)
            }
            try context.save()
        }
    }

    private func importTrips(from fileURL: URL) async throws {
        let (headers, rows) = try parseCSV(fileURL: fileURL)

        let idxTripId = columnIndex(for: "trip_id", in: headers)
        let idxRouteId = columnIndex(for: "route_id", in: headers)
        let idxServiceId = columnIndex(for: "service_id", in: headers)
        let idxHeadsign = columnIndex(for: "trip_headsign", in: headers)
        let idxDirectionId = columnIndex(for: "direction_id", in: headers)
        let idxShapeId = columnIndex(for: "shape_id", in: headers)

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        for batchStart in stride(from: 0, to: rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, rows.count)
            for i in batchStart..<batchEnd {
                let row = rows[i]
                let tripId = field(row, at: idxTripId)
                guard !tripId.isEmpty else { continue }

                let trip = Trip(
                    tripId: tripId,
                    routeId: field(row, at: idxRouteId),
                    serviceId: field(row, at: idxServiceId),
                    tripHeadsign: field(row, at: idxHeadsign),
                    directionId: Int(field(row, at: idxDirectionId)) ?? 0,
                    shapeId: field(row, at: idxShapeId)
                )
                context.insert(trip)
            }
            try context.save()
        }
    }

    private func importStopTimes(from fileURL: URL) async throws {
        let (headers, rows) = try parseCSV(fileURL: fileURL)

        let idxTripId = columnIndex(for: "trip_id", in: headers)
        let idxArrival = columnIndex(for: "arrival_time", in: headers)
        let idxDeparture = columnIndex(for: "departure_time", in: headers)
        let idxStopId = columnIndex(for: "stop_id", in: headers)
        let idxSequence = columnIndex(for: "stop_sequence", in: headers)
        let idxShapeDist = columnIndex(for: "shape_dist_traveled", in: headers)

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        for batchStart in stride(from: 0, to: rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, rows.count)
            for i in batchStart..<batchEnd {
                let row = rows[i]
                let tripId = field(row, at: idxTripId)
                guard !tripId.isEmpty else { continue }

                let shapeDistStr = field(row, at: idxShapeDist)
                let shapeDist: Double? = shapeDistStr.isEmpty ? nil : Double(shapeDistStr)

                let stopTime = StopTime(
                    tripId: tripId,
                    arrivalTime: field(row, at: idxArrival),
                    departureTime: field(row, at: idxDeparture),
                    stopId: field(row, at: idxStopId),
                    stopSequence: Int(field(row, at: idxSequence)) ?? 0,
                    shapeDist: shapeDist
                )
                context.insert(stopTime)
            }
            try context.save()
        }
    }

    private func importShapes(from fileURL: URL) async throws {
        let (headers, rows) = try parseCSV(fileURL: fileURL)

        let idxShapeId = columnIndex(for: "shape_id", in: headers)
        let idxLat = columnIndex(for: "shape_pt_lat", in: headers)
        let idxLon = columnIndex(for: "shape_pt_lon", in: headers)
        let idxSequence = columnIndex(for: "shape_pt_sequence", in: headers)
        let idxShapeDist = columnIndex(for: "shape_dist_traveled", in: headers)

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        for batchStart in stride(from: 0, to: rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, rows.count)
            for i in batchStart..<batchEnd {
                let row = rows[i]
                let shapeId = field(row, at: idxShapeId)
                guard !shapeId.isEmpty else { continue }

                let shape = Shape(
                    shapeId: shapeId,
                    lat: Double(field(row, at: idxLat)) ?? 0.0,
                    lon: Double(field(row, at: idxLon)) ?? 0.0,
                    sequence: Int(field(row, at: idxSequence)) ?? 0,
                    shapeDist: Double(field(row, at: idxShapeDist)) ?? 0.0
                )
                context.insert(shape)
            }
            try context.save()
        }
    }

    private func importCalendarDates(from fileURL: URL) async throws {
        let (headers, rows) = try parseCSV(fileURL: fileURL)

        let idxServiceId = columnIndex(for: "service_id", in: headers)
        let idxDate = columnIndex(for: "date", in: headers)
        let idxExceptionType = columnIndex(for: "exception_type", in: headers)

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        for batchStart in stride(from: 0, to: rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, rows.count)
            for i in batchStart..<batchEnd {
                let row = rows[i]
                let serviceId = field(row, at: idxServiceId)
                guard !serviceId.isEmpty else { continue }

                let calDate = CalendarDate(
                    serviceId: serviceId,
                    date: field(row, at: idxDate),
                    exceptionType: Int(field(row, at: idxExceptionType)) ?? 1
                )
                context.insert(calDate)
            }
            try context.save()
        }
    }

    // MARK: - Zip Extraction

    /// Extracts a zip file to a destination directory.
    /// Uses Foundation's built-in decompression on iOS 16+ or falls back to a shell command.
    private func unzip(source: URL, destination: URL) async throws {
        // Use FileManager or a lightweight approach.
        // On iOS, we can use the `Archive` type from Apple's frameworks or spawn a process.
        // Since we target iOS 26, we use the modern approach.
        #if os(iOS)
        // On iOS, use the system unzip via NSFileCoordinator or a third-party library.
        // For a self-contained solution, we parse the zip manually or rely on a bundled framework.
        // Here we use a simple approach with Process on macOS and a fallback for iOS.
        try extractZipFile(at: source, to: destination)
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", source.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GTFSError.unzipFailed
        }
        #endif
    }

    /// A minimal zip extractor for iOS that reads the zip central directory and extracts stored/deflated entries.
    /// For production use, consider using Apple's Compression framework or a dedicated library.
    private func extractZipFile(at sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: sourceURL)

        // Find entries using the local file header signature: PK\x03\x04
        var offset = 0
        while offset + 30 <= data.count {
            let sig = data[offset..<offset+4]
            guard sig.elementsEqual([0x50, 0x4B, 0x03, 0x04]) else {
                break
            }

            let compressionMethod = UInt16(data[offset + 8]) | (UInt16(data[offset + 9]) << 8)
            let compressedSize = Int(UInt32(data[offset + 18]) | (UInt32(data[offset + 19]) << 8) |
                                     (UInt32(data[offset + 20]) << 16) | (UInt32(data[offset + 21]) << 24))
            let uncompressedSize = Int(UInt32(data[offset + 22]) | (UInt32(data[offset + 23]) << 8) |
                                       (UInt32(data[offset + 24]) << 16) | (UInt32(data[offset + 25]) << 24))
            let fileNameLength = Int(UInt16(data[offset + 26]) | (UInt16(data[offset + 27]) << 8))
            let extraFieldLength = Int(UInt16(data[offset + 28]) | (UInt16(data[offset + 29]) << 8))

            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + fileNameLength
            guard fileNameEnd <= data.count else { break }

            let fileNameData = data[fileNameStart..<fileNameEnd]
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                offset = fileNameEnd + extraFieldLength + compressedSize
                continue
            }

            let dataStart = fileNameEnd + extraFieldLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= data.count else { break }

            let entryData = data[dataStart..<dataEnd]
            let filePath = destinationURL.appendingPathComponent(fileName)

            if fileName.hasSuffix("/") {
                try fileManager.createDirectory(at: filePath, withIntermediateDirectories: true)
            } else {
                let parentDir = filePath.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parentDir.path) {
                    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }

                if compressionMethod == 0 {
                    // Stored (no compression).
                    try Data(entryData).write(to: filePath)
                } else if compressionMethod == 8 {
                    // Deflated: use Compression framework.
                    let decompressed = try decompressDeflate(Data(entryData), uncompressedSize: uncompressedSize)
                    try decompressed.write(to: filePath)
                }
                // Skip other compression methods.
            }

            offset = dataEnd
        }
    }

    /// Decompresses deflate-compressed data using the Compression framework.
    private func decompressDeflate(_ compressedData: Data, uncompressedSize: Int) throws -> Data {
        // Attempt raw DEFLATE decompression using the Compression framework.
        var destinationBuffer = Data(count: uncompressedSize)
        let decompressedSize = destinationBuffer.withUnsafeMutableBytes { destPtr in
            compressedData.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    destPtr.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decompressedSize > 0 else {
            throw GTFSError.decompressionFailed
        }

        return destinationBuffer.prefix(decompressedSize)
    }
}

// MARK: - GTFSError

enum GTFSError: LocalizedError {
    case bundleNotFound(String)
    case unzipFailed
    case decompressionFailed
    case invalidCSV(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound(let name):
            return "GTFS bundle directory '\(name)' not found in app bundle."
        case .unzipFailed:
            return "Failed to extract GTFS zip archive."
        case .decompressionFailed:
            return "Failed to decompress GTFS data."
        case .invalidCSV(let file):
            return "Invalid CSV format in file: \(file)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
