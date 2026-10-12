import Combine
import Foundation

struct WebpageFavorite: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
    var createdAt: Date = .now

    var trimmedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class WebpageFavoritesStore: ObservableObject {
    static let shared = WebpageFavoritesStore()

    @Published private(set) var favorites: [WebpageFavorite] = []

    private let defaults: UserDefaults
    private let storageKey = "dashboard.webpageFavorites"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addFavorite(title: String, urlString: String) {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLString.isEmpty else { return }

        if let existingIndex = favorites.firstIndex(where: {
            $0.trimmedURLString.caseInsensitiveCompare(trimmedURLString) == .orderedSame
        }) {
            favorites[existingIndex].title = sanitizedTitle(title, fallbackURLString: trimmedURLString)
            save()
            return
        }

        favorites.insert(
            WebpageFavorite(
                title: sanitizedTitle(title, fallbackURLString: trimmedURLString),
                urlString: trimmedURLString
            ),
            at: 0
        )
        save()
    }

    func removeFavorite(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    func removeFavorite(urlString: String) {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLString.isEmpty else { return }

        favorites.removeAll {
            $0.trimmedURLString.caseInsensitiveCompare(trimmedURLString) == .orderedSame
        }
        save()
    }

    func contains(urlString: String) -> Bool {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLString.isEmpty else { return false }

        return favorites.contains {
            $0.trimmedURLString.caseInsensitiveCompare(trimmedURLString) == .orderedSame
        }
    }

    private func sanitizedTitle(_ title: String, fallbackURLString: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        if let url = URL(string: fallbackURLString),
           let host = url.host(percentEncoded: false),
           !host.isEmpty {
            return host
        }

        return fallbackURLString
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            favorites = []
            return
        }

        do {
            favorites = try decoder.decode([WebpageFavorite].self, from: data)
        } catch {
            favorites = []
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(favorites)
            defaults.set(data, forKey: storageKey)
        } catch {
            defaults.removeObject(forKey: storageKey)
        }
    }
}
