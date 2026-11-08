#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
import AuthenticationServices

/// Planning Center OAuth settings (see docs/INTEGRATIONS.md). Community builds ship with no
/// client ID; register your own Planning Center app and enter its client ID in
/// Settings > Integrations (or set `PCO_OAUTH_CLIENT_ID` in `Config/Local.xcconfig`).
public enum PCOOAuthConfiguration {
    /// Redirect URI to register on your Planning Center app. Its scheme is declared in Info.plist.
    public static let redirectURI = "app.relay.pco://oauth/callback"

    public static var clientID: String {
        ServiceCredentials.resolved(
            defaultsKey: ServiceCredentials.Key.pcoClientID,
            plistKeys: ["PCO_OAUTH_CLIENT_ID"]
        )
    }

    public static var isConfigured: Bool { !clientID.isEmpty }
}

public final class OAuthService: NSObject {
    public enum OAuthError: LocalizedError, Equatable {
        case missingCode
        case cancelled
        case notConfigured

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Planning Center sign-in is not configured. Enter your Planning Center client ID in Settings > Integrations (see docs/INTEGRATIONS.md)."
            case .missingCode:
                return "Planning Center did not return an authorization code."
            case .cancelled:
                return "Sign-in canceled."
            }
        }
    }

    private let clientID: String
    private let authURL = URL(string: "https://api.planningcenteronline.com/oauth/authorize")!
    private let tokenURL = URL(string: "https://api.planningcenteronline.com/oauth/token")!
    private let redirectURI = PCOOAuthConfiguration.redirectURI
    private let scope = "services people" // Add additional scopes space-separated if needed, e.g., "services people"

    private let tokenStore: TokenStore
    private var currentSession: ASWebAuthenticationSession?
#if os(macOS)
    private weak var macAnchor: ASPresentationAnchor?
#endif
#if os(iOS)
    private weak var iosAnchor: ASPresentationAnchor?
#endif

    public init(clientID: String, tokenStore: TokenStore) {
        self.clientID = clientID
        self.tokenStore = tokenStore
    }

    private func platformRedirectURI() -> String {
        redirectURI
    }

    // MARK: - Runtime Self-Checks
    private func isURLSchemeDeclared(_ scheme: String) -> Bool {
        guard !scheme.isEmpty else { return false }
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }
        for type in urlTypes {
            if let schemes = type["CFBundleURLSchemes"] as? [String] {
                if schemes.contains(where: { $0.caseInsensitiveCompare(scheme) == .orderedSame }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - PKCE

    private func generateVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }

    private func challenge(for verifier: String) throws -> String {
        let data = verifier.data(using: .utf8)!
        let hashed = try data.sha256()
        return hashed.base64URLEncodedString()
    }

    // MARK: - Public API

    public func startLogin(forceReauthenticate: Bool = false, clearStoredTokens: Bool = false, forcePromptLogin: Bool = false, presentingAnchor: ASPresentationAnchor? = nil) async throws {
        // Validate scope is non-empty for PCO
        if scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("ERROR: OAuthService: Scope must not be empty for Planning Center. Update the scope string (e.g., 'services'). Aborting login.")
            return
        }
#if os(macOS)
        // Capture the presenting window for ASWebAuthenticationSession on macOS
        if let presentingAnchor = presentingAnchor {
            self.macAnchor = presentingAnchor
        } else {
            // Fallbacks to avoid presentation error 2
            self.macAnchor = NSApp.keyWindow ?? NSApp.windows.first
        }
#endif
        
#if os(iOS)
if let presentingAnchor = presentingAnchor {
    self.iosAnchor = presentingAnchor
} else if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = scene.windows.first(where: { $0.isKeyWindow }) {
    // Use the key window as anchor for ASWebAuthenticationSession
    self.iosAnchor = window
}
#endif

        guard !clientID.isEmpty else { throw OAuthError.notConfigured }

        let verifier = generateVerifier()
        let challenge = try challenge(for: verifier)
        let redirect = platformRedirectURI()

        // Runtime self-check: Ensure the expected callback scheme is declared in Info.plist
        let expectedSchemeForCheck = URL(string: redirect)?.scheme ?? ""
        if !isURLSchemeDeclared(expectedSchemeForCheck) {
            print("WARNING: OAuthService: Expected URL scheme not declared in Info.plist: \(expectedSchemeForCheck). Add a URL Type with this scheme so the OAuth callback can return to the app. Redirect URI: \(redirect)")
        }

        if clearStoredTokens {
            tokenStore.clear()
        }

        var comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: scope)
        ]
        // Request a fresh login UI only when explicitly forcing a different user
        if forcePromptLogin {
            items.append(URLQueryItem(name: "prompt", value: "login"))
        }
        comps.queryItems = items
        let authURL = comps.url!

        let expectedScheme = URL(string: redirect)!.scheme ?? "<nil>"
        print("\n===== OAuth Debug =====\nAuth URL (copy to inspect):\n\(authURL.absoluteString)\nRedirect URI: \(redirect)\nExpected callback scheme: \(expectedScheme)\nEphemeral session: \(forceReauthenticate)\nForce prompt login: \(forcePromptLogin)\n========================\n")
        print("NOTE: Ensure your macOS target Info → URL Types includes scheme: \(expectedScheme) and that your Planning Center app registration Redirect URI matches exactly: \(redirect)")

        let callbackURL = try await presentAuthSession(authURL: authURL, callbackScheme: URL(string: redirect)!.scheme!, ephemeral: forceReauthenticate)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }
        try await exchangeCodeForTokens(code: code, redirectURI: redirect, verifier: verifier)
    }

    public func logout() {
        tokenStore.clear()
    }

    public func ensureValidAccessToken() async throws -> String {
        if let tokens = tokenStore.loadTokens(), let exp = tokens.expiresAt, exp > Date().addingTimeInterval(30) {
            return tokens.accessToken
        }
        // Try refresh
        if let tokens = tokenStore.loadTokens(), let refresh = tokens.refreshToken {
            let newTokens = try await refreshTokens(refreshToken: refresh)
            tokenStore.saveTokens(newTokens)
            return newTokens.accessToken
        }
        throw NSError(domain: "OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid access token. Please login."])
    }

    // MARK: - Private

    private func presentAuthSession(authURL: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, error in
                if let error = error as NSError? {
                    print("ASWebAuthenticationSession completion error: domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
                } else if let url = url {
                    print("ASWebAuthenticationSession completion URL: \(url.absoluteString)")
                } else {
                    print("ASWebAuthenticationSession completion: no URL and no error")
                }
                if let error = error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: OAuthError.missingCode)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = ephemeral
            self.currentSession = session
            session.start()
        }
    }

    private func exchangeCodeForTokens(code: String, redirectURI: String, verifier: String) async throws {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        req.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(domain: "OAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(text)"])
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: TimeInterval?
        }
        let tok = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = tok.expires_in.map { Date().addingTimeInterval($0) }
        tokenStore.saveTokens(OAuthTokens(accessToken: tok.access_token, refreshToken: tok.refresh_token, expiresAt: expiresAt))
    }

    public func refreshTokens(refreshToken: String) async throws -> OAuthTokens {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        req.httpBody = body.query?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(domain: "OAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed: \(text)"])
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: TimeInterval?
        }
        let tok = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = tok.expires_in.map { Date().addingTimeInterval($0) }
        return OAuthTokens(accessToken: tok.access_token, refreshToken: tok.refresh_token ?? refreshToken, expiresAt: expiresAt)
    }
}

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        if let a = macAnchor { return a }
        if let key = NSApp.keyWindow { return key }
        if let any = NSApp.windows.first { return any }
        return ASPresentationAnchor()
        #else
        // iOS: system chooses the active window if we return an empty anchor
        return ASPresentationAnchor()
        #endif
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    func sha256() throws -> Data {
        #if canImport(CryptoKit)
        return Data(CryptoKit.SHA256.hash(data: self))
        #else
        throw NSError(domain: "OAuthService", code: -10,
                      userInfo: [NSLocalizedDescriptionKey: "SHA256 requires CryptoKit, which is unavailable on this platform."])
        #endif
    }
}
