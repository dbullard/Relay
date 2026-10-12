import Foundation

struct RelayAccountMagicLinkRequest: Codable, Equatable {
    let email: String
    var codeChallenge: String? = nil
}

struct RelayAccountAuthExchangeRequest: Codable, Equatable {
    let code: String
    let codeVerifier: String
}

struct RelayAccountAuthExchangeResponse: Codable, Equatable {
    let ok: Bool
    let token: String?
}

struct RelayAccountHeartbeatRequest: Codable, Equatable {
    let installationId: UUID
    let platform: String
    let appVersion: String
}

struct RelayAccountHeartbeatResponse: Codable, Equatable {
    let ok: Bool
}

struct RelayAccountMagicLinkResponse: Codable, Equatable {
    let ok: Bool
    let message: String?
    let verifyURL: URL?

    private enum CodingKeys: String, CodingKey {
        case ok
        case message
        case verifyURL
    }

    private enum AltCodingKeys: String, CodingKey {
        case verifyURL = "verifyUrl"
    }

    init(ok: Bool, message: String?, verifyURL: URL?) {
        self.ok = ok
        self.message = message
        self.verifyURL = verifyURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        message = try container.decodeIfPresent(String.self, forKey: .message)
        verifyURL = try container.decodeIfPresent(URL.self, forKey: .verifyURL)
            ?? altContainer.decodeIfPresent(URL.self, forKey: .verifyURL)
    }
}

struct RelayAccountLinkLicenseRequest: Codable, Equatable {
    let licenseKey: String
}

struct RelayAccountActivateLinkedLicenseRequest: Codable, Equatable {
    let instanceName: String
    let deviceFingerprint: String
    let appVersion: String
    let bundleID: String
    let platform: String
}

struct RelayAccountActivateLinkedLicenseResponse: Codable, Equatable {
    let ok: Bool
    let activated: Bool
    let entitlement: LicenseEntitlement?
}

struct RelayAccountDeactivateLinkedLicenseRequest: Codable, Equatable {
    let deviceFingerprint: String
    let bundleID: String
    let platform: String
}

struct RelayAccountDeactivateLinkedLicenseResponse: Codable, Equatable {
    let ok: Bool
    let deactivated: Bool
    let entitlement: LicenseEntitlement?
}

struct RelayAccountUser: Codable, Equatable {
    let id: String
    let email: String
}

struct RelayEntitlementSources: Codable, Equatable {
    let subscription: Bool
    let license: Bool

    init(subscription: Bool, license: Bool) {
        self.subscription = subscription
        self.license = license
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscription = try container.decodeIfPresent(Bool.self, forKey: .subscription) ?? false
        license = try container.decodeIfPresent(Bool.self, forKey: .license) ?? false
    }
}

struct RelayAccountSubscription: Codable, Equatable, Identifiable {
    let provider: String
    let status: String
    let currentPeriodEnd: Date?

    var id: String {
        let currentPeriodTimestamp = currentPeriodEnd?.timeIntervalSince1970 ?? 0
        return "\(provider)-\(status)-\(currentPeriodTimestamp)"
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case status
        case currentPeriodEnd
    }

    private enum AltCodingKeys: String, CodingKey {
        case currentPeriodEnd = "current_period_end"
    }

    init(provider: String, status: String, currentPeriodEnd: Date?) {
        self.provider = provider
        self.status = status
        self.currentPeriodEnd = currentPeriodEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        status = try container.decode(String.self, forKey: .status)
        currentPeriodEnd = try container.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
            ?? altContainer.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(currentPeriodEnd, forKey: .currentPeriodEnd)
    }
}

struct RelayAccountLinkedLicense: Codable, Equatable, Identifiable {
    let licenseKeyMasked: String
    let customerEmail: String?
    let productName: String?
    let variantName: String?
    let status: String
    let activationUsageCount: Int?
    let activationLimit: Int?
    let expiresAt: Date?
    let source: String?
    let linkedAt: Date?
    let lastValidatedAt: Date?

    var id: String {
        licenseKeyMasked
    }

    private enum CodingKeys: String, CodingKey {
        case licenseKeyMasked
        case customerEmail
        case productName
        case variantName
        case status
        case activationUsageCount
        case activationLimit
        case expiresAt
        case source
        case linkedAt
        case lastValidatedAt
    }

    private enum AltCodingKeys: String, CodingKey {
        case licenseKeyMasked = "license_key_masked"
        case customerEmail = "customer_email"
        case productName = "product_name"
        case variantName = "variant_name"
        case activationUsageCount = "activation_usage_count"
        case activationLimit = "activation_limit"
        case expiresAt = "expires_at"
        case linkedAt = "linked_at"
        case lastValidatedAt = "last_validated_at"
    }

    init(
        licenseKeyMasked: String,
        customerEmail: String?,
        productName: String?,
        variantName: String?,
        status: String,
        activationUsageCount: Int?,
        activationLimit: Int?,
        expiresAt: Date?,
        source: String?,
        linkedAt: Date?,
        lastValidatedAt: Date?
    ) {
        self.licenseKeyMasked = licenseKeyMasked
        self.customerEmail = customerEmail
        self.productName = productName
        self.variantName = variantName
        self.status = status
        self.activationUsageCount = activationUsageCount
        self.activationLimit = activationLimit
        self.expiresAt = expiresAt
        self.source = source
        self.linkedAt = linkedAt
        self.lastValidatedAt = lastValidatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try decoder.container(keyedBy: AltCodingKeys.self)
        licenseKeyMasked = try container.decodeIfPresent(String.self, forKey: .licenseKeyMasked)
            ?? altContainer.decodeIfPresent(String.self, forKey: .licenseKeyMasked)
            ?? ""
        customerEmail = try container.decodeIfPresent(String.self, forKey: .customerEmail)
            ?? altContainer.decodeIfPresent(String.self, forKey: .customerEmail)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .productName)
        variantName = try container.decodeIfPresent(String.self, forKey: .variantName)
            ?? altContainer.decodeIfPresent(String.self, forKey: .variantName)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        activationUsageCount = try container.decodeIfPresent(Int.self, forKey: .activationUsageCount)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .activationUsageCount)
        activationLimit = try container.decodeIfPresent(Int.self, forKey: .activationLimit)
            ?? altContainer.decodeIfPresent(Int.self, forKey: .activationLimit)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            ?? altContainer.decodeIfPresent(Date.self, forKey: .expiresAt)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        linkedAt = try container.decodeIfPresent(Date.self, forKey: .linkedAt)
            ?? altContainer.decodeIfPresent(Date.self, forKey: .linkedAt)
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
            ?? altContainer.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
    }
}

struct RelayAccountSessionResponse: Codable, Equatable {
    let authenticated: Bool
    let user: RelayAccountUser?

    init(authenticated: Bool, user: RelayAccountUser?) {
        self.authenticated = authenticated
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authenticated = try container.decodeIfPresent(Bool.self, forKey: .authenticated) ?? false
        user = try container.decodeIfPresent(RelayAccountUser.self, forKey: .user)
    }
}

struct RelayAccountEntitlementsResponse: Codable, Equatable {
    let pro: Bool
    let authenticated: Bool
    let user: RelayAccountUser?
    let sources: RelayEntitlementSources
    let subscriptions: [RelayAccountSubscription]
    let licenses: [RelayAccountLinkedLicense]

    init(
        pro: Bool,
        authenticated: Bool,
        user: RelayAccountUser?,
        sources: RelayEntitlementSources,
        subscriptions: [RelayAccountSubscription],
        licenses: [RelayAccountLinkedLicense]
    ) {
        self.pro = pro
        self.authenticated = authenticated
        self.user = user
        self.sources = sources
        self.subscriptions = subscriptions
        self.licenses = licenses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pro = try container.decodeIfPresent(Bool.self, forKey: .pro) ?? false
        authenticated = try container.decodeIfPresent(Bool.self, forKey: .authenticated) ?? false
        user = try container.decodeIfPresent(RelayAccountUser.self, forKey: .user)
        sources = try container.decodeIfPresent(RelayEntitlementSources.self, forKey: .sources)
            ?? RelayEntitlementSources(subscription: false, license: false)
        subscriptions = try container.decodeIfPresent([RelayAccountSubscription].self, forKey: .subscriptions) ?? []
        licenses = try container.decodeIfPresent([RelayAccountLinkedLicense].self, forKey: .licenses) ?? []
    }
}

enum RelayAccountState: Equatable {
    case signedOut
    case sendingMagicLink
    case waitingForEmail(email: String)
    case signingIn
    case signedIn(email: String, pro: Bool)
    case error(message: String)
}

struct RelayAccountDiagnosticsSnapshot: Equatable {
    let authEnabled: Bool
    let signedIn: Bool
    let currentEmail: String?
    let relayAccountPro: Bool
    let sourceSubscription: Bool
    let sourceLicense: Bool
    let lastRefreshAt: Date?
    let lastErrorCode: Int?
    let lastErrorMessage: String?
}

nonisolated enum RelayAccountLicenseProvider: Equatable, Sendable {
    case appStore
    case lemonSqueezy

    var displayName: String {
        switch self {
        case .appStore:
            return "App Store"
        case .lemonSqueezy:
            return "Lemon Squeezy"
        }
    }

    static func resolve(from entitlements: RelayAccountEntitlementsResponse) -> RelayAccountLicenseProvider? {
        let activeSubscriptions = entitlements.subscriptions.filter { isProStatus($0.status) }
        let activeLicenses = entitlements.licenses.filter { isProStatus($0.status) }

        for subscription in activeSubscriptions {
            if let provider = fromSubscriptionProvider(subscription.provider) {
                return provider
            }
        }

        for license in activeLicenses {
            if let provider = fromLicenseSource(license.source) {
                return provider
            }
        }

        for subscription in entitlements.subscriptions {
            if let provider = fromSubscriptionProvider(subscription.provider) {
                return provider
            }
        }

        for license in entitlements.licenses {
            if let provider = fromLicenseSource(license.source) {
                return provider
            }
        }

        if entitlements.sources.subscription {
            return .appStore
        }

        if entitlements.sources.license {
            return .lemonSqueezy
        }

        return nil
    }

    private static func fromSubscriptionProvider(_ rawValue: String) -> RelayAccountLicenseProvider? {
        let normalized = normalizedValue(rawValue)
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("appstore") || normalized.contains("app_store") || normalized.contains("apple") {
            return .appStore
        }

        return nil
    }

    private static func fromLicenseSource(_ rawValue: String?) -> RelayAccountLicenseProvider? {
        let normalized = normalizedValue(rawValue)
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("lemonsqueezy") || normalized.contains("lemon_squeezy") || normalized.contains("lemon-squeezy") {
            return .lemonSqueezy
        }

        if normalized.contains("appstore") || normalized.contains("app_store") || normalized.contains("apple") {
            return .appStore
        }

        return nil
    }

    private static func normalizedValue(_ rawValue: String?) -> String {
        rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "") ?? ""
    }

    private static func isProStatus(_ rawValue: String) -> Bool {
        RelayAccountEntitlementEvaluator.proStatuses.contains(
            rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }
}

nonisolated enum RelayAccountEntitlementEvaluator {
    static let proStatuses: Set<String> = ["active", "trialing", "on_trial", "billing_grace_period"]

    static func resolvePro(from payload: RelayAccountEntitlementsResponse) -> Bool {
        if payload.pro {
            return true
        }

        if payload.sources.subscription || payload.sources.license {
            return true
        }

        if payload.subscriptions.contains(where: { proStatuses.contains($0.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) {
            return true
        }

        return payload.licenses.contains { license in
            proStatuses.contains(license.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }
}
