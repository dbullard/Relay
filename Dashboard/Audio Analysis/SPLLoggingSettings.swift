import Foundation

struct SPLLoggingSettings: Codable, Equatable {
    /// Persisted so the manager can auto-resume logging on next app launch
    /// if the app was quit mid-session (see SPLLoggingManager.init).
    var isLogging: Bool = false
    /// Human-readable path used for display and as a non-sandboxed fallback.
    /// Primary access uses `folderBookmarkData` (security-scoped bookmark).
    var folderPath: String = ""
    var folderBookmarkData: Data? = nil

    static let userDefaultsKey = "relay_spl_logging_settings_v1"

    static func load() -> SPLLoggingSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(SPLLoggingSettings.self, from: data)
        else { return SPLLoggingSettings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            assertionFailure("SPLLoggingSettings: encoding failed")
            return
        }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
