import Foundation

/// Performs the per-band energy aggregation as an actor so the (potentially large, at
/// high band resolutions like 1/48-octave) per-frame computation runs off the main actor
/// and doesn't compete with SwiftUI rendering.
actor RTABandProcessor {
    private(set) var bands: [RTABand] = []
    private var smoothedEnergies: [Double] = []
    private var peakHolds: [Double] = []
    private var lastTimestamp: TimeInterval = 0
    private let resolution: RTABandResolution

    /// Equivalent noise bandwidth of the Hann window, in bins. A tone's power is smeared
    /// over ~1.5 bins' worth of squared magnitude, so summed band power is divided by this
    /// to read a 0 dBFS sine as 0 dB instead of +1.76 dB.
    static let hannENBW: Double = 1.5

    /// Per-band FFT bin weights, rebuilt whenever the FFT length or sample rate changes.
    /// Band `i` uses `weightBins[weightOffsets[i] ..< weightOffsets[i + 1]]`.
    private var weightBins: [Int] = []
    private var weightValues: [Double] = []
    private var weightOffsets: [Int] = []
    private var weightsBinCount = 0
    private var weightsSampleRate: Double = 0

    init(resolution: RTABandResolution, frequencyRangeLow: Double, frequencyRangeHigh: Double) {
        self.resolution = resolution
        let centers = Self.iec61260Centers(divisor: resolution.divisor,
                                            low: frequencyRangeLow,
                                            high: frequencyRangeHigh)
        let halfBand = pow(2.0, 1.0 / Double(2 * resolution.divisor))
        bands = centers.enumerated().map { idx, center in
            RTABand(id: idx, centerHz: center,
                    lowerHz: center / halfBand, upperHz: center * halfBand,
                    energyDb: -120, peakDb: -120)
        }
        smoothedEnergies = Array(repeating: 0, count: bands.count)
        peakHolds = Array(repeating: -120, count: bands.count)
    }

    func process(frame: FFTFrame, timeSmoothing: RTATimeSmoothing, peakHoldDecayDbPerSec: Double) -> [RTABand] {
        let binCount = frame.magnitudes.count
        guard binCount > 0, frame.sampleRate > 0 else { return bands }
        let now = frame.timestamp
        let dt = lastTimestamp > 0 ? min(max(now - lastTimestamp, 0), 0.5) : 0.05
        lastTimestamp = now
        let alpha = exp(-dt / timeSmoothing.tau)

        if binCount != weightsBinCount || frame.sampleRate != weightsSampleRate {
            rebuildWeights(binCount: binCount, sampleRate: frame.sampleRate)
        }

        frame.magnitudes.withUnsafeBufferPointer { mags in
            for i in bands.indices {
                var power: Double = 0
                var k = weightOffsets[i]
                let end = weightOffsets[i + 1]
                while k < end {
                    let m = Double(mags[weightBins[k]])
                    power += m * m * weightValues[k]
                    k += 1
                }
                power /= Self.hannENBW
                smoothedEnergies[i] = alpha * smoothedEnergies[i] + (1 - alpha) * power
                let db = smoothedEnergies[i] > 1e-12 ? 10 * log10(smoothedEnergies[i]) : -120
                peakHolds[i] = db > peakHolds[i] ? db : max(db, peakHolds[i] - peakHoldDecayDbPerSec * dt)
                bands[i].energyDb = db
                bands[i].peakDb = peakHolds[i]
            }
        }
        return bands
    }

    /// Each FFT bin k covers [(k − ½)·binHz, (k + ½)·binHz]. A band takes each bin's power
    /// in proportion to how much of that span lies inside the band, so:
    /// - every bin's power is counted exactly once across adjacent bands (the previous
    ///   round-outward edges counted edge bins in two bands), and
    /// - bands narrower than a bin (low frequencies at fine resolutions) get their share of
    ///   the bin instead of all reading the same whole bins.
    private func rebuildWeights(binCount: Int, sampleRate: Double) {
        let weights = Self.bandWeights(bands: bands, binCount: binCount, sampleRate: sampleRate)
        weightBins = weights.bins
        weightValues = weights.values
        weightOffsets = weights.offsets
        weightsBinCount = binCount
        weightsSampleRate = sampleRate
    }

    static func bandWeights(bands: [RTABand], binCount: Int, sampleRate: Double)
        -> (bins: [Int], values: [Double], offsets: [Int]) {
        let binHz = sampleRate / Double(binCount * 2)
        var bins: [Int] = []
        var values: [Double] = []
        var offsets: [Int] = [0]
        offsets.reserveCapacity(bands.count + 1)
        for band in bands {
            let first = max(0, Int((band.lowerHz / binHz - 0.5).rounded(.down)))
            let last = min(binCount - 1, Int((band.upperHz / binHz + 0.5).rounded(.up)))
            if first <= last {
                for k in first...last {
                    let binLow = (Double(k) - 0.5) * binHz
                    let binHigh = (Double(k) + 0.5) * binHz
                    let overlap = min(band.upperHz, binHigh) - max(band.lowerHz, binLow)
                    guard overlap > 0 else { continue }
                    bins.append(k)
                    values.append(overlap / binHz)
                }
            }
            offsets.append(bins.count)
        }
        return (bins, values, offsets)
    }

    static func iec61260Centers(divisor: Int, low: Double, high: Double) -> [Double] {
        let ref = 1000.0
        let kMin = Int(ceil(Double(divisor) * log2(low / ref)))
        let kMax = Int(floor(Double(divisor) * log2(high / ref)))
        guard kMin <= kMax else { return [] }
        return (kMin...kMax).compactMap { k -> Double? in
            let center = ref * pow(2.0, Double(k) / Double(divisor))
            return (center >= low * 0.99 && center <= high * 1.01) ? center : nil
        }
    }
}
