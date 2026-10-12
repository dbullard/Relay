import Foundation

struct RelayAccountConfig {
    static let defaultAPIBaseURL = URL(string: "http://127.0.0.1:8787")!

    static var apiBaseURL: URL {
        if let raw = stringValue(forInfoKey: "RELAY_ACCOUNT_API_BASE_URL"),
           let url = URL(string: raw) {
            return url
        }

        if let fallback = RelayLicensingConfig.apiBaseURL {
            return fallback
        }

        return defaultAPIBaseURL
    }

    static var isAuthEnabled: Bool {
        if let explicit = boolValue(forInfoKey: "RELAY_ACCOUNT_AUTH_ENABLED") {
            return explicit
        }

        return false
    }

    static func debugTokenEntryAllowed(channel: RelayDistributionChannel) -> Bool {
        channel == .debug
    }

    /// Pasting a session token by hand is a developer tool: debug builds only.
    static var supportsDebugTokenEntry: Bool {
        debugTokenEntryAllowed(channel: RelayLicensingConfig.distributionChannel)
    }

    private static func stringValue(forInfoKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(forInfoKey key: String) -> Bool? {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? Bool {
            return value
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber {
            return value.boolValue
        }

        guard let raw = stringValue(forInfoKey: key)?.lowercased() else { return nil }
        switch raw {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}
