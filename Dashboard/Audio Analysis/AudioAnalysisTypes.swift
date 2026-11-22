import Foundation

// MARK: - Stream type aliases
typealias SPLStream = AsyncStream<SPLPayload>
typealias FFTStream = AsyncStream<FFTFrame>

// MARK: - SPL

nonisolated struct SPLPayload: Sendable, Equatable {
    var aFast: Double
    var aSlow: Double
    var cFast: Double
    var cSlow: Double
    var zFast: Double
    var zSlow: Double
    var caFast: Double
    var caSlow: Double
    /// Uncalibrated digital levels (dBFS): Z-weighted fast RMS and buffer peak.
    var rawDbFS: Double
    var rawPeakDbFS: Double
    // Instantaneous squared-amplitude power per weighting BEFORE IEC time-weighting.
    // Subscribers use these to compute correct LAeq over a window.
    var aInstantPower: Double
    var cInstantPower: Double
    var zInstantPower: Double
    var clippingWarning: Bool
    var headroomDb: Double
    var noiseFloorDbFS: Double
    var sampleRate: Double
    var timestamp: Date
    /// True when the input has stopped delivering audio (device unplugged, capture failed
    /// to start, audio session interrupted). Level fields are meaningless when set.
    var isStale: Bool
    // Running totals of calibrated squared-sample power since the processor was created,
    // per weighting, plus the matching sample count. They only ever grow, so a subscriber
    // can compute an exact Leq over any window from two payloads' differences — even when
    // the payloads in between were dropped by the stream's buffering policy.
    var cumulativeAPower: Double = 0
    var cumulativeCPower: Double = 0
    var cumulativeZPower: Double = 0
    var cumulativeSampleCount: Double = 0
    /// Calibration offset (dB) applied to this payload's levels.
    var calibrationOffsetDb: Double = 0

    static let empty = SPLPayload(
        aFast: .nan, aSlow: .nan, cFast: .nan, cSlow: .nan,
        zFast: .nan, zSlow: .nan, caFast: .nan, caSlow: .nan,
        rawDbFS: .nan, rawPeakDbFS: .nan,
        aInstantPower: 0, cInstantPower: 0, zInstantPower: 0,
        clippingWarning: false, headroomDb: 0, noiseFloorDbFS: 0,
        sampleRate: 44100, timestamp: Date(timeIntervalSince1970: 0), isStale: true
    )
}

// MARK: - FFT

nonisolated struct FFTFrame: Sendable, Equatable {
    var magnitudes: [Float]
    var sampleRate: Double
    var timestamp: TimeInterval
    var isRepeated: Bool

    /// Sent once when the input stops delivering audio. Carries no magnitudes.
    var isStale: Bool { magnitudes.isEmpty }

    static func stale(timestamp: TimeInterval) -> FFTFrame {
        FFTFrame(magnitudes: [], sampleRate: 0, timestamp: timestamp, isRepeated: true)
    }
}

// MARK: - RTA

nonisolated struct RTABand: Sendable, Identifiable, Equatable {
    var id: Int
    var centerHz: Double
    var lowerHz: Double
    var upperHz: Double
    var energyDb: Double  // dBFS
    var peakDb: Double    // dBFS
}

// MARK: - Spectrogram color map

enum SpectrogramPreset: String, Codable, CaseIterable {
    case firePlasma
    case greenPhosphor
    case purpleGlow
    case amber
    case custom
}

struct CodableGradientStop: Codable, Equatable {
    var position: Double      // 0.0 – 1.0
    var color: CodableColor
}

struct SpectrogramColorMap: Codable, Equatable {
    var preset: SpectrogramPreset
    var customStops: [CodableGradientStop]

    static let defaultFirePlasma = SpectrogramColorMap(preset: .firePlasma, customStops: [])
}

// MARK: - Shared enums

enum FrequencyScale: String, Codable, CaseIterable {
    case linear
    case logarithmic
}

