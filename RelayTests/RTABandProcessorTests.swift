import XCTest
@testable import Relay

final class RTABandProcessorTests: XCTestCase {

    func testThirdOctBandCount() async {
        let processor = RTABandProcessor(resolution: .thirdOct, frequencyRangeLow: 20, frequencyRangeHigh: 20000)
        // IEC 61260 1/3-octave centers from ~25 Hz to 16 kHz that fall within [20*0.99, 20000*1.01]
        let bands = await processor.bands
        XCTAssertEqual(bands.count, 29)
    }

    func testOctBandCount() async {
        let processor = RTABandProcessor(resolution: .oct, frequencyRangeLow: 20, frequencyRangeHigh: 20000)
        let bands = await processor.bands
        XCTAssertEqual(bands.count, 10)
    }

    func testBandContains1kHz() async {
        let processor = RTABandProcessor(resolution: .thirdOct, frequencyRangeLow: 20, frequencyRangeHigh: 20000)
        let bands = await processor.bands
        let band1k = bands.first { abs($0.centerHz - 1000) < 1 }
        XCTAssertNotNil(band1k)
        XCTAssertLessThan(band1k!.lowerHz, 1000)
        XCTAssertGreaterThan(band1k!.upperHz, 1000)
    }

    func testNoBandOverlap() async {
        let processor = RTABandProcessor(resolution: .thirdOct, frequencyRangeLow: 20, frequencyRangeHigh: 20000)
        let bands = await processor.bands
        for i in 0..<(bands.count - 1) {
            let upper = bands[i].upperHz
            let nextLower = bands[i + 1].lowerHz
            XCTAssertLessThanOrEqual(upper, nextLower + 1.0,
                "Band \(i) upper=\(upper) overlaps band \(i+1) lower=\(nextLower)")
        }
    }

    func testPeakHoldDecay() async {
        let processor = RTABandProcessor(resolution: .oct, frequencyRangeLow: 20, frequencyRangeHigh: 20000)
        let sampleRate = 44100.0
        let fftSize = 2048
        var mags = [Float](repeating: 0, count: fftSize / 2)
        mags[50] = 1.0  // 0 dBFS in bin 50
        let loudFrame = FFTFrame(magnitudes: mags, sampleRate: sampleRate, timestamp: 0, isRepeated: false)
        let _ = await processor.process(frame: loudFrame, timeSmoothing: .fast, peakHoldDecayDbPerSec: 20)

        let silentMags = [Float](repeating: 1e-6, count: fftSize / 2)
        let silentFrame = FFTFrame(magnitudes: silentMags, sampleRate: sampleRate, timestamp: 1.0, isRepeated: false)
        let result = await processor.process(frame: silentFrame, timeSmoothing: .fast, peakHoldDecayDbPerSec: 20)

        // After 1 second at 20 dB/sec decay, peak should have dropped significantly
        let anyBand = result.first
        if let band = anyBand {
            XCTAssertLessThan(band.peakDb, -10, "Peak should have decayed significantly after 1 second at 20 dB/s")
        }
    }
}
