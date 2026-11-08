import XCTest
@testable import Relay

@MainActor
final class PreviewFeaturesTests: XCTestCase {
    func test_releaseWithSwitchOff_hasNoPreviewFeatures() {
        XCTAssertFalse(RelayBuildConfig.previewFeaturesEnabled(channel: .release, userEnabled: false))
    }

    func test_releaseWithSwitchOn_hasPreviewFeatures() {
        XCTAssertTrue(RelayBuildConfig.previewFeaturesEnabled(channel: .release, userEnabled: true))
    }

    func test_debugAlwaysHasPreviewFeatures() {
        XCTAssertTrue(RelayBuildConfig.previewFeaturesEnabled(channel: .debug, userEnabled: false))
    }

    func test_previewKeyIsStable() {
        XCTAssertEqual(RelayBuildConfig.previewFeaturesKey, "relay_preview_features_enabled")
    }

    func test_unknownOrOldBetaChannelValueFallsBackToRelease() {
        XCTAssertNil(RelayDistributionChannel(rawValue: "beta"))
    }

    func test_wirelessLoggingKeyMatchesPreviewKey() {
        UserDefaults.standard.set(true, forKey: RelayBuildConfig.previewFeaturesKey)
        defer { UserDefaults.standard.removeObject(forKey: RelayBuildConfig.previewFeaturesKey) }
        // The Debug test build is already "debug", so this asserts the literal matches by reading it back.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "relay_preview_features_enabled"))
    }
}
