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
        let now = frame.timestamp
        let dt = lastTimestamp > 0 ? min(max(now - lastTimestamp, 0), 0.5) : 0.05
        lastTimestamp = now
        let alpha = exp(-dt / timeSmoothing.tau)
        let binHz = frame.sampleRate / Double(frame.magnitudes.count * 2)

        for i in bands.indices {
            let startBin = max(0, Int((bands[i].lowerHz / binHz).rounded(.down)))
            let endBin = min(frame.magnitudes.count - 1, Int((bands[i].upperHz / binHz).rounded(.up)))
            var power: Double = 0
            if startBin <= endBin {
                for bin in startBin...endBin {
                    let m = Double(frame.magnitudes[bin])
                    power += m * m
                }
            }
            smoothedEnergies[i] = alpha * smoothedEnergies[i] + (1 - alpha) * power
            let db = smoothedEnergies[i] > 0 ? 10 * log10(smoothedEnergies[i]) : -120
            peakHolds[i] = db > peakHolds[i] ? db : max(db, peakHolds[i] - peakHoldDecayDbPerSec * dt)
            bands[i].energyDb = db
            bands[i].peakDb = peakHolds[i]
        }
        return bands
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
