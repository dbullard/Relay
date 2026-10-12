import Foundation
import SwiftUI

nonisolated enum RTABandResolution: String, Codable, CaseIterable, Comparable {
    case oct          // 1-octave,  10 bands
    case thirdOct     // 1/3-octave, 31 bands
    case sixthOct     // 1/6-octave, 61 bands
    case twelfthOct   // 1/12-octave, 120 bands
    case twentyFourthOct // 1/24-octave, 240 bands
    case fortyEighthOct  // 1/48-octave, 478 bands

    var divisor: Int {
        switch self {
        case .oct: return 1
        case .thirdOct: return 3
        case .sixthOct: return 6
        case .twelfthOct: return 12
        case .twentyFourthOct: return 24
        case .fortyEighthOct: return 48
        }
    }

    var displayTitle: String {
        switch self {
        case .oct: return "1-Octave"
        case .thirdOct: return "1/3-Octave"
        case .sixthOct: return "1/6-Octave"
        case .twelfthOct: return "1/12-Octave"
        case .twentyFourthOct: return "1/24-Octave"
        case .fortyEighthOct: return "1/48-Octave"
        }
    }

    static func minimumFFTSize(for resolution: RTABandResolution) -> Int {
        switch resolution {
        case .oct:            return 2048
        case .thirdOct:       return 4096
        case .sixthOct:       return 8192
        case .twelfthOct:     return 8192
        case .twentyFourthOct: return 16384
        case .fortyEighthOct:  return 16384
        }
    }

    private var order: Int {
        switch self {
        case .oct: return 0
        case .thirdOct: return 1
        case .sixthOct: return 2
        case .twelfthOct: return 3
        case .twentyFourthOct: return 4
        case .fortyEighthOct: return 5
        }
    }
    static func < (lhs: RTABandResolution, rhs: RTABandResolution) -> Bool { lhs.order < rhs.order }
}

enum RTADisplayMode: String, Codable, CaseIterable {
    case bars
    case filledCurve

    var displayTitle: String {
        switch self {
        case .bars: return "Bars"
        case .filledCurve: return "Filled Curve"
        }
    }
}

enum RTATimeSmoothing: String, Codable, CaseIterable {
    case fast
    case slow

    var tau: Double { self == .fast ? 0.125 : 1.0 }
}

struct RTAModuleModel: Codable, Equatable {
    var inputID: UUID?
    /// Extra sources overlaid on the RTA as colored line traces, in addition to `inputID`.
    var additionalInputIDs: [UUID]
    /// Sources (primary `inputID` or entries in `additionalInputIDs`) currently hidden
    /// from the display via the on-tile legend, without removing them from the module.
    var hiddenSourceIDs: Set<UUID>
    var bandResolution: RTABandResolution
    var displayMode: RTADisplayMode
    var showPeakHold: Bool
    var peakHoldDecayDbPerSec: Double
    var timeSmoothing: RTATimeSmoothing
    var frequencyRangeLow: Double
    var frequencyRangeHigh: Double
    var dBRangeLow: Double
    var dBRangeHigh: Double
    var limitColorEnabled: Bool
    var limitColorNormal: CodableColor
    var limitColorWarning: CodableColor
    var limitColorAlert: CodableColor
    var limitWarningDb: Double
    var limitAlertDb: Double
    var showFrequencyAxis: Bool
    var showDBAxis: Bool
    var opacity: Double
    var isEnabled: Bool
    var isArmedByUser: Bool
    var showsTitle: Bool

    init(
        inputID: UUID? = nil,
        additionalInputIDs: [UUID] = [],
        hiddenSourceIDs: Set<UUID> = [],
        bandResolution: RTABandResolution = .thirdOct,
        displayMode: RTADisplayMode = .bars,
        showPeakHold: Bool = true,
        peakHoldDecayDbPerSec: Double = 20,
        timeSmoothing: RTATimeSmoothing = .fast,
        frequencyRangeLow: Double = 20,
        frequencyRangeHigh: Double = 20000,
        dBRangeLow: Double = -60,
        dBRangeHigh: Double = 0,
        limitColorEnabled: Bool = false,
        limitColorNormal: CodableColor = CodableColor(.white),
        limitColorWarning: CodableColor = CodableColor(.yellow),
        limitColorAlert: CodableColor = CodableColor(.red),
        limitWarningDb: Double = -12,
        limitAlertDb: Double = -6,
        showFrequencyAxis: Bool = true,
        showDBAxis: Bool = true,
        opacity: Double = 1.0,
        isEnabled: Bool = true,
        isArmedByUser: Bool = false,
        showsTitle: Bool = false
    ) {
        self.inputID = inputID
        self.additionalInputIDs = additionalInputIDs
        self.hiddenSourceIDs = hiddenSourceIDs
        self.bandResolution = bandResolution
        self.displayMode = displayMode
        self.showPeakHold = showPeakHold
        self.peakHoldDecayDbPerSec = peakHoldDecayDbPerSec
        self.timeSmoothing = timeSmoothing
        self.frequencyRangeLow = frequencyRangeLow
        self.frequencyRangeHigh = frequencyRangeHigh
        self.dBRangeLow = dBRangeLow
        self.dBRangeHigh = dBRangeHigh
        self.limitColorEnabled = limitColorEnabled
        self.limitColorNormal = limitColorNormal
        self.limitColorWarning = limitColorWarning
        self.limitColorAlert = limitColorAlert
        self.limitWarningDb = limitWarningDb
        self.limitAlertDb = limitAlertDb
        self.showFrequencyAxis = showFrequencyAxis
        self.showDBAxis = showDBAxis
        self.opacity = max(0.1, min(1.0, opacity))
        self.isEnabled = isEnabled
        self.isArmedByUser = isArmedByUser
        self.showsTitle = showsTitle
    }

    private enum CodingKeys: String, CodingKey {
        case inputID, additionalInputIDs, hiddenSourceIDs, bandResolution, displayMode, showPeakHold, peakHoldDecayDbPerSec,
             timeSmoothing, frequencyRangeLow, frequencyRangeHigh, dBRangeLow, dBRangeHigh,
             limitColorEnabled, limitColorNormal, limitColorWarning, limitColorAlert,
             limitWarningDb, limitAlertDb, showFrequencyAxis, showDBAxis, opacity,
             isEnabled, isArmedByUser, showsTitle
    }

    /// Decodes leniently with defaults for any field, so documents saved before a field
    /// was added (e.g. `opacity`) keep loading as RTA modules instead of falling back
    /// to the generic clock module.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputID = try c.decodeIfPresent(UUID.self, forKey: .inputID)
        additionalInputIDs = try c.decodeIfPresent([UUID].self, forKey: .additionalInputIDs) ?? []
        hiddenSourceIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .hiddenSourceIDs) ?? []
        bandResolution = try c.decodeIfPresent(RTABandResolution.self, forKey: .bandResolution) ?? .thirdOct
        displayMode = try c.decodeIfPresent(RTADisplayMode.self, forKey: .displayMode) ?? .bars
        showPeakHold = try c.decodeIfPresent(Bool.self, forKey: .showPeakHold) ?? true
        peakHoldDecayDbPerSec = try c.decodeIfPresent(Double.self, forKey: .peakHoldDecayDbPerSec) ?? 20
        timeSmoothing = try c.decodeIfPresent(RTATimeSmoothing.self, forKey: .timeSmoothing) ?? .fast
        frequencyRangeLow = try c.decodeIfPresent(Double.self, forKey: .frequencyRangeLow) ?? 20
        frequencyRangeHigh = try c.decodeIfPresent(Double.self, forKey: .frequencyRangeHigh) ?? 20000
        dBRangeLow = try c.decodeIfPresent(Double.self, forKey: .dBRangeLow) ?? -60
        dBRangeHigh = try c.decodeIfPresent(Double.self, forKey: .dBRangeHigh) ?? 0
        limitColorEnabled = try c.decodeIfPresent(Bool.self, forKey: .limitColorEnabled) ?? false
        limitColorNormal = try c.decodeIfPresent(CodableColor.self, forKey: .limitColorNormal) ?? CodableColor(red: 1, green: 1, blue: 1)
        limitColorWarning = try c.decodeIfPresent(CodableColor.self, forKey: .limitColorWarning) ?? CodableColor(red: 1, green: 1, blue: 0)
        limitColorAlert = try c.decodeIfPresent(CodableColor.self, forKey: .limitColorAlert) ?? CodableColor(red: 1, green: 0, blue: 0)
        limitWarningDb = try c.decodeIfPresent(Double.self, forKey: .limitWarningDb) ?? -12
        limitAlertDb = try c.decodeIfPresent(Double.self, forKey: .limitAlertDb) ?? -6
        showFrequencyAxis = try c.decodeIfPresent(Bool.self, forKey: .showFrequencyAxis) ?? true
        showDBAxis = try c.decodeIfPresent(Bool.self, forKey: .showDBAxis) ?? true
        let decodedOpacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        opacity = max(0.1, min(1.0, decodedOpacity))
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isArmedByUser = try c.decodeIfPresent(Bool.self, forKey: .isArmedByUser) ?? false
        showsTitle = try c.decodeIfPresent(Bool.self, forKey: .showsTitle) ?? false
    }
}
