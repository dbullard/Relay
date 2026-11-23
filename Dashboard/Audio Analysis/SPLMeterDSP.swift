import Foundation

/// The SPL meter's signal processing for one input: A/C weighting filters and IEC 61672
/// exponential time weighting (Fast 125 ms, Slow 1 s) of the squared signal, plus per-block
/// energy for Leq. Pure and synchronous, so it can be validated against generated test
/// signals; `AudioInputProcessor` feeds it each capture buffer.
///
/// All levels are uncalibrated: dB relative to full scale RMS (a full-scale sine reads
/// −3.01 dB). The caller adds the input's calibration offset.
nonisolated struct SPLMeterDSP {
    struct Levels {
        var aFast: Double, aSlow: Double
        var cFast: Double, cSlow: Double
        var zFast: Double, zSlow: Double
        /// Sum of squared weighted samples in this block (for Leq).
        var sumA: Double, sumC: Double, sumZ: Double
        /// Highest time-weighted level reached within this block (Lmax), dB.
        var aFastMax: Double, aSlowMax: Double
        var cFastMax: Double, cSlowMax: Double
        var zFastMax: Double, zSlowMax: Double
        /// Largest absolute Z (unweighted) sample in this block.
        var peak: Double
        var sampleCount: Int
    }

    private struct SmoothPair {
        var fast: Double = 0
        var slow: Double = 0
    }

    static let fastTau = 0.125
    static let slowTau = 1.0

    let sampleRate: Double
    private var filterA: WeightingFilter?
    private var filterC: WeightingFilter?
    private var smoothA = SmoothPair()
    private var smoothC = SmoothPair()
    private var smoothZ = SmoothPair()
    private let alphaFast: Double
    private let alphaSlow: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        filterA = WeightingFilter(weighting: .a, sampleRate: sampleRate)
        filterC = WeightingFilter(weighting: .c, sampleRate: sampleRate)
        let dt = 1.0 / sampleRate
        alphaFast = exp(-dt / Self.fastTau)
        alphaSlow = exp(-dt / Self.slowTau)
    }

    /// dB of a mean-square value (RMS re full scale); −120 for silence.
    static func toDb(_ meanSquare: Double) -> Double {
        let rms = sqrt(max(0, meanSquare))
        return rms > 1e-10 ? 20 * log10(rms) : -120
    }

    mutating func process(_ samples: UnsafeBufferPointer<Double>) -> Levels {
        var sumA = 0.0, sumC = 0.0, sumZ = 0.0, peak = 0.0
        var maxAF = 0.0, maxAS = 0.0, maxCF = 0.0, maxCS = 0.0, maxZF = 0.0, maxZS = 0.0
        let aF = alphaFast, aS = alphaSlow
        for z in samples {
            let a = filterA?.processSample(z) ?? z
            let c = filterC?.processSample(z) ?? z
            let z2 = z * z, a2 = a * a, c2 = c * c
            smoothZ.fast = aF * smoothZ.fast + (1 - aF) * z2
            smoothZ.slow = aS * smoothZ.slow + (1 - aS) * z2
            smoothA.fast = aF * smoothA.fast + (1 - aF) * a2
            smoothA.slow = aS * smoothA.slow + (1 - aS) * a2
            smoothC.fast = aF * smoothC.fast + (1 - aF) * c2
            smoothC.slow = aS * smoothC.slow + (1 - aS) * c2
            peak = max(peak, abs(z))
            sumZ += z2; sumA += a2; sumC += c2
            maxAF = max(maxAF, smoothA.fast); maxAS = max(maxAS, smoothA.slow)
            maxCF = max(maxCF, smoothC.fast); maxCS = max(maxCS, smoothC.slow)
            maxZF = max(maxZF, smoothZ.fast); maxZS = max(maxZS, smoothZ.slow)
        }
        return Levels(
            aFast: Self.toDb(smoothA.fast), aSlow: Self.toDb(smoothA.slow),
            cFast: Self.toDb(smoothC.fast), cSlow: Self.toDb(smoothC.slow),
            zFast: Self.toDb(smoothZ.fast), zSlow: Self.toDb(smoothZ.slow),
            sumA: sumA, sumC: sumC, sumZ: sumZ,
            aFastMax: Self.toDb(maxAF), aSlowMax: Self.toDb(maxAS),
            cFastMax: Self.toDb(maxCF), cSlowMax: Self.toDb(maxCS),
            zFastMax: Self.toDb(maxZF), zSlowMax: Self.toDb(maxZS),
            peak: peak, sampleCount: samples.count
        )
    }

    /// Convenience for tests: process an array in one block.
    mutating func process(_ samples: [Double]) -> Levels {
        samples.withUnsafeBufferPointer { process($0) }
    }
}
