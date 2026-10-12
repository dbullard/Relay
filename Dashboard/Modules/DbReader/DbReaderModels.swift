import Foundation
import SwiftUI
import AVFoundation

// MARK: - Models / Enums / Settings

enum DbReaderSourceKind: String, Codable, CaseIterable {
    case microphone
}

nonisolated enum DbWeighting: String, Codable, CaseIterable {
    case a
    case c
    case z
    case ca
}

enum DbTimeWeighting: String, Codable, CaseIterable {
    case fast
    case slow
}

enum DbReaderGraphLineMode: String, Codable, CaseIterable {
    case rawSpl
    case averageSpl
}

struct DbReaderAudioDevice: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let name: String
}

enum DbReaderAudioDevices {
    static func microphones() -> [DbReaderAudioDevice] {
        #if os(macOS)
        let mapped = AudioDeviceEnumerator.inputDevices().map { DbReaderAudioDevice(uid: $0.uid, name: $0.name) }
        return mapped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #else
        let mapped = AudioDeviceEnumerator.inputDevices().map { DbReaderAudioDevice(uid: $0.uid, name: $0.name) }
        return mapped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #endif
    }

    static func defaultMicrophoneUID() -> String? {
        #if os(macOS)
        return AVCaptureDevice.default(for: .audio)?.uniqueID
        #else
        let session = AVAudioSession.sharedInstance()
        return session.preferredInput?.uid ?? session.availableInputs?.first?.uid
        #endif
    }
}

struct DbReaderModuleModel: Codable, Equatable {
    var isEnabled: Bool

    var inputID: UUID?
    var showsTitle: Bool

    var weighting: DbWeighting
    var timeWeighting: DbTimeWeighting

    var averagingEnabled: Bool
    var averagingWindowSeconds: Double

    var showMainValue: Bool
    var showGraph: Bool
    var graphHeight: Double
    var showGraphUnits: Bool

    /// The graph always mirrors the main SPL display: averaged when averaging is enabled, raw otherwise.
    var graphLineMode: DbReaderGraphLineMode {
        averagingEnabled ? .averageSpl : .rawSpl
    }

    var publishHz: Double
    var isArmedByUser: Bool

    var historyWindowSeconds: Double
    var historyMaxSeconds: Double

    var exportIncludeRawDbFS: Bool
    var exportIncludePeak: Bool

    var limitColorEnabled: Bool
    var limitWarningDb: Double
    var limitAlertDb: Double
    var limitColorNormal: CodableColor
    var limitColorWarning: CodableColor
    var limitColorAlert: CodableColor

    var showBarMeter: Bool
    var caUpperLimit: Double
    var caLowerLimit: Double

    init(
        isEnabled: Bool = true,
        inputID: UUID? = nil,
        showsTitle: Bool = false,
        weighting: DbWeighting = .a,
        timeWeighting: DbTimeWeighting = .fast,
        averagingEnabled: Bool = false,
        averagingWindowSeconds: Double = 60,
        showMainValue: Bool = true,
        showGraph: Bool = true,
        graphHeight: Double = 120,
        showGraphUnits: Bool = true,
        publishHz: Double = 10,
        isArmedByUser: Bool = false,
        historyWindowSeconds: Double = 30,
        historyMaxSeconds: Double = 600,
        exportIncludeRawDbFS: Bool = true,
        exportIncludePeak: Bool = true,
        limitColorEnabled: Bool = false,
        limitWarningDb: Double = 90,
        limitAlertDb: Double = 100,
        limitColorNormal: CodableColor = CodableColor(.white),
        limitColorWarning: CodableColor = CodableColor(.yellow),
        limitColorAlert: CodableColor = CodableColor(.red),
        showBarMeter: Bool = false,
        caUpperLimit: Double = 12.0,
        caLowerLimit: Double = 8.0
    ) {
        self.isEnabled = isEnabled
        self.inputID = inputID
        self.showsTitle = showsTitle
        self.weighting = weighting
        self.timeWeighting = timeWeighting
        self.averagingEnabled = averagingEnabled
        self.averagingWindowSeconds = max(1, averagingWindowSeconds)
        self.showMainValue = showMainValue
        self.showGraph = showGraph
        self.graphHeight = max(120, graphHeight)
        self.showGraphUnits = showGraphUnits
        self.publishHz = min(20, max(1, publishHz))
        self.isArmedByUser = isArmedByUser
        self.historyWindowSeconds = max(5, historyWindowSeconds)
        self.historyMaxSeconds = max(30, historyMaxSeconds)
        self.exportIncludeRawDbFS = exportIncludeRawDbFS
        self.exportIncludePeak = exportIncludePeak
        self.limitColorEnabled = limitColorEnabled
        self.limitWarningDb = limitWarningDb
        self.limitAlertDb = limitAlertDb
        self.limitColorNormal = limitColorNormal
        self.limitColorWarning = limitColorWarning
        self.limitColorAlert = limitColorAlert
        self.showBarMeter = showBarMeter
        self.caUpperLimit = caUpperLimit
        self.caLowerLimit = caLowerLimit
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case inputID
        // Legacy keys — decoded only for migration, never encoded
        case sourceKind
        case deviceUID
        case channelIndex
        case calibrationOffsetDb  // migrated to AudioInputConfig.calibrationOffsetDb
        case graphLineMode  // removed — graph now always mirrors averagingEnabled
        case showsTitle
        case weighting
        case timeWeighting
        case averagingEnabled
        case averagingWindowSeconds
        case showMainValue
        case showGraph
        case graphHeight
        case showGraphUnits
        case publishHz
        case isArmedByUser
        case historyWindowSeconds
        case historyMaxSeconds
        case exportIncludeRawDbFS
        case exportIncludePeak
        case limitColorEnabled
        case limitWarningDb
        case limitAlertDb
        case limitColorNormal
        case limitColorWarning
        case limitColorAlert
        case showBarMeter
        case caUpperLimit
        case caLowerLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        inputID = try container.decodeIfPresent(UUID.self, forKey: .inputID)
        if inputID == nil {
            let legacyUID = try container.decodeIfPresent(String.self, forKey: .deviceUID)
            let legacyCh  = try container.decodeIfPresent(Int.self, forKey: .channelIndex) ?? 0
            if legacyUID != nil || legacyCh != 0 {
                let store = AudioInputsConfigStore.shared
                if let existing = store.inputs.first(where: { $0.deviceUID == legacyUID && $0.channelIndex == legacyCh }) {
                    inputID = existing.id
                } else {
                    let deviceName = legacyUID.flatMap { uid in
                        DbReaderAudioDevices.microphones().first(where: { $0.uid == uid })?.name
                    } ?? "Migrated Input"
                    let newConfig = AudioInputConfig(name: deviceName, deviceUID: legacyUID, channelIndex: legacyCh)
                    store.inputs.append(newConfig)
                    inputID = newConfig.id
                }
            }
        }

        showsTitle = try container.decodeIfPresent(Bool.self, forKey: .showsTitle) ?? false
        weighting = try container.decodeIfPresent(DbWeighting.self, forKey: .weighting) ?? .a
        timeWeighting = try container.decodeIfPresent(DbTimeWeighting.self, forKey: .timeWeighting) ?? .fast
        averagingEnabled = try container.decodeIfPresent(Bool.self, forKey: .averagingEnabled) ?? false
        averagingWindowSeconds = try container.decodeIfPresent(Double.self, forKey: .averagingWindowSeconds) ?? 60
        showMainValue = try container.decodeIfPresent(Bool.self, forKey: .showMainValue) ?? true
        showGraph = try container.decodeIfPresent(Bool.self, forKey: .showGraph) ?? true
        graphHeight = max(120, try container.decodeIfPresent(Double.self, forKey: .graphHeight) ?? 120)
        showGraphUnits = try container.decodeIfPresent(Bool.self, forKey: .showGraphUnits) ?? true
        publishHz = min(20, max(1, try container.decodeIfPresent(Double.self, forKey: .publishHz) ?? 10))
        isArmedByUser = try container.decodeIfPresent(Bool.self, forKey: .isArmedByUser) ?? false

        // Migration: per-tile calibrationOffsetDb was moved to AudioInputConfig.calibrationOffsetDb.
        // If a saved dashboard has a non-zero value here, copy it to the input (once) so calibration
        // isn't silently lost when loading old dashboards. The field is no longer encoded going forward.
        let legacyCal = try container.decodeIfPresent(Double.self, forKey: .calibrationOffsetDb) ?? 0
        if legacyCal != 0, let inputID = inputID,
           let idx = AudioInputsConfigStore.shared.inputs.firstIndex(where: { $0.id == inputID }),
           AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb == 0 {
            AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb = legacyCal
        }
        historyWindowSeconds = try container.decodeIfPresent(Double.self, forKey: .historyWindowSeconds) ?? 30
        historyMaxSeconds = try container.decodeIfPresent(Double.self, forKey: .historyMaxSeconds) ?? 600
        exportIncludeRawDbFS = try container.decodeIfPresent(Bool.self, forKey: .exportIncludeRawDbFS) ?? true
        exportIncludePeak = try container.decodeIfPresent(Bool.self, forKey: .exportIncludePeak) ?? true
        limitColorEnabled = try container.decodeIfPresent(Bool.self, forKey: .limitColorEnabled) ?? false
        limitWarningDb = try container.decodeIfPresent(Double.self, forKey: .limitWarningDb) ?? 90
        limitAlertDb = try container.decodeIfPresent(Double.self, forKey: .limitAlertDb) ?? 100
        limitColorNormal = try container.decodeIfPresent(CodableColor.self, forKey: .limitColorNormal) ?? CodableColor(.white)
        limitColorWarning = try container.decodeIfPresent(CodableColor.self, forKey: .limitColorWarning) ?? CodableColor(.yellow)
        limitColorAlert = try container.decodeIfPresent(CodableColor.self, forKey: .limitColorAlert) ?? CodableColor(.red)
        showBarMeter = try container.decodeIfPresent(Bool.self, forKey: .showBarMeter) ?? false
        caUpperLimit = try container.decodeIfPresent(Double.self, forKey: .caUpperLimit) ?? 12.0
        caLowerLimit = try container.decodeIfPresent(Double.self, forKey: .caLowerLimit) ?? 8.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(inputID, forKey: .inputID)
        try container.encode(showsTitle, forKey: .showsTitle)
        try container.encode(weighting, forKey: .weighting)
        try container.encode(timeWeighting, forKey: .timeWeighting)
        try container.encode(averagingEnabled, forKey: .averagingEnabled)
        try container.encode(averagingWindowSeconds, forKey: .averagingWindowSeconds)
        try container.encode(showMainValue, forKey: .showMainValue)
        try container.encode(showGraph, forKey: .showGraph)
        try container.encode(graphHeight, forKey: .graphHeight)
        try container.encode(showGraphUnits, forKey: .showGraphUnits)
        try container.encode(publishHz, forKey: .publishHz)
        try container.encode(isArmedByUser, forKey: .isArmedByUser)
        // Note: calibrationOffsetDb is intentionally not encoded — it now lives in AudioInputConfig.
        try container.encode(historyWindowSeconds, forKey: .historyWindowSeconds)
        try container.encode(historyMaxSeconds, forKey: .historyMaxSeconds)
        try container.encode(exportIncludeRawDbFS, forKey: .exportIncludeRawDbFS)
        try container.encode(exportIncludePeak, forKey: .exportIncludePeak)
        try container.encode(limitColorEnabled, forKey: .limitColorEnabled)
        try container.encode(limitWarningDb, forKey: .limitWarningDb)
        try container.encode(limitAlertDb, forKey: .limitAlertDb)
        try container.encode(limitColorNormal, forKey: .limitColorNormal)
        try container.encode(limitColorWarning, forKey: .limitColorWarning)
        try container.encode(limitColorAlert, forKey: .limitColorAlert)
        try container.encode(showBarMeter, forKey: .showBarMeter)
        try container.encode(caUpperLimit, forKey: .caUpperLimit)
        try container.encode(caLowerLimit, forKey: .caLowerLimit)
        // Note: sourceKind, deviceUID, channelIndex are legacy keys — not encoded.
    }
}

struct DbSample: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let graphTimestamp: TimeInterval
    let spl: Double
    let peak: Double
    let rawDbFS: Double
    let rawPeakDbFS: Double
}

// MARK: - Output Payload / Notifications

struct DbWeightingSnapshot: Equatable {
    var aFast: Double
    var aSlow: Double
    var cFast: Double
    var cSlow: Double
    var zFast: Double
    var zSlow: Double
    var caFast: Double
    var caSlow: Double
}

struct DbReaderOutputPayload: Equatable {
    var spl: Double
    var peak: Double
    var rawDbFS: Double
    var rawPeakDbFS: Double
    var weighting: DbWeighting
    var timeWeighting: DbTimeWeighting
    var caSlow: Double?
    var timestamp: Date
    var isStale: Bool

    static let empty = DbReaderOutputPayload(
        spl: 0,
        peak: 0,
        rawDbFS: 0,
        rawPeakDbFS: 0,
        weighting: .z,
        timeWeighting: .fast,
        caSlow: nil,
        timestamp: Date(timeIntervalSince1970: 0),
        isStale: true
    )
}

extension Notification.Name {
    static let dbReaderDidPublish = Notification.Name("Relay.DbReader.DidPublish")
    static let dbReaderClearRequested = Notification.Name("Relay.DbReader.ClearRequested")
}

// MARK: - Display Snapshot

struct DbReaderDisplaySnapshot: Equatable {
    var currentSpl: Double
    var currentSplSlow: Double
    var currentZSlow: Double
    var displaySpl: Double
    var averagingProgress: Double
    var currentPeak: Double
    var rawDbFS: Double
    var rawPeakDbFS: Double
    var rawAWeightedDbFS: Double
    var rawAcDbFS: Double
    var rawDcDbFS: Double
    var estimatedFrequencyHz: Double
    var clippingWarning: Bool
    var headroomDb: Double
    var noiseFloorDbFS: Double
    var frozenPayload: DbReaderOutputPayload
    var frozenAveragingProgress: Double

    static let empty = DbReaderDisplaySnapshot(
        currentSpl: 0,
        currentSplSlow: 0,
        currentZSlow: 0,
        displaySpl: 0,
        averagingProgress: 0,
        currentPeak: 0,
        rawDbFS: 0,
        rawPeakDbFS: 0,
        rawAWeightedDbFS: Double.nan,
        rawAcDbFS: Double.nan,
        rawDcDbFS: Double.nan,
        estimatedFrequencyHz: Double.nan,
        clippingWarning: false,
        headroomDb: 0,
        noiseFloorDbFS: 0,
        frozenPayload: .empty,
        frozenAveragingProgress: 0
    )
}
