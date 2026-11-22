import XCTest
@testable import Relay

/// The waterfall scrolls at the configured rows per second, regardless of how often FFT
/// frames arrive (which depends on the FFT size other tiles on the input ask for).
@MainActor
final class SpectrogramScrollRateTests: XCTestCase {

    /// Feeds `seconds` of frames at `frameRate` and returns the rows emitted after the
    /// first frame.
    private func rowsEmitted(scrollRate: Double, frameRate: Double, seconds: Double) -> Int {
        var settings = SpectrogramModuleModel()
        settings.scrollRate = scrollRate
        let controller = SpectrogramController(settings: settings)
        let mags = [Float](repeating: 0.01, count: 2048)
        let frameCount = Int(seconds * frameRate)
        controller.ingestForTesting(FFTFrame(magnitudes: mags, sampleRate: 48_000, timestamp: 1000, isRepeated: false))
        let afterFirst = controller.rowsEmittedForTesting
        for i in 1...frameCount {
            let t = 1000 + Double(i) / frameRate
            controller.ingestForTesting(FFTFrame(magnitudes: mags, sampleRate: 48_000, timestamp: t, isRepeated: false))
        }
        return controller.rowsEmittedForTesting - afterFirst
    }

    func testDefaultRateWithFastFrames() {
        // ~47 frames/s (4096-point FFT, 1024 hop at 48 kHz) → 24 rows/s.
        XCTAssertEqual(rowsEmitted(scrollRate: 24, frameRate: 46.875, seconds: 10), 240, accuracy: 2)
    }

    func testRateIsIndependentOfFrameRate() {
        // Slower frames (a larger FFT requested by another tile) still give 24 rows/s.
        XCTAssertEqual(rowsEmitted(scrollRate: 24, frameRate: 11.72, seconds: 10), 240, accuracy: 2)
    }

    func testSliderExtremes() {
        XCTAssertEqual(rowsEmitted(scrollRate: 60, frameRate: 46.875, seconds: 10), 600, accuracy: 3)
        XCTAssertEqual(rowsEmitted(scrollRate: 1, frameRate: 46.875, seconds: 10), 10, accuracy: 1)
    }
}
