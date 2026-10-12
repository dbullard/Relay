import XCTest
@testable import Relay

final class DiGiCoConsoleSyncServiceTests: XCTestCase {

    // MARK: - Early-stop logic

    func testScanStopsAfter8ConsecutiveEmptyAfterLastValid() {
        // Channels 1-5 valid, 6-13 empty (8 consecutive) → should stop at 13
        let results: [Int: String] = [1: "Kick", 2: "Snare", 3: "HH", 4: "OH L", 5: "OH R"]
        let stopAt = DiGiCoConsoleSyncService.firstEarlyStopIndex(
            scanned: Array(1...13),
            results: results,
            consecutiveEmptyThreshold: 8
        )
        XCTAssertEqual(stopAt, 13)
    }

    func testScanDoesNotStopBeforeThreshold() {
        // Channels 1-5 valid, 6-12 empty (7 consecutive) — threshold is 8, no stop yet
        let results: [Int: String] = [1: "Kick", 2: "Snare", 3: "HH", 4: "OH L", 5: "OH R"]
        let stopAt = DiGiCoConsoleSyncService.firstEarlyStopIndex(
            scanned: Array(1...12),
            results: results,
            consecutiveEmptyThreshold: 8
        )
        XCTAssertNil(stopAt)
    }

    func testScanDoesNotStopWithNoValidResponses() {
        // All empty — no valid response seen → should not early-stop
        let stopAt = DiGiCoConsoleSyncService.firstEarlyStopIndex(
            scanned: Array(1...8),
            results: [:],
            consecutiveEmptyThreshold: 8
        )
        XCTAssertNil(stopAt)
    }

    func testScanStopsAfterGapInMiddle() {
        // 1 valid, 2-9 empty (8 consecutive) → stop at 9
        let results: [Int: String] = [1: "Kick"]
        let stopAt = DiGiCoConsoleSyncService.firstEarlyStopIndex(
            scanned: Array(1...9),
            results: results,
            consecutiveEmptyThreshold: 8
        )
        XCTAssertEqual(stopAt, 9)
    }

    // MARK: - Input channel merge

    func testMergeOSCWinsForNonEmptyName() {
        let existing = [
            ExternalDeviceConfig.DiGiCoInputChannel(channel: 1, stereo: false, name: "OLD NAME"),
        ]
        let discovered: [Int: String] = [1: "Kick"]
        let merged = DiGiCoConsoleSyncService.mergeInputChannels(existing: existing, discovered: discovered)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Kick")
        XCTAssertEqual(merged[0].stereo, false)
    }

    func testMergeRTFPreservedWhenOSCReturnsEmpty() {
        let existing = [
            ExternalDeviceConfig.DiGiCoInputChannel(channel: 2, stereo: true, name: "PIANO"),
        ]
        let discovered: [Int: String] = [2: ""]
        let merged = DiGiCoConsoleSyncService.mergeInputChannels(existing: existing, discovered: discovered)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "PIANO")
        XCTAssertEqual(merged[0].stereo, true)
    }

    func testMergeAddsNewOSCChannel() {
        let existing: [ExternalDeviceConfig.DiGiCoInputChannel] = []
        let discovered: [Int: String] = [5: "Snare"]
        let merged = DiGiCoConsoleSyncService.mergeInputChannels(existing: existing, discovered: discovered)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].channel, 5)
        XCTAssertEqual(merged[0].name, "Snare")
        XCTAssertFalse(merged[0].stereo)
    }

    func testMergePreservesOrder() {
        let existing = [
            ExternalDeviceConfig.DiGiCoInputChannel(channel: 3, stereo: false, name: "OLD3"),
            ExternalDeviceConfig.DiGiCoInputChannel(channel: 1, stereo: false, name: "OLD1"),
        ]
        let discovered: [Int: String] = [1: "Kick", 2: "Snare", 3: "HH"]
        let merged = DiGiCoConsoleSyncService.mergeInputChannels(existing: existing, discovered: discovered)
        XCTAssertEqual(merged.map(\.channel), [1, 2, 3])
        XCTAssertEqual(merged.map(\.name), ["Kick", "Snare", "HH"])
    }

    // MARK: - Layout bank parsing

    func testParseLayoutBankExtractsStrips() {
        let bank = DiGiCoConsoleSyncService.LayoutBank(
            name: "Inputs A",
            section: "L",
            page: 1,
            layer: 0,
            strips: [
                (type: "Input_Channels", index: 1),
                (type: "Input_Channels", index: 2),
                (type: "Aux_Outputs", index: 8),
            ]
        )
        XCTAssertEqual(bank.strips.count, 3)
        XCTAssertEqual(bank.strips[2].type, "Aux_Outputs")
        XCTAssertEqual(bank.strips[2].index, 8)
    }
}
