import Foundation

enum RelayDistributionChannel: String {
    case release = "release"
    case debug = "debug"
}

enum RelayPurchaseMode: String {
    case appStore = "appstore"
    case direct = "direct"
    case both = "both"
}

struct RelayLicensingConfig {
    static let privacyPolicyURL = URL(string: "https://github.com/dbullard/Relay#privacy-and-optional-services")!
    static let termsURL = URL(string: "https://github.com/dbullard/Relay/blob/main/LICENSE")!
    static let supportURL = URL(string: "https://github.com/dbullard/Relay")!

    static var apiBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RELAY_API_BASE_URL") as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return URL(string: raw)
    }

    static var distributionChannel: RelayDistributionChannel {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "RELAY_DISTRIBUTION_CHANNEL") as? String)
            ?? RelayDistributionChannel.release.rawValue
        return RelayDistributionChannel(rawValue: raw.lowercased()) ?? .release
    }

    static var purchaseMode: RelayPurchaseMode {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "RELAY_PURCHASE_MODE") as? String)
            ?? RelayPurchaseMode.direct.rawValue
        return RelayPurchaseMode(rawValue: raw.lowercased()) ?? .direct
    }

    static var isDirectMacDistribution: Bool {
#if os(macOS)
        switch purchaseMode {
        case .direct, .both:
            return true
        case .appStore:
            return false
        }
#else
        return false
#endif
    }

    /// UserDefaults key for the user's "Preview features" switch (Settings > Preview).
    static let previewFeaturesKey = "relay_preview_features_enabled"

    /// Pure rule, kept separate so it can be unit tested in a Debug test build.
    static func previewFeaturesEnabled(channel: RelayDistributionChannel, userEnabled: Bool) -> Bool {
        channel == .debug || userEnabled
    }

    /// True when experimental (formerly beta-only) features are available. Debug builds always
    /// have them. Everyone else opts in with the Preview switch and must restart Relay.
    static var isPreviewEnabled: Bool {
        previewFeaturesEnabled(
            channel: distributionChannel,
            userEnabled: UserDefaults.standard.bool(forKey: previewFeaturesKey)
        )
    }

    static var isDebugBuild: Bool {
        distributionChannel == .debug
    }

    /// Which What's New feed channel this build should request. Debug builds request "beta" too,
    /// since they're used for internal testing of pre-release features and "debug" isn't a channel
    /// the server recognizes.
    static var whatsNewFeedChannel: String {
        switch distributionChannel {
        case .debug:
            return "beta"
        case .release:
            return "release"
        }
    }

    /// Human-readable label for the running build's distribution channel, for display purposes
    /// (e.g. in the What's New header) — not to be confused with `whatsNewFeedChannel`, which
    /// collapses debug into "beta" for the API request.
    static var channelDisplayLabel: String {
        switch distributionChannel {
        case .release:
            return "Release"
        case .debug:
            return "Debug"
        }
    }

    static var currentAppBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    static var isVistaIntegrationEnabled: Bool {
        true
    }

    static var usesAppStorePurchases: Bool {
        switch purchaseMode {
        case .appStore, .both:
            return true
        case .direct:
            return false
        }
    }
}
