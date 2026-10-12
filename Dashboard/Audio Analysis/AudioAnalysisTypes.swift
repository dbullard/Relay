import Foundation

// MARK: - Stream type aliases
typealias SPLStream = AsyncStream<SPLPayload>
typealias FFTStream = AsyncStream<FFTFrame>

// MARK: - SPL

struct SPLPayload: Sendable, Equatable {
    var aFast: Double
    var aSlow: Double
    var cFast: Double
    var cSlow: Double
    var zFast: Double
    var zSlow: Double
    var caFast: Double
    var caSlow: Double
    var rawDbFS: Double
    var rawPeakDbFS: Double
    // Instantaneous squared-amplitude power per weighting BEFORE IEC time-weighting.
    // Subscribers use these to compute correct LAeq over a window.
    var aInstantPower: Double
    var cInstantPower: Double
    var zInstantPower: Double
    var estimatedFrequencyHz: Double  // .nan if unavailable
    var clippingWarning: Bool
    var headroomDb: Double
    var noiseFloorDbFS: Double
    var sampleRate: Double
    var timestamp: Date
    var isStale: Bool

    static let empty = SPLPayload(
        aFast: .nan, aSlow: .nan, cFast: .nan, cSlow: .nan,
        zFast: .nan, zSlow: .nan, caFast: .nan, caSlow: .nan,
        rawDbFS: .nan, rawPeakDbFS: .nan,
        aInstantPower: 0, cInstantPower: 0, zInstantPower: 0,
        estimatedFrequencyHz: .nan,
        clippingWarning: false, headroomDb: 0, noiseFloorDbFS: 0,
        sampleRate: 44100, timestamp: Date(timeIntervalSince1970: 0), isStale: true
    )
}

// MARK: - FFT

struct FFTFrame: Sendable, Equatable {
    var magnitudes: [Float]
    var sampleRate: Double
    var timestamp: TimeInterval
    var isRepeated: Bool
}

// MARK: - RTA

struct RTABand: Sendable, Identifiable, Equatable {
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

