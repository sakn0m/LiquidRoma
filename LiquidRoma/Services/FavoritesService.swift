import Foundation

// MARK: - FavoritesService

/// An observable service that manages user favorites (stops and lines) with
/// persistence through UserDefaults. Favorites are stored as JSON-encoded data.
@Observable
final class FavoritesService {

    // MARK: - Published Properties

    /// The user's list of favorite items, kept in sync with UserDefaults.
    private(set) var favorites: [FavoriteItem] = []

    // MARK: - Configuration

    private static let userDefaultsKey = "user_favorites"

    // MARK: - Initialization

    init() {
        loadFromDefaults()
    }

    // MARK: - Public API

    /// Adds a favorite item. Does nothing if the item is already a favorite.
    func add(_ item: FavoriteItem) {
        guard !isFavorite(item) else { return }
        favorites.append(item)
        saveToDefaults()
    }

    /// Removes a favorite item. Does nothing if the item is not a favorite.
    func remove(_ item: FavoriteItem) {
        favorites.removeAll { $0.id == item.id }
        saveToDefaults()
    }

    /// Returns true if the given item is currently in the favorites list.
    func isFavorite(_ item: FavoriteItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    /// Toggles a favorite item: adds it if not present, removes it if already present.
    func toggle(_ item: FavoriteItem) {
        if isFavorite(item) {
            remove(item)
        } else {
            add(item)
        }
    }

    /// Moves favorites at the specified offsets to a new position.
    /// Useful for SwiftUI List reordering support.
    func move(from offsets: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
        saveToDefaults()
    }

    /// Removes all favorites.
    func removeAll() {
        favorites.removeAll()
        saveToDefaults()
    }

    /// Returns all favorite stops.
    var favoriteStops: [FavoriteItem] {
        favorites.filter {
            if case .stop = $0 { return true }
            return false
        }
    }

    /// Returns all favorite lines.
    var favoriteLines: [FavoriteItem] {
        favorites.filter {
            if case .line = $0 { return true }
            return false
        }
    }

    // MARK: - Persistence

    /// Loads favorites from UserDefaults. Called once during init.
    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) else {
            favorites = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([FavoriteItem].self, from: data)
            favorites = decoded
        } catch {
            // If decoding fails (e.g. schema change), start fresh.
            favorites = []
        }
    }

    /// Saves the current favorites array to UserDefaults as JSON.
    private func saveToDefaults() {
        do {
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } catch {
            // Encoding of Codable enums should not fail in practice.
            // If it does, the in-memory state is still correct; persistence will retry on next mutation.
        }
    }
}
