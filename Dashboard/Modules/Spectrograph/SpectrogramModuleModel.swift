import Foundation
import SwiftUI

struct SpectrogramModuleModel: Codable, Equatable {
    var inputID: UUID?
    var frequencyScale: FrequencyScale
    var dBRangeLow: Double
    var dBRangeHigh: Double
    var scrollRate: Double
    var colorMap: SpectrogramColorMap
    var showFrequencyAxis: Bool
    var showTimeAxis: Bool
    var opacity: Double
    var isEnabled: Bool
    var isArmedByUser: Bool
    var showsTitle: Bool
    /// When true, follow the primary input source and dB range of the RTA module
    /// in this dashboard tab, instead of this module's own settings.
    var linkToRTA: Bool

    init(
        inputID: UUID? = nil,
        frequencyScale: FrequencyScale = .logarithmic,
        dBRangeLow: Double = -90,
        dBRangeHigh: Double = 0,
        scrollRate: Double = 24,
        colorMap: SpectrogramColorMap = .defaultFirePlasma,
        showFrequencyAxis: Bool = true,
        showTimeAxis: Bool = false,
        opacity: Double = 1.0,
        isEnabled: Bool = true,
        isArmedByUser: Bool = false,
        showsTitle: Bool = false,
        linkToRTA: Bool = false
    ) {
        self.inputID = inputID
        self.frequencyScale = frequencyScale
        self.dBRangeLow = dBRangeLow
        self.dBRangeHigh = dBRangeHigh
        self.scrollRate = max(1, min(60, scrollRate))
        self.colorMap = colorMap
        self.showFrequencyAxis = showFrequencyAxis
        self.showTimeAxis = showTimeAxis
        self.opacity = max(0.1, min(1.0, opacity))
        self.isEnabled = isEnabled
        self.isArmedByUser = isArmedByUser
        self.showsTitle = showsTitle
        self.linkToRTA = linkToRTA
    }

    private enum CodingKeys: String, CodingKey {
        case inputID, frequencyScale, dBRangeLow, dBRangeHigh, scrollRate, colorMap,
             showFrequencyAxis, showTimeAxis, opacity, isEnabled, isArmedByUser, showsTitle, linkToRTA
    }

    /// Decodes leniently with defaults for any field, so documents saved before a field
    /// was added (e.g. `opacity`) keep loading as Spectrograph modules instead of falling
    /// back to the generic clock module.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputID = try c.decodeIfPresent(UUID.self, forKey: .inputID)
        frequencyScale = try c.decodeIfPresent(FrequencyScale.self, forKey: .frequencyScale) ?? .logarithmic
        dBRangeLow = try c.decodeIfPresent(Double.self, forKey: .dBRangeLow) ?? -90
        dBRangeHigh = try c.decodeIfPresent(Double.self, forKey: .dBRangeHigh) ?? 0
        let decodedScrollRate = try c.decodeIfPresent(Double.self, forKey: .scrollRate) ?? 24
        scrollRate = max(1, min(60, decodedScrollRate))
        colorMap = try c.decodeIfPresent(SpectrogramColorMap.self, forKey: .colorMap) ?? .defaultFirePlasma
        showFrequencyAxis = try c.decodeIfPresent(Bool.self, forKey: .showFrequencyAxis) ?? true
        showTimeAxis = try c.decodeIfPresent(Bool.self, forKey: .showTimeAxis) ?? false
        let decodedOpacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        opacity = max(0.1, min(1.0, decodedOpacity))
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isArmedByUser = try c.decodeIfPresent(Bool.self, forKey: .isArmedByUser) ?? false
        showsTitle = try c.decodeIfPresent(Bool.self, forKey: .showsTitle) ?? false
        linkToRTA = try c.decodeIfPresent(Bool.self, forKey: .linkToRTA) ?? false
    }
}

// MARK: - Color LUT

struct SpectrogramLUT {
    let table: [UInt32]   // 256 ARGB entries

    init(colorMap: SpectrogramColorMap) {
        table = Self.buildLUT(colorMap: colorMap)
    }

    func color(normalizedValue: Float) -> UInt32 {
        table[Int(max(0, min(1, normalizedValue)) * 255)]
    }

    private static func buildLUT(colorMap: SpectrogramColorMap) -> [UInt32] {
        typealias Stop = (position: Double, r: Double, g: Double, b: Double)
        let stops: [Stop]
        switch colorMap.preset {
        case .firePlasma:
            stops = [(0.0,0,0,0),(0.25,0,0,0.5),(0.5,0,0.8,0.8),(0.75,1,1,0),(1.0,1,0,0)]
        case .greenPhosphor:
            stops = [(0,0,0,0),(0.4,0,0.2,0),(1,0,1,0)]
        case .purpleGlow:
            stops = [(0,0,0,0),(0.5,0.5,0,0.8),(1,1,1,1)]
        case .amber:
            stops = [(0,0,0,0),(0.5,0.8,0.4,0),(1,1,0.9,0.7)]
        case .custom:
            if colorMap.customStops.count >= 2 {
                stops = colorMap.customStops.map { s in (s.position, Double(s.color.red), Double(s.color.green), Double(s.color.blue)) }
            } else {
                stops = [(0,0,0,0),(1,1,1,1)]
            }
        }
        return (0...255).map { idx -> UInt32 in
            let t = Double(idx) / 255.0
            var lo = stops.first!, hi = stops.last!
            for i in 0..<(stops.count - 1) {
                if t >= stops[i].position && t <= stops[i+1].position { lo = stops[i]; hi = stops[i+1]; break }
            }
            let span = hi.position - lo.position
            let f = span > 0 ? (t - lo.position) / span : 0
            func lerp(_ a: Double, _ b: Double) -> UInt32 { UInt32(max(0, min(255, (a + f * (b - a)) * 255))) }
            return (0xFF << 24) | (lerp(lo.r, hi.r) << 16) | (lerp(lo.g, hi.g) << 8) | lerp(lo.b, hi.b)
        }
    }
}
