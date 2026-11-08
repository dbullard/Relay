import Foundation

struct RelayBuildConfig {
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

    /// UserDefaults key for the user's "Preview features" switch (Settings > Preview).
    static let previewFeaturesKey = "relay_preview_features_enabled"

    /// True when experimental features are available. Everyone opts in with the Preview switch
    /// (Settings > Preview) and must restart Relay; debug and release builds behave the same.
    static var isPreviewEnabled: Bool {
        UserDefaults.standard.bool(forKey: previewFeaturesKey)
    }

    static let whatsNewFeedChannel = "release"

    static var currentAppBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    static var isVistaIntegrationEnabled: Bool {
        true
    }
}
