import XCTest
@testable import Relay

/// Accuracy checks for the audio-analysis fixes: weighting filters at every common sample
/// rate, RTA band energy accounting, and sample-rate-aware FFT sizing.
final class AudioAnalysisAccuracyTests: XCTestCase {

    // MARK: - Weighting filters

    /// Steady-state gain (dB) of a weighting filter for a sine at `hz`.
    private func weightingGainDb(_ weighting: DbWeighting, hz: Double, sampleRate: Double) throws -> Double {
        var filter = try XCTUnwrap(WeightingFilter(weighting: weighting, sampleRate: sampleRate),
                                   "No \(weighting) filter at \(sampleRate) Hz")
        let total = Int(sampleRate)          // 1 s
        let settle = total / 2               // ignore the first 0.5 s
        var inPower = 0.0, outPower = 0.0
        for n in 0..<total {
            let x = sin(2 * Double.pi * hz * Double(n) / sampleRate)
            let y = filter.processSample(x)
            if n >= settle { inPower += x * x; outPower += y * y }
        }
        return 10 * log10(outPower / inPower)
    }

    func testAWeightingMatchesIECAtCommonSampleRates() throws {
        // IEC 61672 A-weighting: 100 Hz −19.1 dB, 1 kHz 0 dB, 4 kHz +1.0 dB.
        for rate in [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0] {
            XCTAssertEqual(try weightingGainDb(.a, hz: 100, sampleRate: rate), -19.1, accuracy: 0.5, "100 Hz @ \(rate)")
            XCTAssertEqual(try weightingGainDb(.a, hz: 1_000, sampleRate: rate), 0, accuracy: 0.3, "1 kHz @ \(rate)")
            XCTAssertEqual(try weightingGainDb(.a, hz: 4_000, sampleRate: rate), 1.0, accuracy: 0.5, "4 kHz @ \(rate)")
        }
    }

    func testCWeightingMatchesIECAtCommonSampleRates() throws {
        // IEC 61672 C-weighting: 31.5 Hz −3.0 dB, 1 kHz 0 dB.
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            XCTAssertEqual(try weightingGainDb(.c, hz: 31.5, sampleRate: rate), -3.0, accuracy: 0.5, "31.5 Hz @ \(rate)")
            XCTAssertEqual(try weightingGainDb(.c, hz: 1_000, sampleRate: rate), 0, accuracy: 0.3, "1 kHz @ \(rate)")
        }
    }

    // MARK: - RTA bands

    func testBandWeightsCountEveryBinOnceAcrossContiguousBands() async {
        let processor = RTABandProcessor(resolution: .thirdOct, frequencyRangeLow: 20, frequencyRangeHigh: 20_000)
        let bands = await processor.bands
        let binCount = 2048
        let weights = RTABandProcessor.bandWeights(bands: bands, binCount: binCount, sampleRate: 48_000)
        var perBin = [Double](repeating: 0, count: binCount)
        for (bin, w) in zip(weights.bins, weights.values) { perBin[bin] += w }
        // Bins whose whole span is inside the covered range must sum to exactly 1 —
        // previously edge bins were counted in two neighbouring bands.
        let binHz = 48_000.0 / Double(binCount * 2)
        let lo = bands.first!.lowerHz, hi = bands.last!.upperHz
        for k in 0..<binCount {
            let spanLow = (Double(k) - 0.5) * binHz, spanHigh = (Double(k) + 0.5) * binHz
            guard spanLow >= lo, spanHigh <= hi else { continue }
            XCTAssertEqual(perBin[k], 1.0, accuracy: 1e-9, "bin \(k)")
        }
    }

    func testFullScaleToneReadsSameAsSPLMeterInItsBand() async {
        // A Hann-windowed full-scale tone spreads over neighbouring bins (amplitudes 1, ½, ½
        // for a bin-aligned tone with this normalisation). With the ENBW correction and RMS
        // scaling the band reads −3.01 dB, the same as the SPL meter's Z level for that tone.
        let processor = RTABandProcessor(resolution: .oct, frequencyRangeLow: 20, frequencyRangeHigh: 20_000)
        let binCount = 4096
        let sampleRate = 48_000.0
        let binHz = sampleRate / Double(binCount * 2)
        let toneBin = Int((1_000 / binHz).rounded())
        var mags = [Float](repeating: 0, count: binCount)
        mags[toneBin] = 1.0
        mags[toneBin - 1] = 0.5
        mags[toneBin + 1] = 0.5
        let frame = FFTFrame(magnitudes: mags, sampleRate: sampleRate, timestamp: 1, isRepeated: false)
        var result: [RTABand] = []
        // Let the time smoothing converge.
        for i in 0..<200 {
            var f = frame
            f.timestamp = 1 + Double(i) * 0.05
            result = await processor.process(frame: f, timeSmoothing: .fast, peakHoldDecayDbPerSec: 20)
        }
        let band1k = try? XCTUnwrap(result.first { abs($0.centerHz - 1_000) < 1 })
        XCTAssertEqual(band1k?.energyDb ?? -999, -3.01, accuracy: 0.1)
    }

    // MARK: - Decibel averaging

    func testPowerMeanOfDecibels() {
        XCTAssertEqual(DecibelMath.powerMean([70, 70, 70])!, 70, accuracy: 1e-9)
        // 60 and 70 dB: energy mean is 67.40 dB, not the arithmetic 65.
        XCTAssertEqual(DecibelMath.powerMean([60, 70])!, 67.40, accuracy: 0.01)
        XCTAssertEqual(DecibelMath.powerMean([-60, -50])!, -52.60, accuracy: 0.01)
        XCTAssertEqual(DecibelMath.powerMean([140, 140])!, 140, accuracy: 1e-9, "No overflow at high levels")
        XCTAssertNil(DecibelMath.powerMean([]))
        XCTAssertEqual(DecibelMath.powerMean([70, .nan])!, 70, accuracy: 1e-9)
    }

    // MARK: - FFT sizing

    func testFFTSizeScalesWithSampleRate() {
        let base = RTABandResolution.minimumFFTSize(for: .thirdOct)
        XCTAssertEqual(AudioInputProcessor.fftSize(for: .thirdOct, sampleRate: 44_100), base)
        XCTAssertEqual(AudioInputProcessor.fftSize(for: .thirdOct, sampleRate: 48_000), base)
        XCTAssertEqual(AudioInputProcessor.fftSize(for: .thirdOct, sampleRate: 96_000), base * 2)
        XCTAssertEqual(AudioInputProcessor.fftSize(for: .thirdOct, sampleRate: 192_000), base * 4)
        XCTAssertEqual(AudioInputProcessor.fftSize(for: .thirdOct, sampleRate: 0), base)
    }
}
