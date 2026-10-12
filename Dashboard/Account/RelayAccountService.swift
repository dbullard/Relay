import Foundation

protocol RelayAccountServicing {
    func requestMagicLink(email: String, codeChallenge: String?) async throws -> RelayAccountMagicLinkResponse
    func exchangeAuthCode(code: String, codeVerifier: String) async throws -> String
    func validateSession(token: String) async throws -> RelayAccountSessionResponse
    func fetchAccount(token: String) async throws -> RelayAccountSessionResponse
    func fetchEntitlements(token: String) async throws -> RelayAccountEntitlementsResponse
    func sendHeartbeat(token: String, request: RelayAccountHeartbeatRequest) async throws
    func linkLegacyLicense(token: String, licenseKey: String) async throws
    func activateLinkedLicense(token: String, request: RelayAccountActivateLinkedLicenseRequest) async throws -> RelayAccountActivateLinkedLicenseResponse
    func deactivateLinkedLicense(token: String, request: RelayAccountDeactivateLinkedLicenseRequest) async throws -> RelayAccountDeactivateLinkedLicenseResponse
    func linkAppStoreSubscription(token: String, request: RelayAccountLinkAppStoreSubscriptionRequest) async throws
    func logout(token: String) async throws
    func deleteAccount(token: String) async throws
}

final class RelayAccountService: RelayAccountServicing {
    struct ServiceError: LocalizedError, Equatable {
        let statusCode: Int?
        let message: String

        var errorDescription: String? { message }

        var isUnauthorized: Bool {
            statusCode == 401 || statusCode == 403
        }
    }

    private struct EmptyBody: Encodable {}
    private struct EmptyResponse: Decodable {}
    private struct ErrorResponse: Decodable {
        let error: String?
        let message: String?
    }

    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL = RelayAccountConfig.apiBaseURL, session: URLSession = RelayAccountService.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    func requestMagicLink(email: String, codeChallenge: String?) async throws -> RelayAccountMagicLinkResponse {
        let body = RelayAccountMagicLinkRequest(email: email, codeChallenge: codeChallenge)
        return try await post(path: "/api/auth/magic-link", body: body)
    }

    func exchangeAuthCode(code: String, codeVerifier: String) async throws -> String {
        let response: RelayAccountAuthExchangeResponse = try await post(
            path: "/api/auth/exchange",
            body: RelayAccountAuthExchangeRequest(code: code, codeVerifier: codeVerifier)
        )
        guard response.ok, let token = response.token, !token.isEmpty else {
            throw ServiceError(statusCode: 401, message: "Sign-in link expired. Request a new one.")
        }
        return token
    }

    func validateSession(token: String) async throws -> RelayAccountSessionResponse {
        try await get(path: "/api/auth/session", token: token)
    }

    func fetchAccount(token: String) async throws -> RelayAccountSessionResponse {
        try await get(path: "/api/me", token: token)
    }

    func fetchEntitlements(token: String) async throws -> RelayAccountEntitlementsResponse {
        try await get(path: "/api/me/entitlements", token: token)
    }

    func sendHeartbeat(token: String, request: RelayAccountHeartbeatRequest) async throws {
        let _: RelayAccountHeartbeatResponse = try await post(
            path: "/api/me/heartbeat",
            token: token,
            body: request
        )
    }

    func linkLegacyLicense(token: String, licenseKey: String) async throws {
        let _: EmptyResponse = try await post(
            path: "/api/me/link-license",
            token: token,
            body: RelayAccountLinkLicenseRequest(licenseKey: licenseKey)
        )
    }

    func activateLinkedLicense(token: String, request: RelayAccountActivateLinkedLicenseRequest) async throws -> RelayAccountActivateLinkedLicenseResponse {
        try await post(
            path: "/api/me/activate-linked-license",
            token: token,
            body: request
        )
    }

    func deactivateLinkedLicense(token: String, request: RelayAccountDeactivateLinkedLicenseRequest) async throws -> RelayAccountDeactivateLinkedLicenseResponse {
        try await post(
            path: "/api/me/deactivate-linked-license",
            token: token,
            body: request
        )
    }

    func linkAppStoreSubscription(token: String, request: RelayAccountLinkAppStoreSubscriptionRequest) async throws {
        let _: EmptyResponse = try await post(
            path: "/api/me/link-app-store-subscription",
            token: token,
            body: request
        )
    }

    func logout(token: String) async throws {
        let _: EmptyResponse = try await post(path: "/api/auth/logout", token: token, body: EmptyBody())
    }

    func deleteAccount(token: String) async throws {
        let _: EmptyResponse = try await delete(path: "/api/me", token: token)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, body: Body) async throws -> T {
        try await post(path: path, token: nil, body: body)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, token: String?, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request: request)
    }

    private func delete<T: Decodable>(path: String, token: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request: request)
    }

    private func get<T: Decodable>(path: String, token: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request: request)
    }

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ServiceError(statusCode: nil, message: "Invalid Relay Account response.")
        }

        let requestURL = request.url?.absoluteString ?? "<unknown-url>"
        print("[RelayAccountService] \(request.httpMethod ?? "REQUEST") \(requestURL) -> \(http.statusCode)")

        guard (200...299).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data) ?? "Relay Account request failed."
            throw ServiceError(statusCode: http.statusCode, message: messageForStatusCode(http.statusCode, fallback: message))
        }

        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }

        do {
            return try makeRelayAccountJSONDecoder().decode(T.self, from: data)
        } catch {
            throw ServiceError(statusCode: http.statusCode, message: "Relay Account response could not be read.")
        }
    }

    private func mapTransportError(_ error: Error) -> ServiceError {
        if let serviceError = error as? ServiceError {
            return serviceError
        }

        guard let urlError = error as? URLError else {
            return ServiceError(statusCode: nil, message: error.localizedDescription)
        }

        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return ServiceError(statusCode: nil, message: "Relay Account is offline right now.")
        case .timedOut:
            return ServiceError(statusCode: nil, message: "Relay Account request timed out.")
        default:
            return ServiceError(statusCode: nil, message: urlError.localizedDescription)
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let payload = try? makeRelayAccountJSONDecoder().decode(ErrorResponse.self, from: data) {
            return payload.message ?? payload.error
        }
        guard let decoded = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !decoded.isEmpty else { return nil }
        return decoded
    }

    private func messageForStatusCode(_ statusCode: Int, fallback: String) -> String {
        switch statusCode {
        case 401, 403:
            return "Your Relay Account session has expired. Sign in again."
        default:
            return fallback
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

func makeRelayAccountJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self) {
            let withFractionalSeconds = ISO8601DateFormatter()
            withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractionalSeconds.date(from: raw) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: raw) {
                return date
            }
        }

        if let raw = try? container.decode(Double.self) {
            return Date(timeIntervalSinceReferenceDate: raw)
        }

        throw RelayAccountService.ServiceError(statusCode: nil, message: "Invalid Relay Account date value.")
    }
    return decoder
}

func makeRelayAccountJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: date))
    }
    return encoder
}
