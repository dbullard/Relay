import Foundation

final class RelayLicensingClient {
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

    func checkout(planId: String) async throws -> URL {
        let request = LicensingCheckoutRequest(planId: planId)
        let response: LicensingCheckoutResponse = try await post(path: "/api/licensing/checkout", body: request)
        guard let url = URL(string: response.url) else {
            throw ClientError(message: "Checkout URL is invalid.")
        }
        return url
    }

    func fetchPlans() async throws -> LicensingPlansResponse {
        try await get(path: "/api/licensing/plans")
    }

    func activate(request: LicensingActivateRequest) async throws -> LicensingActivateResponse {
        try await post(path: "/api/licensing/activate", body: request)
    }

    @available(*, deprecated, message: "Use checkout(planId:) with dynamic plans.")
    func checkout(variant: LicensingVariant) async throws -> URL {
        let request = LicensingCheckoutRequest(variant: variant.rawValue)
        let response: LicensingCheckoutResponse = try await post(path: "/api/licensing/checkout", body: request)
        guard let url = URL(string: response.url) else {
            throw ClientError(message: "Checkout URL is invalid.")
        }
        return url
    }

    func validate(request: LicensingValidateRequest) async throws -> LicensingValidateResponse {
        try await post(path: "/api/licensing/validate", body: request)
    }

    func deactivate(request: LicensingDeactivateRequest) async throws -> LicensingDeactivateResponse {
        try await post(path: "/api/licensing/deactivate", body: request)
    }

    func manageURL() async throws -> URL {
        let response: LicensingManageResponse = try await get(path: "/api/licensing/manage")
        let sanitized = sanitizeManageURL(response.url)
        guard let url = URL(string: sanitized) else {
            throw ClientError(message: "Manage URL is invalid.")
        }
        return url
    }

    private func sanitizeManageURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicatedHost = ".lemonsqueezy.com.lemonsqueezy.com"
        if trimmed.contains(duplicatedHost) {
            return trimmed.replacingOccurrences(of: duplicatedHost, with: ".lemonsqueezy.com")
        }
        return trimmed
    }

    private func post<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request: request)
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        return try await perform(request: request)
    }

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "Invalid server response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError(message: "Server error (\(http.statusCode)): \(body)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: raw) { return date }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: raw) { return date }
            throw ClientError(message: "Invalid date format: \(raw)")
        }
        return try decoder.decode(T.self, from: data)
    }
}
