//
//  DAWTransportModule.swift
//  Relay
//
//  Created by Codex on 5/9/26.
//

import SwiftUI
import Foundation
import CoreMIDI
import Combine

enum DAWTransportCommand: String, CaseIterable, Codable, Identifiable {
    case rewind
    case stop
    case play
    case record
    case fastForward

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rewind:
            return "Rewind"
        case .stop:
            return "Stop"
        case .play:
            return "Play"
        case .record:
            return "Record"
        case .fastForward:
            return "Fast Forward"
        }
    }

    var systemImage: String {
        switch self {
        case .rewind:
            return "backward.fill"
        case .stop:
            return "stop.fill"
        case .play:
            return "play.fill"
        case .record:
            return "record.circle.fill"
        case .fastForward:
            return "forward.fill"
        }
    }
}

enum DAWTransportType: String, CaseIterable, Codable, Identifiable {
    case proToolsHUI
    case logicProHUI
    case reaperHUI
    case reaperMCU
    case cubaseNuendoHUI
    case digitalPerformerHUI
    case genericHUI
    case genericMTCMMC

    var id: String { rawValue }

    static var selectableCases: [DAWTransportType] {
        if RelayLicensingConfig.isPreviewEnabled {
            return allCases
        }
        return [.proToolsHUI, .genericHUI]
    }

    var normalizedForCurrentBuild: DAWTransportType {
        Self.runtimeType(stored: self, previewEnabled: RelayLicensingConfig.isPreviewEnabled)
    }

    /// Runtime fallback never changes the user's saved protocol.
    static func runtimeType(stored: DAWTransportType, previewEnabled: Bool) -> DAWTransportType {
        if previewEnabled || [.proToolsHUI, .genericHUI].contains(stored) {
            return stored
        }
        return stored.supportsHUI ? .genericHUI : .proToolsHUI
    }

    var title: String {
        profileInfo.title
    }

    var preferredCommandMode: DAWTransportCommandMode {
        switch self {
        case .proToolsHUI, .logicProHUI, .reaperHUI, .cubaseNuendoHUI, .digitalPerformerHUI, .genericHUI:
            return .hui
        case .reaperMCU:
            return .mcu
        case .genericMTCMMC:
            return .mmc
        }
    }

    var defaultDisplayMode: DAWTransportDisplayMode {
        switch self {
        case .genericMTCMMC:
            return .timecode
        case .proToolsHUI, .logicProHUI, .reaperHUI, .reaperMCU, .cubaseNuendoHUI, .digitalPerformerHUI, .genericHUI:
            return .automatic
        }
    }

    var supportsHUI: Bool {
        switch self {
        case .proToolsHUI, .logicProHUI, .reaperHUI, .cubaseNuendoHUI, .digitalPerformerHUI, .genericHUI:
            return true
        case .reaperMCU, .genericMTCMMC:
            return false
        }
    }

    var supportsMCU: Bool {
        self == .reaperMCU
    }

    var prefersHUIInAuto: Bool {
        supportsHUI
    }

    var prefersMCUInAuto: Bool {
        supportsMCU
    }

    var requiresHUIPingReply: Bool {
        profileInfo.requiresHUIPingReply
    }

    var supportsDisplayFeedback: Bool {
        switch self {
        case .proToolsHUI, .logicProHUI, .reaperHUI, .reaperMCU, .cubaseNuendoHUI, .digitalPerformerHUI, .genericHUI:
            return true
        case .genericMTCMMC:
            return false
        }
    }

    var setupHelpText: String {
        profileInfo.setupSummary
    }

    var profileInfo: DAWTransportProfileInfo {
        switch self {
        case .proToolsHUI:
            return DAWTransportProfileInfo(
                title: "Pro Tools HUI",
                protocolLabel: "HUI",
                setupSummary: "Setup > MIDI > MIDI Input Devices: enable Relay HUI input. Setup > Peripherals > MIDI Controllers: Type = HUI, Receive From = Relay HUI Out, Send To = Relay HUI In.",
                expectedCounterSource: "Pro Tools main counter over HUI SysEx",
                supportedCounterFormats: "SMPTE, Bars|Beats, Feet+Frames, Minutes:Seconds, Samples, or other Pro Tools main counter modes",
                recommendedDisplayMode: .automatic,
                requiresBidirectionalMIDI: true,
                requiresHUIPingReply: true,
                troubleshootingNotes: "The HUI display follows the Pro Tools main counter only. It does not expose the Pro Tools sub counter."
            )
        case .logicProHUI:
            return DAWTransportProfileInfo(
                title: "Logic Pro HUI",
                protocolLabel: "HUI",
                setupSummary: "Logic Pro > Control Surfaces > Setup > New > Install: select HUI, then assign MIDI In and MIDI Out.",
                expectedCounterSource: "Logic HUI display",
                supportedCounterFormats: "SMPTE or Bars/Beats/Divisions/Ticks",
                recommendedDisplayMode: .automatic,
                requiresBidirectionalMIDI: true,
                requiresHUIPingReply: false,
                troubleshootingNotes: "Dotted or pipe-separated musical counters are treated as bars/beats."
            )
        case .reaperHUI:
            return DAWTransportProfileInfo(
                title: "REAPER HUI",
                protocolLabel: "HUI",
                setupSummary: "Options > Preferences > Control/OSC/web: add HUI and assign MIDI In and MIDI Out.",
                expectedCounterSource: "REAPER HUI display",
                supportedCounterFormats: "Varies by control surface setup; obvious timecode and musical counters are detected",
                recommendedDisplayMode: .automatic,
                requiresBidirectionalMIDI: true,
                requiresHUIPingReply: false,
                troubleshootingNotes: "Relay preserves raw REAPER display text unless the format is obvious."
            )
        case .reaperMCU:
            return DAWTransportProfileInfo(
                title: "REAPER MCU",
                protocolLabel: "Mackie Control Universal",
                setupSummary: "Options > Preferences > Control/OSC/web: add Mackie Control Universal and assign MIDI In and MIDI Out.",
                expectedCounterSource: "REAPER MCU display",
                supportedCounterFormats: "REAPER Mackie Control counter display; obvious timecode and musical counters are detected",
                recommendedDisplayMode: .automatic,
                requiresBidirectionalMIDI: true,
                requiresHUIPingReply: false,
                troubleshootingNotes: "Use this when REAPER is set to Mackie Universal. HUI Partial may accept buttons but usually does not send the counter Relay needs."
            )
        case .cubaseNuendoHUI:
            return DAWTransportProfileInfo(
                title: "Cubase/Nuendo HUI",
                protocolLabel: "HUI compatibility",
                setupSummary: "Studio Setup: add Mackie HUI and assign MIDI ports.",
                expectedCounterSource: "Cubase/Nuendo HUI-compatible display",
                supportedCounterFormats: "DAW main counter formats; conservative parsing",
                recommendedDisplayMode: .automatic,
                requiresBidirectionalMIDI: true,
                requiresHUIPingReply: false,
                troubleshootingNotes: "Relay prefers raw fallback over forced formatting for this profile."
            )
        case .digitalPerformerHUI:
            return DAWTransportProfileInfo(
                title: "Digital Performer HUI",
                protocolLabel: "HUI compatibility",
                setupSummary: "Control Surface Setup: add or select HUI and assign MIDI ports.",
                expectedCounterSource: "Digital Performer HUI-compatible display",
                supportedCounterFormats: "DAW main counter formats; conservative parsing",
                recommendedDisplayMode: .automatic,
                requiresBidirectionalMIDI: true,
                requiresHUIPingReply: false,
                troubleshootingNotes: "Relay preserves raw display unless the format is confidently detected."
            )
        case .genericHUI:
            return DAWTransportProfileInfo(
                title: "Generic HUI",
                protocolLabel: "HUI",
                setupSummary: "Configure the DAW or device as a HUI control surface and assign Relay MIDI In and Out ports.",
                expectedCounterSource: "HUI display",
                supportedCounterFormats: "Explicit timecode, bars/beats, feet+frames, samples, or raw fallback",
                recommendedDisplayMode: .automatic,
                requiresBidirectionalMIDI: true,
                requiresHUIPingReply: false,
                troubleshootingNotes: "This is the most conservative HUI profile."
            )
        case .genericMTCMMC:
            return DAWTransportProfileInfo(
                title: "Generic MTC/MMC",
                protocolLabel: "MTC/MMC",
                setupSummary: "Configure the DAW or device to send MIDI Timecode and receive MIDI Machine Control on the selected ports.",
                expectedCounterSource: "MIDI Timecode",
                supportedCounterFormats: "MTC timecode only",
                recommendedDisplayMode: .timecode,
                requiresBidirectionalMIDI: false,
                requiresHUIPingReply: false,
                troubleshootingNotes: "Use this when the DAW does not provide a HUI display counter."
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "proTools":
            self = .proToolsHUI
        case "logicPro":
            self = .logicProHUI
        case "mackieControlUniversal":
            self = .reaperMCU
        case "genericMMC":
            self = .genericMTCMMC
        default:
            self = DAWTransportType(rawValue: rawValue) ?? .proToolsHUI
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct DAWTransportProfileInfo: Equatable {
    var title: String
    var protocolLabel: String
    var setupSummary: String
    var expectedCounterSource: String
    var supportedCounterFormats: String
    var recommendedDisplayMode: DAWTransportDisplayMode
    var requiresBidirectionalMIDI: Bool
    var requiresHUIPingReply: Bool
    var troubleshootingNotes: String
}

enum DAWTransportCommandMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case mmc
    case mcu
    case hui

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Auto"
        case .mmc:
            return "MMC"
        case .mcu:
            return "MCU"
        case .hui:
            return "HUI"
        }
    }
}

enum DAWTransportDisplayMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case clock
    case timecode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "DAW main counter"
        case .clock:
            return "DAW main as HH:MM:SS"
        case .timecode:
            return "MTC only"
        }
    }
}

private enum DAWTransportDisplayModeResolver {
    static func selectableModes(for dawType: DAWTransportType) -> [DAWTransportDisplayMode] {
        dawType.supportsDisplayFeedback ? [.automatic, .timecode] : [.timecode]
    }

    static func normalized(_ mode: DAWTransportDisplayMode, for dawType: DAWTransportType) -> DAWTransportDisplayMode {
        selectableModes(for: dawType).contains(mode) ? mode : dawType.defaultDisplayMode
    }
}

private enum DAWTransportProtocol: String {
    case mmc = "MMC"
    case mcu = "MCU"
    case hui = "HUI"
}

enum DAWTransportFrameRateSetting: String, CaseIterable, Codable, Identifiable {
    case auto
    case fps23976
    case fps24
    case fps25
    case fps2997Drop
    case fps2997NonDrop
    case fps30

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .fps23976:
            return "23.976"
        case .fps24:
            return "24"
        case .fps25:
            return "25"
        case .fps2997Drop:
            return "29.97 drop"
        case .fps2997NonDrop:
            return "29.97 non-drop"
        case .fps30:
            return "30"
        }
    }

    func resolvedFrameRate(autoDetected: DAWTransportResolvedFrameRate?) -> DAWTransportResolvedFrameRate? {
        switch self {
        case .auto:
            return autoDetected
        case .fps23976:
            return .fps23976
        case .fps24:
            return .fps24
        case .fps25:
            return .fps25
        case .fps2997Drop:
            return .fps2997Drop
        case .fps2997NonDrop:
            return .fps2997NonDrop
        case .fps30:
            return .fps30
        }
    }
}

enum DAWTransportResolvedFrameRate: String, Codable, Equatable {
    case fps23976
    case fps24
    case fps25
    case fps2997Drop
    case fps2997NonDrop
    case fps30

    static func autoDetected(rateBits: Int) -> DAWTransportResolvedFrameRate? {
        switch rateBits {
        case 0:
            return .fps24
        case 1:
            return .fps25
        case 2:
            return .fps2997Drop
        case 3:
            return .fps30
        default:
            return nil
        }
    }

    var label: String {
        switch self {
        case .fps23976:
            return "23.976"
        case .fps24:
            return "24"
        case .fps25:
            return "25"
        case .fps2997Drop:
            return "29.97 DF"
        case .fps2997NonDrop:
            return "29.97 NDF"
        case .fps30:
            return "30"
        }
    }

    var framesPerSecond: Double {
        switch self {
        case .fps23976:
            return 24_000.0 / 1_001.0
        case .fps24:
            return 24.0
        case .fps25:
            return 25.0
        case .fps2997Drop, .fps2997NonDrop:
            return 30_000.0 / 1_001.0
        case .fps30:
            return 30.0
        }
    }

    var nominalFramesPerSecond: Int {
        switch self {
        case .fps23976, .fps24:
            return 24
        case .fps25:
            return 25
        case .fps2997Drop, .fps2997NonDrop, .fps30:
            return 30
        }
    }
}

struct DAWTransportModuleConfiguration: Codable, Equatable {
    var dawType: DAWTransportType = .proToolsHUI
    var connectionName: String = ""
    var midiInputSourceID: Int32? = nil
    var midiOutputDestinationID: Int32? = nil
    var frameRateSetting: DAWTransportFrameRateSetting = .auto
    var commandMode: DAWTransportCommandMode = .automatic
    var displayMode: DAWTransportDisplayMode = .automatic
    var appendMTCToDAWDisplay: Bool = false
    var showHeader: Bool = true
    var showTimer: Bool = true
    var showTransportButtons: Bool = true
    var showDebugUI: Bool = true

    static func `default`() -> DAWTransportModuleConfiguration {
        var configuration = DAWTransportModuleConfiguration()
        configuration.commandMode = configuration.dawType.preferredCommandMode
        configuration.displayMode = configuration.dawType.defaultDisplayMode
        return configuration
    }

    init() {}

    var trimmedConnectionName: String {
        connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCustomConnectionName: Bool {
        !trimmedConnectionName.isEmpty
    }

    var resolvedConnectionName: String {
        hasCustomConnectionName ? trimmedConnectionName : dawType.title
    }

    private enum CodingKeys: String, CodingKey {
        case dawType
        case connectionName
        case midiInputSourceID
        case midiOutputDestinationID
        case frameRateSetting
        case commandMode
        case displayMode
        case appendMTCToDAWDisplay
        case showHeader
        case showTimer
        case showTransportButtons
        case showDebugUI
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dawType = try container.decodeIfPresent(DAWTransportType.self, forKey: .dawType) ?? .proToolsHUI
        connectionName = try container.decodeIfPresent(String.self, forKey: .connectionName) ?? ""
        midiInputSourceID = try container.decodeIfPresent(Int32.self, forKey: .midiInputSourceID)
        midiOutputDestinationID = try container.decodeIfPresent(Int32.self, forKey: .midiOutputDestinationID)
        frameRateSetting = try container.decodeIfPresent(DAWTransportFrameRateSetting.self, forKey: .frameRateSetting) ?? .auto
        commandMode = try container.decodeIfPresent(DAWTransportCommandMode.self, forKey: .commandMode) ?? dawType.preferredCommandMode
        displayMode = try container.decodeIfPresent(DAWTransportDisplayMode.self, forKey: .displayMode) ?? dawType.defaultDisplayMode
        appendMTCToDAWDisplay = try container.decodeIfPresent(Bool.self, forKey: .appendMTCToDAWDisplay) ?? false
        showHeader = try container.decodeIfPresent(Bool.self, forKey: .showHeader) ?? true
        showTimer = try container.decodeIfPresent(Bool.self, forKey: .showTimer) ?? true
        showTransportButtons = try container.decodeIfPresent(Bool.self, forKey: .showTransportButtons) ?? true
        showDebugUI = try container.decodeIfPresent(Bool.self, forKey: .showDebugUI) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dawType, forKey: .dawType)
        try container.encode(connectionName, forKey: .connectionName)
        try container.encodeIfPresent(midiInputSourceID, forKey: .midiInputSourceID)
        try container.encodeIfPresent(midiOutputDestinationID, forKey: .midiOutputDestinationID)
        try container.encode(frameRateSetting, forKey: .frameRateSetting)
        try container.encode(commandMode, forKey: .commandMode)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(appendMTCToDAWDisplay, forKey: .appendMTCToDAWDisplay)
        try container.encode(showHeader, forKey: .showHeader)
        try container.encode(showTimer, forKey: .showTimer)
        try container.encode(showTransportButtons, forKey: .showTransportButtons)
        try container.encode(showDebugUI, forKey: .showDebugUI)
    }
}

struct DAWTransportConnectionLabel: Equatable {
    var title: String
    var subtitle: String?
}

enum DAWTransportConnectionLabelResolver {
    static func resolve(
        configuration: DAWTransportModuleConfiguration,
        midiOutputName: String? = nil,
        midiInputName: String? = nil
    ) -> DAWTransportConnectionLabel {
        let profileTitle = configuration.dawType.title

        if let connectionName = sanitized(configuration.connectionName) {
            return label(title: connectionName, profileTitle: profileTitle)
        }

        if let outputName = sanitized(midiOutputName) {
            return label(title: outputName, profileTitle: profileTitle)
        }

        if let inputName = sanitized(midiInputName) {
            return label(title: inputName, profileTitle: profileTitle)
        }

        return DAWTransportConnectionLabel(title: profileTitle, subtitle: nil)
    }

    private static func label(title: String, profileTitle: String) -> DAWTransportConnectionLabel {
        let subtitle = title == profileTitle ? nil : profileTitle
        return DAWTransportConnectionLabel(title: title, subtitle: subtitle)
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum DAWTransportConnectionState: String {
    case connected
    case paused
    case stale
    case disconnected

    var title: String {
        switch self {
        case .connected:
            return "Connected"
        case .paused:
            return "Paused"
        case .stale:
            return "Stale"
        case .disconnected:
            return "Disconnected"
        }
    }

    var systemImage: String {
        switch self {
        case .connected:
            return "dot.radiowaves.left.and.right"
        case .paused:
            return "pause.circle.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .disconnected:
            return "slash.circle"
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            return .green
        case .paused:
            return .secondary
        case .stale:
            return .orange
        case .disconnected:
            return .secondary
        }
    }

    /// `hasKnownTransportPlayState` is false until the DAW has sent at least one
    /// HUI/MCU transport control update. Some DAW protocols (pure MTC followers)
    /// never send one, so a stale signal with an unknown play state falls back to
    /// `.stale` rather than guessing `.paused`.
    static func resolved(
        hasFreshSignal: Bool,
        hasStaleSignal: Bool,
        hasKnownTransportPlayState: Bool,
        isPlaying: Bool
    ) -> DAWTransportConnectionState {
        if hasFreshSignal {
            return .connected
        }
        if hasStaleSignal {
            if hasKnownTransportPlayState, !isPlaying {
                return .paused
            }
            return .stale
        }
        return .disconnected
    }
}

struct DAWTimecode: Codable, Equatable {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var frames: Int

    static let placeholder = "--:--:--:--"

    var formatted: String {
        String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    var clockFormatted: String {
        String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func advanced(by elapsed: TimeInterval, frameRate: DAWTransportResolvedFrameRate) -> DAWTimecode {
        let additionalFrames = max(0, Int((elapsed * frameRate.framesPerSecond).rounded(.down)))
        return advanced(byFrames: additionalFrames, nominalFramesPerSecond: frameRate.nominalFramesPerSecond)
    }

    private func advanced(byFrames additionalFrames: Int, nominalFramesPerSecond: Int) -> DAWTimecode {
        guard nominalFramesPerSecond > 0 else { return self }

        let secondsPerDay = 24 * 60 * 60
        let currentFrameCount =
            ((((hours * 60) + minutes) * 60) + seconds) * nominalFramesPerSecond
            + frames
        let wrappedFrameCount = (currentFrameCount + additionalFrames) % (secondsPerDay * nominalFramesPerSecond)

        let totalSeconds = wrappedFrameCount / nominalFramesPerSecond
        let nextFrames = wrappedFrameCount % nominalFramesPerSecond
        let nextHours = (totalSeconds / 3600) % 24
        let nextMinutes = (totalSeconds / 60) % 60
        let nextSeconds = totalSeconds % 60

        return DAWTimecode(hours: nextHours, minutes: nextMinutes, seconds: nextSeconds, frames: nextFrames)
    }
}

struct DAWMTCUpdate: Equatable {
    var timecode: DAWTimecode
    var detectedFrameRate: DAWTransportResolvedFrameRate?
    var receivedAt: Date
}

struct DAWHUIDisplayUpdate: Equatable {
    var text: String
    var receivedAt: Date
}

struct DAWMCUDisplayUpdate: Equatable {
    var text: String
    var receivedAt: Date
}

enum DAWCounterKind: String, Codable, Equatable {
    case timecode
    case barsBeats
    case feetFrames
    case samples
    case clock
    case unknown
}

enum DAWCounterSource: String, Codable {
    case huiDisplay
    case mcuDisplay
    case mtc
}

enum DAWCounterConfidence: String, Codable {
    case explicit
    case inferred
    case rawFallback
}

struct DAWCounterDisplay: Equatable {
    var rawText: String
    var displayText: String
    var kind: DAWCounterKind
    var source: DAWCounterSource
    var confidence: DAWCounterConfidence
    var receivedAt: Date
}

enum DAWDisplayFeedbackMode: Equatable {
    case timecode
    case barsBeats
    case feetFrames
}

enum DAWCounterClassifier {
    static func classify(
        rawText: String,
        explicitFeedbackMode: DAWDisplayFeedbackMode?,
        dawType: DAWTransportType,
        source: DAWCounterSource = .huiDisplay,
        receivedAt: Date = Date()
    ) -> DAWCounterDisplay {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DAWCounterDisplay(
                rawText: rawText,
                displayText: rawText,
                kind: .unknown,
                source: source,
                confidence: .rawFallback,
                receivedAt: receivedAt
            )
        }

        if source == .mtc {
            return DAWCounterDisplay(
                rawText: rawText,
                displayText: trimmed,
                kind: .timecode,
                source: source,
                confidence: .explicit,
                receivedAt: receivedAt
            )
        }

        if explicitFeedbackMode == .barsBeats || isBarsBeats(trimmed) {
            return DAWCounterDisplay(
                rawText: rawText,
                displayText: normalizeBarsBeats(trimmed),
                kind: .barsBeats,
                source: source,
                confidence: explicitFeedbackMode == .barsBeats ? .explicit : .inferred,
                receivedAt: receivedAt
            )
        }

        if explicitFeedbackMode == .feetFrames || isFeetFrames(trimmed) {
            return DAWCounterDisplay(
                rawText: rawText,
                displayText: trimmed,
                kind: .feetFrames,
                source: source,
                confidence: explicitFeedbackMode == .feetFrames ? .explicit : .inferred,
                receivedAt: receivedAt
            )
        }

        if isSamples(trimmed) {
            return DAWCounterDisplay(
                rawText: rawText,
                displayText: trimmed,
                kind: .samples,
                source: source,
                confidence: .inferred,
                receivedAt: receivedAt
            )
        }

        if let timecode = classifiedTimecode(trimmed, explicitFeedbackMode: explicitFeedbackMode, dawType: dawType) {
            return DAWCounterDisplay(
                rawText: rawText,
                displayText: timecode.text,
                kind: timecode.kind,
                source: source,
                confidence: timecode.confidence,
                receivedAt: receivedAt
            )
        }

        return DAWCounterDisplay(
            rawText: rawText,
            displayText: trimmed,
            kind: .unknown,
            source: source,
            confidence: .rawFallback,
            receivedAt: receivedAt
        )
    }

    private static func isBarsBeats(_ text: String) -> Bool {
        let separator: Character?
        if text.contains("|") {
            separator = "|"
        } else if text.contains(".") {
            separator = "."
        } else {
            separator = nil
        }

        guard let separator else { return false }
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isWholeNumber) }
    }

    private static func normalizeBarsBeats(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: ".")
    }

    private static func isFeetFrames(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return text.contains("+")
            || lowercased.contains("ft")
            || text.contains("'")
            || text.contains("′")
    }

    private static func isSamples(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.contains("sample") || lowercased.hasSuffix("smp") {
            return true
        }
        return false
    }

    private static func classifiedTimecode(
        _ text: String,
        explicitFeedbackMode: DAWDisplayFeedbackMode?,
        dawType: DAWTransportType
    ) -> (text: String, kind: DAWCounterKind, confidence: DAWCounterConfidence)? {
        _ = dawType
        if let separated = separatedTimecode(text) {
            return (separated, separated.split(separator: ":").count == 3 ? .clock : .timecode, .inferred)
        }

        guard text.count == 8, text.allSatisfy(\.isWholeNumber) else { return nil }
        guard explicitFeedbackMode == .timecode else {
            return nil
        }

        let hour = Int(text.prefix(2)) ?? 0
        let minute = Int(text.dropFirst(2).prefix(2)) ?? 0
        let second = Int(text.dropFirst(4).prefix(2)) ?? 0
        let frame = Int(text.dropFirst(6).prefix(2)) ?? 0
        guard minute <= 59, second <= 59, frame <= 99 else { return nil }

        let formatted = String(format: "%02d:%02d:%02d:%02d", hour, minute, second, frame)
        return (formatted, .timecode, .explicit)
    }

    private static func separatedTimecode(_ text: String) -> String? {
        let isNegative = text.hasPrefix("-")
        let unsigned = isNegative ? String(text.dropFirst()) : text
        let separator: Character?
        if unsigned.contains(":") {
            separator = ":"
        } else if unsigned.contains(";") {
            separator = ";"
        } else {
            separator = nil
        }

        guard let separator else { return nil }
        let parts = unsigned.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isWholeNumber) }) else { return nil }

        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        if values.indices.contains(1), values[1] > 59 { return nil }
        if values.indices.contains(2), values[2] > 59 { return nil }
        if values.indices.contains(3), values[3] > 99 { return nil }

        return text
    }
}

private struct DAWHUIControlUpdate: Equatable {
    var transportStates: [DAWTransportCommand: Bool]
    var displayFeedbackMode: DAWDisplayFeedbackMode?
    var receivedAt: Date
}

private struct DAWMCUControlUpdate: Equatable {
    var transportStates: [DAWTransportCommand: Bool]
    var receivedAt: Date
}

enum DAWTransportCommandEncoder {
    private static let huiTransportNoteByCommand: [DAWTransportCommand: UInt8] = [
        .rewind: 91,
        .fastForward: 92,
        .stop: 93,
        .play: 94,
        .record: 95
    ]
    private static let proToolsHUITransportPortByCommand: [DAWTransportCommand: UInt8] = [
        .rewind: 0x01,
        .fastForward: 0x02,
        .stop: 0x03,
        .play: 0x04,
        .record: 0x05
    ]
    private static let proToolsHUITransportZone: UInt8 = 0x0E
    private static let mcuTransportNoteByCommand: [DAWTransportCommand: UInt8] = [
        .rewind: 0x5B,
        .fastForward: 0x5C,
        .stop: 0x5D,
        .play: 0x5E,
        .record: 0x5F
    ]

    static let huiPingRequest: [UInt8] = [0x90, 0x00, 0x00]
    static let huiPingReply: [UInt8] = [0x90, 0x00, 0x7F]

    static func encode(
        command: DAWTransportCommand,
        configuration: DAWTransportModuleConfiguration,
        isInputConnected: Bool,
        isOutputConnected: Bool
    ) -> [UInt8] {
        switch resolvedProtocol(
            configuration: configuration,
            isInputConnected: isInputConnected,
            isOutputConnected: isOutputConnected
        ) {
        case .mmc:
            return encodeMMC(command: command)
        case .mcu:
            return encodeMCU(command: command)
        case .hui:
            return encodeHUI(command: command)
        }
    }

    fileprivate static func releaseBytes(
        command: DAWTransportCommand,
        transportProtocol: DAWTransportProtocol,
        dawType: DAWTransportType
    ) -> [UInt8]? {
        guard shouldSendRelease(for: command, transportProtocol: transportProtocol, dawType: dawType) else {
            return nil
        }

        switch transportProtocol {
        case .mmc:
            return nil
        case .mcu:
            let note = mcuTransportNoteByCommand[command] ?? 0x5D
            return [0x80, note, 0x00]
        case .hui:
            let port = proToolsHUITransportPortByCommand[command] ?? 0x04
            return [0xB0, 0x0F, proToolsHUITransportZone, 0xB0, 0x2F, port]
        }
    }

    private static func shouldSendRelease(
        for command: DAWTransportCommand,
        transportProtocol: DAWTransportProtocol,
        dawType: DAWTransportType
    ) -> Bool {
        switch transportProtocol {
        case .mmc:
            return false
        case .mcu, .hui:
            return true
        }
    }

    fileprivate static func resolvedProtocol(
        configuration: DAWTransportModuleConfiguration,
        isInputConnected: Bool,
        isOutputConnected: Bool
    ) -> DAWTransportProtocol {
        guard isOutputConnected else { return .mmc }

        let commandMode = configuration.commandMode == .automatic
            ? configuration.dawType.preferredCommandMode
            : configuration.commandMode

        switch commandMode {
        case .mmc:
            return .mmc
        case .mcu:
            return configuration.dawType.supportsMCU ? .mcu : .mmc
        case .hui:
            return canUseHUI(configuration: configuration, isInputConnected: isInputConnected) ? .hui : .mmc
        case .automatic:
            return .mmc
        }
    }

    static func shouldReplyToHUIPing(configuration: DAWTransportModuleConfiguration) -> Bool {
        configuration.dawType.supportsHUI
    }

    static func containsHUIPingRequest(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 3 else { return false }
        for index in 0...(bytes.count - 3) {
            if bytes[index] == huiPingRequest[0],
               bytes[index + 1] == huiPingRequest[1],
               bytes[index + 2] == huiPingRequest[2] {
                return true
            }
        }
        return false
    }

    private static func canUseHUI(
        configuration: DAWTransportModuleConfiguration,
        isInputConnected: Bool
    ) -> Bool {
        guard configuration.dawType.supportsHUI else { return false }
        if configuration.dawType.requiresHUIPingReply {
            return isInputConnected
        }
        return true
    }

    private static func encodeMMC(command: DAWTransportCommand) -> [UInt8] {
        let commandByte: UInt8
        switch command {
        case .stop:
            commandByte = 0x01
        case .play:
            commandByte = 0x02
        case .fastForward:
            commandByte = 0x04
        case .rewind:
            commandByte = 0x05
        case .record:
            commandByte = 0x06
        }

        return [0xF0, 0x7F, 0x7F, 0x06, commandByte, 0xF7]
    }

    private static func encodeHUI(command: DAWTransportCommand) -> [UInt8] {
        let port = proToolsHUITransportPortByCommand[command] ?? 0x04
        return [0xB0, 0x0F, proToolsHUITransportZone, 0xB0, 0x2F, 0x40 | port]
    }

    private static func encodeMCU(command: DAWTransportCommand) -> [UInt8] {
        let note = mcuTransportNoteByCommand[command] ?? 0x5D
        return [0x90, note, 0x7F]
    }
}

final class DAWMTCParser {
    private var pieceValues: [Int?] = Array(repeating: nil, count: 8)
    private var seenPieces: Set<Int> = []

    nonisolated deinit {}

    func consume(bytes: [UInt8], receivedAt: Date = Date()) -> DAWMTCUpdate? {
        guard !bytes.isEmpty else { return nil }

        var lastUpdate: DAWMTCUpdate?
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            if status == 0xF1, index + 1 < bytes.count {
                lastUpdate = consumeQuarterFrame(bytes[index + 1], receivedAt: receivedAt) ?? lastUpdate
                index += 2
            } else {
                index += 1
            }
        }

        return lastUpdate
    }

    @discardableResult
    func consumeQuarterFrame(_ dataByte: UInt8, receivedAt: Date = Date()) -> DAWMTCUpdate? {
        let pieceIndex = Int((dataByte & 0x70) >> 4)
        let valueNibble = Int(dataByte & 0x0F)

        guard pieceValues.indices.contains(pieceIndex) else { return nil }
        pieceValues[pieceIndex] = valueNibble
        seenPieces.insert(pieceIndex)

        guard pieceIndex == 7, seenPieces.count == 8 else { return nil }
        guard
            let frameLow = pieceValues[0],
            let frameHigh = pieceValues[1],
            let secondLow = pieceValues[2],
            let secondHigh = pieceValues[3],
            let minuteLow = pieceValues[4],
            let minuteHigh = pieceValues[5],
            let hourLow = pieceValues[6],
            let hourHighAndRate = pieceValues[7]
        else {
            return nil
        }

        let frames = frameLow | ((frameHigh & 0x1) << 4)
        let seconds = secondLow | ((secondHigh & 0x3) << 4)
        let minutes = minuteLow | ((minuteHigh & 0x3) << 4)
        let hours = hourLow | ((hourHighAndRate & 0x1) << 4)
        let rateBits = (hourHighAndRate & 0x6) >> 1

        return DAWMTCUpdate(
            timecode: DAWTimecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames),
            detectedFrameRate: DAWTransportResolvedFrameRate.autoDetected(rateBits: rateBits),
            receivedAt: receivedAt
        )
    }
}

final class DAWHUIDisplayParser {
    private static let sysexHeader: [UInt8] = [0xF0, 0x00, 0x00, 0x66, 0x05, 0x00]
    private static let timeDisplayCommand: UInt8 = 0x11
    private var digits: [UInt8?] = Array(repeating: nil, count: 8)
    private var lastStableText: String?

    nonisolated deinit {}

    func consume(bytes: [UInt8], receivedAt: Date = Date()) -> DAWHUIDisplayUpdate? {
        guard bytes.count >= Self.sysexHeader.count + 3 else { return nil }

        var index = 0
        var lastUpdate: DAWHUIDisplayUpdate?
        while index < bytes.count {
            guard bytes[index] == 0xF0 else {
                index += 1
                continue
            }

            guard
                index + Self.sysexHeader.count < bytes.count,
                Array(bytes[index..<(index + Self.sysexHeader.count)]) == Self.sysexHeader
            else {
                index += 1
                continue
            }

            let command = bytes[index + Self.sysexHeader.count]
            let payloadStart = index + Self.sysexHeader.count + 1
            var payloadEnd = payloadStart
            while payloadEnd < bytes.count, bytes[payloadEnd] != 0xF7 {
                payloadEnd += 1
            }
            guard payloadEnd < bytes.count else { break }

            if command == Self.timeDisplayCommand {
                let payload = Array(bytes[payloadStart..<payloadEnd])
                if let text = decodeDisplayText(payload), !text.isEmpty {
                    lastUpdate = DAWHUIDisplayUpdate(text: text, receivedAt: receivedAt)
                }
            }

            index = payloadEnd + 1
        }

        return lastUpdate
    }

    private func decodeDisplayText(_ payload: [UInt8]) -> String? {
        guard !payload.isEmpty else { return nil }
        for (index, value) in payload.prefix(8).enumerated() {
            digits[index] = value
        }
        return currentStableDisplayText()
    }

    private func currentStableDisplayText() -> String? {
        let rendered = digits.reversed().compactMap { value -> String? in
            guard let value else { return nil }
            return decodeDigit(value)
        }.joined()
        let trailingTrimmed = rendered.trimmingTrailingWhitespaceAndNewlines()
        let displayText = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayText.isEmpty else { return nil }

        if isLikelyLeftTruncatedRefresh(rendered: trailingTrimmed, displayText: displayText) {
            return lastStableText
        }

        lastStableText = displayText
        return displayText
    }

    private func isLikelyLeftTruncatedRefresh(rendered: String, displayText: String) -> Bool {
        guard
            rendered.first == " ",
            let lastStableText,
            lastStableText.count > displayText.count,
            lastStableText.hasSuffix(displayText)
        else {
            return false
        }

        return true
    }

    private func decodeDigit(_ value: UInt8) -> String? {
        if value == 0x20 {
            return " "
        }

        let characterNibble = Int(value & 0x0F)
        let hasDecimalPoint = (value & 0x10) != 0

        let character: String
        switch characterNibble {
        case 0...9:
            character = String(characterNibble)
        case 0x0A:
            character = "A"
        case 0x0B:
            character = "b"
        case 0x0C:
            character = "C"
        case 0x0D:
            character = "-"
        case 0x0E:
            character = "E"
        case 0x0F:
            character = "F"
        default:
            return nil
        }

        return hasDecimalPoint ? "\(character)." : character
    }
}

private extension String {
    func trimmingTrailingWhitespaceAndNewlines() -> String {
        var result = self
        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        return result
    }
}

final class DAWMCUDisplayParser {
    private let digitControllerRange = 0x40...0x49
    private var digits: [Int: String] = [:]
    private var seenControllers = Set<Int>()
    private var hasCompleteSnapshot = false

    func consume(bytes: [UInt8], receivedAt: Date = Date()) -> DAWMCUDisplayUpdate? {
        guard !bytes.isEmpty else { return nil }

        var index = 0
        var lastUpdate: DAWMCUDisplayUpdate?
        while index + 2 < bytes.count {
            let status = bytes[index]
            let controller = Int(bytes[index + 1])
            let value = bytes[index + 2]

            guard status == 0xB0 else {
                index += 1
                continue
            }

            if controller == 0x78 || controller == 0x7B {
                index += 3
                continue
            }

            if digitControllerRange.contains(controller),
               let decodedDigit = decodeDigit(value) {
                digits[controller] = decodedDigit
                seenControllers.insert(controller)
                hasCompleteSnapshot = hasCompleteSnapshot || digitControllerRange.allSatisfy { seenControllers.contains($0) }

                if hasCompleteSnapshot,
                   let text = currentDisplayText() {
                    lastUpdate = DAWMCUDisplayUpdate(text: text, receivedAt: receivedAt)
                }
                index += 3
            } else {
                index += 1
            }
        }

        return lastUpdate
    }

    private func decodeDigit(_ value: UInt8) -> String? {
        if value == 0x00 {
            return " "
        }

        if value >= 0x20 && value <= 0x7E {
            return String(UnicodeScalar(Int(value))!)
        }

        let hasDot = (value & 0x40) != 0
        let digitValue = Int(value & 0x0F)

        let character: String
        switch digitValue {
        case 0...9:
            character = String(digitValue)
        case 0x0A:
            character = "A"
        case 0x0B:
            character = "b"
        case 0x0C:
            character = "C"
        case 0x0D:
            character = "d"
        case 0x0E:
            character = "E"
        case 0x0F:
            character = "F"
        default:
            return nil
        }

        return hasDot ? "\(character)." : character
    }

    private func currentDisplayText() -> String? {
        if let reaperBarsBeats = formattedReaperBarsBeatsDisplay() {
            return reaperBarsBeats
        }

        let orderedControllers = Array(digitControllerRange).sorted()
        let fragments = orderedControllers.compactMap { controller -> String? in
            guard let fragment = digits[controller], fragment != " " else { return nil }
            return fragment
        }
        guard !fragments.isEmpty else { return nil }
        return fragments.joined()
    }

    private func formattedReaperBarsBeatsDisplay() -> String? {
        let barHundreds = value(for: 0x49)
        let barTens = value(for: 0x48)
        let barOnes = value(for: 0x47)
        let beatTens = value(for: 0x46)
        let beatOnes = value(for: 0x45)
        let tickHundreds = value(for: 0x42)
        let tickTens = value(for: 0x41)
        let tickOnes = value(for: 0x40)

        guard [barHundreds, barTens, barOnes, beatTens, beatOnes, tickHundreds, tickTens, tickOnes].contains(where: { $0 != nil }) else {
            return nil
        }

        let barText = [barHundreds, barTens, barOnes].compactMap { $0 }.joined()
        let beatText = [beatTens, beatOnes].compactMap { $0 }.joined()
        let tickText = [tickHundreds, tickTens, tickOnes].compactMap { $0 }.joined()

        var components: [String] = []
        if !barText.isEmpty { components.append(barText) }
        if !beatText.isEmpty { components.append(beatText) }
        if !tickText.isEmpty { components.append(tickText) }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: ".")
    }

    private func value(for controller: Int) -> String? {
        guard let value = digits[controller], value != " " else { return nil }
        return value
    }
}

private final class DAWMCUControlParser {
    private static let transportCommandByNote: [UInt8: DAWTransportCommand] = [
        0x5B: .rewind,
        0x5C: .fastForward,
        0x5D: .stop,
        0x5E: .play,
        0x5F: .record
    ]

    private var transportStates: [DAWTransportCommand: Bool] = [:]

    func consume(bytes: [UInt8], receivedAt: Date = Date()) -> DAWMCUControlUpdate? {
        guard !bytes.isEmpty else { return nil }

        var index = 0
        var changed = false
        while index + 2 < bytes.count {
            let status = bytes[index]
            let note = bytes[index + 1]
            let velocity = bytes[index + 2]

            guard let command = Self.transportCommandByNote[note] else {
                index += 1
                continue
            }

            let statusKind = status & 0xF0
            guard statusKind == 0x90 || statusKind == 0x80 else {
                index += 1
                continue
            }

            let isOn = statusKind == 0x90 && velocity > 0
            let previous = transportStates[command]
            transportStates[command] = isOn
            changed = changed || previous != isOn
            index += 3
        }

        guard changed else { return nil }
        return DAWMCUControlUpdate(transportStates: transportStates, receivedAt: receivedAt)
    }
}

private final class DAWHUIControlParser {
    private static let zoneSelectController: UInt8 = 0x0C
    private static let portValueController: UInt8 = 0x2C
    private static let transportZone: UInt8 = 0x0E
    private static let displayModeZone: UInt8 = 0x16

    private static let transportCommandByPort: [UInt8: DAWTransportCommand] = [
        0x01: .rewind,
        0x02: .fastForward,
        0x03: .stop,
        0x04: .play,
        0x05: .record
    ]

    private static let displayModeByPort: [UInt8: DAWDisplayFeedbackMode] = [
        0x00: .timecode,
        0x01: .feetFrames,
        0x02: .barsBeats
    ]

    private var selectedZone: UInt8?
    private var transportStates: [DAWTransportCommand: Bool] = [:]
    private var activeDisplayFeedbackMode: DAWDisplayFeedbackMode?

    func consume(bytes: [UInt8], receivedAt: Date = Date()) -> DAWHUIControlUpdate? {
        guard !bytes.isEmpty else { return nil }

        var index = 0
        var changed = false
        while index + 2 < bytes.count {
            let status = bytes[index]
            let controller = bytes[index + 1]
            let value = bytes[index + 2]

            guard (status & 0xF0) == 0xB0 else {
                index += 1
                continue
            }

            switch controller {
            case Self.zoneSelectController:
                selectedZone = value
                index += 3

            case Self.portValueController:
                if handlePortValue(value) {
                    changed = true
                }
                index += 3

            default:
                index += 3
            }
        }

        guard changed else { return nil }
        return DAWHUIControlUpdate(
            transportStates: transportStates,
            displayFeedbackMode: activeDisplayFeedbackMode,
            receivedAt: receivedAt
        )
    }

    private func handlePortValue(_ value: UInt8) -> Bool {
        guard let selectedZone else { return false }

        let port = value & 0x07
        let isOn = (value & 0x40) != 0

        if selectedZone == Self.transportZone,
           let command = Self.transportCommandByPort[port] {
            let previous = transportStates[command]
            transportStates[command] = isOn
            return previous != isOn
        }

        if selectedZone == Self.displayModeZone,
           let mode = Self.displayModeByPort[port] {
            let previous = activeDisplayFeedbackMode
            if isOn {
                activeDisplayFeedbackMode = mode
            } else if previous == mode {
                activeDisplayFeedbackMode = nil
            }
            return previous != activeDisplayFeedbackMode
        }

        return false
    }
}

private struct MIDISourceOption: Identifiable, Hashable {
    let id: Int32
    let name: String
}

private enum MIDISourceDiscovery {
    static func currentSources() -> [MIDISourceOption] {
        let count = MIDIGetNumberOfSources()
        var result: [MIDISourceOption] = []
        result.reserveCapacity(Int(count))

        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }

            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

            var nameRef: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameRef)
            let name = (nameRef?.takeRetainedValue() as String?) ?? "MIDI Source \(index)"
            result.append(MIDISourceOption(id: uniqueID, name: name))
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func endpoint(for uniqueID: Int32) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }

            var candidateID: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &candidateID)
            if candidateID == uniqueID {
                return endpoint
            }
        }
        return nil
    }
}

private enum DAWTransportConstants {
    static let mtcStaleAfter: TimeInterval = 1.0
    static let dawDisplayStaleAfter: TimeInterval = 5.0
    static let mcuDisplayStaleAfter: TimeInterval = 15.0
    static let statusTimerInterval: TimeInterval = 0.2
    static let buttonReleaseDelay: TimeInterval = 0.05
    static let receiveDebugLogLimit: Int = 40
}

final class DAWTransportViewModel: ObservableObject {
    @Published private(set) var displayedTimecode: String = DAWTimecode.placeholder
    @Published private(set) var displayPlaceholder: String = DAWTimecode.placeholder
    @Published private(set) var connectionLabel: DAWTransportConnectionLabel = DAWTransportConnectionLabelResolver.resolve(
        configuration: .default()
    )
    @Published private(set) var connectionState: DAWTransportConnectionState = .disconnected
    @Published private(set) var connectionStatusText: String = DAWTransportConnectionState.disconnected.title
    @Published private(set) var inputStatusText: String = "Input: Automatic"
    @Published private(set) var outputStatusText: String = "Output: Automatic"
    @Published private(set) var mtcStatusText: String = "Waiting for MTC"
    @Published private(set) var lastReceivedAgeText: String = "Last: -"
    @Published private(set) var frameRateText: String = "Rate: Auto"
    @Published private(set) var transportProtocolText: String = "Transport: MMC"
    @Published private(set) var warningText: String? = nil
    @Published private(set) var isReceivingMTC: Bool = false
    @Published private(set) var isMTCStale: Bool = false
    @Published private(set) var isInputConnected: Bool = false
    @Published private(set) var isOutputConnected: Bool = false
    @Published private(set) var isRecordEnabled: Bool = false
    @Published private(set) var isRecordFlashVisible: Bool = false
    @Published private(set) var isPlaying: Bool = false

    private var configuration: DAWTransportModuleConfiguration
    private let mtcParser = DAWMTCParser()
    private let huiDisplayParser = DAWHUIDisplayParser()
    private let mcuDisplayParser = DAWMCUDisplayParser()
    private let huiControlParser = DAWHUIControlParser()
    private let mcuControlParser = DAWMCUControlParser()
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    private var statusTimer: Timer?
    private var lastResolvedFrameRate: DAWTransportResolvedFrameRate? = nil
    private var lastReceivedTimecode: DAWTimecode? = nil
    private var lastMTCReceivedAt: Date? = nil
    private var lastDAWCounterDisplay: DAWCounterDisplay? = nil
    private var lastHUIDisplayAt: Date? = nil
    private var transportStates: [DAWTransportCommand: Bool] = [:]
    private var hasKnownTransportPlayState: Bool = false
    private var displayFeedbackMode: DAWDisplayFeedbackMode? = nil
    private var hasLoggedMTCReceivingState: Bool = false
    private var hasLoggedMTCStaleState: Bool = false
    private var hasLoggedHUIReceivingState: Bool = false
    private var hasLoggedHUIStaleState: Bool = false
    private var hasLoggedDisplayRawFallback: Bool = false
    private var receiveDebugLogCount: Int = 0

    init(configuration: DAWTransportModuleConfiguration) {
        self.configuration = {
            var normalizedConfiguration = configuration
            normalizedConfiguration.dawType = configuration.dawType.normalizedForCurrentBuild
            normalizedConfiguration.commandMode = normalizedConfiguration.dawType.preferredCommandMode
            normalizedConfiguration.displayMode = DAWTransportDisplayModeResolver.normalized(
                configuration.displayMode,
                for: normalizedConfiguration.dawType
            )
            if normalizedConfiguration.dawType == .proToolsHUI {
                normalizedConfiguration.appendMTCToDAWDisplay = false
            }
            if !normalizedConfiguration.dawType.supportsDisplayFeedback || normalizedConfiguration.displayMode == .timecode {
                normalizedConfiguration.appendMTCToDAWDisplay = false
            }
            return normalizedConfiguration
        }()
        setupMIDI()
        refreshMIDIPorts()
        startStatusTimer()
        updateStatusSnapshot()
    }

    deinit {
        disconnectSources()
        statusTimer?.invalidate()
    }

    func updateConfiguration(_ configuration: DAWTransportModuleConfiguration) {
        let normalizedConfiguration = normalized(configuration)
        let inputChanged = self.configuration.midiInputSourceID != normalizedConfiguration.midiInputSourceID
        let outputChanged = self.configuration.midiOutputDestinationID != normalizedConfiguration.midiOutputDestinationID
        let frameRateChanged = self.configuration.frameRateSetting != normalizedConfiguration.frameRateSetting
        let modeChanged = self.configuration.commandMode != normalizedConfiguration.commandMode
        let dawChanged = self.configuration.dawType != normalizedConfiguration.dawType

        self.configuration = normalizedConfiguration

        if dawChanged {
            hasKnownTransportPlayState = false
            transportStates = [:]
            lastDAWCounterDisplay = nil
            lastReceivedTimecode = nil
            lastHUIDisplayAt = nil
            lastMTCReceivedAt = nil
        }

        if inputChanged || outputChanged {
            refreshMIDIPorts()
        } else if frameRateChanged || modeChanged || dawChanged {
            updateStatusSnapshot()
        }
    }

    func refreshMIDIPorts() {
        MIDISendManager.shared.refreshDestinations()
        reconnectSelectedSources()
        logSelectedPorts()
        updateStatusSnapshot()
    }

    func send(_ command: DAWTransportCommand, isLiveMode: Bool) {
        let resolvedProtocol = DAWTransportCommandEncoder.resolvedProtocol(
            configuration: configuration,
            isInputConnected: isInputConnected,
            isOutputConnected: isOutputConnected
        )

        guard isLiveMode else {
            RelayDiagnosticsStore.shared.recordError("Blocked DAW transport command outside Live Mode", tag: "DAW Transport")
            print("[DAWTransport] blocked_outside_live_mode daw=\(configuration.dawType.rawValue) command=\(command.rawValue)")
            updateStatusSnapshot()
            return
        }

        guard isOutputConnected else {
            RelayDiagnosticsStore.shared.recordError("DAW Transport send blocked: missing MIDI output", tag: "DAW Transport")
            updateStatusSnapshot()
            return
        }

        let bytes = DAWTransportCommandEncoder.encode(
            command: command,
            configuration: configuration,
            isInputConnected: isInputConnected,
            isOutputConnected: isOutputConnected
        )

        print("[DAWTransport] send daw=\(configuration.dawType.rawValue) protocol=\(resolvedProtocol.rawValue) command=\(command.rawValue)")
        let didSend = MIDISendManager.shared.send(bytes: bytes, to: configuration.midiOutputDestinationID)
        if !didSend {
            RelayDiagnosticsStore.shared.recordError("DAW Transport send failed for \(command.rawValue)", tag: "DAW Transport")
        }
        if didSend,
           let destinationID = configuration.midiOutputDestinationID,
           let releaseBytes = DAWTransportCommandEncoder.releaseBytes(
                command: command,
                transportProtocol: resolvedProtocol,
                dawType: configuration.dawType
           ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + DAWTransportConstants.buttonReleaseDelay) {
                let releaseDidSend = MIDISendManager.shared.send(bytes: releaseBytes, to: destinationID)
                if !releaseDidSend {
                    RelayDiagnosticsStore.shared.recordError("DAW Transport release send failed for \(command.rawValue)", tag: "DAW Transport")
                }
            }
        }
        updateStatusSnapshot()
    }

    fileprivate func handlePacketList(_ pktList: UnsafePointer<MIDIPacketList>, sourceID: Int32?) {
        MIDIPacketListParser.forEachPacket(in: pktList) { packet in
            let bytes = MIDIPacketListParser.extractBytes(packet: packet.pointee)
            logReceivedBytesIfNeeded(bytes, sourceID: sourceID)
            respondToHUIPingIfNeeded(bytes: bytes)
            let receivedAt = Date()
            if let update = mtcParser.consume(bytes: bytes, receivedAt: receivedAt) {
                handle(update: update, sourceID: sourceID)
            }
            if configuration.dawType.supportsHUI,
               let update = huiDisplayParser.consume(bytes: bytes, receivedAt: receivedAt) {
                handle(huiDisplayUpdate: update, sourceID: sourceID)
            }
            if configuration.dawType.supportsMCU,
               let update = mcuDisplayParser.consume(bytes: bytes, receivedAt: receivedAt) {
                handle(mcuDisplayUpdate: update, sourceID: sourceID)
            }
            if configuration.dawType.supportsMCU,
               let update = mcuControlParser.consume(bytes: bytes, receivedAt: receivedAt) {
                handle(mcuControlUpdate: update)
            }
            if configuration.dawType.supportsHUI,
               let update = huiControlParser.consume(bytes: bytes, receivedAt: receivedAt) {
                handle(huiControlUpdate: update)
            }
        }
    }

    private func logReceivedBytesIfNeeded(_ bytes: [UInt8], sourceID: Int32?) {
        guard receiveDebugLogCount < DAWTransportConstants.receiveDebugLogLimit else { return }
        guard configuration.dawType.supportsDisplayFeedback else { return }
        guard bytes.contains(where: { $0 >= 0x80 }) else { return }

        receiveDebugLogCount += 1
        let sourceLabel = sourceID.map(String.init) ?? "automatic"
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[DAWTransport] recv source=\(sourceLabel) bytes=\(hex)")
    }

    private func respondToHUIPingIfNeeded(bytes: [UInt8]) {
        guard DAWTransportCommandEncoder.shouldReplyToHUIPing(configuration: configuration) else { return }
        guard DAWTransportCommandEncoder.containsHUIPingRequest(bytes) else { return }
        guard isOutputConnected else { return }

        let didSend = MIDISendManager.shared.send(
            bytes: DAWTransportCommandEncoder.huiPingReply,
            to: configuration.midiOutputDestinationID
        )
        if didSend {
            print("[DAWTransport] HUI ping reply daw=\(configuration.dawType.rawValue)")
        } else {
            RelayDiagnosticsStore.shared.recordError("DAW Transport failed to send HUI ping reply", tag: "DAW Transport")
        }
    }

    private func handle(update: DAWMTCUpdate, sourceID: Int32?) {
        DispatchQueue.main.async {
            self.lastReceivedTimecode = update.timecode
            self.lastMTCReceivedAt = update.receivedAt
            self.lastResolvedFrameRate = self.configuration.frameRateSetting.resolvedFrameRate(autoDetected: update.detectedFrameRate)

            if !self.hasLoggedMTCReceivingState {
                let sourceLabel = sourceID.map(String.init) ?? "automatic"
                print("[DAWTransport] MTC receiving daw=\(self.configuration.dawType.rawValue) source=\(sourceLabel)")
                self.hasLoggedMTCReceivingState = true
                self.hasLoggedMTCStaleState = false
            }

            self.updateStatusSnapshot()
        }
    }

    private func handle(huiDisplayUpdate: DAWHUIDisplayUpdate, sourceID: Int32?) {
        DispatchQueue.main.async {
            self.lastDAWCounterDisplay = DAWCounterClassifier.classify(
                rawText: huiDisplayUpdate.text,
                explicitFeedbackMode: self.displayFeedbackMode,
                dawType: self.configuration.dawType,
                source: .huiDisplay,
                receivedAt: huiDisplayUpdate.receivedAt
            )
            if self.lastDAWCounterDisplay?.confidence == .rawFallback, !self.hasLoggedDisplayRawFallback {
                print("[DAWTransport] display_raw_fallback daw=\(self.configuration.dawType.rawValue) source=huiDisplay")
                self.hasLoggedDisplayRawFallback = true
            }
            self.lastHUIDisplayAt = huiDisplayUpdate.receivedAt

            if !self.hasLoggedHUIReceivingState {
                let sourceLabel = sourceID.map(String.init) ?? "automatic"
                print("[DAWTransport] HUI display receiving daw=\(self.configuration.dawType.rawValue) source=\(sourceLabel) counter=\(self.lastDAWCounterDisplay?.kind.rawValue ?? "unknown") confidence=\(self.lastDAWCounterDisplay?.confidence.rawValue ?? "unknown")")
                self.hasLoggedHUIReceivingState = true
                self.hasLoggedHUIStaleState = false
            }

            self.updateStatusSnapshot()
        }
    }

    private func handle(mcuDisplayUpdate: DAWMCUDisplayUpdate, sourceID: Int32?) {
        DispatchQueue.main.async {
            self.lastDAWCounterDisplay = DAWCounterClassifier.classify(
                rawText: mcuDisplayUpdate.text,
                explicitFeedbackMode: self.displayFeedbackMode,
                dawType: self.configuration.dawType,
                source: .mcuDisplay,
                receivedAt: mcuDisplayUpdate.receivedAt
            )
            if self.lastDAWCounterDisplay?.confidence == .rawFallback, !self.hasLoggedDisplayRawFallback {
                print("[DAWTransport] display_raw_fallback daw=\(self.configuration.dawType.rawValue) source=mcuDisplay")
                self.hasLoggedDisplayRawFallback = true
            }
            self.lastHUIDisplayAt = mcuDisplayUpdate.receivedAt

            if !self.hasLoggedHUIReceivingState {
                let sourceLabel = sourceID.map(String.init) ?? "automatic"
                print("[DAWTransport] MCU display receiving daw=\(self.configuration.dawType.rawValue) source=\(sourceLabel) counter=\(self.lastDAWCounterDisplay?.kind.rawValue ?? "unknown") confidence=\(self.lastDAWCounterDisplay?.confidence.rawValue ?? "unknown")")
                self.hasLoggedHUIReceivingState = true
                self.hasLoggedHUIStaleState = false
            }

            self.updateStatusSnapshot()
        }
    }

    private func handle(huiControlUpdate: DAWHUIControlUpdate) {
        DispatchQueue.main.async {
            self.transportStates = huiControlUpdate.transportStates
            self.hasKnownTransportPlayState = true
            self.displayFeedbackMode = huiControlUpdate.displayFeedbackMode ?? self.displayFeedbackMode
            self.updateStatusSnapshot()
        }
    }

    private func handle(mcuControlUpdate: DAWMCUControlUpdate) {
        DispatchQueue.main.async {
            self.transportStates = mcuControlUpdate.transportStates
            self.hasKnownTransportPlayState = true
            self.lastHUIDisplayAt = mcuControlUpdate.receivedAt
            self.updateStatusSnapshot()
        }
    }

    /// MIDIClientCreate/MIDIInputPortCreate can block for tens of seconds if a third-party
    /// CoreMIDI driver/agent is misbehaving, so this runs off the main thread to avoid
    /// hanging the UI (this view model is constructed synchronously during thumbnail
    /// rendering immediately after a document opens).
    private func setupMIDI() {
        let refCon = Unmanaged.passUnretained(self).toOpaque()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var newClient = MIDIClientRef()
            var newPort = MIDIPortRef()
            MIDIClientCreate("RelayDAWTransport" as CFString, nil, nil, &newClient)
            MIDIInputPortCreate(
                newClient,
                "RelayDAWTransportIn" as CFString,
                dawTransportReadProc,
                refCon,
                &newPort
            )
            DispatchQueue.main.async {
                guard let self else {
                    MIDIPortDispose(newPort)
                    MIDIClientDispose(newClient)
                    return
                }
                self.client = newClient
                self.inputPort = newPort
                self.refreshMIDIPorts()
            }
        }
    }

    private func reconnectSelectedSources() {
        disconnectSources()
        guard inputPort != 0 else { return }

        if let selectedSourceID = configuration.midiInputSourceID {
            guard let endpoint = MIDISourceDiscovery.endpoint(for: selectedSourceID) else { return }
            let refCon = UnsafeMutableRawPointer(bitPattern: Int(selectedSourceID))
            MIDIPortConnectSource(inputPort, endpoint, refCon)
            connectedSources = [endpoint]
        } else {
            for source in MIDISourceDiscovery.currentSources() {
                guard let endpoint = MIDISourceDiscovery.endpoint(for: source.id) else { continue }
                let refCon = UnsafeMutableRawPointer(bitPattern: Int(source.id))
                MIDIPortConnectSource(inputPort, endpoint, refCon)
                connectedSources.append(endpoint)
            }
        }
    }

    private func disconnectSources() {
        guard inputPort != 0 else { return }
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()
    }

    private func startStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: DAWTransportConstants.statusTimerInterval, repeats: true) { [weak self] _ in
            self?.updateStatusSnapshot()
        }
    }

    private func updateStatusSnapshot() {
        let availableSources = MIDISourceDiscovery.currentSources()
        let availableDestinations = MIDIDestinationDiscovery.currentDestinations()
        let selectedSourceID = configuration.midiInputSourceID
        let selectedDestinationID = configuration.midiOutputDestinationID

        let selectedInputName = selectedSourceID.flatMap { id in
            availableSources.first(where: { $0.id == id })?.name
        }
        let selectedOutputName = selectedDestinationID.flatMap { id in
            availableDestinations.first(where: { $0.id == id })?.name
        }
        let automaticOutputName = selectedDestinationID == nil ? availableDestinations.first?.name : nil
        let inputName = selectedInputName ?? "Automatic"
        let outputName = selectedOutputName ?? "Automatic"

        isInputConnected = selectedSourceID == nil ? !availableSources.isEmpty : availableSources.contains(where: { $0.id == selectedSourceID })
        isOutputConnected = selectedDestinationID == nil ? MIDISendManager.shared.destination(for: nil) != nil : MIDISendManager.shared.destination(for: selectedDestinationID) != nil
        connectionLabel = DAWTransportConnectionLabelResolver.resolve(
            configuration: configuration,
            midiOutputName: selectedOutputName ?? automaticOutputName,
            midiInputName: selectedInputName
        )

        inputStatusText = "Input: \(inputName) \(isInputConnected ? "connected" : "missing")"
        outputStatusText = "Output: \(outputName) \(isOutputConnected ? "connected" : "missing")"

        let resolvedProtocol = DAWTransportCommandEncoder.resolvedProtocol(
            configuration: configuration,
            isInputConnected: isInputConnected,
            isOutputConnected: isOutputConnected
        )
        transportProtocolText = "Transport: \(resolvedProtocol.rawValue)"

        let now = Date()
        let mtcAge = lastMTCReceivedAt.map { now.timeIntervalSince($0) }
        let huiAge = lastHUIDisplayAt.map { now.timeIntervalSince($0) }
        let displayStaleAfter = configuration.dawType.supportsMCU
            ? DAWTransportConstants.mcuDisplayStaleAfter
            : DAWTransportConstants.dawDisplayStaleAfter
        let isHUIFresh = huiAge.map { $0 <= displayStaleAfter } ?? false
        let isMTCFresh = mtcAge.map { $0 <= DAWTransportConstants.mtcStaleAfter } ?? false
        let frameRate = configuration.frameRateSetting.resolvedFrameRate(autoDetected: lastResolvedFrameRate)

        isRecordEnabled = transportStates[.record] == true
        isRecordFlashVisible = isRecordEnabled && Int(now.timeIntervalSinceReferenceDate / 0.35).isMultiple(of: 2)
        isPlaying = transportStates[.play] == true
        displayPlaceholder = currentDisplayPlaceholder()

        let dawCounterDisplay = lastDAWCounterDisplay

        let mtcDisplayText: String? = {
            guard let lastReceivedTimecode else { return nil }
            if let mtcAge, let frameRate, isMTCFresh {
                return lastReceivedTimecode.advanced(by: mtcAge, frameRate: frameRate).formatted
            }
            return lastReceivedTimecode.formatted
        }()
        let prefersMTCDisplay = configuration.displayMode == .timecode
        let appendedDisplayText: String? = {
            guard
                configuration.appendMTCToDAWDisplay,
                configuration.displayMode != .timecode,
                let dawCounterDisplay,
                let mtcDisplayText,
                isMTCFresh
            else {
                return nil
            }
            return "\(dawCounterDisplay.displayText)\n\(mtcDisplayText)"
        }()

        let hasAnySignalHistory = lastDAWCounterDisplay != nil || lastReceivedTimecode != nil
        let hasFreshSignal = (!prefersMTCDisplay && (isHUIFresh || isMTCFresh)) || (prefersMTCDisplay && isMTCFresh)
        let hasStaleSignal = hasAnySignalHistory && !hasFreshSignal

        connectionState = DAWTransportConnectionState.resolved(
            hasFreshSignal: hasFreshSignal,
            hasStaleSignal: hasStaleSignal,
            hasKnownTransportPlayState: hasKnownTransportPlayState,
            isPlaying: isPlaying
        )

        if prefersMTCDisplay, isMTCFresh, let mtcDisplayText, let mtcAge {
            isReceivingMTC = true
            isMTCStale = false
            displayedTimecode = mtcDisplayText
            mtcStatusText = "Receiving MTC"
            lastReceivedAgeText = "Last: \(formattedAge(mtcAge))"
            frameRateText = "Rate: \((frameRate ?? lastResolvedFrameRate)?.label ?? "Auto")"
            hasLoggedMTCStaleState = false
        } else if !prefersMTCDisplay, let appendedDisplayText, isHUIFresh, let dawCounterDisplay, let huiAge {
            isReceivingMTC = true
            isMTCStale = false
            displayedTimecode = appendedDisplayText
            mtcStatusText = "\(receivingStatusText(for: dawCounterDisplay)) + MTC"
            lastReceivedAgeText = "Last: \(formattedAge(huiAge))"
            frameRateText = "Rate: DAW display + \((frameRate ?? lastResolvedFrameRate)?.label ?? "MTC")"
            hasLoggedHUIStaleState = false
            hasLoggedMTCStaleState = false
        } else if !prefersMTCDisplay, isHUIFresh, let dawCounterDisplay, let huiAge {
            isReceivingMTC = true
            isMTCStale = false
            displayedTimecode = dawCounterDisplay.displayText
            mtcStatusText = receivingStatusText(for: dawCounterDisplay)
            lastReceivedAgeText = "Last: \(formattedAge(huiAge))"
            frameRateText = "Rate: DAW display"
            hasLoggedHUIStaleState = false

            if hasLoggedMTCReceivingState, !isMTCFresh {
                hasLoggedMTCReceivingState = false
            }
        } else if !prefersMTCDisplay, isMTCFresh, let mtcDisplayText, let mtcAge {
            isReceivingMTC = true
            isMTCStale = false
            displayedTimecode = mtcDisplayText
            mtcStatusText = configuration.displayMode == .clock ? "Receiving MTC fallback" : "Receiving MTC"
            lastReceivedAgeText = "Last: \(formattedAge(mtcAge))"
            frameRateText = "Rate: \((frameRate ?? lastResolvedFrameRate)?.label ?? "Auto")"
            hasLoggedMTCStaleState = false
        } else if !prefersMTCDisplay, let dawCounterDisplay, let huiAge {
            isReceivingMTC = false
            isMTCStale = true
            displayedTimecode = dawCounterDisplay.displayText
            mtcStatusText = connectionState == .paused
                ? "Paused"
                : "\(receivingStatusText(for: dawCounterDisplay).replacingOccurrences(of: "Receiving ", with: "")) stale"
            lastReceivedAgeText = "Last: \(formattedAge(huiAge))"
            frameRateText = "Rate: DAW display"

            if !hasLoggedHUIStaleState {
                print("[DAWTransport] HUI display stale daw=\(configuration.dawType.rawValue) after \(String(format: "%.2f", huiAge))s")
                hasLoggedHUIStaleState = true
                hasLoggedHUIReceivingState = false
            }
        } else if let mtcDisplayText, let mtcAge {
            isReceivingMTC = false
            isMTCStale = true
            displayedTimecode = mtcDisplayText
            mtcStatusText = connectionState == .paused
                ? "Paused"
                : (configuration.displayMode == .clock ? "MTC fallback stale" : "MTC stale")
            lastReceivedAgeText = "Last: \(formattedAge(mtcAge))"
            frameRateText = "Rate: \((frameRate ?? lastResolvedFrameRate)?.label ?? "Auto")"

            if !hasLoggedMTCStaleState {
                print("[DAWTransport] MTC stale daw=\(configuration.dawType.rawValue) after \(String(format: "%.2f", mtcAge))s")
                hasLoggedMTCStaleState = true
                hasLoggedMTCReceivingState = false
            }
        } else {
            isReceivingMTC = false
            isMTCStale = false
            displayedTimecode = displayPlaceholder
            mtcStatusText = waitingStatusText()
            lastReceivedAgeText = "Last: -"
            frameRateText = "Rate: \((configuration.frameRateSetting.resolvedFrameRate(autoDetected: lastResolvedFrameRate) ?? lastResolvedFrameRate)?.label ?? "Auto")"
        }

        connectionStatusText = connectionState.title

        warningText = warningSummary(
            inputConnected: isInputConnected,
            outputConnected: isOutputConnected,
            resolvedProtocol: resolvedProtocol,
            isMTCStale: isMTCStale && connectionState != .paused
        )
    }

    private func warningSummary(
        inputConnected: Bool,
        outputConnected: Bool,
        resolvedProtocol: DAWTransportProtocol,
        isMTCStale: Bool
    ) -> String? {
        if !outputConnected {
            return "Select a MIDI output port to enable DAW transport commands."
        }
        if !inputConnected {
            if resolvedProtocol == .hui && configuration.dawType.requiresHUIPingReply {
                return "Pro Tools HUI needs the MIDI input online so Relay can answer HUI ping messages."
            }
            if configuration.dawType.supportsDisplayFeedback {
                return "Select a valid MIDI input port to receive MTC or MCU/HUI display data."
            }
            return "Select a valid MIDI input port to receive MIDI Timecode."
        }
        if isMTCStale {
            if configuration.dawType.supportsDisplayFeedback {
                return "DAW timing display is stale. Check that \(configuration.dawType.title) is still transmitting MTC or MCU/HUI display data."
            }
            return "MIDI Timecode is stale. Check that \(configuration.dawType.title) is still transmitting MTC."
        }
        return nil
    }

    private func formattedAge(_ age: TimeInterval) -> String {
        if age < 1 {
            return "<1s ago"
        }
        return String(format: "%.1fs ago", age)
    }

    private func logSelectedPorts() {
        let availableSources = MIDISourceDiscovery.currentSources()
        let availableDestinations = MIDIDestinationDiscovery.currentDestinations()
        let inputLabel = configuration.midiInputSourceID.flatMap { selectedID in
            availableSources.first(where: { $0.id == selectedID })?.name
        } ?? "Automatic"
        let outputLabel = configuration.midiOutputDestinationID.flatMap { selectedID in
            availableDestinations.first(where: { $0.id == selectedID })?.name
        } ?? "Automatic"
        print("[DAWTransport] daw=\(configuration.dawType.rawValue) protocol=\(configuration.dawType.profileInfo.protocolLabel) input=\"\(inputLabel)\" output=\"\(outputLabel)\" counterSource=\(configuration.displayMode.rawValue) appendMTC=\(configuration.appendMTCToDAWDisplay)")
    }

    private func normalized(_ configuration: DAWTransportModuleConfiguration) -> DAWTransportModuleConfiguration {
        var normalizedConfiguration = configuration
        normalizedConfiguration.dawType = configuration.dawType.normalizedForCurrentBuild
        normalizedConfiguration.commandMode = normalizedConfiguration.dawType.preferredCommandMode
        normalizedConfiguration.displayMode = DAWTransportDisplayModeResolver.normalized(
            configuration.displayMode,
            for: normalizedConfiguration.dawType
        )
        if normalizedConfiguration.dawType == .proToolsHUI {
            normalizedConfiguration.appendMTCToDAWDisplay = false
        }
        if !normalizedConfiguration.dawType.supportsDisplayFeedback || normalizedConfiguration.displayMode == .timecode {
            normalizedConfiguration.appendMTCToDAWDisplay = false
        }
        return normalizedConfiguration
    }

    private func waitingStatusText() -> String {
        switch configuration.displayMode {
        case .automatic:
            return configuration.dawType.supportsDisplayFeedback ? "Waiting for MTC or MCU/HUI display" : "Waiting for MTC"
        case .clock:
            return configuration.dawType.supportsDisplayFeedback ? "Waiting for DAW clock or MTC fallback" : "Waiting for MTC"
        case .timecode:
            return "Waiting for MTC"
        }
    }

    private func currentDisplayPlaceholder() -> String {
        let sourcePlaceholder: String
        switch configuration.displayMode {
        case .automatic:
            sourcePlaceholder = "--------"
        case .clock:
            sourcePlaceholder = "88:88:88"
        case .timecode:
            sourcePlaceholder = "88:88:88:88"
        }

        guard configuration.appendMTCToDAWDisplay, configuration.displayMode != .timecode else {
            return sourcePlaceholder
        }
        return "\(sourcePlaceholder)\n88:88:88:88"
    }

    private func receivingStatusText(for counterDisplay: DAWCounterDisplay) -> String {
        switch counterDisplay.source {
        case .mtc:
            return "Receiving MTC"
        case .huiDisplay, .mcuDisplay:
            switch counterDisplay.kind {
            case .timecode, .clock:
                return "Receiving Timecode"
            case .barsBeats:
                return "Receiving Bars/Beats"
            case .feetFrames:
                return "Receiving Feet+Frames"
            case .samples:
                return "Receiving Samples"
            case .unknown:
                return "Receiving DAW Main Counter"
            }
        }
    }

}

private let dawTransportReadProc: MIDIReadProc = { pktList, readProcRefCon, srcConnRefCon in
    guard let readProcRefCon else { return }
    let viewModel = Unmanaged<DAWTransportViewModel>.fromOpaque(readProcRefCon).takeUnretainedValue()
    let sourceID: Int32? = {
        guard let srcConnRefCon else { return nil }
        return Int32(Int(bitPattern: srcConnRefCon))
    }()
    viewModel.handlePacketList(pktList, sourceID: sourceID)
}

struct DAWTransportTileView: View {
    @Binding var config: DAWTransportModuleConfiguration
    let isLiveMode: Bool

    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.tileCornerRadius) private var tileCornerRadius

    @StateObject private var viewModel: DAWTransportViewModel

    init(moduleId: UUID, config: Binding<DAWTransportModuleConfiguration>, isLiveMode: Bool) {
        self._config = config
        self.isLiveMode = isLiveMode
        self._viewModel = StateObject(wrappedValue: DAWTransportViewModelStore.shared.model(
            for: moduleId,
            configuration: config.wrappedValue
        ))
    }

    private var primaryColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? .white
    }

    private var secondaryColor: Color {
        primaryColor.opacity(0.72)
    }

    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    private var buttonIconSize: CGFloat {
        min(max(baseFontSize * 0.7, 14), 18)
    }

    private var buttonLabelSize: CGFloat {
        min(max(baseFontSize * 0.45, 9), 11)
    }

    private var buttonMinHeight: CGFloat {
        42
    }

    private var titleWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    private var alignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var textAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if config.showHeader {
                Text("DAW Transport")
                    .font(.system(size: baseFontSize * 0.82, weight: titleWeight))
                    .foregroundStyle(secondaryColor)
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.connectionLabel.title)
                        .font(.system(size: baseFontSize * 0.58, weight: .medium))
                        .foregroundStyle(secondaryColor)

                    if let subtitle = viewModel.connectionLabel.subtitle {
                        Text(subtitle)
                            .font(.system(size: baseFontSize * 0.42, weight: .regular))
                            .foregroundStyle(secondaryColor.opacity(0.82))
                    }
                }
                Spacer()
                statusIndicator
            }

            if config.showTimer {
                ZStack(alignment: alignment) {
                    Text(viewModel.displayPlaceholder)
                        .font(.system(size: baseFontSize * 1.35, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(textAlignment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .opacity(0)
                    Text(viewModel.displayedTimecode)
                        .font(.system(size: baseFontSize * 1.35, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(textAlignment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(
                            viewModel.isRecordEnabled
                            ? Color.red
                            : (viewModel.isMTCStale && viewModel.connectionState != .paused ? Color.orange : primaryColor)
                        )
                }
            }

            if config.showTransportButtons {
                HStack(spacing: 8) {
                    ForEach(DAWTransportCommand.allCases) { command in
                        Button {
                            viewModel.send(command, isLiveMode: isLiveMode)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: command.systemImage)
                                    .font(.system(size: buttonIconSize, weight: .semibold))
                                Text(command.title)
                                    .font(.system(size: buttonLabelSize, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: buttonMinHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        buttonBackgroundColor(for: command)
                                    )
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isLiveMode || !viewModel.isOutputConnected)
                        .tint(buttonTintColor(for: command))
                        .help(isLiveMode ? command.title : "Switch to Live Mode to control transport.")
                    }
                }
            }

            if config.showTransportButtons && !isLiveMode {
                Text("Transport control is available in Live Mode.")
                    .font(.system(size: baseFontSize * 0.48, weight: .medium))
                    .foregroundStyle(secondaryColor)
            }

            if config.showDebugUI {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.transportProtocolText)
                    Text(viewModel.frameRateText)
                    Text(viewModel.lastReceivedAgeText)
                    Text(viewModel.inputStatusText)
                    Text(viewModel.outputStatusText)
                }
                .font(.system(size: baseFontSize * 0.5, weight: .regular))
                .foregroundStyle(secondaryColor)
            }

            if let warningText = viewModel.warningText {
                Text(warningText)
                    .font(.system(size: baseFontSize * 0.48, weight: .medium))
                    .foregroundStyle(viewModel.isOutputConnected && viewModel.isInputConnected ? Color.orange : Color.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius))
        .onAppear {
            viewModel.updateConfiguration(config)
        }
        .onChange(of: config) { _, newValue in
            viewModel.updateConfiguration(newValue)
        }
    }

    private func buttonTintColor(for command: DAWTransportCommand) -> Color? {
        switch command {
        case .play:
            return viewModel.isPlaying ? .green : nil
        case .record:
            return viewModel.isRecordEnabled ? .red : nil
        case .rewind, .stop, .fastForward:
            return nil
        }
    }

    private func buttonBackgroundColor(for command: DAWTransportCommand) -> Color {
        switch command {
        case .play:
            return viewModel.isPlaying ? Color.green.opacity(0.20) : .clear
        case .record:
            guard viewModel.isRecordEnabled else { return .clear }
            return viewModel.isRecordFlashVisible ? Color.red.opacity(0.28) : Color.red.opacity(0.12)
        case .rewind, .stop, .fastForward:
            return .clear
        }
    }

    private var statusIndicator: some View {
        Image(systemName: viewModel.connectionState.systemImage)
            .font(.system(size: baseFontSize * 0.52, weight: .semibold))
            .foregroundStyle(viewModel.connectionState.tint)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(viewModel.connectionState.tint.opacity(0.14))
            )
            .help(viewModel.connectionStatusText)
    }
}

struct DAWTransportModuleSettingsHost: View {
    @Binding var config: DAWTransportModuleConfiguration
    let onPersist: () -> Void

    @State private var sources: [MIDISourceOption] = MIDISourceDiscovery.currentSources()
    @State private var destinations: [MIDIDestinationOption] = MIDIDestinationDiscovery.currentDestinations()

    private var selectedInputMissing: Bool {
        guard let selected = config.midiInputSourceID else { return false }
        return !sources.contains(where: { $0.id == selected })
    }

    private var selectedOutputMissing: Bool {
        guard let selected = config.midiOutputDestinationID else { return false }
        return !destinations.contains(where: { $0.id == selected })
    }

    private var selectableDisplayModes: [DAWTransportDisplayMode] {
        DAWTransportDisplayModeResolver.selectableModes(for: config.dawType)
    }

    private var effectiveDisplayMode: DAWTransportDisplayMode {
        DAWTransportDisplayModeResolver.normalized(config.displayMode, for: config.dawType)
    }

    private enum CounterSourceSelection: String, CaseIterable, Identifiable {
        case dawMain
        case mtc
        case dawMainPlusMTC

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dawMain:
                return "DAW Main Counter"
            case .mtc:
                return "MIDI Timecode"
            case .dawMainPlusMTC:
                return "DAW Main Counter + MTC"
            }
        }
    }

    private var selectableCounterSources: [CounterSourceSelection] {
        if config.dawType == .proToolsHUI {
            return [.dawMain, .mtc]
        }
        if config.dawType.supportsDisplayFeedback {
            return [.dawMain, .mtc, .dawMainPlusMTC]
        }
        return [.mtc]
    }

    private var counterSourceSelection: CounterSourceSelection {
        if effectiveDisplayMode == .timecode {
            return .mtc
        }
        return config.appendMTCToDAWDisplay ? .dawMainPlusMTC : .dawMain
    }

    private var isMTCActive: Bool {
        counterSourceSelection != .dawMain
    }

    private var huiNoteText: String? {
        if config.dawType.supportsMCU {
            return "MCU transport sends Mackie Control Universal note messages and listens for the DAW main counter on the selected MIDI input."
        }
        guard config.dawType.supportsHUI else { return nil }
        if config.dawType.requiresHUIPingReply {
            return "Pro Tools HUI requires Relay to answer the incoming HUI ping on the selected MIDI input. HUI exposes the DAW main counter only, not the Pro Tools sub counter."
        }
        return "HUI transport sends note-on/note-off button messages on MIDI channel 1 using the selected output port. Incoming HUI display updates expose the DAW main counter only."
    }

    private var displayHelpText: String {
        switch counterSourceSelection {
        case .dawMain:
            return "Shows whatever the DAW main counter is sending over HUI or MCU, including bars|beats or time."
        case .mtc:
            return "Shows MIDI Timecode from the selected MIDI input instead of the DAW HUI/MCU counter."
        case .dawMainPlusMTC:
            return "Shows the DAW main counter and adds separate MIDI Timecode underneath when MTC is available."
        }
    }

    private func applyCounterSourceSelection(_ selection: CounterSourceSelection) {
        switch selection {
        case .dawMain:
            config.displayMode = .automatic
            config.appendMTCToDAWDisplay = false
        case .mtc:
            config.displayMode = .timecode
            config.appendMTCToDAWDisplay = false
        case .dawMainPlusMTC:
            config.displayMode = .automatic
            config.appendMTCToDAWDisplay = true
        }
        onPersist()
    }

    func normalizeDisplaySettingsIfNeeded() {
        // Normalize saved display options against the saved protocol, never a runtime fallback.
        let normalizedDAWType = config.dawType
        let normalizedDisplayMode = DAWTransportDisplayModeResolver.normalized(config.displayMode, for: normalizedDAWType)
        var changed = false

        if config.displayMode != normalizedDisplayMode {
            config.displayMode = normalizedDisplayMode
            changed = true
        }

        if config.dawType == .proToolsHUI && config.appendMTCToDAWDisplay {
            config.appendMTCToDAWDisplay = false
            changed = true
        }

        if (!config.dawType.supportsDisplayFeedback || normalizedDisplayMode == .timecode) && config.appendMTCToDAWDisplay {
            config.appendMTCToDAWDisplay = false
            changed = true
        }

        if changed {
            onPersist()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show header", isOn: Binding(
                get: { config.showHeader },
                set: { newValue in
                    config.showHeader = newValue
                    onPersist()
                }
            ))

            Toggle("Show Counter", isOn: Binding(
                get: { config.showTimer },
                set: { newValue in
                    config.showTimer = newValue
                    onPersist()
                }
            ))

            Toggle("Show transport buttons", isOn: Binding(
                get: { config.showTransportButtons },
                set: { newValue in
                    config.showTransportButtons = newValue
                    onPersist()
                }
            ))

            Picker("DAW", selection: Binding(
                get: { config.dawType },
                set: { newValue in
                    config.dawType = newValue
                    config.commandMode = newValue.preferredCommandMode
                    config.displayMode = newValue.defaultDisplayMode
                    if !newValue.supportsDisplayFeedback {
                        config.appendMTCToDAWDisplay = false
                    }
                    onPersist()
                }
            )) {
                ForEach(DAWTransportType.selectableCases) { dawType in
                    Text(dawType.title).tag(dawType)
                }
            }

            TextField("Connection name (optional)", text: Binding(
                get: { config.connectionName },
                set: { newValue in
                    config.connectionName = newValue
                    onPersist()
                }
            ))

            profileInfoCard

            Picker("MIDI input", selection: Binding(
                get: { config.midiInputSourceID },
                set: { newValue in
                    config.midiInputSourceID = newValue
                    onPersist()
                }
            )) {
                Text("Automatic").tag(Int32?.none)
                ForEach(sources) { source in
                    Text(source.name).tag(Int32?.some(source.id))
                }
            }

            Picker("MIDI output", selection: Binding(
                get: { config.midiOutputDestinationID },
                set: { newValue in
                    config.midiOutputDestinationID = newValue
                    onPersist()
                }
            )) {
                Text("Automatic").tag(Int32?.none)
                ForEach(destinations) { destination in
                    Text(destination.name).tag(Int32?.some(destination.id))
                }
            }

            Picker("Counter Source", selection: Binding(
                get: { counterSourceSelection },
                set: { newValue in
                    applyCounterSourceSelection(newValue)
                }
            )) {
                ForEach(selectableCounterSources) { source in
                    Text(source.title).tag(source)
                }
            }
            Text(displayHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isMTCActive {
                Picker("Frame rate", selection: Binding(
                    get: { config.frameRateSetting },
                    set: { newValue in
                        config.frameRateSetting = newValue
                        onPersist()
                    }
                )) {
                    ForEach(DAWTransportFrameRateSetting.allCases) { setting in
                        Text(setting.title).tag(setting)
                    }
                }
            }

            HStack {
                Text("Protocol")
                Spacer()
                Text(config.dawType.profileInfo.protocolLabel)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Advanced") {
                Toggle("Show debug UI", isOn: Binding(
                    get: { config.showDebugUI },
                    set: { newValue in
                        config.showDebugUI = newValue
                        onPersist()
                    }
                ))
            }

            Button("Refresh MIDI devices") {
                sources = MIDISourceDiscovery.currentSources()
                destinations = MIDIDestinationDiscovery.currentDestinations()
            }
            .dashboardLinkButtonStyle()

            if selectedInputMissing {
                Text("The selected MIDI input port is not currently available.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if selectedOutputMissing {
                Text("The selected MIDI output port is not currently available.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(config.dawType.setupHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let huiNoteText {
                Text(huiNoteText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 6)
        .onAppear {
            normalizeDisplaySettingsIfNeeded()
        }
        .onChange(of: config.dawType) { _, _ in
            normalizeDisplaySettingsIfNeeded()
        }
    }

    private var profileInfoCard: some View {
        let info = config.dawType.profileInfo
        return VStack(alignment: .leading, spacing: 4) {
            Text("Protocol: \(info.protocolLabel)")
            Text("Counter: \(info.expectedCounterSource)")
            Text("Expected: \(info.supportedCounterFormats)")
            Text(info.troubleshootingNotes)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

enum DAWTransportModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .dawTransport }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        _ = tab
        _ = tile

        let configBinding = Binding<DAWTransportModuleConfiguration>(
            get: { module.wrappedValue.dawTransportConfig ?? DAWTransportModuleConfiguration.default() },
            set: { newValue in
                var updated = module.wrappedValue
                updated.dawTransportConfig = newValue
                module.wrappedValue = updated
            }
        )

        return AnyView(DAWTransportTileView(
            moduleId: module.wrappedValue.id,
            config: configBinding,
            isLiveMode: isLiveMode
        ))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        _ = showsHeader
        return AnyView(
            DAWTransportModuleSettingsHost(
                config: .constant(DAWTransportModuleConfiguration.default()),
                onPersist: onPersist
            )
        )
    }
}
