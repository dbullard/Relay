import XCTest
@testable import Relay

@MainActor
final class RelayAccountTests: XCTestCase {

    func test_entitlementsDecoding_supportsSnakeCaseSubscriptionFields() throws {
        let payload = """
        {
          "pro": false,
          "authenticated": true,
          "sources": {
            "subscription": false,
            "license": true
          },
          "user": {
            "id": "user_123",
            "email": "person@example.com"
          },
          "subscriptions": [
            {
              "provider": "lemon_squeezy",
              "status": "trialing",
              "current_period_end": "2026-05-23T12:34:56Z"
            }
          ],
          "licenses": [
            {
              "license_key_masked": "••••-••••-2AF37E",
              "customer_email": "person@example.com",
              "product_name": "Relay Pro",
              "variant_name": "Relay Pro Yearly",
              "status": "active",
              "activation_usage_count": 1,
              "activation_limit": 3,
              "expires_at": null,
              "source": "lemonsqueezy",
              "linked_at": "2026-05-23T12:34:56Z",
              "last_validated_at": "2026-05-23T12:34:56Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try makeRelayAccountJSONDecoder().decode(RelayAccountEntitlementsResponse.self, from: payload)

        XCTAssertEqual(decoded.user?.email, "person@example.com")
        XCTAssertTrue(decoded.sources.license)
        XCTAssertEqual(decoded.subscriptions.first?.provider, "lemon_squeezy")
        XCTAssertEqual(decoded.subscriptions.first?.status, "trialing")
        XCTAssertNotNil(decoded.subscriptions.first?.currentPeriodEnd)
        XCTAssertEqual(decoded.licenses.first?.licenseKeyMasked, "••••-••••-2AF37E")
        XCTAssertEqual(decoded.licenses.first?.activationUsageCount, 1)
        XCTAssertEqual(decoded.licenses.first?.activationLimit, 3)
    }

    func test_magicLinkResponse_decodesVerifyURL() throws {
        let payload = """
        {
          "ok": true,
          "message": "Magic link created",
          "verifyUrl": "https://project-he33k.vercel.app/api/auth/verify?token=abc123"
        }
        """.data(using: .utf8)!

        let decoded = try makeRelayAccountJSONDecoder().decode(RelayAccountMagicLinkResponse.self, from: payload)

        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.message, "Magic link created")
        XCTAssertEqual(decoded.verifyURL?.absoluteString, "https://project-he33k.vercel.app/api/auth/verify?token=abc123")
    }

    func test_callbackState_supportsWaitingForEmailAndSigningIn() {
        XCTAssertEqual(RelayAccountState.waitingForEmail(email: "person@example.com"), .waitingForEmail(email: "person@example.com"))
        XCTAssertEqual(RelayAccountState.signingIn, .signingIn)
        XCTAssertEqual(RelayAccountState.signedIn(email: "person@example.com", pro: true), .signedIn(email: "person@example.com", pro: true))
    }

    func test_effectivePro_isLegacyOrRelayAccount() {
        XCTAssertTrue(SubscriptionManager.resolveEffectivePro(legacyLicensePro: true, relayAccountPro: false, relayAccountAuthEnabled: true))
        XCTAssertTrue(SubscriptionManager.resolveEffectivePro(legacyLicensePro: false, relayAccountPro: true, relayAccountAuthEnabled: true))
        XCTAssertFalse(SubscriptionManager.resolveEffectivePro(legacyLicensePro: false, relayAccountPro: true, relayAccountAuthEnabled: false))
        XCTAssertFalse(SubscriptionManager.resolveEffectivePro(legacyLicensePro: false, relayAccountPro: false, relayAccountAuthEnabled: true))
    }

    func test_hasActiveLinkedAppStoreSubscription_requiresActiveStatus() {
        let expiredAppStoreOnly = RelayAccountEntitlementsResponse(
            pro: false,
            authenticated: true,
            user: RelayAccountUser(id: "user_123", email: "person@example.com"),
            sources: RelayEntitlementSources(subscription: false, license: false),
            subscriptions: [
                RelayAccountSubscription(
                    provider: "app_store",
                    status: "expired",
                    currentPeriodEnd: nil
                )
            ],
            licenses: []
        )

        let activeAppStore = RelayAccountEntitlementsResponse(
            pro: true,
            authenticated: true,
            user: RelayAccountUser(id: "user_123", email: "person@example.com"),
            sources: RelayEntitlementSources(subscription: true, license: false),
            subscriptions: [
                RelayAccountSubscription(
                    provider: "app_store",
                    status: "active",
                    currentPeriodEnd: nil
                )
            ],
            licenses: []
        )

        XCTAssertFalse(SubscriptionManager.hasActiveLinkedAppStoreSubscription(expiredAppStoreOnly))
        XCTAssertTrue(SubscriptionManager.hasActiveLinkedAppStoreSubscription(activeAppStore))
    }

    func test_shouldTrustRelayAccountAppStoreEntitlement_requiresLocalEntitlementOnOriginalLinkedDevice() {
        XCTAssertFalse(
            SubscriptionManager.shouldTrustRelayAccountAppStoreEntitlement(
                legacyLicensePro: false,
                relayAccountProvider: .appStore,
                hasLinkedLocalAppStorePurchase: true
            )
        )

        XCTAssertTrue(
            SubscriptionManager.shouldTrustRelayAccountAppStoreEntitlement(
                legacyLicensePro: true,
                relayAccountProvider: .appStore,
                hasLinkedLocalAppStorePurchase: true
            )
        )

        XCTAssertTrue(
            SubscriptionManager.shouldTrustRelayAccountAppStoreEntitlement(
                legacyLicensePro: false,
                relayAccountProvider: .appStore,
                hasLinkedLocalAppStorePurchase: false
            )
        )

        XCTAssertTrue(
            SubscriptionManager.shouldTrustRelayAccountAppStoreEntitlement(
                legacyLicensePro: false,
                relayAccountProvider: .lemonSqueezy,
                hasLinkedLocalAppStorePurchase: true
            )
        )
    }

    func test_shouldTrustRelayAccountAppStoreEntitlement_blocksStaleRestoreOnceLocalPurchaseHasEverBeenSeen() {
        let hadLocalPurchase = true
        let localEntitlementActive = false

        XCTAssertFalse(
            SubscriptionManager.shouldTrustRelayAccountAppStoreEntitlement(
                legacyLicensePro: localEntitlementActive,
                relayAccountProvider: .appStore,
                hasLinkedLocalAppStorePurchase: hadLocalPurchase
            )
        )
    }

    func test_appStoreLinking_needsSeparateObservedAndAccountLinkedTransactionState() {
        let observedOriginalTransactionId = "2000001176185499"
        let newlyPurchasedOriginalTransactionId = "2000001177000001"

        XCTAssertNotEqual(observedOriginalTransactionId, newlyPurchasedOriginalTransactionId)
        XCTAssertTrue(
            SubscriptionManager.shouldTrustRelayAccountAppStoreEntitlement(
                legacyLicensePro: false,
                relayAccountProvider: .appStore,
                hasLinkedLocalAppStorePurchase: false
            )
        )
    }

    func test_subscriptionStatuses_treatActiveTrialingAndOnTrialAsPro() {
        let statuses = ["active", "trialing", "on_trial", "billing_grace_period"]
        for status in statuses {
            let payload = RelayAccountEntitlementsResponse(
                pro: false,
                authenticated: true,
                user: RelayAccountUser(id: "user_123", email: "person@example.com"),
                sources: RelayEntitlementSources(subscription: false, license: false),
                subscriptions: [RelayAccountSubscription(provider: "lemon_squeezy", status: status, currentPeriodEnd: nil)],
                licenses: []
            )
            XCTAssertTrue(RelayAccountEntitlementEvaluator.resolvePro(from: payload), "Expected \(status) to resolve to Pro.")
        }
    }

    func test_appStoreLinkRequest_roundTripsISO8601ExpirationDate() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)
        let request = RelayAccountLinkAppStoreSubscriptionRequest(
            originalTransactionId: "original-123",
            transactionId: "tx-456",
            productId: "relay.pro.subscription",
            expirationDate: referenceDate,
            isActive: true
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RelayAccountLinkAppStoreSubscriptionRequest.self, from: encoded)

        XCTAssertEqual(decoded.originalTransactionId, "original-123")
        XCTAssertEqual(decoded.transactionId, "tx-456")
        XCTAssertEqual(decoded.productId, "relay.pro.subscription")
        let decodedExpiration = try XCTUnwrap(decoded.expirationDate)
        XCTAssertEqual(decodedExpiration.timeIntervalSince1970, referenceDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(decoded.isActive)
    }

    func test_licenseSourceTreatsEntitlementsAsPro() {
        let payload = RelayAccountEntitlementsResponse(
            pro: false,
            authenticated: true,
            user: RelayAccountUser(id: "user_123", email: "person@example.com"),
            sources: RelayEntitlementSources(subscription: false, license: true),
            subscriptions: [],
            licenses: []
        )
        XCTAssertTrue(RelayAccountEntitlementEvaluator.resolvePro(from: payload))
    }

    @MainActor
    func test_restoreSessionIfNeeded_withoutToken_staysSignedOut() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockRelayAccountService()
        let keychain = MockRelayAccountTokenStore()
        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        await coordinator.restoreSessionIfNeeded()

        XCTAssertEqual(coordinator.state, RelayAccountState.signedOut)
        XCTAssertFalse(coordinator.relayAccountPro)
    }

    @MainActor
    func test_init_primesRelayAccountProFromCachedEntitlementsWhenTokenExists() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let currentPeriodEnd = Date(timeIntervalSince1970: 1_780_000_000)
        let cachedEntitlements = RelayAccountEntitlementsResponse(
            pro: true,
            authenticated: true,
            user: RelayAccountUser(id: "user_123", email: "person@example.com"),
            sources: RelayEntitlementSources(subscription: true, license: false),
            subscriptions: [RelayAccountSubscription(provider: "app_store", status: "active", currentPeriodEnd: currentPeriodEnd)],
            licenses: []
        )
        let encoded = try XCTUnwrap(try? makeRelayAccountJSONEncoder().encode(cachedEntitlements))
        defaults.set(encoded, forKey: "relay_account_cached_entitlements")

        let service = MockRelayAccountService()
        let keychain = MockRelayAccountTokenStore()
        keychain.sessionToken = "token_123"

        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        XCTAssertTrue(coordinator.relayAccountPro)
        XCTAssertEqual(coordinator.currentUserEmail, "person@example.com")
        let cachedCurrentPeriodEnd = try XCTUnwrap(coordinator.currentEntitlements?.subscriptions.first?.currentPeriodEnd)
        XCTAssertEqual(cachedCurrentPeriodEnd.timeIntervalSince1970, currentPeriodEnd.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(coordinator.state, .signedIn(email: "person@example.com", pro: true))
    }

    @MainActor
    func test_restoreSessionIfNeeded_unauthorizedToken_clearsStoredToken() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockRelayAccountService()
        service.validateSessionError = RelayAccountService.ServiceError(
            statusCode: 401,
            message: "expired"
        )

        let keychain = MockRelayAccountTokenStore()
        keychain.sessionToken = "token_123"

        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        await coordinator.completeSignIn(withToken: "token_123")

        XCTAssertNil(keychain.sessionToken)
        XCTAssertEqual(coordinator.state, RelayAccountState.error(message: "expired"))
    }

    @MainActor
    func test_logout_clearsKeychainTokenEvenWhenRequestFails() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockRelayAccountService()
        service.logoutError = RelayAccountService.ServiceError(
            statusCode: 500,
            message: "logout failed"
        )

        let keychain = MockRelayAccountTokenStore()
        keychain.sessionToken = "token_123"

        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        await coordinator.logout()

        XCTAssertNil(keychain.sessionToken)
        XCTAssertEqual(coordinator.state, RelayAccountState.signedOut)
    }

    @MainActor
    func test_logout_deactivatesLinkedLicenseWhenNoDirectLicenseExists() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockRelayAccountService()
        service.includesLinkedLicense = true

        let keychain = MockRelayAccountTokenStore()
        keychain.sessionToken = "token_123"

        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        await coordinator.completeSignIn(withToken: "token_123")
        await coordinator.logout()

        XCTAssertEqual(service.deactivateLinkedLicenseRequests.count, 1)
        XCTAssertNil(keychain.sessionToken)
        XCTAssertEqual(coordinator.state, RelayAccountState.signedOut)
    }

    @MainActor
    func test_handleIncomingURL_missingToken_setsError() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let coordinator = RelayAccountCoordinator(
            service: MockRelayAccountService(),
            keychain: MockRelayAccountTokenStore(),
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        coordinator.handleIncomingURL(URL(string: "relay://auth/callback")!)

        XCTAssertEqual(coordinator.state, RelayAccountState.error(message: "Relay sign-in link is missing a session token."))
    }

    @MainActor
    func test_handleIncomingURL_validCallback_signsIn() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let keychain = MockRelayAccountTokenStore()
        let service = MockRelayAccountService()
        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        coordinator.handleIncomingURL(URL(string: "relay://auth/callback?token=jwt_123")!)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(keychain.sessionToken, "jwt_123")
        XCTAssertEqual(coordinator.state, RelayAccountState.signedIn(email: "person@example.com", pro: true))
        XCTAssertTrue(coordinator.relayAccountPro)
    }

    @MainActor
    func test_handleIncomingURL_codeCallback_exchangesWithPKCEVerifier() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let keychain = MockRelayAccountTokenStore()
        let service = MockRelayAccountService()
        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        await coordinator.requestMagicLink(email: "person@example.com")
        let challenge = try? XCTUnwrap(service.requestedChallenges.first ?? nil)
        coordinator.handleIncomingURL(URL(string: "relay://auth/callback?code=one-time")!)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(service.exchangeRequests.count, 1)
        XCTAssertEqual(service.exchangeRequests.first?.code, "one-time")
        XCTAssertEqual(PKCE.challenge(for: service.exchangeRequests.first?.verifier ?? ""), challenge)
        XCTAssertEqual(keychain.sessionToken, "exchanged-token")
    }

    @MainActor
    func test_handleIncomingURL_codeCallbackWithoutPendingVerifier_setsError() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockRelayAccountService()
        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: MockRelayAccountTokenStore(),
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        coordinator.handleIncomingURL(URL(string: "relay://auth/callback?code=one-time")!)

        XCTAssertTrue(service.exchangeRequests.isEmpty)
        if case .error = coordinator.state {} else { XCTFail("expected error state") }
    }

    @MainActor
    func test_deleteAccount_success_clearsSessionAndSignsOut() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let keychain = MockRelayAccountTokenStore()
        keychain.sessionToken = "jwt_123"
        let service = MockRelayAccountService()
        let coordinator = RelayAccountCoordinator(
            service: service, keychain: keychain, defaults: defaults,
            isAuthEnabled: true, legacyLicenseKeyProvider: { nil }, autoRestore: false
        )

        let ok = await coordinator.deleteAccount()

        XCTAssertTrue(ok)
        XCTAssertEqual(service.deleteAccountTokens, ["jwt_123"])
        XCTAssertNil(keychain.sessionToken)
        XCTAssertEqual(coordinator.state, RelayAccountState.signedOut)
    }

    @MainActor
    func test_deleteAccount_failure_keepsSessionAndSetsError() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let keychain = MockRelayAccountTokenStore()
        keychain.sessionToken = "jwt_123"
        let service = MockRelayAccountService()
        service.deleteAccountError = RelayAccountService.ServiceError(statusCode: 500, message: "boom")
        let coordinator = RelayAccountCoordinator(
            service: service, keychain: keychain, defaults: defaults,
            isAuthEnabled: true, legacyLicenseKeyProvider: { nil }, autoRestore: false
        )

        let ok = await coordinator.deleteAccount()

        XCTAssertFalse(ok)
        XCTAssertEqual(keychain.sessionToken, "jwt_123")
        XCTAssertEqual(coordinator.lastErrorMessage, "boom")
    }

    @MainActor
    func test_successfulSignIn_linksStoredLegacyLicense() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockRelayAccountService()
        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: MockRelayAccountTokenStore(),
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { "RELAY-LEGACY-2AF37E" },
            autoRestore: false
        )

        await coordinator.completeSignIn(withToken: "jwt_123")

        XCTAssertEqual(service.linkedLicenseKeys, ["RELAY-LEGACY-2AF37E"])
        XCTAssertEqual(coordinator.state, RelayAccountState.signedIn(email: "person@example.com", pro: true))
    }

    @MainActor
    func test_successfulSignIn_activatesLinkedLicenseWhenNoDirectLicenseExists() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockRelayAccountService()
        service.includesLinkedLicense = true
        let coordinator = RelayAccountCoordinator(
            service: service,
            keychain: MockRelayAccountTokenStore(),
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        await coordinator.completeSignIn(withToken: "jwt_123")

        XCTAssertEqual(service.activateLinkedLicenseRequests.count, 1)
        XCTAssertEqual(coordinator.state, RelayAccountState.signedIn(email: "person@example.com", pro: true))
    }

    @MainActor
    func test_completeSignIn_keychainSaveFails_reportsKeychainError() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let keychain = MockRelayAccountTokenStore()
        keychain.shouldFailSave = true

        let coordinator = RelayAccountCoordinator(
            service: MockRelayAccountService(),
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        let before = RelayDiagnosticsStore.shared.recentErrorsSummary()
        await coordinator.completeSignIn(withToken: "token_123")

        XCTAssertNotEqual(RelayDiagnosticsStore.shared.recentErrorsSummary(), before)
        XCTAssertTrue(
            RelayDiagnosticsStore.shared.recentErrorsSummary()
                .contains("Failed to persist Relay account session token")
        )
    }

    @MainActor
    func test_logout_keychainDeleteFails_reportsKeychainError() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let keychain = MockRelayAccountTokenStore()
        keychain.sessionToken = "token_123"
        keychain.shouldFailDelete = true

        let coordinator = RelayAccountCoordinator(
            service: MockRelayAccountService(),
            keychain: keychain,
            defaults: defaults,
            isAuthEnabled: true,
            legacyLicenseKeyProvider: { nil },
            autoRestore: false
        )

        let before = RelayDiagnosticsStore.shared.recentErrorsSummary()
        await coordinator.logout()

        XCTAssertNotEqual(RelayDiagnosticsStore.shared.recentErrorsSummary(), before)
        XCTAssertTrue(
            RelayDiagnosticsStore.shared.recentErrorsSummary()
                .contains("Failed to clear Relay account session token")
        )
    }
}

private final class MockRelayAccountTokenStore: RelayAccountTokenStore {
    var sessionToken: String?
    var shouldFailSave = false
    var shouldFailDelete = false

    @discardableResult
    func saveRelayAccountToken(_ token: String) -> Bool {
        guard !shouldFailSave else { return false }
        sessionToken = token
        return true
    }

    func loadRelayAccountToken() -> String? {
        sessionToken
    }

    @discardableResult
    func deleteRelayAccountToken() -> Bool {
        guard !shouldFailDelete else { return false }
        sessionToken = nil
        return true
    }
}

private final class MockRelayAccountService: RelayAccountServicing {
    var validateSessionError: Error?
    var logoutError: Error?
    var linkedLicenseKeys: [String] = []
    var includesLinkedLicense = false
    var activateLinkedLicenseRequests: [RelayAccountActivateLinkedLicenseRequest] = []
    var deactivateLinkedLicenseRequests: [RelayAccountDeactivateLinkedLicenseRequest] = []
    var linkedAppStoreSubscriptions: [RelayAccountLinkAppStoreSubscriptionRequest] = []

    var exchangeRequests: [(code: String, verifier: String)] = []
    var requestedChallenges: [String?] = []

    func exchangeAuthCode(code: String, codeVerifier: String) async throws -> String {
        exchangeRequests.append((code, codeVerifier))
        return "exchanged-token"
    }

    func requestMagicLink(email: String, codeChallenge: String?) async throws -> RelayAccountMagicLinkResponse {
        requestedChallenges.append(codeChallenge)
        return RelayAccountMagicLinkResponse(ok: true, message: "Magic link created", verifyURL: nil)
    }

    func validateSession(token: String) async throws -> RelayAccountSessionResponse {
        if let validateSessionError {
            throw validateSessionError
        }

        return RelayAccountSessionResponse(
            authenticated: true,
            user: RelayAccountUser(id: "user_123", email: "person@example.com")
        )
    }

    func fetchAccount(token: String) async throws -> RelayAccountSessionResponse {
        RelayAccountSessionResponse(
            authenticated: true,
            user: RelayAccountUser(id: "user_123", email: "person@example.com")
        )
    }

    func fetchEntitlements(token: String) async throws -> RelayAccountEntitlementsResponse {
        let hasLinkedLicense = includesLinkedLicense || !linkedLicenseKeys.isEmpty
        return RelayAccountEntitlementsResponse(
            pro: true,
            authenticated: true,
            user: RelayAccountUser(id: "user_123", email: "person@example.com"),
            sources: RelayEntitlementSources(subscription: true, license: hasLinkedLicense),
            subscriptions: [RelayAccountSubscription(provider: "lemon_squeezy", status: "active", currentPeriodEnd: nil)],
            licenses: (hasLinkedLicense ? [linkedLicenseKeys.first ?? "LINKED-2AF37E"] : []).map {
                RelayAccountLinkedLicense(
                    licenseKeyMasked: "••••-••••-\($0.suffix(6))",
                    customerEmail: "person@example.com",
                    productName: "Relay Pro",
                    variantName: "Relay Pro Yearly",
                    status: "active",
                    activationUsageCount: 1,
                    activationLimit: 3,
                    expiresAt: nil,
                    source: "lemonsqueezy",
                    linkedAt: nil,
                    lastValidatedAt: nil
                )
            }
        )
    }

    func sendHeartbeat(token: String, request: RelayAccountHeartbeatRequest) async throws {}

    func linkLegacyLicense(token: String, licenseKey: String) async throws {
        linkedLicenseKeys.append(licenseKey)
    }

    func activateLinkedLicense(token: String, request: RelayAccountActivateLinkedLicenseRequest) async throws -> RelayAccountActivateLinkedLicenseResponse {
        activateLinkedLicenseRequests.append(request)
        return RelayAccountActivateLinkedLicenseResponse(
            ok: true,
            activated: true,
            entitlement: nil
        )
    }

    func deactivateLinkedLicense(token: String, request: RelayAccountDeactivateLinkedLicenseRequest) async throws -> RelayAccountDeactivateLinkedLicenseResponse {
        deactivateLinkedLicenseRequests.append(request)
        return RelayAccountDeactivateLinkedLicenseResponse(
            ok: true,
            deactivated: true,
            entitlement: nil
        )
    }

    func linkAppStoreSubscription(token: String, request: RelayAccountLinkAppStoreSubscriptionRequest) async throws {
        linkedAppStoreSubscriptions.append(request)
    }

    func logout(token: String) async throws {
        if let logoutError {
            throw logoutError
        }
    }

    var deleteAccountError: Error?
    var deleteAccountTokens: [String] = []

    func deleteAccount(token: String) async throws {
        deleteAccountTokens.append(token)
        if let deleteAccountError { throw deleteAccountError }
    }
}
