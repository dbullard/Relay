import XCTest
@testable import Relay

final class LiveTranscriptionBoundsTests: XCTestCase {
    private func entry(_ seconds: TimeInterval, _ text: String) -> TranscriptEntry {
        TranscriptEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: seconds),
            sourceId: UUID(),
            sourceDisplayName: "Pastor",
            rawText: text,
            displayText: text,
            isFinal: true,
            confidence: nil
        )
    }

    func testEntriesAlreadyInOrderAreKept() {
        let entries = [entry(1, "a"), entry(2, "b"), entry(2, "c"), entry(3, "d")]
        XCTAssertEqual(LiveTranscriptionController.sortedByTimestamp(entries), entries)
    }

    func testOutOfOrderEntriesAreSorted() {
        let first = entry(1, "a"), second = entry(2, "b"), third = entry(3, "c")
        let sorted = LiveTranscriptionController.sortedByTimestamp([first, third, second])
        XCTAssertEqual(sorted.map(\.rawText), ["a", "b", "c"])
    }

    func testTileShowsLatest400WithLimitsOff() {
        let retention = LiveTranscriptionRetentionSettings(limitsEnabled: false, maxEntries: 2000)
        XCTAssertEqual(LiveTranscriptionTileView.displayedEntryLimit(retention: retention), 400)
    }

    func testHigherEntryLimitIsShownInFull() {
        let retention = LiveTranscriptionRetentionSettings(limitsEnabled: true, maxEntries: 1000)
        XCTAssertEqual(LiveTranscriptionTileView.displayedEntryLimit(retention: retention), 1000)
    }

    func testLowerEntryLimitKeepsTheDefaultWindow() {
        let retention = LiveTranscriptionRetentionSettings(limitsEnabled: true, maxEntries: 50)
        XCTAssertEqual(LiveTranscriptionTileView.displayedEntryLimit(retention: retention), 400)
    }
}
