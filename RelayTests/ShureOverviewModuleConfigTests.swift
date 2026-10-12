import XCTest
@testable import Relay

final class ShureOverviewModuleConfigTests: XCTestCase {

    private func decode(_ json: String) throws -> ShureOverviewModuleConfig {
        try JSONDecoder().decode(ShureOverviewModuleConfig.self, from: Data(json.utf8))
    }

    func testDefaultConfigUsesSignalLight() {
        XCTAssertEqual(ShureOverviewModuleConfig.default().audioActivityMode, .signalLight)
    }

    func testDecodingLegacyShowAudioMeterTrueMapsToSignalLight() throws {
        let config = try decode(#"{"showAudioMeter": true}"#)
        XCTAssertEqual(config.audioActivityMode, .signalLight)
    }

    func testDecodingLegacyShowAudioMeterFalseMapsToOff() throws {
        let config = try decode(#"{"showAudioMeter": false}"#)
        XCTAssertEqual(config.audioActivityMode, .off)
    }

    func testDecodingNewAudioActivityModeKeyTakesPrecedenceOverLegacyKey() throws {
        let config = try decode(#"{"showAudioMeter": false, "audioActivityMode": 2}"#)
        XCTAssertEqual(config.audioActivityMode, .meter)
    }

    func testDecodingWithNeitherKeyDefaultsToSignalLight() throws {
        let config = try decode("{}")
        XCTAssertEqual(config.audioActivityMode, .signalLight)
    }

    func testRoundTripPreservesNonDefaultValues() throws {
        var original = ShureOverviewModuleConfig.default()
        original.deviceScope = .selectedDevices
        original.selectedDeviceIDs = [UUID(), UUID()]
        original.defaultTab = .mics
        original.lowBatteryWarningPercent = 42
        original.criticalBatteryPercent = 10
        original.lowRFWarningThreshold = 3
        original.criticalRFThreshold = 2
        original.staleTelemetryTimeoutSeconds = 15
        original.hideOfflineChannels = true
        original.showFrequency = false
        original.showDeviceName = false
        original.audioActivityMode = .meter
        original.showSummaryStatusChips = false
        original.showChannelStatusPill = false
        original.showLastUpdatedTimestamp = true
        original.sortOrder = .battery
        original.cardSize = .large
        original.displayStyle = .cards
        original.channelPersonAssignments = ["ch-1": "Alex"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShureOverviewModuleConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testPartialPayloadStillDefaultsUnrelatedFields() throws {
        let config = try decode(#"{"lowBatteryWarningPercent": 99}"#)

        XCTAssertEqual(config.lowBatteryWarningPercent, 99)
        XCTAssertEqual(config.criticalBatteryPercent, 15)
        XCTAssertEqual(config.lowRFWarningThreshold, 2)
        XCTAssertEqual(config.criticalRFThreshold, 1)
        XCTAssertEqual(config.staleTelemetryTimeoutSeconds, 8)
        XCTAssertFalse(config.hideOfflineChannels)
        XCTAssertTrue(config.showFrequency)
        XCTAssertTrue(config.showDeviceName)
        XCTAssertEqual(config.audioActivityMode, .signalLight)
        XCTAssertTrue(config.showSummaryStatusChips)
        XCTAssertTrue(config.showChannelStatusPill)
        XCTAssertFalse(config.showLastUpdatedTimestamp)
        XCTAssertEqual(config.sortOrder, .severity)
        XCTAssertEqual(config.cardSize, .medium)
        XCTAssertEqual(config.displayStyle, .list)
        XCTAssertTrue(config.channelPersonAssignments.isEmpty)
    }

    func testIndicatorIsHiddenWhenModeIsOff() {
        let indicator = ShureOverviewAudioIndicator.indicator(mode: .off, audioBucket: 4, effectiveLiveMode: true)
        XCTAssertEqual(indicator, .hidden)
    }

    func testIndicatorIsSignalLightLitWhenBucketIsAboveZero() {
        let indicator = ShureOverviewAudioIndicator.indicator(mode: .signalLight, audioBucket: 2, effectiveLiveMode: true)
        XCTAssertEqual(indicator, .signalLight(isLive: true))
    }

    func testIndicatorIsSignalLightDarkWhenBucketIsZero() {
        let indicator = ShureOverviewAudioIndicator.indicator(mode: .signalLight, audioBucket: 0, effectiveLiveMode: true)
        XCTAssertEqual(indicator, .signalLight(isLive: false))
    }

    func testIndicatorIsSignalLightDarkWhenNotLive() {
        let indicator = ShureOverviewAudioIndicator.indicator(mode: .signalLight, audioBucket: 5, effectiveLiveMode: false)
        XCTAssertEqual(indicator, .signalLight(isLive: false))
    }

    func testIndicatorIsMeterWithFilledSegmentsMatchingBucket() {
        let indicator = ShureOverviewAudioIndicator.indicator(mode: .meter, audioBucket: 3, effectiveLiveMode: true)
        XCTAssertEqual(indicator, .meter(filledSegments: 3))
    }

    func testIndicatorIsMeterZeroedWhenNotLive() {
        let indicator = ShureOverviewAudioIndicator.indicator(mode: .meter, audioBucket: 3, effectiveLiveMode: false)
        XCTAssertEqual(indicator, .meter(filledSegments: 0))
    }
}
