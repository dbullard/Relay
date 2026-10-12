import Foundation
import AuthenticationServices
import Security
import LocalAuthentication

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import Network
#endif

#if canImport(CryptoKit)
import CryptoKit
#endif

enum LiveStreamFeatureFlags {
    static var isEnabled: Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "RELAY_DISTRIBUTION_CHANNEL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "beta" || raw == "debug"
    }
}

struct YouTubeBroadcastChoice: Identifiable, Equatable, Hashable {
    enum State: String, Equatable, Hashable {
        case live
        case upcoming
        case ended
        case ready
        case unknown

        var title: String {
            switch self {
            case .live:
                return "Live"
            case .upcoming:
                return "Upcoming"
            case .ended:
                return "Ended"
            case .ready:
                return "Ready"
            case .unknown:
                return "Unknown"
            }
        }
    }

    let id: String
    let title: String
    let state: State
    let scheduledStartTime: Date?
    let boundStreamID: String?

    var subtitle: String {
        var segments: [String] = [state.title]
        if let scheduledStartTime {
            segments.append(Self.formatter.string(from: scheduledStartTime))
        }
        return segments.joined(separator: " • ")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct YouTubeChannelSummary: Equatable {
    let channelID: String
    let title: String
}

struct YouTubeMonitorSnapshot: Equatable {
    enum LiveState: Equatable {
        case offline
        case starting
        case live
        case ended
        case error(String)

        var title: String {
            switch self {
            case .offline:
                return "Offline"
            case .starting:
                return "Starting"
            case .live:
                return "Live"
            case .ended:
                return "Ended"
            case .error:
                return "Error"
            }
        }
    }

    enum HealthState: Equatable {
        case unknown
        case good
        case warning
        case bad

        var title: String {
            switch self {
            case .unknown:
                return "Unknown"
            case .good:
                return "Good"
            case .warning:
                return "Warning"
            case .bad:
                return "Issue"
            }
        }
    }

    let broadcastID: String
    let broadcastTitle: String
    let liveState: LiveState
    let viewerCount: Int?
    let healthState: HealthState
    let healthSummary: String?
    let lastUpdatedAt: Date
    let deepLinkURL: URL?
}

enum YouTubeConfigurationError: LocalizedError {
    case missingClientID(String)
    case invalidRedirectURI(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID(let key):
            return "YouTube OAuth is not configured. Add a Google OAuth client ID to Info.plist key \(key)."
        case .invalidRedirectURI(let uri):
            return "The YouTube OAuth redirect URI is invalid: \(uri)"
        }
    }
}

enum YouTubeAPIError: LocalizedError {
    case noSavedTokens
    case broadcastNotFound
    case unauthorized
    case invalidResponse
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .noSavedTokens:
            return "Connect a YouTube account to load live stream data."
        case .broadcastNotFound:
            return "The selected YouTube broadcast could not be found."
        case .unauthorized:
            return "The saved YouTube login is no longer valid. Reconnect the account."
        case .invalidResponse:
            return "YouTube returned an unexpected response."
        case .providerMessage(let message):
            return message
        }
    }
}

enum YouTubeOAuthState {
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func matches(callbackURL: URL, expected: String) -> Bool {
        guard !expected.isEmpty,
              let value = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "state" })?.value else { return false }
        return value == expected
    }
}

struct YouTubeOAuthConfiguration {
    let clientID: String
    let clientSecret: String?
    let redirectURI: String

    var callbackScheme: String {
        URL(string: redirectURI)?.scheme ?? ""
    }

    static func load() throws -> YouTubeOAuthConfiguration {
        #if os(iOS)
        let clientIDKey = "YOUTUBE_OAUTH_CLIENT_ID_IOS"
        let clientSecretKey = "YOUTUBE_OAUTH_CLIENT_SECRET_IOS"
        let redirectKey = "YOUTUBE_OAUTH_REDIRECT_URI_IOS"
        #else
        let clientIDKey = "YOUTUBE_OAUTH_CLIENT_ID_MACOS"
        let clientSecretKey = "YOUTUBE_OAUTH_CLIENT_SECRET_MACOS"
        let redirectKey = "YOUTUBE_OAUTH_REDIRECT_URI_MACOS"
        #endif

        let genericClientKey = "YOUTUBE_OAUTH_CLIENT_ID"
        let genericClientSecretKey = "YOUTUBE_OAUTH_CLIENT_SECRET"
        let genericRedirectKey = "YOUTUBE_OAUTH_REDIRECT_URI"

        let clientID = (
            Bundle.main.object(forInfoDictionaryKey: clientIDKey) as? String
            ?? Bundle.main.object(forInfoDictionaryKey: genericClientKey) as? String
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clientID.isEmpty else {
            throw YouTubeConfigurationError.missingClientID(clientIDKey)
        }

        let clientSecret = (
            Bundle.main.object(forInfoDictionaryKey: clientSecretKey) as? String
            ?? Bundle.main.object(forInfoDictionaryKey: genericClientSecretKey) as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let redirectURI = (
            Bundle.main.object(forInfoDictionaryKey: redirectKey) as? String
            ?? Bundle.main.object(forInfoDictionaryKey: genericRedirectKey) as? String
            ?? "app.relay.youtube:/oauth2redirect"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: redirectURI),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            throw YouTubeConfigurationError.invalidRedirectURI(redirectURI)
        }

        return YouTubeOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret?.isEmpty == true ? nil : clientSecret,
            redirectURI: redirectURI
        )
    }
}

struct YouTubeOAuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

protocol YouTubeTokenStore: AnyObject {
    func loadTokens() -> YouTubeOAuthTokens?
    func saveTokens(_ tokens: YouTubeOAuthTokens?)
    func clear()
}

final class YouTubeKeychainTokenStore: YouTubeTokenStore {
    private let service = "app.relay.youtube.oauth"
    private let account = "youtube"

    func loadTokens() -> YouTubeOAuthTokens? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(YouTubeOAuthTokens.self, from: data)
    }

    func saveTokens(_ tokens: YouTubeOAuthTokens?) {
        guard let tokens else {
            clear()
            return
        }

        let data = (try? JSONEncoder().encode(tokens)) ?? Data()
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(
            attrs as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            let addContext = LAContext()
            addContext.interactionNotAllowed = true
            var addQuery = attrs
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            addQuery[kSecUseAuthenticationContext as String] = addContext
            _ = SecItemAdd(addQuery as CFDictionary, nil)
            return
        }

        clear()
        let addContext = LAContext()
        addContext.interactionNotAllowed = true
        var addQuery = attrs
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecUseAuthenticationContext as String] = addContext
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class YouTubeOAuthService: NSObject {
    private let configuration: YouTubeOAuthConfiguration
    private let tokenStore: YouTubeTokenStore
    private let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let scope = "https://www.googleapis.com/auth/youtube.readonly"
    private var currentSession: ASWebAuthenticationSession?

    #if os(macOS)
    private weak var macAnchor: ASPresentationAnchor?
    #endif

    #if os(iOS)
    private weak var iosAnchor: ASPresentationAnchor?
    #endif

    init(
        configuration: YouTubeOAuthConfiguration,
        tokenStore: YouTubeTokenStore = YouTubeKeychainTokenStore()
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
    }

    func startLogin(presentingAnchor: ASPresentationAnchor? = nil) async throws {
        #if os(macOS)
        macAnchor = presentingAnchor ?? NSApp.keyWindow ?? NSApp.windows.first
        #endif

        #if os(iOS)
        if let presentingAnchor {
            iosAnchor = presentingAnchor
        } else if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first(where: { $0.isKeyWindow }) {
            iosAnchor = window
        }
        #endif

        let verifier = Self.generateVerifier()
        let challenge = try Self.challenge(for: verifier)
        let state = YouTubeOAuthState.make()

        #if os(macOS)
        let loopbackServer = try YouTubeLoopbackRedirectServer(redirectURI: configuration.redirectURI)
        let redirectURI = try await loopbackServer.start()
        let authorizationURL = Self.makeAuthorizationURL(
            baseURL: self.authURL,
            clientID: configuration.clientID,
            redirectURI: redirectURI,
            scope: scope,
            challenge: challenge,
            state: state
        )

        guard NSWorkspace.shared.open(authorizationURL) else {
            throw YouTubeAPIError.providerMessage("Relay could not open the browser for YouTube login.")
        }

        let callbackURL = try await loopbackServer.waitForCallback()
        #else
        let redirectURI = configuration.redirectURI
        var comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = Self.authorizationQueryItems(
            clientID: configuration.clientID,
            redirectURI: redirectURI,
            scope: scope,
            challenge: challenge,
            state: state
        )

        let callbackURL = try await presentAuthSession(
            authURL: comps.url!,
            callbackScheme: configuration.callbackScheme
        )
        #endif

        guard YouTubeOAuthState.matches(callbackURL: callbackURL, expected: state) else {
            throw YouTubeAPIError.invalidResponse
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value else {
            throw YouTubeAPIError.providerMessage("YouTube login did not return an authorization code.")
        }

        try await exchangeCodeForTokens(code: code, redirectURI: redirectURI, verifier: verifier)
    }

    func logout() {
        tokenStore.clear()
    }

    func ensureValidAccessToken() async throws -> String {
        if let tokens = tokenStore.loadTokens(),
           let expiresAt = tokens.expiresAt,
           expiresAt > Date().addingTimeInterval(30) {
            return tokens.accessToken
        }

        if let tokens = tokenStore.loadTokens(),
           tokens.expiresAt == nil,
           !tokens.accessToken.isEmpty {
            return tokens.accessToken
        }

        if let tokens = tokenStore.loadTokens(),
           let refreshToken = tokens.refreshToken,
           !refreshToken.isEmpty {
            let refreshed = try await refreshTokens(refreshToken: refreshToken)
            tokenStore.saveTokens(refreshed)
            return refreshed.accessToken
        }

        throw YouTubeAPIError.noSavedTokens
    }

    private func presentAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: YouTubeAPIError.invalidResponse)
                    return
                }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            currentSession = session
            session.start()
        }
    }

    private func exchangeCodeForTokens(code: String, redirectURI: String, verifier: String) async throws {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "client_id", value: configuration.clientID),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_verifier", value: verifier)
        ]
        if let clientSecret = configuration.clientSecret {
            body.queryItems?.append(.init(name: "client_secret", value: clientSecret))
        }
        request.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Google OAuth error."
            throw YouTubeAPIError.providerMessage(message)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        tokenStore.saveTokens(tokenResponse.storedTokens)
    }

    func refreshTokens(refreshToken: String) async throws -> YouTubeOAuthTokens {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            .init(name: "grant_type", value: "refresh_token"),
            .init(name: "client_id", value: configuration.clientID),
            .init(name: "refresh_token", value: refreshToken)
        ]
        if let clientSecret = configuration.clientSecret {
            body.queryItems?.append(.init(name: "client_secret", value: clientSecret))
        }
        request.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Google OAuth refresh error."
            throw YouTubeAPIError.providerMessage(message)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let refresh = tokenResponse.refresh_token ?? refreshToken
        return YouTubeOAuthTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: refresh,
            expiresAt: tokenResponse.expires_in.map { Date().addingTimeInterval($0) }
        )
    }

    private static func generateVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }

    private static func challenge(for verifier: String) throws -> String {
        let data = verifier.data(using: .utf8) ?? Data()
        return try data.sha256().base64URLEncodedString()
    }

    private static func makeAuthorizationURL(
        baseURL: URL,
        clientID: String,
        redirectURI: String,
        scope: String,
        challenge: String,
        state: String
    ) -> URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = authorizationQueryItems(
            clientID: clientID,
            redirectURI: redirectURI,
            scope: scope,
            challenge: challenge,
            state: state
        )
        return comps.url!
    }

    private static func authorizationQueryItems(
        clientID: String,
        redirectURI: String,
        scope: String,
        challenge: String,
        state: String
    ) -> [URLQueryItem] {
        [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "include_granted_scopes", value: "true"),
            .init(name: "prompt", value: "consent")
        ]
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: TimeInterval?

        var storedTokens: YouTubeOAuthTokens {
            YouTubeOAuthTokens(
                accessToken: access_token,
                refreshToken: refresh_token,
                expiresAt: expires_in.map { Date().addingTimeInterval($0) }
            )
        }
    }
}

#if os(macOS)
private final class YouTubeLoopbackRedirectServer {
    private let listener: NWListener
    private let redirectURI: String
    private var continuation: CheckedContinuation<URL, Error>?
    private var timeoutTask: Task<Void, Never>?
    private let lock = NSLock()

    init(redirectURI: String) throws {
        guard let url = URL(string: redirectURI),
              let port = url.port,
              url.host == "127.0.0.1" || url.host?.lowercased() == "localhost",
              let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw YouTubeConfigurationError.invalidRedirectURI(redirectURI)
        }

        self.redirectURI = redirectURI
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: endpointPort)
    }

    func start() async throws -> String {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { @MainActor [self] in
                self.handle(connection: connection)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self else { return }
                    continuation.resume(returning: self.redirectURI)
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            self.listener.start(queue: .main)
        }
    }

    func waitForCallback(timeoutSeconds: TimeInterval = 180) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self?.finish(with: .failure(YouTubeAPIError.providerMessage("Timed out waiting for the YouTube login to finish.")))
            }
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.finish(with: .failure(error))
                connection.cancel()
                return
            }

            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.finish(with: .failure(YouTubeAPIError.invalidResponse))
                connection.cancel()
                return
            }

            let callbackURL = self.extractURL(from: request)
            let response = self.httpResponseBody(for: callbackURL)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })

            if let callbackURL {
                self.finish(with: .success(callbackURL))
            } else {
                self.finish(with: .failure(YouTubeAPIError.invalidResponse))
            }
        }
    }

    private func extractURL(from request: String) -> URL? {
        guard let firstLine = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first else {
            return nil
        }
        let segments = firstLine.split(separator: " ")
        guard segments.count >= 2 else { return nil }
        let pathAndQuery = String(segments[1])
        return URL(string: "http://127.0.0.1\(pathAndQuery)")
    }

    private func httpResponseBody(for callbackURL: URL?) -> Data {
        let message: String
        if callbackURL?.host == "127.0.0.1" {
            message = """
            <html><body style="font-family:-apple-system,system-ui;padding:32px;background:#111;color:#fff;">
            <h2>YouTube connected</h2>
            <p>You can close this window and return to Relay.</p>
            </body></html>
            """
        } else {
            message = """
            <html><body style="font-family:-apple-system,system-ui;padding:32px;background:#111;color:#fff;">
            <h2>Relay login error</h2>
            <p>This callback was not recognized. You can close this window and try again.</p>
            </body></html>
            """
        }

        let body = message.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/html; charset=utf-8\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    private func finish(with result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        timeoutTask?.cancel()
        timeoutTask = nil
        listener.cancel()

        guard let continuation else { return }
        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
#endif

extension YouTubeOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        if let macAnchor {
            return macAnchor
        }
        if let keyWindow = NSApp.keyWindow {
            return keyWindow
        }
        if let firstWindow = NSApp.windows.first {
            return firstWindow
        }
        return ASPresentationAnchor()
        #else
        return iosAnchor ?? ASPresentationAnchor()
        #endif
    }
}

final class YouTubeAPIClient {
    private let oauthService: YouTubeOAuthService
    private let tokenStore: YouTubeTokenStore
    private let session: URLSession

    init(
        oauthService: YouTubeOAuthService,
        tokenStore: YouTubeTokenStore = YouTubeKeychainTokenStore(),
        session: URLSession = .shared
    ) {
        self.oauthService = oauthService
        self.tokenStore = tokenStore
        self.session = session
    }

    var isConnected: Bool {
        tokenStore.loadTokens() != nil
    }

    func fetchCurrentChannel() async throws -> YouTubeChannelSummary? {
        let response: ChannelsResponse = try await send(
            path: "/youtube/v3/channels",
            query: [
                "part": "snippet",
                "mine": "true",
                "maxResults": "1"
            ]
        )

        guard let first = response.items.first else { return nil }
        return YouTubeChannelSummary(
            channelID: first.id,
            title: first.snippet.title
        )
    }

    func fetchBroadcastChoices() async throws -> [YouTubeBroadcastChoice] {
        let broadcasts: BroadcastsResponse = try await send(
            path: "/youtube/v3/liveBroadcasts",
            query: [
                "part": "id,snippet,status,contentDetails",
                "mine": "true",
                "broadcastType": "all",
                "maxResults": "50"
            ]
        )

        var merged: [String: YouTubeBroadcastChoice] = [:]
        for item in broadcasts.items {
            let state = Self.choiceState(from: item.status.lifeCycleStatus, fallback: .unknown)
            guard state != .ended, state != .unknown else { continue }

            let choice = YouTubeBroadcastChoice(
                id: item.id,
                title: item.snippet.title,
                state: state,
                scheduledStartTime: item.snippet.scheduledStartTime.flatMap(Self.isoFormatter.date(from:)),
                boundStreamID: item.contentDetails?.boundStreamID
            )
            merged[item.id] = choice
        }

        return merged.values.sorted { lhs, rhs in
            let lhsPriority = Self.sortPriority(for: lhs.state)
            let rhsPriority = Self.sortPriority(for: rhs.state)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            switch (lhs.scheduledStartTime, rhs.scheduledStartTime) {
            case let (l?, r?):
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    func fetchMonitorSnapshot(broadcastID: String) async throws -> YouTubeMonitorSnapshot {
        let broadcasts: BroadcastsResponse = try await send(
            path: "/youtube/v3/liveBroadcasts",
            query: [
                "part": "id,snippet,status,contentDetails",
                "id": broadcastID
            ]
        )

        guard let broadcast = broadcasts.items.first else {
            throw YouTubeAPIError.broadcastNotFound
        }

        let videoResponse: VideosResponse = try await send(
            path: "/youtube/v3/videos",
            query: [
                "part": "liveStreamingDetails",
                "id": broadcastID
            ]
        )

        let viewerCount = videoResponse.items.first?.liveStreamingDetails?.concurrentViewers.flatMap(Int.init)

        let streamID = broadcast.contentDetails?.boundStreamID
        let liveStream: LiveStreamResponse.Item?
        if let streamID {
            let response: LiveStreamResponse = try await send(
                path: "/youtube/v3/liveStreams",
                query: [
                    "part": "status",
                    "id": streamID
                ]
            )
            liveStream = response.items.first
        } else {
            liveStream = nil
        }

        let healthStatus = Self.healthState(from: liveStream?.status.healthStatus?.status)
        let healthSummary = Self.healthSummary(from: liveStream?.status.healthStatus)
        let liveState = Self.liveState(from: broadcast.status.lifeCycleStatus)

        return YouTubeMonitorSnapshot(
            broadcastID: broadcast.id,
            broadcastTitle: broadcast.snippet.title,
            liveState: liveState,
            viewerCount: viewerCount,
            healthState: healthStatus,
            healthSummary: healthSummary,
            lastUpdatedAt: Date(),
            deepLinkURL: URL(string: "https://www.youtube.com/watch?v=\(broadcast.id)")
        )
    }

    private func send<T: Decodable>(
        path: String,
        query: [String: String],
        retryingAfterRefresh: Bool = false
    ) async throws -> T {
        let token = try await oauthService.ensureValidAccessToken()

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.googleapis.com"
        comps.path = path
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = comps.url else {
            throw YouTubeAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Relay/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.invalidResponse
        }

        if http.statusCode == 401, !retryingAfterRefresh,
           let refreshToken = tokenStore.loadTokens()?.refreshToken,
           !refreshToken.isEmpty {
            let refreshed = try await oauthService.refreshTokens(refreshToken: refreshToken)
            tokenStore.saveTokens(refreshed)
            return try await send(path: path, query: query, retryingAfterRefresh: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw YouTubeAPIError.unauthorized
            }

            if let payload = try? JSONDecoder().decode(YouTubeErrorEnvelope.self, from: data),
               let first = payload.error.errors.first {
                throw YouTubeAPIError.providerMessage(first.message)
            }

            let rawMessage = String(data: data, encoding: .utf8) ?? "Unknown YouTube API error."
            throw YouTubeAPIError.providerMessage(rawMessage)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func choiceState(from lifeCycleStatus: String?, fallback: YouTubeBroadcastChoice.State = .unknown) -> YouTubeBroadcastChoice.State {
        switch lifeCycleStatus?.lowercased() {
        case "live", "livestarting", "teststarting":
            return .live
        case "ready", "created":
            return .ready
        case "complete", "revoked":
            return .ended
        case "testing":
            return .live
        default:
            return fallback
        }
    }

    private static func sortPriority(for state: YouTubeBroadcastChoice.State) -> Int {
        switch state {
        case .live:
            return 0
        case .upcoming:
            return 1
        case .ready:
            return 2
        case .unknown:
            return 3
        case .ended:
            return 4
        }
    }

    private static func liveState(from lifeCycleStatus: String?) -> YouTubeMonitorSnapshot.LiveState {
        switch lifeCycleStatus?.lowercased() {
        case "live", "testing":
            return .live
        case "livestarting", "teststarting":
            return .starting
        case "complete":
            return .ended
        case "ready", "created", "revoked":
            return .offline
        default:
            return .offline
        }
    }

    private static func healthState(from status: String?) -> YouTubeMonitorSnapshot.HealthState {
        switch status?.lowercased() {
        case "good":
            return .good
        case "ok":
            return .warning
        case "bad", "no_data":
            return .bad
        default:
            return .unknown
        }
    }

    private static func healthSummary(from healthStatus: LiveStreamResponse.HealthStatus?) -> String? {
        if let issue = healthStatus?.configurationIssues?.first {
            let details = [issue.description, issue.reason]
                .compactMap { value in
                    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? nil : trimmed
                }
            if !details.isEmpty {
                return details.joined(separator: " • ")
            }
        }

        let trimmed = (healthStatus?.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private struct ChannelsResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let id: String
            let snippet: Snippet

            struct Snippet: Decodable {
                let title: String
            }
        }
    }

    private struct BroadcastsResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let id: String
            let snippet: Snippet
            let status: Status
            let contentDetails: ContentDetails?

            struct Snippet: Decodable {
                let title: String
                let scheduledStartTime: String?
            }

            struct Status: Decodable {
                let lifeCycleStatus: String?
            }

            struct ContentDetails: Decodable {
                let boundStreamID: String?

                enum CodingKeys: String, CodingKey {
                    case boundStreamID = "boundStreamId"
                }
            }
        }
    }

    private struct VideosResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let liveStreamingDetails: LiveStreamingDetails?

            struct LiveStreamingDetails: Decodable {
                let concurrentViewers: String?
            }
        }
    }

    private struct LiveStreamResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let status: Status
        }

        struct Status: Decodable {
            let healthStatus: HealthStatus?
        }

        struct HealthStatus: Decodable {
            let status: String?
            let configurationIssues: [ConfigurationIssue]?
        }

        struct ConfigurationIssue: Decodable {
            let description: String?
            let reason: String?
        }
    }

    private struct YouTubeErrorEnvelope: Decodable {
        let error: YouTubeError

        struct YouTubeError: Decodable {
            let errors: [YouTubeInnerError]
        }

        struct YouTubeInnerError: Decodable {
            let message: String
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func sha256() throws -> Data {
        #if canImport(CryptoKit)
        return Data(CryptoKit.SHA256.hash(data: self))
        #else
        throw NSError(
            domain: "YouTubeOAuthService",
            code: -10,
            userInfo: [NSLocalizedDescriptionKey: "SHA256 requires CryptoKit on this platform."]
        )
        #endif
    }
}
