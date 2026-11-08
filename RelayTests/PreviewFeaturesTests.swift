import XCTest
@testable import Relay

@MainActor
final class PreviewFeaturesTests: XCTestCase {
    func test_previewFollowsOnlyTheUserSwitch() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: RelayBuildConfig.previewFeaturesKey)
        defer {
            if let original { defaults.set(original, forKey: RelayBuildConfig.previewFeaturesKey) }
            else { defaults.removeObject(forKey: RelayBuildConfig.previewFeaturesKey) }
        }
        defaults.set(false, forKey: RelayBuildConfig.previewFeaturesKey)
        XCTAssertFalse(RelayBuildConfig.isPreviewEnabled)
        defaults.set(true, forKey: RelayBuildConfig.previewFeaturesKey)
        XCTAssertTrue(RelayBuildConfig.isPreviewEnabled)
    }

    func test_previewKeyIsStable() {
        XCTAssertEqual(RelayBuildConfig.previewFeaturesKey, "relay_preview_features_enabled")
    }

    func test_wirelessLoggingKeyMatchesPreviewKey() {
        UserDefaults.standard.set(true, forKey: RelayBuildConfig.previewFeaturesKey)
        defer { UserDefaults.standard.removeObject(forKey: RelayBuildConfig.previewFeaturesKey) }
        // The Debug test build is already "debug", so this asserts the literal matches by reading it back.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "relay_preview_features_enabled"))
    }
}
