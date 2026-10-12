import XCTest
@testable import Relay

/// Covers `TranscriptionThrottler`'s cancel-before-replace and explicit-cancel
/// behavior. This throttler is used by `SpeechTranscriber`, whose `stop()` now
/// calls `cancel()` explicitly (mirroring a fix applied to its XPC-process
/// sibling `HelperTranscriptionThrottler` after a proven bug where a stale,
/// already-scheduled publish fired after the owning session had stopped).
final class TranscriptionThrottlerTests: XCTestCase {
    /// A very high `targetHz` still floors `minInterval` at 0.05s (see
    /// `TranscriptionThrottler.publish`), giving a short, predictable throttle
    /// window without needing to mock time.
    private let highHz: Double = 1000
    private let settleNanoseconds: UInt64 = 150_000_000

    @MainActor
    func testPendingPublishFiresWhenNotCancelled() async throws {
        let throttler = TranscriptionThrottler()
        var publishCount = 0

        // Prime `lastPublish` with an immediate final publish.
        throttler.publish(isFinal: true, targetHz: highHz) { }

        // Arrives within the throttle window, so it schedules a delayed publish
        // rather than firing synchronously.
        throttler.publish(isFinal: false, targetHz: highHz) { publishCount += 1 }
        XCTAssertEqual(publishCount, 0, "a throttled publish should not fire synchronously")

        try await Task.sleep(nanoseconds: settleNanoseconds)
        XCTAssertEqual(publishCount, 1, "an uncancelled pending publish should fire after the throttle window")
    }

    @MainActor
    func testCancelPreventsPendingPublishFromFiring() async throws {
        let throttler = TranscriptionThrottler()
        var publishCount = 0

        throttler.publish(isFinal: true, targetHz: highHz) { }
        throttler.publish(isFinal: false, targetHz: highHz) { publishCount += 1 }
        XCTAssertEqual(publishCount, 0)

        throttler.cancel()

        try await Task.sleep(nanoseconds: settleNanoseconds)
        XCTAssertEqual(publishCount, 0, "cancel() should prevent the pending publish from ever firing")
    }

    @MainActor
    func testSchedulingNewPublishCancelsThePreviouslyPendingOne() async throws {
        let throttler = TranscriptionThrottler()
        var fired: [String] = []

        throttler.publish(isFinal: true, targetHz: highHz) { }

        // Two rapid non-final publishes land in the same throttle window: the
        // second call must cancel the first's pending work before scheduling its
        // own, so only the latest closure ever fires.
        throttler.publish(isFinal: false, targetHz: highHz) { fired.append("first") }
        throttler.publish(isFinal: false, targetHz: highHz) { fired.append("second") }

        try await Task.sleep(nanoseconds: settleNanoseconds)
        XCTAssertEqual(fired, ["second"], "the earlier pending publish should have been cancelled, not fired")
    }

    @MainActor
    func testFinalPublishCancelsAnyPendingPublishAndFiresImmediately() async throws {
        let throttler = TranscriptionThrottler()
        var fired: [String] = []

        throttler.publish(isFinal: true, targetHz: highHz) { }
        throttler.publish(isFinal: false, targetHz: highHz) { fired.append("partial") }

        // A final publish should cancel the pending partial and fire synchronously.
        throttler.publish(isFinal: true, targetHz: highHz) { fired.append("final") }
        XCTAssertEqual(fired, ["final"], "isFinal publishes fire synchronously and cancel any pending partial")

        try await Task.sleep(nanoseconds: settleNanoseconds)
        XCTAssertEqual(fired, ["final"], "the superseded partial publish must not fire later")
    }
}
