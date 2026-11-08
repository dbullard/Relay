import Foundation
#if os(macOS)
import AppKit
#endif

/// Imports settings from the earlier closed-source Relay (bundle ID `davidbullard.relay`).
///
/// Relay 2.0 is a separate app with a new bundle ID, so macOS keeps its settings apart from
/// the old app's. This reads the old app's preferences file and copies an allowlist of keys
/// into this app. Nothing from accounts, licensing, or subscriptions is copied, and Keychain
/// items (such as the Planning Center sign-in) can't be copied, so those need reconnecting.
enum PreviousRelayImporter {
    static let previousBundleID = "davidbullard.relay"
    /// Set when the user has chosen to import; applied on the next launch, before any store reads settings.
    static let pendingKey = "relay_pending_previous_import_v1"
    /// Set once the user answered the first-launch prompt (imported or declined).
    static let promptAnsweredKey = "relay_previous_import_prompt_answered_v1"

    // MARK: - What gets imported

    private static let exactKeys: Set<String> = [
        "external_devices_v1", "relay_shared_values_v1", "relay_spl_logging_settings_v1",
        "relay_transcription_inputs_config_v1", "relay_transcription_inputs_migrated_v2",
        "relay_preview_features_enabled", "autosave_announcement_shown_v1", "gridBackgroundOpacity",
        "relay.didShowTriggerSendMigrationNotice", "lan_browser_listen_port",
        "Relay.ResolumeProfilesStore.v1", "Relay.SmartLightProfilesStore.v1"
    ]

    private static let prefixes: [String] = [
        "dashboard", "midi", "osc", "propresenter_", "prodlink.x32sync.", "dbreader_", "wireless_log_",
        "relay.ndi."
    ]

    /// Keys that match an allowed prefix but belong to a sign-in, which can't be carried over.
    private static let excludedPrefixes: [String] = [
        "dashboard_pco_", "dashboard_youtube_"
    ]

    static func shouldImport(key: String) -> Bool {
        if excludedPrefixes.contains(where: { key.hasPrefix($0) }) { return false }
        if exactKeys.contains(key) { return true }
        return prefixes.contains { key.hasPrefix($0) }
    }

    // MARK: - Reading the old preferences

    static func previousPreferencesURL(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        home.appendingPathComponent("Library/Preferences/\(previousBundleID).plist")
    }

    static func readPreviousPreferences(at url: URL = previousPreferencesURL()) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    static func importableEntries(from preferences: [String: Any]) -> [String: Any] {
        preferences.filter { shouldImport(key: $0.key) }
    }

    struct Summary: Equatable {
        var settingCount: Int
        var deviceCount: Int?
    }

    static func summary(of entries: [String: Any]) -> Summary {
        var devices: Int?
        if let data = entries["external_devices_v1"] as? Data,
           let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            devices = array.count
        }
        return Summary(settingCount: entries.count, deviceCount: devices)
    }

    /// The old app's settings, if its preferences file exists and has anything worth importing.
    static func availableImport(at url: URL = previousPreferencesURL()) -> (entries: [String: Any], summary: Summary)? {
        guard let preferences = readPreviousPreferences(at: url) else { return nil }
        let entries = importableEntries(from: preferences)
        guard !entries.isEmpty else { return nil }
        return (entries, summary(of: entries))
    }

    // MARK: - Applying

    static func apply(_ entries: [String: Any], to defaults: UserDefaults = .standard) {
        for (key, value) in entries {
            defaults.set(value, forKey: key)
        }
    }

    /// Whether the first-launch prompt should be offered: the old app's data exists and the
    /// user hasn't answered yet.
    static func shouldOfferOnLaunch(defaults: UserDefaults = .standard, url: URL = previousPreferencesURL()) -> Bool {
        guard !defaults.bool(forKey: promptAnsweredKey) else { return false }
        return availableImport(at: url) != nil
    }

    // MARK: - Two-step import (apply before stores load, then relaunch)

    /// Stores read their settings when they are created, so the import is applied on the next
    /// launch, before any of them exist.
    static func requestImportAndRelaunch(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
        defaults.set(true, forKey: promptAnsweredKey)
        defaults.synchronize()
        relaunch()
    }

    static func declineOffer(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: promptAnsweredKey)
    }

    /// Call as early as possible at launch. No-op unless an import was requested.
    @discardableResult
    static func applyPendingImportIfNeeded(
        defaults: UserDefaults = .standard,
        url: URL = previousPreferencesURL()
    ) -> Bool {
        guard defaults.bool(forKey: pendingKey) else { return false }
        defaults.removeObject(forKey: pendingKey)
        guard let available = availableImport(at: url) else { return false }
        apply(available.entries, to: defaults)
        defaults.synchronize()
        return true
    }

    private static func relaunch() {
        #if os(macOS)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
        #endif
    }
}
