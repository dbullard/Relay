import XCTest
@testable import Relay

final class PreviousRelayImporterTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "PreviousRelayImporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func writePreferences(_ dict: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prev-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func test_allowlistKeepsSettingsAndDropsAccountsAndSignIns() {
        let keep = ["external_devices_v1", "dashboard_snap_to_grid_enabled", "midi_enabled", "osc_port",
                    "propresenter_host", "prodlink.x32sync.map.ABC", "relay_shared_values_v1", "wireless_log_shure_master"]
        let drop = ["license_keychain_migration_v1", "pro_upgrade_prompt_seen_v1", "subscription_lastSyncAt",
                    "relay_account_cached_entitlements", "relay_usage_diagnostics_enabled", "relay_whatsnew_last_seen_version",
                    "sparkle_beta_opt_in", "SUHasLaunchedBefore", "NSWindow Frame Foo", "prodlink.deviceId",
                    "lan_paired_devices", "dashboard_pco_connected", "dashboard_pco_account_name",
                    "dashboard_youtube_connected", "RelayLastWindowFrame"]
        keep.forEach { XCTAssertTrue(PreviousRelayImporter.shouldImport(key: $0), $0) }
        drop.forEach { XCTAssertFalse(PreviousRelayImporter.shouldImport(key: $0), $0) }
    }

    func test_availableImportReadsOnlyAllowedKeysAndCountsDevices() throws {
        let devices = try JSONSerialization.data(withJSONObject: [["name": "a"], ["name": "b"]])
        let url = try writePreferences([
            "external_devices_v1": devices, "dashboard_live_mode_enabled": true, "license_x": "secret"
        ])
        let available = try XCTUnwrap(PreviousRelayImporter.availableImport(at: url))
        XCTAssertEqual(Set(available.entries.keys), ["external_devices_v1", "dashboard_live_mode_enabled"])
        XCTAssertEqual(available.summary, .init(settingCount: 2, deviceCount: 2))
    }

    func test_noImportWhenFileMissingOrNothingImportable() throws {
        XCTAssertNil(PreviousRelayImporter.availableImport(at: URL(fileURLWithPath: "/nonexistent/x.plist")))
        let url = try writePreferences(["license_x": "1", "SUHasLaunchedBefore": true])
        XCTAssertNil(PreviousRelayImporter.availableImport(at: url))
    }

    func test_pendingImportIsAppliedOnceAndOnlyWhenRequested() throws {
        let defaults = makeDefaults()
        let url = try writePreferences(["dashboard_view_mode": "canvas", "license_x": "1"])

        XCTAssertFalse(PreviousRelayImporter.applyPendingImportIfNeeded(defaults: defaults, url: url))
        XCTAssertNil(defaults.object(forKey: "dashboard_view_mode"))

        defaults.set(true, forKey: PreviousRelayImporter.pendingKey)
        XCTAssertTrue(PreviousRelayImporter.applyPendingImportIfNeeded(defaults: defaults, url: url))
        XCTAssertEqual(defaults.string(forKey: "dashboard_view_mode"), "canvas")
        XCTAssertNil(defaults.object(forKey: "license_x"))
        XCTAssertFalse(PreviousRelayImporter.applyPendingImportIfNeeded(defaults: defaults, url: url))
    }

    func test_launchOfferIsOnlyMadeOnceAndOnlyWithData() throws {
        let defaults = makeDefaults()
        let url = try writePreferences(["dashboard_view_mode": "canvas"])
        XCTAssertTrue(PreviousRelayImporter.shouldOfferOnLaunch(defaults: defaults, url: url))
        PreviousRelayImporter.declineOffer(defaults: defaults)
        XCTAssertFalse(PreviousRelayImporter.shouldOfferOnLaunch(defaults: defaults, url: url))
        XCTAssertFalse(PreviousRelayImporter.shouldOfferOnLaunch(defaults: makeDefaults(), url: URL(fileURLWithPath: "/nonexistent.plist")))
    }
}
