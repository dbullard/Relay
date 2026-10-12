import Foundation

struct NDIGlobalPreferences: Codable, Equatable {
    var preferredInterfaceID: String?
    var allowAutoFallback: Bool

    static let `default` = NDIGlobalPreferences(
        preferredInterfaceID: nil,
        allowAutoFallback: true
    )
}

enum NDIPreferencesStore {
    static let preferredInterfaceIDKey = "relay.ndi.preferredInterfaceID"
    static let allowAutoFallbackKey = "relay.ndi.allowAutoFallback"

    static func load(defaults: UserDefaults = .standard) -> NDIGlobalPreferences {
        NDIGlobalPreferences(
            preferredInterfaceID: defaults.string(forKey: preferredInterfaceIDKey),
            allowAutoFallback: defaults.object(forKey: allowAutoFallbackKey) as? Bool ?? true
        )
    }

    static func save(_ preferences: NDIGlobalPreferences, defaults: UserDefaults = .standard) {
        if let preferredInterfaceID = preferences.preferredInterfaceID,
           !preferredInterfaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(preferredInterfaceID, forKey: preferredInterfaceIDKey)
        } else {
            defaults.removeObject(forKey: preferredInterfaceIDKey)
        }
        defaults.set(preferences.allowAutoFallback, forKey: allowAutoFallbackKey)
    }
}
