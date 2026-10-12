import Combine
import Foundation
import os

@MainActor
final class RelayAccountCoordinator: ObservableObject {
    private static let signposter = OSSignposter(logger: Logger(subsystem: "Relay", category: "AccountSignIn"))

    static let shared = RelayAccountCoordinator(
        service: RelayAccountService(),
        keychain: RelayAccountKeychainStore.shared,
        defaults: .standard,
        isAuthEnabled: RelayAccountConfig.isAuthEnabled,
        autoRestore: true
    )

    @Published private(set) var state: RelayAccountState = .signedOut
    @Published private(set) var relayAccountPro: Bool = false
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var currentUserEmail: String? = nil
    @Published private(set) var currentEntitlements: RelayAccountEntitlementsResponse? = nil
    @Published private(set) var cachedEntitlements: RelayAccountEntitlementsResponse? = nil
    @Published private(set) var lastMagicLinkVerifyURL: URL? = nil
    @Published private(set) var lastMagicLinkMessage: String? = nil
    @Published private(set) var lastMagicLinkRequestedAt: Date? = nil
    @Published private(set) var lastRefreshAt: Date? = nil
    @Published private(set) var lastErrorCode: Int? = nil
    @Published private(set) var lastErrorMessage: String? = nil
    @Published private(set) var heartbeatStatus = RelayAccountHeartbeatStatus()

    private let service: RelayAccountServicing
    private let keychain: RelayAccountTokenStore
    private let defaults: UserDefaults
    private let isAuthEnabled: Bool
    private let legacyLicenseKeyProvider: @MainActor () -> String?
    private let cachedEntitlementsKey = "relay_account_cached_entitlements"
    private let cachedRefreshAtKey = "relay_account_last_refresh_at"
    private let magicLinkCooldownSeconds: TimeInterval = 60
    private var startupTask: Task<Void, Never>?
    private var usageDiagnosticsCancellable: AnyCancellable?
    private var hasVerifiedSession = false
    private lazy var heartbeatReporter = RelayAccountHeartbeatReporter(
        service: service,
        isUsageDiagnosticsEnabled: { UsageDiagnosticsPreferences.shared.isEnabled },
        sessionToken: { [weak self] in self?.normalizedToken(self?.keychain.sessionToken) },
        isSessionVerified: { [weak self] in self?.hasVerifiedSession == true },
        statusChanged: { [weak self] status in self?.heartbeatStatus = status }
    )

    init(
        service: RelayAccountServicing,
        keychain: RelayAccountTokenStore,
        defaults: UserDefaults,
        isAuthEnabled: Bool,
        legacyLicenseKeyProvider: @escaping @MainActor () -> String? = {
#if os(macOS)
            LicenseCoordinator.shared.currentLicenseKey()
#else
            nil
#endif
        },
        autoRestore: Bool
    ) {
        self.service = service
        self.keychain = keychain
        self.defaults = defaults
        self.isAuthEnabled = isAuthEnabled
        self.legacyLicenseKeyProvider = legacyLicenseKeyProvider
        self.cachedEntitlements = Self.loadCachedEntitlements(from: defaults, key: cachedEntitlementsKey)
        self.lastRefreshAt = defaults.object(forKey: cachedRefreshAtKey) as? Date
        self.primeStateFromCachedEntitlementsIfPossible()
        self.usageDiagnosticsCancellable = UsageDiagnosticsPreferences.shared.$isEnabled.sink { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.heartbeatReporter.refreshEligibility()
            } else {
                self.heartbeatReporter.stop()
            }
        }

        if autoRestore, isAuthEnabled {
            startupTask = Task { [weak self] in
                await self?.restoreSessionIfNeeded()
            }
        }
    }

    deinit {
        startupTask?.cancel()
    }

    var isSignedIn: Bool {
        if case .signedIn = state {
            return true
        }
        return false
    }

    var displayedEntitlements: RelayAccountEntitlementsResponse? {
        currentEntitlements ?? cachedEntitlements
    }

    var supportsDebugTokenEntry: Bool {
        RelayAccountConfig.supportsDebugTokenEntry
    }

    func canRequestMagicLink(at date: Date = Date()) -> Bool {
        secondsUntilMagicLinkRequestAllowed(at: date) == 0
    }

    func secondsUntilMagicLinkRequestAllowed(at date: Date = Date()) -> Int {
        guard let lastMagicLinkRequestedAt else { return 0 }
        let elapsed = date.timeIntervalSince(lastMagicLinkRequestedAt)
        let remaining = magicLinkCooldownSeconds - elapsed
        return max(0, Int(remaining.rounded(.up)))
    }

    /// PKCE verifier for the in-flight sign-in link. Memory only: it never touches disk.
    private var pendingPKCEVerifier: String?

    func requestMagicLink(email: String) async {
        guard isAuthEnabled else { return }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            logAccount("Magic link request rejected: empty email input")
            state = .error(message: "Enter an email address first.")
            return
        }

        guard canRequestMagicLink() else {
            let secondsRemaining = secondsUntilMagicLinkRequestAllowed()
            state = .waitingForEmail(email: normalizedEmail)
            lastErrorCode = nil
            lastErrorMessage = "You can request another sign-in link in \(secondsRemaining) seconds."
            return
        }

        isBusy = true
        clearLastError()
        defer { isBusy = false }
        state = .sendingMagicLink
        logAccount("Requesting magic link for \(redactedEmail(normalizedEmail))")

        do {
            let verifier = PKCE.makeVerifier()
            let response = try await service.requestMagicLink(email: normalizedEmail, codeChallenge: PKCE.challenge(for: verifier))
            pendingPKCEVerifier = verifier
            lastMagicLinkRequestedAt = Date()
            lastMagicLinkVerifyURL = response.verifyURL
            lastMagicLinkMessage = response.message
            state = .waitingForEmail(email: normalizedEmail)
            logAccount("Magic link request succeeded for \(redactedEmail(normalizedEmail))")
        } catch {
            logAccount("Magic link request failed: \(userFacingMessage(for: error))")
            applyError(error, fallbackState: .error(message: userFacingMessage(for: error)))
        }
    }

    func restoreSessionIfNeeded() async {
        guard isAuthEnabled else {
            logAccount("Session restore skipped: auth disabled")
            clearResolvedAccountState(keepCachedEntitlements: true)
            state = .signedOut
            return
        }

        guard let token = normalizedToken(keychain.sessionToken) else {
            logAccount("Session restore skipped: no stored account token")
            clearResolvedAccountState(keepCachedEntitlements: true)
            state = .signedOut
            return
        }

        logAccount("Restoring Relay Account session from Keychain")
        state = .signingIn
        await refreshSession(using: token, invalidateOnFailure: true)
    }

    func refreshEntitlements() async {
        guard isAuthEnabled else { return }
        guard let token = normalizedToken(keychain.sessionToken) else {
            logAccount("Entitlement refresh skipped: no stored account token")
            clearResolvedAccountState(keepCachedEntitlements: true)
            state = .signedOut
            return
        }

        logAccount("Refreshing Relay Account entitlements")
        await refreshSession(using: token, invalidateOnFailure: false)
    }

    func completeSignIn(withToken token: String) async {
        guard isAuthEnabled else { return }
        guard let normalized = normalizedToken(token) else {
            logAccount("Sign-in rejected: callback/manual token was empty")
            state = .error(message: "Enter a Relay session token.")
            return
        }

        let signpostID = Self.signposter.makeSignpostID()
        let signpostState = Self.signposter.beginInterval("Complete Sign In", id: signpostID)
        defer { Self.signposter.endInterval("Complete Sign In", signpostState) }

        logAccount("Received Relay Account token via callback/manual flow; storing in Keychain")
        if !keychain.saveRelayAccountToken(normalized) {
            RelayDiagnosticsStore.shared.recordError(
                "Failed to persist Relay account session token", tag: "Keychain"
            )
        }
        state = .signingIn
        await refreshSession(using: normalized, invalidateOnFailure: true)
    }

    func logout() async {
        guard isAuthEnabled else { return }

        let token = normalizedToken(keychain.sessionToken)
        isBusy = true
        clearLastError()

        if let token {
            await deactivateLinkedLicenseIfNeeded(token: token)
            do {
                try await service.logout(token: token)
            } catch {
                applyDiagnosticError(error)
            }
        }

        clearStoredSession()
        clearResolvedAccountState(keepCachedEntitlements: false)
        state = .signedOut
        isBusy = false
    }

    /// Permanently deletes the server-side account, then signs out locally. On failure the
    /// session is kept so the user can retry.
    @discardableResult
    func deleteAccount() async -> Bool {
        guard isAuthEnabled, let token = normalizedToken(keychain.sessionToken) else { return false }

        isBusy = true
        clearLastError()
        defer { isBusy = false }

        do {
            try await service.deleteAccount(token: token)
        } catch {
            logAccount("Account deletion failed: \(userFacingMessage(for: error))")
            applyDiagnosticError(error)
            return false
        }

        clearStoredSession()
        clearResolvedAccountState(keepCachedEntitlements: false)
        state = .signedOut
        return true
    }

    func setApplicationActive(_ active: Bool) {
        heartbeatReporter.setApplicationActive(active)
    }

    func linkAppStoreSubscription(_ subscription: RelayPendingAppStoreSubscription) async throws {
        guard isAuthEnabled else { return }
        guard let token = normalizedToken(keychain.sessionToken) else {
            throw RelayAccountService.ServiceError(statusCode: 401, message: "Sign in to Relay Account to link this App Store subscription.")
        }

        isBusy = true
        clearLastError()
        defer { isBusy = false }

        logAccount("Linking App Store subscription \(subscription.originalTransactionId) to Relay Account")

        do {
            try await service.linkAppStoreSubscription(token: token, request: subscription.linkRequest)
            let entitlements = try await service.fetchEntitlements(token: token)
            applyAuthenticatedState(
                email: currentUserEmail ?? entitlements.user?.email,
                entitlements: entitlements
            )
        } catch {
            applyDiagnosticError(error)
            logAccount("App Store subscription link failed: \(userFacingMessage(for: error))")
            throw error
        }
    }

    func relinkLemonLicense(_ licenseKey: String) async throws {
        guard isAuthEnabled else { return }
        guard let token = normalizedToken(keychain.sessionToken) else {
            throw RelayAccountService.ServiceError(statusCode: 401, message: "Sign in to Relay Account to re-link this Lemon license.")
        }

        let normalizedLicenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLicenseKey.isEmpty else {
            throw RelayAccountService.ServiceError(statusCode: 400, message: "Enter the full Lemon license key.")
        }

        isBusy = true
        clearLastError()
        defer { isBusy = false }

        logAccount("Re-linking Lemon license \(redactedLicenseKey(normalizedLicenseKey)) to Relay Account")

        do {
            try await service.linkLegacyLicense(token: token, licenseKey: normalizedLicenseKey)
            let entitlements = try await service.fetchEntitlements(token: token)
            applyAuthenticatedState(
                email: currentUserEmail ?? entitlements.user?.email,
                entitlements: entitlements
            )
        } catch {
            applyDiagnosticError(error)
            logAccount("Lemon license re-link failed: \(userFacingMessage(for: error))")
            throw error
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard isAuthEnabled else { return }
        logAccount("Received URL open event: \(sanitizedURLDescription(url))")
        guard matchesSupportedCallbackURL(url) else {
            logAccount("Ignored URL open event: unsupported callback shape")
            return
        }
        logAccount("Matched Relay Account auth callback")
        Self.signposter.emitEvent("Auth Callback Matched")
        if let code = codeFromIncomingURL(url) {
            guard let verifier = pendingPKCEVerifier else {
                logAccount("Auth callback failed: no pending PKCE verifier")
                state = .error(message: "Request a new sign-in link from this copy of Relay, then open it on this computer.")
                return
            }
            pendingPKCEVerifier = nil
            Task {
                do {
                    let token = try await service.exchangeAuthCode(code: code, codeVerifier: verifier)
                    await completeSignIn(withToken: token)
                } catch {
                    logAccount("Auth code exchange failed: \(userFacingMessage(for: error))")
                    applyError(error, fallbackState: .error(message: userFacingMessage(for: error)))
                }
            }
            return
        }
        guard let token = tokenFromIncomingURL(url) else {
            logAccount("Auth callback failed: token query item missing")
            state = .error(message: "Relay sign-in link is missing a session token.")
            return
        }
        logAccount("Auth callback contained a token; beginning session validation")

        Task {
            await completeSignIn(withToken: token)
        }
    }

    func diagnosticsSnapshot() -> RelayAccountDiagnosticsSnapshot {
        let entitlements = displayedEntitlements
        return RelayAccountDiagnosticsSnapshot(
            authEnabled: isAuthEnabled,
            signedIn: isSignedIn,
            currentEmail: currentUserEmail ?? displayedEntitlements?.user?.email,
            relayAccountPro: relayAccountPro,
            sourceSubscription: entitlements?.sources.subscription ?? false,
            sourceLicense: entitlements?.sources.license ?? false,
            lastRefreshAt: lastRefreshAt,
            lastErrorCode: lastErrorCode,
            lastErrorMessage: lastErrorMessage
        )
    }

    private func refreshSession(using token: String, invalidateOnFailure: Bool) async {
        isBusy = true
        clearLastError()
        defer { isBusy = false }
        logAccount("Validating Relay Account session")

        let signpostID = Self.signposter.makeSignpostID()
        let signpostState = Self.signposter.beginInterval("Refresh Session", id: signpostID)
        defer { Self.signposter.endInterval("Refresh Session", signpostState) }

        do {
            let validateState = Self.signposter.beginInterval("Validate Session", id: signpostID)
            let sessionPayload = try await service.validateSession(token: token)
            Self.signposter.endInterval("Validate Session", validateState)
            guard sessionPayload.authenticated else {
                throw RelayAccountService.ServiceError(statusCode: 401, message: "Your Relay Account session has expired. Sign in again.")
            }
            logAccount("Session verification succeeded")

            let loadAccountState = Self.signposter.beginInterval("Load Account Payload", id: signpostID)
            let accountPayload = try await loadAccountPayload(token: token, preferred: sessionPayload)
            Self.signposter.endInterval("Load Account Payload", loadAccountState)

            logAccount("Fetching Relay Account entitlements")
            let fetchEntitlementsState = Self.signposter.beginInterval("Fetch Entitlements", id: signpostID)
            var entitlementsPayload = try await service.fetchEntitlements(token: token)
            Self.signposter.endInterval("Fetch Entitlements", fetchEntitlementsState)

            let linkLegacyState = Self.signposter.beginInterval("Link Legacy License", id: signpostID)
            entitlementsPayload = try await linkLegacyLicenseIfNeeded(token: token, entitlements: entitlementsPayload)
            Self.signposter.endInterval("Link Legacy License", linkLegacyState)

            let activateLinkedState = Self.signposter.beginInterval("Activate Linked License", id: signpostID)
            entitlementsPayload = await activateLinkedLicenseIfNeeded(token: token, entitlements: entitlementsPayload)
            Self.signposter.endInterval("Activate Linked License", activateLinkedState)

            let applyState = Self.signposter.beginInterval("Apply Authenticated State", id: signpostID)
            applyAuthenticatedState(
                email: accountPayload.user?.email ?? sessionPayload.user?.email,
                entitlements: entitlementsPayload
            )
            Self.signposter.endInterval("Apply Authenticated State", applyState)
        } catch {
            if shouldInvalidateSession(for: error, invalidateOnFailure: invalidateOnFailure) {
                clearStoredSession()
                clearResolvedAccountState(keepCachedEntitlements: true)
                applyDiagnosticError(error)
                logAccount("Session validation failed with invalid/expired token: \(userFacingMessage(for: error))")
                state = .error(message: userFacingMessage(for: error))
                return
            }

            let email = currentUserEmail ?? displayedEntitlements?.user?.email
            if let email {
                state = .signedIn(email: email, pro: relayAccountPro)
            } else {
                state = .error(message: userFacingMessage(for: error))
            }
            applyDiagnosticError(error)
            logAccount("Relay Account refresh failed: \(userFacingMessage(for: error))")
        }
    }

    private func loadAccountPayload(token: String, preferred sessionPayload: RelayAccountSessionResponse) async throws -> RelayAccountSessionResponse {
        if let user = sessionPayload.user, !user.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sessionPayload
        }
        return try await service.fetchAccount(token: token)
    }

    private func linkLegacyLicenseIfNeeded(
        token: String,
        entitlements: RelayAccountEntitlementsResponse
    ) async throws -> RelayAccountEntitlementsResponse {
        let existingLicenseKey = normalizedToken(legacyLicenseKeyProvider())
        guard let existingLicenseKey else {
            logAccount("No stored legacy license key available for account linking")
            return entitlements
        }

        if entitlements.sources.license {
            guard linkedLemonLicenseNeedsRepair(in: entitlements) else {
                logAccount("Relay Account already has a linked legacy license source")
                return entitlements
            }

            logAccount("Relay Account has a legacy linked Lemon license without activation sync data; attempting silent repair with stored key \(redactedLicenseKey(existingLicenseKey))")
        } else {
            logAccount("Attempting to link stored legacy license \(redactedLicenseKey(existingLicenseKey))")
        }

        do {
            try await service.linkLegacyLicense(token: token, licenseKey: existingLicenseKey)
            logAccount("Stored legacy license linked successfully; refreshing entitlements")
            return try await service.fetchEntitlements(token: token)
        } catch {
            applyDiagnosticError(error)
            logAccount("Legacy license link failed: \(userFacingMessage(for: error))")
            return entitlements
        }
    }

    private func activateLinkedLicenseIfNeeded(
        token: String,
        entitlements: RelayAccountEntitlementsResponse
    ) async -> RelayAccountEntitlementsResponse {
        guard RelayLicensingConfig.isDirectMacDistribution else {
            return entitlements
        }

        guard entitlements.sources.license else {
            logAccount("Skipping linked license activation: no linked license source on account")
            return entitlements
        }

#if os(macOS)
        if let existingLicenseKey = normalizedToken(legacyLicenseKeyProvider()) {
            logAccount("Skipping linked license activation: this Mac already has a direct license \(redactedLicenseKey(existingLicenseKey))")
            return entitlements
        }

        guard let request = LicenseCoordinator.shared.relayAccountActivationRequest() else {
            logAccount("Skipping linked license activation: no macOS activation context available")
            return entitlements
        }

        do {
            let response = try await service.activateLinkedLicense(token: token, request: request)
            let responseSummary: String
            if let entitlement = response.entitlement {
                let usage = entitlement.activationUsageCount.map(String.init) ?? "nil"
                let limit = entitlement.activationLimit.map(String.init) ?? "nil"
                responseSummary = "license=\(entitlement.licenseKeyMasked), status=\(entitlement.statusRaw), usage=\(usage), limit=\(limit)"
            } else {
                responseSummary = "entitlement=nil"
            }
            logAccount("Linked license activation completed; activated=\(response.activated ? "true" : "false"), \(responseSummary)")
            return try await service.fetchEntitlements(token: token)
        } catch {
            applyDiagnosticError(error)
            logAccount("Linked license activation failed: \(userFacingMessage(for: error))")
            return entitlements
        }
#else
        return entitlements
#endif
    }

    private func deactivateLinkedLicenseIfNeeded(token: String) async {
        guard RelayLicensingConfig.isDirectMacDistribution else {
            return
        }

        guard displayedEntitlements?.sources.license == true else {
            logAccount("Skipping linked license deactivation: no linked license source on account")
            return
        }

#if os(macOS)
        if let existingLicenseKey = normalizedToken(legacyLicenseKeyProvider()) {
            logAccount("Skipping linked license deactivation: this Mac has a direct license \(redactedLicenseKey(existingLicenseKey))")
            return
        }

        guard let request = LicenseCoordinator.shared.relayAccountDeactivationRequest() else {
            logAccount("Skipping linked license deactivation: no macOS deactivation context available")
            return
        }

        do {
            let response = try await service.deactivateLinkedLicense(token: token, request: request)
            let responseSummary: String
            if let entitlement = response.entitlement {
                let usage = entitlement.activationUsageCount.map(String.init) ?? "nil"
                let limit = entitlement.activationLimit.map(String.init) ?? "nil"
                responseSummary = "license=\(entitlement.licenseKeyMasked), status=\(entitlement.statusRaw), usage=\(usage), limit=\(limit)"
            } else {
                responseSummary = "entitlement=nil"
            }
            logAccount("Linked license deactivation completed; deactivated=\(response.deactivated ? "true" : "false"), \(responseSummary)")
        } catch {
            applyDiagnosticError(error)
            logAccount("Linked license deactivation failed: \(userFacingMessage(for: error))")
        }
#endif
    }

    private func applyAuthenticatedState(email: String?, entitlements: RelayAccountEntitlementsResponse) {
        let resolvedPro = RelayAccountEntitlementEvaluator.resolvePro(from: entitlements)
        let resolvedEmail = email ?? entitlements.user?.email ?? "Unknown Email"
        logAccount("Entitlement summary: authenticated=\(entitlements.authenticated ? "true" : "false"), pro=\(entitlements.pro ? "true" : "false"), sources=subscription:\(entitlements.sources.subscription ? "true" : "false"),license:\(entitlements.sources.license ? "true" : "false"), subscriptions=\(entitlementSubscriptionSummary(entitlements.subscriptions)), licenses=\(entitlementLicenseSummary(entitlements.licenses))")
        currentUserEmail = resolvedEmail
        currentEntitlements = entitlements
        hasVerifiedSession = true
        relayAccountPro = resolvedPro
        lastRefreshAt = Date()
        lastMagicLinkVerifyURL = nil
        clearLastError()
        state = .signedIn(email: resolvedEmail, pro: resolvedPro)
        logAccount("Signed in as \(redactedEmail(resolvedEmail)); relayAccountPro=\(resolvedPro ? "true" : "false")")

        cacheEntitlements(entitlements)
        defaults.set(lastRefreshAt, forKey: cachedRefreshAtKey)
        heartbeatReporter.refreshEligibility()
    }

    private func cacheEntitlements(_ entitlements: RelayAccountEntitlementsResponse) {
        cachedEntitlements = entitlements
        if let data = try? makeRelayAccountJSONEncoder().encode(entitlements) {
            defaults.set(data, forKey: cachedEntitlementsKey)
        }
    }

    private func primeStateFromCachedEntitlementsIfPossible() {
        guard isAuthEnabled,
              let cachedEntitlements,
              let token = normalizedToken(keychain.sessionToken),
              !token.isEmpty else {
            return
        }

        let resolvedPro = RelayAccountEntitlementEvaluator.resolvePro(from: cachedEntitlements)
        currentEntitlements = cachedEntitlements
        relayAccountPro = resolvedPro

        if let cachedEmail = cachedEntitlements.user?.email {
            currentUserEmail = cachedEmail
            state = .signedIn(email: cachedEmail, pro: resolvedPro)
        }
    }

    private func clearStoredSession() {
        logAccount("Clearing stored Relay Account token")
        heartbeatReporter.stop()
        hasVerifiedSession = false
        if !keychain.deleteRelayAccountToken() {
            RelayDiagnosticsStore.shared.recordError(
                "Failed to clear Relay account session token", tag: "Keychain"
            )
        }
    }

    private func clearResolvedAccountState(keepCachedEntitlements: Bool) {
        hasVerifiedSession = false
        relayAccountPro = false
        currentUserEmail = nil
        currentEntitlements = nil
        lastMagicLinkVerifyURL = nil
        lastMagicLinkMessage = nil
        lastMagicLinkRequestedAt = nil
        if !keepCachedEntitlements {
            cachedEntitlements = nil
            defaults.removeObject(forKey: cachedEntitlementsKey)
            defaults.removeObject(forKey: cachedRefreshAtKey)
            lastRefreshAt = nil
        }
    }

    private func clearLastError() {
        lastErrorCode = nil
        lastErrorMessage = nil
    }

    private func applyError(_ error: Error, fallbackState: RelayAccountState) {
        applyDiagnosticError(error)
        state = fallbackState
    }

    private func applyDiagnosticError(_ error: Error) {
        if let serviceError = error as? RelayAccountService.ServiceError {
            lastErrorCode = serviceError.statusCode
            lastErrorMessage = serviceError.message
        } else {
            lastErrorCode = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let serviceError = error as? RelayAccountService.ServiceError {
            return serviceError.message
        }
        return error.localizedDescription
    }

    private func shouldInvalidateSession(for error: Error, invalidateOnFailure: Bool) -> Bool {
        _ = invalidateOnFailure
        guard let serviceError = error as? RelayAccountService.ServiceError else { return false }
        return serviceError.isUnauthorized
    }

    private func normalizedToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func codeFromIncomingURL(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func tokenFromIncomingURL(_ url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           let normalized = normalizedToken(token) {
            return normalized
        }

        return nil
    }

    private func matchesSupportedCallbackURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "relay" else { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host == "auth" && path == "/callback"
    }

    private func logAccount(_ message: String) {
        print("[RelayAccount] \(message)")
    }

    private func sanitizedURLDescription(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "\(url.scheme ?? "unknown")://<unparseable>"
        }

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.map { item in
                if ["token", "code"].contains(item.name.lowercased()) {
                    return URLQueryItem(name: item.name, value: "<redacted>")
                }
                return item
            }
        }

        return components.string ?? "\(url.scheme ?? "unknown")://<invalid>"
    }

    private func redactedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "<redacted-email>" }

        let local = parts[0]
        let domain = parts[1]
        let visiblePrefix = local.prefix(1)
        return "\(visiblePrefix)***@\(domain)"
    }

    private func entitlementSubscriptionSummary(_ subscriptions: [RelayAccountSubscription]) -> String {
        guard !subscriptions.isEmpty else { return "none" }
        return subscriptions.map { subscription in
            "\(subscription.provider):\(subscription.status)"
        }.joined(separator: ", ")
    }

    private func entitlementLicenseSummary(_ licenses: [RelayAccountLinkedLicense]) -> String {
        guard !licenses.isEmpty else { return "none" }
        return licenses.map { license in
            let usage = license.activationUsageCount.map(String.init) ?? "nil"
            let limit = license.activationLimit.map(String.init) ?? "nil"
            return "\(license.licenseKeyMasked):\(license.status):usage=\(usage):limit=\(limit)"
        }.joined(separator: ", ")
    }

    private func linkedLemonLicenseNeedsRepair(in entitlements: RelayAccountEntitlementsResponse) -> Bool {
        entitlements.licenses.contains { license in
            let source = license.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let isLemon = source.contains("lemonsqueezy") || source.contains("lemon_squeezy") || source.contains("lemon-squeezy")
            return isLemon && (license.activationUsageCount == nil || license.activationLimit == nil)
        }
    }

    private func redactedLicenseKey(_ licenseKey: String) -> String {
        let suffix = String(licenseKey.suffix(6))
        return "••••-••••-\(suffix)"
    }

    private static func loadCachedEntitlements(from defaults: UserDefaults, key: String) -> RelayAccountEntitlementsResponse? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? makeRelayAccountJSONDecoder().decode(RelayAccountEntitlementsResponse.self, from: data)
    }
}
