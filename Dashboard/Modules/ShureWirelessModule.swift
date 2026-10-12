// MARK: - Shure Module Config

/// Per-module configuration for the Shure Wireless module.
/// Stored on `DashboardModuleModel` as `shureConfig`.
struct ShureModuleConfig: Codable, Equatable {
    var selectedChannel: ExternalDevicesStore.ShureSelectedChannel?
    var showDeviceName: Bool
    var showChannelName: Bool
    var showIPPort: Bool
    var showFrequency: Bool
    var showBattery: Bool
    var showRFStrength: Bool
    var showAudioMeter: Bool = true
    var demoEnabled: Bool = false
    var demoIsIem: Bool = false
    var demoMicName: String = "Pastor Mic"
    var demoDeviceName: String = "Demo Rack"
    var demoBatteryPercent: Int = 82
    var demoFrequencyMHz: Double = 552.125

    init(
        selectedChannel: ExternalDevicesStore.ShureSelectedChannel? = nil,
        showDeviceName: Bool = true,
        showChannelName: Bool = true,
        showIPPort: Bool = false,
        showFrequency: Bool = true,
        showBattery: Bool = true,
        showRFStrength: Bool = true,
        showAudioMeter: Bool = true,
        demoEnabled: Bool = false,
        demoIsIem: Bool = false,
        demoMicName: String = "Pastor Mic",
        demoDeviceName: String = "Demo Rack",
        demoBatteryPercent: Int = 82,
        demoFrequencyMHz: Double = 552.125
    ) {
        self.selectedChannel = selectedChannel
        self.showDeviceName = showDeviceName
        self.showChannelName = showChannelName
        self.showIPPort = showIPPort
        self.showFrequency = showFrequency
        self.showBattery = showBattery
        self.showRFStrength = showRFStrength
        self.showAudioMeter = showAudioMeter
        self.demoEnabled = demoEnabled
        self.demoIsIem = demoIsIem
        self.demoMicName = demoMicName
        self.demoDeviceName = demoDeviceName
        self.demoBatteryPercent = demoBatteryPercent
        self.demoFrequencyMHz = demoFrequencyMHz
    }

    static func `default`() -> ShureModuleConfig {
        ShureModuleConfig(
            selectedChannel: nil,
            showDeviceName: true,
            showChannelName: true,
            showIPPort: false,
            showFrequency: true,
            showBattery: true,
            showRFStrength: true,
            showAudioMeter: true,
            demoEnabled: false,
            demoIsIem: false,
            demoMicName: "Pastor Mic",
            demoDeviceName: "Demo Rack",
            demoBatteryPercent: 82,
            demoFrequencyMHz: 552.125
        )
    }

    private enum CodingKeys: String, CodingKey {
        case selectedChannel
        case showDeviceName
        case showChannelName
        case showIPPort
        case showFrequency
        case showBattery
        case showRFStrength
        case showAudioMeter
        case demoEnabled
        case demoIsIem
        case demoMicName
        case demoDeviceName
        case demoBatteryPercent
        case demoFrequencyMHz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedChannel = try container.decodeIfPresent(ExternalDevicesStore.ShureSelectedChannel.self, forKey: .selectedChannel)
        showDeviceName = try container.decodeIfPresent(Bool.self, forKey: .showDeviceName) ?? true
        showChannelName = try container.decodeIfPresent(Bool.self, forKey: .showChannelName) ?? true
        showIPPort = try container.decodeIfPresent(Bool.self, forKey: .showIPPort) ?? false
        showFrequency = try container.decodeIfPresent(Bool.self, forKey: .showFrequency) ?? true
        showBattery = try container.decodeIfPresent(Bool.self, forKey: .showBattery) ?? true
        showRFStrength = try container.decodeIfPresent(Bool.self, forKey: .showRFStrength) ?? true
        showAudioMeter = try container.decodeIfPresent(Bool.self, forKey: .showAudioMeter) ?? true

        demoEnabled = try container.decodeIfPresent(Bool.self, forKey: .demoEnabled) ?? false
        demoIsIem = try container.decodeIfPresent(Bool.self, forKey: .demoIsIem) ?? false
        demoMicName = try container.decodeIfPresent(String.self, forKey: .demoMicName) ?? "Pastor Mic"
        demoDeviceName = try container.decodeIfPresent(String.self, forKey: .demoDeviceName) ?? "Demo Rack"
        demoBatteryPercent = try container.decodeIfPresent(Int.self, forKey: .demoBatteryPercent) ?? 82
        demoFrequencyMHz = try container.decodeIfPresent(Double.self, forKey: .demoFrequencyMHz) ?? 552.125
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedChannel, forKey: .selectedChannel)
        try container.encode(showDeviceName, forKey: .showDeviceName)
        try container.encode(showChannelName, forKey: .showChannelName)
        try container.encode(showIPPort, forKey: .showIPPort)
        try container.encode(showFrequency, forKey: .showFrequency)
        try container.encode(showBattery, forKey: .showBattery)
        try container.encode(showRFStrength, forKey: .showRFStrength)
        try container.encode(showAudioMeter, forKey: .showAudioMeter)
        try container.encode(demoEnabled, forKey: .demoEnabled)
        try container.encode(demoIsIem, forKey: .demoIsIem)
        try container.encode(demoMicName, forKey: .demoMicName)
        try container.encode(demoDeviceName, forKey: .demoDeviceName)
        try container.encode(demoBatteryPercent, forKey: .demoBatteryPercent)
        try container.encode(demoFrequencyMHz, forKey: .demoFrequencyMHz)
    }
}
//
//  ShureModuleState.swift
//  Relay
//
//  Created by David Bullard on 11/19/25.
//

//
//  ShureWirelessModule.swift
//  Relay
//
//  Created by David Bullard on 11/19/25.
//

import SwiftUI
import Network
import Combine
import Foundation
import CryptoKit

private actor ShureResumeGate<T> {
    private var didResume = false
    private var continuation: CheckedContinuation<T, Never>?
    private var pendingValue: T?

    func store(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
        if let pendingValue {
            self.pendingValue = nil
            resume(with: pendingValue)
        }
    }

    func resume(with value: T) {
        guard !didResume else { return }
        if let continuation {
            didResume = true
            self.continuation = nil
            continuation.resume(returning: value)
        } else {
            pendingValue = value
        }
    }
}

// MARK: - Shure Receiver State

/// Legacy state container – no longer used directly, but kept for
/// compatibility in case other files reference the type.
struct ShureModuleState {
    var device: ExternalDeviceConfig?
    var isConnected: Bool = false
    var lastError: String? = nil
    var lastHeardAt: Date? = nil
    var recentReports: [String] = []
    /// Channel names reported by the current device, keyed by channel index.
    var channelNames: [Int: String] = [:]
    /// Last known tuned frequency per channel, already formatted for display.
    var channelFrequencies: [Int: String] = [:]
    /// RF TX level reported by the current device, keyed by channel index.
    var rfTxLevels: [Int: Int] = [:]
    /// For PSM devices (e.g. P10T), last reported audio input levels for L/R per channel.
    var psmAudioLevels: [Int: (left: Double, right: Double)] = [:]
    /// Last parsed human-readable battery label per channel (e.g. "85%", "1:20", "45m").
    var channelBatteryLabels: [Int: String] = [:]
    /// Last known battery percentage per channel (0–100) when available.
    var channelBatteryPercentages: [Int: Int] = [:]
    /// Last parsed RF strength as a 0–5 bar count per channel.
    var channelRFBarCounts: [Int: Int] = [:]
}

/// Represents a specific RF channel on a specific Shure device.
struct ShureChannelDescriptor: Identifiable, Equatable, Hashable {
    let deviceID: UUID
    let deviceName: String
    let channelIndex: Int

    /// Stable identity so Picker selection and diffing work reliably.
    var id: String {
        "\(deviceID.uuidString)-\(channelIndex)"
    }

    var displayName: String {
        "\(deviceName) – CH \(channelIndex)"
    }

    static func == (lhs: ShureChannelDescriptor, rhs: ShureChannelDescriptor) -> Bool {
        lhs.deviceID == rhs.deviceID && lhs.channelIndex == rhs.channelIndex
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(deviceID)
        hasher.combine(channelIndex)
    }
}

private struct ShureIncomingFrame: Sendable {
    let rawLine: String
    let parts: [Substring]
    let verbUpper: String

    nonisolated init(rawLine: String) {
        self.rawLine = rawLine
        self.parts = rawLine.split(separator: " ")
        self.verbUpper = parts.first?.uppercased() ?? ""
    }

    nonisolated var isReportVerb: Bool {
        verbUpper == "REP" || verbUpper == "REPORT"
    }

    nonisolated var firstNumericChannelIndex: Int? {
        guard let token = parts.dropFirst().first(where: { Int($0) != nil }) else {
            return nil
        }
        return Int(token)
    }
}

private enum ShureIncomingFrameParser {
    nonisolated static func extractFrames(from text: String) -> [ShureIncomingFrame] {
        var frames: [ShureIncomingFrame] = []
        var current = ""
        var inside = false

        for ch in text {
            if ch == "<" {
                inside = true
                current = ""
            } else if ch == ">" {
                guard inside else { continue }
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    frames.append(ShureIncomingFrame(rawLine: trimmed))
                }
                inside = false
                current = ""
            } else if inside {
                current.append(ch)
            }
        }

        return frames
    }

    nonisolated static func bracedValue(in line: String) -> String? {
        guard let openIdx = line.firstIndex(of: "{"),
              let closeIdx = line.lastIndex(of: "}") else {
            return nil
        }
        let valueRange = line.index(after: openIdx)..<closeIdx
        return String(line[valueRange]).trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func firstInt(afterKey key: String, in frame: ShureIncomingFrame) -> Int? {
        if let value = firstInt(afterKey: key, in: frame.rawLine) {
            return value
        }

        guard let keyIndex = frame.parts.firstIndex(where: { $0.uppercased() == key }) else {
            return nil
        }
        let start = frame.parts.index(after: keyIndex)
        guard start < frame.parts.endIndex else { return nil }
        for token in frame.parts[start...] {
            if let value = firstInt(in: token) {
                return value
            }
        }
        return nil
    }

    nonisolated static func firstDouble(afterKey key: String, in frame: ShureIncomingFrame) -> Double? {
        guard let keyIndex = frame.parts.firstIndex(where: { $0.uppercased() == key }) else {
            return nil
        }
        let start = frame.parts.index(after: keyIndex)
        guard start < frame.parts.endIndex else { return nil }
        for token in frame.parts[start...] {
            if let value = Double(token) {
                return value
            }
        }
        return nil
    }

    nonisolated static func lastInt(afterKey key: String, in frame: ShureIncomingFrame) -> Int? {
        guard let keyIndex = frame.parts.firstIndex(where: { $0.uppercased() == key }) else {
            return nil
        }
        let start = frame.parts.index(after: keyIndex)
        guard start < frame.parts.endIndex else { return nil }

        var lastValue: Int? = nil
        for token in frame.parts[start...] {
            if let value = firstInt(in: token) {
                lastValue = value
            }
        }
        return lastValue
    }

    nonisolated static func lastDouble(afterKey key: String, in frame: ShureIncomingFrame) -> Double? {
        guard let keyIndex = frame.parts.firstIndex(where: { $0.uppercased() == key }) else {
            return nil
        }
        let start = frame.parts.index(after: keyIndex)
        guard start < frame.parts.endIndex else { return nil }

        var lastValue: Double? = nil
        for token in frame.parts[start...] {
            if let value = Double(token) {
                lastValue = value
            }
        }
        return lastValue
    }

    private nonisolated static func firstInt(afterKey key: String, in line: String) -> Int? {
        let upper = line.uppercased()
        guard let range = upper.range(of: key) else { return nil }
        return firstInt(in: line[range.upperBound...])
    }

    private nonisolated static func firstInt<S: StringProtocol>(in text: S) -> Int? {
        var digits = ""
        var started = false
        for ch in text {
            if ch.isNumber {
                digits.append(ch)
                started = true
            } else if started {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }
}

struct ShureSampleFrameTelemetry: Equatable {
    let rfLevel: Double
    let audioLevel: Double?
}

struct ShureAxientSampleFrameTelemetry: Equatable {
    let channelQuality: Int
    let audioBitmap: Int
    let audioPeakLevel: Double?
    let audioRmsLevel: Double?
    /// RSSI_LED_BITMAP-format registers per antenna, matching what
    /// RSSI_LED_BITMAP 0/1 return over REP -- present in normal
    /// antenna-diversity mode. Absent (nil) in frequency-diversity
    /// combining mode, which reports RF differently; parsed opportunistically
    /// so audio telemetry still flows even when RF fields aren't there.
    let rfLedBitmapA: Int?
    let rfLedBitmapB: Int?
}

enum ShureSampleFrameTelemetryParser {
    static func parseCompactSamplePayload(from rawLine: String) -> ShureSampleFrameTelemetry? {
        let parts = rawLine.split(separator: " ")
        guard parts.count >= 6,
              parts[0].uppercased() == "SAMPLE",
              parts[2].uppercased() == "ALL" else {
            return nil
        }

        let payload = Array(parts.dropFirst(3))
        guard let placeholderIndex = payload.firstIndex(where: { Double($0) == nil }) else {
            guard let rfLevel = payload.first.flatMap({ Double($0) }) else { return nil }
            let audioLevel = payload.last.flatMap { Double($0) }
            return ShureSampleFrameTelemetry(rfLevel: rfLevel, audioLevel: audioLevel)
        }

        if placeholderIndex == 0 {
            guard payload.count >= 3,
                  let rfLevel = Double(payload[1]) else {
                return nil
            }
            let audioLevel = Double(payload[2])
            return ShureSampleFrameTelemetry(rfLevel: rfLevel, audioLevel: audioLevel)
        }

        guard let rfLevel = Double(payload[placeholderIndex - 1]) else {
            return nil
        }

        let trailingNumericValues = payload[(placeholderIndex + 1)...].compactMap { Double($0) }
        let audioLevel = trailingNumericValues.max()
        return ShureSampleFrameTelemetry(rfLevel: rfLevel, audioLevel: audioLevel)
    }
}

enum ShureAxientSampleFrameTelemetryParser {
    static func parse(from rawLine: String) -> ShureAxientSampleFrameTelemetry? {
        let parts = rawLine.split(separator: " ")
        guard parts.count >= 7,
              parts[0].uppercased() == "SAMPLE",
              parts[2].uppercased() == "ALL" else {
            return nil
        }

        let payload = Array(parts.dropFirst(3))
        guard payload.count >= 4,
              let channelQuality = Int(payload[0]),
              let audioBitmap = Int(payload[1]) else {
            return nil
        }

        let audioPeakLevel = Double(payload[2])
        let audioRmsLevel = Double(payload[3])

        // Field layout beyond the audio quartet: [4]=antenna label,
        // [5]=RF LED bitmap A, [6]=RF level A, [7]=RF LED bitmap B,
        // [8]=RF level B. Bounds-checked independently of the audio fields
        // above since frequency-diversity combining mode omits them.
        let rfLedBitmapA = payload.count > 5 ? Int(payload[5]) : nil
        let rfLedBitmapB = payload.count > 7 ? Int(payload[7]) : nil

        return ShureAxientSampleFrameTelemetry(
            channelQuality: channelQuality,
            audioBitmap: audioBitmap,
            audioPeakLevel: audioPeakLevel,
            audioRmsLevel: audioRmsLevel,
            rfLedBitmapA: rfLedBitmapA,
            rfLedBitmapB: rfLedBitmapB
        )
    }
}

enum ShureReceiverPresenceResolver {
    static func resolveNonAxientState(
        rfBarCount: Int,
        recentFalseAt: Date?,
        recentTrueAt: Date?,
        rfUpdatedRecently: Bool
    ) -> ShureTelemetryTransmitterState {
        if recentFalseAt != nil {
            if rfUpdatedRecently, rfBarCount <= 1 {
                return .off
            }
            return .off
        }

        if recentTrueAt != nil {
            return .on
        }

        return .off
    }
}

enum ShureReconnectBackoff {
    static let baseDelaySeconds: TimeInterval = 1.0
    static let maxDelaySeconds: TimeInterval = 60.0

    /// Exponential backoff delay (before jitter) for a 1-indexed attempt
    /// number. Attempt 1 is the first retry after an unexpected drop.
    static func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return baseDelaySeconds }
        let raw = baseDelaySeconds * pow(2.0, Double(attempt - 1))
        return min(maxDelaySeconds, raw)
    }
}

struct ShureAxientAudioDisposition: Equatable {
    let acceptedLevel: Double?
    let shouldClearStoredLevel: Bool
}

enum ShureAxientAudioDispositionResolver {
    static func resolve(
        keyUpper: String,
        level: Double,
        shouldAccept: Bool,
        bitmapAllowsLevel: Bool
    ) -> ShureAxientAudioDisposition {
        if keyUpper == "AUDIO_LED_BITMAP" {
            if bitmapAllowsLevel, shouldAccept {
                return ShureAxientAudioDisposition(
                    acceptedLevel: level,
                    shouldClearStoredLevel: false
                )
            }
            // The receiver's own LED bitmap says there's no audio -- actively
            // zero the meter rather than just declining to update it, so a
            // stale nonzero RMS/PEAK reading from a moment ago doesn't linger.
            return ShureAxientAudioDisposition(
                acceptedLevel: 0,
                shouldClearStoredLevel: true
            )
        }

        // AUDIO_LEVEL_RMS/PEAK report a nonzero noise-floor value even on a
        // channel with no transmitter present (confirmed live: CHAN_QUALITY
        // 255/no antenna channels steadily reporting RMS ~33, rendering as a
        // visible 2-3 bar meter with nothing plugged in). AUDIO_LED_BITMAP is
        // the receiver's own gate on whether that numeric reading reflects
        // real audio, so RMS/PEAK must defer to it -- without this guard the
        // gate above never actually filters anything, since RMS/PEAK values
        // always arrive as their own separate keys, never as AUDIO_LED_BITMAP.
        guard bitmapAllowsLevel else {
            return ShureAxientAudioDisposition(
                acceptedLevel: nil,
                shouldClearStoredLevel: true
            )
        }

        return ShureAxientAudioDisposition(
            acceptedLevel: shouldAccept ? level : nil,
            shouldClearStoredLevel: false
        )
    }
}

enum ShureAxientPresenceResolver {
    static let positiveEvidenceHoldSeconds: TimeInterval = 12.0
    // A single brief false frame shouldn't flip presence -- that's what the
    // positive hold above is for. But real hardware evidence (a customer
    // field log, mic powered off ~1s after the last positive TX_DEVICE_ID
    // reply) showed negative evidence arriving continuously, every second,
    // for 14+ seconds, while positive evidence's 12s hold kept resolving
    // .on the entire time -- RF had already collapsed to 0 immediately, so
    // the Overview showed "Critical" for the better part of the hold
    // window instead of "Off". Sustained negative evidence (not just a
    // one-off blip) should be able to override an in-progress positive
    // hold well before it naturally expires.
    static let sustainedNegativeEvidenceSeconds: TimeInterval = 2.0

    static func resolve(
        recentPositiveEvidenceAt: Date?,
        recentNegativeEvidenceAt: Date?,
        negativeEvidenceStreakStartAt: Date? = nil,
        now: Date
    ) -> ShureTelemetryTransmitterState {
        let negativeIsFresh = recentNegativeEvidenceAt.map { now.timeIntervalSince($0) <= 1.5 } ?? false

        if let recentPositiveEvidenceAt,
           now.timeIntervalSince(recentPositiveEvidenceAt) <= positiveEvidenceHoldSeconds {
            if negativeIsFresh,
               let negativeEvidenceStreakStartAt,
               now.timeIntervalSince(negativeEvidenceStreakStartAt) >= sustainedNegativeEvidenceSeconds {
                return .off
            }
            return .on
        }

        if negativeIsFresh {
            return .off
        }

        return .off
    }
}

struct ShureAxientRfBarHoldState: Equatable {
    var acceptedValue: Int
    var candidateValue: Int?
    var candidateSince: Date?
}

/// Real AD4Q RSSI readings naturally dip for a second or two (a person
/// briefly walking between antenna and transmitter, momentary multipath)
/// even on a rig with a solid overall link -- confirmed via a real packet
/// capture and diagnostics log showing a smooth multi-sample dip and
/// recovery on both antennas together, not corrupted/garbage values.
/// Shure's own Wireless Workbench visibly holds the meter steady through
/// dips like that; converting each raw RSSI sample to bars immediately made
/// Relay's meter look erratic by comparison. Mirrors the codebase's
/// existing mic-audio hold pattern (`shouldAcceptMicLevel`): rises are
/// accepted immediately (fast attack), drops are only accepted once
/// they've persisted past a short hold window (slow release).
enum ShureAxientRfBarHoldResolver {
    static let dropHoldSeconds: TimeInterval = 1.5

    static func resolve(
        rawBars: Int,
        previousState: ShureAxientRfBarHoldState?,
        now: Date
    ) -> ShureAxientRfBarHoldState {
        guard let previousState else {
            return ShureAxientRfBarHoldState(acceptedValue: rawBars, candidateValue: nil, candidateSince: nil)
        }

        if rawBars >= previousState.acceptedValue {
            return ShureAxientRfBarHoldState(acceptedValue: rawBars, candidateValue: nil, candidateSince: nil)
        }

        if previousState.candidateValue != rawBars {
            return ShureAxientRfBarHoldState(acceptedValue: previousState.acceptedValue, candidateValue: rawBars, candidateSince: now)
        }

        let candidateSince = previousState.candidateSince ?? now
        guard now.timeIntervalSince(candidateSince) >= dropHoldSeconds else {
            return previousState
        }

        return ShureAxientRfBarHoldState(acceptedValue: rawBars, candidateValue: nil, candidateSince: nil)
    }
}

struct ShureRssiLedBitmapDecoded: Equatable {
    let bars: Int
    let isOverload: Bool
}

/// Decodes the raw RSSI_LED_BITMAP register per Shure's Axient Digital and
/// ANX4 command-string references: bits 0-4 (LEDs 1-5, amber) are the
/// normal signal ladder, bit 5 (LED 6, red) is a separate overload/RF-pad-
/// engaged flag rather than a 6th rung on the same ladder -- the spec
/// explicitly documents it lighting with LEDs 1-5 all off. Pulled out as a
/// pure function so this parsing can be verified against the documented
/// bit patterns directly, without needing hardware to physically trigger a
/// genuine overload condition.
enum ShureRssiLedBitmapDecoder {
    static func decode(_ bitmap: Int) -> ShureRssiLedBitmapDecoded {
        let ladderMask = bitmap & 0x1F
        var bars = 0
        for bit in 0..<5 {
            if (ladderMask & (1 << bit)) != 0 {
                bars += 1
            }
        }
        return ShureRssiLedBitmapDecoded(bars: bars, isOverload: (bitmap & 0x20) != 0)
    }
}

private struct ShureReportReductionContext: Sendable {
    let isAxientDevice: Bool
    let hasBatteryValue: Bool
    let meterRate: Int
    let lastNonZeroMicAudioAt: Date?
    let now: Date
}

private struct ShureReportContextSnapshot: Sendable {
    let hasBatteryValueByChannel: [Int: Bool]
    let meterRates: [Int: Int]
    let lastNonZeroMicAudioAt: [Int: Date]
}

private struct ShureReportReduction: Sendable {
    enum BatteryUpdate: Sendable {
        case clear(reason: String)
        case set(label: String, percentage: Int?, isApproximate: Bool, priority: Int)
        case ignoredSentinel(Int)
        case unparsed
    }

    struct MicAudioUpdate: Sendable {
        let keyUpper: String
        let level: Double
        let shouldAccept: Bool
        /// True clip/overage flag from the receiver's own AUDIO_LED_BITMAP
        /// bit 7 ("LED 8 - Red" per Shure's Axient Digital command-string
        /// reference) -- nil for keys that don't carry this bit (AUDIO_LVL,
        /// AUDIO_LEVEL_RMS/PEAK). Deliberately not derived from our own
        /// popcount-based level/bar-count: that's an approximation of what
        /// the receiver's meter is doing, this is the receiver's own answer.
        let isOverload: Bool?
    }

    var channelName: String?
    var channelNameMissingBraces = false
    var rfTxLevel: Int?
    var frequencyDisplay: String?
    var batteryKey: String?
    var batteryUpdate: BatteryUpdate?
    var audioMute: Bool?
    var meterRate: Int?
    var rfBarCount: Int?
    var rfOverload: Bool?
    /// Which antenna an RSSI_LED_BITMAP reading came from (1-4). Diversity
    /// receivers report each antenna as a separate frame; the consumer
    /// needs this to combine them (max across antennas) before smoothing,
    /// rather than feeding each antenna's reading into shared hold state
    /// independently, which lets whichever antenna happens to report next
    /// override the other's in-progress drop.
    var rfAntennaIndex: Int?
    var transmitterPresent: Bool?
    var transmitterDeviceIDPresent: Bool?
    var shouldPreserveExistingZeroBitmap = false
    var micAudioUpdate: MicAudioUpdate?

    nonisolated init() {}
}

private struct ShurePreparedReportWorkItem: Sendable {
    let frameIndex: Int
    let channelIndex: Int?
    let reduction: ShureReportReduction?
}

private struct ShurePreparedIncomingData: Sendable {
    let frames: [ShureIncomingFrame]
    let reportWorkItems: [ShurePreparedReportWorkItem]
}

private struct ShureTcpChannelState: Sendable {
    var channelName: String?
    var rfTxLevel: Int?
    var frequencyDisplay: String?
    var batteryLabel: String?
    var batteryPercentage: Int?
    var batteryIsApproximate: Bool?
    var batteryPriority: Int?
    var audioMute: Bool?
    var meterRate: Int?
    var rfBarCount: Int?
    var rfOverload: Bool?
    var micAudioLevel: Double?
    var micAudioOverload: Bool?
    var lastUpdatedAt: Date?

    nonisolated init() {}
}

private struct ShureUdpChannelState: Sendable {
    var rfTxLevel: Int?
    var rfBarCount: Int?
    var micAudioLevel: Double?
    var lastUpdatedAt: Date?

    nonisolated init() {}
}

private struct ShureStandardReportChannelSnapshot: Sendable, Equatable {
    var channelName: String?
    var rfTxLevel: Int?
    var frequencyDisplay: String?
    var batteryLabel: String?
    var batteryPercentage: Int?
    var batteryIsApproximate: Bool?
    var batteryPriority: Int?
    var audioMute: Bool?
    var meterRate: Int?
    var rfBarCount: Int?
    var rfOverload: Bool?
    var micAudioLevel: Double?
    var micAudioOverload: Bool?
}

private struct ShureStandardReportLowFrequencySnapshot: Sendable, Equatable {
    var channelName: String?
    var frequencyDisplay: String?
    var batteryLabel: String?
    var batteryPercentage: Int?
    var batteryIsApproximate: Bool?
    var audioMute: Bool?
    var meterRate: Int?
}

struct ShureTelemetryChannelSnapshot: Sendable, Equatable, Identifiable {
    let id: String
    let channelIndex: Int
    let channelName: String?
    let frequencyLabel: String?
    let batteryPercent: Int?
    let batteryLabel: String?
    let batteryIsApproximate: Bool
    let rfBars: Int?
    let rfOverload: Bool
    let rfTxLevel: Int?
    let audioLevel: Double?
    let audioOverload: Bool
    let audioLeftLevel: Double?
    let audioRightLevel: Double?
    let isMuted: Bool?
    let meterRate: Int?
    let transmitterState: ShureTelemetryTransmitterState
    let transmitterPresent: Bool?
    let lastHeardAt: Date?
    let lastBatteryAt: Date?
    let lastRFAt: Date?
    let lastAudioAt: Date?
}

enum ShureTelemetryTransmitterState: String, Sendable, Equatable {
    case on
    case off
    case unknown
}

struct ShureTelemetryDiagnosticsSnapshot: Sendable, Equatable {
    let activeServiceCount: Int
    let connectedPhysicalDeviceCount: Int
    let overviewSubscriberCount: Int
    let channelSubscriberCount: Int
    let pollingIntervalDescription: String
    let snapshotPublishRateHz: Double
    let averageParseTimeMilliseconds: Double
    let averageSnapshotBuildTimeMilliseconds: Double
    let droppedCoalescedUpdateCount: Int
    let lastSlowRefreshAt: Date?
    let lastFastTelemetryAt: Date?

    static let empty = ShureTelemetryDiagnosticsSnapshot(
        activeServiceCount: 0,
        connectedPhysicalDeviceCount: 0,
        overviewSubscriberCount: 0,
        channelSubscriberCount: 0,
        pollingIntervalDescription: "idle",
        snapshotPublishRateHz: 0,
        averageParseTimeMilliseconds: 0,
        averageSnapshotBuildTimeMilliseconds: 0,
        droppedCoalescedUpdateCount: 0,
        lastSlowRefreshAt: nil,
        lastFastTelemetryAt: nil
    )
}

struct ShureTelemetryDeviceSnapshot: Sendable, Equatable {
    let deviceID: UUID?
    let deviceName: String
    let isConnected: Bool
    let isReconnecting: Bool
    let lastHeardAt: Date?
    let updatedAt: Date?
    let channels: [ShureTelemetryChannelSnapshot]
    let diagnostics: ShureTelemetryDiagnosticsSnapshot

    static let empty = ShureTelemetryDeviceSnapshot(
        deviceID: nil,
        deviceName: "",
        isConnected: false,
        isReconnecting: false,
        lastHeardAt: nil,
        updatedAt: nil,
        channels: [],
        diagnostics: .empty
    )

    func channelSnapshot(for channelIndex: Int) -> ShureTelemetryChannelSnapshot? {
        channels.first(where: { $0.channelIndex == channelIndex })
    }

    /// Compares only the fields the UI consumes, deliberately ignoring the
    /// volatile `updatedAt` timestamp and the `diagnostics` block. Both of
    /// those change on every build, so a plain `==` made every freshly-built
    /// snapshot compare unequal — silently defeating publish de-duplication
    /// and forcing a full SwiftUI/hub update cascade on every poll tick even
    /// when nothing actually changed.
    func hasSameContent(as other: ShureTelemetryDeviceSnapshot) -> Bool {
        deviceID == other.deviceID
            && deviceName == other.deviceName
            && isConnected == other.isConnected
            && isReconnecting == other.isReconnecting
            && lastHeardAt == other.lastHeardAt
            && channels == other.channels
    }
}

private struct ShureStandardReportStateUpdate: Sendable {
    let channelIndex: Int
    let channelName: String?
    let rfTxLevel: Int?
    let frequencyDisplay: String?
    let batteryUpdate: ShureReportReduction.BatteryUpdate?
    let audioMute: Bool?
    let meterRate: Int?
    let rfBarCount: Int?
    let rfOverload: Bool?
    let shouldPreserveExistingZeroBitmap: Bool
    let micAudioLevel: Double?
    let micAudioAccepted: Bool
    let shouldClearMicAudioLevel: Bool
    let micAudioOverload: Bool?
    let now: Date
}

private struct ShureUdpStateUpdate: Sendable {
    let channelIndex: Int
    let rfTxLevel: Int?
    let rfBarCount: Int?
    let micAudioLevel: Double?
    let now: Date
}

private struct ShureSnapshotCompositionPolicy: Sendable {
    let preferUdpRf: Bool
    let preferUdpMic: Bool
}

private actor ShureStandardReportStateStore {
    private var tcpChannelStates: [Int: ShureTcpChannelState] = [:]
    private var udpChannelStates: [Int: ShureUdpChannelState] = [:]

    private func applyTcpState(_ update: ShureStandardReportStateUpdate) {
        var state = tcpChannelStates[update.channelIndex] ?? ShureTcpChannelState()

        if let channelName = update.channelName {
            state.channelName = channelName
        }
        if let rfTxLevel = update.rfTxLevel {
            state.rfTxLevel = rfTxLevel
        }
        if let frequencyDisplay = update.frequencyDisplay {
            state.frequencyDisplay = frequencyDisplay
        }

        if let batteryUpdate = update.batteryUpdate {
            switch batteryUpdate {
            case .clear:
                state.batteryLabel = nil
                state.batteryPercentage = nil
                state.batteryIsApproximate = nil
                state.batteryPriority = nil
            case .set(let label, let percentage, let isApproximate, let priority):
                let existingPriority = state.batteryPriority ?? 0
                if priority >= existingPriority {
                    state.batteryLabel = label
                    state.batteryPriority = priority
                }
                // Percentage updates independently of the label-priority
                // race above, not just gated inside it. Runtime-remaining
                // keys (TX_BATT_MINS/BATT_MINS/BATT_RUN_TIME) have the
                // highest priority of any battery key and carry no
                // percentage of their own -- once one of those has ever
                // won the race and latched batteryPriority to that high
                // value, every later TX_BATT_CHARGE_PERCENT/BATT_CHARGE
                // update (lower priority) used to fail `priority >=
                // existingPriority` and never reach here at all, freezing
                // batteryPercentage forever at whatever it last was before
                // that happened -- confirmed live: Overview's % display got
                // stuck within the first couple minutes of a device
                // connecting while the single-tile's time-remaining label
                // (which only needs to beat its own priority) kept updating
                // correctly the entire time, making it look like an
                // Overview-only bug when the real cause was upstream. The
                // label text and the percentage are logically independent
                // fields -- percentage should refresh whenever a report
                // actually provides one, regardless of which key currently
                // owns display priority for the label.
                // Exact percentage (TX_BATT_CHARGE_PERCENT/BATT_CHARGE/
                // TX_BATT_PERCENT/BATT_PERCENT, priority 2) always wins.
                // Approximate percentage (derived from TX_BATT_BARS/
                // BATT_BARS's 5-level reading, priority 1 -- e.g. a full
                // 5/5 bars rounds to "100%") only applies when there isn't
                // already an exact reading in hand, so it can't clobber it.
                // Decoupling percentage from the label-priority race above
                // (this same block, moments earlier) fixed one bug but
                // introduced this one: without any ordering between the two
                // percentage *sources* themselves, whichever happened to
                // arrive most recently won outright -- confirmed live, a
                // precise 86%/94% reading would show for a moment then get
                // overwritten by "100%" the next time a full-bars report
                // came in, which happens often since 81-100% all round to
                // 5/5 bars.
                if let percentage {
                    let currentIsExact = state.batteryIsApproximate == false
                    if !isApproximate || !currentIsExact {
                        state.batteryPercentage = percentage
                        state.batteryIsApproximate = isApproximate
                    }
                }
            case .ignoredSentinel, .unparsed:
                break
            }
        }

        if let audioMute = update.audioMute {
            state.audioMute = audioMute
        }
        if let meterRate = update.meterRate {
            state.meterRate = meterRate
        }
        if let rfBarCount = update.rfBarCount {
            if !(update.shouldPreserveExistingZeroBitmap && rfBarCount == 0 && (state.rfBarCount ?? 0) > 0) {
                state.rfBarCount = rfBarCount
            }
        }
        if let rfOverload = update.rfOverload {
            state.rfOverload = rfOverload
        }
        if let micAudioOverload = update.micAudioOverload {
            state.micAudioOverload = micAudioOverload
        }
        if update.shouldClearMicAudioLevel {
            state.micAudioLevel = nil
        } else if update.micAudioAccepted, let micAudioLevel = update.micAudioLevel {
            state.micAudioLevel = micAudioLevel
        }

        state.lastUpdatedAt = update.now
        tcpChannelStates[update.channelIndex] = state
    }

    func applyTcp(
        _ update: ShureStandardReportStateUpdate,
        composition: ShureSnapshotCompositionPolicy
    ) -> ShureStandardReportChannelSnapshot? {
        applyTcpState(update)
        return snapshot(channelIndex: update.channelIndex, composition: composition)
    }

    func applyUdp(
        _ update: ShureUdpStateUpdate,
        composition: ShureSnapshotCompositionPolicy
    ) -> ShureStandardReportChannelSnapshot? {
        var state = udpChannelStates[update.channelIndex] ?? ShureUdpChannelState()
        if let rfTxLevel = update.rfTxLevel {
            state.rfTxLevel = rfTxLevel
        }
        if let rfBarCount = update.rfBarCount {
            state.rfBarCount = rfBarCount
        }
        if let micAudioLevel = update.micAudioLevel {
            state.micAudioLevel = micAudioLevel
        }
        state.lastUpdatedAt = update.now
        udpChannelStates[update.channelIndex] = state
        return snapshot(channelIndex: update.channelIndex, composition: composition)
    }

    func snapshot(
        channelIndex: Int,
        composition: ShureSnapshotCompositionPolicy
    ) -> ShureStandardReportChannelSnapshot? {
        let tcpState = tcpChannelStates[channelIndex]
        let udpState = udpChannelStates[channelIndex]
        guard tcpState != nil || udpState != nil else { return nil }

        let rfTxLevel = composition.preferUdpRf
            ? (udpState?.rfTxLevel ?? tcpState?.rfTxLevel)
            : (tcpState?.rfTxLevel ?? udpState?.rfTxLevel)
        let rfBarCount = composition.preferUdpRf
            ? (udpState?.rfBarCount ?? tcpState?.rfBarCount)
            : (tcpState?.rfBarCount ?? udpState?.rfBarCount)
        let micAudioLevel = composition.preferUdpMic
            ? (udpState?.micAudioLevel ?? tcpState?.micAudioLevel)
            : (tcpState?.micAudioLevel ?? udpState?.micAudioLevel)

        return ShureStandardReportChannelSnapshot(
            channelName: tcpState?.channelName,
            rfTxLevel: rfTxLevel,
            frequencyDisplay: tcpState?.frequencyDisplay,
            batteryLabel: tcpState?.batteryLabel,
            batteryPercentage: tcpState?.batteryPercentage,
            batteryIsApproximate: tcpState?.batteryIsApproximate,
            batteryPriority: tcpState?.batteryPriority,
            audioMute: tcpState?.audioMute,
            meterRate: tcpState?.meterRate,
            rfBarCount: rfBarCount,
            rfOverload: tcpState?.rfOverload,
            micAudioLevel: micAudioLevel,
            micAudioOverload: tcpState?.micAudioOverload
        )
    }

    func clear() {
        tcpChannelStates.removeAll()
        udpChannelStates.removeAll()
    }
}

private enum ShureReportReducer {
    nonisolated static func reduce(frame: ShureIncomingFrame, context: ShureReportReductionContext) -> ShureReportReduction {
        var reduction = ShureReportReduction()
        let parts = frame.parts
        guard frame.isReportVerb, parts.count >= 3 else {
            return reduction
        }

        if parts.contains(where: { $0.uppercased() == "CHAN_NAME" }) {
            if let cleaned = ShureIncomingFrameParser.bracedValue(in: frame.rawLine) {
                if !cleaned.isEmpty {
                    reduction.channelName = cleaned
                }
            } else {
                reduction.channelNameMissingBraces = true
            }
        }

        if let rfIndex = parts.firstIndex(where: { $0.uppercased() == "RF_TX_LVL" }) {
            let valueIndex = parts.index(after: rfIndex)
            if valueIndex < parts.endIndex {
                reduction.rfTxLevel = Int(parts[valueIndex])
            }
        }

        if let freqIndex = parts.firstIndex(where: { $0.uppercased() == "FREQUENCY" }) {
            let valueIndex = parts.index(after: freqIndex)
            if valueIndex < parts.endIndex {
                let raw = String(parts[valueIndex])
                if let numeric = Double(raw) {
                    if numeric > 1000 {
                        reduction.frequencyDisplay = String(format: "%.3f MHz", numeric / 1000.0)
                    } else {
                        reduction.frequencyDisplay = String(format: "%.3f MHz", numeric)
                    }
                } else {
                    reduction.frequencyDisplay = raw
                }
            }
        }

        let batteryKeys: Set<String> = [
            "TX_BATT_CHARGE_PERCENT", "BATT_CHARGE",
            "TX_BATT_BARS", "BATT_BARS",
            "TX_BATT_MINS", "BATT_MINS", "BATT_RUN_TIME",
            "BATT_HEALTH",
            "TX_BATT_PERCENT", "BATT_PERCENT"
        ]
        if let keyIndex = parts.firstIndex(where: { batteryKeys.contains($0.uppercased()) }) {
            let key = parts[keyIndex].uppercased()
            reduction.batteryKey = key
            let value = ShureIncomingFrameParser.firstInt(afterKey: key, in: frame)
            reduction.batteryUpdate = reduceBattery(key: key, value: value)
        }

        if parts.count >= 3,
           Int(parts[1]) != nil {
            let key = parts[2].uppercased()
            switch key {
            case "AUDIO_MUTE":
                if parts.count >= 4 {
                    let value = parts[3].uppercased()
                    reduction.audioMute = (value == "ON" || value == "TRUE" || value == "1")
                }
            case "METER_RATE":
                if parts.count >= 4 {
                    reduction.meterRate = Int(parts[3])
                }
            case "RSSI":
                if let raw = ShureIncomingFrameParser.lastDouble(afterKey: "RSSI", in: frame) {
                    let bars = rfBars(fromDbm: raw - 120.0)
                    if !context.isAxientDevice {
                        reduction.rfBarCount = bars
                    }
                    // For Axient devices, RSSI_LED_BITMAP below is the RF
                    // bar source -- it's the receiver's own native LED
                    // ladder register, the same one Shure's own Wireless
                    // Workbench reads to draw its RF meter. Deriving bars
                    // from this dBm reading instead used arbitrary,
                    // never-validated bucket boundaries and fought
                    // RSSI_LED_BITMAP over the same field.
                }
            case "RSSI_LED_BITMAP":
                if let bitmap = ShureIncomingFrameParser.lastInt(afterKey: "RSSI_LED_BITMAP", in: frame) {
                    // ULX-D and SLX-D don't have this property at all
                    // (confirmed against their own references), so this
                    // only ever fires for Axient Digital/ANX4/ADTD/ADTQ
                    // devices. See ShureRssiLedBitmapDecoder for the bit
                    // layout.
                    let decoded = ShureRssiLedBitmapDecoder.decode(bitmap)
                    let count = decoded.bars
                    reduction.rfBarCount = count
                    reduction.rfOverload = decoded.isOverload
                    reduction.rfAntennaIndex = ShureIncomingFrameParser.firstInt(afterKey: "RSSI_LED_BITMAP", in: frame)
                    reduction.shouldPreserveExistingZeroBitmap = (count == 0 && !context.isAxientDevice)
                }
            case "RF_ANTENNA":
                if parts.count >= 4 {
                    let value = parts[3].uppercased()
                    reduction.transmitterPresent = (value != "XX")
                }
            case "TX_DEVICE_ID":
                if let value = ShureIncomingFrameParser.bracedValue(in: frame.rawLine) {
                    reduction.transmitterDeviceIDPresent = !value.isEmpty
                } else if parts.count >= 4 {
                    let rawValue = parts[3...].joined(separator: " ")
                    let trimmedValue = rawValue
                        .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    reduction.transmitterDeviceIDPresent = !trimmedValue.isEmpty
                }
            case "RX_RF_LVL":
                if let raw = ShureIncomingFrameParser.firstDouble(afterKey: "RX_RF_LVL", in: frame) {
                    reduction.rfBarCount = rfBars(fromDbm: raw - 128.0)
                }
            case "CHAN_QUALITY":
                if let quality = ShureIncomingFrameParser.firstInt(afterKey: "CHAN_QUALITY", in: frame) {
                    if quality == 255, context.isAxientDevice {
                        reduction.transmitterPresent = false
                        reduction.shouldPreserveExistingZeroBitmap = false
                    } else if (0...5).contains(quality) {
                        if context.isAxientDevice {
                            reduction.transmitterPresent = quality > 0
                            // Don't also write rfBarCount here: on real AD4Q
                            // hardware CHAN_QUALITY only ever reports 5 or
                            // 255 (a binary present/absent flag, not a
                            // graduated reading -- confirmed against a full
                            // session log), yet it's queried far more often
                            // than RSSI/RSSI_LED_BITMAP (every fast refresh
                            // tick vs. only the ~1s slow refresh). Letting it
                            // share this field meant it constantly snapped
                            // the RF bars to "full"/"zero" moments after the
                            // real antenna-strength RSSI reading set them,
                            // making the RF meter look erratic. RSSI is the
                            // sole bar-count source for Axient devices below.
                        } else {
                            reduction.rfBarCount = quality
                            reduction.shouldPreserveExistingZeroBitmap = (quality == 0)
                        }
                    }
                }
            default:
                break
            }
        }

        reduction.micAudioUpdate = reduceMicAudio(frame: frame, context: context)
        return reduction
    }

    private nonisolated static func reduceBattery(key: String, value: Int?) -> ShureReportReduction.BatteryUpdate {
        guard let value else { return .unparsed }

        switch key {
        case "TX_BATT_CHARGE_PERCENT", "BATT_CHARGE", "TX_BATT_PERCENT", "BATT_PERCENT":
            if value == 255 || value > 100 {
                return .ignoredSentinel(value)
            }
            return .set(label: "\(value)%", percentage: value, isApproximate: false, priority: 2)

        case "TX_BATT_BARS", "BATT_BARS":
            if value == 255 {
                return .clear(reason: "bars_unknown")
            }
            guard (0...5).contains(value) else { return .unparsed }
            let percent = Int((Double(value) / 5.0) * 100.0)
            return .set(label: "\(percent)% approx", percentage: percent, isApproximate: true, priority: 1)

        case "TX_BATT_MINS", "BATT_MINS", "BATT_RUN_TIME":
            // Some Shure devices briefly report sentinel-like or otherwise
            // unrealistic runtime values before resolving to a real estimate.
            // Ignore those so they do not override a sane battery display.
            if value >= 65534 || value > (24 * 60) {
                return .ignoredSentinel(value)
            }
            if value >= 60 {
                let hours = value / 60
                let remainder = value % 60
                return .set(
                    label: String(format: "%d:%02d", hours, remainder),
                    percentage: nil,
                    isApproximate: false,
                    priority: 3
                )
            }
            return .set(label: "\(value)m", percentage: nil, isApproximate: false, priority: 3)

        case "BATT_HEALTH":
            if value == 255 { return .ignoredSentinel(value) }
            return .set(label: "\(value)% (health)", percentage: nil, isApproximate: false, priority: 0)

        default:
            return .unparsed
        }
    }

    private nonisolated static func reduceMicAudio(
        frame: ShureIncomingFrame,
        context: ShureReportReductionContext
    ) -> ShureReportReduction.MicAudioUpdate? {
        let parts = frame.parts
        guard parts.count >= 4 else { return nil }

        var allowedAudioKeys: Set<String> = ["AUDIO_LVL"]
        if context.isAxientDevice {
            allowedAudioKeys.formUnion([
                "AUDIO_LEVEL_PEAK",
                "AUDIO_LEVEL_RMS",
                "AUDIO_LED_BITMAP"
            ])
        }

        guard let audioKeyIndex = parts.firstIndex(where: { allowedAudioKeys.contains($0.uppercased()) }) else {
            return nil
        }

        let keyUpper = parts[audioKeyIndex].uppercased()
        var level: Double? = nil
        let valueIndex = parts.index(after: audioKeyIndex)
        if valueIndex < parts.endIndex {
            level = Double(parts[valueIndex])
        }

        if level == nil,
           let range = frame.rawLine.uppercased().range(of: keyUpper) {
            let tail = frame.rawLine[range.upperBound...]
            var number = ""
            var started = false
            for ch in tail {
                if ch == "-" || ch == "." || ch.isNumber {
                    number.append(ch)
                    started = true
                } else if started {
                    break
                }
            }
            if !number.isEmpty {
                level = Double(number)
            }
        }

        var isOverload: Bool? = nil
        if keyUpper == "AUDIO_LED_BITMAP", let raw = level {
            let bitmap = Int(raw)
            let mask = bitmap & 0xFF
            var count = 0
            for bit in 0..<8 {
                if (mask & (1 << bit)) != 0 { count += 1 }
            }
            isOverload = (mask & 0x80) != 0
            level = Double(count) / 8.0 * 20.0
        } else if context.isAxientDevice,
                  (keyUpper == "AUDIO_LEVEL_PEAK" || keyUpper == "AUDIO_LEVEL_RMS"),
                  let raw = level {
            let clamped = min(max(raw, 0.0), 120.0)
            level = (clamped / 120.0) * 20.0
        }

        guard let level else { return nil }
        if context.isAxientDevice, keyUpper == "AUDIO_LVL" {
            return nil
        }

        let holdSeconds = context.meterRate == 0 ? 6.0 : 2.0
        let shouldAccept: Bool
        if level <= 0, context.hasBatteryValue,
           let lastNonZero = context.lastNonZeroMicAudioAt,
           context.now.timeIntervalSince(lastNonZero) < holdSeconds {
            shouldAccept = false
        } else {
            shouldAccept = true
        }

        return ShureReportReduction.MicAudioUpdate(
            keyUpper: keyUpper,
            level: level,
            shouldAccept: shouldAccept,
            isOverload: isOverload
        )
    }

    private nonisolated static func rfBars(fromDbm dbm: Double) -> Int {
        switch dbm {
        case let v where v >= -45: return 5
        case -60 ..< -45: return 4
        case -75 ..< -60: return 3
        case -90 ..< -75: return 2
        case -105 ..< -90: return 1
        default: return 0
        }
    }
}

private func preferredShureDisplayName(for device: ExternalDeviceConfig) -> String {
    let currentDisplayName = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelCode = device.shureModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let deviceIDName = device.shureDeviceIDName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let discoveryFunction = device.shureDiscoveryFCTN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let discoveryUACN = device.shureDiscoveryUACN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let isUdpOnly: Bool = {
        switch device.shureNetworkModel {
        case .anx4, .adtd, .adtq:
            return true
        default:
            return false
        }
    }()

    if isUdpOnly {
        let shouldPreferCanonicalName = currentDisplayName.isEmpty
            || (!deviceIDName.isEmpty && currentDisplayName.caseInsensitiveCompare(deviceIDName) == .orderedSame)
        if shouldPreferCanonicalName {
            if !modelCode.isEmpty { return modelCode }
            if !discoveryFunction.isEmpty { return discoveryFunction }
            if !discoveryUACN.isEmpty { return discoveryUACN }
        }
    }

    if !currentDisplayName.isEmpty { return currentDisplayName }
    if !modelCode.isEmpty { return modelCode }
    if !deviceIDName.isEmpty { return deviceIDName }
    if !discoveryFunction.isEmpty { return discoveryFunction }
    if !discoveryUACN.isEmpty { return discoveryUACN }
    return "Shure"
}

// MARK: - ANX4 UDP Handshake

private enum ShureAnx4Handshake {
    static let cidSuffix: [UInt8] = [0x00, 0x00, 0x11, 0xdd, 0xa0, 0x00, 0x00, 0x0e, 0xdd, 0xcc, 0xcc, 0xcc]
    static let defaultDeviceCIDPrefix: [UInt8] = [0xdd, 0xae, 0x08, 0xf6]

    static func senderCID(sessionId: [UInt8]) -> UUID {
        cid(prefix: sessionId)
    }

    static func targetCID(from discoveryCID: UUID?) -> UUID {
        guard let discoveryCID else {
            return cid(prefix: defaultDeviceCIDPrefix)
        }
        return discoveryCID
    }

    static func initialSubscribe(senderCID: UUID, targetCID: UUID, localSessionSelector: UInt16) -> Data {
        var payload = Data()
        payload.append(contentsOf: [0x00, 0x01])
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x05, 0x00, 0x00, 0x02, 0x00, 0x32, 0x00, 0x14, 0xff])
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x04,
                framingTargetCID: targetCID,
                payload: payload
            )
        )
    }

    static func sessionAck(
        senderCID: UUID,
        targetCID: UUID,
        localSessionSelector: UInt16,
        remoteQuerySelector: UInt16,
        remoteDataSelector: UInt16
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(remoteQuerySelector))
        payload.append(contentsOf: [0x00, 0x01, 0x00, 0x00])
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: selectorBytes(remoteDataSelector))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x06,
                framingTargetCID: targetCID,
                payload: payload
            )
        )
    }

    static func bootstrapFrame2(
        senderCID: UUID,
        localSessionSelector: UInt16,
        currentSelector: UInt16,
        previousSelector: UInt16,
        oldestSelector: UInt16,
        remoteQuerySelector: UInt16,
        remoteDataSelector: UInt16
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(currentSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(previousSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(oldestSelector))
        payload.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0x00, 0x00])

        var subPayload = Data()
        subPayload.append(contentsOf: [0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        subPayload.append(contentsOf: selectorBytes(remoteQuerySelector))
        subPayload.append(contentsOf: [0x70, 0x07, 0x0e, 0x00, 0x00])
        subPayload.append(contentsOf: selectorBytes(remoteDataSelector))
        payload.append(subPDU(payload: subPayload))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x02,
                framingTargetCID: nil,
                payload: payload
            )
        )
    }

    static func bootstrapFrame1(
        senderCID: UUID,
        localSessionSelector: UInt16,
        currentSelector: UInt16,
        previousSelector: UInt16,
        oldestSelector: UInt16,
        subtype: UInt8
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(currentSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(previousSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(oldestSelector))
        payload.append(contentsOf: [0xff, 0xff, 0x00, 0x00, 0x00, 0x00])

        let subPayload = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x70, 0x07, subtype, 0x00, 0x00, 0x00, 0x02])
        payload.append(subPDU(payload: subPayload))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x01,
                framingTargetCID: nil,
                payload: payload
            )
        )
    }

    static func telemetryRequestFrame(
        senderCID: UUID,
        localSessionSelector: UInt16,
        currentSelector: UInt16,
        previousSelector: UInt16,
        oldestSelector: UInt16,
        subtype: UInt8
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(currentSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(previousSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(oldestSelector))
        payload.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0x00, 0x00])

        let subPayload = Data([
            0x00, 0x01, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x70, 0x08, subtype, 0x02, 0x01, 0x20, 0x00,
            0x10, 0x10, 0x06, 0x01, 0x20, 0x00, 0x11
        ])
        payload.append(subPDU(payload: subPayload))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x01,
                framingTargetCID: nil,
                payload: payload
            )
        )
    }

    static func singlePropertyRequestFrame(
        senderCID: UUID,
        localSessionSelector: UInt16,
        currentSelector: UInt16,
        previousSelector: UInt16,
        oldestSelector: UInt16,
        propertyAddress: [UInt8]
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(currentSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(previousSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(oldestSelector))
        payload.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0x00, 0x00])

        var subPayload = Data([
            0x00, 0x01, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x70, 0x08, 0x01, 0x02
        ])
        subPayload.append(contentsOf: propertyAddress.prefix(4))
        payload.append(subPDU(payload: subPayload))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x01,
                framingTargetCID: nil,
                payload: payload
            )
        )
    }

    static func pairedPropertyRequestFrame(
        senderCID: UUID,
        localSessionSelector: UInt16,
        currentSelector: UInt16,
        previousSelector: UInt16,
        oldestSelector: UInt16,
        subtype: UInt8,
        firstPropertyAddress: [UInt8],
        secondPropertyAddress: [UInt8]
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(currentSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(previousSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(oldestSelector))
        payload.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0x00, 0x00])

        var subPayload = Data([
            0x00, 0x01, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x70, 0x08, subtype, 0x02
        ])
        subPayload.append(contentsOf: firstPropertyAddress.prefix(4))
        subPayload.append(contentsOf: [0x10, 0x06])
        subPayload.append(contentsOf: secondPropertyAddress.prefix(4))
        payload.append(subPDU(payload: subPayload))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x01,
                framingTargetCID: nil,
                payload: payload
            )
        )
    }

    /// Builds the WWB-shaped property-poll request that triggers the device's
    /// 79-byte meter bursts. Mirrors the 133-byte packet observed in
    /// WWB_ADTQ.pcapng: framing 0x01 (no target CID), `00 01` outer vector,
    /// 4-byte inner records using flags 0x7 for the first PDU and inheriting
    /// flags 0x1 for the rest.
    static func propertyAddressListFrame(
        senderCID: UUID,
        localSessionSelector: UInt16,
        currentSelector: UInt16,
        previousSelector: UInt16,
        oldestSelector: UInt16,
        innerVector: [UInt8] = [0x07, 0x02],
        propertyAddresses: [[UInt8]] = defaultPropertyAddresses
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(currentSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(previousSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(oldestSelector))
        payload.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0x00, 0x00])

        var subPayload = Data()
        subPayload.append(contentsOf: [0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00])

        var firstRecord = true
        for address in propertyAddresses where address.count == 4 {
            if firstRecord {
                var firstBody = Data()
                firstBody.append(contentsOf: innerVector)
                firstBody.append(contentsOf: address)
                let length = firstBody.count + 2
                let flagsLen = UInt16(0x7000 | max(0, min(length, 0x0FFF)))
                subPayload.append(contentsOf: [UInt8((flagsLen >> 8) & 0xFF), UInt8(flagsLen & 0xFF)])
                subPayload.append(firstBody)
                firstRecord = false
            } else {
                let length = address.count + 2
                let flagsLen = UInt16(0x1000 | max(0, min(length, 0x0FFF)))
                subPayload.append(contentsOf: [UInt8((flagsLen >> 8) & 0xFF), UInt8(flagsLen & 0xFF)])
                subPayload.append(contentsOf: address)
            }
        }

        payload.append(subPDU(payload: subPayload))
        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x01,
                framingTargetCID: nil,
                payload: payload
            )
        )
    }

    /// Default address list captured from a working WWB session against an
    /// ANX4 + ADTQ pair. Matches the first WWB property-poll that triggered
    /// the 79-byte meter burst response.
    static let defaultPropertyAddresses: [[UInt8]] = [
        [0x01, 0x00, 0x00, 0x12],
        [0x01, 0x00, 0x00, 0x23],
        [0x01, 0x00, 0x00, 0x24],
        [0x01, 0x00, 0x00, 0x25],
        [0x01, 0x00, 0x00, 0x26],
        [0x01, 0x00, 0x00, 0x28],
        [0x01, 0x00, 0x00, 0x2B],
        [0x01, 0x01, 0x01, 0x01],
        [0x01, 0x01, 0x01, 0x02],
        [0x01, 0x01, 0x01, 0x03]
    ]

    /// WWB uses a different property-address list for ULXD fast telemetry than
    /// the ANX4/ADTQ list above. Mirroring these addresses is what triggers the
    /// larger burst responses that carry the ULXD RF meter records.
    static let ulxdFastTelemetryPropertyAddresses: [[UInt8]] = [
        [0x01, 0x00, 0x00, 0x12],
        [0x01, 0x00, 0x00, 0xC0],
        [0x01, 0x00, 0x00, 0x23],
        [0x01, 0x00, 0x00, 0x2B],
        [0x01, 0x06, 0x00, 0x04],
        [0x01, 0x06, 0x00, 0x32],
        [0x01, 0x06, 0x00, 0x80],
        [0x01, 0x01, 0x01, 0x01],
        [0x01, 0x01, 0x01, 0x02],
        [0x01, 0x01, 0x01, 0x03]
    ]

    static let ulxdFastBurstActivationAddress: [UInt8] = [0x01, 0x20, 0x00, 0x23]

    static func opaqueRequestFrame(
        senderCID: UUID,
        localSessionSelector: UInt16,
        currentSelector: UInt16,
        previousSelector: UInt16,
        oldestSelector: UInt16,
        subVectorLength: UInt16,
        body: Data
    ) -> Data {
        var payload = Data()
        payload.append(contentsOf: selectorBytes(localSessionSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(currentSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(previousSelector))
        payload.append(contentsOf: [0x00, 0x00])
        payload.append(contentsOf: selectorBytes(oldestSelector))
        payload.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0x00, 0x00])

        var subPayload = Data([
            0x00, 0x01,
            0x00, 0x00,
            0x01, 0x02,
            0x00, 0x00,
            0x01, 0x01
        ])
        subPayload.append(contentsOf: selectorBytes(UInt16(body.count)))
        subPayload.append(body)

        let length = subPayload.count + 2
        let flagsLen = UInt16(0x7000 | max(0, min(length, Int(subVectorLength))))
        payload.append(contentsOf: [UInt8((flagsLen >> 8) & 0xFF), UInt8(flagsLen & 0xFF)])
        payload.append(subPayload)

        return ShureSessionFramer.frame(
            packet: ShureSessionPacket(
                rootVector: 0x00000001,
                senderCID: senderCID,
                framingVector: 0x01,
                framingTargetCID: nil,
                payload: payload
            )
        )
    }

    private static func cid(prefix: [UInt8]) -> UUID {
        let bytes = prefix + cidSuffix
        var buffer: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &buffer) { raw in
            raw.copyBytes(from: bytes)
        }
        return UUID(uuid: buffer)
    }

    private static func selectorBytes(_ selector: UInt16) -> [UInt8] {
        [UInt8((selector >> 8) & 0xFF), UInt8(selector & 0xFF)]
    }

    private static func subPDU(payload: Data) -> Data {
        let length = payload.count + 2
        let flagsLen = UInt16(0x7000 | max(0, min(length, 0x0FFF)))
        var data = Data()
        data.append(contentsOf: [UInt8((flagsLen >> 8) & 0xFF), UInt8(flagsLen & 0xFF)])
        data.append(payload)
        return data
    }
}

// MARK: - Service

@MainActor
final class ShureWirelessService: ObservableObject {
    private enum DebugTelemetryProtocol: String {
        case tcp2202 = "TCP 2202"
        case udp = "UDP"
    }

    private final class CallbackGate: @unchecked Sendable {
        private let lock = NSLock()
        private var active = true

        func deactivate() {
            lock.lock()
            active = false
            lock.unlock()
        }

        func isActive() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return active
        }
    }

    private enum Anx4WWBPhase: String {
        case inactive = "inactive"
        case request2A = "0x2a"
        case request5A = "0x5a"
        case request60 = "0x60"
        case replayCapture = "capture_replay"
        case steady60 = "steady_0x60"
    }

    private struct Anx4OpaqueReplayStage {
        let label: String
        let subVectorLength: UInt16
        let body: [UInt8]
    }

    /// Master verbose-logging gate, resolved against `WirelessLoggingPreferences`.
    /// Returns false in release builds; in beta/debug builds reflects the
    /// dashboard "Wireless Diagnostics Logging" master toggle. Family-specific
    /// gating for hot-path traces is performed via `isVerboseLogging(for:)`.
    nonisolated static var isVerboseLogging: Bool {
        WirelessLoggingPreferences.shureMasterVerbose
    }

    /// Per-device verbose-logging gate. Use this at hot-path call sites
    /// (per-packet `recordShureTrace`) so non-debug device families don't
    /// pay the main-actor cost in beta builds.
    nonisolated static func isVerboseLogging(for device: ExternalDeviceConfig?) -> Bool {
        WirelessLoggingPreferences.isVerboseShure(forModel: device?.shureModelIdentifier)
    }

    nonisolated static func shouldEmitConsoleLogs(for device: ExternalDeviceConfig?) -> Bool {
        isVerboseLogging(for: device)
    }
    /// Enable mic receiver logs without flooding PSM output.
    static let isVerboseMicLogging = true
    /// Enable PSM logs independently of mic logs.
    static let isVerbosePsmLogging = false

    /// Shared per-endpoint service cache so multiple tiles talking to the
    /// same physical Shure device reuse a single connection.
    private static var sharedServices: [String: ShureWirelessService] = [:]
    private static let nilDeviceKey = "nil-device"

    /// Factory that returns a shared service instance for a given device.
    static func shared(for deviceID: UUID?) -> ShureWirelessService {
        let key = sharedServiceKey(for: deviceID)
        if let existing = sharedServices[key] {
            return existing
        }
        if let deviceID {
            if let existingByDeviceID = sharedServices.values.first(where: { $0.deviceID == deviceID }) {
                sharedServices[key] = existingByDeviceID
                return existingByDeviceID
            }
            if let config = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceID && $0.kind == .shureWireless }) {
                let identity = endpointIdentity(for: config)
                if let existingByEndpoint = sharedServices.values.first(where: { service in
                    guard let boundDevice = service.device else { return false }
                    return endpointIdentity(for: boundDevice) == identity
                }) {
                    sharedServices[key] = existingByEndpoint
                    return existingByEndpoint
                }
            }
        }
        let service = ShureWirelessService(deviceID: deviceID)
        sharedServices[key] = service
        return service
    }

    private static func sharedServiceKey(for deviceID: UUID?) -> String {
        guard
            let deviceID,
            let config = ExternalDevicesStore.shared.devices.first(where: { $0.id == deviceID && $0.kind == .shureWireless })
        else {
            return nilDeviceKey
        }
        return endpointIdentity(for: config)
    }

    private static func endpointIdentity(for device: ExternalDeviceConfig) -> String {
        let host = device.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isUdpOnlyShureDevice(device) {
            let udpHost = device.shureSdtHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let udpPort = device.shureSdtPort ?? 57383
            return "shure-udp:\(udpHost?.isEmpty == false ? udpHost! : host):\(udpPort)"
        }
        return "shure-tcp:\(host):\(device.port)"
    }

    private static func isUdpOnlyShureDevice(_ device: ExternalDeviceConfig) -> Bool {
        switch device.shureNetworkModel {
        case .anx4, .adtd, .adtq:
            // TCP is now the default for these models -- both "Auto" and
            // "TCP Only" mean TCP. Confirmed against a real customer field
            // log: an ANX4 with UDP active (the reverse-engineered,
            // undocumented fallback protocol) established a session and
            // polled continuously but never once decoded a single meter
            // value across four separate real sessions -- silently
            // connected with zero telemetry. TCP command strings are
            // documented, validated against Shure's own ANX4/Axient
            // Digital references, and already carry full RF/audio/battery
            // data for this same device family (see
            // project_shure_telemetry_accuracy_fixes memory). UDP is now
            // an explicit opt-in ("UDP Preferred") for receivers that
            // genuinely don't have TCP command strings enabled, not the
            // default.
            return (device.shureTransportMode ?? .auto) == .udpPreferred
        default:
            return false
        }
    }

    private static func isLicensedShureDeviceModel(_ device: ExternalDeviceConfig) -> Bool {
        switch device.shureNetworkModel {
        case .anx4, .adtd, .adtq:
            return true
        default:
            return false
        }
    }

    fileprivate static func isFastUdpTelemetryCapableDevice(_ device: ExternalDeviceConfig) -> Bool {
        switch device.shureNetworkModel {
        case .ad4, .ad4d, .ad4q, .ulxd4q, .ulxd4d:
            return true
        default:
            return false
        }
    }

    /// AD4/AD4D/AD4Q have full TCP command-string support -- unlike
    /// ANX4/ADTD/ADTQ, which genuinely needed UDP before Shure added TCP
    /// command strings to their firmware, TCP alone already provides
    /// everything Relay displays for these three models (confirmed across
    /// this whole RF investigation). Their fast-UDP-telemetry sidecar is a
    /// reverse-engineered, undocumented binary protocol (reconstructed from
    /// packet captures, not from any Shure reference) that was never proven
    /// necessary and had real gaps surface in it (unvalidated bar
    /// thresholds, a whole packet subtype that never fires in practice).
    /// Disabled here rather than deleted: `handleAnx4Packet`, `udpRfBars`,
    /// and the rest of the decode path are left fully in place in case
    /// they're ever needed again, but these three models now never open
    /// the UDP connection that would feed them, so none of that code can
    /// influence what's actually displayed. ULX-D4Q/D4D and the
    /// ANX4/ADTD/ADTQ family are untouched -- this is scoped to exactly the
    /// models where UDP was optional icing on an already-complete TCP path.
    private static func isFastUdpTelemetryDisabledByDefault(_ device: ExternalDeviceConfig) -> Bool {
        switch device.shureNetworkModel {
        case .ad4, .ad4d, .ad4q:
            return true
        default:
            return false
        }
    }

    private func effectiveShureTransportMode(for device: ExternalDeviceConfig) -> ShureTransportMode {
        device.shureTransportMode ?? .auto
    }

    private func transportModeLogLabel(for device: ExternalDeviceConfig) -> String {
        effectiveShureTransportMode(for: device).rawValue
    }

    private func udpRfBars(fromRawByte rawByte: Int) -> Int {
        switch rawByte {
        case ..<24:
            return 0
        case ..<72:
            return 1
        case ..<128:
            return 2
        case ..<176:
            return 3
        case ..<224:
            return 4
        default:
            return 5
        }
    }

    // MARK: - Shared channel-name cache (for settings dropdown)

    /// Cache of channel names discovered from any Shure device, keyed by deviceID then channelIndex.
    /// This is intentionally lightweight and in-memory only.
    private static var channelNameCache: [UUID: [Int: String]] = [:]

    /// Throttle automatic name refresh so opening settings doesn't spam the network.
    private static var lastChannelNameRefreshAt: Date? = nil

    static func cachedChannelName(deviceID: UUID, channelIndex: Int) -> String? {
        channelNameCache[deviceID]?[channelIndex]
    }

    @MainActor
    private static func cacheChannelName(deviceID: UUID, channelIndex: Int, name: String) {
        var perDevice = channelNameCache[deviceID] ?? [:]
        perDevice[channelIndex] = name
        channelNameCache[deviceID] = perDevice
        ExternalDevicesStore.shared.updateShureChannelName(
            deviceID: deviceID,
            channelIndex: channelIndex,
            name: name
        )
    }

    /// One-shot refresh of CHAN_NAME across all configured Shure devices.
    /// This is used to improve the settings dropdown experience (show names before selection).
    /// It is throttled and uses short-lived TCP connections.
    static func refreshChannelNamesIfNeeded(throttleSeconds: TimeInterval = 45) {
        let now = Date()
        if let last = lastChannelNameRefreshAt, now.timeIntervalSince(last) < throttleSeconds {
            return
        }
        lastChannelNameRefreshAt = now

        let devices = ExternalDevicesStore.shared.devices.filter { $0.kind == .shureWireless }
        guard !devices.isEmpty else { return }

        // Perform the refresh on a background task.
        Task.detached(priority: .utility) {
            for device in devices {
                await Self.fetchChannelNames(for: device)
            }
        }
    }

    /// Refresh CHAN_NAME for a single Shure device (unthrottled).
    static func refreshChannelNames(for device: ExternalDeviceConfig) {
        Task.detached(priority: .utility) {
            await fetchChannelNames(for: device)
        }
    }

    /// Refresh the auto-detected licensed channel count for a single Shure
    /// device (unthrottled). No-op unless the device is a licensed model
    /// (ANX4/ADTD/ADTQ) reachable over TCP command strings.
    static func refreshLicensedChannelCount(for device: ExternalDeviceConfig) {
        Task.detached(priority: .utility) {
            _ = await runWithTimeout(seconds: 6.0) {
                await fetchLicensedChannelCount(for: device)
            }
        }
    }

    /// Refresh Device ID name for a single Shure device (unthrottled).
    static func refreshDeviceIDName(for device: ExternalDeviceConfig) {
        Task.detached(priority: .utility) {
            await fetchDeviceIDName(for: device)
        }
    }

    /// Refresh Device ID name with explicit timeout and P10T override.
    static func refreshDeviceIDName(
        for device: ExternalDeviceConfig,
        allowP10T: Bool,
        timeoutSeconds: TimeInterval,
        forceRefresh: Bool = false
    ) {
        Task.detached(priority: .utility) {
            _ = await runWithTimeout(seconds: timeoutSeconds) {
                await fetchDeviceIDName(for: device, allowP10T: allowP10T, forceRefresh: forceRefresh)
            }
        }
    }

    /// Refresh Device ID name synchronously (awaits completion).
    static func refreshDeviceIDNameSync(for device: ExternalDeviceConfig, allowP10T: Bool, forceRefresh: Bool = false) async {
        await fetchDeviceIDName(for: device, allowP10T: allowP10T, forceRefresh: forceRefresh)
    }

    static func refreshDeviceIDNameSync(
        for device: ExternalDeviceConfig,
        allowP10T: Bool,
        forceRefresh: Bool,
        timeoutSeconds: TimeInterval
    ) async -> Bool {
        await runWithTimeout(seconds: timeoutSeconds) {
            await fetchDeviceIDName(for: device, allowP10T: allowP10T, forceRefresh: forceRefresh)
        }
    }

    static func refreshChannelNamesSync(for device: ExternalDeviceConfig, timeoutSeconds: TimeInterval) async -> Bool {
        await runWithTimeout(seconds: timeoutSeconds) {
            await fetchChannelNames(for: device)
        }
    }

    /// Sequential refresh used after scan to avoid hammering finicky devices.
    static func refreshShureAfterScan(for device: ExternalDeviceConfig) async -> (Bool, Bool) {
        let modelCode = device.shureModelIdentifier?.uppercased() ?? ""
        let upperName = device.name.uppercased()
        let isP10T = modelCode.contains("P10T") || upperName.contains("P10T")

#if DEBUG
        let refreshStart = Date()
        print("[ShureWirelessService] Refresh after scan start device=\(device.name) host=\(device.host):\(device.port)")
#endif

        // P10T: run session bootstrap + device ID probe.
        if isP10T {
#if DEBUG
            print("[ShureWirelessService] P10T refresh start device=\(device.name) host=\(device.host):\(device.port)")
#endif
            let idOK = await runWithTimeout(seconds: 12.0) {
                await fetchDeviceIDName(for: device, allowP10T: true)
            }
#if DEBUG
            if idOK {
                print("[ShureWirelessService] P10T device ID probe done device=\(device.name) host=\(device.host):\(device.port)")
            } else {
                print("[ShureWirelessService] P10T device ID probe timed out device=\(device.name) host=\(device.host):\(device.port)")
            }
#endif
            let channelOK = await runWithTimeout(seconds: 5.0) {
                await fetchChannelNames(for: device)
            }
#if DEBUG
            if !channelOK {
                print("[ShureWirelessService] Channel name refresh timed out device=\(device.name) host=\(device.host):\(device.port)")
            }
            let elapsed = Int(Date().timeIntervalSince(refreshStart) * 1000)
            print("[ShureWirelessService] Refresh after scan done (P10T) device=\(device.name) ms=\(elapsed)")
#endif
            return (idOK, channelOK)
        }

        let idOK = await runWithTimeout(seconds: 6.0) {
            await fetchDeviceIDName(for: device)
        }
#if DEBUG
        if !idOK {
            print("[ShureWirelessService] Device ID probe timed out device=\(device.name) host=\(device.host):\(device.port)")
        }
#endif

        let channelOK = false
        Task.detached(priority: .utility) {
            #if DEBUG
            print("[ShureWirelessService] Channel name refresh scheduled device=\(device.name) host=\(device.host):\(device.port)")
            #endif
            await fetchChannelNames(for: device)
            #if DEBUG
            print("[ShureWirelessService] Channel name refresh background done device=\(device.name) host=\(device.host):\(device.port)")
            #endif
        }
        Task.detached(priority: .utility) {
            await runWithTimeout(seconds: 6.0) {
                await fetchLicensedChannelCount(for: device)
            }
        }

#if DEBUG
        let elapsed = Int(Date().timeIntervalSince(refreshStart) * 1000)
        print("[ShureWirelessService] Refresh after scan done device=\(device.name) ms=\(elapsed)")
#endif
        return (idOK, channelOK)
    }

    /// Connect briefly to a Shure device and request CHAN_NAME for all channels.
    /// Stores results in the shared cache.
    private static func fetchChannelNames(for device: ExternalDeviceConfig) async {
        if isUdpOnlyShureDevice(device) {
#if DEBUG
            print("[ShureWirelessService] Channel name refresh skipped for UDP-only device \(device.name) host=\(device.host)")
#endif
            return
        }

        // Respect the PSM900 offline placeholder behavior.
        let modelCode = device.shureModelIdentifier?.uppercased()
        let upperName = device.name.uppercased()
        let isPSM900 = (modelCode == "PSM900") || upperName.contains("PSM 900") || upperName.contains("PSM900")
        let isP10T = (modelCode?.contains("P10T") ?? false) || upperName.contains("P10T")
        let isIemDevice = (modelCode?.contains("ADTD") ?? false)
            || (modelCode?.contains("ADTQ") ?? false)
            || upperName.contains("ADTD")
            || upperName.contains("ADTQ")
        if isPSM900 { return }

#if DEBUG
        let start = Date()
        print("[ShureWirelessService] Channel name refresh start device=\(device.name) host=\(device.host):\(device.port)")
        if isP10T {
            print("[ShureWirelessService] P10T TCP CHAN_NAME start host=\(device.host):\(device.port)")
        }
#endif

        guard let port = NWEndpoint.Port(rawValue: device.port) else { return }

        let host = NWEndpoint.Host(device.host)
        let params = NWParameters.tcp
        let conn = NWConnection(host: host, port: port, using: params)

        let queue = DispatchQueue(label: "ShureWirelessService.nameRefresh.\(device.id)")

        // Small helper to send a raw Shure frame.
        func send(_ body: String) {
            var trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("<") {
                trimmed = "< \(trimmed) >"
            }
            let payload = trimmed + "\r\n"
            conn.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
        }

        // Infer channel count using the same heuristic as the live service.
        let channelCount = device.effectiveShureChannelCount

        // Await connection ready/failure.
        let ready = await awaitReady(conn, queue: queue, timeout: 3.0)

        guard ready else {
#if DEBUG
            print("[ShureWirelessService] Channel name refresh ready timeout device=\(device.name) host=\(device.host):\(device.port)")
            if isP10T {
                print("[ShureWirelessService] P10T TCP CHAN_NAME ready timeout host=\(device.host):\(device.port)")
            }
#endif
            conn.cancel()
            return
        }

        if Task.isCancelled {
#if DEBUG
            print("[ShureWirelessService] Channel name refresh cancelled device=\(device.name) host=\(device.host):\(device.port)")
#endif
            conn.cancel()
            return
        }

        // Request just CHAN_NAME for each channel.
        if isP10T {
            let p10tCommands = [
                "GET DEVICE_NAME",
                "GET 1 CHAN_NAME",
                "GET 1 AUDIO_IN_LVL",
                "GET 1 GROUP_CHAN",
                "GET 1 FREQUENCY",
                "GET 1 RF_TX_LVL",
                "GET 1 RF_MUTE",
                "GET 1 AUDIO_TX_MODE",
                "GET 1 AUDIO_IN_LINE_LVL",
                "GET 2 CHAN_NAME",
                "GET 2 AUDIO_IN_LVL",
                "GET 2 GROUP_CHAN",
                "GET 2 FREQUENCY",
                "GET 2 RF_TX_LVL",
                "GET 2 RF_MUTE",
                "GET 2 AUDIO_TX_MODE",
                "GET 2 AUDIO_IN_LINE_LVL"
            ]
            let payload = p10tCommands.map { "< \($0) >\r\n" }.joined()
            conn.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
#if DEBUG
            for command in p10tCommands {
                print("[ShureWirelessService] P10T TCP send \(command)")
            }
#endif
        } else {
            for ch in 1...channelCount {
                if Task.isCancelled { break }
                if isIemDevice {
                    send("GET \(ch) IEM_NAME")
                }
                send("GET \(ch) CHAN_NAME")
            }
        }

        // Receive for a short window, parsing any CHAN_NAME frames.
        // We keep this short to avoid any sluggishness.
        let deadlineSeconds: TimeInterval = isP10T ? 5.0 : 0.7
        let deadline = Date().addingTimeInterval(deadlineSeconds)
        var buffer = ""
        var updates = 0
        var p10tDebugFramesLogged = 0

        while Date() < deadline {
            if Task.isCancelled { break }
            let chunk: String? = await receiveTcpMessage(conn, timeout: 0.2)

            guard let chunk else { continue }
            if isP10T, p10tDebugFramesLogged < 6 {
#if DEBUG
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    print("[ShureWirelessService] P10T TCP CHAN_NAME recv chunk=\"\(trimmed)\"")
                }
#endif
                p10tDebugFramesLogged += 1
            }
            buffer.append(chunk)

            // Parse frames in the same style as handleIncoming: extract text inside < >.
            var frames: [String] = []
            var current = ""
            var inside = false
            for c in buffer {
                if c == "<" {
                    inside = true
                    current = ""
                } else if c == ">" {
                    if inside {
                        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { frames.append(trimmed) }
                    }
                    inside = false
                    current = ""
                } else if inside {
                    current.append(c)
                }
            }

            // Keep only the tail to avoid buffer growth.
            if buffer.count > 4096 {
                buffer = String(buffer.suffix(2048))
            }

            for line in frames {
                let parts = line.split(separator: " ")
                guard parts.count >= 3 else { continue }
                let verb = parts[0].uppercased()
                guard verb == "REP" || verb == "REPORT" else { continue }

                let channelKeys: Set<String> = ["CHAN_NAME", "CH_NAME", "NAME", "TX_NAME", "IEM_NAME"]
                guard let keyIndex = parts.firstIndex(where: { channelKeys.contains($0.uppercased()) }) else { continue }
                if !isP10T {
                    let key = parts[keyIndex].uppercased()
                    if key != "CHAN_NAME", !(isIemDevice && key == "IEM_NAME") { continue }
                }

                let channelIndex: Int? = {
                    if parts.count >= 2, let idx = Int(parts[1]) { return idx }
                    let searchRange = parts.startIndex..<keyIndex
                    if let token = parts[searchRange].first(where: { Int($0) != nil }) {
                        return Int(token)
                    }
                    return nil
                }()
                guard let chIndex = channelIndex else { continue }

                let nameValue: String? = {
                    if let openIdx = line.firstIndex(of: "{"), let closeIdx = line.lastIndex(of: "}") {
                        let nameRange = line.index(after: openIdx)..<closeIdx
                        return String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                    }
                    let valueTokens = parts[(keyIndex + 1)..<parts.endIndex]
                    guard !valueTokens.isEmpty else { return nil }
                    return valueTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                }()

                if let cleaned = nameValue, !cleaned.isEmpty {
                    await MainActor.run {
                        Self.cacheChannelName(deviceID: device.id, channelIndex: chIndex, name: cleaned)
                    }
                    updates += 1
                }
            }
        }

#if DEBUG
        if Task.isCancelled {
            print("[ShureWirelessService] Channel name refresh cancelled (loop) device=\(device.name) host=\(device.host):\(device.port)")
        }
#endif
        conn.cancel()

#if DEBUG
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        print("[ShureWirelessService] Channel name refresh done device=\(device.name) ms=\(elapsed) updates=\(updates)")
        if isP10T {
            print("[ShureWirelessService] P10T TCP CHAN_NAME done host=\(device.host):\(device.port) updates=\(updates)")
        }
#endif
    }

    /// Connect briefly to a Shure device and request Device ID name.
    /// This starts with AD4Q only (per request).
    private static func fetchDeviceIDName(for device: ExternalDeviceConfig, allowP10T: Bool = false, forceRefresh: Bool = false) async {
        if isUdpOnlyShureDevice(device) {
#if DEBUG
            print("[ShureWirelessService] Device ID probe skipped for UDP-only device \(device.name) host=\(device.host)")
#endif
            return
        }

        let modelCode = device.shureModelIdentifier?.uppercased() ?? ""
        let upperName = device.name.uppercased()
        let isP10T = modelCode.contains("P10T") || upperName.contains("P10T")

        if isP10T && !allowP10T {
#if DEBUG
            print("[ShureWirelessService] Device ID probe skipped for P10T device=\(device.name) host=\(device.host):\(device.port)")
#endif
            return
        }

        if isP10T,
           !forceRefresh,
           let existing = device.shureDeviceIDName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
#if DEBUG
            print("[ShureWirelessService] Device ID probe skipped (already set) device=\(device.name) host=\(device.host):\(device.port)")
#endif
            return
        }

#if DEBUG
        let start = Date()
        print("[ShureWirelessService] Device ID probe start device=\(device.name) host=\(device.host):\(device.port)")
        if isP10T {
            print("[ShureWirelessService] P10T TCP DEVICE_NAME probe start host=\(device.host):\(device.port)")
        }
#endif

        guard let port = NWEndpoint.Port(rawValue: device.port) else { return }

        let channelCount = device.effectiveShureChannelCount
        var probeCommands = [
            "GET 0 DEVICE_ID",
            "GET 0 DEVICE_NAME",
            "GET 0 DEV_ID",
            "GET 0 DEV_NAME",
            "GET DEVICE_ID",
            "GET DEVICE_NAME",
            "GET DEV_ID",
            "GET DEV_NAME"
        ]
        if channelCount > 0 {
            for ch in 1...channelCount {
                probeCommands.append("GET \(ch) DEVICE_NAME")
                probeCommands.append("GET \(ch) DEVICE_ID")
                probeCommands.append("GET \(ch) DEV_NAME")
                probeCommands.append("GET \(ch) DEV_ID")
            }
        }

        if isP10T {
            // PSM1000: try both global and per-channel name queries.
            probeCommands = [
                "GET DEVICE_NAME",
                "GET 1 DEVICE_NAME",
                "GET 2 DEVICE_NAME",
                "GET 0 DEVICE_NAME",
                "GET 1 NAME",
                "GET 2 NAME",
                "GET NAME"
            ]
#if DEBUG
            print("[ShureWirelessService] P10T TCP DEVICE_NAME commands=\(probeCommands)")
#endif
        }
        let keys = [
            "DEVICE_ID",
            "DEVICE_NAME",
            "DEV_ID",
            "DEV_NAME",
            "DEVICEID",
            "DEVICENAME",
            "DEVNAME"
        ]

        func extractDeviceID(from line: String) -> String? {
            let upper = line.uppercased()
            guard keys.contains(where: { upper.contains($0) }) else { return nil }

            if let openIdx = line.firstIndex(of: "{"),
               let closeIdx = line.lastIndex(of: "}") {
                let nameRange = line.index(after: openIdx)..<closeIdx
                let raw = String(line[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            }

            let parts = line.split(separator: " ")
            for (idx, part) in parts.enumerated() {
                let token = part.uppercased()
                if keys.contains(String(token)) {
                    let valueIndex = idx + 1
                    if valueIndex < parts.count {
                        let raw = String(parts[valueIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                        return raw.isEmpty ? nil : raw
                    }
                }
            }

            return nil
        }

        let host = NWEndpoint.Host(device.host)
        let maxAttempts = isP10T ? 1 : 3
        let readDeadlineSeconds: TimeInterval = isP10T ? 4.0 : 3.0
        let interCommandDelayNanos: UInt64 = isP10T ? 40_000_000 : 0
        let attemptPauseNanos: UInt64 = isP10T ? 300_000_000 : 300_000_000
        var discovered: String? = nil

        for attempt in 1...maxAttempts {
            if Task.isCancelled {
#if DEBUG
                print("[ShureWirelessService] Device ID probe cancelled device=\(device.name) host=\(device.host):\(device.port)")
#endif
                break
            }
            let conn = NWConnection(host: host, port: port, using: .tcp)
            let queue = DispatchQueue(label: "ShureWirelessService.deviceID.\(device.id).\(attempt)")

            func send(_ body: String) {
                var trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.hasPrefix("<") {
                    trimmed = "< \(trimmed) >"
                }
                let payload = trimmed + "\r\n"
                conn.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
            }

            let ready = await awaitReady(conn, queue: queue, timeout: 3.0)

            guard ready else {
#if DEBUG
                print("[ShureWirelessService] Device ID probe ready timeout device=\(device.name) host=\(device.host):\(device.port)")
                if isP10T {
                    print("[ShureWirelessService] P10T TCP DEVICE_NAME ready timeout host=\(device.host):\(device.port)")
                }
#endif
                conn.cancel()
                continue
            }

            #if DEBUG
            print("[ShureWirelessService] Device ID probe start attempt=\(attempt) device=\(device.name) host=\(device.host):\(device.port)")
            #endif

            for cmd in probeCommands {
                if Task.isCancelled { break }
                send(cmd)
#if DEBUG
                if isP10T {
                    print("[ShureWirelessService] P10T TCP send \(cmd)")
                }
#endif
                if interCommandDelayNanos > 0 {
                    try? await Task.sleep(nanoseconds: interCommandDelayNanos)
                }
            }

            let deadline = Date().addingTimeInterval(readDeadlineSeconds)
            var buffer = ""

            while Date() < deadline && discovered == nil {
                if Task.isCancelled { break }
                let chunk: String? = await receiveTcpMessage(conn, timeout: 0.25)

                guard let chunk else { continue }
                buffer.append(chunk)

                var frames: [String] = []
                var current = ""
                var inside = false
                for c in buffer {
                    if c == "<" {
                        inside = true
                        current = ""
                    } else if c == ">" {
                        if inside {
                            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { frames.append(trimmed) }
                        }
                        inside = false
                        current = ""
                    } else if inside {
                        current.append(c)
                    }
                }

                if buffer.count > 4096 {
                    buffer = String(buffer.suffix(2048))
                }

                for line in frames {
                    if let candidate = extractDeviceID(from: line) {
                        discovered = candidate
                        #if DEBUG
                        print("[ShureWirelessService] Device ID probe found '\(candidate)' (line: \(line))")
                        if isP10T {
                            print("[ShureWirelessService] P10T TCP DEVICE_NAME parsed '\(candidate)'")
                        }
                        #endif
                        break
                    }
                }
            }

            conn.cancel()

            if discovered != nil {
                break
            }

            if attemptPauseNanos > 0 {
                try? await Task.sleep(nanoseconds: attemptPauseNanos)
            }
        }

        if let discovered {
            let model = device.shureModelIdentifier?.uppercased() ?? ""
            let discoveredUpper = discovered.uppercased()
            if model.contains("ULXD4") && discoveredUpper.contains("ULXD1") {
#if DEBUG
                print("[ShureWirelessService] Device ID probe ignoring bodypack name device=\(device.name) discovered=\(discovered)")
#endif
            } else {
                await MainActor.run {
                    ExternalDevicesStore.shared.updateShureDeviceIDName(deviceID: device.id, name: discovered)
                }
            }
        } else {
            #if DEBUG
            print("[ShureWirelessService] Device ID probe complete (no device id found) device=\(device.name)")
            if isP10T {
                print("[ShureWirelessService] P10T TCP DEVICE_NAME no response host=\(device.host):\(device.port)")
            }
            #endif
        }

#if DEBUG
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        print("[ShureWirelessService] Device ID probe done device=\(device.name) ms=\(elapsed)")
#endif
    }

    /// Probe a licensed Shure receiver (ANX4 / ADTD / ADTQ) for its actual
    /// licensed channel count over TPCI command strings, per Shure's
    /// published ANX4 Command Strings reference: NUMBER_CHANNELS_LICENSED
    /// is a device-level property (no channel index), reporting 00-24.
    /// Does nothing if the device doesn't answer — the model's fixed
    /// default (or a manual override) keeps being used in that case.
    private static func fetchLicensedChannelCount(for device: ExternalDeviceConfig) async {
        guard isLicensedShureDeviceModel(device) else { return }
        guard device.shureChannelCountOverride == nil else { return }
        guard !isUdpOnlyShureDevice(device) else { return }
        guard let port = NWEndpoint.Port(rawValue: device.port) else { return }

        let candidateKeys = ["NUMBER_CHANNELS_LICENSED"]
        let probeCommands = candidateKeys.map { "GET \($0)" }

        let host = NWEndpoint.Host(device.host)
        let conn = NWConnection(host: host, port: port, using: .tcp)
        let queue = DispatchQueue(label: "ShureWirelessService.channelCount.\(device.id)")

        func send(_ body: String) {
            var trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("<") {
                trimmed = "< \(trimmed) >"
            }
            let payload = trimmed + "\r\n"
            conn.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
        }

        guard await awaitReady(conn, queue: queue, timeout: 3.0) else {
            conn.cancel()
            return
        }

        for cmd in probeCommands {
            if Task.isCancelled { break }
            send(cmd)
        }

        let deadline = Date().addingTimeInterval(3.0)
        var buffer = ""
        var discovered: Int?

        while Date() < deadline, discovered == nil {
            if Task.isCancelled { break }
            guard let chunk = await receiveTcpMessage(conn, timeout: 0.25) else { continue }
            buffer.append(chunk)

            var frames: [String] = []
            var current = ""
            var inside = false
            for c in buffer {
                if c == "<" {
                    inside = true
                    current = ""
                } else if c == ">" {
                    if inside {
                        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { frames.append(trimmed) }
                    }
                    inside = false
                    current = ""
                } else if inside {
                    current.append(c)
                }
            }
            if buffer.count > 4096 {
                buffer = String(buffer.suffix(2048))
            }

            for line in frames {
                let upper = line.uppercased()
                guard let matchedKey = candidateKeys.first(where: { upper.contains($0) }) else { continue }
                let parts = line.split(separator: " ")
                guard let keyIndex = parts.firstIndex(where: { $0.uppercased() == matchedKey }) else { continue }
                let valueIndex = parts.index(after: keyIndex)
                guard valueIndex < parts.endIndex, let value = Int(parts[valueIndex]) else { continue }
                if value > 0, value <= 24 {
                    discovered = value
                    break
                }
            }
        }

        conn.cancel()

        if let discovered {
#if DEBUG
            print("[ShureWirelessService] Licensed channel count probe found \(discovered) device=\(device.name)")
#endif
            await MainActor.run {
                ExternalDevicesStore.shared.updateShureDetectedChannelCount(deviceID: device.id, count: discovered)
            }
        }
    }

    private static func runWithTimeout(seconds: TimeInterval, operation: @escaping @Sendable () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await operation()
                return true
            }
            group.addTask {
                let nanos = UInt64(max(0, seconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private static func awaitReady(_ conn: NWConnection, queue: DispatchQueue, timeout: TimeInterval) async -> Bool {
        let gate = ShureResumeGate<Bool>()
        return await withCheckedContinuation { continuation in
            Task { await gate.store(continuation) }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    Task { await gate.resume(with: true) }
                case .failed, .cancelled:
                    conn.stateUpdateHandler = nil
                    Task { await gate.resume(with: false) }
                default:
                    break
                }
            }
            conn.start(queue: queue)
            if timeout > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    Task { await gate.resume(with: false) }
                }
            }
        }
    }

    private static func receiveTcpMessage(_ conn: NWConnection, timeout: TimeInterval) async -> String? {
        let gate = ShureResumeGate<String?>()
        return await withCheckedContinuation { continuation in
            Task { await gate.store(continuation) }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    Task { await gate.resume(with: String(decoding: data, as: UTF8.self)) }
                } else if isComplete || error != nil {
                    Task { await gate.resume(with: nil) }
                } else {
                    Task { await gate.resume(with: nil) }
                }
            }
            if timeout > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    Task { await gate.resume(with: nil) }
                }
            }
        }
    }

// MARK: Granular published state (Option B)

    @Published var device: ExternalDeviceConfig?
    @Published var isConnected: Bool = false
    @Published var lastError: String? = nil
    @Published var lastHeardAt: Date? = nil
    @Published var isReconnecting: Bool = false

    /// Channel names reported by the current device, keyed by channel index.
    @Published var channelNames: [Int: String] = [:]
    /// Last known tuned frequency per channel, already formatted for display.
    @Published var channelFrequencies: [Int: String] = [:]
    /// RF TX level reported by the current device, keyed by channel index.
    @Published var rfTxLevels: [Int: Int] = [:]
    /// Last time we updated RF TX level per channel.
    @Published var rfTxLastUpdated: [Int: Date] = [:]
    /// For PSM devices (e.g. P10T), last reported audio input levels for L/R per channel.
    @Published var psmAudioLevels: [Int: (left: Double, right: Double)] = [:]
    /// For microphone receivers, last reported audio level per channel (mono).
    @Published var micAudioLevels: [Int: Double] = [:]
    /// Last time we updated mic audio level per channel.
    @Published var micAudioLastUpdated: [Int: Date] = [:]
    /// Last reported meter rate per channel (0 means disabled/idle on some devices).
    @Published var channelMeterRates: [Int: Int] = [:]
    /// Last time we saw a non-zero mic audio value per channel.
    private var micAudioLastNonZeroAt: [Int: Date] = [:]
    /// Last parsed human-readable battery label per channel (e.g. "85%", "1:20", "45m").
    @Published var channelBatteryLabels: [Int: String] = [:]
    /// Last known battery percentage per channel (0–100) when available.
    @Published var channelBatteryPercentages: [Int: Int] = [:]
    /// Whether the displayed battery percentage is approximated from bar-only data.
    @Published var channelBatteryIsApproximate: [Int: Bool] = [:]
    /// Priority of the current battery display source per channel.
    private var channelBatteryPriority: [Int: Int] = [:]
    /// Whether a channel has shown evidence of a smart Shure battery path.
    private var channelBatteryHasSmartTelemetry: [Int: Bool] = [:]
    /// Short-lived placeholder state while smart-battery runtime is still resolving.
    private var channelBatteryCalculationPendingAt: [Int: Date] = [:]
    /// Last time we updated battery data per channel.
    @Published var channelBatteryLastUpdated: [Int: Date] = [:]
    /// Last time a battery field explicitly cleared for a channel.
    /// Latched evidence that a microphone transmitter is currently on.
    @Published var channelPresenceLastSeenAt: [Int: Date] = [:]
    /// Strong positive Axient-only evidence such as transmitter identity or
    /// non-sentinel transmitter telemetry. This wins over brief false frames.
    @Published var channelAxientPositiveEvidenceLastSeenAt: [Int: Date] = [:]
    /// When the current unbroken run of negative Axient presence evidence
    /// began (cleared as soon as positive evidence returns). Lets sustained
    /// negative evidence override an in-progress positive hold in
    /// ShureAxientPresenceResolver without waiting for it to expire.
    @Published var channelAxientNegativeEvidenceStreakStartAt: [Int: Date] = [:]
    /// Family-specific explicit transmitter presence, when the receiver reports it.
    @Published var channelTransmitterPresent: [Int: Bool] = [:]
    /// Last time explicit transmitter presence was updated per channel.
    @Published var channelTransmitterPresentLastUpdated: [Int: Date] = [:]
    /// Last time receiver-reported transmitter presence was explicitly true.
    @Published var channelTransmitterPresentLastTrueAt: [Int: Date] = [:]
    /// Last time receiver-reported transmitter presence was explicitly false.
    @Published var channelTransmitterPresentLastFalseAt: [Int: Date] = [:]
    /// Explicit transmitter identity presence, based on TX_DEVICE_ID when available.
    @Published var channelTransmitterDeviceIDPresent: [Int: Bool] = [:]
    /// Last time TX_DEVICE_ID presence was updated per channel.
    @Published var channelTransmitterDeviceIDLastUpdated: [Int: Date] = [:]
    /// Last parsed RF strength as a 0–5 bar count per channel.
    @Published var channelRFBarCounts: [Int: Int] = [:]
    /// Last time we updated RF data per channel.
    @Published var channelRfLastUpdated: [Int: Date] = [:]
    /// Axient-only RF bar hold/hysteresis state, see `ShureAxientRfBarHoldResolver`.
    private var channelRfBarHoldState: [Int: ShureAxientRfBarHoldState] = [:]
    /// Latest raw RSSI_LED_BITMAP bar count per antenna, per channel --
    /// combined (max) before being fed into channelRfBarHoldState so the
    /// two antennas don't fight over shared hold state.
    private var channelAxientRfBarsByAntenna: [Int: [Int: Int]] = [:]
    /// Temporary: rate-limits a lightweight queue-depth trace added while
    /// chasing unbounded growth in the outgoing command queues.
    private var lastQueueDepthTraceAt: Date?
    /// Last known audio mute state per channel (true = muted).
    @Published var channelAudioMutes: [Int: Bool] = [:]
    /// Shadow cache populated by reading the raw standard-report actor state.
    @Published private var shadowStandardReportSnapshots: [Int: ShureStandardReportChannelSnapshot] = [:]
    /// Low-frequency subset of the actor-backed shadow cache.
    @Published private var shadowStandardReportLowFrequencySnapshots: [Int: ShureStandardReportLowFrequencySnapshot] = [:]
    @Published private(set) var debugTelemetryProtocolLabel: String = DebugTelemetryProtocol.tcp2202.rawValue
    @Published private(set) var telemetrySnapshot: ShureTelemetryDeviceSnapshot = .empty

    /// Raw recent report lines kept for debugging / fallback parsing.
    /// This is intentionally *not* @Published so that every incoming
    /// frame does not invalidate SwiftUI views.
    var recentReports: [String] = []

    private var connection: NWConnection?
    private var udpConnection: NWConnection?
    private var transportProbeConnection: NWConnection?
    private var isAutoTransportProbing = false
    private var reconnectAttempt: Int = 0
    private var reconnectTask: Task<Void, Never>?
    /// Watches a connection that has entered `.waiting` (Network.framework's
    /// non-terminal "can't connect right now, might work later" state) and
    /// force-cancels it if it's still waiting after `waitingEscalationSeconds`.
    /// `.waiting` is otherwise invisible to `scheduleReconnectIfNeeded` --
    /// only `.failed`/`.cancelled` trigger a retry -- so without this, a
    /// connection that lands in `.waiting` (e.g. right after the peer resets
    /// it, which can cause a receiver to briefly refuse the next SYN) sits
    /// forever with no logged trace and no retry. Cancelling routes it
    /// through the same `.cancelled` handler that already calls
    /// `scheduleReconnectIfNeeded` for a clean failure.
    private var waitingTimeoutTask: Task<Void, Never>?

    /// UDP-path counterpart to `waitingTimeoutTask` -- kept as a separate
    /// property (not shared) because TCP and UDP connections can be active
    /// concurrently (the fast-telemetry-sidecar case), and each needs to be
    /// able to watch its own `.waiting` connection independently. Sharing one
    /// property would let one transport's in-flight watchdog cause the other
    /// transport's `.waiting` case to skip starting its own.
    private var udpWaitingTimeoutTask: Task<Void, Never>?
    private var tcpReceiveGate = CallbackGate()
    private var tcpSendGate = CallbackGate()
    private let queue = DispatchQueue(label: "ShureWirelessService.connection")
    private let udpQueue = DispatchQueue(label: "ShureWirelessService.udp")

    /// Convenience: currently bound device ID (if we add per-tile selection later).
    private var deviceID: UUID?
    private var anx4SessionId: [UInt8] = []
    private var anx4LocalSessionSelector: UInt16 = 0xED16
    private var anx4RemoteSessionSelector: UInt16?
    private var anx4RemoteQuerySelector: UInt16?
    private var anx4RemoteDataSelector: UInt16?
    private var anx4ResponderCID: UUID?
    private var anx4HandshakedCIDs: Set<UUID> = []
    private var anx4HandshakeSent = false
    private var anx4FollowupsSent = false
    private var didLogAnx4Receive: Bool = false
    private var didLogAnx4MeterDecoded: Bool = false
    private var didLogAnx4RFDecoded: Bool = false
    private var didLogFastUdpFallbackNoDecode = false
    private var currentConnectionIdentity: String?
    private var lastLiveSyncPersistAt: Date?
    private var anx4NextSelector: UInt16 = 0xED17
    private var anx4PreviousSelector: UInt16 = 0xED16
    private var anx4OldestSelector: UInt16 = 0xED16
    private var anx4TelemetryLoopTask: Task<Void, Never>?
    private var anx4UseOpaqueRequestPhase = false
    private var anx4WWBPhase: Anx4WWBPhase = .inactive
    private var anx4OpaqueRequestPrefix = Data(repeating: 0, count: 8)
    private var anx4OpaqueRequestCounter: UInt64 = 0
    private var anx4Phase2ASendCount = 0
    private var anx4SawControlFrame0F = false
    private var anx4SawControlFrame08 = false
    private var anx4SawControlSubPDU0D = false
    private var anx4Template2AIndex = 0
    private var anx4Template5AIndex = 0
    private var anx4Template60Index = 0
    private var anx4CaptureReplayIndex = 0
    private var tcpStartupTask: Task<Void, Never>?
    /// Global per-connection send queues -- see sendRaw/drainOutgoingCommandQueueIfNeeded.
    /// Two tiers, not a single FIFO: a strict single queue made a watched
    /// channel's own presence-critical commands wait behind unrelated
    /// background polling for channels nobody's looking at, which was
    /// worse than the coalescing problem the queue was built to fix --
    /// confirmed on a live capture where a tile-watched channel's presence
    /// visibly flapped once its refresh started queueing behind other
    /// channels' traffic. `highPriorityCommandQueue` always drains first.
    private var highPriorityCommandQueue: [String] = []
    private var normalPriorityCommandQueue: [String] = []
    private var outgoingSendTask: Task<Void, Never>?
    private var fastUdpDecodeTimeoutTask: Task<Void, Never>?
    private var fastUdpRfLastUpdated: [Int: Date] = [:]
    private var fastUdpMicLastUpdated: [Int: Date] = [:]
    private var fastUdpRfAntenna12Levels: [Int: Int] = [:]
    private var fastUdpRfAntenna13Levels: [Int: Int] = [:]
    private var activeUdpEndpointHost: String?
    private var activeUdpEndpointPort: UInt16?
    private let standardReportStateStore = ShureStandardReportStateStore()

    /// Throttle SAMPLE commands so multiple views can request refreshes
    /// without flooding the network. We remember when we last sent a
    /// SAMPLE ALL for this service instance.
    /// Overview-only Axient fallback cadence. Each channel receives one
    /// RMS request per second, but requests are staggered to avoid a burst
    /// across a multi-channel receiver.
    private var lastAxientOverviewMeterPollAt: [Int: Date] = [:]
    /// Same idea as lastAxientOverviewMeterPollAt but for channels
    /// currently resolved "on" -- these get a much shorter minimum
    /// interval so their meters feel close to the single-tile module's own
    /// 100ms rate, since they're what a user is actually watching move.
    private var lastAxientOverviewFastMeterPollAt: [Int: Date] = [:]
    /// Per-channel backpressure for the stalePresenceChannels catch-up loop
    /// (Axient's sendAxientPresenceRefresh and ULX-D's sendUlxdPresenceRefresh
    /// both use it): without this, a channel stays in stalePresence until its
    /// reply actually lands, so the loop re-enqueues a fresh burst for it
    /// every tick (~0.25-0.4s) regardless of whether the last one has even
    /// drained yet.
    private var lastStalePresenceRefreshAt: [Int: Date] = [:]
    private var lastChannelSnapshotQueryAt: [Int: Date] = [:]
    private var liveModeEnabled: Bool = false
    private var micAudioStereoLevels: [Int: (left: Double, right: Double)] = [:]
    private var axientAudioBitmapAllowsLevel: [Int: Bool] = [:]
    /// Last known clip/overage state per channel, from AUDIO_LED_BITMAP bit
    /// 7 ("LED 8 - Red" per Shure's own Axient Digital reference). Persisted
    /// across ticks the same way axientAudioBitmapAllowsLevel is, since
    /// AUDIO_LEVEL_RMS/PEAK updates arrive on their own cadence without a
    /// fresh bitmap alongside every one.
    private var channelMicAudioOverload: [Int: Bool] = [:]
    private let diagnosticsMinInterval: TimeInterval = 60
    /// How long a connection is allowed to sit in `.waiting` before it's
    /// treated as failed and cancelled. Long enough that normal LAN
    /// path-probing/DNS doesn't trip it (`.preparing` -> `.ready` is
    /// sub-second on a healthy LAN), short enough that a live show doesn't
    /// sit on a stuck device for long.
    private static let waitingEscalationSeconds: TimeInterval = 5.0
    private var overviewConsumerIDs: Set<UUID> = []
    private var channelConsumerSelections: [UUID: Int] = [:]
    private var overviewPollingIntervalSeconds: TimeInterval = 0.3
    private var overviewMeterRateMilliseconds: Int = 100
    private var lastAppliedMeterRateMilliseconds: [Int: Int] = [:]
    private var sharedPollingTask: Task<Void, Never>?
    private var telemetryPublishTask: Task<Void, Never>?
    private var droppedCoalescedTelemetryUpdateCount: Int = 0
    private var lastTelemetrySnapshotPublishAt: Date?
    private var telemetrySnapshotPublishCount: Int = 0
    private var telemetryPublishWindowStartedAt = Date()
    private var parseDurationTotal: TimeInterval = 0
    private var parseDurationSamples: Int = 0
    private var snapshotBuildDurationTotal: TimeInterval = 0
    private var snapshotBuildSamples: Int = 0
    private var lastSlowRefreshAt: Date?
    private var lastFastTelemetryAt: Date?
    private var lastDiagnosticsTraceAt: Date?

    init(deviceID: UUID? = nil) {
        self.deviceID = deviceID
        refreshDevice()
    }

    /// Re-resolve the device from the ExternalDevicesStore (e.g. on init, or
    /// if the store changes and we want to follow edits).
    func refreshDevice() {
        let store = ExternalDevicesStore.shared

        // If a specific deviceID is provided, use that. Otherwise just grab
        // the first Shure wireless device in the store.
        if let id = deviceID,
           let config = store.devices.first(where: { $0.id == id && $0.kind == .shureWireless }) {
            device = config
        } else {
            device = store.devices.first(where: { $0.kind == .shureWireless })
        }
    }

    /// Bind this service to a specific Shure device and reconnect.
    func setDevice(id: UUID?) {
        let previousSharedKey = Self.sharedServiceKey(for: deviceID)
        let previousIdentity = device.map(Self.endpointIdentity(for:))
        deviceID = id
        refreshDevice()
        let newSharedKey = Self.sharedServiceKey(for: id)
        Self.sharedServices[newSharedKey] = self
        if previousSharedKey != newSharedKey, Self.sharedServices[previousSharedKey] === self {
            Self.sharedServices.removeValue(forKey: previousSharedKey)
        }
        let newIdentity = device.map(Self.endpointIdentity(for:))

        if previousIdentity == newIdentity, liveModeEnabled, (connection != nil || udpConnection != nil || isConnected) {
            return
        }

        // Reset transient state for the new device.
        recentReports.removeAll()
        lastHeardAt = nil
        lastError = nil
        resetReconnectState()
        anx4SessionId = []
        anx4RemoteSessionSelector = nil
        anx4RemoteQuerySelector = nil
        anx4RemoteDataSelector = nil
        anx4ResponderCID = nil
        anx4HandshakedCIDs.removeAll()
        anx4HandshakeSent = false
        anx4FollowupsSent = false
        didLogAnx4Receive = false
        didLogAnx4MeterDecoded = false
        didLogAnx4RFDecoded = false
        didLogFastUdpFallbackNoDecode = false
        fastUdpDecodeTimeoutTask?.cancel()
        fastUdpDecodeTimeoutTask = nil
        fastUdpRfLastUpdated.removeAll()
        fastUdpMicLastUpdated.removeAll()
        fastUdpRfAntenna12Levels.removeAll()
        fastUdpRfAntenna13Levels.removeAll()
        activeUdpEndpointHost = nil
        activeUdpEndpointPort = nil
        debugTelemetryProtocolLabel = DebugTelemetryProtocol.tcp2202.rawValue
        resetAnx4LocalSessionSelector()
        anx4UseOpaqueRequestPhase = false
        anx4WWBPhase = .inactive
        anx4Phase2ASendCount = 0
        anx4SawControlFrame0F = false
        anx4SawControlFrame08 = false
        anx4SawControlSubPDU0D = false
        anx4Template2AIndex = 0
        anx4Template5AIndex = 0
        anx4Template60Index = 0
        anx4CaptureReplayIndex = 0
        anx4TelemetryLoopTask?.cancel()
        anx4TelemetryLoopTask = nil
        lastLiveSyncPersistAt = nil
        channelNames.removeAll()
        channelFrequencies.removeAll()
        rfTxLevels.removeAll()
        rfTxLastUpdated.removeAll()
        psmAudioLevels.removeAll()
        micAudioLevels.removeAll()
        micAudioLastUpdated.removeAll()
        micAudioStereoLevels.removeAll()
        axientAudioBitmapAllowsLevel.removeAll()
        channelMicAudioOverload.removeAll()
        channelBatteryLabels.removeAll()
        channelBatteryPercentages.removeAll()
        channelBatteryIsApproximate.removeAll()
        channelBatteryPriority.removeAll()
        channelBatteryHasSmartTelemetry.removeAll()
        channelBatteryCalculationPendingAt.removeAll()
        channelBatteryLastUpdated.removeAll()
        channelPresenceLastSeenAt.removeAll()
        channelAxientPositiveEvidenceLastSeenAt.removeAll()
        channelAxientNegativeEvidenceStreakStartAt.removeAll()
        channelAxientRfBarsByAntenna.removeAll()
        channelTransmitterPresent.removeAll()
        channelTransmitterPresentLastUpdated.removeAll()
        channelTransmitterPresentLastTrueAt.removeAll()
        channelTransmitterPresentLastFalseAt.removeAll()
        channelTransmitterDeviceIDPresent.removeAll()
        channelTransmitterDeviceIDLastUpdated.removeAll()
        channelRFBarCounts.removeAll()
        channelRfLastUpdated.removeAll()
        channelAudioMutes.removeAll()
        shadowStandardReportSnapshots.removeAll()
        shadowStandardReportLowFrequencySnapshots.removeAll()
        channelMeterRates.removeAll()
        micAudioLastNonZeroAt.removeAll()
        Task {
            await standardReportStateStore.clear()
        }

        if device != nil, liveModeEnabled {
            connect()
        } else {
            disconnect()
        }
        scheduleTelemetrySnapshotPublish(immediate: true)
    }

    private func logDiagnosticError(_ message: String, keySuffix: String) {
        let host = device?.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = device?.port ?? 0
        let endpoint = (host?.isEmpty == false) ? "\(host ?? "unknown"):\(port)" : "unknown"
        let deviceKey = device?.id.uuidString ?? "unknown"
        let key = "shure_\(deviceKey)_\(endpoint)_\(keySuffix)"
        let model = device?.shureModelIdentifier ?? "unknown"
        if Self.isVerboseLogging(for: device) {
            RelayDiagnosticsStore.shared.recordShureTrace("module \(keySuffix) \(endpoint) model=\(model) message=\(message)")
        }
        RelayDiagnosticsStore.shared.recordThrottledError(message, tag: "Shure", key: key, minInterval: diagnosticsMinInterval)
    }

    private func recordBatteryTrace(_ message: String) {
        let host = device?.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = device?.port ?? 0
        let endpoint = (host?.isEmpty == false) ? "\(host ?? "unknown"):\(port)" : "unknown"
        let model = device?.shureModelIdentifier ?? "unknown"
        guard Self.isVerboseLogging(for: device) else { return }
        RelayDiagnosticsStore.shared.recordShureTrace("module battery \(endpoint) model=\(model) \(message)")
    }

    private nonisolated static func isAd4QModel(_ model: String?) -> Bool {
        (model?.uppercased() ?? "").contains("AD4Q")
    }

    /// Short device identifier for generic verbose logs. Multiple
    /// ShureWirelessService instances (one per configured device) all print
    /// through the same unqualified "[ShureWirelessService]" prefix, which
    /// makes their console output indistinguishable on any rig with more
    /// than one device connected -- added while chasing a report on a
    /// specific device (a PSM1000) in a 21-device rig where that ambiguity
    /// made the existing logs useless for isolating its traffic.
    private var deviceLogTag: String {
        guard let device else { return "unknown" }
        let host = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = host.isEmpty ? "unknown" : "\(host):\(device.port)"
        return device.name.isEmpty ? endpoint : "\(device.name)@\(endpoint)"
    }

    private func shouldTraceAD4QRF() -> Bool {
        guard Self.isAd4QModel(device?.shureModelIdentifier) else { return false }
#if DEBUG
        return true
#else
        return Self.shouldEmitConsoleLogs(for: device)
#endif
    }

    private nonisolated static func shouldTraceAD4QFrame(_ frame: ShureIncomingFrame) -> Bool {
        frame.isReportVerb
    }

    private func recordAD4QRFTrace(_ message: String) {
        guard shouldTraceAD4QRF() else { return }
        let host = device?.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = device?.port ?? 0
        let endpoint = (host?.isEmpty == false) ? "\(host ?? "unknown"):\(port)" : "unknown"
        let model = device?.shureModelIdentifier ?? "unknown"
        print("[Shure][AD4Q RF] \(message)")
        RelayDiagnosticsStore.shared.recordShureTrace("module ad4q_rf \(endpoint) model=\(model) \(message)")
    }

    private func shouldTraceULXDTxDeviceID() -> Bool {
        let model = (device?.shureModelIdentifier ?? "").uppercased()
        let upperName = (device?.name ?? "").uppercased()
        guard model.contains("ULXD") || upperName.contains("ULX-D") || upperName.contains("ULXD") else { return false }
        return Self.shouldEmitConsoleLogs(for: device)
    }

    private nonisolated static func shouldTraceULXDTxDeviceIDFrame(_ frame: ShureIncomingFrame) -> Bool {
        frame.isReportVerb && frame.parts.contains(where: { $0.uppercased() == "TX_DEVICE_ID" })
    }

    private func recordULXDTxDeviceIDTrace(_ message: String) {
        guard shouldTraceULXDTxDeviceID() else { return }
        let host = device?.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = device?.port ?? 0
        let endpoint = (host?.isEmpty == false) ? "\(host ?? "unknown"):\(port)" : "unknown"
        let model = device?.shureModelIdentifier ?? "unknown"
        print("[Shure][ULXD TXID] \(message)")
        RelayDiagnosticsStore.shared.recordShureTrace("module ulxd_txid \(endpoint) model=\(model) \(message)")
    }

    // MARK: - Connection

    func connect() {
        guard let device = device else {
            lastError = "No Shure device configured. Add one in Settings → External Devices."
            return
        }

        let endpointIdentity = Self.endpointIdentity(for: device)
        let isUdpDevice = isAnx4UdpDevice(device)

        if currentConnectionIdentity == endpointIdentity {
            // Check actual live connection state here, not a fresh re-derivation
            // of isUdpDevice from config: under "auto" transport, which of these
            // is active was decided by the probe below, not by the config alone.
            if isAutoTransportProbing {
                return
            }
            if connection != nil {
                maybeStartFastUdpTelemetry(for: device)
                return
            }
            if udpConnection != nil {
                return
            }
        }

        // Always tear down any existing connection before we decide what to do next.
        disconnect()

        // Treat PSM 900 devices as offline placeholders: we never attempt a
        // network connection for them, since they don't expose a network API
        // in this workflow. The module UI simply shows the configured device
        // and channel name without live data.
        let modelCode = device.shureModelIdentifier?.uppercased()
        let upperName = device.name.uppercased()
        let isPSM900 = (modelCode == "PSM900")
            || upperName.contains("PSM 900")
            || upperName.contains("PSM900")

        if isPSM900 {
            if Self.isVerboseLogging {
                print("[ShureWirelessService] PSM900 placeholder configured; skipping network connection for \(device.name)")
            }
            isConnected = false
            lastError = nil
            return
        }

        // "Auto" transport on a licensed Axient model (ANX4/ADTD/ADTQ) used
        // to mean: probe TCP command strings briefly, fall back to the
        // reverse-engineered UDP path if the probe didn't pan out. Removed
        // -- confirmed via a real customer field log that the UDP fallback
        // can silently connect and poll forever without ever decoding a
        // single meter value, and the probe's own success/fail signal
        // wasn't reliable enough to trust as the deciding factor. TCP is
        // now the default outright (see isUdpOnlyShureDevice); UDP is only
        // used when a user explicitly selects "UDP Preferred". The probe
        // machinery (beginAutoTransportProbe/finishAutoTransportProbe)
        // is kept in place but unused, not deleted, in case it's needed
        // again.
        if isUdpDevice {
            connectAnx4Udp(device, endpoint: resolvedUdpTelemetryEndpoint(for: device), udpOnly: true)
            return
        }

        startTcpConnection(device: device, endpointIdentity: endpointIdentity)
    }

    /// Briefly probes port 2202 for real TPCI command-string support before
    /// committing to a transport. Falls back to the UDP handshake if the
    /// probe fails to connect or doesn't get a recognizable REP back within
    /// the timeout.
    private func beginAutoTransportProbe(device: ExternalDeviceConfig, endpointIdentity: String) {
        isAutoTransportProbing = true

        guard let port = NWEndpoint.Port(rawValue: device.port) else {
            finishAutoTransportProbe(tcpWorks: false, device: device, endpointIdentity: endpointIdentity)
            return
        }

        if Self.shouldEmitConsoleLogs(for: device) {
            print("[Shure] Auto transport: probing TCP command strings for \(device.name) \(device.host):\(device.port)")
        }
        RelayDiagnosticsStore.shared.recordShureTrace("module auto_probe_start \(device.name) \(device.host):\(device.port)")

        let host = NWEndpoint.Host(device.host)
        let probeConn = NWConnection(host: host, port: port, using: .tcp)
        transportProbeConnection = probeConn

        final class ProbeResolveGate: @unchecked Sendable {
            private let lock = NSLock()
            private var resolved = false
            func resolveOnce() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if resolved { return false }
                resolved = true
                return true
            }
        }
        let gate = ProbeResolveGate()

        nonisolated func finish(tcpWorks: Bool) {
            guard gate.resolveOnce() else { return }
            probeConn.stateUpdateHandler = nil
            probeConn.cancel()
            DispatchQueue.main.async { [weak self] in
                self?.finishAutoTransportProbe(tcpWorks: tcpWorks, device: device, endpointIdentity: endpointIdentity)
            }
        }

        probeConn.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                let probePayload = "< GET 0 ALL >\r\n"
                probeConn.send(content: Data(probePayload.utf8), completion: .contentProcessed { _ in })
                probeConn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    if let data, !data.isEmpty, String(decoding: data, as: UTF8.self).contains("REP") {
                        finish(tcpWorks: true)
                    } else {
                        finish(tcpWorks: false)
                    }
                }
            case .failed, .cancelled:
                finish(tcpWorks: false)
            default:
                break
            }
        }
        probeConn.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 2.5) {
            finish(tcpWorks: false)
        }
    }

    private func finishAutoTransportProbe(tcpWorks: Bool, device: ExternalDeviceConfig, endpointIdentity: String) {
        guard isAutoTransportProbing, currentConnectionIdentity == endpointIdentity else { return }
        isAutoTransportProbing = false
        transportProbeConnection = nil

        RelayDiagnosticsStore.shared.recordShureTrace(
            "module auto_probe_result \(device.name) \(device.host):\(device.port) tcp_works=\(tcpWorks)"
        )
        if Self.shouldEmitConsoleLogs(for: device) {
            print("[Shure] Auto transport: probe result for \(device.name) tcp_works=\(tcpWorks)")
        }

        if tcpWorks {
            startTcpConnection(device: device, endpointIdentity: endpointIdentity)
        } else {
            connectAnx4Udp(device, endpoint: resolvedUdpTelemetryEndpoint(for: device), udpOnly: true)
        }
    }

    private func startTcpConnection(device: ExternalDeviceConfig, endpointIdentity: String) {
        guard let port = NWEndpoint.Port(rawValue: device.port) else {
            lastError = "Invalid port \(device.port)"
            logDiagnosticError("Invalid port \(device.port) for \(device.name)", keySuffix: "invalid_port")
            return
        }

        let host = NWEndpoint.Host(device.host)
        let params = NWParameters.tcp

        let conn = NWConnection(host: host, port: port, using: params)
        connection = conn
        currentConnectionIdentity = endpointIdentity

        lastError = nil

        if Self.isVerboseLogging {
            print("[ShureWirelessService] Starting connection to \(device.host):\(device.port)")
        }
        if isLicensedShureDevice(device), Self.shouldEmitConsoleLogs(for: device) {
            print("[Shure] Live mode connecting to \(device.name) \(device.host):\(device.port) model=\(device.shureModelIdentifier ?? "unknown") transport=\(transportModeLogLabel(for: device))")
        }

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.connection === conn else { return }
                switch newState {
                case .ready:
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] Connection ready to \(device.host):\(device.port)")
                    }
                    if self.isLicensedShureDevice(device), Self.shouldEmitConsoleLogs(for: device) {
                        print("[Shure] Live mode connected to \(device.name) \(device.host):\(device.port)")
                    }
                    if Self.shouldEmitConsoleLogs(for: device) {
                        print("[Shure] Connection ready to \(device.name) \(device.host):\(device.port) model=\(device.shureModelIdentifier ?? "unknown") transport=\(self.transportModeLogLabel(for: device))")
                    }
                    self.isConnected = true
                    self.resetReconnectState()
                    self.waitingTimeoutTask?.cancel()
                    self.waitingTimeoutTask = nil
                    self.lastError = nil
                    self.refreshSharedPollingTask()
                    self.scheduleTelemetrySnapshotPublish(immediate: true)
                    self.startReceiveLoop()
                    self.startTcpStartupSequence(for: device, connection: conn)
                    self.maybeStartFastUdpTelemetry(for: device)
                case .waiting(let error):
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] Connection waiting to \(device.host):\(device.port) — \(error.localizedDescription)")
                    }
                    RelayDiagnosticsStore.shared.recordShureTrace(
                        "module tcp_waiting \(device.name) \(device.host):\(device.port) error=\(error.localizedDescription)"
                    )
                    guard self.waitingTimeoutTask == nil else { return }
                    self.waitingTimeoutTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(Self.waitingEscalationSeconds * 1_000_000_000))
                        guard !Task.isCancelled, let self, self.connection === conn else { return }
                        self.waitingTimeoutTask = nil
                        RelayDiagnosticsStore.shared.recordShureTrace(
                            "module tcp_waiting_timeout \(device.name) \(device.host):\(device.port) after=\(String(format: "%.1f", Self.waitingEscalationSeconds))s"
                        )
                        conn.cancel()
                    }
                case .failed(let error):
                    print("[ShureWirelessService] \(device.name)@\(device.host):\(device.port) Connection failed: \(error)")
                    if Self.shouldEmitConsoleLogs(for: device) {
                        print("[Shure] Connection failed to \(device.name) \(device.host):\(device.port) — \(error.localizedDescription)")
                    }
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.logDiagnosticError("Connection failed to \(device.host):\(device.port) — \(error.localizedDescription)", keySuffix: "connection_failed")
                    // Clear the dead reference -- leaving it non-nil left the
                    // service in a zombie state: every future sendRaw() call
                    // saw a non-nil `connection` and tried to send on it
                    // anyway (failing forever with "Socket is not connected"),
                    // and setLiveModeEnabled's `connection == nil` check never
                    // saw a reason to reconnect, requiring a full exit/re-enter
                    // of Live Mode (which calls disconnect(), the only other
                    // place that clears this) to recover.
                    self.connection = nil
                    self.waitingTimeoutTask?.cancel()
                    self.waitingTimeoutTask = nil
                    self.refreshSharedPollingTask()
                    self.scheduleReconnectIfNeeded(for: device)
                    self.scheduleTelemetrySnapshotPublish(immediate: true)
                case .cancelled:
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] \(device.name)@\(device.host):\(device.port) Connection cancelled")
                    }
                    self.isConnected = false
                    self.connection = nil
                    self.waitingTimeoutTask?.cancel()
                    self.waitingTimeoutTask = nil
                    self.refreshSharedPollingTask()
                    self.scheduleReconnectIfNeeded(for: device)
                    self.scheduleTelemetrySnapshotPublish(immediate: true)
                default:
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] \(device.name)@\(device.host):\(device.port) Connection state updated: \(newState)")
                    }
                }
            }
        }

        conn.start(queue: queue)
    }

    func disconnect() {
        let tcpConnection = connection
        let activeUdpConnection = udpConnection
        let activeProbeConnection = transportProbeConnection
        let previousReceiveGate = tcpReceiveGate
        let previousSendGate = tcpSendGate
        tcpReceiveGate = CallbackGate()
        tcpSendGate = CallbackGate()
        connection = nil
        udpConnection = nil
        transportProbeConnection = nil
        isAutoTransportProbing = false
        previousReceiveGate.deactivate()
        previousSendGate.deactivate()
        tcpConnection?.stateUpdateHandler = nil
        activeUdpConnection?.stateUpdateHandler = nil
        activeProbeConnection?.stateUpdateHandler = nil
        tcpConnection?.cancel()
        activeUdpConnection?.cancel()
        activeProbeConnection?.cancel()
        currentConnectionIdentity = nil
        anx4RemoteSessionSelector = nil
        anx4RemoteQuerySelector = nil
        anx4RemoteDataSelector = nil
        anx4ResponderCID = nil
        anx4HandshakedCIDs.removeAll()
        anx4HandshakeSent = false
        anx4FollowupsSent = false
        isConnected = false
        didLogAnx4Receive = false
        didLogAnx4MeterDecoded = false
        didLogAnx4RFDecoded = false
        didLogFastUdpFallbackNoDecode = false
        resetAnx4LocalSessionSelector()
        anx4UseOpaqueRequestPhase = false
        anx4WWBPhase = .inactive
        anx4Phase2ASendCount = 0
        anx4SawControlFrame0F = false
        anx4SawControlFrame08 = false
        anx4SawControlSubPDU0D = false
        anx4Template2AIndex = 0
        anx4Template5AIndex = 0
        anx4Template60Index = 0
        anx4CaptureReplayIndex = 0
        anx4TelemetryLoopTask?.cancel()
        anx4TelemetryLoopTask = nil
        fastUdpDecodeTimeoutTask?.cancel()
        fastUdpDecodeTimeoutTask = nil
        tcpStartupTask?.cancel()
        tcpStartupTask = nil
        outgoingSendTask?.cancel()
        outgoingSendTask = nil
        highPriorityCommandQueue.removeAll()
        normalPriorityCommandQueue.removeAll()
        lastLiveSyncPersistAt = nil
        lastChannelSnapshotQueryAt.removeAll()
        fastUdpRfLastUpdated.removeAll()
        fastUdpMicLastUpdated.removeAll()
        fastUdpRfAntenna12Levels.removeAll()
        fastUdpRfAntenna13Levels.removeAll()
        activeUdpEndpointHost = nil
        activeUdpEndpointPort = nil
        debugTelemetryProtocolLabel = DebugTelemetryProtocol.tcp2202.rawValue
        axientAudioBitmapAllowsLevel.removeAll()
        channelMicAudioOverload.removeAll()
        channelBatteryHasSmartTelemetry.removeAll()
        channelBatteryCalculationPendingAt.removeAll()
        shadowStandardReportSnapshots.removeAll()
        shadowStandardReportLowFrequencySnapshots.removeAll()
        Task {
            await standardReportStateStore.clear()
        }
        refreshSharedPollingTask()
        scheduleTelemetrySnapshotPublish(immediate: true)
    }

    private func isAnx4UdpDevice(_ device: ExternalDeviceConfig) -> Bool {
        Self.isUdpOnlyShureDevice(device)
    }

    /// Clears any in-flight reconnect backoff state. Called whenever a
    /// genuinely fresh (non-retry) connection attempt starts: on successful
    /// `.ready`, on explicit Live-Mode-on/off, and on device rebind.
    private func resetReconnectState() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        isReconnecting = false
    }

    /// Schedules a single reconnect attempt after an unexpected connection
    /// failure/cancellation, using exponential backoff with jitter. Only
    /// schedules while still in Live Mode — `setLiveModeEnabled(false)`
    /// flips `liveModeEnabled` to false before calling `disconnect()`, so an
    /// intentional stop is already excluded by this guard by the time any
    /// resulting state-handler callback runs.
    private func scheduleReconnectIfNeeded(for device: ExternalDeviceConfig) {
        guard liveModeEnabled else { return }

        reconnectTask?.cancel()
        reconnectAttempt += 1
        isReconnecting = true
        let attempt = reconnectAttempt
        let delay = ShureReconnectBackoff.delay(forAttempt: attempt) * Double.random(in: 0.8...1.2)

        RelayDiagnosticsStore.shared.recordShureTrace(
            "module reconnect_scheduled \(device.name) \(device.host):\(device.port) attempt=\(attempt) delay=\(String(format: "%.1f", delay))s"
        )

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.liveModeEnabled else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    private func connectAnx4Udp(
        _ device: ExternalDeviceConfig,
        endpoint: (host: String, port: UInt16)?,
        udpOnly: Bool
    ) {
        guard let endpoint else {
            if udpOnly {
                lastError = "No UDP telemetry endpoint discovered"
                logDiagnosticError("No UDP telemetry endpoint for \(device.name)", keySuffix: "udp_endpoint_missing")
            } else {
                RelayDiagnosticsStore.shared.recordShureTrace("module udp_fallback \(device.name) \(device.host) reason=no_discovered_endpoint")
            }
            return
        }
        let host = NWEndpoint.Host(endpoint.host)
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            if udpOnly {
                lastError = "Invalid UDP port \(endpoint.port)"
                logDiagnosticError("Invalid UDP port \(endpoint.port) for \(device.name)", keySuffix: "udp_port_invalid")
            } else {
                RelayDiagnosticsStore.shared.recordShureTrace("module udp_fallback \(device.name) \(endpoint.host):\(endpoint.port) reason=invalid_port")
            }
            return
        }

        if anx4SessionId.isEmpty {
            anx4SessionId = [UInt8](repeating: 0, count: 4)
            _ = SecRandomCopyBytes(kSecRandomDefault, anx4SessionId.count, &anx4SessionId)
        }
        anx4RemoteSessionSelector = nil
        anx4RemoteQuerySelector = nil
        anx4RemoteDataSelector = nil
        anx4ResponderCID = nil
        anx4HandshakedCIDs.removeAll()
        anx4HandshakeSent = false
        anx4FollowupsSent = false
        resetAnx4LocalSessionSelector()
        anx4UseOpaqueRequestPhase = false
        anx4WWBPhase = .inactive
        anx4Phase2ASendCount = 0
        anx4SawControlFrame0F = false
        anx4SawControlFrame08 = false
        anx4SawControlSubPDU0D = false
        anx4Template2AIndex = 0
        anx4Template5AIndex = 0
        anx4Template60Index = 0
        anx4CaptureReplayIndex = 0
        anx4TelemetryLoopTask?.cancel()
        anx4TelemetryLoopTask = nil

        let params = NWParameters.udp
        let conn = NWConnection(host: host, port: port, using: params)
        udpConnection = conn
        activeUdpEndpointHost = endpoint.host
        activeUdpEndpointPort = endpoint.port
        currentConnectionIdentity = Self.endpointIdentity(for: device)
        lastError = nil
        didLogAnx4Receive = false
        didLogAnx4MeterDecoded = false
        didLogAnx4RFDecoded = false
        didLogFastUdpFallbackNoDecode = false
        fastUdpRfLastUpdated.removeAll()
        fastUdpMicLastUpdated.removeAll()
        fastUdpRfAntenna12Levels.removeAll()
        fastUdpRfAntenna13Levels.removeAll()
        scheduleFastUdpDecodeTimeoutLog(for: device, endpoint: endpoint)

        if Self.isVerboseLogging {
            print("[ShureWirelessService] Starting Shure UDP telemetry connection to \(endpoint.host):\(endpoint.port)")
        }
        RelayDiagnosticsStore.shared.recordShureTrace("module udp_connect_start \(device.name) \(endpoint.host):\(endpoint.port) model=\(device.shureModelIdentifier ?? "unknown") transport=\(transportModeLogLabel(for: device))")
        if Self.shouldEmitConsoleLogs(for: device) {
            print("[Shure] Live mode connecting (UDP) to \(device.name) \(endpoint.host):\(endpoint.port) model=\(device.shureModelIdentifier ?? "unknown") transport=\(transportModeLogLabel(for: device))")
        }

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.udpConnection === conn else { return }
                switch newState {
                case .ready:
                    RelayDiagnosticsStore.shared.recordShureTrace("module udp_ready \(device.name) \(endpoint.host):\(endpoint.port) model=\(device.shureModelIdentifier ?? "unknown") transport=\(self.transportModeLogLabel(for: device))")
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] Shure UDP telemetry ready to \(endpoint.host):\(endpoint.port)")
                    }
                    if Self.shouldEmitConsoleLogs(for: device) {
                        print("[Shure] UDP ready to \(device.name) \(endpoint.host):\(endpoint.port) model=\(device.shureModelIdentifier ?? "unknown") transport=\(self.transportModeLogLabel(for: device))")
                    }
                    if udpOnly || self.connection == nil {
                        self.isConnected = true
                    }
                    self.resetReconnectState()
                    self.udpWaitingTimeoutTask?.cancel()
                    self.udpWaitingTimeoutTask = nil
                    self.lastError = nil
                    self.scheduleTelemetrySnapshotPublish(immediate: true)
                    self.sendAnx4Handshake()
                    self.startAnx4ReceiveLoop()
                case .waiting(let error):
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] Shure UDP telemetry waiting to \(endpoint.host):\(endpoint.port) — \(error.localizedDescription)")
                    }
                    RelayDiagnosticsStore.shared.recordShureTrace(
                        "module udp_waiting \(device.name) \(endpoint.host):\(endpoint.port) error=\(error.localizedDescription)"
                    )
                    guard self.udpWaitingTimeoutTask == nil else { return }
                    self.udpWaitingTimeoutTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(Self.waitingEscalationSeconds * 1_000_000_000))
                        guard !Task.isCancelled, let self, self.udpConnection === conn else { return }
                        self.udpWaitingTimeoutTask = nil
                        RelayDiagnosticsStore.shared.recordShureTrace(
                            "module udp_waiting_timeout \(device.name) \(endpoint.host):\(endpoint.port) after=\(String(format: "%.1f", Self.waitingEscalationSeconds))s"
                        )
                        conn.cancel()
                    }
                case .failed(let error):
                    let errorMessage = error.localizedDescription
                    RelayDiagnosticsStore.shared.recordShureTrace("module udp_failed \(device.name) \(endpoint.host):\(endpoint.port) error=\(errorMessage)")
                    print("[ShureWirelessService] Shure UDP telemetry failed: \(error)")
                    if Self.shouldEmitConsoleLogs(for: device) {
                        print("[Shure] UDP failed to \(device.name) \(endpoint.host):\(endpoint.port) — \(errorMessage)")
                    }
                    self.udpConnection = nil
                    self.activeUdpEndpointHost = nil
                    self.activeUdpEndpointPort = nil
                    self.udpWaitingTimeoutTask?.cancel()
                    self.udpWaitingTimeoutTask = nil
                    if udpOnly || self.connection == nil {
                        self.isConnected = false
                        self.lastError = errorMessage
                        self.logDiagnosticError("Shure UDP failed to \(endpoint.host):\(endpoint.port) — \(errorMessage)", keySuffix: "udp_failed")
                        if udpOnly {
                            self.scheduleReconnectIfNeeded(for: device)
                        }
                    } else {
                        self.debugTelemetryProtocolLabel = DebugTelemetryProtocol.tcp2202.rawValue
                        RelayDiagnosticsStore.shared.recordShureTrace("module udp_fallback \(device.name) \(device.host):\(device.port) reason=\(errorMessage)")
                    }
                    self.scheduleTelemetrySnapshotPublish(immediate: true)
                case .cancelled:
                    RelayDiagnosticsStore.shared.recordShureTrace("module udp_cancelled \(device.name) \(endpoint.host):\(endpoint.port)")
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] Shure UDP telemetry cancelled")
                    }
                    self.udpConnection = nil
                    self.activeUdpEndpointHost = nil
                    self.activeUdpEndpointPort = nil
                    self.udpWaitingTimeoutTask?.cancel()
                    self.udpWaitingTimeoutTask = nil
                    if udpOnly || self.connection == nil {
                        self.isConnected = false
                        if udpOnly {
                            self.scheduleReconnectIfNeeded(for: device)
                        }
                    } else {
                        self.debugTelemetryProtocolLabel = DebugTelemetryProtocol.tcp2202.rawValue
                    }
                    self.scheduleTelemetrySnapshotPublish(immediate: true)
                default:
                    if Self.isVerboseLogging {
                        print("[ShureWirelessService] Shure UDP telemetry state updated: \(newState)")
                    }
                }
            }
        }

        conn.start(queue: udpQueue)
    }

    private func sendAnx4Handshake() {
        guard !anx4HandshakeSent else { return }
        anx4HandshakeSent = true
        guard let conn = udpConnection else { return }
        let senderCID = ShureAnx4Handshake.senderCID(sessionId: anx4SessionId)
        let targetCID = ShureAnx4Handshake.targetCID(from: device?.shureDiscoveryCID)
        let payloads = [
            ShureAnx4Handshake.initialSubscribe(
                senderCID: senderCID,
                targetCID: targetCID,
                localSessionSelector: anx4LocalSessionSelector
            )
        ]
        let endpoint = activeUdpEndpointDescription()
        let shouldLog = Self.shouldEmitConsoleLogs(for: device)
        if Self.shouldEmitConsoleLogs(for: device) {
            print("[Shure] UDP handshake sending \(payloads.count) packets to \(endpoint)")
        }
        RelayDiagnosticsStore.shared.recordShureTrace(
            "module udp_handshake_start \(endpoint) payloads=\(payloads.count) localSession=0x\(String(anx4LocalSessionSelector, radix: 16)) targetCID=\(targetCID.uuidString)"
        )
        for payload in payloads {
            logAnx4PacketSummary(payload, direction: "out")
            conn.send(content: payload, completion: .contentProcessed { [weak self] error in
                if let error {
                    DispatchQueue.main.async {
                        self?.lastError = error.localizedDescription
                    }
                    if shouldLog {
                        print("[Shure] ANX4 UDP send failed — \(error.localizedDescription)")
                    }
                    Task { @MainActor [weak self] in
                        self?.logDiagnosticError("ANX4 UDP send failed — \(error.localizedDescription)", keySuffix: "udp_send_failed")
                    }
                } else {
                    Task { @MainActor in
                        RelayDiagnosticsStore.shared.recordShureTrace("module udp_handshake_packet_sent \(endpoint) bytes=\(payload.count)")
                    }
                }
            })
        }
    }

    private func startAnx4ReceiveLoop() {
        guard let conn = udpConnection else { return }
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, self.udpConnection === conn else { return }
                if let data, !data.isEmpty {
                    self.lastHeardAt = Date()
                    self.recordLiveSyncIfNeeded()
                    if !self.didLogAnx4Receive {
                        self.didLogAnx4Receive = true
                        let endpoint = self.activeUdpEndpointDescription()
                        if Self.shouldEmitConsoleLogs(for: self.device) {
                            print("[Shure] UDP data received from \(endpoint)")
                        }
                        RelayDiagnosticsStore.shared.recordShureTrace("module udp_first_receive \(endpoint) bytes=\(data.count)")
                    }
                    self.handleAnx4Packet(data)
                }
                if let error {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    if Self.shouldEmitConsoleLogs(for: self.device) {
                        print("[Shure] ANX4 UDP receive failed — \(error.localizedDescription)")
                    }
                    self.logDiagnosticError("ANX4 UDP receive failed — \(error.localizedDescription)", keySuffix: "udp_receive_failed")
                    return
                }
                self.startAnx4ReceiveLoop()
            }
        }
    }

    private func handleAnx4Packet(_ data: Data) {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return }

        logAnx4PacketSummary(data, direction: "in")

        if let parsed = ShureSessionFramer.parse(data),
           parsed.framingVector == 0x06,
           parsed.payload.count >= 10 {
            let remoteSessionSelector = UInt16(parsed.payload[0]) << 8 | UInt16(parsed.payload[1])
            let remoteQuerySelector = UInt16(parsed.payload[8]) << 8 | UInt16(parsed.payload[9])
            RelayDiagnosticsStore.shared.recordShureTrace("module udp_bootstrap_response frame=0x06 sessionSelector=0x\(String(remoteSessionSelector, radix: 16)) querySelector=0x\(String(remoteQuerySelector, radix: 16)) bytes=\(data.count)")
            anx4RemoteSessionSelector = remoteSessionSelector
            anx4RemoteQuerySelector = remoteQuerySelector
            anx4ResponderCID = parsed.senderCID
        }

        if let parsed = ShureSessionFramer.parse(data),
           parsed.framingVector == 0x04 {
            if let parsedDataSelector = parseAnx4DataSelector(from: parsed.payload) {
                anx4RemoteDataSelector = parsedDataSelector
            }
            let responderCID = anx4ResponderCID ?? parsed.senderCID
            if let parsedResponderCID = anx4ResponderCID, parsed.senderCID == parsedResponderCID {
                anx4ResponderCID = parsedResponderCID
            }
            if !anx4HandshakedCIDs.contains(responderCID),
               let remoteSessionSelector = anx4RemoteSessionSelector,
               let remoteQuerySelector = anx4RemoteQuerySelector,
               let remoteDataSelector = anx4RemoteDataSelector {
                anx4HandshakedCIDs.insert(responderCID)
                sendAnx4BootstrapFollowups(
                    responderCID: responderCID,
                    remoteSessionSelector: remoteSessionSelector,
                    remoteQuerySelector: remoteQuerySelector,
                    remoteDataSelector: remoteDataSelector
                )
            }
        }

        if let parsed = ShureSessionFramer.parse(data),
           anx4FollowupsSent,
           anx4TelemetryLoopTask == nil,
           let responderCID = anx4ResponderCID,
           let remoteQuerySelector = anx4RemoteQuerySelector,
           let remoteDataSelector = anx4RemoteDataSelector,
           parsed.framingVector == 0x02 || parsed.framingVector == 0x08 || parsed.framingVector == 0x01 {
            RelayDiagnosticsStore.shared.recordShureTrace(
                "module udp_loop_start_trigger frame=0x\(String(parsed.framingVector, radix: 16)) \(device?.host ?? "unknown"):57383"
            )
            startAnx4TelemetryLoop(
                host: device?.host ?? "unknown",
                responderCID: responderCID,
                remoteQuerySelector: remoteQuerySelector,
                remoteDataSelector: remoteDataSelector
            )
        }

        // Capture-replay opaque path is disabled: the 0x2A/0x5A/0x60 and
        // capture-stage payloads contain WWB session-specific HMAC/nonce
        // material that fails validation against any other session, causing
        // the device to silently drop us after a few seconds. Property-list
        // polling (frame 0x01 + outer 0x0001 + 0x07 0x02 inner records) is
        // used instead — see `ShureAnx4Handshake.propertyAddressListFrame`.
        if false,
           let parsed = ShureSessionFramer.parse(data),
           !anx4UseOpaqueRequestPhase,
           parsed.rootVector == 0x00000001,
           parsed.framingVector == 0x01 || parsed.framingVector == 0x02,
           (data.count == 95 || data.count == 80 || data.count == 61) {
            anx4UseOpaqueRequestPhase = true
            anx4WWBPhase = .request2A
            anx4Phase2ASendCount = 0
            anx4CaptureReplayIndex = 0
            RelayDiagnosticsStore.shared.recordShureTrace(
                "module udp_wwb_phase_enabled \(device?.host ?? "unknown"):57383 triggerBytes=\(data.count) frame=0x\(String(parsed.framingVector, radix: 16))"
            )
        }

        if let parsed = ShureSessionFramer.parse(data),
           anx4UseOpaqueRequestPhase,
           parsed.rootVector == 0x00000001,
           parsed.framingVector == 0x01,
           firstAnx4SubPDUMarker(in: parsed.payload) == 0x2a,
           anx4WWBPhase == .request2A {
            anx4WWBPhase = .request5A
            RelayDiagnosticsStore.shared.recordShureTrace(
                "module udp_wwb_phase_promote \(device?.host ?? "unknown"):57383 stage=0x5a reason=inbound_0x2a"
            )
        }

        if let parsed = ShureSessionFramer.parse(data),
           anx4UseOpaqueRequestPhase {
            if parsed.framingVector == 0x0f {
                anx4SawControlFrame0F = true
            }
            if parsed.framingVector == 0x08 {
                anx4SawControlFrame08 = true
            }
            if parsed.framingVector == 0x01, firstAnx4SubPDUMarker(in: parsed.payload) == 0x0d {
                anx4SawControlSubPDU0D = true
            }

            if anx4WWBPhase == .steady60,
               anx4SawControlFrame0F,
               anx4SawControlFrame08,
               anx4SawControlSubPDU0D {
                anx4SawControlFrame0F = false
                anx4SawControlFrame08 = false
                anx4SawControlSubPDU0D = false
                anx4WWBPhase = .request5A
                anx4CaptureReplayIndex = 0
                RelayDiagnosticsStore.shared.recordShureTrace(
                    "module udp_wwb_phase_promote \(device?.host ?? "unknown"):57383 stage=0x5a reason=post_control_triplet"
                )
            }
        }

        var index = 0
        while index + 7 <= bytes.count {
            if bytes[index] == 0x10, bytes[index + 1] == 0x07, bytes[index + 2] == 0x02 {
                let channelIndex = fastUdpChannelIndex(from: Int(bytes[index + 3]))
                if bytes[index + 4] == 0x01, bytes[index + 5] == 0x01 {
                    let now = Date()
                    let raw = Double(bytes[index + 6])
                    let level = (raw / 255.0) * 20.0
                    micAudioLastUpdated[channelIndex] = now
                    fastUdpMicLastUpdated[channelIndex] = now
                    if raw > 0 {
                        micAudioLastNonZeroAt[channelIndex] = now
                        if shouldTrustFastUdpPresenceEvidence() {
                            updateFastUdpTransmitterPresence(channelIndex: channelIndex, isPresent: true, now: now)
                        }
                    }
                    debugTelemetryProtocolLabel = DebugTelemetryProtocol.udp.rawValue
                    let composition = snapshotCompositionPolicy(channelIndex: channelIndex, now: now)
                    let udpUpdate = ShureUdpStateUpdate(
                        channelIndex: channelIndex,
                        rfTxLevel: nil,
                        rfBarCount: nil,
                        micAudioLevel: level,
                        now: now
                    )
                    Task { [weak self] in
                        guard let self else { return }
                        let mirrored = await self.standardReportStateStore.applyUdp(
                            udpUpdate,
                            composition: composition
                        )
                        await MainActor.run {
                            guard let mirrored else { return }
                            self.applyShadowStandardReportLowFrequencySnapshot(
                                channelIndex: channelIndex,
                                mirrored: mirrored,
                                line: "UDP audio ch=\(channelIndex)"
                            )
                            self.verifyMirroredStandardReportState(
                                channelIndex: channelIndex,
                                mirrored: mirrored,
                                line: "UDP audio ch=\(channelIndex)"
                            )
                        }
                    }
                    if !didLogAnx4MeterDecoded {
                        didLogAnx4MeterDecoded = true
                        let endpoint = activeUdpEndpointDescription()
                        RelayDiagnosticsStore.shared.recordShureTrace(
                            "module udp_meter_first_decoded \(endpoint) type=audio ch=\(channelIndex) raw=\(Int(raw)) level=\(String(format: "%.2f", level))"
                        )
                    }
                }
                index += 7
                continue
            }
            if bytes[index] == 0x10, bytes[index + 1] == 0x0a, bytes[index + 2] == 0x02 {
                let channelIndex = fastUdpChannelIndex(from: Int(bytes[index + 3]))
                if bytes[index + 4] == 0x01, bytes[index + 5] == 0x14, index + 9 < bytes.count {
                    let now = Date()
                    let rfByte = bytes[index + 9]
                    let bars = max(0, min(5, udpRfBars(fromRawByte: Int(rfByte))))
                    // Same hold/hysteresis as the TCP RSSI_LED_BITMAP path
                    // (see ShureAxientRfBarHoldResolver) -- this UDP decode
                    // path is a separate, independently-computed RF source
                    // (fast telemetry preferred over TCP when fresh) that
                    // otherwise bypassed that smoothing entirely, and
                    // sharing the same per-channel hold state means a
                    // channel that flips between TCP and UDP sourcing
                    // doesn't produce a visible jump on the switch either.
                    let smoothedBars = isAxientDeviceModel() ? smoothedAxientRfBarCount(bars, channelIndex: channelIndex, now: now) : bars
                    rfTxLastUpdated[channelIndex] = now
                    channelRfLastUpdated[channelIndex] = now
                    fastUdpRfLastUpdated[channelIndex] = now
                    if shouldTrustFastUdpPresenceEvidence() {
                        if shouldTrustFastUdpPresenceEvidence() {
                            updateFastUdpTransmitterPresence(channelIndex: channelIndex, isPresent: rfByte > 0, now: now)
                        }
                    }
                    debugTelemetryProtocolLabel = DebugTelemetryProtocol.udp.rawValue
                    let composition = snapshotCompositionPolicy(channelIndex: channelIndex, now: now)
                    let udpUpdate = ShureUdpStateUpdate(
                        channelIndex: channelIndex,
                        rfTxLevel: Int(rfByte),
                        rfBarCount: smoothedBars,
                        micAudioLevel: nil,
                        now: now
                    )
                    Task { [weak self] in
                        guard let self else { return }
                        let mirrored = await self.standardReportStateStore.applyUdp(
                            udpUpdate,
                            composition: composition
                        )
                        await MainActor.run {
                            guard let mirrored else { return }
                            self.applyShadowStandardReportLowFrequencySnapshot(
                                channelIndex: channelIndex,
                                mirrored: mirrored,
                                line: "UDP rf ch=\(channelIndex)"
                            )
                            self.verifyMirroredStandardReportState(
                                channelIndex: channelIndex,
                                mirrored: mirrored,
                                line: "UDP rf ch=\(channelIndex)"
                            )
                        }
                    }
                    if !didLogAnx4RFDecoded {
                        didLogAnx4RFDecoded = true
                        let endpoint = activeUdpEndpointDescription()
                        RelayDiagnosticsStore.shared.recordShureTrace(
                            "module udp_meter_first_decoded \(endpoint) type=rf ch=\(channelIndex) rfByte=\(Int(rfByte)) bars=\(bars)"
                        )
                    }
                }
                index += 10
                continue
            }
            if bytes[index] == 0x10, bytes[index + 1] == 0x08, bytes[index + 2] == 0x02, index + 7 < bytes.count {
                let channelIndex = fastUdpChannelIndex(from: Int(bytes[index + 3]))
                if bytes[index + 4] == 0x08 {
                    let property = bytes[index + 5]
                    let raw = Int(bytes[index + 7])
                    if property == 0x12 || property == 0x13 {
                        let now = Date()
                        if property == 0x12 {
                            fastUdpRfAntenna12Levels[channelIndex] = raw
                        } else {
                            fastUdpRfAntenna13Levels[channelIndex] = raw
                        }
                        let rfByte = max(
                            fastUdpRfAntenna12Levels[channelIndex] ?? 0,
                            fastUdpRfAntenna13Levels[channelIndex] ?? 0
                        )
                        let bars = max(0, min(5, udpRfBars(fromRawByte: rfByte)))
                        // See the matching comment on the 0x0a decode branch
                        // above -- same hold/hysteresis, same shared
                        // per-channel state.
                        let smoothedBars = isAxientDeviceModel() ? smoothedAxientRfBarCount(bars, channelIndex: channelIndex, now: now) : bars
                        rfTxLastUpdated[channelIndex] = now
                        channelRfLastUpdated[channelIndex] = now
                        fastUdpRfLastUpdated[channelIndex] = now
                        if shouldTrustFastUdpPresenceEvidence() {
                            updateFastUdpTransmitterPresence(channelIndex: channelIndex, isPresent: rfByte > 0, now: now)
                        }
                        debugTelemetryProtocolLabel = DebugTelemetryProtocol.udp.rawValue
                        let composition = snapshotCompositionPolicy(channelIndex: channelIndex, now: now)
                        let udpUpdate = ShureUdpStateUpdate(
                            channelIndex: channelIndex,
                            rfTxLevel: rfByte,
                            rfBarCount: smoothedBars,
                            micAudioLevel: nil,
                            now: now
                        )
                        Task { [weak self] in
                            guard let self else { return }
                            let mirrored = await self.standardReportStateStore.applyUdp(
                                udpUpdate,
                                composition: composition
                            )
                            await MainActor.run {
                                guard let mirrored else { return }
                                self.applyShadowStandardReportLowFrequencySnapshot(
                                    channelIndex: channelIndex,
                                    mirrored: mirrored,
                                    line: "UDP rf-ulxd ch=\(channelIndex)"
                                )
                                self.verifyMirroredStandardReportState(
                                    channelIndex: channelIndex,
                                    mirrored: mirrored,
                                    line: "UDP rf-ulxd ch=\(channelIndex)"
                                )
                            }
                        }
                        if !didLogAnx4RFDecoded {
                            didLogAnx4RFDecoded = true
                            let endpoint = activeUdpEndpointDescription()
                            RelayDiagnosticsStore.shared.recordShureTrace(
                                "module udp_meter_first_decoded \(endpoint) type=rf-ulxd ch=\(channelIndex) property=0x\(String(property, radix: 16)) rfByte=\(rfByte) bars=\(bars)"
                            )
                        }
                    }
                }
                index += 8
                continue
            }
            index += 1
        }
    }

    private func logAnx4PacketSummary(_ data: Data, direction: String) {
        // Per-packet trace — gated by family preference so a fleet of
        // non-ANX4 devices (or release builds) doesn't pay the main-actor
        // cost on every frame.
        guard Self.isVerboseLogging(for: device) else { return }

        guard let parsed = ShureSessionFramer.parse(data) else {
            RelayDiagnosticsStore.shared.recordShureTrace("module udp_packet_\(direction)_unparsed bytes=\(data.count)")
            return
        }

        let selectors = parsedSelectors(from: parsed.payload)
        let selectorText = selectors.isEmpty
            ? "selectors=none"
            : "selectors=" + selectors.map { String(format: "0x%04x", $0) }.joined(separator: ",")

        let targetText = parsed.framingTargetCID?.uuidString ?? "none"
        let meterText = anx4MeterMarkers(in: parsed.payload)
        let subPDUText = firstAnx4SubPDUMarker(in: parsed.payload).map { " subPDU=0x" + String($0, radix: 16) } ?? ""
        let meterSuffix = meterText.isEmpty ? "" : " \(meterText)"

        RelayDiagnosticsStore.shared.recordShureTrace(
            "module udp_packet_\(direction) frame=0x\(String(parsed.framingVector, radix: 16)) root=0x\(String(parsed.rootVector, radix: 16)) bytes=\(data.count) payload=\(parsed.payload.count) targetCID=\(targetText) \(selectorText)\(subPDUText)\(meterSuffix)"
        )

        if direction == "in", shouldTraceDetailedAnx4Payload(parsed: parsed, packetByteCount: data.count) {
            RelayDiagnosticsStore.shared.recordShureTrace(
                "module udp_payload_in frame=0x\(String(parsed.framingVector, radix: 16)) bytes=\(data.count) hex=\(hexPreview(parsed.payload, limit: detailedAnx4HexLimit(for: parsed, packetByteCount: data.count)))"
            )
        }
    }

    private func parsedSelectors(from payload: Data) -> [UInt16] {
        let bytes = [UInt8](payload)
        guard bytes.count >= 2 else { return [] }

        var selectors: [UInt16] = []
        var seen = Set<UInt16>()
        var index = 0

        while index + 1 < bytes.count, selectors.count < 4 {
            let value = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            if value >= 0x4000, value <= 0x7fff {
                index += 2
                continue
            }
            if seen.insert(value).inserted {
                selectors.append(value)
            }
            index += 2
        }

        return selectors
    }

    private func anx4MeterMarkers(in payload: Data) -> String {
        let bytes = [UInt8](payload)
        var markers: [String] = []
        var index = 0

        while index + 6 < bytes.count, markers.count < 3 {
            if bytes[index] == 0x10, bytes[index + 1] == 0x07, bytes[index + 2] == 0x02,
               bytes[index + 4] == 0x01, bytes[index + 5] == 0x01 {
                let channel = Int(bytes[index + 3]) + 1
                let raw = bytes[index + 6]
                markers.append("audioCH\(channel)=\(raw)")
                index += 7
                continue
            }

            if bytes[index] == 0x10, bytes[index + 1] == 0x0a, bytes[index + 2] == 0x02,
               bytes[index + 4] == 0x01, bytes[index + 5] == 0x14,
               index + 9 < bytes.count {
                let channel = Int(bytes[index + 3]) + 1
                let raw = bytes[index + 9]
                markers.append("rfCH\(channel)=\(raw)")
                index += 10
                continue
            }

            index += 1
        }

        return markers.joined(separator: " ")
    }

    private func shouldTraceDetailedAnx4Payload(parsed: ShureSessionFramer.ParsedPacket, packetByteCount: Int) -> Bool {
        if parsed.framingVector == 0x08 || parsed.framingVector == 0x0f {
            return true
        }
        guard parsed.framingVector == 0x01 || parsed.framingVector == 0x02 else { return false }
        if packetByteCount == 95 || packetByteCount == 80 || packetByteCount == 61 || packetByteCount == 66 || packetByteCount == 73 || packetByteCount == 74 || packetByteCount == 103 || packetByteCount == 151 || packetByteCount == 157 {
            return true
        }
        if parsed.framingVector == 0x01, firstAnx4SubPDUMarker(in: parsed.payload) == 0x0d {
            return true
        }
        return anx4MeterMarkers(in: parsed.payload).isEmpty && packetByteCount > 78
    }

    private func detailedAnx4HexLimit(for parsed: ShureSessionFramer.ParsedPacket, packetByteCount: Int) -> Int {
        if parsed.framingVector == 0x08 || parsed.framingVector == 0x0f || packetByteCount >= 151 {
            return 96
        }
        if packetByteCount == 66 || packetByteCount == 73 || packetByteCount == 74 {
            return 64
        }
        return 48
    }

    private func firstAnx4SubPDUMarker(in payload: Data) -> UInt16? {
        guard payload.count >= 22 else { return nil }
        let marker = UInt16(payload[20]) << 8 | UInt16(payload[21])
        guard (marker & 0xF000) == 0x7000 else { return nil }
        return marker & 0x0FFF
    }

    private func hexPreview(_ data: Data, limit: Int) -> String {
        data.prefix(limit).map { String(format: "%02x", $0) }.joined()
    }

    private func parseAnx4Cid(from bytes: [UInt8]) -> [UInt8]? {
        if bytes.isEmpty { return nil }
        let ascii = String(bytes: bytes, encoding: .ascii) ?? ""
        if let cidRange = ascii.range(of: "cid=") {
            let start = cidRange.upperBound
            let suffix = ascii[start...]
            let hexPart = suffix.prefix(8)
            if hexPart.count == 8 {
                var result: [UInt8] = []
                var index = hexPart.startIndex
                while index < hexPart.endIndex {
                    let next = hexPart.index(index, offsetBy: 2)
                    let pair = hexPart[index..<next]
                    if let byte = UInt8(pair, radix: 16) {
                        result.append(byte)
                    }
                    index = next
                }
                if result.count == 4 { return result }
            }
        }
        return nil
    }

    private func parseAnx4QuerySelector(from payload: Data) -> UInt16? {
        let bytes = [UInt8](payload)
        guard bytes.count >= 4 else { return nil }
        let selector = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        return selector == 0 ? nil : selector
    }

    private func parseAnx4DataSelector(from payload: Data) -> UInt16? {
        let bytes = [UInt8](payload)
        guard bytes.count >= 14 else { return nil }
        let candidates = [
            UInt16(bytes[8]) << 8 | UInt16(bytes[9]),
            UInt16(bytes[12]) << 8 | UInt16(bytes[13])
        ]
        return candidates.first(where: { $0 != 0 })
    }

    private func resetAnx4LocalSessionSelector() {
        var selector: UInt16 = 0
        repeat {
            selector = UInt16.random(in: 0x0100...0xFFEF)
        } while selector == 0
        anx4LocalSessionSelector = selector
        anx4NextSelector = selector &+ 1
        if anx4NextSelector == 0 {
            anx4NextSelector = 1
        }
        anx4PreviousSelector = selector
        anx4OldestSelector = selector
        anx4OpaqueRequestCounter = 0

        var prefix = Data(repeating: 0, count: 8)
        prefix.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        anx4OpaqueRequestPrefix = prefix
    }

    private func advanceAnx4Selectors() -> (current: UInt16, previous: UInt16, oldest: UInt16) {
        let previous = anx4PreviousSelector
        let oldest = anx4OldestSelector
        let current = anx4NextSelector
        anx4OldestSelector = previous
        anx4PreviousSelector = current
        anx4NextSelector = current &+ 1
        if anx4NextSelector == 0 {
            anx4NextSelector = 1
        }
        return (current, previous, oldest)
    }

    private func sendAnx4Payload(_ payload: Data, host: String, event: String) {
        guard let conn = udpConnection else { return }
        let shouldLog = Self.shouldEmitConsoleLogs(for: device)
        let endpoint = activeUdpEndpointDescription(fallbackHost: host)
        logAnx4PacketSummary(payload, direction: "out")
        conn.send(content: payload, completion: .contentProcessed { [weak self] error in
            if let error {
                let errorMessage = error.localizedDescription
                DispatchQueue.main.async {
                    self?.lastError = errorMessage
                }
                if shouldLog {
                    print("[Shure] ANX4 UDP \(event) failed — \(errorMessage)")
                }
                Task { @MainActor in
                    RelayDiagnosticsStore.shared.recordShureTrace("module \(event)_failed \(endpoint) error=\(errorMessage)")
                }
            } else {
                Task { @MainActor in
                    RelayDiagnosticsStore.shared.recordShureTrace("module \(event)_sent \(endpoint) bytes=\(payload.count)")
                }
            }
        })
    }

    private func sendAnx4BootstrapFollowups(
        responderCID: UUID,
        remoteSessionSelector: UInt16,
        remoteQuerySelector: UInt16,
        remoteDataSelector: UInt16
    ) {
        guard let conn = udpConnection else { return }
        let senderCID = ShureAnx4Handshake.senderCID(sessionId: anx4SessionId)
        let host = device?.host ?? "unknown"
        let shouldLog = Self.shouldEmitConsoleLogs(for: device)
        let bootstrapQuery = advanceAnx4Selectors()
        let payloads = [
            ShureAnx4Handshake.sessionAck(
                senderCID: senderCID,
                targetCID: responderCID,
                localSessionSelector: anx4LocalSessionSelector,
                remoteQuerySelector: remoteQuerySelector,
                remoteDataSelector: remoteDataSelector
            ),
            ShureAnx4Handshake.bootstrapFrame2(
                senderCID: senderCID,
                localSessionSelector: anx4LocalSessionSelector,
                currentSelector: bootstrapQuery.current,
                previousSelector: bootstrapQuery.previous,
                oldestSelector: bootstrapQuery.oldest,
                remoteQuerySelector: remoteQuerySelector,
                remoteDataSelector: remoteDataSelector
            )
        ]
        anx4FollowupsSent = true
        RelayDiagnosticsStore.shared.recordShureTrace("module udp_followups_start \(host):57383 payloads=\(payloads.count) remoteSession=0x\(String(remoteSessionSelector, radix: 16)) remoteQuery=0x\(String(remoteQuerySelector, radix: 16)) remoteData=0x\(String(remoteDataSelector, radix: 16)) targetCID=\(responderCID.uuidString)")
        for payload in payloads {
            logAnx4PacketSummary(payload, direction: "out")
            conn.send(content: payload, completion: .contentProcessed { [weak self] error in
                guard let error else {
                    Task { @MainActor in
                        RelayDiagnosticsStore.shared.recordShureTrace("module udp_followup_sent \(host):57383 bytes=\(payload.count)")
                    }
                    return
                }
                let errorMessage = error.localizedDescription
                DispatchQueue.main.async {
                    self?.lastError = errorMessage
                }
                if shouldLog {
                    print("[Shure] ANX4 UDP follow-up send failed — \(errorMessage)")
                }
                Task { @MainActor in
                    RelayDiagnosticsStore.shared.recordShureTrace("module udp_followup_failed \(host):57383 error=\(errorMessage)")
                }
            })
        }
    }

    private func startAnx4TelemetryLoop(
        host: String,
        responderCID: UUID,
        remoteQuerySelector: UInt16,
        remoteDataSelector: UInt16
    ) {
        anx4TelemetryLoopTask?.cancel()
        let expectedIdentity = currentConnectionIdentity
        anx4TelemetryLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var iteration = 0
            while !Task.isCancelled {
                guard self.currentConnectionIdentity == expectedIdentity, self.udpConnection != nil else { return }
                let senderCID = ShureAnx4Handshake.senderCID(sessionId: self.anx4SessionId)
                let useOpaquePhase = self.anx4UseOpaqueRequestPhase
                let deviceSnapshot = self.device
                let useUlxdFastTelemetry = deviceSnapshot.map(Self.isFastUdpTelemetryCapableDevice) ?? false

                let pollSelector = self.advanceAnx4Selectors()
                let pollSubtype: UInt8 = useOpaquePhase ? 0x0A : ((iteration % 2 == 0) ? 0x09 : 0x0A)
                let pollFrame = ShureAnx4Handshake.bootstrapFrame1(
                    senderCID: senderCID,
                    localSessionSelector: self.anx4LocalSessionSelector,
                    currentSelector: pollSelector.current,
                    previousSelector: pollSelector.previous,
                    oldestSelector: pollSelector.oldest,
                    subtype: pollSubtype
                )
                self.sendAnx4Payload(pollFrame, host: host, event: "udp_poll")

                if useOpaquePhase {
                    let requestSelector = self.advanceAnx4Selectors()
                    switch self.anx4WWBPhase {
                    case .request2A:
                        let opaqueFrame = ShureAnx4Handshake.opaqueRequestFrame(
                            senderCID: senderCID,
                            localSessionSelector: self.anx4LocalSessionSelector,
                            currentSelector: requestSelector.current,
                            previousSelector: requestSelector.previous,
                            oldestSelector: requestSelector.oldest,
                            subVectorLength: 0x2A,
                            body: self.nextAnx4OpaqueRequestBody(subPDU: 0x2A, bodyLength: 28)
                        )
                        self.sendAnx4Payload(opaqueFrame, host: host, event: "udp_opaque")
                        self.anx4Phase2ASendCount += 1
                        if self.anx4Phase2ASendCount >= 3 {
                            self.anx4WWBPhase = .request5A
                            RelayDiagnosticsStore.shared.recordShureTrace(
                                "module udp_wwb_phase_promote \(host):57383 stage=0x5a reason=fallback_after_0x2a"
                            )
                        }
                    case .request5A:
                        let request5A = ShureAnx4Handshake.opaqueRequestFrame(
                            senderCID: senderCID,
                            localSessionSelector: self.anx4LocalSessionSelector,
                            currentSelector: requestSelector.current,
                            previousSelector: requestSelector.previous,
                            oldestSelector: requestSelector.oldest,
                            subVectorLength: 0x5A,
                            body: self.nextAnx4OpaqueRequestBody(subPDU: 0x5A, bodyLength: 76)
                        )
                        self.sendAnx4Payload(request5A, host: host, event: "udp_opaque")
                        self.anx4WWBPhase = .request60
                        RelayDiagnosticsStore.shared.recordShureTrace(
                            "module udp_wwb_phase_promote \(host):57383 stage=0x60 reason=sent_0x5a"
                        )
                    case .request60:
                        let request60 = ShureAnx4Handshake.opaqueRequestFrame(
                            senderCID: senderCID,
                            localSessionSelector: self.anx4LocalSessionSelector,
                            currentSelector: requestSelector.current,
                            previousSelector: requestSelector.previous,
                            oldestSelector: requestSelector.oldest,
                            subVectorLength: 0x60,
                            body: self.nextAnx4OpaqueRequestBody(subPDU: 0x60, bodyLength: 82)
                        )
                        self.sendAnx4Payload(request60, host: host, event: "udp_opaque")
                        self.anx4WWBPhase = .replayCapture
                        self.anx4CaptureReplayIndex = 0
                        RelayDiagnosticsStore.shared.recordShureTrace(
                            "module udp_wwb_phase_promote \(host):57383 stage=capture_replay reason=sent_0x60"
                        )
                    case .replayCapture:
                        if let replayStage = self.nextAnx4CaptureReplayStage() {
                            let replayFrame = ShureAnx4Handshake.opaqueRequestFrame(
                                senderCID: senderCID,
                                localSessionSelector: self.anx4LocalSessionSelector,
                                currentSelector: requestSelector.current,
                                previousSelector: requestSelector.previous,
                                oldestSelector: requestSelector.oldest,
                                subVectorLength: replayStage.subVectorLength,
                                body: Data(replayStage.body)
                            )
                            self.sendAnx4Payload(replayFrame, host: host, event: "udp_opaque")
                            RelayDiagnosticsStore.shared.recordShureTrace(
                                "module udp_wwb_phase_promote \(host):57383 stage=\(replayStage.label) reason=capture_replay"
                            )
                        } else {
                            self.anx4WWBPhase = .steady60
                            RelayDiagnosticsStore.shared.recordShureTrace(
                                "module udp_wwb_phase_promote \(host):57383 stage=steady_0x60 reason=capture_replay_complete"
                            )
                        }
                    case .steady60:
                        if iteration.isMultiple(of: 4) {
                            let request60 = ShureAnx4Handshake.opaqueRequestFrame(
                                senderCID: senderCID,
                                localSessionSelector: self.anx4LocalSessionSelector,
                                currentSelector: requestSelector.current,
                                previousSelector: requestSelector.previous,
                                oldestSelector: requestSelector.oldest,
                                subVectorLength: 0x60,
                                body: self.nextAnx4OpaqueRequestBody(subPDU: 0x60, bodyLength: 82)
                            )
                            self.sendAnx4Payload(request60, host: host, event: "udp_opaque")
                        }
                    case .inactive:
                        break
                    }
                } else {
                    let querySelector = self.advanceAnx4Selectors()
                    let queryFrame = ShureAnx4Handshake.bootstrapFrame2(
                        senderCID: senderCID,
                        localSessionSelector: self.anx4LocalSessionSelector,
                        currentSelector: querySelector.current,
                        previousSelector: querySelector.previous,
                        oldestSelector: querySelector.oldest,
                        remoteQuerySelector: remoteQuerySelector,
                        remoteDataSelector: remoteDataSelector
                    )
                    self.sendAnx4Payload(queryFrame, host: host, event: "udp_query")

                    // Send the WWB-shaped property-list poll a couple of
                    // times per second. This is the request that triggers
                    // the device's 79-byte meter bursts which our existing
                    // 0x10/0x07/0x02 and 0x10/0x0a/0x02 parser already
                    // decodes for audio + RF levels.
                    if iteration % 4 == 0 {
                        let propertySelector = self.advanceAnx4Selectors()
                        let propertyFrame = ShureAnx4Handshake.propertyAddressListFrame(
                            senderCID: senderCID,
                            localSessionSelector: self.anx4LocalSessionSelector,
                            currentSelector: propertySelector.current,
                            previousSelector: propertySelector.previous,
                            oldestSelector: propertySelector.oldest,
                            propertyAddresses: self.device.map(self.fastUdpPropertyAddresses(for:)) ?? ShureAnx4Handshake.defaultPropertyAddresses
                        )
                        self.sendAnx4Payload(propertyFrame, host: host, event: "udp_property_list")
                    }
                }

                if !useOpaquePhase {
                    if useUlxdFastTelemetry {
                        if iteration % 2 == 0 {
                            let activationSelector = self.advanceAnx4Selectors()
                            let activationFrame = ShureAnx4Handshake.singlePropertyRequestFrame(
                                senderCID: senderCID,
                                localSessionSelector: self.anx4LocalSessionSelector,
                                currentSelector: activationSelector.current,
                                previousSelector: activationSelector.previous,
                                oldestSelector: activationSelector.oldest,
                                propertyAddress: ShureAnx4Handshake.ulxdFastBurstActivationAddress
                            )
                            self.sendAnx4Payload(activationFrame, host: host, event: "udp_ulxd_activate")
                        }

                        if iteration % 2 == 1, let deviceSnapshot {
                            let channelIndices = self.fastUdpChannelIndices(for: deviceSnapshot)
                            if !channelIndices.isEmpty {
                                let channelIndex = channelIndices[(iteration / 2) % channelIndices.count]
                                let propertyPair = self.fastUdpRfPropertyPair(for: channelIndex)
                                let requestSelector = self.advanceAnx4Selectors()
                                let subtype: UInt8 = (iteration % 4 == 1) ? 0x07 : 0x01
                                let rfPairFrame = ShureAnx4Handshake.pairedPropertyRequestFrame(
                                    senderCID: senderCID,
                                    localSessionSelector: self.anx4LocalSessionSelector,
                                    currentSelector: requestSelector.current,
                                    previousSelector: requestSelector.previous,
                                    oldestSelector: requestSelector.oldest,
                                    subtype: subtype,
                                    firstPropertyAddress: propertyPair.first,
                                    secondPropertyAddress: propertyPair.second
                                )
                                self.sendAnx4Payload(rfPairFrame, host: host, event: "udp_ulxd_rf_pair")
                            }
                        }
                    } else if iteration % 3 == 0 {
                        let requestSelector = self.advanceAnx4Selectors()
                        let requestSubtype: UInt8 = (iteration % 6 == 0) ? 0x07 : 0x0C
                        let telemetryFrame = ShureAnx4Handshake.telemetryRequestFrame(
                            senderCID: senderCID,
                            localSessionSelector: self.anx4LocalSessionSelector,
                            currentSelector: requestSelector.current,
                            previousSelector: requestSelector.previous,
                            oldestSelector: requestSelector.oldest,
                            subtype: requestSubtype
                        )
                        self.sendAnx4Payload(telemetryFrame, host: host, event: "udp_telemetry")
                    }
                }

                iteration += 1
                try? await Task.sleep(for: .milliseconds(125))
            }
        }
    }

    private func nextAnx4OpaqueRequestBody(subPDU: UInt8, bodyLength: Int) -> Data {
        if let templateBody = nextAnx4ObservedTemplateBody(subPDU: subPDU, expectedLength: bodyLength) {
            return templateBody
        }

        var body = Data()
        body.append(anx4OpaqueRequestPrefix)

        let counterBytes = withUnsafeBytes(of: anx4OpaqueRequestCounter.bigEndian) { Data($0) }
        body.append(counterBytes)

        var digestInput = Data()
        digestInput.append(subPDU)
        digestInput.append(UInt8(bodyLength & 0xFF))
        digestInput.append(anx4OpaqueRequestPrefix)
        digestInput.append(counterBytes)
        digestInput.append(contentsOf: anx4SessionId)
        digestInput.append(contentsOf: [
            UInt8((anx4LocalSessionSelector >> 8) & 0xFF),
            UInt8(anx4LocalSessionSelector & 0xFF)
        ])

        let remainingBytes = max(0, bodyLength - body.count)
        var tail = Data()
        var blockIndex: UInt8 = 0
        while tail.count < remainingBytes {
            var blockInput = digestInput
            blockInput.append(blockIndex)
            tail.append(Data(SHA256.hash(data: blockInput)))
            blockIndex &+= 1
        }
        body.append(tail.prefix(remainingBytes))

        anx4OpaqueRequestCounter &+= 1
        return body
    }

    private func nextAnx4ObservedTemplateBody(subPDU: UInt8, expectedLength: Int) -> Data? {
        let template: [UInt8]?
        switch subPDU {
        case 0x2A:
            let templates: [[UInt8]] = [
                [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x9B, 0x34, 0xD7, 0x94, 0x89, 0x1D, 0x11, 0xE8,
                    0x8B, 0x9A, 0xC2, 0x6A
                ],
                [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
                    0x78, 0x9A, 0x5A, 0x48, 0xD2, 0x1F, 0x39, 0xED,
                    0x64, 0x73, 0xCB, 0xD6
                ],
                [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
                    0xE6, 0x4D, 0x4F, 0xFA, 0x79, 0x93, 0xFE, 0x4E,
                    0x2D, 0x94, 0xD0, 0x2C
                ]
            ]
            guard anx4Template2AIndex < templates.count else { return nil }
            template = templates[anx4Template2AIndex]
            anx4Template2AIndex += 1
        case 0x5A:
            let templates: [[UInt8]] = [
                [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02,
                    0xC8, 0x01, 0xB4, 0xFF, 0x97, 0xF6, 0xBE, 0x07,
                    0x27, 0xC0, 0x9C, 0x35, 0xD6, 0x1C, 0x7C, 0xEA,
                    0xA4, 0x25, 0x4F, 0xFB, 0xC7, 0x50, 0x57, 0x0D,
                    0x60, 0xC4, 0x23, 0xCA, 0x54, 0xC3, 0xBB, 0x17,
                    0x48, 0xAC, 0x7D, 0x00, 0x4A, 0x62, 0x59, 0xC5,
                    0x6F, 0xB3, 0xEB, 0x18, 0xA6, 0x56, 0xD9, 0xD7,
                    0x22, 0x88, 0x7E, 0xE8, 0x43, 0x90, 0x50, 0x6F,
                    0x69, 0x07, 0x2D, 0xF6
                ]
            ]
            guard anx4Template5AIndex < templates.count else { return nil }
            template = templates[anx4Template5AIndex]
            anx4Template5AIndex += 1
        case 0x60:
            let templates: [[UInt8]] = [
                [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05,
                    0x32, 0xB3, 0x1C, 0x69, 0xF0, 0xC3, 0x5B, 0xF4,
                    0xCE, 0xF3, 0x69, 0x54, 0x3A, 0xC1, 0x63, 0x36,
                    0xBD, 0xEA, 0x05, 0x57, 0xF8, 0x31, 0x1E, 0xDA,
                    0x77, 0xEF, 0x0D, 0xEB, 0x8D, 0xD2, 0x16, 0xDB,
                    0x44, 0xF7, 0x17, 0xA9, 0xE8, 0xBE, 0xDA, 0x47,
                    0x63, 0x0E, 0x90, 0x3D, 0x40, 0x51, 0xB8, 0x43,
                    0x69, 0xC4, 0xF3, 0xE1, 0x16, 0x76, 0xD3, 0x43,
                    0xA8, 0xE3, 0xC9, 0xDF, 0x37, 0xC4, 0x94, 0x10,
                    0x53, 0xD2
                ],
                [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x09,
                    0xD8, 0x26, 0x58, 0xD5, 0x9D, 0x34, 0x9D, 0x87,
                    0x91, 0x35, 0x6F, 0xE5, 0x2F, 0x1A, 0x46, 0x5F,
                    0xD4, 0xDF, 0xF7, 0xC1, 0x09, 0x30, 0xB5, 0x3D,
                    0xDD, 0xE9, 0xF2, 0x78, 0x7E, 0x76, 0x3F, 0xDA,
                    0x7E, 0x40, 0xB7, 0x36, 0xDF, 0x61, 0x22, 0x80,
                    0xA9, 0xCB, 0xF4, 0x17, 0xAD, 0x45, 0x8C, 0xB5,
                    0x54, 0x8F, 0xB1, 0x5E, 0x12, 0x6A, 0x0F, 0x70,
                    0x61, 0x46, 0xE2, 0x71, 0x47, 0x87, 0xB0, 0x8F,
                    0x4C, 0x3E
                ]
            ]
            guard anx4Template60Index < templates.count else { return nil }
            template = templates[anx4Template60Index]
            anx4Template60Index += 1
        default:
            return nil
        }

        guard let template, template.count == expectedLength else { return nil }
        return Data(template)
    }

    private func nextAnx4CaptureReplayStage() -> Anx4OpaqueReplayStage? {
        let stages: [Anx4OpaqueReplayStage] = [
            Anx4OpaqueReplayStage(
                label: "0xf2",
                subVectorLength: 0x00F2,
                body: [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0D,
                    0x5C, 0x25, 0xDF, 0xAC, 0x17, 0x9C, 0x1D, 0x7A,
                    0x06, 0x74, 0xCD, 0xD0, 0x3C, 0x42, 0x7E, 0xAD,
                    0x2D, 0xB1, 0x3A, 0x5B, 0xD4, 0x3E, 0xED, 0xF0,
                    0xA0, 0x10, 0x8F, 0xD9, 0x80, 0x28, 0x02, 0xF2,
                    0xBC, 0x5E, 0x18, 0x8E, 0xB9, 0x04, 0x96, 0xB3,
                    0x87, 0xC1, 0xE8, 0xEB, 0xDB, 0xEF, 0x4E, 0x1F,
                    0x57, 0x5C, 0xB4, 0xFE, 0xFD, 0x75, 0xC0, 0x62,
                    0xFA, 0x2B, 0x02, 0x71, 0x45, 0x2C, 0xF9, 0xEA,
                    0x4F, 0x37, 0x8E, 0x6C, 0x77, 0xB5, 0x10, 0x14,
                    0x8C, 0xC6, 0xA3, 0xB1, 0xD8, 0xCC, 0xF6, 0x4C,
                    0xDE, 0xC8, 0x39, 0x3E, 0x40, 0xB8, 0x04, 0xE5,
                    0x51, 0xF4, 0x3D, 0xED, 0x4F, 0x9C, 0x0A, 0x6C,
                    0xF2, 0x01, 0x77, 0xAF, 0x1F, 0x6F, 0x24, 0x93,
                    0x61, 0x78, 0xE1, 0x95, 0x2D, 0x62, 0x87, 0x40,
                    0x90, 0x07, 0x58, 0x56, 0x4C, 0x1D, 0x9D, 0x02,
                    0x13, 0x07, 0xEA, 0x8F, 0x4D, 0x3E, 0xDA, 0xAF,
                    0x09, 0x85, 0x30, 0x5C, 0x36, 0x88, 0x3E, 0x65,
                    0x4B, 0x21, 0x20, 0xF1, 0x0C, 0x87, 0x34, 0xED,
                    0x1A, 0xD2, 0x91, 0xE9, 0xEA, 0x2D, 0x58, 0x20,
                    0x65, 0x64, 0xB6, 0x95, 0x75, 0x35, 0x1A, 0x65,
                    0x9A, 0xA9, 0x93, 0x18, 0x6A, 0x1A, 0x1E, 0x0B,
                    0x59, 0x26, 0xCC, 0x05, 0xB3, 0x69, 0x74, 0x91,
                    0xC3, 0x76, 0xE0, 0xD7, 0x4F, 0x90, 0x49, 0x0D,
                    0xC5, 0x8D, 0x36, 0x57, 0x6F, 0xB7, 0x94, 0x15,
                    0x6B, 0xA1, 0x55, 0xA7, 0x66, 0x60, 0xB9, 0x80,
                    0x6D, 0x84, 0x5E, 0xEA, 0x13, 0xD6, 0x90, 0x43,
                    0xFC, 0x01, 0xEA, 0x44
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x30",
                subVectorLength: 0x0030,
                body: [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1D,
                    0xFE, 0xD7, 0xC0, 0x34, 0x03, 0x81, 0x4E, 0x51,
                    0xB9, 0x32, 0x81, 0x01, 0x89, 0x71, 0x5D, 0x7C,
                    0x92, 0x5C
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x48",
                subVectorLength: 0x0048,
                body: [
                    0x31, 0xC8, 0x40, 0xD5, 0xD2, 0x6F, 0xA1, 0x62,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1E,
                    0x9D, 0xFD, 0xDB, 0x1C, 0x41, 0x02, 0x8D, 0xC3,
                    0xC4, 0xC9, 0xC6, 0x96, 0xE3, 0x8F, 0x04, 0x8B,
                    0x98, 0x0C, 0x32, 0xE6, 0xAF, 0x1B, 0x80, 0x86,
                    0x44, 0x86, 0xB9, 0x49, 0x29, 0x02, 0xEF, 0x84,
                    0xC5, 0xD9, 0x06, 0x7B, 0x7E, 0xE9, 0x40, 0xC2,
                    0xD4, 0x80
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x5c",
                subVectorLength: 0x005C,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x23, 0x7F,
                    0xC8, 0xEE, 0xE4, 0xF9, 0xE2, 0xE1, 0xE1, 0x55,
                    0xB5, 0x97, 0x14, 0x60, 0x3C, 0x96, 0xD5, 0x6F,
                    0xBF, 0x75, 0x7E, 0xAD, 0xAD, 0x09, 0x18, 0x1B,
                    0x11, 0xAA, 0x60, 0x48, 0xD4, 0x5C, 0x13, 0xEC,
                    0x2A, 0x14, 0x24, 0x6A, 0x72, 0xE7, 0x34, 0xDD,
                    0x0A, 0xD2, 0x49, 0x5F, 0x8E, 0x11, 0xE4, 0x0B,
                    0x18, 0x20, 0x7E, 0x49, 0x14, 0x21, 0xE8, 0xE7,
                    0xF6, 0x6A, 0x67, 0xF9, 0x0E
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x2b",
                subVectorLength: 0x002B,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x27, 0xDE,
                    0x8B, 0x49, 0x06, 0x4A, 0x94, 0x38, 0xC9, 0xF9,
                    0x49, 0x81, 0xA1, 0xA3
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x90",
                subVectorLength: 0x0090,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0xE2,
                    0x8F, 0x93, 0x2D, 0xEC, 0x87, 0x07, 0x73, 0x9E,
                    0x2F, 0xF3, 0x49, 0x17, 0xB9, 0x04, 0x99, 0x6F,
                    0x36, 0xF5, 0xF7, 0xE9, 0x71, 0x8E, 0x2A, 0xFF,
                    0x5B, 0x83, 0x4A, 0x67, 0xD6, 0x33, 0x04, 0x8B,
                    0x7B, 0xD9, 0x50, 0xEC, 0x03, 0x44, 0x4F, 0xA0,
                    0x90, 0x41, 0xF1, 0xCC, 0x75, 0xB2, 0xE3, 0xE4,
                    0xF0, 0x16, 0xD6, 0xB1, 0x16, 0x4F, 0x0F, 0x7A,
                    0xE1, 0xBD, 0x6B, 0x65, 0xEB, 0x0F, 0x9F, 0xD5,
                    0xB4, 0x5A, 0xF8, 0x4E, 0xB6, 0xAA, 0x66, 0xED,
                    0x5B, 0xA2, 0x02, 0x9A, 0xD9, 0x07, 0xCC, 0xAF,
                    0x5D, 0xE7, 0x71, 0xD7, 0xB6, 0x92, 0x7E, 0x5A,
                    0x12, 0x02, 0xF7, 0xA8, 0xBE, 0xC8, 0x2F, 0x83,
                    0xE3, 0x43, 0xC6, 0x7F, 0x96, 0xFA, 0x1D, 0x39,
                    0x1A, 0xD0, 0x06, 0xDA, 0x91, 0x6D, 0x40, 0x0F,
                    0xFD
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x7c",
                subVectorLength: 0x007C,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2E, 0xAB,
                    0xE1, 0xA5, 0xFA, 0x61, 0xDE, 0xA9, 0x6B, 0x7A,
                    0xD5, 0x82, 0xB2, 0x4F, 0x31, 0xAB, 0xA1, 0x39,
                    0x0A, 0x43, 0x73, 0x4B, 0x48, 0xEE, 0x80, 0x19,
                    0x53, 0xE5, 0x9B, 0xC6, 0x20, 0x2E, 0x30, 0x25,
                    0xB0, 0x6B, 0x25, 0xC2, 0x07, 0xF0, 0x61, 0x11,
                    0x7E, 0xD2, 0xA4, 0x95, 0xAF, 0x55, 0xC1, 0xA4,
                    0x5A, 0x45, 0xF4, 0x8E, 0xD2, 0x70, 0x49, 0xF6,
                    0x48, 0x0E, 0xA1, 0x1C, 0x0A, 0x04, 0x34, 0xAF,
                    0x38, 0x4F, 0xCD, 0xBE, 0xBE, 0xD6, 0xA2, 0xF1,
                    0xB5, 0x71, 0xE4, 0x9B, 0x71, 0x86, 0x0E, 0x52,
                    0xBD, 0xE3, 0x88, 0x28, 0x50, 0x87, 0xDB, 0xAE,
                    0x58, 0x73, 0x11, 0x6A, 0x9C
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x84",
                subVectorLength: 0x0084,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x52,
                    0xC2, 0x42, 0x9F, 0x13, 0x45, 0x11, 0x68, 0x7A,
                    0x8A, 0xCE, 0xBA, 0xE9, 0xCB, 0xD2, 0x0D, 0xE0,
                    0x3E, 0x77, 0x28, 0xFD, 0x45, 0xAA, 0x45, 0x07,
                    0xD5, 0x80, 0x91, 0x30, 0x52, 0xD3, 0x98, 0x35,
                    0x7D, 0xC3, 0x22, 0x6E, 0xD2, 0x29, 0x5A, 0xD0,
                    0xA8, 0x79, 0xC1, 0xB4, 0x86, 0x12, 0xBF, 0xDC,
                    0xF2, 0xB1, 0x50, 0xB8, 0x1C, 0x0F, 0xDF, 0x37,
                    0x14, 0x7B, 0x4C, 0x23, 0x4E, 0x26, 0xE3, 0x67,
                    0x92, 0xC1, 0x7B, 0x92, 0x7F, 0xA3, 0x44, 0x89,
                    0xBE, 0x3F, 0x60, 0x21, 0xB6, 0x6B, 0xB4, 0x43,
                    0x33, 0x50, 0x95, 0x8B, 0xAF, 0x83, 0x7A, 0x44,
                    0xD3, 0x77, 0x6C, 0x29, 0xD8, 0xAF, 0x9C, 0x3A,
                    0xE4, 0x97, 0xCD, 0x7C, 0x25
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x88",
                subVectorLength: 0x0088,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3A, 0xBF,
                    0x29, 0x57, 0xD0, 0xE8, 0x93, 0x29, 0x2A, 0x8F,
                    0xB9, 0xD9, 0x3A, 0xD2, 0x3E, 0x78, 0x3D, 0x54,
                    0x93, 0x67, 0xFB, 0xD1, 0xB1, 0xC8, 0xCD, 0x57,
                    0x09, 0xB8, 0xF5, 0x9B, 0xAB, 0xC3, 0xE1, 0xC8,
                    0x45, 0x6C, 0x02, 0x0C, 0x07, 0xE4, 0xAE, 0xA4,
                    0xFC, 0xAB, 0x08, 0x04, 0x46, 0x32, 0x5D, 0x21,
                    0x95, 0xFA, 0x88, 0x82, 0x86, 0x0A, 0x23, 0xCE,
                    0x25, 0x5F, 0x61, 0xEC, 0x1B, 0x8E, 0x83, 0x2C,
                    0x2E, 0x6F, 0xDD, 0x65, 0x6B, 0x42, 0x95, 0xF9,
                    0xDB, 0xD3, 0x7B, 0x16, 0x4C, 0xB9, 0xF5, 0xFF,
                    0xD1, 0x15, 0xB8, 0x73, 0x47, 0xDE, 0xD9, 0x1B,
                    0xFC, 0xB6, 0x97, 0x88, 0x44, 0x84, 0x89, 0xEF,
                    0xF2, 0x2A, 0x1D, 0x0B, 0x60, 0x31, 0xE5, 0x50,
                    0xF7
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0x11d",
                subVectorLength: 0x011D,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41, 0x72,
                    0x12, 0x91, 0xB0, 0xFD, 0xAC, 0xF1, 0xE2, 0xA6,
                    0x4C, 0xF9, 0x40, 0xA0, 0x95, 0x4B, 0x36, 0xED,
                    0x22, 0x4B, 0xF8, 0xD7, 0x30, 0xD5, 0xD5, 0xFD,
                    0xE0, 0x9A, 0xD1, 0x41, 0x78, 0xF4, 0x6D, 0x9B,
                    0x95, 0x72, 0xE5, 0x7C, 0xC3, 0xCA, 0xE8, 0x43,
                    0xC1, 0xED, 0x9E, 0xA4, 0x66, 0xE4, 0x57, 0x62,
                    0xCB, 0x06, 0xB1, 0x4C, 0x63, 0x45, 0x09, 0x77,
                    0xAD, 0x64, 0xC7, 0xDE, 0xDC, 0x36, 0xA2, 0x41,
                    0xE0, 0xDE, 0x6D, 0xD5, 0x40, 0x52, 0x64, 0x8A,
                    0xEA, 0x97, 0x41, 0xC9, 0xD5, 0x49, 0xB2, 0xF7,
                    0xA5, 0x1F, 0xE6, 0xF4, 0xAB, 0x7C, 0xD2, 0x56,
                    0xFC, 0xCE, 0xD5, 0x35, 0x8A, 0x8F, 0x33, 0x6C,
                    0x03, 0x96, 0xEB, 0xC6, 0xF0, 0x87, 0x6F, 0x83,
                    0x3F, 0xA4, 0x4C, 0xF2, 0xDD, 0x9B, 0xF2, 0x9C,
                    0x92, 0x61, 0xD1, 0xF2, 0x23, 0x6D, 0xF5, 0x60,
                    0x65, 0xAA, 0x94, 0x11, 0x23, 0xB6, 0x4E, 0x8D,
                    0x32, 0x13, 0x2A, 0xB0, 0xEA, 0x18, 0x64, 0xCD,
                    0x53, 0x1D, 0x63, 0xF8, 0xD0, 0x0F, 0xF6, 0xD7,
                    0xB8, 0x62, 0xBA, 0x53, 0x0F, 0xB3, 0x80, 0x93,
                    0xDF, 0xFA, 0xA5, 0x78, 0xA7, 0xBE, 0x18, 0xF0,
                    0x22, 0x1C, 0x63, 0xE9, 0x82, 0xEA, 0xEE, 0x8E,
                    0x6A, 0x23, 0x2F, 0x96, 0x73, 0x2A, 0x85, 0xC6,
                    0x71, 0x7C, 0xD8, 0x7E, 0x53, 0xCF, 0xA3, 0x49,
                    0x4C, 0x25, 0xB2, 0xCD, 0xEA, 0x45, 0x3D, 0x44,
                    0x12, 0x8C, 0x14, 0x9E, 0x26, 0x97, 0xAF, 0x62
                ]
            ),
            Anx4OpaqueReplayStage(
                label: "0xad",
                subVectorLength: 0x00AD,
                body: [
                    0x52, 0x74, 0xD5, 0xF9, 0x12, 0x9C, 0x48, 0x73,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x50, 0x3C,
                    0x1E, 0x51, 0x0F, 0x5D, 0x4D, 0xE7, 0x21, 0x69,
                    0x13, 0xA7, 0x40, 0x77, 0x39, 0x55, 0xCD, 0xA5,
                    0x4B, 0x38, 0xD7, 0xD0, 0x21, 0x52, 0xC2, 0xD3,
                    0xF5, 0xEC, 0xB7, 0x9F, 0xC6, 0xD6, 0x66, 0x84,
                    0xC1, 0x96, 0xFD, 0x1D, 0xF2, 0x6F, 0x8E, 0x1A,
                    0x9D, 0xAA, 0xAC, 0x78, 0xD7, 0xC8, 0x92, 0x79,
                    0x3B, 0x1C, 0x39, 0xF4, 0x5B, 0x74, 0xDB, 0x5D,
                    0x73, 0x97, 0x7D, 0x0A, 0xC4, 0x1F, 0xC1, 0xDE,
                    0xED, 0x09, 0x6E, 0x50, 0xD2, 0xA2, 0x45, 0x31,
                    0x38, 0x17, 0x08, 0xC2, 0x3A, 0x02, 0xB4, 0x9A,
                    0x4F, 0xB0, 0xE5, 0xA9, 0x29, 0x97, 0xAE, 0xA5,
                    0x71, 0x59, 0x84, 0x39, 0x23, 0xE5, 0x25, 0x16,
                    0x83, 0x72, 0x51, 0x08, 0xD5, 0x7A, 0x67, 0x05,
                    0x7A, 0xDC, 0xBF, 0xC6, 0x7A, 0x28, 0xE2, 0x66,
                    0x35, 0xAC, 0x73, 0xAE, 0xE7, 0x33, 0x77, 0x67,
                    0x37, 0x78, 0x28, 0x34, 0xC5, 0x31, 0x8A, 0x0D,
                    0x33, 0xDF, 0x91, 0xFC, 0xAB, 0x78, 0x48, 0x82,
                    0x4D, 0x7F, 0xC2, 0x23, 0x81, 0xAC
                ]
            )
        ]

        guard anx4CaptureReplayIndex < stages.count else { return nil }
        defer { anx4CaptureReplayIndex += 1 }
        return stages[anx4CaptureReplayIndex]
    }

    // MARK: - Commands

    enum SendPriority {
        /// For commands driving a channel the user is actively watching
        /// right now -- a single-tile module's own refresh calls. These
        /// jump ahead of anything already queued at `.normal`.
        case high
        /// Everything else: Overview's background polling for channels
        /// nobody has a tile open on, batch refreshes, broadcasts.
        case normal
    }

    /// Enqueues `body` on this device's outgoing send queue rather than
    /// sending it immediately.
    ///
    /// Every call site used to send straight to the socket, and several of
    /// them (sendMediumPriorityRefresh, the TCP startup sequence,
    /// sendPacedCommands) separately paced their OWN multi-command bursts
    /// apart to avoid the receiver's line parser choking on commands the
    /// OS/TCP stack coalesced into one packet. That pacing only protected
    /// each function's own burst -- it didn't protect against two DIFFERENT
    /// callers (e.g. a single-tile view's own poll loop and the Overview
    /// shared loop) independently pacing themselves at the same time,
    /// whose interleaved sends could still land closer together than the
    /// proven-safe gap on the wire. Confirmed on a live capture with two
    /// single-tile views open alongside Overview on the same AD4Q: 1,527
    /// REP ERR replies and a continuously climbing dropped-update count in
    /// ~90 seconds, despite every individual caller already pacing itself.
    /// A shared queue, fed by every caller, is the only way to guarantee
    /// spacing holds regardless of how many things want to talk to this
    /// device at once.
    ///
    /// Hard ceiling on each priority queue's length, independent of
    /// whatever is producing into it or how the drain loop shares time
    /// between the two. Every fix tonight aimed at keeping production
    /// within what the 150ms-per-command ceiling can drain, and each one
    /// got outpaced by some other source in turn (stale-presence
    /// overproduction, then medium-refresh, then residual growth even with
    /// drain-loop fairness) -- confirmed live during an actual show, the
    /// normal queue was still sitting at 400+ and climbing, old enough that
    /// the battery/mute values behind those commands were long since
    /// meaningless by the time they could ever reach the wire, while
    /// competing with genuinely time-sensitive audio-level polling for the
    /// same connection. A hard cap makes this bounded no matter what any
    /// individual producer does: a command this far back in line is stale
    /// enough that sending it wouldn't help anyway, so dropping the oldest
    /// excess is strictly better than queueing behind it forever.
    ///
    /// 40 was too tight: startTcpStartupSequence enqueues its entire
    /// one-time startup burst (GET 0 ALL, then ~17 per-channel commands --
    /// name, frequency, RF, audio, 8 battery fields, METER_RATE -- for
    /// Axient) in a single tight loop with no pacing of its own, relying
    /// entirely on the shared queue to drain it. A 4-channel Axient device
    /// alone produces ~70 commands that way; at a 40-item cap, the oldest
    /// of those (frequency, battery, channel name -- all queued before
    /// METER_RATE, which is appended last) got silently dropped before
    /// ever reaching the wire. Confirmed live: frequency and battery went
    /// missing on connect and only came back after manually restarting
    /// Live Mode, which re-ran the startup sequence at a moment the queue
    /// had more headroom under the cap. 200 comfortably covers a realistic
    /// one-time burst (even an 8+ channel device) while still bounding
    /// genuinely unbounded growth to a finite, self-draining ~30s worst
    /// case instead of the observed 400+ and still climbing.
    private static let maxQueuedCommandsPerPriority = 200

    /// Two priority tiers, not a single FIFO -- see highPriorityCommandQueue.
    func sendRaw(_ body: String, priority: SendPriority = .normal) {
        guard connection != nil else {
            lastError = "Not connected."
            return
        }
        switch priority {
        case .high:
            highPriorityCommandQueue.append(body)
            if highPriorityCommandQueue.count > Self.maxQueuedCommandsPerPriority {
                highPriorityCommandQueue.removeFirst(highPriorityCommandQueue.count - Self.maxQueuedCommandsPerPriority)
            }
        case .normal:
            normalPriorityCommandQueue.append(body)
            if normalPriorityCommandQueue.count > Self.maxQueuedCommandsPerPriority {
                normalPriorityCommandQueue.removeFirst(normalPriorityCommandQueue.count - Self.maxQueuedCommandsPerPriority)
            }
        }
        drainOutgoingCommandQueueIfNeeded()
    }

    /// Minimum spacing between any two commands sent to this device,
    /// regardless of which caller enqueued them.
    ///
    /// Started at 75ms (the pacing already proven necessary just to avoid
    /// the OS/TCP stack coalescing adjacent commands into one packet), but
    /// a live capture after centralizing all pacing into this single queue
    /// still showed REP ERR arriving in bursts of 8-10 that didn't line up
    /// 1:1 with what was just sent -- most individual GET/REP round trips
    /// were clean, but clusters of errors persisted, suggesting the AD4Q's
    /// own processing throughput (servicing its actual radio duties, not
    /// just answering TCP commands) is the remaining ceiling at ~13
    /// commands/sec, not just wire-level coalescing. Widened to give the
    /// receiver more headroom between commands.
    private static let outgoingCommandSpacingNanoseconds: UInt64 = 150_000_000

    /// How many consecutive high-priority sends are allowed before a
    /// pending normal-priority command is forced through instead.
    ///
    /// Without this, normal-priority commands can be starved indefinitely:
    /// on a device with the 150ms-per-command hard ceiling below, two
    /// tile-open channels alone can need close to the entire budget just to
    /// stay responsive for presence, and draining always prefers .high with
    /// no fairness -- confirmed live, the normal queue climbed past 500
    /// queued commands (stale battery/mute/frequency data) while .high
    /// stayed healthy the whole time, simply because .high was never fully
    /// empty long enough for .normal to get a turn. 1-in-6 costs at most
    /// ~1 presence-refresh slot per second of headroom, which the fast lane
    /// doesn't need every single cycle to stay well within its 12s
    /// evidence-hold window.
    private static let maxConsecutiveHighPriorityDrains = 5

    private func drainOutgoingCommandQueueIfNeeded() {
        guard outgoingSendTask == nil else { return }
        outgoingSendTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var consecutiveHighDrains = 0
            while !Task.isCancelled {
                let command: String
                let forceNormal = consecutiveHighDrains >= Self.maxConsecutiveHighPriorityDrains
                    && !self.normalPriorityCommandQueue.isEmpty
                if !forceNormal, !self.highPriorityCommandQueue.isEmpty {
                    command = self.highPriorityCommandQueue.removeFirst()
                    consecutiveHighDrains += 1
                } else if !self.normalPriorityCommandQueue.isEmpty {
                    command = self.normalPriorityCommandQueue.removeFirst()
                    consecutiveHighDrains = 0
                } else if !self.highPriorityCommandQueue.isEmpty {
                    command = self.highPriorityCommandQueue.removeFirst()
                    consecutiveHighDrains += 1
                } else {
                    break
                }
                self.sendRawImmediately(command)
                if !self.highPriorityCommandQueue.isEmpty || !self.normalPriorityCommandQueue.isEmpty {
                    try? await Task.sleep(nanoseconds: Self.outgoingCommandSpacingNanoseconds)
                }
            }
            self.outgoingSendTask = nil
        }
    }

    private func sendRawImmediately(_ body: String) {
        guard let connection else {
            lastError = "Not connected."
            return
        }
        let sendGate = tcpSendGate

        var trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("<") {
            trimmed = "< \(trimmed) >"
        }

        let payload = trimmed + "\r\n"
        let data = Data(payload.utf8)

        if Self.isVerboseLogging {
            print("[ShureWirelessService] \(deviceLogTag) Sending: \(payload.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        // Every outgoing command funnels through here, so this is the single
        // place to trace what's actually sent to an AD4Q device -- pairs
        // with the existing recv-side `recordAD4QRFTrace("recv line=...")`
        // call in the report-parsing path to let a REP ERR reply be matched
        // back to the specific command that provoked it.
        recordAD4QRFTrace("sent: \(trimmed)")

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                guard sendGate.isActive() else { return }
                let errorMessage = error.localizedDescription
                DispatchQueue.main.async {
                    guard let self, sendGate.isActive(), self.connection === connection else { return }
                    self.lastError = errorMessage
                    self.logDiagnosticError("Send failed to \(self.device?.host ?? "unknown"):\(self.device?.port ?? 0) — \(errorMessage)", keySuffix: "send_failed")
                }
            }
        })
    }

    func sendGetAll() {
        sendRaw("GET 0 ALL")
    }

    func sendSampleAll() {
        sendRaw("SAMPLE 0 ALL")
    }

    private func startTcpStartupSequence(for device: ExternalDeviceConfig, connection: NWConnection) {
        tcpStartupTask?.cancel()
        let startupCommands = makeTcpStartupCommands(for: device)
        guard !startupCommands.isEmpty else { return }

        // Pacing itself now lives in sendRaw's global send queue (see
        // drainOutgoingCommandQueueIfNeeded) rather than here -- this just
        // enqueues, still bailing out per-command if the connection this
        // sequence was built for has since been replaced.
        tcpStartupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for command in startupCommands {
                if Task.isCancelled { return }
                guard self.connection === connection, self.isConnected else { return }
                // METER_RATE is the one startup command that configures the
                // receiver's actual streaming behavior for the rest of the
                // session -- unlike the rest of this one-time burst (channel
                // name, frequency, battery, etc., all of which get refreshed
                // again soon anyway via ongoing polling), a delay here
                // directly means a delayed/unresponsive meter. At .normal
                // priority it sat at the very end of this ~77-command burst,
                // behind everything else in the same queue; confirmed live,
                // with the drain loop's 1-in-6 fairness share to .normal
                // while .high stayed busy, it could take over a minute to
                // actually reach the wire -- not lost, just badly delayed.
                let priority: SendPriority = command.hasPrefix("SET") && command.contains("METER_RATE") ? .high : .normal
                self.sendRaw(command, priority: priority)
            }
        }
    }

    private func makeTcpStartupCommands(for device: ExternalDeviceConfig) -> [String] {
        // GET 0 ALL is officially documented (Shure ANX4 Command Strings
        // reference) to return a full device + all-channel REP dump, so
        // it's safe to send on every model. SAMPLE 0 ALL (the channel-0
        // broadcast form) isn't documented anywhere in Shure's Axient
        // Digital or ANX4 Command Strings references -- every SAMPLE
        // example in both addresses a specific channel -- and confirmed on
        // real AD4Q hardware: every SAMPLE 0 ALL sent got REP ERR back (0
        // successful SAMPLE replies across a full test session). This was
        // originally scoped to just the licensed models (ANX4/ADTD/ADTQ),
        // but the same rejection happens on plain AD4Q -- broadened to
        // every Axient Digital model. Rely on unprompted SAMPLE streaming
        // once METER_RATE is set per channel instead.
        let supportsSampleAllBroadcast = !Self.isAxientDeviceModel(device)
        var commands: [String] = ["GET 0 ALL"]
        if liveModeEnabled, supportsSampleAllBroadcast {
            commands.append("SAMPLE 0 ALL")
        }

        let channelCount = inferredChannelCount(for: device)
        let isAxientModel = Self.isAxientDeviceModel(device)
        let shouldQueryTxDeviceID = shouldQueryTxDeviceID(for: device)
        if channelCount > 0 {
            if Self.isVerboseLogging {
                print("[ShureWirelessService] \(device.name)@\(device.host):\(device.port) Queuing paced startup for \(channelCount) channels")
            }

            for ch in 1...channelCount {
                // Keep the startup query set explicit so older 2202 receivers
                // get the same coverage without relying on GET <ch> ALL support.
                commands.append("GET \(ch) CHAN_NAME")
                commands.append("GET \(ch) FREQUENCY")
                if shouldQueryTxDeviceID {
                    if shouldTraceULXDTxDeviceID() {
                        recordULXDTxDeviceIDTrace("startup query ch=\(ch) key=TX_DEVICE_ID")
                    }
                    commands.append("GET \(ch) TX_DEVICE_ID")
                }
                if isAxientModel {
                    // RSSI and RSSI_LED_BITMAP take an antenna index argument
                    // per Shure's ANX4 Command Strings reference; 0 = all antennas.
                    commands.append("GET \(ch) RSSI 0")
                    commands.append("GET \(ch) RSSI_LED_BITMAP 0")
                    commands.append("GET \(ch) CHAN_QUALITY")
                } else {
                    commands.append("GET \(ch) RF_TX_LVL")
                    commands.append("GET \(ch) RX_RF_LVL")
                    commands.append("GET \(ch) RF_ANTENNA")
                    commands.append("GET \(ch) RSSI_LED_BITMAP")
                }
                if isAxientModel {
                    // AUDIO_LVL isn't a recognized Axient Digital property --
                    // confirmed against Shure's Axient Digital Command
                    // Strings reference and against real AD4Q hardware
                    // (which replies REP ERR to it every time). Axient's
                    // audio meters are AUDIO_LEVEL_RMS/AUDIO_LEVEL_PEAK/
                    // AUDIO_LED_BITMAP, matching what refreshAudioLevelIfNeeded
                    // already queries correctly for Axient devices.
                    commands.append("GET \(ch) AUDIO_LEVEL_RMS")
                    commands.append("GET \(ch) AUDIO_LEVEL_PEAK")
                    commands.append("GET \(ch) AUDIO_LED_BITMAP")
                } else {
                    commands.append("GET \(ch) AUDIO_LVL")
                }
                // Family-specific battery keys only -- see
                // sendMediumPriorityRefresh for why sending both
                // conventions to every device is pure waste, confirmed
                // against a full real show's traffic.
                if isAxientModel {
                    commands.append("GET \(ch) TX_BATT_CHARGE_PERCENT")
                    commands.append("GET \(ch) TX_BATT_BARS")
                    commands.append("GET \(ch) TX_BATT_MINS")
                } else {
                    commands.append("GET \(ch) BATT_CHARGE")
                    commands.append("GET \(ch) BATT_BARS")
                    commands.append("GET \(ch) BATT_MINS")
                    commands.append("GET \(ch) BATT_RUN_TIME")
                }
            }
        }

        guard liveModeEnabled else { return commands }

        guard Self.isMeterRateCapableDevice(device), channelCount > 0 else { return commands }

        // Request the effective METER_RATE per channel: 100ms whenever a
        // channel-detail consumer is active or the channel is currently
        // resolved "on", otherwise the overview hub's requested rate --
        // uniformly across device families (Axient no longer gets a special
        // slow-constant carve-out here; see effectiveMeterRateMilliseconds
        // for why).
        let now = Date()
        for ch in 1...channelCount {
            let effectiveRate: Int
            if channelConsumerSelections.values.contains(ch) {
                effectiveRate = 100
            } else if resolvedTelemetryTransmitterState(for: ch, now: now) == .on {
                effectiveRate = 100
            } else {
                effectiveRate = overviewMeterRateMilliseconds
            }
            let rateString = String(format: "%05d", effectiveRate)
            commands.append("SET \(ch) METER_RATE \(rateString)")
            commands.append("GET \(ch) METER_RATE")
            lastAppliedMeterRateMilliseconds[ch] = effectiveRate
        }

        return commands
    }

    /// Sends `commands` as a group. Pacing itself is now handled globally
    /// by sendRaw's own outgoing queue (see drainOutgoingCommandQueueIfNeeded),
    /// which guarantees a 75ms floor between ANY two commands sent to this
    /// device regardless of which caller enqueued them -- this used to pace
    /// itself locally with its own Task/sleep loop, but that only protected
    /// this specific burst, not against a different caller (e.g. a
    /// single-tile view's poll loop) enqueueing its own commands in the gaps.
    /// Kept as a named call for the multi-command Axient clusters that used
    /// to need special handling, so the call sites stay self-documenting.
    private func sendPacedCommands(_ commands: [String], priority: SendPriority = .normal) {
        for command in commands {
            sendRaw(command, priority: priority)
        }
    }

    private func isAxientDeviceModel() -> Bool {
        guard let device else { return false }
        return Self.isAxientDeviceModel(device)
    }

    /// How often this device's `@Published telemetrySnapshot` -- the sole
    /// thing the UI actually observes -- is allowed to update.
    ///
    /// This is a completely separate throttle from how often Relay polls
    /// the hardware. Speeding up the underlying GET/SAMPLE traffic (as the
    /// per-channel adaptive meter-rate work does) doesn't help if the
    /// snapshot carrying that fresher data to SwiftUI still only publishes
    /// once per overviewPollingIntervalSeconds -- confirmed by a customer
    /// report of meters still feeling slow/sticky in Overview even after
    /// that polling-side fix landed. For an Overview-only session (no
    /// single-tile view open), the interval used to be the device-wide
    /// channel-count-scaled tier value unconditionally; now it drops to
    /// the same fast rate a single-tile consumer gets whenever this device
    /// has at least one channel currently resolved "on" -- that's the
    /// channel(s) actually being watched move. A device with everything
    /// off stays on the slow tier, since there's nothing on it changing
    /// fast enough to need a quicker publish.
    func snapshotPublishInterval() -> TimeInterval {
        guard liveModeEnabled else { return 0.5 }
        if !channelConsumerSelections.isEmpty {
            return 0.15
        }
        if !overviewConsumerIDs.isEmpty {
            if hasAnyOnChannel(now: Date()) {
                return 0.15
            }
            return overviewPollingIntervalSeconds
        }
        return 0.75
    }

    /// Whether this device currently has any channel resolved "on".
    /// Internal (not private) so ShureOverviewHub can check across every
    /// service it owns when deciding whether to speed up its own
    /// hub-wide recompute throttle -- see refreshThrottleIntervalForActivity().
    func hasAnyOnChannel(now: Date) -> Bool {
        guard let device else { return false }
        let channelCount = inferredChannelCount(for: device)
        guard channelCount > 0 else { return false }
        return (1...channelCount).contains {
            resolvedTelemetryTransmitterState(for: $0, now: now) == .on
        }
    }

    private func averageMilliseconds(total: TimeInterval, samples: Int) -> Double {
        guard samples > 0 else { return 0 }
        return (total / Double(samples)) * 1000.0
    }

    private func snapshotPublishRateHz(now: Date) -> Double {
        let window = now.timeIntervalSince(telemetryPublishWindowStartedAt)
        guard window > 0 else { return 0 }
        return Double(telemetrySnapshotPublishCount) / window
    }

    private func pollingIntervalDescription() -> String {
        if !overviewConsumerIDs.isEmpty {
            return "fast=0.2s medium=3s slow=45s"
        }
        if !channelConsumerSelections.isEmpty {
            return "channel-driven"
        }
        return liveModeEnabled ? "connected-idle" : "idle"
    }

    private func buildTelemetrySnapshot(now: Date = Date()) -> ShureTelemetryDeviceSnapshot {
        let buildStart = CFAbsoluteTimeGetCurrent()

        var channels = Set<Int>()
        channels.formUnion(standardReportChannelIndices())
        channels.formUnion(psmAudioLevels.keys)
        channels.formUnion(channelTransmitterPresent.keys)
        channels.formUnion(channelTransmitterDeviceIDPresent.keys)

        let snapshots = channels.sorted().map { channelIndex in
            let standard = currentStandardReportSnapshot(channelIndex: channelIndex)
            let lowFrequency = currentStandardReportLowFrequencySnapshot(channelIndex: channelIndex)
            let stereo = psmAudioLevels[channelIndex]
            let channelLastHeardAt = [
                micAudioLastUpdated[channelIndex],
                channelBatteryLastUpdated[channelIndex],
                channelRfLastUpdated[channelIndex],
                rfTxLastUpdated[channelIndex],
                channelTransmitterPresentLastUpdated[channelIndex],
                channelTransmitterDeviceIDLastUpdated[channelIndex],
                lastHeardAt
            ].compactMap { $0 }.max()

            return ShureTelemetryChannelSnapshot(
                id: "\(device?.id.uuidString ?? "device")-\(channelIndex)",
                channelIndex: channelIndex,
                channelName: lowFrequency.channelName,
                frequencyLabel: lowFrequency.frequencyDisplay,
                batteryPercent: standard.batteryPercentage,
                batteryLabel: lowFrequency.batteryLabel,
                batteryIsApproximate: lowFrequency.batteryIsApproximate ?? false,
                rfBars: standard.rfBarCount,
                rfOverload: standard.rfOverload ?? false,
                rfTxLevel: standard.rfTxLevel,
                audioLevel: standard.micAudioLevel ?? micAudioLevels[channelIndex] ?? stereo.map { max($0.left, $0.right) },
                audioOverload: standard.micAudioOverload ?? false,
                audioLeftLevel: stereo?.left,
                audioRightLevel: stereo?.right,
                isMuted: lowFrequency.audioMute,
                meterRate: lowFrequency.meterRate,
                transmitterState: resolvedTelemetryTransmitterState(for: channelIndex, now: now),
                transmitterPresent: {
                    let resolved = resolvedTelemetryTransmitterState(for: channelIndex, now: now)
                    switch resolved {
                    case .on:
                        return true
                    case .off:
                        return false
                    case .unknown:
                        return nil
                    }
                }(),
                lastHeardAt: channelLastHeardAt,
                lastBatteryAt: channelBatteryLastUpdated[channelIndex],
                lastRFAt: channelRfLastUpdated[channelIndex] ?? rfTxLastUpdated[channelIndex],
                lastAudioAt: micAudioLastUpdated[channelIndex]
            )
        }

        snapshotBuildDurationTotal += CFAbsoluteTimeGetCurrent() - buildStart
        snapshotBuildSamples += 1

        // The diagnostics block is only consumed by the verbose telemetry
        // trace (recordTelemetryDiagnosticsIfNeeded). Its aggregation iterates
        // every shared service and filters the entire device store, so building
        // it on every publish was pure main-thread waste. Compute it only when
        // verbose logging is actually enabled for this device.
        let diagnostics: ShureTelemetryDiagnosticsSnapshot
        if Self.isVerboseLogging(for: device) {
            let activeServices = Set(Self.sharedServices.values.map(ObjectIdentifier.init)).count
            let connectedPhysicalDevices = ExternalDevicesStore.shared.devices.filter { $0.kind == .shureWireless }.count
            diagnostics = ShureTelemetryDiagnosticsSnapshot(
                activeServiceCount: activeServices,
                connectedPhysicalDeviceCount: connectedPhysicalDevices,
                overviewSubscriberCount: overviewConsumerIDs.count,
                channelSubscriberCount: Set(channelConsumerSelections.values).count,
                pollingIntervalDescription: pollingIntervalDescription(),
                snapshotPublishRateHz: snapshotPublishRateHz(now: now),
                averageParseTimeMilliseconds: averageMilliseconds(total: parseDurationTotal, samples: parseDurationSamples),
                averageSnapshotBuildTimeMilliseconds: averageMilliseconds(total: snapshotBuildDurationTotal, samples: snapshotBuildSamples),
                droppedCoalescedUpdateCount: droppedCoalescedTelemetryUpdateCount,
                lastSlowRefreshAt: lastSlowRefreshAt,
                lastFastTelemetryAt: lastFastTelemetryAt
            )
        } else {
            diagnostics = .empty
        }

        return ShureTelemetryDeviceSnapshot(
            deviceID: device?.id,
            deviceName: device?.name ?? "",
            isConnected: isConnected,
            isReconnecting: isReconnecting,
            lastHeardAt: lastHeardAt,
            updatedAt: now,
            channels: snapshots,
            diagnostics: diagnostics
        )
    }

    private func recordTelemetryDiagnosticsIfNeeded(snapshot: ShureTelemetryDeviceSnapshot, now: Date) {
        guard Self.isVerboseLogging(for: device) else { return }
        if let lastDiagnosticsTraceAt, now.timeIntervalSince(lastDiagnosticsTraceAt) < 15 {
            return
        }
        lastDiagnosticsTraceAt = now
        let diagnostics = snapshot.diagnostics
        RelayDiagnosticsStore.shared.recordShureTrace(
            "telemetry device=\(snapshot.deviceName) services=\(diagnostics.activeServiceCount) devices=\(diagnostics.connectedPhysicalDeviceCount) overview_subscribers=\(diagnostics.overviewSubscriberCount) channel_subscribers=\(diagnostics.channelSubscriberCount) poll=\(diagnostics.pollingIntervalDescription) publish_hz=\(String(format: "%.2f", diagnostics.snapshotPublishRateHz)) parse_ms=\(String(format: "%.2f", diagnostics.averageParseTimeMilliseconds)) snapshot_ms=\(String(format: "%.2f", diagnostics.averageSnapshotBuildTimeMilliseconds)) dropped=\(diagnostics.droppedCoalescedUpdateCount)"
        )
    }

    private func publishTelemetrySnapshotNow() {
        telemetryPublishTask?.cancel()
        telemetryPublishTask = nil

        let now = Date()
        let snapshot = buildTelemetrySnapshot(now: now)
        guard !snapshot.hasSameContent(as: telemetrySnapshot) else { return }

        telemetrySnapshot = snapshot
        telemetrySnapshotPublishCount += 1
        lastTelemetrySnapshotPublishAt = now
        if now.timeIntervalSince(telemetryPublishWindowStartedAt) >= 10 {
            telemetryPublishWindowStartedAt = now
            telemetrySnapshotPublishCount = 0
        }
        recordTelemetryDiagnosticsIfNeeded(snapshot: snapshot, now: now)
    }

    private func recentTxDeviceIDPresence(for channelIndex: Int, now: Date) -> Bool? {
        guard let lastUpdated = channelTransmitterDeviceIDLastUpdated[channelIndex],
              let transmitterPresent = channelTransmitterDeviceIDPresent[channelIndex] else {
            return nil
        }

        let age = now.timeIntervalSince(lastUpdated)
        if transmitterPresent {
            return age <= 6.0 ? true : nil
        }
        return age <= 1.5 ? false : nil
    }

    private func recentExplicitTransmitterPresence(for channelIndex: Int, now: Date) -> Bool? {
        guard let lastUpdated = channelTransmitterPresentLastUpdated[channelIndex],
              let transmitterPresent = channelTransmitterPresent[channelIndex] else {
            return nil
        }

        let age = now.timeIntervalSince(lastUpdated)
        if transmitterPresent {
            return age <= 6.0 ? true : nil
        }
        return age <= 1.5 ? false : nil
    }

    private func recentAxientPositivePresenceEvidence(for channelIndex: Int, now: Date) -> Date? {
        guard let lastSeenAt = channelAxientPositiveEvidenceLastSeenAt[channelIndex] else {
            return nil
        }
        guard now.timeIntervalSince(lastSeenAt) <= ShureAxientPresenceResolver.positiveEvidenceHoldSeconds else {
            return nil
        }
        return lastSeenAt
    }

    private func telemetryHasUsableBatteryValue(for channelIndex: Int) -> Bool {
        if let percent = standardReportBatteryPercentage(for: channelIndex) {
            return percent > 0
        }
        let batteryLabel = standardReportBatteryLabel(for: channelIndex)
        guard let label = batteryLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              label != "—"
        else {
            return false
        }

        var digits = ""
        for character in label {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }

        if let numericValue = Int(digits) {
            return numericValue > 0
        }

        return true
    }

    private func telemetryReceiverPresenceResolution(for channelIndex: Int, now: Date) -> ShureTelemetryTransmitterState? {
        guard channelTransmitterPresentLastUpdated[channelIndex] != nil else {
            return nil
        }

        if isAxientDeviceModel() {
            let recentFalseAt = recentExplicitTransmitterPresence(for: channelIndex, now: now) == false
                ? channelTransmitterPresentLastUpdated[channelIndex]
                : nil
            return ShureAxientPresenceResolver.resolve(
                recentPositiveEvidenceAt: recentAxientPositivePresenceEvidence(for: channelIndex, now: now),
                recentNegativeEvidenceAt: recentFalseAt,
                negativeEvidenceStreakStartAt: channelAxientNegativeEvidenceStreakStartAt[channelIndex],
                now: now
            )
        }

        let rfBarCount = standardReportRfBarCount(for: channelIndex) ?? 0
        let recentFalseAt = isRecent(channelTransmitterPresentLastFalseAt[channelIndex], within: 2.0, now: now)
            ? channelTransmitterPresentLastFalseAt[channelIndex]
            : nil
        let recentTrueAt = isRecent(channelTransmitterPresentLastTrueAt[channelIndex], within: 12.0, now: now)
            ? channelTransmitterPresentLastTrueAt[channelIndex]
            : nil

        return ShureReceiverPresenceResolver.resolveNonAxientState(
            rfBarCount: rfBarCount,
            recentFalseAt: recentFalseAt,
            recentTrueAt: recentTrueAt,
            rfUpdatedRecently: isRecent(channelRfLastUpdated[channelIndex], within: 2.0, now: now)
        )
    }

    private func resolvedTelemetryTransmitterState(for channelIndex: Int, now: Date) -> ShureTelemetryTransmitterState {
        if isAxientDeviceModel(),
           let recentPositiveEvidenceAt = recentAxientPositivePresenceEvidence(for: channelIndex, now: now) {
            let recentNegativeEvidenceAt = recentTxDeviceIDPresence(for: channelIndex, now: now) == false
                ? channelTransmitterDeviceIDLastUpdated[channelIndex]
                : (recentExplicitTransmitterPresence(for: channelIndex, now: now) == false
                    ? channelTransmitterPresentLastUpdated[channelIndex]
                    : nil)
            return ShureAxientPresenceResolver.resolve(
                recentPositiveEvidenceAt: recentPositiveEvidenceAt,
                recentNegativeEvidenceAt: recentNegativeEvidenceAt,
                negativeEvidenceStreakStartAt: channelAxientNegativeEvidenceStreakStartAt[channelIndex],
                now: now
            )
        }

        if shouldQueryTxDeviceID(), let transmitterPresent = recentTxDeviceIDPresence(for: channelIndex, now: now) {
            return transmitterPresent ? .on : .off
        }

        if let receiverPresence = telemetryReceiverPresenceResolution(for: channelIndex, now: now) {
            return receiverPresence
        }

        if isRecent(channelPresenceLastSeenAt[channelIndex], within: 4.0) {
            return .on
        }

        if isRecent(channelBatteryLastUpdated[channelIndex], within: 3.0, now: now), telemetryHasUsableBatteryValue(for: channelIndex) {
            return .on
        }

        if isRecent(micAudioLastUpdated[channelIndex], within: 2.0, now: now),
           let audioLevel = micAudioLevels[channelIndex],
           audioLevel > 0 {
            return .on
        }

        if shouldQueryTxDeviceID(), channelTransmitterDeviceIDLastUpdated[channelIndex] != nil {
            return .off
        }

        return .unknown
    }

    private func isRecent(_ date: Date?, within seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) <= seconds
    }

    private func scheduleTelemetrySnapshotPublish(immediate: Bool = false) {
        if immediate {
            publishTelemetrySnapshotNow()
            return
        }

        if telemetryPublishTask != nil {
            droppedCoalescedTelemetryUpdateCount += 1
            return
        }

        let delay = snapshotPublishInterval()
        telemetryPublishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.publishTelemetrySnapshotNow()
        }
    }

    /// Only ever called from the single per-device shared polling loop
    /// (see refreshSharedPollingTask), so it must always cover every
    /// channel on the device -- Overview displays all of them, and the
    /// loop is also now the sole poller for single-tile views, regardless
    /// of which specific channel a channel-detail (single-tile) view
    /// happens to have selected via channelConsumerSelections. Previously
    /// narrowed to just the single-tile's selected channel(s) whenever any
    /// were registered, which starved every OTHER channel on a
    /// multi-channel receiver of ongoing polling the moment any
    /// single-tile view was opened -- confirmed on a real field log: a
    /// 4-channel AD4Q's "Mark" channel (which had its own open single-tile)
    /// kept updating continuously, while "Lead" on the same receiver never
    /// got polled again after the initial connection burst.
    private func visibleChannelIndicesForPolling() -> [Int] {
        guard let device else { return [] }
        return Array(1...max(1, inferredChannelCount(for: device)))
    }

    /// Which of `channels` has had NO audio-level or RF update within
    /// `staleAfter` — used to decide whether unprompted SAMPLE streaming is
    /// actually landing for a METER_RATE-capable device, rather than
    /// assuming it always is. Deliberately shorter than the Overview's own
    /// default stale-telemetry timeout (8s) so this heals a stuck channel
    /// before the UI has to flag it.
    ///
    /// Per-channel, not aggregate: a device where the unprompted stream only
    /// covers one channel (confirmed on a 4-channel AD4Q field log -- an
    /// actively-viewed channel streamed continuously via METER_RATE while
    /// its three siblings never received a single unprompted SAMPLE for the
    /// whole session) must still fall back to polling the other channels
    /// individually. Checking "is any channel fresh" instead let that one
    /// streaming channel mask the other three being permanently stale.
    private func staleMeterChannels(among channels: [Int], now: Date, staleAfter: TimeInterval = 6.0) -> [Int] {
        channels.filter { channelIndex in
            if let updated = micAudioLastUpdated[channelIndex], now.timeIntervalSince(updated) <= staleAfter {
                return false
            }
            if let updated = channelRfLastUpdated[channelIndex], now.timeIntervalSince(updated) <= staleAfter {
                return false
            }
            return true
        }
    }

    /// Which of `channels` has had no transmitterPresent update (driven by
    /// RF_ANTENNA on ULX-D-family devices, CHAN_QUALITY/TX_DEVICE_ID on
    /// Axient) within `staleAfter`.
    ///
    /// Deliberately separate from staleMeterChannels. On ULX-D-family
    /// devices, RF/audio levels keep flowing from the SAMPLE broadcast
    /// (which, unlike Axient, isn't discarded on receipt) even once
    /// presence itself has gone stale -- gating the presence-refresh GET
    /// on meter freshness let a channel with fresh RF bars but a stale
    /// RF_ANTENNA reading look "not stale" and never get re-polled.
    /// Confirmed on a field log: a single-channel ULXD4 kept showing real,
    /// recently-updated RF bars (from the still-flowing SAMPLE broadcast)
    /// for the entire time its "on" status silently expired, because
    /// staleMeterChannels never once flagged it as needing a presence
    /// refresh.
    private func stalePresenceChannels(among channels: [Int], now: Date, staleAfter: TimeInterval = 6.0) -> [Int] {
        channels.filter { channelIndex in
            guard let updated = channelTransmitterPresentLastUpdated[channelIndex] else { return true }
            return now.timeIntervalSince(updated) > staleAfter
        }
    }

    /// Explicit REP-triggering refresh for one Axient channel's
    /// presence/RF/audio fields, for use by the shared Overview-driven
    /// polling loop.
    ///
    /// Axient devices' replies to "SAMPLE n ALL" are intentionally
    /// discarded on receipt (see processSampleFrame's isAxientDeviceModel
    /// early-return -- SAMPLE payloads were found unreliable in the
    /// field), which makes SAMPLE a dead end for keeping a channel's
    /// presence/RF state fresh on these devices. The single-tile module
    /// view already refreshes these exact keys successfully via its own
    /// per-instance timer (refreshChannelSnapshotIfNeeded /
    /// refreshAudioLevelIfNeeded), which is why a channel with its own
    /// open tile never goes stale -- confirmed on a field log where an
    /// AD4Q channel with no open tile kept sending "SAMPLE n ALL" every
    /// ~3s under the post-98ff3f1 fix, correctly per staleMeterChannels,
    /// but stayed stale forever because every reply was silently thrown
    /// away, while its sibling channel (open in a tile) stayed fresh the
    /// entire session. This mirrors that already-proven GET set so
    /// channels without their own open tile get the same treatment from
    /// the shared loop instead of depending on one being open somewhere.
    private func sendAxientPresenceRefresh(for channelIndex: Int, priority: SendPriority = .normal) {
        // Paced (see sendPacedCommands) -- this cluster is the same shape
        // as the ones in refreshAudioLevelIfNeeded/refreshChannelSnapshotIfNeeded
        // that were already confirmed to lose data to coalesced-burst REP
        // ERR on real AD4Q hardware when sent unpaced.
        sendPacedCommands([
            "GET \(channelIndex) TX_DEVICE_ID",
            "GET \(channelIndex) CHAN_QUALITY",
            "GET \(channelIndex) RSSI 0",
            "GET \(channelIndex) RSSI_LED_BITMAP 0",
            "GET \(channelIndex) AUDIO_LEVEL_RMS",
            "GET \(channelIndex) AUDIO_LEVEL_PEAK",
            "GET \(channelIndex) AUDIO_LED_BITMAP"
        ], priority: priority)
    }

    /// Explicit REP-triggering presence refresh for one ULX-D-family
    /// channel, for use by the shared Overview-driven polling loop.
    ///
    /// RF_ANTENNA -- not TX_DEVICE_ID, which shouldQueryTxDeviceID() gates
    /// to Axient devices only -- is what actually drives transmitterPresent
    /// for this device family (see the "RF_ANTENNA" case in the report
    /// reducer: transmitterPresent = value != "XX"). The shared loop's
    /// broadcast SAMPLE ALL keeps RF bars/audio levels fresh for these
    /// devices (their SAMPLE replies aren't discarded the way Axient's
    /// are), but SAMPLE frames never touch presence state either way, and
    /// nothing else in the shared loop ever asks for RF_ANTENNA -- only a
    /// channel's own open single-tile view does, via
    /// refreshAudioLevelIfNeeded. Confirmed on a field log: two single-
    /// channel ULXD4 units with no open tile lost "on" status repeatedly
    /// over a 20+ minute session with only sparse, minutes-apart
    /// unprompted TX_DEVICE_ID pushes and no explicit RF_ANTENNA requests
    /// at all, while sibling channels with an open tile stayed solid.
    private func sendUlxdPresenceRefresh(for channelIndex: Int, priority: SendPriority = .normal) {
        sendRaw("GET \(channelIndex) RF_ANTENNA", priority: priority)
    }

    /// Sends 9 GET commands for one channel. Originally paced 75ms apart by
    /// this function itself, after confirming on real AD4Q hardware that
    /// sending these unpaced let the OS/TCP stack coalesce them into fewer
    /// packets than the receiver's line parser expects -- whichever command
    /// landed last in a merged burst (always AUDIO_MUTE, since it's last in
    /// this list) got REP ERR back essentially every cycle: 1,334+ errors
    /// across a single test session, versus single digits for every other
    /// command in this same list. That pacing has since moved into sendRaw
    /// itself (a single global send queue shared by every caller), since
    /// per-function pacing alone didn't protect against a different caller
    /// enqueueing its own commands in the gaps -- this function just
    /// enqueues its 9 commands now.
    /// Every battery key here used to be sent twice -- once in each
    /// family's naming convention -- regardless of which device it was
    /// actually going to. Confirmed against a full real show's traffic
    /// (24 devices, several hours): TX_-prefixed keys got zero replies
    /// ever from ULX-D/QLX-D devices and bare keys got zero replies ever
    /// from the AD4Q, a completely clean split with no overlap either way.
    /// TX_BATT_PERCENT got zero replies from *either* family across the
    /// whole show -- dead from the start, superseded by
    /// TX_BATT_CHARGE_PERCENT and never removed. Sending only the
    /// family-appropriate set here roughly halves this function's
    /// contribution to the outgoing queue, which mattered: this was the
    /// single largest source feeding the .normal queue's sustained
    /// saturation (pegged at its cap for 96% of that same show), which is
    /// why battery% displays were stuck stale for most channels most of
    /// the night. reduceBattery's parsing still accepts both naming
    /// conventions unconditionally -- only what gets requested changes.
    private func sendMediumPriorityRefresh(for channelIndex: Int, priority: SendPriority = .normal) async {
        let batteryKeys = isAxientDeviceModel()
            ? ["TX_BATT_CHARGE_PERCENT", "TX_BATT_BARS", "TX_BATT_MINS"]
            : ["BATT_CHARGE", "BATT_BARS", "BATT_MINS", "BATT_RUN_TIME"]
        for key in batteryKeys {
            sendRaw("GET \(channelIndex) \(key)", priority: priority)
        }
        sendRaw("GET \(channelIndex) AUDIO_MUTE", priority: priority)
    }

    private func sendSlowPriorityRefresh(for channelIndex: Int, priority: SendPriority = .normal) {
        sendRaw("GET \(channelIndex) FREQUENCY", priority: priority)
    }

    /// The single per-device poller. Used to only run for Overview, but a
    /// single-tile view's own independent meterTick-driven poll loop
    /// competed with it on the same connection -- two schedulers pacing
    /// themselves separately couldn't guarantee real spacing between each
    /// other's commands no matter how each one paced its own traffic,
    /// which is what actually caused (not just failed to fix) the REP
    /// ERR/dropped-update/flapping-presence problems chased over several
    /// rounds tonight. Single-tile views no longer poll independently at
    /// all (see the meterTick handler) -- they read this loop's results --
    /// so this must now run whenever EITHER Overview or any tile needs it,
    /// not just Overview, or a tile-only session (no Overview module
    /// anywhere on the canvas) would get no polling at all.
    private func refreshSharedPollingTask() {
        let needsPolling = liveModeEnabled && connection != nil
            && (!overviewConsumerIDs.isEmpty || !channelConsumerSelections.isEmpty)
        if !needsPolling {
            sharedPollingTask?.cancel()
            sharedPollingTask = nil
            return
        }
        guard sharedPollingTask == nil else { return }

        recordAD4QRFTrace("shared_poll_task_started overview=\(overviewConsumerIDs.count) channelConsumers=\(channelConsumerSelections.count)")
        sharedPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard self.liveModeEnabled, self.connection != nil,
                      !self.overviewConsumerIDs.isEmpty || !self.channelConsumerSelections.isEmpty else {
                    self.recordAD4QRFTrace("shared_poll_task_stopped reason=guard_failed liveMode=\(self.liveModeEnabled) connected=\(self.connection != nil) overview=\(self.overviewConsumerIDs.count) channelConsumers=\(self.channelConsumerSelections.count)")
                    break
                }

                let now = Date()
                let channels = self.visibleChannelIndicesForPolling()
                let meterRateCapable = self.device.map(Self.isMeterRateCapableDevice) ?? false
                // A channel with its own open single-tile view has no other
                // source of telemetry any more -- the tile itself no longer
                // polls independently (see the meterTick handler) -- so this
                // loop is now its ONLY poller. Used below to route every
                // per-channel action for these channels through the fast
                // lane and at .high priority, same as any channel resolved
                // "on". Two independently-paced pollers hitting the same
                // connection (the tile's own loop, and this one) is what
                // actually caused the REP ERR/dropped-update/flapping-
                // presence problems chased over several rounds tonight --
                // de-duplicating and reprioritizing a strict FIFO queue
                // both helped without fixing it, because the real problem
                // was having two schedulers at all, not how they shared one
                // queue. Never excluded from `channels` itself (that list
                // must stay the full device channel set -- see
                // visibleChannelIndicesForPolling's own history of the
                // opposite starvation bug).
                let tileOpenChannels = Set(self.channelConsumerSelections.values)

                // Re-evaluate per-channel METER_RATE every tick so a channel
                // flipping on/off promotes/demotes its own unprompted stream
                // rate without needing a tile to be opened -- this is the
                // only regular trigger point for ULX-D-family devices, whose
                // fast path is the device's own unprompted streaming rather
                // than anything this loop sends directly.
                self.applyEffectiveMeterRateIfNeeded()

                if self.lastQueueDepthTraceAt == nil
                    || now.timeIntervalSince(self.lastQueueDepthTraceAt ?? .distantPast) >= 5.0 {
                    self.lastQueueDepthTraceAt = now
                    self.recordAD4QRFTrace("queue_depth highQ=\(self.highPriorityCommandQueue.count) normalQ=\(self.normalPriorityCommandQueue.count)")
                }

                // METER_RATE-capable devices are expected to stream SAMPLE n
                // ALL unprompted at the configured rate, but that isn't
                // reliable on every receiver/firmware in the field — some
                // never push anything after METER_RATE is set. Nothing else
                // in this loop re-requests AUDIO_LVL/RSSI, so when that
                // happens an Overview-only session (no per-channel consumer
                // separately polling via refreshSampleIfNeeded) is left with
                // a permanently stale one-shot snapshot from connect: stuck
                // "off" with meters that never move.
                //
                // Only send the fallback SAMPLE when recent telemetry is
                // actually missing rather than unconditionally on every
                // tick — sending it unconditionally at this cadence across
                // many devices at once turned out to add enough redundant
                // traffic (on top of whatever unprompted streaming is
                // already flowing) to destabilize at least one receiver's
                // TCP connection in the field. Staleness-gating keeps this a
                // safety net instead of a permanent duplicate load.
                if !meterRateCapable {
                    if let device = self.device, Self.isAxientDeviceModel(device) {
                        for channelIndex in channels {
                            self.sendAxientPresenceRefresh(
                                for: channelIndex,
                                priority: tileOpenChannels.contains(channelIndex) ? .high : .normal
                            )
                        }
                    } else {
                        for channelIndex in channels {
                            self.sendUlxdPresenceRefresh(
                                for: channelIndex,
                                priority: tileOpenChannels.contains(channelIndex) ? .high : .normal
                            )
                        }
                        self.sendSampleAll()
                    }
                    self.lastFastTelemetryAt = now
                } else {
                    let staleMeter = self.staleMeterChannels(among: channels, now: now)
                    let stalePresence = self.stalePresenceChannels(among: channels, now: now)
                    var sentAnything = false

                    if let device = self.device, Self.isAxientDeviceModel(device) {
                        // A channel with its own open single-tile view is
                        // now polled ONLY from here -- the tile no longer
                        // runs its own independent poll loop (see the
                        // meterTick handler) -- so it belongs in this fast
                        // lane unconditionally, not just when already
                        // resolved "on": a tile watching a currently-off mic
                        // still needs to see it turn on promptly. Channels
                        // resolved "on" without a tile get the same lane too
                        // -- that's what a user is watching move in Overview
                        // itself. Everything else stays on the slow,
                        // RMS-only lane below: most channels on a large rig
                        // are off and unwatched at any given moment, so this
                        // keeps total added load bounded by *active or
                        // watched* channel count rather than total channel
                        // count.
                        let onChannels = channels.filter {
                            tileOpenChannels.contains($0)
                                || self.resolvedTelemetryTransmitterState(for: $0, now: now) == .on
                        }
                        // sendAxientPresenceRefresh's 6-command cluster is
                        // enqueued onto sendRaw's global send queue (see
                        // drainOutgoingCommandQueueIfNeeded), which paces
                        // every command apart regardless of source, so
                        // overlap on the wire isn't a risk here any more.
                        // This interval still bounds how often the same
                        // channel gets re-enqueued, so this one source can't
                        // by itself dominate the shared queue.
                        // Backpressure: only enqueue a new fast-lane burst
                        // once the previous one has actually drained.
                        // sendAxientPresenceRefresh enqueues 6-7 commands at
                        // once, and the queue drains one command per
                        // outgoingCommandSpacingNanoseconds (150ms) --
                        // roughly a full second to clear one burst. This
                        // loop ticks every ~0.25-0.4s, so gating purely on
                        // minimumInterval let a new burst get enqueued
                        // before the last one finished sending: producing
                        // ~27 commands/sec against a ~6.7 commands/sec drain
                        // rate, so the high-priority queue grew without
                        // bound and commands went out several seconds stale
                        // by the time they finally reached the wire.
                        // Confirmed on a live capture: the scheduler picked
                        // a fresh channel every tick right on schedule, but
                        // actual GET sends for that channel were 4-9 seconds
                        // apart. ULX-D-family devices never hit this because
                        // their fast-lane payload is a single command, not
                        // a multi-command cluster -- no overproduction.
                        //
                        // stalePresence channels are folded into this SAME
                        // pick-one-per-drained-cycle arbiter rather than
                        // handled by a second, independent producer. A
                        // separate "for every stale channel, send .high every
                        // tick" loop was tried and made things worse: right
                        // after connect all 4 channels start stale at once,
                        // and as long as the queue stays even a little behind
                        // (so replies don't land in time to refresh
                        // channelTransmitterPresentLastUpdated before the 6s
                        // staleness window reopens), every stale channel
                        // keeps re-qualifying every tick -- confirmed live,
                        // the high queue climbed past 400 queued commands
                        // within seconds. A second producer with its own
                        // rate limit doesn't fix that: N simultaneously-stale
                        // channels still produce N bursts against the same
                        // ~6.7 commands/sec drain, however that N is paced.
                        // One arbiter picking one channel only when the queue
                        // has actually drained is the only way total
                        // production from this whole mechanism stays bounded
                        // to what the queue can actually clear.
                        let fastLaneCandidates = Array(Set(onChannels).union(stalePresence))
                        if self.highPriorityCommandQueue.isEmpty {
                            let pickedFastChannel = ShureAxientOverviewMeterPollScheduler.nextChannel(
                                among: fastLaneCandidates,
                                lastPolledAt: self.lastAxientOverviewFastMeterPollAt,
                                now: now,
                                minimumInterval: 0.4
                            )
                            if let fastChannel = pickedFastChannel {
                                self.sendAxientPresenceRefresh(for: fastChannel, priority: .high)
                                self.lastAxientOverviewFastMeterPollAt[fastChannel] = now
                                sentAnything = true
                            }
                        }

                        // Some Axient receivers acknowledge METER_RATE but don't
                        // continuously publish meter data that Relay can trust.
                        // Ask for RMS only: it is the value rendered by Overview,
                        // and one staggered request per channel per second limits
                        // even a 44-channel rig to 44 extra commands/sec.
                        let slowChannels = channels.filter { !onChannels.contains($0) }
                        if let meterChannel = ShureAxientOverviewMeterPollScheduler.nextChannel(
                            among: slowChannels,
                            lastPolledAt: self.lastAxientOverviewMeterPollAt,
                            now: now,
                            minimumInterval: 1.0
                        ) {
                            self.sendRaw("GET \(meterChannel) AUDIO_LEVEL_RMS")
                            self.lastAxientOverviewMeterPollAt[meterChannel] = now
                            sentAnything = true
                        }
                    } else {
                        // RF_ANTENNA is addressed per-channel (unlike the
                        // SAMPLE broadcast below, which can't distinguish
                        // channels) so it only goes to the channels whose
                        // presence specifically needs it -- independent of
                        // whether their RF/audio meters are already fresh.
                        if !stalePresence.isEmpty {
                            // Always .high, and rate-limited -- see the
                            // matching Axient comments above for why .normal
                            // here can starve forever and why this needs its
                            // own per-channel gate independent of priority.
                            for channelIndex in stalePresence {
                                let lastAttempt = self.lastStalePresenceRefreshAt[channelIndex]
                                guard lastAttempt == nil || now.timeIntervalSince(lastAttempt!) >= 1.0 else { continue }
                                self.sendUlxdPresenceRefresh(for: channelIndex, priority: .high)
                                self.lastStalePresenceRefreshAt[channelIndex] = now
                            }
                            sentAnything = true
                        }
                        // Broadcast devices can't be addressed per-channel
                        // here, but the broadcast still refreshes every
                        // channel at once, so any single stale channel is
                        // reason enough to send it.
                        if !staleMeter.isEmpty {
                            self.sendSampleAll()
                            sentAnything = true
                        }
                    }

                    if sentAnything {
                        self.lastFastTelemetryAt = now
                    }
                }

                // A tile-open channel no longer has any other source for its
                // FREQUENCY/battery fields (see the meterTick handler), so
                // both loops below cover every channel, just at high
                // priority for the ones with an open tile.
                if self.lastSlowRefreshAt == nil || now.timeIntervalSince(self.lastSlowRefreshAt ?? .distantPast) >= 45 {
                    for channelIndex in channels {
                        self.sendSlowPriorityRefresh(
                            for: channelIndex,
                            priority: tileOpenChannels.contains(channelIndex) ? .high : .normal
                        )
                    }
                    self.lastSlowRefreshAt = now
                }

                // Always .normal, even for tile-open channels: this fires a
                // 9-command battery/mute bundle for every channel at once.
                // At .high it directly competes with the presence-refresh
                // arbiter above for the same lane -- confirmed live, with 2
                // tile-open channels this alone injected ~6 high-priority
                // commands/sec (2 channels x 9 commands / 3s), leaving the
                // arbiter's own highPriorityCommandQueue.isEmpty gate almost
                // no window to ever fire, so presence evidence went stale
                // and channels read "Off" despite the actual fix above being
                // in place and correct. Battery/mute don't need sub-several-
                // second freshness the way presence/RF does, so this can
                // simply wait behind higher-priority traffic.
                let lastMediumRefresh = channels.compactMap { self.lastChannelSnapshotQueryAt[$0] }.max()
                if lastMediumRefresh == nil || now.timeIntervalSince(lastMediumRefresh ?? .distantPast) >= 20 {
                    for channelIndex in channels {
                        await self.sendMediumPriorityRefresh(for: channelIndex, priority: .normal)
                        self.lastChannelSnapshotQueryAt[channelIndex] = now
                    }
                }

                let baseInterval: TimeInterval
                if meterRateCapable {
                    if self.isAxientDeviceModel() {
                        // Four-channel AD4Q/ANX4 receivers can therefore cycle
                        // through each channel once per second without a burst.
                        baseInterval = 0.25
                    } else {
                        // Safety-net cadence: unprompted SAMPLE streaming should
                        // be covering the fast path already, so no need to poll
                        // faster than a few seconds here.
                        baseInterval = max(self.overviewPollingIntervalSeconds, 3.0)
                    }
                } else {
                    baseInterval = self.isConnected ? self.overviewPollingIntervalSeconds : 1.5
                }
                let jitter = Double(abs((self.device?.id.hashValue ?? 0) % 35)) / 1000.0
                try? await Task.sleep(nanoseconds: UInt64((baseInterval + jitter) * 1_000_000_000))
            }
            if Task.isCancelled {
                self.recordAD4QRFTrace("shared_poll_task_stopped reason=cancelled")
            }
            self.sharedPollingTask = nil
        }
    }

    private static func isAxientDeviceModel(_ device: ExternalDeviceConfig) -> Bool {
        if let model = device.shureNetworkModel {
            switch model {
            case .ad4, .ad4d, .ad4q, .anx4, .adtd, .adtq:
                return true
            default:
                break
            }
        }
        let model = (device.shureModelIdentifier ?? "").uppercased()
        if model.contains("AD4") || model.contains("ANX4") || model.contains("AXIENT") {
            return true
        }
        return false
    }

    private func isLicensedShureDevice(_ device: ExternalDeviceConfig) -> Bool {
        switch device.shureNetworkModel {
        case .anx4, .adtd, .adtq:
            return true
        default:
            return false
        }
    }

    func lastNonZeroMicAudioAt(for channelIndex: Int) -> Date? {
        micAudioLastNonZeroAt[channelIndex]
    }

    func micHoldWindowSeconds(for channelIndex: Int) -> Double {
        let meterRate = standardReportMeterRate(for: channelIndex) ?? 0
        if meterRate == 0 {
            return 6.0
        }
        return 2.0
    }

    func setLiveModeEnabled(_ enabled: Bool) {
        // Avoid redundant churn when the value doesn't change.
        guard liveModeEnabled != enabled else { return }
        liveModeEnabled = enabled

        if enabled {
            resetLiveTelemetryState()
            // Start/restore the live connection when entering Live Mode.
            if connection == nil, device != nil {
                if let device, isLicensedShureDevice(device), Self.shouldEmitConsoleLogs(for: device) {
                    print("[Shure] Live mode connect requested for \(device.name) \(device.host):\(device.port) model=\(device.shureModelIdentifier ?? "unknown")")
                }
                connect()
            } else if isConnected {
                // If already connected (shared service), re-apply the
                // effective METER_RATE (lastAppliedMeterRateMilliseconds was
                // just cleared by resetLiveTelemetryState) and prime one sample.
                applyEffectiveMeterRateIfNeeded()
                sendSampleAll()
            }
        } else {
            // In Edit Mode, fully disconnect so we stop receiving/parsing frames.
            resetReconnectState()
            disconnect()
        }

        refreshSharedPollingTask()
        scheduleTelemetrySnapshotPublish(immediate: true)
    }

    func setOverviewConsumerVisible(_ consumerID: UUID, visible: Bool) {
        if visible {
            overviewConsumerIDs.insert(consumerID)
        } else {
            overviewConsumerIDs.remove(consumerID)
        }
        refreshSharedPollingTask()
        scheduleTelemetrySnapshotPublish()
    }

    func setOverviewPollingInterval(_ interval: TimeInterval) {
        guard overviewPollingIntervalSeconds != interval else { return }
        overviewPollingIntervalSeconds = interval
        refreshSharedPollingTask()
        scheduleTelemetrySnapshotPublish()
    }

    func setOverviewMeterRateMilliseconds(_ ms: Int) {
        guard overviewMeterRateMilliseconds != ms else { return }
        overviewMeterRateMilliseconds = ms
        applyEffectiveMeterRateIfNeeded()
    }

    /// The `METER_RATE` (milliseconds) that should currently be in effect
    /// for this device overall: always 100ms whenever any channel-detail
    /// consumer (the single Shure module) is active anywhere on the
    /// device, otherwise the overview's requested rate. Retained for
    /// callers that only need a device-wide figure (e.g. UI display); the
    /// actual per-channel rate applied to hardware is
    /// effectiveMeterRateMilliseconds(for:).
    func effectiveMeterRateMilliseconds() -> Int {
        channelConsumerSelections.isEmpty ? overviewMeterRateMilliseconds : 100
    }

    /// The `METER_RATE` that should be in effect for one specific channel:
    /// 100ms (matching the single-tile module's own fixed rate) whenever
    /// that channel either has its own open tile or is currently resolved
    /// "on", otherwise the overview's requested (channel-count-scaled)
    /// rate. Applies uniformly across device families now.
    ///
    /// Axient used to be pinned to a 5000ms constant regardless of on/off/
    /// tile state, because its SAMPLE replies were discarded on receipt
    /// (see processSampleFrame's history) -- a fast METER_RATE produced
    /// pure waste back then: a live capture showed 10Hz streaming on an
    /// AD4Q flooding 2,718 of 5,802 received lines with SAMPLE frames that
    /// were thrown away, while GET/REP polling (Axient's only real
    /// telemetry source at the time) got 3,192 REP ERR replies in the same
    /// 45s window -- sticky meters, a 0-level channel reading several bars
    /// high, the performance-strain banner flickering. That's no longer
    /// the tradeoff: Axient's SAMPLE stream is now trusted and parsed
    /// (processAxientSampleFrame), so it's the real, low-overhead data
    /// source a fast rate is meant to feed, not competing waste -- and
    /// unlike the GET/REP traffic that flood was actually starving,
    /// unprompted SAMPLE frames don't consume the outgoing command queue
    /// at all. Reported live as "meter feels slow" while this was still
    /// pinned slow, confirming the fast/slow split should apply the same
    /// way it already does for ULX-D.
    private func effectiveMeterRateMilliseconds(for channelIndex: Int, now: Date) -> Int {
        if channelConsumerSelections.values.contains(channelIndex) {
            return 100
        }
        if resolvedTelemetryTransmitterState(for: channelIndex, now: now) == .on {
            return 100
        }
        return overviewMeterRateMilliseconds
    }

    /// Re-applies `METER_RATE` on the live connection, per channel, when a
    /// channel's effective rate has changed (a tile attached/detached, the
    /// overview hub requested a new tier, or the channel's on/off state
    /// changed). No-ops per channel where the effective rate hasn't
    /// changed; no-ops entirely if the device isn't a meter-capable model.
    private func applyEffectiveMeterRateIfNeeded() {
        guard liveModeEnabled, isConnected, connection != nil, let device else { return }
        guard Self.isMeterRateCapableDevice(device) else { return }

        let channelCount = inferredChannelCount(for: device)
        guard channelCount > 0 else { return }

        let now = Date()
        for ch in 1...channelCount {
            let effective = effectiveMeterRateMilliseconds(for: ch, now: now)
            guard lastAppliedMeterRateMilliseconds[ch] != effective else { continue }
            lastAppliedMeterRateMilliseconds[ch] = effective
            sendRaw("SET \(ch) METER_RATE \(String(format: "%05d", effective))")
        }
    }

    private static func isMeterRateCapableDevice(_ device: ExternalDeviceConfig) -> Bool {
        let model = (device.shureModelIdentifier ?? "").uppercased()
        // QLX-D ("QLXD4" in ExternalDevices.swift's model enum) was missing
        // here entirely -- confirmed live: with no METER_RATE ever sent, a
        // real QLXD4 never streamed a single unprompted SAMPLE frame all
        // show, leaving it fully dependent on the non-meterRateCapable
        // fallback's sendSampleAll() ("SAMPLE 0 ALL"), which isn't a real
        // request a receiver answers on its own -- it only ever "worked" for
        // other devices because genuine METER_RATE streaming was already
        // covering them regardless of whether that fallback succeeded.
        // processSampleFrame's non-Axient parser already treats QLX-D's
        // SAMPLE format as the same shape as ULX-D's (see its own comment),
        // so no separate parsing path is needed here.
        return model.contains("ULXD") || model.contains("QLXD") || model.contains("AD4") || model.contains("ANX4") || model.contains("AXIENT")
    }

    func setChannelConsumer(_ consumerID: UUID, channelIndex: Int?) {
        if let channelIndex {
            channelConsumerSelections[consumerID] = channelIndex
        } else {
            channelConsumerSelections.removeValue(forKey: consumerID)
        }
        applyEffectiveMeterRateIfNeeded()
        // The shared polling loop now covers single-tile channels too (see
        // refreshSharedPollingTask's needsPolling), so a tile opening with
        // no Overview module anywhere on the canvas still needs this to
        // actually start the loop, not just adjust METER_RATE.
        refreshSharedPollingTask()
        scheduleTelemetrySnapshotPublish()
    }

    func removeConsumer(_ consumerID: UUID) {
        overviewConsumerIDs.remove(consumerID)
        channelConsumerSelections.removeValue(forKey: consumerID)
        applyEffectiveMeterRateIfNeeded()
        refreshSharedPollingTask()
        scheduleTelemetrySnapshotPublish()
    }

    private func sendInitialChannelQueries() {
        guard let device, let connection else { return }
        startTcpStartupSequence(for: device, connection: connection)
    }

    private func enableMeterRateIfNeeded() {
        guard let device, let connection else { return }
        startTcpStartupSequence(for: device, connection: connection)
    }


    /// Infer how many RF channels a given Shure device exposes.
    ///
    /// Returns 1, 2, or 4 for common Shure models.
    private func inferredChannelCount(for device: ExternalDeviceConfig) -> Int {
        device.effectiveShureChannelCount
    }

    private func shouldQueryTxDeviceID(for device: ExternalDeviceConfig) -> Bool {
        let model = (device.shureModelIdentifier ?? "").uppercased()
        let upperName = device.name.uppercased()
        if model == "P10T" || model.contains("PSM900") || model.contains("ADTD") || model.contains("ADTQ") {
            return false
        }
        if upperName.contains("P10T") || upperName.contains("PSM 900") || upperName.contains("PSM900") {
            return false
        }
        return Self.isAxientDeviceModel(device)
    }

    private func shouldQueryTxDeviceID() -> Bool {
        guard let device else { return false }
        return shouldQueryTxDeviceID(for: device)
    }

    private func resolvedUdpTelemetryEndpoint(for device: ExternalDeviceConfig) -> (host: String, port: UInt16)? {
        guard effectiveShureTransportMode(for: device) != .tcpOnly else {
            return nil
        }
        if let sdtPort = device.shureSdtPort {
            let sdtHost = device.shureSdtHost?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ((sdtHost?.isEmpty == false ? sdtHost! : device.host), sdtPort)
        }

        if let cached = ShureDiscoveryEndpointCache.endpoint(host: device.host, cid: device.shureDiscoveryCID) {
            return (cached.host, cached.port)
        }

        if Self.isUdpOnlyShureDevice(device) {
            return (device.host, 57383)
        }

        return nil
    }

    private func shouldStartFastUdpTelemetry(for device: ExternalDeviceConfig) -> Bool {
        Self.isFastUdpTelemetryCapableDevice(device)
            && !Self.isFastUdpTelemetryDisabledByDefault(device)
            && liveModeEnabled
            && resolvedUdpTelemetryEndpoint(for: device) != nil
    }

    private func shouldPreferFastUdpRfTelemetry(channelIndex: Int, now: Date = Date()) -> Bool {
        guard let updatedAt = fastUdpRfLastUpdated[channelIndex] else { return false }
        return now.timeIntervalSince(updatedAt) <= 1.2
    }

    private func shouldExposeFastUdpRfTelemetry(channelIndex: Int, now: Date = Date()) -> Bool {
        guard shouldPreferFastUdpRfTelemetry(channelIndex: channelIndex, now: now) else {
            return false
        }
        if shouldTrustFastUdpPresenceEvidence() {
            return true
        }
        if shouldQueryTxDeviceID(),
           let lastUpdated = channelTransmitterDeviceIDLastUpdated[channelIndex],
           let transmitterPresent = channelTransmitterDeviceIDPresent[channelIndex],
           transmitterPresent,
           now.timeIntervalSince(lastUpdated) <= 6.0 {
            return true
        }
        if let lastUpdated = channelTransmitterPresentLastUpdated[channelIndex],
           let transmitterPresent = channelTransmitterPresent[channelIndex],
           transmitterPresent,
           now.timeIntervalSince(lastUpdated) <= 6.0 {
            return true
        }
        return false
    }

    private func shouldPreferFastUdpMicTelemetry(channelIndex: Int, now: Date = Date()) -> Bool {
        guard let updatedAt = fastUdpMicLastUpdated[channelIndex] else { return false }
        return now.timeIntervalSince(updatedAt) <= 1.2
    }

    private func snapshotCompositionPolicy(
        channelIndex: Int,
        now: Date = Date()
    ) -> ShureSnapshotCompositionPolicy {
        ShureSnapshotCompositionPolicy(
            preferUdpRf: shouldExposeFastUdpRfTelemetry(channelIndex: channelIndex, now: now),
            preferUdpMic: shouldPreferFastUdpMicTelemetry(channelIndex: channelIndex, now: now)
        )
    }

    private func fastUdpChannelIndex(from rawChannelIndex: Int) -> Int {
        guard let device, Self.isFastUdpTelemetryCapableDevice(device) else {
            return rawChannelIndex
        }
        return rawChannelIndex + 1
    }

    private func updateFastUdpTransmitterPresence(channelIndex: Int, isPresent: Bool, now: Date) {
        if channelTransmitterPresent[channelIndex] != isPresent {
            channelTransmitterPresent[channelIndex] = isPresent
        }
        channelTransmitterPresentLastUpdated[channelIndex] = now
        if isPresent {
            channelTransmitterPresentLastTrueAt[channelIndex] = now
            markChannelPresence(channelIndex: channelIndex, now: now)
        } else {
            channelTransmitterPresentLastFalseAt[channelIndex] = now
        }
    }

    private func shouldTrustFastUdpPresenceEvidence() -> Bool {
        guard let device else { return false }
        return Self.isUdpOnlyShureDevice(device)
    }

    private func resetLiveTelemetryState() {
        resetReconnectState()
        recentReports.removeAll()
        lastHeardAt = nil
        lastError = nil
        lastAxientOverviewMeterPollAt.removeAll()
        lastAxientOverviewFastMeterPollAt.removeAll()
        lastStalePresenceRefreshAt.removeAll()
        lastChannelSnapshotQueryAt.removeAll()
        lastAppliedMeterRateMilliseconds.removeAll()
        channelFrequencies.removeAll()
        rfTxLevels.removeAll()
        rfTxLastUpdated.removeAll()
        psmAudioLevels.removeAll()
        micAudioLevels.removeAll()
        micAudioLastUpdated.removeAll()
        micAudioStereoLevels.removeAll()
        micAudioLastNonZeroAt.removeAll()
        axientAudioBitmapAllowsLevel.removeAll()
        channelMicAudioOverload.removeAll()
        channelBatteryLabels.removeAll()
        channelBatteryPercentages.removeAll()
        channelBatteryIsApproximate.removeAll()
        channelBatteryPriority.removeAll()
        channelBatteryHasSmartTelemetry.removeAll()
        channelBatteryCalculationPendingAt.removeAll()
        channelBatteryLastUpdated.removeAll()
        channelPresenceLastSeenAt.removeAll()
        channelAxientPositiveEvidenceLastSeenAt.removeAll()
        channelAxientNegativeEvidenceStreakStartAt.removeAll()
        channelAxientRfBarsByAntenna.removeAll()
        channelTransmitterPresent.removeAll()
        channelTransmitterPresentLastUpdated.removeAll()
        channelTransmitterPresentLastTrueAt.removeAll()
        channelTransmitterPresentLastFalseAt.removeAll()
        channelTransmitterDeviceIDPresent.removeAll()
        channelTransmitterDeviceIDLastUpdated.removeAll()
        channelRFBarCounts.removeAll()
        channelRfLastUpdated.removeAll()
        channelAudioMutes.removeAll()
        channelMeterRates.removeAll()
        shadowStandardReportSnapshots.removeAll()
        shadowStandardReportLowFrequencySnapshots.removeAll()
        fastUdpRfLastUpdated.removeAll()
        fastUdpMicLastUpdated.removeAll()
        fastUdpRfAntenna12Levels.removeAll()
        fastUdpRfAntenna13Levels.removeAll()
        activeUdpEndpointHost = nil
        activeUdpEndpointPort = nil
        debugTelemetryProtocolLabel = DebugTelemetryProtocol.tcp2202.rawValue
        Task {
            await standardReportStateStore.clear()
        }
    }

    private func activeUdpEndpointDescription(fallbackHost: String? = nil, fallbackPort: UInt16? = nil) -> String {
        let host = activeUdpEndpointHost ?? fallbackHost ?? device?.host ?? "unknown"
        let port = activeUdpEndpointPort ?? fallbackPort ?? device?.shureSdtPort ?? 57383
        return "\(host):\(port)"
    }

    private func scheduleFastUdpDecodeTimeoutLog(for device: ExternalDeviceConfig, endpoint: (host: String, port: UInt16)) {
        fastUdpDecodeTimeoutTask?.cancel()
        didLogFastUdpFallbackNoDecode = false
        fastUdpDecodeTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            guard self.udpConnection != nil else { return }
            guard !self.didLogAnx4MeterDecoded, !self.didLogAnx4RFDecoded, !self.didLogFastUdpFallbackNoDecode else { return }
            self.didLogFastUdpFallbackNoDecode = true
            RelayDiagnosticsStore.shared.recordShureTrace(
                "module udp_fallback \(device.name) \(endpoint.host):\(endpoint.port) reason=no_decode_within_timeout"
            )
        }
    }

    private func fastUdpPropertyAddresses(for device: ExternalDeviceConfig) -> [[UInt8]] {
        if Self.isFastUdpTelemetryCapableDevice(device) {
            return ShureAnx4Handshake.ulxdFastTelemetryPropertyAddresses
        }
        return ShureAnx4Handshake.defaultPropertyAddresses
    }

    private func fastUdpChannelIndices(for device: ExternalDeviceConfig) -> [Int] {
        let channelCount = max(1, inferredChannelCount(for: device))
        return Array(1...channelCount)
    }

    private func fastUdpRfPropertyPair(for channelIndex: Int) -> (first: [UInt8], second: [UInt8]) {
        let channelByte = UInt8(max(0, channelIndex - 1) & 0xFF)
        return (
            first: [0x02, channelByte, 0x08, 0x12],
            second: [0x02, channelByte, 0x08, 0x13]
        )
    }

    private func maybeStartFastUdpTelemetry(for device: ExternalDeviceConfig) {
        guard shouldStartFastUdpTelemetry(for: device) else {
            if effectiveShureTransportMode(for: device) == .tcpOnly {
                RelayDiagnosticsStore.shared.recordShureTrace(
                    "module udp_disabled \(device.name) \(device.host):\(device.port) model=\(device.shureModelIdentifier ?? "unknown") transport=\(transportModeLogLabel(for: device))"
                )
            }
            return
        }
        guard udpConnection == nil else { return }
        connectAnx4Udp(device, endpoint: resolvedUdpTelemetryEndpoint(for: device), udpOnly: false)
    }

    private func stopFastUdpTelemetrySidecar() {
        udpConnection?.cancel()
        udpConnection = nil
        anx4TelemetryLoopTask?.cancel()
        anx4TelemetryLoopTask = nil
        fastUdpDecodeTimeoutTask?.cancel()
        fastUdpDecodeTimeoutTask = nil
        didLogAnx4Receive = false
        didLogAnx4MeterDecoded = false
        didLogAnx4RFDecoded = false
        didLogFastUdpFallbackNoDecode = false
        fastUdpRfLastUpdated.removeAll()
        fastUdpMicLastUpdated.removeAll()
        fastUdpRfAntenna12Levels.removeAll()
        fastUdpRfAntenna13Levels.removeAll()
        activeUdpEndpointHost = nil
        activeUdpEndpointPort = nil
        debugTelemetryProtocolLabel = DebugTelemetryProtocol.tcp2202.rawValue
    }

    // MARK: - Receive

    private func startReceiveLoop() {
        guard let connection else { return }

        let isVerboseLogging = Self.isVerboseLogging

        let deviceSnapshot = device
        let verbosePsm = Self.isVerbosePsmLogging
        let verboseMic = Self.isVerboseMicLogging
        let receiveGate = tcpReceiveGate
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard receiveGate.isActive() else { return }
            Task { @MainActor [weak self] in
                guard let self, receiveGate.isActive(), self.connection === connection else { return }

                if let data {
                    if data.isEmpty {
                        if isVerboseLogging {
                            print("[ShureWirelessService] \(self.deviceLogTag) Received empty packet")
                        }
                    } else if let text = String(data: data, encoding: .utf8) {
                        self.recordLiveSyncIfNeeded()
                        if isVerboseLogging {
                            let modelCode = deviceSnapshot?.shureModelIdentifier?.uppercased()
                            let isPsmTransmitter = (modelCode == "P10T")
                            if (isPsmTransmitter && verbosePsm) || (!isPsmTransmitter && verboseMic) {
                                print("[ShureWirelessService] \(self.deviceLogTag) Received \(data.count) bytes: \"\(text)\"")
                            }
                        }
                        await self.handleIncoming(text: text)
                    } else {
                        if isVerboseLogging {
                            print("[ShureWirelessService] \(self.deviceLogTag) Received \(data.count) bytes (non-UTF8): \(data as NSData)")
                        }
                    }
                }

                if let error {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.logDiagnosticError("Receive error from \(self.device?.host ?? "unknown"):\(self.device?.port ?? 0) — \(error.localizedDescription)", keySuffix: "receive_error")
                    print("[ShureWirelessService] \(self.deviceLogTag) Receive error: \(error)")
                    return
                }

                if isComplete {
                    self.isConnected = false
                    if isVerboseLogging {
                        print("[ShureWirelessService] \(self.deviceLogTag) Connection marked complete by remote")
                    }
                    return
                }

                guard self.liveModeEnabled else { return }
                self.startReceiveLoop()
            }
        }
    }

    private func recordLiveSyncIfNeeded(force: Bool = false) {
        guard let deviceID else { return }
        let now = Date()
        if !force, let lastLiveSyncPersistAt, now.timeIntervalSince(lastLiveSyncPersistAt) < 30 {
            return
        }
        lastLiveSyncPersistAt = now
        ExternalDevicesStore.shared.updateDevice(id: deviceID) { device in
            device.lastChannelSyncAt = now
            let preferredDisplayName = preferredShureDisplayName(for: device)
            let currentDisplayName = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let deviceIDName = device.shureDeviceIDName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let shouldNormalizeDisplayName = Self.isUdpOnlyShureDevice(device)
                && (
                    currentDisplayName.isEmpty
                        || (!deviceIDName.isEmpty && currentDisplayName.caseInsensitiveCompare(deviceIDName) == .orderedSame)
                )
            if shouldNormalizeDisplayName,
               currentDisplayName.caseInsensitiveCompare(preferredDisplayName) != .orderedSame {
                device.name = preferredDisplayName
            }
        }
    }

    private func hasBatteryValue(for channelIndex: Int) -> Bool {
        if let percent = standardReportBatteryPercentage(for: channelIndex) {
            return percent > 0
        }
        return standardReportBatteryLabel(for: channelIndex) != nil
    }

    private func shouldAcceptMicLevel(_ level: Double, channelIndex: Int, now: Date) -> Bool {
        guard level <= 0, hasBatteryValue(for: channelIndex) else {
            return true
        }
        let holdSeconds = micHoldWindowSeconds(for: channelIndex)
        guard let lastNonZero = micAudioLastNonZeroAt[channelIndex] else {
            return true
        }
        return now.timeIntervalSince(lastNonZero) >= holdSeconds
    }

    private func updateMicLevel(
        _ level: Double,
        keyUpper: String,
        channelIndex: Int,
        now: Date,
        persistPublishedLevel: Bool = true,
        bypassHold: Bool = false
    ) {
        guard bypassHold || shouldAcceptMicLevel(level, channelIndex: channelIndex, now: now) else {
            return
        }

        if level > 0 {
            micAudioLastNonZeroAt[channelIndex] = now
        }

        if persistPublishedLevel {
            if keyUpper == "AUDIO_IN_LVL_L" || keyUpper == "AUDIO_IN_LVL_R" {
                var stereo = micAudioStereoLevels[channelIndex] ?? (left: 0.0, right: 0.0)
                if keyUpper == "AUDIO_IN_LVL_L" {
                    stereo.left = level
                } else {
                    stereo.right = level
                }
                micAudioStereoLevels[channelIndex] = stereo
                micAudioLevels[channelIndex] = max(stereo.left, stereo.right)
            } else {
                micAudioLevels[channelIndex] = level
            }
        }

        micAudioLastUpdated[channelIndex] = now
        if Self.isVerboseMicLogging {
            print("[ShureWirelessService] \(deviceLogTag) MIC AUDIO \(keyUpper) ch \(channelIndex): \(level)")
        }
    }

    private func updatePSMAudioLevel(_ level: Double, keyUpper: String, channelIndex: Int) {
        var current = psmAudioLevels[channelIndex] ?? (left: 0.0, right: 0.0)
        if keyUpper == "AUDIO_IN_LVL_L" {
            current.left = level
        } else {
            current.right = level
        }
        psmAudioLevels[channelIndex] = current
        scheduleTelemetrySnapshotPublish()
        if Self.isVerbosePsmLogging {
            print("[ShureWirelessService] \(deviceLogTag) PSM AUDIO_IN \(keyUpper == "AUDIO_IN_LVL_L" ? "L" : "R") ch \(channelIndex): \(level)")
        }
    }

    private func currentStandardReportSnapshot(channelIndex: Int) -> ShureStandardReportChannelSnapshot {
        if let shadow = shadowStandardReportSnapshots[channelIndex] {
            return shadow
        }
        if let lowFrequencyShadow = shadowStandardReportLowFrequencySnapshots[channelIndex] {
            return ShureStandardReportChannelSnapshot(
                channelName: lowFrequencyShadow.channelName,
                rfTxLevel: nil,
                frequencyDisplay: lowFrequencyShadow.frequencyDisplay,
                batteryLabel: lowFrequencyShadow.batteryLabel,
                batteryPercentage: lowFrequencyShadow.batteryPercentage,
                batteryIsApproximate: lowFrequencyShadow.batteryIsApproximate,
                batteryPriority: nil,
                audioMute: lowFrequencyShadow.audioMute,
                meterRate: lowFrequencyShadow.meterRate,
                rfBarCount: nil,
                rfOverload: nil,
                micAudioLevel: nil,
                micAudioOverload: nil
            )
        }
        return ShureStandardReportChannelSnapshot(
            channelName: nil,
            rfTxLevel: nil,
            frequencyDisplay: nil,
            batteryLabel: nil,
            batteryPercentage: nil,
            batteryIsApproximate: nil,
            batteryPriority: nil,
            audioMute: nil,
            meterRate: nil,
            rfBarCount: nil,
            rfOverload: nil,
            micAudioLevel: nil,
            micAudioOverload: nil
        )
    }

    private func currentStandardReportLowFrequencySnapshot(channelIndex: Int) -> ShureStandardReportLowFrequencySnapshot {
        if let shadow = shadowStandardReportLowFrequencySnapshots[channelIndex] {
            return shadow
        }
        if let shadow = shadowStandardReportSnapshots[channelIndex] {
            return lowFrequencySnapshot(from: shadow)
        }
        return ShureStandardReportLowFrequencySnapshot(
            channelName: nil,
            frequencyDisplay: nil,
            batteryLabel: nil,
            batteryPercentage: nil,
            batteryIsApproximate: nil,
            audioMute: nil,
            meterRate: nil
        )
    }

    func standardReportChannelIndices() -> [Int] {
        var channels = Set<Int>()
        channels.formUnion(shadowStandardReportSnapshots.keys)
        channels.formUnion(channelNames.keys)
        channels.formUnion(channelBatteryPercentages.keys)
        channels.formUnion(channelRFBarCounts.keys)
        channels.formUnion(micAudioLevels.keys)
        channels.formUnion(psmAudioLevels.keys)
        return channels.sorted()
    }

    func standardReportChannelName(for channelIndex: Int) -> String? {
        currentStandardReportSnapshot(channelIndex: channelIndex).channelName
    }

    func standardReportFrequencyDisplay(for channelIndex: Int) -> String? {
        currentStandardReportLowFrequencySnapshot(channelIndex: channelIndex).frequencyDisplay
    }

    func standardReportRfTxLevel(for channelIndex: Int) -> Int? {
        currentStandardReportSnapshot(channelIndex: channelIndex).rfTxLevel
    }

    func standardReportBatteryPercentage(for channelIndex: Int) -> Int? {
        currentStandardReportSnapshot(channelIndex: channelIndex).batteryPercentage
    }

    func standardReportBatteryLabel(for channelIndex: Int) -> String? {
        currentStandardReportLowFrequencySnapshot(channelIndex: channelIndex).batteryLabel
    }

    func standardReportAudioMute(for channelIndex: Int) -> Bool? {
        currentStandardReportLowFrequencySnapshot(channelIndex: channelIndex).audioMute
    }

    func standardReportMeterRate(for channelIndex: Int) -> Int? {
        currentStandardReportLowFrequencySnapshot(channelIndex: channelIndex).meterRate
    }

    func standardReportRfBarCount(for channelIndex: Int) -> Int? {
        currentStandardReportSnapshot(channelIndex: channelIndex).rfBarCount
    }

    func standardReportRfOverload(for channelIndex: Int) -> Bool? {
        currentStandardReportSnapshot(channelIndex: channelIndex).rfOverload
    }

    func standardReportMicAudioLevel(for channelIndex: Int) -> Double? {
        currentStandardReportSnapshot(channelIndex: channelIndex).micAudioLevel
    }

    func standardReportMicAudioOverload(for channelIndex: Int) -> Bool? {
        currentStandardReportSnapshot(channelIndex: channelIndex).micAudioOverload
    }

    func liveAudioLevel(for channelIndex: Int) -> Double? {
        if let level = standardReportMicAudioLevel(for: channelIndex) {
            return level
        }
        if let lr = psmAudioLevels[channelIndex] {
            return (lr.left + lr.right) / 2.0
        }
        return nil
    }

    private nonisolated static func isRuntimeBatteryKey(_ key: String) -> Bool {
        key == "TX_BATT_MINS" || key == "BATT_MINS" || key == "BATT_RUN_TIME"
    }

    private nonisolated static func isExactBatteryPercentKey(_ key: String) -> Bool {
        key == "TX_BATT_CHARGE_PERCENT"
            || key == "BATT_CHARGE"
            || key == "TX_BATT_PERCENT"
            || key == "BATT_PERCENT"
    }

    func shouldShowBatteryCalculationPlaceholder(for channelIndex: Int) -> Bool {
        guard let pendingAt = channelBatteryCalculationPendingAt[channelIndex] else { return false }
        guard Date().timeIntervalSince(pendingAt) <= 8.0 else { return false }
        guard hasBatteryValue(for: channelIndex) else { return false }
        guard channelBatteryHasSmartTelemetry[channelIndex] == true else { return false }
        return (channelBatteryPriority[channelIndex] ?? 0) < 3
    }

    func shadowFrequencyDisplay(for channelIndex: Int) -> String? {
        shadowStandardReportLowFrequencySnapshots[channelIndex]?.frequencyDisplay
    }

    func shadowRfTxLevel(for channelIndex: Int) -> Int? {
        shadowStandardReportSnapshots[channelIndex]?.rfTxLevel
    }

    func shadowBatteryPercentage(for channelIndex: Int) -> Int? {
        shadowStandardReportSnapshots[channelIndex]?.batteryPercentage
    }

    func shadowBatteryLabel(for channelIndex: Int) -> String? {
        shadowStandardReportLowFrequencySnapshots[channelIndex]?.batteryLabel
    }

    func shadowAudioMute(for channelIndex: Int) -> Bool? {
        shadowStandardReportLowFrequencySnapshots[channelIndex]?.audioMute
    }

    func shadowMeterRate(for channelIndex: Int) -> Int? {
        shadowStandardReportLowFrequencySnapshots[channelIndex]?.meterRate
    }

    func shadowChannelName(for channelIndex: Int) -> String? {
        shadowStandardReportLowFrequencySnapshots[channelIndex]?.channelName
    }

    func shadowRfBarCount(for channelIndex: Int) -> Int? {
        shadowStandardReportSnapshots[channelIndex]?.rfBarCount
    }

    func shadowMicAudioLevel(for channelIndex: Int) -> Double? {
        shadowStandardReportSnapshots[channelIndex]?.micAudioLevel
    }

    private func markChannelPresence(channelIndex: Int, now: Date) {
        channelPresenceLastSeenAt[channelIndex] = now
    }

    private func markAxientPositivePresenceEvidence(channelIndex: Int, now: Date) {
        channelAxientPositiveEvidenceLastSeenAt[channelIndex] = now
        markChannelPresence(channelIndex: channelIndex, now: now)
    }

    private func hasAxientPositivePresenceEvidence(frame: ShureIncomingFrame) -> Bool {
        guard isAxientDeviceModel(), frame.parts.count >= 4 else { return false }
        let key = frame.parts[2].uppercased()

        switch key {
        case "TX_DEVICE_ID":
            if let value = ShureIncomingFrameParser.bracedValue(in: frame.rawLine) {
                return !value.isEmpty
            }
            return false
        case "TX_BATT_HEALTH_PERCENT":
            if let value = ShureIncomingFrameParser.firstInt(afterKey: key, in: frame) {
                return value > 0 && value < 255
            }
            return false
        case "TX_BATT_TEMP_C", "TX_BATT_TEMP_F", "TX_POWER_LEVEL":
            if let value = ShureIncomingFrameParser.firstInt(afterKey: key, in: frame) {
                return value >= 0 && value < 255
            }
            return false
        case "TX_LOCK":
            return frame.parts.dropFirst(3).first?.uppercased() == "NONE"
        default:
            return false
        }
    }

    private func applyShadowStandardReportSnapshot(
        channelIndex: Int,
        mirrored: ShureStandardReportChannelSnapshot
    ) {
        shadowStandardReportSnapshots[channelIndex] = mirrored
        if let channelName = mirrored.channelName {
            channelNames[channelIndex] = channelName
        } else {
            channelNames.removeValue(forKey: channelIndex)
        }
        if let rfTxLevel = mirrored.rfTxLevel {
            rfTxLevels[channelIndex] = rfTxLevel
        } else {
            rfTxLevels.removeValue(forKey: channelIndex)
        }
        if let frequencyDisplay = mirrored.frequencyDisplay {
            channelFrequencies[channelIndex] = frequencyDisplay
        } else {
            channelFrequencies.removeValue(forKey: channelIndex)
        }
        if let batteryLabel = mirrored.batteryLabel {
            channelBatteryLabels[channelIndex] = batteryLabel
        } else {
            channelBatteryLabels.removeValue(forKey: channelIndex)
        }
        if let batteryPercentage = mirrored.batteryPercentage {
            channelBatteryPercentages[channelIndex] = batteryPercentage
        } else {
            channelBatteryPercentages.removeValue(forKey: channelIndex)
        }
        if let batteryIsApproximate = mirrored.batteryIsApproximate {
            channelBatteryIsApproximate[channelIndex] = batteryIsApproximate
        } else {
            channelBatteryIsApproximate.removeValue(forKey: channelIndex)
        }
        if let batteryPriority = mirrored.batteryPriority {
            channelBatteryPriority[channelIndex] = batteryPriority
        } else {
            channelBatteryPriority.removeValue(forKey: channelIndex)
        }
        if let audioMute = mirrored.audioMute {
            channelAudioMutes[channelIndex] = audioMute
        } else {
            channelAudioMutes.removeValue(forKey: channelIndex)
        }
        if let meterRate = mirrored.meterRate {
            channelMeterRates[channelIndex] = meterRate
        } else {
            channelMeterRates.removeValue(forKey: channelIndex)
        }
        if let rfBarCount = mirrored.rfBarCount {
            channelRFBarCounts[channelIndex] = rfBarCount
        } else {
            channelRFBarCounts.removeValue(forKey: channelIndex)
        }
        if let micAudioLevel = mirrored.micAudioLevel {
            micAudioLevels[channelIndex] = micAudioLevel
        } else {
            micAudioLevels.removeValue(forKey: channelIndex)
        }
    }

    private func lowFrequencySnapshot(from snapshot: ShureStandardReportChannelSnapshot) -> ShureStandardReportLowFrequencySnapshot {
        ShureStandardReportLowFrequencySnapshot(
            channelName: snapshot.channelName,
            frequencyDisplay: snapshot.frequencyDisplay,
            batteryLabel: snapshot.batteryLabel,
            batteryPercentage: snapshot.batteryPercentage,
            batteryIsApproximate: snapshot.batteryIsApproximate,
            audioMute: snapshot.audioMute,
            meterRate: snapshot.meterRate
        )
    }

    private func applyShadowStandardReportLowFrequencySnapshot(
        channelIndex: Int,
        mirrored: ShureStandardReportChannelSnapshot,
        line: String
    ) {
        applyShadowStandardReportSnapshot(channelIndex: channelIndex, mirrored: mirrored)
        let shadow = lowFrequencySnapshot(from: mirrored)
        shadowStandardReportLowFrequencySnapshots[channelIndex] = shadow
        scheduleTelemetrySnapshotPublish()
#if DEBUG
        guard Self.isVerboseLogging else { return }
        let expected = currentStandardReportLowFrequencySnapshot(channelIndex: channelIndex)
        guard shadow != expected else { return }
        RelayDiagnosticsStore.shared.recordShureTrace(
            "module standard_report_low_frequency_shadow_mismatch ch=\(channelIndex) expected=\(String(describing: expected)) shadow=\(String(describing: shadow)) line=\(line)"
        )
#endif
    }

    private func verifyMirroredStandardReportState(
        channelIndex: Int,
        mirrored: ShureStandardReportChannelSnapshot,
        line: String
    ) {
#if DEBUG
        guard Self.isVerboseLogging else { return }
        let expected = currentStandardReportSnapshot(channelIndex: channelIndex)
        guard mirrored != expected else { return }
        RelayDiagnosticsStore.shared.recordShureTrace(
            "module standard_report_mirror_mismatch ch=\(channelIndex) expected=\(String(describing: expected)) mirrored=\(String(describing: mirrored)) line=\(line)"
        )
#endif
    }

    private func rfBars(fromDbm dbm: Double) -> Int {
        switch dbm {
        case let v where v >= -45: return 5
        case -60 ..< -45: return 4
        case -75 ..< -60: return 3
        case -90 ..< -75: return 2
        case -105 ..< -90: return 1
        default: return 0
        }
    }

    private func smoothedAxientRfBarCount(_ rawBars: Int, channelIndex: Int, now: Date) -> Int {
        let newState = ShureAxientRfBarHoldResolver.resolve(
            rawBars: rawBars,
            previousState: channelRfBarHoldState[channelIndex],
            now: now
        )
        channelRfBarHoldState[channelIndex] = newState
        return newState.acceptedValue
    }

    private nonisolated static func prepareIncomingData(
        text: String,
        isAxientDevice: Bool,
        contextSnapshot: ShureReportContextSnapshot,
        now: Date
    ) async -> ShurePreparedIncomingData {
        let task = Task.detached(priority: .utility) {
            let frames = ShureIncomingFrameParser.extractFrames(from: text)
            let reportWorkItems: [ShurePreparedReportWorkItem] = frames.enumerated().compactMap { index, frame in
                guard frame.parts.count >= 3, frame.isReportVerb else { return nil }
                guard let channelIndex = frame.firstNumericChannelIndex else {
                    return ShurePreparedReportWorkItem(
                        frameIndex: index,
                        channelIndex: nil,
                        reduction: nil
                    )
                }

                let context = ShureReportReductionContext(
                    isAxientDevice: isAxientDevice,
                    hasBatteryValue: contextSnapshot.hasBatteryValueByChannel[channelIndex] ?? false,
                    meterRate: contextSnapshot.meterRates[channelIndex] ?? 0,
                    lastNonZeroMicAudioAt: contextSnapshot.lastNonZeroMicAudioAt[channelIndex],
                    now: now
                )
                return ShurePreparedReportWorkItem(
                    frameIndex: index,
                    channelIndex: channelIndex,
                    reduction: ShureReportReducer.reduce(frame: frame, context: context)
                )
            }
            return ShurePreparedIncomingData(
                frames: frames,
                reportWorkItems: reportWorkItems
            )
        }
        return await task.value
    }

    @MainActor
    private func processReportedFrame(
        _ frame: ShureIncomingFrame,
        prepared: ShurePreparedReportWorkItem,
        now: Date
    ) {
        guard liveModeEnabled else { return }
        let line = frame.rawLine
        guard let chIndex = prepared.channelIndex else {
            // Check the verbose flag FIRST so these per-part string scans
            // (uppercasing + comparing every token) don't run on the main
            // thread for every frame when verbose logging is off.
            if Self.isVerboseLogging {
                if frame.parts.contains(where: { $0.uppercased() == "CHAN_NAME" }) {
                    print("[ShureWirelessService] \(deviceLogTag) CHAN_NAME line without numeric channel index (line: \(line))")
                }
                if frame.parts.contains(where: { $0.uppercased() == "RF_TX_LVL" }) {
                    print("[ShureWirelessService] \(deviceLogTag) RF_TX_LVL line without numeric channel index (line: \(line))")
                }
                if frame.parts.contains(where: { $0.uppercased() == "FREQUENCY" }) {
                    print("[ShureWirelessService] \(deviceLogTag) FREQUENCY line without numeric channel index (line: \(line))")
                }
            }
            return
        }

        guard let reduction = prepared.reduction else { return }

        if let cleaned = reduction.channelName {
            if let deviceID = device?.id {
                ExternalDevicesStore.shared.cacheShureChannelName(
                    deviceID: deviceID,
                    channelIndex: chIndex,
                    name: cleaned
                )
            }
            if Self.isVerboseLogging {
                print("[ShureWirelessService] \(deviceLogTag) CHAN_NAME parsed for channel \(chIndex): \(cleaned) (line: \(line))")
            }
        } else if reduction.channelNameMissingBraces, Self.isVerboseLogging {
            print("[ShureWirelessService] \(deviceLogTag) CHAN_NAME braces not found (line: \(line))")
        }

        if let rfValue = reduction.rfTxLevel {
            rfTxLastUpdated[chIndex] = now
            if Self.isVerboseLogging {
                print("[ShureWirelessService] \(deviceLogTag) RF_TX_LVL parsed for channel \(chIndex): \(rfValue) (line: \(line))")
            }
        } else if Self.isVerboseLogging, frame.parts.contains(where: { $0.uppercased() == "RF_TX_LVL" }) {
            print("[ShureWirelessService] \(deviceLogTag) RF_TX_LVL missing value (line: \(line))")
        }

        if let formatted = reduction.frequencyDisplay {
            if Self.isVerboseLogging {
                print("[ShureWirelessService] \(deviceLogTag) FREQUENCY parsed for channel \(chIndex): \(formatted) (line: \(line))")
            }
        } else if Self.isVerboseLogging, frame.parts.contains(where: { $0.uppercased() == "FREQUENCY" }) {
            print("[ShureWirelessService] \(deviceLogTag) FREQUENCY missing value (line: \(line))")
        }

        if hasAxientPositivePresenceEvidence(frame: frame) {
            markAxientPositivePresenceEvidence(channelIndex: chIndex, now: now)
        }

        if let key = reduction.batteryKey {
            recordBatteryTrace("line ch=\(chIndex) key=\(key) raw=\(line)")
            switch reduction.batteryUpdate {
            case .clear(let reason):
                channelBatteryPriority.removeValue(forKey: chIndex)
                channelBatteryCalculationPendingAt.removeValue(forKey: chIndex)
                channelBatteryLastUpdated.removeValue(forKey: chIndex)
                recordBatteryTrace("clear ch=\(chIndex) key=\(key) reason=\(reason)")
            case .set(let label, let percentage, let isApproximate, let priority):
                let existingSnapshot = currentStandardReportSnapshot(channelIndex: chIndex)
                let existingPriority = existingSnapshot.batteryPriority ?? channelBatteryPriority[chIndex] ?? 0
                if priority >= existingPriority {
                    if Self.isExactBatteryPercentKey(key) || (Self.isRuntimeBatteryKey(key) && priority >= 3) {
                        channelBatteryHasSmartTelemetry[chIndex] = true
                    }
                    let didBatteryChange =
                        existingPriority != priority
                        || existingSnapshot.batteryLabel != label
                        || existingSnapshot.batteryPercentage != percentage
                        || existingSnapshot.batteryIsApproximate != isApproximate

                    if channelBatteryPriority[chIndex] != priority {
                        channelBatteryPriority[chIndex] = priority
                    }
                    if didBatteryChange {
                        channelBatteryLastUpdated[chIndex] = now
                    }
                    markChannelPresence(channelIndex: chIndex, now: now)
                    if Self.isRuntimeBatteryKey(key) && priority >= 3 {
                        channelBatteryCalculationPendingAt.removeValue(forKey: chIndex)
                    } else if channelBatteryHasSmartTelemetry[chIndex] != true {
                        channelBatteryCalculationPendingAt.removeValue(forKey: chIndex)
                    }
                    let percentText = percentage.map(String.init) ?? "nil"
                    recordBatteryTrace("update ch=\(chIndex) key=\(key) label=\(label) percent=\(percentText) approximate=\(isApproximate) priority=\(priority)")
                }
            case .ignoredSentinel(let value):
                if Self.isRuntimeBatteryKey(key) {
                    channelBatteryCalculationPendingAt[chIndex] = now
                }
                recordBatteryTrace("ignore_sentinel ch=\(chIndex) key=\(key) value=\(value)")
            case .unparsed:
                recordBatteryTrace("unparsed ch=\(chIndex) key=\(key) raw=\(line)")
            case .none:
                break
            }
        }

        if let transmitterPresent = reduction.transmitterPresent {
            if channelTransmitterPresent[chIndex] != transmitterPresent {
                channelTransmitterPresent[chIndex] = transmitterPresent
            }
            channelTransmitterPresentLastUpdated[chIndex] = now
            if transmitterPresent {
                channelTransmitterPresentLastTrueAt[chIndex] = now
                channelAxientNegativeEvidenceStreakStartAt.removeValue(forKey: chIndex)
            } else {
                channelTransmitterPresentLastFalseAt[chIndex] = now
                if channelAxientNegativeEvidenceStreakStartAt[chIndex] == nil {
                    channelAxientNegativeEvidenceStreakStartAt[chIndex] = now
                }
            }
        }
        if shouldQueryTxDeviceID(), let transmitterDeviceIDPresent = reduction.transmitterDeviceIDPresent {
            if channelTransmitterDeviceIDPresent[chIndex] != transmitterDeviceIDPresent {
                channelTransmitterDeviceIDPresent[chIndex] = transmitterDeviceIDPresent
            }
            channelTransmitterDeviceIDLastUpdated[chIndex] = now
            if transmitterDeviceIDPresent {
                channelAxientNegativeEvidenceStreakStartAt.removeValue(forKey: chIndex)
            } else if channelAxientNegativeEvidenceStreakStartAt[chIndex] == nil {
                channelAxientNegativeEvidenceStreakStartAt[chIndex] = now
            }
        }
        let smoothedRfBarCount: Int? = reduction.rfBarCount.map { rawBars in
            guard isAxientDeviceModel() else { return rawBars }
            // RSSI_LED_BITMAP arrives as one frame per antenna. Combine
            // them (max across antennas, matching standard diversity-
            // receiver behavior -- report whichever antenna currently has
            // the better signal) before smoothing, rather than feeding
            // each antenna's reading into the shared hold state on its own
            // turn: confirmed on a real field log that when one antenna
            // degrades while the other stays strong, alternating between
            // them let the stronger antenna's reading immediately win and
            // reset the weaker antenna's in-progress drop every cycle --
            // the meter never converged to the drop at all.
            let combinedBars: Int
            if let antennaIndex = reduction.rfAntennaIndex {
                var antennaBars = channelAxientRfBarsByAntenna[chIndex] ?? [:]
                antennaBars[antennaIndex] = rawBars
                channelAxientRfBarsByAntenna[chIndex] = antennaBars
                combinedBars = antennaBars.values.max() ?? rawBars
            } else {
                combinedBars = rawBars
            }
            return smoothedAxientRfBarCount(combinedBars, channelIndex: chIndex, now: now)
        }
        if let rfBarCount = smoothedRfBarCount {
            if reduction.shouldPreserveExistingZeroBitmap,
               rfBarCount == 0,
               let existing = standardReportRfBarCount(for: chIndex),
               existing > 0,
               let lastUpdated = channelRfLastUpdated[chIndex],
               now.timeIntervalSince(lastUpdated) < 2.0 {
                // Preserve recent non-zero signal bars when a bitmap briefly reports zero.
            } else {
                channelRfLastUpdated[chIndex] = now
            }
        }

        var acceptedMicLevel = reduction.micAudioUpdate?.shouldAccept == true ? reduction.micAudioUpdate?.level : nil
        var shouldClearStoredMicLevel = false
        if let micUpdate = reduction.micAudioUpdate {
            if let isOverload = micUpdate.isOverload {
                channelMicAudioOverload[chIndex] = isOverload
            }
            let isAxientMeterKey =
                micUpdate.keyUpper == "AUDIO_LEVEL_RMS"
                || micUpdate.keyUpper == "AUDIO_LEVEL_PEAK"
                || micUpdate.keyUpper == "AUDIO_LED_BITMAP"

            if isAxientDeviceModel(), isAxientMeterKey {
                let bitmapAllowsLevel: Bool
                if micUpdate.keyUpper == "AUDIO_LED_BITMAP" {
                    bitmapAllowsLevel = micUpdate.level > 0
                    axientAudioBitmapAllowsLevel[chIndex] = bitmapAllowsLevel
                } else {
                    bitmapAllowsLevel = axientAudioBitmapAllowsLevel[chIndex] == true
                }

                let disposition = ShureAxientAudioDispositionResolver.resolve(
                    keyUpper: micUpdate.keyUpper,
                    level: micUpdate.level,
                    shouldAccept: micUpdate.shouldAccept,
                    bitmapAllowsLevel: bitmapAllowsLevel
                )
                acceptedMicLevel = disposition.acceptedLevel
                shouldClearStoredMicLevel = disposition.shouldClearStoredLevel

                if let acceptedMicLevel {
                    updateMicLevel(
                        acceptedMicLevel,
                        keyUpper: micUpdate.keyUpper,
                        channelIndex: chIndex,
                        now: now,
                        persistPublishedLevel: false,
                        bypassHold: shouldClearStoredMicLevel
                    )
                }
            } else if micUpdate.shouldAccept {
                updateMicLevel(
                    micUpdate.level,
                    keyUpper: micUpdate.keyUpper,
                    channelIndex: chIndex,
                    now: now,
                    persistPublishedLevel: false
                )
            }
        }

        let standardReportUpdate = ShureStandardReportStateUpdate(
            channelIndex: chIndex,
            channelName: reduction.channelName,
            rfTxLevel: reduction.rfTxLevel,
            frequencyDisplay: reduction.frequencyDisplay,
            batteryUpdate: reduction.batteryUpdate,
            audioMute: reduction.audioMute,
            meterRate: reduction.meterRate,
            rfBarCount: smoothedRfBarCount,
            rfOverload: reduction.rfOverload,
            shouldPreserveExistingZeroBitmap: reduction.shouldPreserveExistingZeroBitmap,
            micAudioLevel: acceptedMicLevel,
            micAudioAccepted: acceptedMicLevel != nil,
            shouldClearMicAudioLevel: shouldClearStoredMicLevel,
            micAudioOverload: channelMicAudioOverload[chIndex],
            now: now
        )
        let composition = snapshotCompositionPolicy(channelIndex: chIndex, now: now)
        Task { [weak self] in
            guard let self else { return }
            let mirrored = await self.standardReportStateStore.applyTcp(
                standardReportUpdate,
                composition: composition
            )
            await MainActor.run {
                guard let mirrored else { return }
                self.applyShadowStandardReportLowFrequencySnapshot(
                    channelIndex: chIndex,
                    mirrored: mirrored,
                    line: line
                )
                self.verifyMirroredStandardReportState(
                    channelIndex: chIndex,
                    mirrored: mirrored,
                    line: line
                )
            }
        }
    }

    @MainActor
    private func processPsmAudioFrame(_ frame: ShureIncomingFrame) {
        let parts = frame.parts
        guard parts.count >= 4,
              frame.verbUpper == "REPORT",
              let chIndex = Int(parts[1]) else {
            return
        }

        let keyUpper = parts[2].uppercased()
        guard (keyUpper == "AUDIO_IN_LVL_L" || keyUpper == "AUDIO_IN_LVL_R"),
              let level = Double(parts[3]) else {
            return
        }

        updatePSMAudioLevel(level, keyUpper: keyUpper, channelIndex: chIndex)
    }

    @MainActor
    private func processSampleFrame(_ frame: ShureIncomingFrame, now: Date, isPsmTransmitter: Bool) {
        let parts = frame.parts
        guard parts.count >= 6,
              frame.verbUpper == "SAMPLE",
              parts[2].uppercased() == "ALL",
              let chIndex = Int(parts[1]) else {
            return
        }

        guard !isPsmTransmitter else { return }

        if isAxientDeviceModel() {
            processAxientSampleFrame(frame, chIndex: chIndex, now: now)
            return
        }

        guard let parsedTelemetry = ShureSampleFrameTelemetryParser.parseCompactSamplePayload(from: frame.rawLine) else {
            return
        }

        let dbm = parsedTelemetry.rfLevel - 128.0
        let rfBarCount = rfBars(fromDbm: dbm)
        channelRfLastUpdated[chIndex] = now

        let audioLevel = parsedTelemetry.audioLevel
        var acceptedMicLevel: Double? = nil
        if let level = audioLevel,
           shouldAcceptMicLevel(level, channelIndex: chIndex, now: now) {
            if level > 0 {
                micAudioLastNonZeroAt[chIndex] = now
            }
            acceptedMicLevel = level
            micAudioLastUpdated[chIndex] = now
            if Self.isVerboseMicLogging {
                print("[ShureWirelessService] \(deviceLogTag) SAMPLE audio level ch \(chIndex): \(level)")
            }
        }

        let update = ShureStandardReportStateUpdate(
            channelIndex: chIndex,
            channelName: nil,
            rfTxLevel: nil,
            frequencyDisplay: nil,
            batteryUpdate: nil,
            audioMute: nil,
            meterRate: nil,
            rfBarCount: rfBarCount,
            rfOverload: nil,
            shouldPreserveExistingZeroBitmap: false,
            micAudioLevel: acceptedMicLevel,
            micAudioAccepted: acceptedMicLevel != nil,
            shouldClearMicAudioLevel: false,
            // ULX-D/QLX-D's compact SAMPLE payload (antenna, rfLevel,
            // audioLevel -- 3 fields, confirmed against real hardware) has
            // no AUDIO_LED_BITMAP-equivalent clip bit at all, unlike
            // Axient's 9-field SAMPLE payload. No real overload signal
            // exists for this family via SAMPLE, so this stays nil rather
            // than approximating one.
            micAudioOverload: nil,
            now: now
        )
        let composition = snapshotCompositionPolicy(channelIndex: chIndex, now: now)
        Task { [weak self] in
            guard let self else { return }
            let mirrored = await self.standardReportStateStore.applyTcp(
                update,
                composition: composition
            )
            await MainActor.run {
                guard let mirrored else { return }
                self.applyShadowStandardReportLowFrequencySnapshot(
                    channelIndex: chIndex,
                    mirrored: mirrored,
                    line: frame.rawLine
                )
                self.verifyMirroredStandardReportState(
                    channelIndex: chIndex,
                    mirrored: mirrored,
                    line: frame.rawLine
                )
            }
        }
    }

    /// Trusts Axient's own unprompted SAMPLE stream for RF/audio, the same
    /// way the Bitfocus Companion module's parseADSample does, instead of
    /// discarding it and relying solely on GET/REP polling. Reuses the exact
    /// RSSI_LED_BITMAP decode + antenna-combine + hold smoothing, and the
    /// exact AUDIO_LED_BITMAP/AUDIO_LEVEL_RMS disposition logic, that the
    /// REP path already uses -- so a SAMPLE-derived reading and a
    /// REP-derived reading for the same value agree.
    @MainActor
    private func processAxientSampleFrame(_ frame: ShureIncomingFrame, chIndex: Int, now: Date) {
        guard let parsedTelemetry = ShureAxientSampleFrameTelemetryParser.parse(from: frame.rawLine) else {
            return
        }

        var rfBarCount: Int? = nil
        var rfOverload: Bool? = nil
        if parsedTelemetry.rfLedBitmapA != nil || parsedTelemetry.rfLedBitmapB != nil {
            var barsByAntenna = channelAxientRfBarsByAntenna[chIndex] ?? [:]
            var overload = false
            if let bitmapA = parsedTelemetry.rfLedBitmapA {
                let decoded = ShureRssiLedBitmapDecoder.decode(bitmapA)
                barsByAntenna[0] = decoded.bars
                overload = overload || decoded.isOverload
            }
            if let bitmapB = parsedTelemetry.rfLedBitmapB {
                let decoded = ShureRssiLedBitmapDecoder.decode(bitmapB)
                barsByAntenna[1] = decoded.bars
                overload = overload || decoded.isOverload
            }
            channelAxientRfBarsByAntenna[chIndex] = barsByAntenna
            let combinedBars = barsByAntenna.values.max() ?? 0
            rfBarCount = smoothedAxientRfBarCount(combinedBars, channelIndex: chIndex, now: now)
            rfOverload = overload
            channelRfLastUpdated[chIndex] = now
        }

        let bitmapMask = parsedTelemetry.audioBitmap & 0xFF
        var bitmapBitCount = 0
        for bit in 0..<8 where (bitmapMask & (1 << bit)) != 0 {
            bitmapBitCount += 1
        }
        let bitmapLevel = Double(bitmapBitCount) / 8.0 * 20.0
        let bitmapAllowsLevel = bitmapLevel > 0
        axientAudioBitmapAllowsLevel[chIndex] = bitmapAllowsLevel
        // Bit 7 ("LED 8 - Red" per Shure's own Axient Digital reference) is
        // the receiver's own genuine clip/overage indicator, captured
        // straight off this same bitmap rather than re-derived from our own
        // level scaling -- see MicAudioUpdate.isOverload for why that
        // distinction matters.
        channelMicAudioOverload[chIndex] = (bitmapMask & 0x80) != 0

        var acceptedMicLevel: Double? = nil
        var shouldClearStoredMicLevel = false
        if let rawMeterLevel = parsedTelemetry.audioRmsLevel ?? parsedTelemetry.audioPeakLevel {
            let clamped = min(max(rawMeterLevel, 0.0), 120.0)
            let level = (clamped / 120.0) * 20.0
            let shouldAccept = shouldAcceptMicLevel(level, channelIndex: chIndex, now: now)
            let disposition = ShureAxientAudioDispositionResolver.resolve(
                keyUpper: "AUDIO_LEVEL_RMS",
                level: level,
                shouldAccept: shouldAccept,
                bitmapAllowsLevel: bitmapAllowsLevel
            )
            shouldClearStoredMicLevel = disposition.shouldClearStoredLevel
            acceptedMicLevel = disposition.acceptedLevel
            if let accepted = disposition.acceptedLevel {
                if accepted > 0 {
                    micAudioLastNonZeroAt[chIndex] = now
                }
                micAudioLastUpdated[chIndex] = now
                updateMicLevel(
                    accepted,
                    keyUpper: "AUDIO_LEVEL_RMS",
                    channelIndex: chIndex,
                    now: now,
                    persistPublishedLevel: false,
                    bypassHold: shouldClearStoredMicLevel
                )
            }
        }

        guard rfBarCount != nil || acceptedMicLevel != nil || shouldClearStoredMicLevel else { return }

        let update = ShureStandardReportStateUpdate(
            channelIndex: chIndex,
            channelName: nil,
            rfTxLevel: nil,
            frequencyDisplay: nil,
            batteryUpdate: nil,
            audioMute: nil,
            meterRate: nil,
            rfBarCount: rfBarCount,
            rfOverload: rfOverload,
            shouldPreserveExistingZeroBitmap: false,
            micAudioLevel: acceptedMicLevel,
            micAudioAccepted: acceptedMicLevel != nil,
            shouldClearMicAudioLevel: shouldClearStoredMicLevel,
            micAudioOverload: channelMicAudioOverload[chIndex],
            now: now
        )
        let composition = snapshotCompositionPolicy(channelIndex: chIndex, now: now)
        Task { [weak self] in
            guard let self else { return }
            let mirrored = await self.standardReportStateStore.applyTcp(
                update,
                composition: composition
            )
            await MainActor.run {
                guard let mirrored else { return }
                self.applyShadowStandardReportLowFrequencySnapshot(
                    channelIndex: chIndex,
                    mirrored: mirrored,
                    line: frame.rawLine
                )
                self.verifyMirroredStandardReportState(
                    channelIndex: chIndex,
                    mirrored: mirrored,
                    line: frame.rawLine
                )
            }
        }
    }

    @MainActor private func handleIncoming(text: String) async {
        guard liveModeEnabled else { return }
        let now = Date()
        self.lastHeardAt = now

        let modelCode = device?.shureModelIdentifier?.uppercased()
        let isPsmTransmitter = (modelCode == "P10T")
        let isAxientDevice: Bool = {
            guard let modelCode else { return false }
            if modelCode.contains("AD4") || modelCode.contains("ANX4") { return true }
            if modelCode.contains("AXIENT") { return true }
            return false
        }()

        let hasBatteryValueByChannel = Dictionary(
            uniqueKeysWithValues: Set(channelBatteryLabels.keys).union(channelBatteryPercentages.keys).map { channelIndex in
                (channelIndex, hasBatteryValue(for: channelIndex))
            }
        )
        let parseStart = CFAbsoluteTimeGetCurrent()
        let preparedData = await Self.prepareIncomingData(
            text: text,
            isAxientDevice: isAxientDevice,
            contextSnapshot: ShureReportContextSnapshot(
                hasBatteryValueByChannel: hasBatteryValueByChannel,
                meterRates: channelMeterRates,
                lastNonZeroMicAudioAt: micAudioLastNonZeroAt
            ),
            now: now
        )
        parseDurationTotal += CFAbsoluteTimeGetCurrent() - parseStart
        parseDurationSamples += 1
        guard liveModeEnabled else { return }
        let reportWorkItemsByIndex = Dictionary(
            uniqueKeysWithValues: preparedData.reportWorkItems.map { ($0.frameIndex, $0) }
        )

        for (frameIndex, frame) in preparedData.frames.enumerated() {
            let line = frame.rawLine
            if shouldTraceAD4QRF(), Self.shouldTraceAD4QFrame(frame) {
                recordAD4QRFTrace("recv line=\(line)")
            }
            if shouldTraceULXDTxDeviceID(), Self.shouldTraceULXDTxDeviceIDFrame(frame) {
                recordULXDTxDeviceIDTrace("recv line=\(line)")
            }
            // Store in recent reports (non-published).
            self.recentReports.append(line)
            let maxRecent = 200
            if self.recentReports.count > maxRecent {
                self.recentReports.removeFirst(
                    self.recentReports.count - maxRecent
                )
            }

            // Also inspect for channel-name, RF TX level, and FREQUENCY reports:
            // Common patterns (after stripping < and >):
            // REP    <ch> CHAN_NAME {Name        }
            // REPORT <ch> CHAN_NAME {Name        }
            // REPORT <ch> RF_TX_LVL <value>
            // REPORT <ch> FREQUENCY <value>
            //
            // Some devices (including PSM1000) may insert extra tokens, so we:
            //  - Require "REP" or "REPORT" as the first token
            //  - Look for "CHAN_NAME", "RF_TX_LVL", or "FREQUENCY" anywhere in the line
            //  - Use the first integer token after the verb as the channel index
            if let prepared = reportWorkItemsByIndex[frameIndex] {
                processReportedFrame(frame, prepared: prepared, now: now)
            }

            // 3) For PSM transmitters (e.g. P10T), capture AUDIO_IN_LVL_L/R so we can
            // show audio level meters instead of RF strength bars.
            if liveModeEnabled, isPsmTransmitter {
                processPsmAudioFrame(frame)
            }

            // SAMPLE <ch> ALL frames can also carry RF level information for
            // ULX-D/QLX-D style devices. Use the RSSI code as RX_RF_LVL and
            // map it into our 0–5 bar representation. For *mic* receivers,
            // we also treat the following numeric field as an audio level so
            // we can drive the per-channel audio meter without affecting PSMs.
            if liveModeEnabled {
                processSampleFrame(frame, now: now, isPsmTransmitter: isPsmTransmitter)
            }
        }

        // Optional: debug
        if Self.isVerboseLogging, liveModeEnabled {
            if (isPsmTransmitter && Self.isVerbosePsmLogging) || (!isPsmTransmitter && Self.isVerboseMicLogging) {
                print("[ShureWirelessService] \(deviceLogTag) channelNames = \(self.channelNames)")
            }
        }
    }
}

// MARK: - Module View

struct ShureWirelessModuleView: View {
    private struct ChannelPowerResolution {
        let isOn: Bool
        let sourceLabel: String
    }

    @StateObject private var service: ShureWirelessService
    @State private var micLevelStats: [Int: (min: Double, max: Double)] = [:]
    @State private var micSmoothedLevels: [Int: Double] = [:]
    @State private var visibilityConsumerID = UUID()
    @Binding var selectedChannel: ExternalDevicesStore.ShureSelectedChannel?
    @ObservedObject private var externalStore = ExternalDevicesStore.shared
    private var showDeviceName: Bool
    private var showChannelName: Bool
    private var showIPPort: Bool
    private var showFrequency: Bool
    private var showBattery: Bool
    private var showRFStrength: Bool
    private var showAudioMeter: Bool
    /// Whether this module should render its own header ("Shure Wireless").
    /// Defaults to `true` so existing tiles behave the same, but can be
    /// driven by the tile's `showsTitle` flag from DashboardRootView.
    var showsHeader: Bool
    var isLiveMode: Bool
    @AppStorage("dashboard_live_mode_enabled") private var liveModeEnabled: Bool = false
    private var demoEnabled: Bool
    private var demoIsIem: Bool
    private var demoMicName: String
    private var demoDeviceName: String
    private var demoBatteryPercent: Int
    private var demoFrequencyMHz: Double

    private var effectiveLiveMode: Bool {
        isLiveMode || liveModeEnabled
    }

    init(
        selectedChannel: Binding<ExternalDevicesStore.ShureSelectedChannel?>,
        showsHeader: Bool = true,
        isLiveMode: Bool = false,
        showDeviceName: Bool = true,
        showChannelName: Bool = true,
        showIPPort: Bool = true,
        showFrequency: Bool = true,
        showBattery: Bool = true,
        showRFStrength: Bool = true,
        showAudioMeter: Bool = true,
        demoEnabled: Bool = false,
        demoIsIem: Bool = false,
        demoMicName: String = "Pastor Mic",
        demoDeviceName: String = "Demo Rack",
        demoBatteryPercent: Int = 82,
        demoFrequencyMHz: Double = 552.125
    ) {
        self._selectedChannel = selectedChannel
        let initialDeviceID = selectedChannel.wrappedValue?.deviceID
        self._service = StateObject(wrappedValue: ShureWirelessService.shared(for: initialDeviceID))
        self.showsHeader = showsHeader
        self.isLiveMode = isLiveMode
        self.showDeviceName = showDeviceName
        self.showChannelName = showChannelName
        self.showIPPort = showIPPort
        self.showFrequency = showFrequency
        self.showBattery = showBattery
        self.showRFStrength = showRFStrength
        self.showAudioMeter = showAudioMeter
        self.demoEnabled = demoEnabled
        self.demoIsIem = demoIsIem
        self.demoMicName = demoMicName
        self.demoDeviceName = demoDeviceName
        self.demoBatteryPercent = demoBatteryPercent
        self.demoFrequencyMHz = demoFrequencyMHz
    }

    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    @Environment(\.tileCornerRadius) private var tileCornerRadius
    @Environment(\.dashboardIsTextInputActive) private var isTextInputActive

    private let meterTick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
#if DEBUG
    private let demoTick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    @State private var demoPhase: Double = 0
#endif

    /// Extra bottom padding that scales with the tile's corner radius so
    /// content (especially RF bars) doesn't get clipped by the rounded corners.
    private var bottomPadding: CGFloat {
        // We want ~26pts of padding when the corner radius is 40pts.
        // That corresponds to a scale of 0.65 * radius.
        // Clamp to a minimum so it still looks good when radius is small.
        let scaled = tileCornerRadius * 0.65
        let minimum: CGFloat = 8
        return max(minimum, scaled)
    }

    // MARK: - Text Formatting Helpers

    /// Whether the currently bound Shure device is a PSM 900 (offline placeholder).
    private var isPSM900Device: Bool {
        guard let device = service.device else { return false }
        if let model = device.shureModelIdentifier?.uppercased(), model.contains("PSM900") {
            return true
        }
        let upperName = device.name.uppercased()
        if upperName.contains("PSM 900") || upperName.contains("PSM900") {
            return true
        }
        return false
    }

    /// Base font size for this tile; other sizes are scaled from here.
    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    /// Primary font weight for important labels in this tile.
    private var primaryFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    /// Primary text color derived from tile formatting, defaulting to white.
    private var resolvedPrimaryColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }

    /// Secondary, de-emphasized text color.
    private var resolvedSecondaryColor: Color {
        resolvedPrimaryColor.opacity(0.7)
    }

    /// Resolved text alignment based on the tile's justification setting.
    private var resolvedTextAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Resolved horizontal alignment for frames based on justification.
    private var resolvedHorizontalAlignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Font for the section header ("Shure Wireless").
    private var headerFont: Font {
        .system(size: baseFontSize * 0.85, weight: primaryFontWeight)
    }

    /// Font for labels and content rows (device name, status labels).
    private var contentFont: Font {
        .system(size: baseFontSize * 0.7, weight: .regular)
    }

    /// Font for smaller caption-style text (hints, host:port, notes).
    private var captionFont: Font {
        .system(size: baseFontSize * 0.6, weight: .regular)
    }

    private func applyCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    private var isDemoModeActive: Bool {
#if DEBUG
        return demoEnabled
#else
        return false
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                header
                Divider()
            }

            content
        }
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .padding(.bottom, bottomPadding)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .onAppear {
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            service.setLiveModeEnabled(effectiveLiveMode)
            if let selection = selectedChannel {
                service.setDevice(id: selection.deviceID)
            }
            updateSharedConsumerVisibility()
        }
        .onChange(of: selectedChannel?.deviceID, initial: false) { _, newDeviceID in
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            // Ensure the service knows whether it should sample *before* connecting to a new device.
            service.setLiveModeEnabled(effectiveLiveMode)
            service.setDevice(id: newDeviceID)
            updateSharedConsumerVisibility()
        }
        .onChange(of: isLiveMode, initial: false) { _, newValue in
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            service.setLiveModeEnabled(newValue || liveModeEnabled)
            updateSharedConsumerVisibility()
        }
        .onChange(of: liveModeEnabled, initial: false) { _, newValue in
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            service.setLiveModeEnabled(newValue || isLiveMode)
            updateSharedConsumerVisibility()
        }
        .onChange(of: selectedChannel?.channelIndex, initial: false) { _, _ in
            guard !isLANSnapshotRendering, !isDemoModeActive else { return }
            updateSharedConsumerVisibility()
        }
        .onDisappear {
            service.removeConsumer(visibilityConsumerID)
        }
        .onReceive(meterTick) { _ in
            guard !isDemoModeActive else { return }
            guard !isTextInputActive else { return }
            // Network sampling is the most expensive path; only run it in Live Mode.
            guard effectiveLiveMode else { return }

            if let descriptor = selectedChannelDescriptor {
                // This view no longer polls independently -- the shared
                // per-device loop (see refreshSharedPollingTask) is now the
                // sole poller for every channel, including this one,
                // whenever a tile has it selected via setChannelConsumer.
                // This tick is purely local smoothing/ballistics against
                // whatever that loop most recently fetched. Two
                // independently-paced pollers hitting the same connection
                // (this view's old loop, and the shared one) is what
                // actually caused REP ERR, dropped updates, and flapping
                // presence status on a real AD4Q, even after several
                // rounds of trying to make the two coexist more carefully.

                // Update stats OUTSIDE render pass
                let channelIndex = descriptor.channelIndex
                if !isChannelPoweredOn(for: descriptor) {
                    updateMicSmoothedLevel(channelIndex: channelIndex, level: 0.0, isRecent: false)
                    return
                }

                let holdSeconds = service.micHoldWindowSeconds(for: channelIndex)
                let recentUpdate = isRecent(service.micAudioLastUpdated[channelIndex], within: 8.0)
                let lastNonZero = service.lastNonZeroMicAudioAt(for: channelIndex)
                let isWithinHold = isRecent(lastNonZero, within: holdSeconds)

                let micLevel = service.standardReportMicAudioLevel(for: channelIndex)
                if let level = micLevel, (recentUpdate || isWithinHold) {
                    updateMicLevelStats(channelIndex: channelIndex, level: level)
                    updateMicSmoothedLevel(channelIndex: channelIndex, level: level, isRecent: true)
                } else {
                    updateMicSmoothedLevel(channelIndex: channelIndex, level: 0.0, isRecent: false)
                }
            }
        }
#if DEBUG
        .onReceive(demoTick) { _ in
            guard isDemoModeActive else { return }
            demoPhase += 0.18
        }
#endif
        .onChange(of: externalStore.devices.map(\.id), initial: false) { _, _ in
            // External devices were imported/edited. Re-resolve the bound device.
            if let selection = selectedChannel {
                service.setDevice(id: selection.deviceID)
            } else {
                service.refreshDevice()
            }
        }
    }

    private func updateSharedConsumerVisibility() {
        guard effectiveLiveMode,
              let descriptor = selectedChannelDescriptor else {
            service.removeConsumer(visibilityConsumerID)
            return
        }
        service.setChannelConsumer(visibilityConsumerID, channelIndex: descriptor.channelIndex)
    }

    private var header: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(resolvedPrimaryColor)

            Text(applyCapitalization("Shure Wireless"))
                .font(headerFont)
                .foregroundStyle(resolvedPrimaryColor)

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if isDemoModeActive {
            demoContent
        } else {
            contentBody
        }
        #else
        contentBody
        #endif
    }

    @ViewBuilder
    private var contentBody: some View {
        if service.device == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(applyCapitalization("No Shure device configured."))
                    .font(contentFont)
                    .foregroundStyle(resolvedPrimaryColor)
                Text(applyCapitalization("Add a Shure Wireless device in Settings → External Devices (kind = Shure Wireless)."))
                    .font(captionFont)
                    .foregroundStyle(resolvedSecondaryColor)
            }
        } else {
            channelSelectorSection
            if !isPSM900Device {
                Divider()
                channelReportsSection
            }
        }
    }

#if DEBUG
    private var demoContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            demoChannelSelectorSection
            Divider()
            demoChannelReportsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var demoChannelSelectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(applyCapitalization(demoChannelTitle))
                    .font(.system(size: baseFontSize * 1.15, weight: primaryFontWeight))
                    .foregroundStyle(resolvedPrimaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Text(applyCapitalization(demoIsIem ? "IEM" : "Mic"))
                    .font(captionFont)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((demoIsIem ? Color.accentColor : shureGreen).opacity(0.9))
                    )
                    .foregroundStyle(demoIsIem ? .white : .black)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(0.35))
            )

            if showDeviceName || showIPPort {
                VStack(alignment: .leading, spacing: 4) {
                    if showDeviceName {
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(captionFont)
                                .foregroundStyle(resolvedSecondaryColor)
                            Text(applyCapitalization(demoDeviceName))
                                .font(captionFont)
                                .foregroundStyle(resolvedSecondaryColor)
                                .lineLimit(1)
                        }
                    }

                    if showIPPort {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(captionFont)
                                .foregroundStyle(resolvedSecondaryColor)
                            Text(applyCapitalization("192.168.1.120:2202"))
                                .font(captionFont.monospacedDigit())
                                .foregroundStyle(resolvedSecondaryColor)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(resolvedSecondaryColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var demoChannelReportsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showFrequency || showBattery || showRFStrength || showAudioMeter {
                Text(applyCapitalization("Channel Status"))
                    .font(contentFont.weight(.semibold))
                    .foregroundStyle(resolvedPrimaryColor)
            }

            if showFrequency {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(captionFont)
                            .foregroundStyle(resolvedSecondaryColor)
                        Text(applyCapitalization("Frequency"))
                            .font(captionFont)
                            .foregroundStyle(resolvedSecondaryColor)
                    }
                    Spacer()
                    Text(demoFrequencyLabel)
                        .font(captionFont)
                        .foregroundStyle(resolvedPrimaryColor)
                }
            }

            if showBattery {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "battery.100")
                            .font(captionFont)
                            .foregroundStyle(resolvedSecondaryColor)
                        Text(applyCapitalization("Battery"))
                            .font(captionFont)
                            .foregroundStyle(resolvedSecondaryColor)
                    }
                    Spacer()
                    Text("\(max(0, min(100, demoBatteryPercent)))%")
                        .font(captionFont)
                        .foregroundStyle(resolvedPrimaryColor)
                }
            }

            if showRFStrength || showAudioMeter {
                VStack(alignment: .leading, spacing: 4) {
                    if showRFStrength {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(captionFont)
                                    .foregroundStyle(resolvedSecondaryColor)
                                Text(applyCapitalization("RF"))
                                    .font(captionFont)
                                    .foregroundStyle(resolvedSecondaryColor)
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(0..<6, id: \.self) { idx in
                                    let isOLSegment = (idx == 5)
                                    let fillColor: Color = {
                                        guard idx < demoRfBars else { return Color.secondary.opacity(0.2) }
                                        return isOLSegment ? Color.red.opacity(0.8) : Color.accentColor
                                    }()
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(fillColor)
                                        .frame(width: 10, height: 6)
                                }
                            }
                        }
                    }

                    if showAudioMeter {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(captionFont)
                                    .foregroundStyle(resolvedSecondaryColor)
                                Text(applyCapitalization("Audio"))
                                    .font(captionFont)
                                    .foregroundStyle(resolvedSecondaryColor)
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(0..<ShureOverviewAudioBucket.segmentCount, id: \.self) { idx in
                                    let isLit = idx < demoAudioBars
                                    let isOverageSegment = idx == ShureOverviewAudioBucket.segmentCount - 1
                                    let fillColor: Color = {
                                        guard isLit else { return Color.secondary.opacity(0.2) }
                                        return isOverageSegment ? Color.red.opacity(0.8) : Color.accentColor
                                    }()
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(fillColor)
                                        .frame(width: 10, height: 6)
                                }
                            }
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(resolvedSecondaryColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var demoChannelTitle: String {
        if showChannelName {
            let trimmed = demoMicName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Demo Mic" : trimmed
        }
        return "CH 1"
    }

    private var demoRfBars: Int {
        let value = (sin(demoPhase * 0.6) + 1.0) * 0.5
        return max(0, min(5, Int(round(value * 5.0))))
    }

    private var demoAudioBars: Int {
        let value = (sin(demoPhase * 1.1 + 0.8) + 1.0) * 0.5
        let levelSegments = ShureOverviewAudioBucket.levelSegmentCount
        return max(0, min(ShureOverviewAudioBucket.segmentCount, Int(round(value * Double(levelSegments)))))
    }

    private var demoFrequencyLabel: String {
        let clamped = max(400.000, min(700.000, demoFrequencyMHz))
        return String(format: "%.3f MHz", clamped)
    }
#endif

    private var channelSelectorSection: some View {
        Group {
            if let descriptor = selectedChannelDescriptor,
               let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == descriptor.deviceID }) {
                VStack(alignment: .leading, spacing: 6) {
                    if showChannelName {
                        HStack(spacing: 8) {
                            Text(applyCapitalization(label(for: descriptor)))
                                .font(.system(size: baseFontSize * 1.15, weight: primaryFontWeight))
                                .foregroundStyle(resolvedPrimaryColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .layoutPriority(1)

                            Spacer(minLength: 4)

                            // Mic / IEM badge based on device type
                            let isIEM = isPSMDevice(device)
                            Text(applyCapitalization(isIEM ? "IEM" : "Mic"))
                                .font(captionFont)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(shureGreen.opacity(0.9))
                                )
                                .foregroundStyle(.black)
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        // Make the pill background stretch to full section width
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(channelStatusColor(for: descriptor))
                        )
                    }

                    if showDeviceName || showIPPort || (device.notes?.isEmpty == false) {
                        VStack(alignment: .leading, spacing: 4) {
                            if showDeviceName {
                                HStack(spacing: 6) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                    Text(applyCapitalization(preferredShureDisplayName(for: device)))
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                        .lineLimit(1)
                                }
                            }

                            if showIPPort {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                    Text(applyCapitalization("\(device.host):\(String(device.port))"))
                                        .font(captionFont.monospacedDigit())
                                        .foregroundStyle(resolvedSecondaryColor)
                                        .lineLimit(1)
                                }
                            }

                            if let notes = device.notes, !notes.isEmpty {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "note.text")
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                    Text(applyCapitalization(notes))
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(resolvedSecondaryColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                }
                // Critical: ensure the *whole section* takes the full available width
                .frame(maxWidth: .infinity, alignment: .leading)

            } else {
                Text(applyCapitalization("No Shure channel selected"))
                    .font(captionFont)
                    .foregroundStyle(resolvedSecondaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var channelReportsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Decide whether there is any content to show based on the
            // current toggle configuration. If all of the Channel Status
            // rows are disabled, hide the header entirely.
            let modelCode = service.device?.shureModelIdentifier?.uppercased()
            let isPsmTransmitter = (modelCode == "P10T")

            let shouldShowHeader = isPsmTransmitter
                ? (showFrequency || showRFStrength)
                : (showFrequency || showBattery || showRFStrength || showAudioMeter)

            if shouldShowHeader {
                Text(applyCapitalization("Channel Status"))
                    .font(contentFont.weight(.semibold))
                    .foregroundStyle(resolvedPrimaryColor)
            }

            // Insert Live Mode off notice
            if !effectiveLiveMode {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle")
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                    Text(applyCapitalization("Live data paused — enter Live Mode to update."))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(resolvedSecondaryColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let descriptor = selectedChannelDescriptor {
                // Instead of aggressively filtering recent reports by channel index (which
                // can miss data on some devices), just check whether we have heard
                // *anything* from the Shure device yet for the "no data" message.
                let hasAnyReports = !service.recentReports.isEmpty

                let modelCode = service.device?.shureModelIdentifier?.uppercased()
                let isPsmTransmitter = (modelCode == "P10T")

                if !hasAnyReports {
                    Text(applyCapitalization("No recent data for \(descriptor.displayName)."))
                        .font(captionFont)
                        .foregroundStyle(resolvedSecondaryColor)
                } else {
                    let channelSnapshot = service.telemetrySnapshot.channelSnapshot(for: descriptor.channelIndex)
                    // Use cached values when available, falling back to parsing the
                    // full recentReports list if needed for frequency.
                    let frequencyMHz: String? = {
                        guard effectiveLiveMode else { return nil }
                        if let frequency = channelSnapshot?.frequencyLabel ?? service.standardReportFrequencyDisplay(for: descriptor.channelIndex) {
                            return frequency
                        }
                        return parseFrequency(from: service.recentReports.reversed())
                    }()
                    let batteryLabel: String? = {
                        guard effectiveLiveMode else { return nil }
                        guard isPsmTransmitter || isChannelPoweredOn(for: descriptor) else { return nil }
                        if service.shouldShowBatteryCalculationPlaceholder(for: descriptor.channelIndex) {
                            return "Calc"
                        }
                        return channelSnapshot?.batteryLabel ?? service.standardReportBatteryLabel(for: descriptor.channelIndex)
                    }()
                    let rfTxLevel: Int? = {
                        guard effectiveLiveMode else { return nil }
                        return channelSnapshot?.rfTxLevel ?? service.standardReportRfTxLevel(for: descriptor.channelIndex)
                    }()
                    let rfBars: Int? = {
                        guard effectiveLiveMode else { return nil }
                        guard isPsmTransmitter || isChannelPoweredOn(for: descriptor) else { return 0 }
                        if let bars = channelSnapshot?.rfBars ?? service.standardReportRfBarCount(for: descriptor.channelIndex) {
                            return bars
                        }
                        if let rfTxLevel {
                            return rfBarFallbackCount(from: rfTxLevel)
                        }
                        return nil
                    }()
                    let rfOverload: Bool = {
                        guard effectiveLiveMode else { return false }
                        return channelSnapshot?.rfOverload ?? service.standardReportRfOverload(for: descriptor.channelIndex) ?? false
                    }()
                    let micAudioOverload: Bool = {
                        guard effectiveLiveMode else { return false }
                        return channelSnapshot?.audioOverload ?? service.standardReportMicAudioOverload(for: descriptor.channelIndex) ?? false
                    }()
                    let psmAudio = effectiveLiveMode
                        ? (
                            channelSnapshot.flatMap { snapshot in
                                guard let left = snapshot.audioLeftLevel, let right = snapshot.audioRightLevel else { return nil }
                                return (left: left, right: right)
                            } ?? service.psmAudioLevels[descriptor.channelIndex]
                        )
                        : nil
                    let micAudioLevel: Double? = {
                        guard effectiveLiveMode else { return nil }
                        guard isPsmTransmitter || isChannelPoweredOn(for: descriptor) else { return nil }
                        let channelIndex = descriptor.channelIndex
                        if let smoothed = micSmoothedLevels[channelIndex], smoothed > 0 {
                            return smoothed
                        }

                        let holdSeconds = service.micHoldWindowSeconds(for: channelIndex)
                        let isRecentUpdate = isRecent(service.micAudioLastUpdated[channelIndex], within: 8.0)
                        let lastNonZero = service.lastNonZeroMicAudioAt(for: channelIndex)
                        let isWithinHold = isRecent(lastNonZero, within: holdSeconds)

                        guard isRecentUpdate || isWithinHold else {
                            return nil
                        }
                        return channelSnapshot?.audioLevel ?? service.standardReportMicAudioLevel(for: channelIndex)
                    }()

                    VStack(alignment: .leading, spacing: 6) {
                        if showFrequency {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "waveform.path.ecg")
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                    Text(applyCapitalization("Frequency"))
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                }
                                Spacer()
                                Text(frequencyMHz ?? "—")
                                    .font(captionFont)
                                    .foregroundStyle(resolvedPrimaryColor)
                            }
                        }

                        if showBattery && !isPsmTransmitter {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "battery.100")
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                    Text(applyCapitalization("Battery"))
                                        .font(captionFont)
                                        .foregroundStyle(resolvedSecondaryColor)
                                }
                                Spacer()
                                Text(batteryLabel ?? "—")
                                    .font(captionFont)
                                    .foregroundStyle(resolvedPrimaryColor)
                            }
                        }

                        // RF + audio section
                        if isPsmTransmitter, showRFStrength {
                            // For PSM (P10T), render audio level meters for L/R
                            // (keep existing behavior tied to the RF toggle)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                        ViewThatFits(in: .horizontal) {
                                            Text(applyCapitalization("Audio"))
                                                .font(captionFont)
                                                .foregroundStyle(resolvedSecondaryColor)
                                                .fixedSize(horizontal: true, vertical: false)
                                            EmptyView()
                                        }
                                    }
                                    Spacer()
                                }

                                VStack(alignment: .trailing, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text(applyCapitalization("L"))
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                        let leftBars = psmAudio.map { psmAudioBarCount(from: $0.left) } ?? 0
                                        HStack(spacing: 2) {
                                            ForEach(0..<8, id: \.self) { idx in
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(idx < leftBars ? Color.accentColor : Color.secondary.opacity(0.2))
                                                    .frame(width: 10, height: 6)
                                            }
                                        }
                                    }
                                    HStack(spacing: 4) {
                                        Text(applyCapitalization("R"))
                                            .font(captionFont)
                                            .foregroundStyle(resolvedSecondaryColor)
                                        let rightBars = psmAudio.map { psmAudioBarCount(from: $0.right) } ?? 0
                                        HStack(spacing: 2) {
                                            ForEach(0..<8, id: \.self) { idx in
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(idx < rightBars ? Color.accentColor : Color.secondary.opacity(0.2))
                                                    .frame(width: 10, height: 6)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(resolvedSecondaryColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        } else if !isPsmTransmitter {
                            // For mic receivers: RF and audio are controlled by separate toggles.
                            // Only render the container if at least one of them is requested.
                            if showRFStrength || showAudioMeter {
                                VStack(alignment: .leading, spacing: 6) {
                                    // RF strength row (optional)
                                    if showRFStrength {
                                        HStack(spacing: 8) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "antenna.radiowaves.left.and.right")
                                                    .font(captionFont)
                                                    .foregroundStyle(resolvedSecondaryColor)
                                                Text(applyCapitalization("RF"))
                                                    .font(captionFont)
                                                    .foregroundStyle(resolvedSecondaryColor)
                                            }
                                            Spacer()
                                            if let bars = rfBars {
                                                HStack(spacing: 2) {
                                                    // Matches Shure Wireless Workbench's 6-segment RF
                                                    // meter: segments 1-5 are the normal signal ladder
                                                    // (from RSSI_LED_BITMAP bits 0-4), segment 6 is a
                                                    // separate overload/RF-pad-engaged indicator (bit 5)
                                                    // in red -- confirmed against Shure's own Axient
                                                    // Digital and ANX4 references, it's not just the top
                                                    // of the normal range and can be lit independently of
                                                    // the other 5.
                                                    ForEach(0..<6, id: \.self) { idx in
                                                        let isOLSegment = (idx == 5)
                                                        let isLit = isOLSegment ? rfOverload : (idx < bars)
                                                        let fillColor: Color = {
                                                            guard isLit else { return Color.secondary.opacity(0.2) }
                                                            return isOLSegment ? Color.red.opacity(0.8) : Color.accentColor
                                                        }()

                                                        RoundedRectangle(cornerRadius: 2)
                                                            .fill(fillColor)
                                                            .frame(width: 10, height: 6)
                                                    }
                                                }
                                            } else {
                                                Text("—")
                                                    .font(captionFont)
                                                    .foregroundStyle(resolvedPrimaryColor)
                                            }
                                        }
                                    }

                                    // Mic audio level row (optional, independent of RF)
                                    if showAudioMeter {
                                        HStack(spacing: 8) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .font(captionFont)
                                                    .foregroundStyle(resolvedSecondaryColor)
                                                ViewThatFits(in: .horizontal) {
                                                    Text(applyCapitalization("Audio"))
                                                        .font(captionFont)
                                                        .foregroundStyle(resolvedSecondaryColor)
                                                        .fixedSize(horizontal: true, vertical: false)
                                                    EmptyView()
                                                }
                                            }
                                            Spacer()

                                            let audioBars: Int = {
                                                if let audioLevel = micAudioLevel {
                                                    return micAudioBarCount(from: audioLevel, channelIndex: descriptor.channelIndex)
                                                } else {
                                                    return 0
                                                }
                                            }()

                                            HStack(spacing: 2) {
                                                ForEach(0..<ShureOverviewAudioBucket.segmentCount, id: \.self) { idx in
                                                    // Last segment is a true clip/overage alert,
                                                    // not just "the meter happens to be fully
                                                    // pegged": driven by the receiver's own
                                                    // AUDIO_LED_BITMAP bit 7 ("LED 8 - Red" per
                                                    // Shure's Axient Digital reference), the same
                                                    // way the RF meter's dedicated overload
                                                    // segment above is driven by RSSI_LED_BITMAP
                                                    // bit 5 rather than rfBars alone -- not
                                                    // derived from our own level/bar-count math,
                                                    // which can reach 8/8 at a different
                                                    // threshold than the receiver's own clip
                                                    // detection.
                                                    let isOverageSegment = idx == ShureOverviewAudioBucket.segmentCount - 1
                                                    let isLit = isOverageSegment ? micAudioOverload : (idx < audioBars)
                                                    let fillColor: Color = {
                                                        guard isLit else { return Color.secondary.opacity(0.2) }
                                                        return isOverageSegment ? Color.red.opacity(0.8) : Color.accentColor
                                                    }()
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(fillColor)
                                                        .frame(width: 8, height: 6)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(resolvedSecondaryColor.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    // Ensure the status block consumes the full available width
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(applyCapitalization("No channel selected."))
                    .font(captionFont)
                    .foregroundStyle(resolvedSecondaryColor)
            }
        }
        // Ensure the entire Channel Status section consumes the full available width
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    

    /// Map a PSM audio input level into a 0–8 bar count for display.
    ///
    /// Different PSM 1000 / P10T firmware versions report AUDIO_IN_LVL_* in
    /// slightly different numeric ranges (often in the tens of thousands).
    /// To avoid the meter sitting either at 0 or pegged full, we normalize
    /// over a wide log10 range and then clamp.
    private func psmAudioBarCount(from level: Double) -> Int {
        // Treat non-positive as no signal.
        if level <= 0 { return 0 }

        // Heuristic log-space bounds: assume useful values live somewhere
        // between 10^2 and 10^6. This comfortably covers a wide range of
        // observed PSM AUDIO_IN_LVL values without immediately saturating.
        let logMin: Double = 2.0   // 10^2
        let logMax: Double = 6.0   // 10^6

        let logVal = log10(max(level, pow(10.0, logMin)))
        let ratio = (logVal - logMin) / (logMax - logMin)
        let normalized = min(max(ratio, 0.0), 1.0)

        // Use rounding so mid-range values land in the middle of the bar
        // range instead of being biased low.
        let bars = Int(round(normalized * 8.0))
        return max(0, min(bars, 8))
    }

    private func rfBarFallbackCount(from rfTxLevel: Int) -> Int {
        let clamped = max(0, min(100, rfTxLevel))
        switch clamped {
        case 81...100: return 5
        case 61...80: return 4
        case 41...60: return 3
        case 21...40: return 2
        case 1...20: return 1
        default: return 0
        }
    }

    /// Map a microphone receiver's AUDIO_LVL value into a 0–8 bar count.
    ///
    /// ULX-D/Axient report AUDIO_LVL in a small range, so we scale it
    /// aggressively to keep the meter readable and stable.
    private func micAudioBarCount(from level: Double, channelIndex: Int) -> Int {
        guard level.isFinite else { return 0 }
        if level <= 0 { return 0 }

        if service.standardReportAudioMute(for: channelIndex) == true {
            return 0
        }

        return ShureOverviewAudioBucket.micSegments(level: level)
    }
    private func updateMicLevelStats(channelIndex: Int, level: Double) {
        guard level.isFinite else { return }

        var stats = micLevelStats[channelIndex] ?? (min: level, max: level)

        // Decay window so the meter keeps moving with real-time changes.
        let decay: Double = 0.08
        if level < stats.min {
            stats.min = level
        } else {
            stats.min += (level - stats.min) * decay
        }

        if level > stats.max {
            stats.max = level
        } else {
            stats.max -= (stats.max - level) * decay
        }

        if stats.max - stats.min < 0.1 {
            stats.min = level - 0.05
            stats.max = level + 0.05
        }

        micLevelStats[channelIndex] = stats
    }

    private func updateMicSmoothedLevel(channelIndex: Int, level: Double, isRecent: Bool) {
        let current = micSmoothedLevels[channelIndex] ?? 0.0
        let target = isRecent ? max(level, 0.0) : 0.0
        // Faster rise, slower fall for a more natural meter feel.
        let alpha: Double
        if isRecent {
            alpha = target > current ? 0.7 : 0.45
        } else {
            // Slow decay so meters don't snap to zero between sparse updates.
            alpha = 0.12
        }
        let next = current + (target - current) * alpha
        micSmoothedLevels[channelIndex] = next
    }

    // MARK: - Helpers
    /// Shure brand green used for Mic / IEM pill
    private var shureGreen: Color {
        Color(red: 195.0/255.0, green: 253.0/255.0, blue: 94.0/255.0)
    }
    private var selectedChannelDescriptor: ShureChannelDescriptor? {
        guard let selection = selectedChannel else { return nil }
        guard let device = ExternalDevicesStore.shared.devices.first(where: { $0.id == selection.deviceID }) else { return nil }
        return ShureChannelDescriptor(
            deviceID: device.id,
            deviceName: preferredShureDisplayName(for: device),
            channelIndex: selection.channelIndex
        )
    }

    /// Returns true if the given device should be treated as an in-ear monitor
    /// (PSM-style transmitter), based on its model identifier or name.
    private func isPSMDevice(_ device: ExternalDeviceConfig) -> Bool {
        if let model = device.shureModelIdentifier?.uppercased() {
            if model == "P10T" || model.contains("PSM900") || model.contains("ADTD") || model.contains("ADTQ") {
                return true
            }
        }
        let upperName = device.name.uppercased()
        if upperName.contains("PSM 900") || upperName.contains("PSM900") || upperName.contains("P10T") {
            return true
        }
        if upperName.contains("ADTD") || upperName.contains("ADTQ") {
            return true
        }
        return false
    }

    private func isRecent(_ date: Date?, within seconds: TimeInterval) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= seconds
    }

    private func hasUsableBatteryValue(for channelIndex: Int) -> Bool {
        if let percent = service.standardReportBatteryPercentage(for: channelIndex) {
            return percent > 0
        }
        let batteryLabel = service.standardReportBatteryLabel(for: channelIndex)
        guard let label = batteryLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              label != "—"
        else {
            return false
        }

        var digits = ""
        for character in label {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }

        if let numericValue = Int(digits) {
            return numericValue > 0
        }

        return true
    }

    private func hasRecentBatteryPresence(for channelIndex: Int) -> Bool {
        guard isRecent(service.channelBatteryLastUpdated[channelIndex], within: 2.0) else {
            return false
        }
        return hasUsableBatteryValue(for: channelIndex)
    }

    private func hasExplicitTransmitterPresenceState(for channelIndex: Int) -> Bool {
        service.channelTransmitterPresentLastUpdated[channelIndex] != nil
    }

    private func hasTxDeviceIDPresenceState(for channelIndex: Int) -> Bool {
        service.channelTransmitterDeviceIDLastUpdated[channelIndex] != nil
    }

    private func txDeviceIDPresence(for channelIndex: Int) -> Bool? {
        guard let lastUpdated = service.channelTransmitterDeviceIDLastUpdated[channelIndex],
              let transmitterPresent = service.channelTransmitterDeviceIDPresent[channelIndex] else {
            return nil
        }

        let age = Date().timeIntervalSince(lastUpdated)
        if transmitterPresent {
            return age <= 6.0 ? true : nil
        } else {
            return age <= 1.5 ? false : nil
        }
    }

    private func explicitTransmitterPresence(for channelIndex: Int) -> Bool? {
        guard let lastUpdated = service.channelTransmitterPresentLastUpdated[channelIndex],
              let transmitterPresent = service.channelTransmitterPresent[channelIndex] else {
            return nil
        }

        let age = Date().timeIntervalSince(lastUpdated)
        if transmitterPresent {
            return age <= 6.0 ? true : nil
        } else {
            return age <= 1.5 ? false : nil
        }
    }

    private func recentAxientPositivePresenceEvidence(for channelIndex: Int) -> Date? {
        guard let lastSeenAt = service.channelAxientPositiveEvidenceLastSeenAt[channelIndex] else {
            return nil
        }
        guard Date().timeIntervalSince(lastSeenAt) <= ShureAxientPresenceResolver.positiveEvidenceHoldSeconds else {
            return nil
        }
        return lastSeenAt
    }

    private func receiverPresenceResolution(for descriptor: ShureChannelDescriptor) -> ChannelPowerResolution? {
        let channelIndex = descriptor.channelIndex
        let isAxient = isAxientDevice(for: descriptor)
        let sourceLabel = isAxient ? "chan-quality" : "rf-antenna"

        guard service.channelTransmitterPresentLastUpdated[channelIndex] != nil else {
            return nil
        }

        if isAxient {
            let recentNegativeEvidenceAt = explicitTransmitterPresence(for: channelIndex) == false
                ? service.channelTransmitterPresentLastUpdated[channelIndex]
                : nil
            let resolved = ShureAxientPresenceResolver.resolve(
                recentPositiveEvidenceAt: recentAxientPositivePresenceEvidence(for: channelIndex),
                recentNegativeEvidenceAt: recentNegativeEvidenceAt,
                negativeEvidenceStreakStartAt: service.channelAxientNegativeEvidenceStreakStartAt[channelIndex],
                now: Date()
            )
            return ChannelPowerResolution(isOn: resolved == .on, sourceLabel: sourceLabel)
        }

        let rfBarCount = service.standardReportRfBarCount(for: channelIndex) ?? 0
        let recentFalseAt = isRecent(service.channelTransmitterPresentLastFalseAt[channelIndex], within: 2.0)
            ? service.channelTransmitterPresentLastFalseAt[channelIndex]
            : nil
        let recentTrueAt = isRecent(service.channelTransmitterPresentLastTrueAt[channelIndex], within: 12.0)
            ? service.channelTransmitterPresentLastTrueAt[channelIndex]
            : nil

        if let recentFalseAt, let recentTrueAt {
            if recentTrueAt >= recentFalseAt {
                return ChannelPowerResolution(isOn: true, sourceLabel: "rf-antenna-latched")
            }
            if isRecent(service.channelRfLastUpdated[channelIndex], within: 2.0), rfBarCount <= 1 {
                return ChannelPowerResolution(isOn: false, sourceLabel: "rf-threshold")
            }
            return ChannelPowerResolution(isOn: false, sourceLabel: "rf-antenna-latched")
        }

        if recentFalseAt != nil {
            if isRecent(service.channelRfLastUpdated[channelIndex], within: 2.0), rfBarCount <= 1 {
                return ChannelPowerResolution(isOn: false, sourceLabel: "rf-threshold")
            }
            return ChannelPowerResolution(isOn: false, sourceLabel: "rf-antenna-latched")
        }
        if recentTrueAt != nil {
            return ChannelPowerResolution(isOn: true, sourceLabel: "rf-antenna-latched")
        }
        return ChannelPowerResolution(isOn: false, sourceLabel: sourceLabel)
    }

    private func channelPowerResolution(for descriptor: ShureChannelDescriptor) -> ChannelPowerResolution {
        if isPSM900Device {
            return ChannelPowerResolution(isOn: false, sourceLabel: "psm-placeholder")
        }

        guard let deviceConfig = ExternalDevicesStore.shared.devices.first(where: { $0.id == descriptor.deviceID }) else {
            return ChannelPowerResolution(isOn: false, sourceLabel: "no-device")
        }
        if isPSMDevice(deviceConfig) {
            return ChannelPowerResolution(isOn: false, sourceLabel: "psm-device")
        }

        let channelIndex = descriptor.channelIndex
        let prefersTxDeviceID = isAxientDevice(for: descriptor)

        // Deliberately no "any positive evidence within 12s = on" shortcut
        // here anymore -- that used to short-circuit straight past
        // receiverPresenceResolution below (where ShureAxientPresenceResolver
        // actually lives), so fresh, sustained negative evidence
        // (CHAN_QUALITY 255, empty TX_DEVICE_ID) had no way to override a
        // still-fresh positive hold. Confirmed on a real field log: the
        // single-tile header stayed green for the full ~12s hold after a
        // mic was powered off, while the Overview (which always went
        // through the resolver) recovered in ~2s. The positive-evidence
        // sources this shortcut covered are still fully considered --
        // receiverPresenceResolution passes the same
        // recentAxientPositivePresenceEvidence into the resolver -- just
        // weighed against negative evidence instead of overriding it
        // unconditionally.
        if prefersTxDeviceID, txDeviceIDPresence(for: channelIndex) == true {
            return ChannelPowerResolution(isOn: true, sourceLabel: "tx-device-id")
        }
        if prefersTxDeviceID, let transmitterPresent = txDeviceIDPresence(for: channelIndex) {
            return ChannelPowerResolution(isOn: transmitterPresent, sourceLabel: "tx-device-id")
        }
        if let receiverPresence = receiverPresenceResolution(for: descriptor) {
            return receiverPresence
        }
        if isRecent(service.channelPresenceLastSeenAt[channelIndex], within: 4.0) {
            return ChannelPowerResolution(isOn: true, sourceLabel: "battery-latch")
        }
        if hasRecentBatteryPresence(for: channelIndex) {
            return ChannelPowerResolution(isOn: true, sourceLabel: "battery")
        }
        if prefersTxDeviceID, hasTxDeviceIDPresenceState(for: channelIndex) {
            return ChannelPowerResolution(isOn: false, sourceLabel: "tx-device-id")
        }
        return ChannelPowerResolution(isOn: false, sourceLabel: "none")
    }

    /// Presence latch for mic transmitters. We use stable live evidence
    /// and hold it briefly so the on-state does not flicker while battery
    /// labels resolve. Stale cached battery labels alone do not count as on.
    private func isChannelPoweredOn(for descriptor: ShureChannelDescriptor) -> Bool {
        channelPowerResolution(for: descriptor).isOn
    }

    private func isAxientDevice(for descriptor: ShureChannelDescriptor) -> Bool {
        guard let deviceConfig = ExternalDevicesStore.shared.devices.first(where: { $0.id == descriptor.deviceID }) else {
            return false
        }
        let model = (deviceConfig.shureModelIdentifier ?? "").uppercased()
        if model.contains("AD4") || model.contains("ANX4") || model.contains("AXIENT") {
            return true
        }
        return false
    }

    /// Attempt to extract a numeric battery percentage for this channel.
    private func batteryPercent(for descriptor: ShureChannelDescriptor) -> Int? {
        // PSM placeholders and IEM devices use a different visual language;
        // we only care about a mic's battery percentage here.
        if isPSM900Device {
            return nil
        }
        guard let deviceConfig = ExternalDevicesStore.shared.devices.first(where: { $0.id == descriptor.deviceID }) else {
            return nil
        }
        if isPSMDevice(deviceConfig) {
            return nil
        }

        return service.standardReportBatteryPercentage(for: descriptor.channelIndex)
    }

    /// Determine the fill color for the channel pill behind the Mic/IEM
    /// name, based on power and battery state:
    ///  - Grey: mic off / no valid battery data
    ///  - Green: mic on with battery > 20%
    ///  - Red: mic on with battery <= 20%
    private func channelStatusColor(for descriptor: ShureChannelDescriptor) -> Color {
        // If we don't consider the channel "on" at all, always show grey.
        guard isChannelPoweredOn(for: descriptor) else {
            return resolvedSecondaryColor.opacity(0.15)
        }

        // Try to get a percent; if we can't, treat as "on but unknown" and
        // keep the standard green.
        if let percent = batteryPercent(for: descriptor) {
            if percent <= 20 {
                // Critically low battery: highlight in red.
                return Color.red.opacity(0.35)
            } else {
                return Color.green.opacity(0.35)
            }
        } else {
            return Color.green.opacity(0.35)
        }
    }

    // MARK: - Parsing Helpers

    /// Parse the most recent FREQUENCY report for the selected channel.
    private func parseFrequency<S: Sequence>(from lines: S) -> String? where S.Element == String {
        for line in lines {
            // Expect patterns like: REP x FREQUENCY yyyyyy
            let parts = line.split(separator: " ")
            guard parts.count >= 4 else { continue }

            let verb = parts[0].uppercased()
            if (verb == "REP" || verb == "REPORT"),
               let _ = Int(parts[1]),
               parts[2].uppercased() == "FREQUENCY" {
                let raw = String(parts[3])
                // Many Shure devices represent frequency as kHz or yyy.yyy MHz;
                // here we simply pass it through or format if numeric.
                if let numeric = Double(raw) {
                    // Heuristic: if large, assume kHz and convert to MHz.
                    if numeric > 1000 {
                        let mhz = numeric / 1000.0
                        return String(format: "%.3f MHz", mhz)
                    } else {
                        return String(format: "%.3f MHz", numeric)
                    }
                } else {
                    return raw
                }
            }
        }
        return nil
    }

    ///
    /// Priority:
    ///  1. For PSM 1000 (P10T) or PSM 900, use manual channel names from External Devices settings.
    ///  2. For receivers that report CHAN_NAME, use the live channel name.
    ///  3. Fall back to "DeviceName – CH X".
    private func label(for descriptor: ShureChannelDescriptor) -> String {
        // Helper to normalize manual PSM names.
        func prettifiedPSMName(_ raw: String?) -> String? {
            guard let raw = raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            // Allow users to type names like "Bass_Guitar" and render them as "Bass Guitar".
            return trimmed.replacingOccurrences(of: "_", with: " ")
        }

        // 1) Prefer the External Devices config/cache for edit-mode-friendly titles.
        if let deviceConfig = ExternalDevicesStore.shared.devices.first(where: { $0.id == descriptor.deviceID }) {
            let modelCode = (deviceConfig.shureModelIdentifier ?? "").uppercased()
            let upperName = deviceConfig.name.uppercased()

            let isP10T = modelCode.contains("P10T") || upperName.contains("P10T")
            let isPSM900 = modelCode.contains("PSM900")
                || modelCode.contains("PSM 900")
                || modelCode.contains("P9T")
                || upperName.contains("PSM 900")
                || upperName.contains("PSM900")
                || upperName.contains("P9T")

            if isP10T {
                // PSM 1000 / P10T is always 2 channels.
                if descriptor.channelIndex == 1,
                   let pretty = prettifiedPSMName(deviceConfig.psmChannel1Name) {
                    return pretty
                }

                if descriptor.channelIndex == 2,
                   let pretty = prettifiedPSMName(deviceConfig.psmChannel2Name) {
                    return pretty
                }
            } else if isPSM900 {
                // PSM 900 uses only a single custom name (psmChannel1Name)
                if descriptor.channelIndex == 1,
                   let pretty = prettifiedPSMName(deviceConfig.psmChannel1Name) {
                    return pretty
                }
            }

            if let cached = ExternalDevicesStore.shared.cachedShureChannelName(
                deviceID: deviceConfig.id,
                channelIndex: descriptor.channelIndex
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
               !cached.isEmpty {
                return cached
            }

            if let stored = deviceConfig.shureChannelNames[descriptor.channelIndex]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !stored.isEmpty {
                return stored
            }
        }

        // 1b) Fallback: Some descriptors may not carry the same externalDeviceID that is
        // stored in ExternalDevicesStore, especially for offline PSM 900 placeholders.
        // As a safety net, try to match by device name substring for PSM 900-type devices.
        if descriptor.channelIndex == 1 {
            let upperDescriptorName = descriptor.deviceName.uppercased()

            if let config = ExternalDevicesStore.shared.devices.first(where: { device in
                let modelCode = (device.shureModelIdentifier ?? "").uppercased()
                let upperConfigName = device.name.uppercased()

                let isPSM900 = modelCode.contains("PSM900")
                    || modelCode.contains("PSM 900")
                    || modelCode.contains("P9T")
                    || upperConfigName.contains("PSM 900")
                    || upperConfigName.contains("PSM900")
                    || upperConfigName.contains("P9T")

                guard isPSM900 else { return false }

                // Allow "PSM 900 - WT 8 - Ch 1" vs "PSM 900 - WT 8" etc.
                return upperDescriptorName.contains(upperConfigName)
                    || upperConfigName.contains(upperDescriptorName)
            }),
               let pretty = prettifiedPSMName(config.psmChannel1Name) {
                return pretty
            }
        }

        // 2) Next, fall back to any live CHAN_NAME reports from the receiver.
        if let device = service.device,
           device.id == descriptor.deviceID {
            if let name = service.standardReportChannelName(for: descriptor.channelIndex),
               !name.trimmingCharacters(in: .whitespaces).isEmpty {
                return name
            }
        }

        // 3) Fallback: "DeviceName – CH X"
        return "\(descriptor.deviceName) – CH \(descriptor.channelIndex)"
    }
}


// MARK: - Shure Module Plugin

/// Plugin wrapper so Shure Wireless can be rendered via the shared module-plugin pipeline.
///
/// NOTE: This assumes your `DashboardModuleKind` includes `.shureWireless` and that
/// `DashboardModuleModel` stores Shure settings in `shureSelectedChannel` and related
/// boolean fields. If your field names differ, adjust the bindings below to match.

enum ShureWirelessModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .shureWireless }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        // Bind the selected channel + display toggles from the module model.
        // These defaults preserve existing behavior if any fields are missing.
        // Module-owned Shure config is the single source of truth.
        // If missing, seed a default config.
        let configBinding = Binding<ShureModuleConfig>(
            get: { module.wrappedValue.shureConfig ?? ShureModuleConfig.default() },
            set: { module.wrappedValue.shureConfig = $0 }
        )

        // Optional: if module has no selection yet, inherit from legacy tile-level selection once.
        if configBinding.wrappedValue.selectedChannel == nil,
           let legacy = tile.wrappedValue.shureChannelSelection {
            var seeded = configBinding.wrappedValue
            seeded.selectedChannel = legacy
            configBinding.wrappedValue = seeded
        }

        let selectedChannel = Binding<ExternalDevicesStore.ShureSelectedChannel?>(
            get: { configBinding.wrappedValue.selectedChannel },
            set: { newValue in
                var updated = configBinding.wrappedValue
                updated.selectedChannel = newValue
                configBinding.wrappedValue = updated
            }
        )

        let config = configBinding.wrappedValue
        let showsHeader = true
        let showDeviceName = config.showDeviceName
        let showChannelName = config.showChannelName
        let showIPPort = config.showIPPort
        let showFrequency = config.showFrequency
        let showBattery = config.showBattery
        let showRFStrength = config.showRFStrength
        let showAudioMeter = config.showAudioMeter

        return AnyView(
            ShureWirelessModuleView(
                selectedChannel: selectedChannel,
                showsHeader: showsHeader,
                isLiveMode: isLiveMode,
                showDeviceName: showDeviceName,
                showChannelName: showChannelName,
                showIPPort: showIPPort,
                showFrequency: showFrequency,
                showBattery: showBattery,
                showRFStrength: showRFStrength,
                showAudioMeter: showAudioMeter,
                demoEnabled: config.demoEnabled,
                demoIsIem: config.demoIsIem,
                demoMicName: config.demoMicName,
                demoDeviceName: config.demoDeviceName,
                demoBatteryPercent: config.demoBatteryPercent,
                demoFrequencyMHz: config.demoFrequencyMHz
            )
            .id(isLiveMode)
        )
    }

    /// The shared plugin protocol currently only provides a `showsHeader` binding for settings.
    /// We bridge this into the module so the header toggle stays module-owned.
    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Shure Wireless") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show header (Shure Wireless)", isOn: showsHeader)
                            .onChange(of: showsHeader.wrappedValue, initial: false) { _, _ in onPersist() }
                    }
                    .toggleStyle(.switch)
                }
            }
        )
    }
}

// MARK: - Shure Module Settings Inspector

/// Module-owned settings UI for Shure Wireless.
///
/// This mirrors the legacy `shureSection` from DashboardTileEditView, but binds directly
/// to a module's stored `ShureModuleConfig`.
struct ShureModuleSettingsInspector: View {
    @Binding var config: ShureModuleConfig
    var channels: [ShureChannelDescriptor]
    var showsTitle: Binding<Bool>
    var onPersist: () -> Void
    @ObservedObject private var externalStore = ExternalDevicesStore.shared

    var body: some View {
        // Determine if this module's selected channel is a PSM device.
        let isPSM: Bool = {
            guard let stored = config.selectedChannel else { return false }
            let devices = ExternalDevicesStore.shared.devices
            guard let device = devices.first(where: { $0.id == stored.deviceID }) else { return false }
            return isPSMDevice(device)
        }()

        let isPSM900: Bool = {
            guard let stored = config.selectedChannel else { return false }
            let devices = ExternalDevicesStore.shared.devices
            guard let device = devices.first(where: { $0.id == stored.deviceID }) else { return false }
            return isPSM900Device(device)
        }()

        // Map between ShureModuleConfig.selectedChannel and ShureChannelDescriptor
        let selectionBinding = Binding<ShureChannelDescriptor?>(
            get: {
                guard let stored = config.selectedChannel else { return nil }
                return channels.first {
                    $0.deviceID == stored.deviceID && $0.channelIndex == stored.channelIndex
                }
            },
            set: { newChoice in
                if let choice = newChoice {
                    config.selectedChannel = ExternalDevicesStore.ShureSelectedChannel(
                        deviceID: choice.deviceID,
                        channelIndex: choice.channelIndex
                    )
                } else {
                    config.selectedChannel = nil
                }
                onPersist()
            }
        )

        return GroupBox("Shure Wireless Module") {
            VStack(alignment: .leading, spacing: 8) {
                if channels.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Shure channels found.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Add a Shure Wireless device in Settings → External Devices.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Channel", selection: selectionBinding) {
                        ForEach(channels) { channel in
                            Text({
                                // Prefer: manual PSM names, then cached CHAN_NAME, then fallback.
                                if let device = externalStore.devices.first(where: { $0.id == channel.deviceID }) {
                                    return externalStore.shureChannelDisplayLabel(device: device, channelIndex: channel.channelIndex)
                                }
                                return channel.displayName
                            }())
                            .tag(Optional<ShureChannelDescriptor>(channel))
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Show module title", isOn: showsTitle)
                        .onChange(of: showsTitle.wrappedValue, initial: false) { _, _ in
                            onPersist()
                        }

                    Divider()
                        .padding(.vertical, 4)

                    Text("Display Options")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isPSM900 {
                        // PSM 900: OFFLINE – only channel + device name
                        Toggle("Show channel name", isOn: Binding(
                            get: { config.showChannelName },
                            set: { config.showChannelName = $0; onPersist() }
                        ))

                        Toggle("Show device name", isOn: Binding(
                            get: { config.showDeviceName },
                            set: { config.showDeviceName = $0; onPersist() }
                        ))

                    } else if isPSM {
                        Toggle("Show channel name", isOn: Binding(
                            get: { config.showChannelName },
                            set: { config.showChannelName = $0; onPersist() }
                        ))

                        Toggle("Show device name", isOn: Binding(
                            get: { config.showDeviceName },
                            set: { config.showDeviceName = $0; onPersist() }
                        ))

                        Toggle("Show IP:Port", isOn: Binding(
                            get: { config.showIPPort },
                            set: { config.showIPPort = $0; onPersist() }
                        ))

                        Toggle("Show frequency", isOn: Binding(
                            get: { config.showFrequency },
                            set: { config.showFrequency = $0; onPersist() }
                        ))

                        // For PSM (P10T), the tile uses the RF toggle to show L/R audio meters.
                        Toggle("Show audio meter", isOn: Binding(
                            get: { config.showRFStrength },
                            set: { config.showRFStrength = $0; onPersist() }
                        ))

                    } else {
                        Toggle("Show channel name", isOn: Binding(
                            get: { config.showChannelName },
                            set: { config.showChannelName = $0; onPersist() }
                        ))

                        Toggle("Show device name", isOn: Binding(
                            get: { config.showDeviceName },
                            set: { config.showDeviceName = $0; onPersist() }
                        ))

                        Toggle("Show IP:Port", isOn: Binding(
                            get: { config.showIPPort },
                            set: { config.showIPPort = $0; onPersist() }
                        ))

                        Toggle("Show frequency", isOn: Binding(
                            get: { config.showFrequency },
                            set: { config.showFrequency = $0; onPersist() }
                        ))

                        Toggle("Show battery level", isOn: Binding(
                            get: { config.showBattery },
                            set: { config.showBattery = $0; onPersist() }
                        ))

                        Toggle("Show RF strength", isOn: Binding(
                            get: { config.showRFStrength },
                            set: { config.showRFStrength = $0; onPersist() }
                        ))

                        Toggle("Show audio meter", isOn: Binding(
                            get: { config.showAudioMeter },
                            set: { config.showAudioMeter = $0; onPersist() }
                        ))
                    }
                }
#if DEBUG
                GroupBox("Demo Mode (Debug)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use Demo Data for Wireless Modules", isOn: $config.demoEnabled)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Device Name")
                                TextField("", text: $config.demoDeviceName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("Mic / Channel Name")
                                TextField("", text: $config.demoMicName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Toggle("IEM Mode", isOn: $config.demoIsIem)

                            HStack {
                                Text("Battery")
                                Spacer()
                                Stepper(value: $config.demoBatteryPercent, in: 0...100, step: 1) {
                                    Text("\(config.demoBatteryPercent)%")
                                        .frame(minWidth: 48, alignment: .trailing)
                                }
                            }

                            HStack {
                                Text("Frequency")
                                Spacer()
                                Stepper(value: $config.demoFrequencyMHz, in: 400.0...700.0, step: 0.025) {
                                    Text(String(format: "%.3f MHz", config.demoFrequencyMHz))
                                        .frame(minWidth: 110, alignment: .trailing)
                                }
                            }
                        }
                        .disabled(!config.demoEnabled)
                        .opacity(config.demoEnabled ? 1.0 : 0.5)
                    }
                }
#endif
            }
            .toggleStyle(.switch)
            .onAppear {
                // One-shot refresh so the dropdown can show real channel names before selection.
                externalStore.requestShureNameRefreshIfNeeded()

                // Auto-select the first available channel the first time this module is configured.
                if config.selectedChannel == nil, let first = channels.first {
                    config.selectedChannel = ExternalDevicesStore.ShureSelectedChannel(
                        deviceID: first.deviceID,
                        channelIndex: first.channelIndex
                    )
                    onPersist()
                }
            }
        }
    }

    private func isPSMDevice(_ device: ExternalDeviceConfig) -> Bool {
        let model = (device.shureModelIdentifier ?? "").uppercased()
        let name = device.name.uppercased()
        return model == "P10T" || model.contains("PSM900") || name.contains("P10T") || name.contains("PSM 900") || name.contains("PSM900")
    }

    private func isPSM900Device(_ device: ExternalDeviceConfig) -> Bool {
        let model = (device.shureModelIdentifier ?? "").uppercased()
        let name = device.name.uppercased()
        return model.contains("PSM900") || name.contains("PSM 900") || name.contains("PSM900")
    }
}
