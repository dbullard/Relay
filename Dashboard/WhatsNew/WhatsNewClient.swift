import Foundation

final class WhatsNewClient {
    struct ClientError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let session: URLSession
    private let baseURL: URL

    init?(baseURL: URL?, session: URLSession = .shared) {
        guard let baseURL else { return nil }
        self.baseURL = baseURL
        self.session = session
    }

    static func feedURL(baseURL: URL, channel: String) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/api/whats-new"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "channel", value: channel)]
        return components?.url ?? baseURL.appendingPathComponent("/api/whats-new")
    }

    func fetchFeed(channel: String) async throws -> WhatsNewFeed {
        var request = URLRequest(url: Self.feedURL(baseURL: baseURL, channel: channel))
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "Invalid server response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ClientError(message: "Server error (\(http.statusCode)) fetching What's New feed.")
        }
        return try JSONDecoder().decode(WhatsNewFeed.self, from: data)
    }
}
