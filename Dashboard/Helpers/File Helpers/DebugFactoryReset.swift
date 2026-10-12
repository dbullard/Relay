//
//  DebugFactoryReset.swift
//  Relay
//

import Foundation
#if os(macOS)
import AppKit
#endif

#if DEBUG
/// Debug-only utility that wipes local app state back to a fresh-install
/// baseline: the whole UserDefaults domain, plus everything under
/// Application Support and Caches (device/audio-input config, onboarding
/// "already shown" flags, window/UI prefs, cached feeds, etc).
///
/// Deliberately does NOT touch the Keychain, so a Pro license
/// (Dashboard/Licensing/LicenseKeychainStore) survives a reset — this is a
/// "reset my test config," not a "pretend I never activated" tool.
///
/// All of this must run from inside the app itself: an external `defaults
/// delete` from a shell doesn't reliably reach a sandboxed app's real,
/// container-redirected UserDefaults domain, and FileManager's standard
/// directory URLs only resolve to the correct sandbox container when called
/// in-process.
enum DebugFactoryReset {
    /// Wipes all local state and, on macOS, relaunches the app. On iOS there
    /// is no supported way to relaunch programmatically — the caller should
    /// tell the user to force-quit and reopen manually.
    static func perform() {
        wipeUserDefaults()
        wipeDirectory(.applicationSupportDirectory)
        wipeDirectory(.cachesDirectory)
        relaunchIfPossible()
    }

    private static func wipeUserDefaults() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
    }

    private static func wipeDirectory(_ directory: FileManager.SearchPathDirectory) {
        guard let url = FileManager.default.urls(for: directory, in: .userDomainMask).first,
              let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return
        }
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func relaunchIfPossible() {
#if os(macOS)
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                exit(0)
            }
        }
#endif
    }
}
#endif
