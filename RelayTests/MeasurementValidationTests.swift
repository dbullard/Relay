import XCTest
@testable import Relay

/// Validates Relay's SPL meter and RTA against the standards that sound level meters and
/// analysers like Smaart are judged by, using generated test signals:
///
/// - Frequency weighting (A, C) vs IEC 61672-1 Class 1 tolerances, 10 Hz – 20 kHz, at
///   44.1 / 48 / 96 / 192 kHz.
/// - Time weighting (Fast, Slow) tone-burst response and decay rate vs IEC 61672-1.
/// - Leq of signals with a known answer.
/// - RTA fractional-octave band levels for tones and noise, on the same RMS scale as the
///   SPL meter (so calibrated RTA levels agree with the meter).
///
/// Every measured value is also written to `relay-measurement-validation.txt` in the test
/// host's temporary directory, so deviations can be reviewed, not just pass/fail.
final class MeasurementValidationTests: XCTestCase {

    // MARK: - Report

    private static let reportURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("relay-measurement-validation.txt")

    private func report(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: Self.reportURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: Self.reportURL)
        }
    }

    // MARK: - Signals

    private func sine(_ hz: Double, amplitude: Double, seconds: Double, sampleRate: Double) -> [Double] {
        let n = Int(seconds * sampleRate)
        let w = 2 * Double.pi * hz / sampleRate
        return (0..<n).map { amplitude * sin(w * Double($0)) }
    }

    /// Deterministic Gaussian white noise (standard deviation `sigma`).
    private func whiteNoise(count: Int, sigma: Double, seed: UInt64 = 0x5EED) -> [Double] {
        var state = seed
        func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 11) + 0.5) / Double(1 << 53)
        }
        var out = [Double](repeating: 0, count: count)
        var i = 0
        while i < count {
            let u1 = uniform(), u2 = uniform()
            let r = sqrt(-2 * log(u1))
            out[i] = sigma * r * cos(2 * .pi * u2)
            if i + 1 < count { out[i + 1] = sigma * r * sin(2 * .pi * u2) }
            i += 2
        }
        return out
    }

    // MARK: - Frequency weighting (IEC 61672-1)

    /// IEC 61672-1 analytic A and C weightings (dB).
    private static func iecA(_ f: Double) -> Double {
        let f2 = f * f
        let ra = pow(12194, 2) * f2 * f2
            / ((f2 + pow(20.598997, 2)) * sqrt((f2 + pow(107.65265, 2)) * (f2 + pow(737.86223, 2))) * (f2 + pow(12194, 2)))
        return 20 * log10(ra) + 2.0
    }
    private static func iecC(_ f: Double) -> Double {
        let f2 = f * f
        let rc = pow(12194, 2) * f2 / ((f2 + pow(20.598997, 2)) * (f2 + pow(12194, 2)))
        return 20 * log10(rc) + 0.06
    }

    /// IEC 61672-1:2013 Class 1 acceptance limits (upper, lower) by nominal frequency.
    private static let class1Limits: [(f: Double, upper: Double, lower: Double)] = [
        (10, 3.0, -.infinity), (12.5, 2.5, -.infinity), (16, 2.0, -4.0), (20, 2.0, -2.0),
        (25, 2.0, -1.5), (31.5, 1.5, -1.5), (40, 1.0, -1.0), (50, 1.0, -1.0), (63, 1.0, -1.0),
        (80, 1.0, -1.0), (100, 1.0, -1.0), (125, 1.0, -1.0), (160, 1.0, -1.0), (200, 1.0, -1.0),
        (250, 1.0, -1.0), (315, 1.0, -1.0), (400, 1.0, -1.0), (500, 1.0, -1.0), (630, 1.0, -1.0),
        (800, 1.0, -1.0), (1000, 0.7, -0.7), (1250, 1.0, -1.0), (1600, 1.0, -1.0), (2000, 1.0, -1.0),
        (2500, 1.0, -1.0), (3150, 1.0, -1.0), (4000, 1.0, -1.0), (5000, 1.5, -1.5), (6300, 1.5, -2.0),
        (8000, 1.5, -2.5), (10000, 2.0, -3.0), (12500, 2.0, -5.0), (16000, 2.5, -16.0), (20000, 3.0, -.infinity),
    ]

    /// Measured weighting (dB, weighted level minus unweighted level) for a steady sine.
    private func measuredWeighting(hz: Double, sampleRate: Double) -> (a: Double, c: Double) {
        // Long enough for the low-frequency filter sections to settle, then measure.
        // One continuous sine (no phase jump between the settling and measuring parts), and
        // measure a whole number of cycles.
        let settleCount = Int(max(1.0, 20 / hz) * sampleRate)
        let measureCount = Int((Double(Int(max(0.5, 20 / hz) * hz)) / hz) * sampleRate)
        let tone = sine(hz, amplitude: 0.5, seconds: Double(settleCount + measureCount + 1) / sampleRate, sampleRate: sampleRate)
        var dsp = SPLMeterDSP(sampleRate: sampleRate)
        _ = dsp.process(Array(tone[0..<settleCount]))
        let measure = dsp.process(Array(tone[settleCount..<(settleCount + measureCount)]))
        return (10 * log10(measure.sumA / measure.sumZ), 10 * log10(measure.sumC / measure.sumZ))
    }

    func testFrequencyWeightingMeetsIECClass1() {
        report("== Frequency weighting vs IEC 61672-1 Class 1 (deviation = measured - IEC) ==")
        for rate in [44_100.0, 48_000.0, 96_000.0, 192_000.0] {
            var worst = (a: 0.0, c: 0.0)
            for limit in Self.class1Limits where limit.f < rate / 2 {
                let m = measuredWeighting(hz: limit.f, sampleRate: rate)
                let devA = m.a - Self.iecA(limit.f)
                let devC = m.c - Self.iecC(limit.f)
                worst.a = abs(devA) > abs(worst.a) ? devA : worst.a
                worst.c = abs(devC) > abs(worst.c) ? devC : worst.c
                report(String(format: "%6.0f Hz  %7.0f Hz  A %+.2f  C %+.2f  (limits %+.1f/%+.1f)",
                              rate, limit.f, devA, devC, limit.upper, limit.lower))
                XCTAssert(devA <= limit.upper && devA >= limit.lower,
                          String(format: "A-weighting %.0f Hz @ %.0f Hz off by %+.2f dB", limit.f, rate, devA))
                XCTAssert(devC <= limit.upper && devC >= limit.lower,
                          String(format: "C-weighting %.0f Hz @ %.0f Hz off by %+.2f dB", limit.f, rate, devC))
            }
            report(String(format: "%6.0f Hz  worst A %+.2f dB, worst C %+.2f dB", rate, worst.a, worst.c))
        }
    }

    /// Tighter than Class 1: within ±0.5 dB of the IEC curve from 10 Hz to 16 kHz at every
    /// supported sample rate (reference-grade analysers are judged at this level).
    func testFrequencyWeightingWithinHalfDecibelTo16kHz() {
        for rate in [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0] {
            for limit in Self.class1Limits where limit.f <= 16_000 && limit.f < rate / 2 {
                let m = measuredWeighting(hz: limit.f, sampleRate: rate)
                let devA = m.a - Self.iecA(limit.f), devC = m.c - Self.iecC(limit.f)
                XCTAssertEqual(devA, 0, accuracy: 0.5, String(format: "A %.0f Hz @ %.0f Hz: %+.2f dB", limit.f, rate, devA))
                XCTAssertEqual(devC, 0, accuracy: 0.5, String(format: "C %.0f Hz @ %.0f Hz: %+.2f dB", limit.f, rate, devC))
            }
        }
    }

    // MARK: - Time weighting (IEC 61672-1)

    /// Max Fast/Slow level reached by a 4 kHz tone burst, relative to the steady level.
    private func burstResponse(durationMs: Double, sampleRate: Double = 48_000) -> (fast: Double, slow: Double) {
        let amplitude = 0.5
        let steady = SPLMeterDSP.toDb(amplitude * amplitude / 2)
        var dsp = SPLMeterDSP(sampleRate: sampleRate)
        _ = dsp.process([Double](repeating: 0, count: Int(0.2 * sampleRate)))
        var signal = sine(4000, amplitude: amplitude, seconds: durationMs / 1000, sampleRate: sampleRate)
        signal += [Double](repeating: 0, count: Int(3 * sampleRate))
        let levels = dsp.process(signal)
        return (levels.zFastMax - steady, levels.zSlowMax - steady)
    }

    func testToneBurstResponseMeetsIECClass1() {
        report("== Tone-burst response (4 kHz) vs IEC 61672-1 ==")
        func tolerance(_ ms: Double) -> (upper: Double, lower: Double) {
            if ms >= 10 { return (0.5, -0.5) }
            if ms >= 1 { return (1.0, -1.5) }
            return (1.0, -3.0)
        }
        for ms in [1000.0, 500, 200, 100, 50, 20, 10, 5, 2, 1, 0.5, 0.25] {
            let r = burstResponse(durationMs: ms)
            let expectedFast = 10 * log10(1 - exp(-ms / 1000 / SPLMeterDSP.fastTau))
            let expectedSlow = 10 * log10(1 - exp(-ms / 1000 / SPLMeterDSP.slowTau))
            let devF = r.fast - expectedFast, devS = r.slow - expectedSlow
            report(String(format: "%7.2f ms  Fast %+.2f (IEC %+.1f, dev %+.2f)  Slow %+.2f (IEC %+.1f, dev %+.2f)",
                          ms, r.fast, expectedFast, devF, r.slow, expectedSlow, devS))
            let tol = tolerance(ms)
            XCTAssert(devF <= tol.upper && devF >= tol.lower, String(format: "Fast %.2f ms burst off by %+.2f dB", ms, devF))
            if ms >= 2 {
                XCTAssert(devS <= tol.upper && devS >= tol.lower, String(format: "Slow %.2f ms burst off by %+.2f dB", ms, devS))
            }
        }
    }

    func testDecayRates() {
        let rate = 48_000.0
        var dsp = SPLMeterDSP(sampleRate: rate)
        _ = dsp.process(sine(1000, amplitude: 0.5, seconds: 5, sampleRate: rate))
        _ = dsp.process([Double](repeating: 0, count: Int(0.1 * rate)))
        let a = dsp.process([Double](repeating: 0, count: 1))
        _ = dsp.process([Double](repeating: 0, count: Int(0.5 * rate)))
        let b = dsp.process([Double](repeating: 0, count: 1))
        let fastRate = (a.zFast - b.zFast) / 0.5
        let slowRate = (a.zSlow - b.zSlow) / 0.5
        report(String(format: "== Decay rates == Fast %.1f dB/s (IEC 34.7), Slow %.2f dB/s (IEC 4.3)", fastRate, slowRate))
        XCTAssertEqual(fastRate, 34.7, accuracy: 1.0)
        XCTAssertEqual(slowRate, 4.34, accuracy: 0.3)
    }

    // MARK: - Leq

    func testLeqOfKnownSignal() {
        // 10 s at -30 dB RMS then 10 s at -10 dB RMS: Leq = 10·log10((1e-3 + 1e-1) / 2) = -12.96 dB.
        let rate = 48_000.0
        var dsp = SPLMeterDSP(sampleRate: rate)
        let quiet = dsp.process(sine(1000, amplitude: pow(10, -30.0 / 20) * sqrt(2), seconds: 10, sampleRate: rate))
        let loud = dsp.process(sine(1000, amplitude: pow(10, -10.0 / 20) * sqrt(2), seconds: 10, sampleRate: rate))
        let leqZ = 10 * log10((quiet.sumZ + loud.sumZ) / Double(quiet.sampleCount + loud.sampleCount))
        report(String(format: "== Leq == measured %.3f dB, expected -12.964 dB", leqZ))
        XCTAssertEqual(leqZ, -12.964, accuracy: 0.01)
    }

    // MARK: - RTA bands

    /// Band levels (dB, energy-averaged over `frames` consecutive blocks, no smoothing),
    /// computed the way the app does: normal window plus the long low-frequency window.
    private func bandLevels(samples: [Double], resolution: RTABandResolution, sampleRate: Double,
                            frames: Int = 1) async -> [RTABand] {
        let size = AudioInputProcessor.fftSize(for: resolution, sampleRate: sampleRate)
        let longSize = size * AudioInputProcessor.lowFrequencyWindowFactor
        let analyzer = FFTAnalyzer(size: size)!
        let longAnalyzer = FFTAnalyzer(size: longSize)!
        let processor = RTABandProcessor(resolution: resolution, frequencyRangeLow: 20, frequencyRangeHigh: 20_000)
        var sums: [Double] = []
        var template: [RTABand] = []
        for f in 0..<frames {
            let block = samples[(f * longSize)..<((f + 1) * longSize)].map { Float($0) }
            let frame = FFTFrame(magnitudes: analyzer.amplitudeSpectrum(Array(block.suffix(size))),
                                 sampleRate: sampleRate, timestamp: 0, isRepeated: false,
                                 lowFrequencyMagnitudes: longAnalyzer.amplitudeSpectrum(block))
            let levels = await processor.instantaneousBands(frame: frame)
            if sums.isEmpty { sums = Array(repeating: 0, count: levels.count); template = levels }
            for (i, b) in levels.enumerated() { sums[i] += pow(10, b.energyDb / 10) }
        }
        return template.enumerated().map { i, b in
            var band = b
            band.energyDb = 10 * log10(sums[i] / Double(frames))
            return band
        }
    }

    func testRTAToneLevelsMatchSPLMeterScale() async {
        report("== RTA tone at each band centre (expected = SPL meter Z level of the tone) ==")
        let rate = 48_000.0
        let amplitude = 0.1
        let expected = SPLMeterDSP.toDb(amplitude * amplitude / 2) // -23.01 dB
        // Lowest band centre expected within ±0.5 dB, given the long window's resolution.
        let checkedFrom: [RTABandResolution: Double] = [.oct: 31, .thirdOct: 31, .twelfthOct: 63]
        for resolution in [RTABandResolution.oct, .thirdOct, .twelfthOct] {
            let centers = RTABandProcessor.iec61260Centers(divisor: resolution.divisor, low: 20, high: 20_000)
            let size = AudioInputProcessor.fftSize(for: resolution, sampleRate: rate)
            let longSize = size * AudioInputProcessor.lowFrequencyWindowFactor
            for (i, fc) in centers.enumerated() where i % max(1, resolution.divisor / 3) == 0 {
                let samples = sine(fc, amplitude: amplitude, seconds: Double(longSize) / rate + 0.01, sampleRate: rate)
                let bands = await bandLevels(samples: Array(samples.prefix(longSize)), resolution: resolution, sampleRate: rate)
                guard let band = bands.first(where: { abs($0.centerHz - fc) < 0.01 }) else { continue }
                let dev = band.energyDb - expected
                let line = String(format: "%@ %8.1f Hz  %+.2f dB", resolution.rawValue, fc, dev)
                report(line)
                if fc >= checkedFrom[resolution]! {
                    XCTAssertEqual(dev, 0, accuracy: 0.5, line)
                }
            }
        }
    }

    /// With the same calibration offset, the RTA band containing a tone reads what the SPL
    /// meter reads for it — Z and A weighted — so calibrated RTA levels are dB SPL.
    func testCalibratedRTAAgreesWithSPLMeter() async {
        report("== Calibrated RTA vs SPL meter (calibration offset 120 dB) ==")
        let rate = 48_000.0, cal = 120.0, amplitude = 0.1
        let size = AudioInputProcessor.fftSize(for: .thirdOct, sampleRate: rate)
        let analyzer = FFTAnalyzer(size: size)!
        for (hz, weighting) in [(1000.0, DbWeighting.z), (1000.0, .a), (100.0, .a), (100.0, .c), (4000.0, .a)] {
            var dsp = SPLMeterDSP(sampleRate: rate)
            _ = dsp.process(sine(hz, amplitude: amplitude, seconds: 2, sampleRate: rate))
            let m = dsp.process(sine(hz, amplitude: amplitude, seconds: 2, sampleRate: rate))
            let n = Double(m.sampleCount)
            let meter = (weighting == .a ? 10 * log10(m.sumA / n) : weighting == .c ? 10 * log10(m.sumC / n) : 10 * log10(m.sumZ / n)) + cal

            let processor = RTABandProcessor(resolution: .thirdOct, frequencyRangeLow: 20, frequencyRangeHigh: 20_000)
            let longSize = size * AudioInputProcessor.lowFrequencyWindowFactor
            let block = sine(hz, amplitude: amplitude, seconds: Double(longSize) / rate + 0.01, sampleRate: rate).prefix(longSize).map { Float($0) }
            let frame = FFTFrame(magnitudes: analyzer.amplitudeSpectrum(Array(block.suffix(size))), sampleRate: rate,
                                 timestamp: 0, isRepeated: false, calibrationOffsetDb: cal,
                                 lowFrequencyMagnitudes: FFTAnalyzer(size: longSize)!.amplitudeSpectrum(Array(block)))
            var bands: [RTABand] = []
            for i in 0..<100 {  // let the band smoothing settle
                var f = frame; f.timestamp = Double(i) * 0.05
                bands = await processor.process(frame: f, timeSmoothing: .fast, peakHoldDecayDbPerSec: 20,
                                                levelOffsetDb: f.calibrationOffsetDb, weighting: weighting)
            }
            let band = bands.min(by: { abs(log2($0.centerHz / hz)) < abs(log2($1.centerHz / hz)) })!
            let line = String(format: "%6.0f Hz %@  meter %.2f dB SPL, RTA %.2f dB SPL (%+.2f)",
                              hz, weighting.rawValue.uppercased(), meter, band.energyDb, band.energyDb - meter)
            report(line)
            XCTAssertEqual(band.energyDb, meter, accuracy: 0.3, line)
        }
    }

    func testRTAWhiteNoiseBandsConserveEnergy() async {
        report("== RTA white noise (1/3 octave): band level vs expected share of noise power ==")
        let rate = 48_000.0
        let sigma = 0.1
        let size = AudioInputProcessor.fftSize(for: .thirdOct, sampleRate: rate)
        let frames = 200
        let noise = whiteNoise(count: size * AudioInputProcessor.lowFrequencyWindowFactor * frames, sigma: sigma)
        let bands = await bandLevels(samples: noise, resolution: .thirdOct, sampleRate: rate, frames: frames)
        for band in bands {
            let width = band.upperHz - band.lowerHz
            let expected = 10 * log10(sigma * sigma * width / (rate / 2))
            let dev = band.energyDb - expected
            let line = String(format: "third %8.1f Hz  %+.2f dB", band.centerHz, dev)
            report(line)
            if band.centerHz >= 31 {
                XCTAssertEqual(dev, 0, accuracy: 0.5, line)
            }
        }
    }
}
