//
//  ProPresenterModuleConfig.swift
//  Relay
//
//  Created by David Bullard on 12/16/25.
//


//
//  ProPresenterModuleView.swift
//  Relay
//
//  ProPresenter module “plugin” bundle (UI + config + service + edit UI)
//

import SwiftUI
import Foundation
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Module Config

/// Stored with a module instance (Codable).
/// Key point: each module can point at a specific saved profile (UUID) so multiple
/// ProPresenters can run simultaneously.
struct ProPresenterModuleConfig: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()

    /// Which saved ProPresenter connection profile this module uses.
    /// nil is treated as "not selected" and is only retained for legacy decoding.
    var connectionProfileID: UUID? = nil

    /// Poll interval override (optional). If nil, use global poll interval.
    var pollIntervalOverride: Double? = nil

    /// What kind of ProPresenter data this module displays.
    var dataMode: ProPresenterDataMode = .slideCurrentNext

	// Display options
	var showPresentationName: Bool = true
		var showArrangementName: Bool = true
	var showSlideNumbers: Bool = false
	var showGroupName: Bool = false
	var showGroupColor: Bool = false
	var slideContentMode: ProPresenterSlideContentMode = .text
	var maxPreviewLines: Int = 2
    /// For Timers mode: if set, show only this timer. nil/empty = show all timers.
    var selectedTimerUUID: String? = nil
    /// For Message mode: pick stage vs audience endpoint.
    var messageTarget: ProPresenterMessageTarget = .stage
    var stageMessageFlashEnabled: Bool = true
    var stageMessageFlashColor: CodableColor? = CodableColor(red: 1, green: 0, blue: 0)
    var stageMessageFlashRepeatCount: Int = 5
    var stageMessageFlashIndefinite: Bool = false
    var audienceMessageFlashEnabled: Bool = true
    var audienceMessageFlashColor: CodableColor? = CodableColor(red: 1, green: 0, blue: 0)
    var audienceMessageFlashRepeatCount: Int = 5
    var audienceMessageFlashIndefinite: Bool = false
    /// Show request/response/debug text inside the tile.
    var showDebugInfo: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case connectionProfileID
        case pollIntervalOverride
        case dataMode
        case showPresentationName
        case showArrangementName
        case showSlideNumbers
        case showGroupName
        case showGroupColor
        case slideContentMode
        case showSlideThumbnails
        case showGroupInfo
        case maxPreviewLines
        case selectedTimerUUID
        case messageTarget
        case stageMessageFlashEnabled
        case stageMessageFlashColor
        case stageMessageFlashRepeatCount
        case stageMessageFlashIndefinite
        case audienceMessageFlashEnabled
        case audienceMessageFlashColor
        case audienceMessageFlashRepeatCount
        case audienceMessageFlashIndefinite
        case showDebugInfo
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        connectionProfileID = try container.decodeIfPresent(UUID.self, forKey: .connectionProfileID)
        pollIntervalOverride = try container.decodeIfPresent(Double.self, forKey: .pollIntervalOverride)
        dataMode = try container.decodeIfPresent(ProPresenterDataMode.self, forKey: .dataMode) ?? .slideCurrentNext
        showPresentationName = try container.decodeIfPresent(Bool.self, forKey: .showPresentationName) ?? true
        showArrangementName = try container.decodeIfPresent(Bool.self, forKey: .showArrangementName) ?? true
        showSlideNumbers = try container.decodeIfPresent(Bool.self, forKey: .showSlideNumbers) ?? false
        let legacyGroupInfo = try container.decodeIfPresent(Bool.self, forKey: .showGroupInfo)
        showGroupName = try container.decodeIfPresent(Bool.self, forKey: .showGroupName) ?? legacyGroupInfo ?? false
        showGroupColor = try container.decodeIfPresent(Bool.self, forKey: .showGroupColor) ?? legacyGroupInfo ?? false
        if let mode = try container.decodeIfPresent(ProPresenterSlideContentMode.self, forKey: .slideContentMode) {
            slideContentMode = mode
        } else {
            let legacyThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showSlideThumbnails) ?? false
            slideContentMode = legacyThumbnails ? .thumbnail : .text
        }
        maxPreviewLines = try container.decodeIfPresent(Int.self, forKey: .maxPreviewLines) ?? 2
        selectedTimerUUID = try container.decodeIfPresent(String.self, forKey: .selectedTimerUUID)
        messageTarget = try container.decodeIfPresent(ProPresenterMessageTarget.self, forKey: .messageTarget) ?? .stage
        stageMessageFlashEnabled = try container.decodeIfPresent(Bool.self, forKey: .stageMessageFlashEnabled) ?? true
        stageMessageFlashColor = try container.decodeIfPresent(CodableColor.self, forKey: .stageMessageFlashColor)
            ?? CodableColor(red: 1, green: 0, blue: 0)
        stageMessageFlashRepeatCount = try container.decodeIfPresent(Int.self, forKey: .stageMessageFlashRepeatCount) ?? 5
        stageMessageFlashIndefinite = try container.decodeIfPresent(Bool.self, forKey: .stageMessageFlashIndefinite) ?? false
        audienceMessageFlashEnabled = try container.decodeIfPresent(Bool.self, forKey: .audienceMessageFlashEnabled) ?? true
        audienceMessageFlashColor = try container.decodeIfPresent(CodableColor.self, forKey: .audienceMessageFlashColor)
            ?? CodableColor(red: 1, green: 0, blue: 0)
        audienceMessageFlashRepeatCount = try container.decodeIfPresent(Int.self, forKey: .audienceMessageFlashRepeatCount) ?? 5
        audienceMessageFlashIndefinite = try container.decodeIfPresent(Bool.self, forKey: .audienceMessageFlashIndefinite) ?? false
        showDebugInfo = try container.decodeIfPresent(Bool.self, forKey: .showDebugInfo) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(connectionProfileID, forKey: .connectionProfileID)
        try container.encodeIfPresent(pollIntervalOverride, forKey: .pollIntervalOverride)
        try container.encode(dataMode, forKey: .dataMode)
        try container.encode(showPresentationName, forKey: .showPresentationName)
        try container.encode(showArrangementName, forKey: .showArrangementName)
        try container.encode(showSlideNumbers, forKey: .showSlideNumbers)
        try container.encode(showGroupName, forKey: .showGroupName)
        try container.encode(showGroupColor, forKey: .showGroupColor)
        try container.encode(slideContentMode, forKey: .slideContentMode)
        try container.encode(maxPreviewLines, forKey: .maxPreviewLines)
        try container.encodeIfPresent(selectedTimerUUID, forKey: .selectedTimerUUID)
        try container.encode(messageTarget, forKey: .messageTarget)
        try container.encode(stageMessageFlashEnabled, forKey: .stageMessageFlashEnabled)
        try container.encodeIfPresent(stageMessageFlashColor, forKey: .stageMessageFlashColor)
        try container.encode(stageMessageFlashRepeatCount, forKey: .stageMessageFlashRepeatCount)
        try container.encode(stageMessageFlashIndefinite, forKey: .stageMessageFlashIndefinite)
        try container.encode(audienceMessageFlashEnabled, forKey: .audienceMessageFlashEnabled)
        try container.encodeIfPresent(audienceMessageFlashColor, forKey: .audienceMessageFlashColor)
        try container.encode(audienceMessageFlashRepeatCount, forKey: .audienceMessageFlashRepeatCount)
        try container.encode(audienceMessageFlashIndefinite, forKey: .audienceMessageFlashIndefinite)
        try container.encode(showDebugInfo, forKey: .showDebugInfo)
    }
}

// MARK: - Data Mode

/// What payload this module should request / display.
///
/// Notes:
/// - Slide status comes from `GET /v1/status/slide`.
/// - Timers come from `GET /v1/timers/current`.
/// - Video countdown comes from `GET /v1/timer/video_countdown`.
enum ProPresenterDataMode: String, Codable, CaseIterable, Identifiable {
    case slideCurrentNext
    case slideCurrentOnly
    case slideNextOnly

    case timersCurrent
    case timerVideoCountdown
    case stageMessage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slideCurrentNext: return "Current + Next Slide"
        case .slideCurrentOnly: return "Current Slide"
        case .slideNextOnly: return "Next Slide"
        case .timersCurrent: return "Timers"
        case .timerVideoCountdown: return "Video Countdown"
        case .stageMessage: return "Message"
        }
    }

    /// Primary endpoint to call for this data mode.
    func requestPath(messageTarget: ProPresenterMessageTarget) -> String {
        switch self {
        case .slideCurrentNext, .slideCurrentOnly, .slideNextOnly:
            return "/v1/status/slide"
        case .timersCurrent:
            return "/v1/timers/current"
        case .timerVideoCountdown:
            return "/v1/timer/video_countdown"
        case .stageMessage:
            return messageTarget.requestPath
        }
    }

    /// Label shown above the main value.
    var primaryLabel: String {
        switch self {
        case .slideCurrentNext, .slideCurrentOnly: return "Current"
        case .slideNextOnly: return "Next"
        case .timersCurrent: return "Timers"
        case .timerVideoCountdown: return "Video Countdown"
        case .stageMessage: return "Message"
        }
    }

    /// Whether this mode inherently has a “next” secondary value.
    var supportsNextPreview: Bool {
        switch self {
        case .slideCurrentNext:
            return true
        default:
            return false
        }
    }

    var isSlideMode: Bool {
        switch self {
        case .slideCurrentNext, .slideCurrentOnly, .slideNextOnly:
            return true
        default:
            return false
        }
    }
}

enum ProPresenterSlideContentMode: String, Codable, CaseIterable, Identifiable {
    case text
    case notes
    case thumbnail

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .notes:
            return "Notes"
        case .thumbnail:
            return "Thumbnail"
        }
    }
}

enum ProPresenterMessageTarget: String, Codable, CaseIterable, Identifiable {
    case stage
    case audience

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stage: return "Stage"
        case .audience: return "Audience"
        }
    }

    var requestPath: String {
        switch self {
        case .stage: return "/v1/stage/message"
        case .audience: return "/v1/message"
        }
    }
}

// MARK: - Probe state (connectivity check when not in live mode)

enum ProPresenterProbeState {
    case idle
    case checking
    case reachable
    case unreachable
}

// MARK: - Generic JSON decoding (schema-safe)

/// Generic JSON value to decode unknown ProPresenter responses without being brittle.
enum JSONValue: Decodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: AnyCodingKey.self) {
            var obj: [String: JSONValue] = [:]
            for k in c.allKeys {
                obj[k.stringValue] = try c.decode(JSONValue.self, forKey: k)
            }
            self = .object(obj)
            return
        }
        if var a = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !a.isAtEnd {
                arr.append(try a.decode(JSONValue.self))
            }
            self = .array(arr)
            return
        }

        let s = try decoder.singleValueContainer()
        if s.decodeNil() { self = .null; return }
        if let b = try? s.decode(Bool.self) { self = .bool(b); return }
        if let d = try? s.decode(Double.self) { self = .number(d); return }
        if let t = try? s.decode(String.self) { self = .string(t); return }
        self = .null
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    func asString() -> String? {
        switch self {
        case .string(let s): return s
        case .number(let n):
            // Keep integers clean
            if n.rounded(.towardZero) == n { return String(Int(n)) }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    func asInt() -> Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    func debugCompactString(maxLength: Int = 700) -> String {
        func render(_ v: JSONValue) -> String {
            switch v {
            case .null: return "null"
            case .bool(let b): return b ? "true" : "false"
            case .number(let n):
                if n.rounded(.towardZero) == n { return String(Int(n)) }
                return String(n)
            case .string(let s):
                let escaped = s
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                return "\"\(escaped)\""
            case .array(let a):
                let items = a.prefix(25).map(render).joined(separator: ",")
                return "[" + items + (a.count > 25 ? ",…" : "") + "]"
            case .object(let o):
                let keys = o.keys.sorted()
                let parts = keys.prefix(40).map { k in
                    let vv = o[k] ?? .null
                    return "\"\(k)\":" + render(vv)
                }
                return "{" + parts.joined(separator: ",") + (keys.count > 40 ? ",…" : "") + "}"
            }
        }

        let raw = render(self)
        if raw.count <= maxLength { return raw }
        return String(raw.prefix(maxLength)) + "..."
    }
}

extension JSONValue {
    func decodedJSONValueIfJSONString() -> JSONValue? {
        guard case .string(let raw) = self else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        if let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return decoded
        }
        // Best-effort: find JSON boundaries in case of extra text.
        guard let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = trimmed.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start <= end else {
            return nil
        }
        let json = String(trimmed[start...end])
        guard let sanitized = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: sanitized)
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

// MARK: - Normalized state for UI

struct ProPresenterSlideStatus: Equatable {
    var isConnected: Bool
    var presentationName: String?
    var arrangementName: String?

	// Current
	var slideText: String?
    var slideNotes: String?
	var slideIndex: Int?
	var slideTotal: Int?
	var slideLabel: String?
	var slideUUID: String?
	var groupName: String? = nil
	var groupColor: CodableColor? = nil

    // Next
    var nextSlideText: String?
    var nextSlideNotes: String?
	var nextSlideUUID: String?

	static let empty = ProPresenterSlideStatus(
		isConnected: false,
		presentationName: nil,
		arrangementName: nil,
		slideText: nil,
        slideNotes: nil,
		slideIndex: nil,
		slideTotal: nil,
		slideLabel: nil,
		slideUUID: nil,
		nextSlideText: nil,
        nextSlideNotes: nil,
		nextSlideUUID: nil
	)
}

// MARK: - Service (poll loop per module)

@MainActor
final class ProPresenterService: ObservableObject {
    struct ProPresenterGroupRange: Equatable {
        var start: Int
        var end: Int
        var name: String?
        var color: CodableColor?
        var slideTexts: [String]
        var slideUUIDs: [String]
    }
    struct TimerItem: Equatable, Identifiable {
        var id: String { uuid ?? name ?? "timer" }
        var uuid: String?
        var name: String?
        var time: String?
        var state: String?
    }
    struct AudienceMessageOption: Equatable, Identifiable {
        var id: String
        var name: String
        var message: String
        var isActive: Bool
        var isVisible: Bool
    }
    struct State: Equatable {
        var status: ProPresenterSlideStatus = .empty
        var lastError: String? = nil
        var lastUpdated: Date? = nil
        var isPolling: Bool = false
        var lastSourceKey: String? = nil

        // Debug
        var lastRequestDescription: String? = nil
        var lastResponseSummary: String? = nil
        var lastJSONPreview: String? = nil

        // Active presentation debug
        var lastPresentationRequest: String? = nil
        var lastPresentationJSONPreview: String? = nil
        var lastPresentationError: String? = nil
        var lastSlideTotal: Int? = nil
        var lastSlideTotalUpdated: Date? = nil
        var lastSlideTotalRequest: String? = nil
        var lastSlideTotalJSONPreview: String? = nil
        var lastSlideTotalError: String? = nil
        /// 0-based slide index from GET /v1/presentation/slide_index (the only authoritative source).
        var lastAPISlideIndex: Int? = nil
        var lastGroupName: String? = nil
        var lastGroupColor: CodableColor? = nil
        var lastGroupRanges: [ProPresenterGroupRange] = []
        var lastGroupRangesUpdated: Date? = nil
        var lastGroupSlideIndex: Int? = nil
        var lastGroupSummary: String? = nil
        var lastPlaylistItemIndex: Int? = nil
        var lastThumbnailCurrentIndex: Int? = nil
        var lastThumbnailNextIndex: Int? = nil
        var lastThumbnailPlaylistItemIndex: Int? = nil
        var lastThumbnailQuality: Int? = nil
        var lastThumbnailCurrentData: Data? = nil
        var lastThumbnailNextData: Data? = nil
        // Timers (structured)
        var lastTimers: [TimerItem] = []
        var lastAudienceMessages: [AudienceMessageOption] = []
    }

    /// The subset of State relevant to detecting a change worth firing an automation
    /// trigger for. Deliberately excludes debug/preview fields (lastJSONPreview, etc.)
    /// that change on every poll regardless of actual content.
    struct ChangeSnapshot: Equatable {
        var slideUUID: String?
        var slideIndex: Int?
        var slideLabel: String?
        var presentationName: String?
        var arrangementName: String?
        var activeMessageName: String?
        var activeMessageText: String?
        var timerStatesByName: [String: String]
    }

    enum ChangeKind: Equatable {
        case slideChanged(label: String?, index: Int?)
        case presentationChanged(name: String?)
        case messageChanged(name: String?, text: String?)
        case timerChanged(name: String?, value: String?)
    }

    /// Builds a ChangeSnapshot from a State. The single active message (if any) is used
    /// for messageChanged -- if multiple messages are ever active simultaneously this only
    /// tracks the first, which matches how the tile UI already treats "the current message."
    static func changeSnapshot(from state: State) -> ChangeSnapshot {
        let activeMessage = state.lastAudienceMessages.first(where: { $0.isActive })
        var timerStates: [String: String] = [:]
        for timer in state.lastTimers {
            let key = timer.name ?? timer.uuid ?? "timer"
            timerStates[key] = timer.state ?? ""
        }
        return ChangeSnapshot(
            slideUUID: state.status.slideUUID,
            slideIndex: state.status.slideIndex,
            slideLabel: state.status.slideLabel,
            presentationName: state.status.presentationName,
            arrangementName: state.status.arrangementName,
            activeMessageName: activeMessage?.name,
            activeMessageText: activeMessage?.message,
            timerStatesByName: timerStates
        )
    }

    /// Pure diff between two snapshots. Order of returned changes is: slide, presentation,
    /// message, then any changed timers (sorted by name for determinism). Multiple changes
    /// can be returned from one tick (e.g. jumping to a different presentation changes both
    /// the presentation name and the slide at once).
    static func detectChanges(before: ChangeSnapshot, after: ChangeSnapshot) -> [ChangeKind] {
        var changes: [ChangeKind] = []

        if before.slideUUID != after.slideUUID || before.slideIndex != after.slideIndex {
            changes.append(.slideChanged(label: after.slideLabel, index: after.slideIndex))
        }

        if before.presentationName != after.presentationName || before.arrangementName != after.arrangementName {
            changes.append(.presentationChanged(name: after.presentationName))
        }

        if before.activeMessageName != after.activeMessageName || before.activeMessageText != after.activeMessageText {
            changes.append(.messageChanged(name: after.activeMessageName, text: after.activeMessageText))
        }

        let changedTimerNames = Set(before.timerStatesByName.keys)
            .union(after.timerStatesByName.keys)
            .filter { before.timerStatesByName[$0] != after.timerStatesByName[$0] }
            .sorted()
        for name in changedTimerNames {
            changes.append(.timerChanged(name: name, value: after.timerStatesByName[name]))
        }

        return changes
    }

    /// Attempts to interpret a ProPresenter timer's raw time string as a plain numeric
    /// value (e.g. "300" -> 300.0). Timer time strings from ProPresenter can also be
    /// formatted as HH:MM:SS depending on API/version, which this deliberately does NOT
    /// attempt to parse -- guessing at an ambiguous colon-separated format's meaning
    /// (elapsed vs. remaining, hours vs. not) risks silently returning a wrong number,
    /// which is worse than correctly returning nil for "not parseable as-is."
    static func parseNumericTimerValue(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        return Double(raw.trimmingCharacters(in: .whitespaces))
    }

    private struct PollBackoffState {
        var consecutiveTransportFailures: Int = 0
        var nextAllowedAttemptAt: Date? = nil
    }

    @Published private(set) var stateByModuleID: [UUID: State] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var pollingOwnerByModuleID: [UUID: UUID] = [:]
    private var pollBackoffBySourceKey: [String: PollBackoffState] = [:]

    // Keep the latest config per module so changes in the inspector apply immediately.
    private var latestConfigByModuleID: [UUID: ProPresenterModuleConfig] = [:]

    func setConfig(moduleID: UUID, config: ProPresenterModuleConfig) {
        latestConfigByModuleID[moduleID] = config
    }

    func startPolling(moduleID: UUID, config: ProPresenterModuleConfig, ownerID: UUID) {
        tasks[moduleID]?.cancel()
        tasks[moduleID] = nil
        pollingOwnerByModuleID[moduleID] = ownerID

        // Store the latest config (used by the polling loop).
        latestConfigByModuleID[moduleID] = config

        var s = stateByModuleID[moduleID] ?? State()
        s.isPolling = true
        var dict = stateByModuleID
        dict[moduleID] = s
        stateByModuleID = dict

        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let effectiveConfig = self.latestConfigByModuleID[moduleID] ?? config
                let sourceKey = self.sourceKey(for: effectiveConfig)
                let prePollCooldown = self.cooldownDelay(for: sourceKey)
                if prePollCooldown > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(prePollCooldown * 1_000_000_000))
                    continue
                }
                await self.tick(moduleID: moduleID, config: effectiveConfig)

                let interval = effectiveConfig.pollIntervalOverride
                    ?? UserDefaults.standard.object(forKey: "propresenter_pollInterval") as? Double
                    ?? 0.5

                let clamped = max(0.1, interval)
                let delay = self.nextPollDelay(baseInterval: clamped, sourceKey: sourceKey)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        tasks[moduleID] = task
    }

    func stopPolling(moduleID: UUID, ownerID: UUID? = nil) {
        if let ownerID,
           let currentOwner = pollingOwnerByModuleID[moduleID],
           currentOwner != ownerID {
            return
        }
        tasks[moduleID]?.cancel()
        tasks[moduleID] = nil
        pollingOwnerByModuleID[moduleID] = nil
        latestConfigByModuleID[moduleID] = nil
        if var s = stateByModuleID[moduleID] {
            s.isPolling = false
            var dict = stateByModuleID
            dict[moduleID] = s
            stateByModuleID = dict
        }
    }

    func stopAll() {
        for (id, t) in tasks {
            t.cancel()
            tasks[id] = nil
            pollingOwnerByModuleID[id] = nil
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ProPresenterService] \(message)")
        #endif
    }

    private func sourceKey(for config: ProPresenterModuleConfig) -> String {
        let connection = ProPresenterConnection(profileID: config.connectionProfileID)
        let profileDesc = config.connectionProfileID?.uuidString ?? "ACTIVE"
        return "\(profileDesc)|\(connection.settings.host):\(connection.settings.port)"
    }

    private func cooldownDelay(for sourceKey: String) -> TimeInterval {
        guard let nextAllowed = pollBackoffBySourceKey[sourceKey]?.nextAllowedAttemptAt else {
            return 0
        }
        return max(0, nextAllowed.timeIntervalSinceNow)
    }

    private func nextPollDelay(baseInterval: TimeInterval, sourceKey: String) -> TimeInterval {
        max(baseInterval, cooldownDelay(for: sourceKey))
    }

    private func resetPollBackoff(for sourceKey: String) {
        pollBackoffBySourceKey.removeValue(forKey: sourceKey)
    }

    private func recordTransportFailure(for sourceKey: String) {
        var state = pollBackoffBySourceKey[sourceKey] ?? PollBackoffState()
        state.consecutiveTransportFailures += 1

        let cooldownSchedule: [TimeInterval] = [2, 5, 10, 20, 30]
        let cooldownIndex = min(state.consecutiveTransportFailures - 1, cooldownSchedule.count - 1)
        state.nextAllowedAttemptAt = Date().addingTimeInterval(cooldownSchedule[cooldownIndex])
        pollBackoffBySourceKey[sourceKey] = state
    }

    private func resetStateForSourceChange(_ state: inout State, sourceKey: String) {
        let wasPolling = state.isPolling
        state = State()
        state.isPolling = wasPolling
        state.lastSourceKey = sourceKey
    }

    private func clearCachedPresentationState(_ state: inout State, isConnected: Bool) {
        state.status = ProPresenterSlideStatus(
            isConnected: isConnected,
            presentationName: nil,
            arrangementName: nil,
            slideText: nil,
            slideNotes: nil,
            slideIndex: nil,
            slideTotal: nil,
            slideLabel: state.status.slideLabel,
            slideUUID: nil,
            groupName: nil,
            groupColor: nil,
            nextSlideText: nil,
            nextSlideNotes: nil,
            nextSlideUUID: nil
        )
        state.lastPresentationRequest = nil
        state.lastPresentationJSONPreview = nil
        state.lastPresentationError = nil
        state.lastSlideTotal = nil
        state.lastSlideTotalUpdated = nil
        state.lastSlideTotalRequest = nil
        state.lastSlideTotalJSONPreview = nil
        state.lastSlideTotalError = nil
        state.lastAPISlideIndex = nil
        state.lastGroupName = nil
        state.lastGroupColor = nil
        state.lastGroupRanges = []
        state.lastGroupRangesUpdated = nil
        state.lastGroupSlideIndex = nil
        state.lastGroupSummary = nil
        state.lastPlaylistItemIndex = nil
        state.lastThumbnailCurrentIndex = nil
        state.lastThumbnailNextIndex = nil
        state.lastThumbnailPlaylistItemIndex = nil
        state.lastThumbnailQuality = nil
        state.lastThumbnailCurrentData = nil
        state.lastThumbnailNextData = nil
        state.lastTimers = []
        state.lastAudienceMessages = []
    }

    private func isTransportDisconnectError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
                 .callIsActive, .dataNotAllowed, .secureConnectionFailed:
                return true
            default:
                return false
            }
        }

        if let connectionError = error as? ProPresenterConnectionError {
            switch connectionError {
            case .notConnected:
                return true
            case .httpStatus, .decoding:
                return false
            }
        }

        return false
    }

    private func summarizeError(_ error: Error) -> String {
        if let connectionError = error as? ProPresenterConnectionError {
            switch connectionError {
            case .notConnected:
                return "Not connected to ProPresenter."
            case .httpStatus(let code, let body):
                let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmedBody.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(trimmedBody)"
            case .decoding(let body):
                let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmedBody.isEmpty ? "Response was not valid JSON." : "Response was not valid JSON: \(trimmedBody)"
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Timed out"
            case .cannotFindHost:
                return "Cannot find host"
            case .cannotConnectToHost:
                return "Cannot connect to host"
            case .networkConnectionLost:
                return "Network connection lost"
            case .notConnectedToInternet:
                return "Not connected to the internet"
            default:
                break
            }
        }

        return String(describing: error)
    }

    private func logDiagnosticError(_ message: String, key: String) {
        RelayDiagnosticsStore.shared.recordThrottledError(message, tag: "ProPresenter", key: key, minInterval: 60)
    }

    private func shouldTreatAsNoPresentation(error: Error) -> Bool {
        if let connError = error as? ProPresenterConnectionError {
            switch connError {
            case .httpStatus(let code, let body):
                let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (code == 400 || code == 404) && trimmed.isEmpty
            case .decoding(let body):
                let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty
            case .notConnected:
                return false
            }
        }
        return false
    }

    private func httpGetRaw(host: String, port: Int, path: String, password: String, accept: String = "application/json") async throws -> Data {
        let trimmedPath = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: "http://\(host):\(port)\(trimmedPath)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if !password.isEmpty {
            req.setValue(password, forHTTPHeaderField: "X-ProPresenter-Password")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func tryDecodeJSONValue(_ data: Data) -> JSONValue? {
        // Some endpoints appear to return plain text (not JSON) depending on ProPresenter version/config.
        // If it's JSON, decode it; otherwise return nil.
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func decodeToStringFallback(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func fetchActivePresentationName(host: String, port: Int, password: String) async -> (name: String?, debugPath: String, debugPreview: String, debugError: String?, slideTotal: Int?) {
        // Try a few known/likely endpoints across versions.
        let candidates = [
            "/v1/presentation/active?chunked=false",
            "/v1/status/presentation",
            "/v1/presentation/current?chunked=false",
            "/v1/presentation/focused?chunked=false"
        ]

        var lastPath: String = candidates.first ?? "/v1/presentation/active?chunked=false"
        var lastPreview: String = ""
        var lastErr: String? = nil
        var lastTotal: Int? = nil

        for path in candidates {
            lastPath = path
            do {
                let data = try await httpGetRaw(host: host, port: port, path: path, password: password)

                if let json = tryDecodeJSONValue(data) {
                    let preview = json.debugCompactString(maxLength: 1200)
                    lastPreview = preview

                    // Deliberately NOT reading an index here: `presentation.id.index` (and the bare
                    // `index` on /presentation/focused) is the playlist position, not the slide.
                    // See fetchCurrentSlideIndex.
                    if let total = json["count"]?.asInt() ?? json["total"]?.asInt() ?? json["slideCount"]?.asInt() {
                        lastTotal = total
                    }

                    if let name = Self.extractPresentationName(from: json) {
                        return (name, path, preview, nil, lastTotal)
                    }

                    // No title here—record and continue trying other endpoints.
                    lastErr = "No title key matched"
                    continue
                } else {
                    // Non-JSON response (common: UUID or empty). Keep it for debugging.
                    let text = decodeToStringFallback(data)
                    let preview = text.count > 500 ? String(text.prefix(500)) + "…" : text
                    lastPreview = preview

                    // If this is a quoted JSON string, we can still treat it as a name.
                    if text.hasPrefix("\"") && text.hasSuffix("\"") {
                        let unquoted = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        if !unquoted.isEmpty {
                            return (unquoted, path, preview, nil, lastTotal)
                        }
                    }

                    // If it *looks* like a name directly, use it.
                    if !text.isEmpty,
                       text.range(of: "^[A-Za-z0-9].*", options: .regularExpression) != nil,
                       text.count < 120 {
                        return (text, path, preview, nil, lastTotal)
                    }

                    lastErr = text.isEmpty ? "Empty response" : "Non-JSON response"
                    continue
                }
            } catch {
                // Record and try next candidate.
                lastErr = summarizeError(error)
                continue
            }
        }

        return (nil, lastPath, lastPreview, lastErr ?? "Unable to decode presentation name", lastTotal)
    }

    private func fetchActivePresentationSlideTotal(host: String, port: Int, password: String, slideIndex: Int?, slideUUID: String?, slideText: String?, slideLabel: String?) async -> (total: Int?, groupName: String?, groupColor: CodableColor?, groupRanges: [ProPresenterGroupRange], debugPath: String, debugPreview: String, debugError: String?) {
        let candidates = [
            "/v1/presentation/active?chunked=false",
            "/v1/presentation/active/slides?chunked=false",
            "/v1/presentation/active/slide?chunked=false"
        ]

        var lastPath: String = candidates.first ?? "/v1/presentation/active?chunked=false"
        var lastPreview: String = ""
        var lastErr: String? = nil
        var lastGroupName: String? = nil
        var lastGroupColor: CodableColor? = nil
        var lastGroupRanges: [ProPresenterGroupRange] = []
        func firstInt(in value: JSONValue?, keys: [String]) -> Int? {
            guard let value else { return nil }
            for key in keys {
                if let number = value[key]?.asInt() {
                    return number
                }
            }
            return nil
        }

        func arrayCount(_ value: JSONValue?) -> Int? {
            guard let value else { return nil }
            if case .array(let arr) = value { return arr.count }
            return nil
        }

        func groupsSlideCount(in value: JSONValue?) -> Int? {
            guard case .array(let groups) = value else { return nil }
            var total = 0
            var found = false
            for group in groups {
                guard case .object(let obj) = group else { continue }
                if case .array(let slides) = obj["slides"] {
                    total += slides.count
                    found = true
                }
            }
            return found ? total : nil
        }

        func doubleValue(_ value: JSONValue?) -> Double? {
            guard let value else { return nil }
            switch value {
            case .number(let n):
                return n
            case .string(let s):
                return Double(s)
            default:
                return nil
            }
        }

        func normalizeSlideText(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            return parts.joined(separator: " ").lowercased()
        }

        func normalizedColorComponent(_ value: Double?) -> Double? {
            guard let value, value.isFinite else { return nil }
            if value > 1 {
                return min(max(value / 255.0, 0), 1)
            }
            return min(max(value, 0), 1)
        }

        func colorFromHexString(_ raw: String) -> CodableColor? {
            let hex = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard [6, 8].contains(hex.count), let value = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 6 {
                let red = Double((value >> 16) & 0xFF) / 255.0
                let green = Double((value >> 8) & 0xFF) / 255.0
                let blue = Double(value & 0xFF) / 255.0
                return CodableColor(red: red, green: green, blue: blue, alpha: 1)
            }
            let red = Double((value >> 24) & 0xFF) / 255.0
            let green = Double((value >> 16) & 0xFF) / 255.0
            let blue = Double((value >> 8) & 0xFF) / 255.0
            let alpha = Double(value & 0xFF) / 255.0
            return CodableColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        func parseGroupColor(from value: JSONValue?) -> CodableColor? {
            guard let value else { return nil }

            if let string = value.asString(), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let parsed = colorFromHexString(string) {
                    return parsed
                }
            }

            if case .array(let array) = value {
                let components = array.compactMap(doubleValue)
                guard components.count >= 3 else { return nil }
                let red = normalizedColorComponent(components[0]) ?? 0
                let green = normalizedColorComponent(components[1]) ?? 0
                let blue = normalizedColorComponent(components[2]) ?? 0
                let alpha = normalizedColorComponent(components.count >= 4 ? components[3] : 1) ?? 1
                return CodableColor(red: red, green: green, blue: blue, alpha: alpha)
            }

            guard case .object(let colorObj) = value else { return nil }

            if let hex = colorObj["hex"]?.asString()
                ?? colorObj["hexString"]?.asString()
                ?? colorObj["rgbHex"]?.asString() {
                if let parsed = colorFromHexString(hex) {
                    return parsed
                }
            }

            let red = normalizedColorComponent(
                doubleValue(colorObj["red"])
                ?? doubleValue(colorObj["r"])
                ?? doubleValue(colorObj["srgbRed"])
            )
            let green = normalizedColorComponent(
                doubleValue(colorObj["green"])
                ?? doubleValue(colorObj["g"])
                ?? doubleValue(colorObj["srgbGreen"])
            )
            let blue = normalizedColorComponent(
                doubleValue(colorObj["blue"])
                ?? doubleValue(colorObj["b"])
                ?? doubleValue(colorObj["srgbBlue"])
            )
            let alpha = normalizedColorComponent(
                doubleValue(colorObj["alpha"])
                ?? doubleValue(colorObj["a"])
                ?? doubleValue(colorObj["opacity"])
                ?? 1
            ) ?? 1

            guard let red, let green, let blue else { return nil }
            return CodableColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        func slideTokens(from text: String?, label: String?) -> [String] {
            var tokens: [String] = []
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tokens.append(normalizeSlideText(text))
            }
            if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tokens.append(normalizeSlideText(label))
            }
            return tokens
        }

        func rangeMatches(tokens: [String], ranges: [ProPresenterGroupRange]) -> Bool {
            guard !tokens.isEmpty else { return false }
            for range in ranges {
                for slideText in range.slideTexts {
                    let normalized = normalizeSlideText(slideText)
                    for token in tokens {
                        if normalized == token || normalized.contains(token) || token.contains(normalized) {
                            return true
                        }
                    }
                }
            }
            return false
        }

        func extractGroupInfo(from groupsValue: JSONValue?, slideIndex: Int?) -> (name: String?, color: CodableColor?, ranges: [ProPresenterGroupRange]) {
            guard case .array(let groups) = groupsValue else { return (nil, nil, []) }

            var runningIndex = 0
            var ranges: [ProPresenterGroupRange] = []
            var matchedName: String? = nil
            var matchedColor: CodableColor? = nil
            func slideText(from value: JSONValue) -> String? {
                guard case .object(let obj) = value else { return nil }
                let candidates = [
                    obj["text"]?.asString(),
                    obj["content"]?.asString(),
                    obj["label"]?.asString(),
                    obj["notes"]?.asString()
                ]
                for candidate in candidates {
                    if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return candidate
                    }
                }
                return nil
            }

            func slideUUID(from value: JSONValue) -> String? {
                // Delegates to extractSlideUUID so the groups-endpoint parser and the
                // status/slide-endpoint parser can never drift out of sync again — they
                // previously duplicated the candidate list, and this copy was missing the
                // `uuid: {uuid, name}` nesting the other one handled, which meant every
                // group's slideUUIDs came back empty for that payload shape. That silently
                // broke the direct UUID match and pushed blank-slide resolution onto the
                // fragile next-slide-text fallback below.
                extractSlideUUID(from: value)
            }
            for group in groups {
                guard case .object(let obj) = group else { continue }
                let name = obj["name"]?.asString()
                    ?? obj["label"]?.asString()
                    ?? obj["title"]?.asString()
                let slides: [JSONValue] = {
                    guard case .array(let slides) = obj["slides"] else { return [] }
                    // slide_index counts disabled slides too (confirmed live: a 71-slide song with
                    // 5 disabled slides reported indexes above 66), so keep them in the ranges.
                    return slides
                }()
                let slidesCount = slides.count
                if slidesCount > 0 {
                    let rangeStart = runningIndex + 1
                    let rangeEnd = runningIndex + slidesCount
                    let colorValue = parseGroupColor(from: obj["color"] ?? obj["groupColor"] ?? obj["colorInfo"])
                    let slideTexts = slides.compactMap { slideText(from: $0) }
                    let slideUUIDs = slides.compactMap { slideUUID(from: $0) }
                    ranges.append(.init(start: rangeStart, end: rangeEnd, name: name, color: colorValue, slideTexts: slideTexts, slideUUIDs: slideUUIDs))
                    if let slideIndex, slideIndex >= rangeStart && slideIndex <= rangeEnd, matchedName == nil {
                        matchedName = name
                        matchedColor = colorValue
                    }
                    runningIndex += slidesCount
                }
            }
            return (matchedName, matchedColor, ranges)
        }

        func extractTotal(from json: JSONValue) -> Int? {
            let totalKeys = [
                "slideCount",
                "slide_count",
                "slidesCount",
                "slides_count",
                "slideTotal",
                "slide_total",
                "totalSlides",
                "total_slides",
                "count",
                "total",
                "size",
                "length"
            ]

            if let count = firstInt(in: json, keys: totalKeys) { return count }
            if let count = firstInt(in: json["presentation"], keys: totalKeys) { return count }
            if let count = firstInt(in: json["data"], keys: totalKeys) { return count }

            if let count = arrayCount(json["slides"]) { return count }
            if let count = arrayCount(json["presentation"]?["slides"]) { return count }
            if let count = arrayCount(json["data"]?["slides"]) { return count }
            if let count = arrayCount(json["items"]) { return count }

            if let count = groupsSlideCount(in: json["presentation"]?["groups"]) { return count }
            if let count = groupsSlideCount(in: json["groups"]) { return count }

            if case .array(let arr) = json { return arr.count }
            return nil
        }

        for path in candidates {
            lastPath = path
            do {
                let data = try await httpGetRaw(host: host, port: port, path: path, password: password)

                if let json = tryDecodeJSONValue(data) {
                    let preview = json.debugCompactString(maxLength: 500)
                    lastPreview = preview

                    // ProPresenter's REST API has no arrangement endpoints, and `groups` already
                    // reflects the presentation's slide order, so use it directly.
                    let groupsValue = json["presentation"]?["groups"] ?? json["groups"]

                    #if DEBUG
                    if case .array(let dbgGroups) = groupsValue {
                        var rawCount = 0, enabledCount = 0
                        for g in dbgGroups {
                            guard case .array(let sl) = g["slides"] else { continue }
                            rawCount += sl.count
                            enabledCount += sl.filter { if case .bool(false)? = $0["enabled"] { return false }; return true }.count
                        }
                        print("[ProPresenterService][slide-debug] groups=\(dbgGroups.count) rawSlides=\(rawCount) enabledSlides=\(enabledCount) names=\(dbgGroups.map { $0["name"]?.asString() ?? "?" })")
                    }
                    #endif
                    let groupInfo = extractGroupInfo(
                        from: groupsValue,
                        slideIndex: slideIndex
                    )
                    lastGroupName = groupInfo.name
                    lastGroupColor = groupInfo.color
                    lastGroupRanges = groupInfo.ranges

                    if let total = groupsSlideCount(in: groupsValue) {
                        return (total, lastGroupName, lastGroupColor, lastGroupRanges, path, preview, nil)
                    }

                    if let total = extractTotal(from: json) {
                        return (total, lastGroupName, lastGroupColor, lastGroupRanges, path, preview, nil)
                    }

                    lastErr = "No slide count matched"
                    continue
                } else {
                    let text = decodeToStringFallback(data)
                    let preview = text.count > 500 ? String(text.prefix(500)) + "…" : text
                    lastPreview = preview
                    lastErr = text.isEmpty ? "Empty response" : "Non-JSON response"
                    continue
                }
            } catch {
                lastErr = summarizeError(error)
                continue
            }
        }

        return (nil, lastGroupName, lastGroupColor, lastGroupRanges, lastPath, lastPreview, lastErr ?? "Unable to decode slide total")
    }

    private func extractPlaylistItemIndex(from json: JSONValue) -> Int? {
        let candidates: [JSONValue?] = [
            json["presentation"]?["playlist_item"]?["id"],
            json["presentation"]?["playlist_item"],
            json["playlist_item"]?["id"],
            json["playlist_item"],
            json["presentation"]?["item"],
            json["item"],
            json["presentation"]
        ]
        for candidate in candidates {
            if let index = candidate?["index"]?.asInt() {
                return index
            }
        }
        return nil
    }

    private func fetchActivePlaylistItemIndex(
        host: String,
        port: Int,
        password: String
    ) async -> (index: Int?, debugPath: String, debugPreview: String, debugError: String?) {
        let path = "/v1/playlist/active"
        do {
            let data = try await httpGetRaw(host: host, port: port, path: path, password: password)
            if let json = tryDecodeJSONValue(data) {
                let preview = json.debugCompactString(maxLength: 400)
                let index = extractPlaylistItemIndex(from: json)
                return (index, path, preview, nil)
            }
            let text = decodeToStringFallback(data)
            let preview = text.count > 400 ? String(text.prefix(400)) + "…" : text
            return (nil, path, preview, text.isEmpty ? "Empty response" : "Non-JSON response")
        } catch {
            return (nil, path, "", summarizeError(error))
        }
    }

    private func fetchSlideThumbnail(
        host: String,
        port: Int,
        password: String,
        playlistItemIndex: Int,
        slideIndex: Int,
        quality: Int
    ) async -> Data? {
        let path = "/v1/playlist/active/presentation/\(playlistItemIndex)/thumbnail/\(slideIndex)?quality=\(quality)"
        return try? await httpGetRaw(
            host: host,
            port: port,
            path: path,
            password: password,
            accept: "image/*"
        )
    }

    private func summarizeGroupRanges(_ ranges: [ProPresenterGroupRange]) -> String {
        guard !ranges.isEmpty else { return "" }
        let parts = ranges.map { range in
            let name = range.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : "Untitled"
            return "\(range.start)-\(range.end) \(resolvedName)"
        }
        let joined = parts.joined(separator: " | ")
        if joined.count <= 300 { return joined }
        return String(joined.prefix(300)) + "…"
    }

    enum ProPresenterSlideIdentity {
        // Decides whether cached group ranges/name need refetching sooner (0.5s cadence)
        // rather than on the slow (5s) cadence. Callers must pass `currentRawIndex` from
        // data fetched THIS cycle (e.g. the just-fetched presentation index) -- comparing
        // against a value snapshotted at the end of the previous cycle makes this always
        // agree with `lastMatchedRawIndex` (both were set together back then), which silently
        // defeats the fast path and leaves the group label stale until the slow cadence
        // eventually catches up.
        static func shouldRefreshGroupsSoon(
            hasRanges: Bool,
            lastMatchedRawIndex: Int?,
            currentRawIndex: Int?,
            timeRefreshDue: Bool
        ) -> Bool {
            if !hasRanges { return true }
            if timeRefreshDue { return true }
            return lastMatchedRawIndex != currentRawIndex
        }

        static func resolvedCurrentSlideIndex(
            currentSlideIndex: Int?,
            currentSlideText: String?,
            preferredDisplayIndex: Int?,
            ranges: [ProPresenterGroupRange]
        ) -> Int? {
            if let currentSlideIndex {
                return currentSlideIndex
            }

            guard let currentSlideText else { return nil }
            let normalizedText = normalizeSlideText(currentSlideText)
            guard !normalizedText.isEmpty,
                  let match = bestExactTextMatch(
                    for: normalizedText,
                    in: ranges,
                    preferredDisplayIndex: preferredDisplayIndex
                  ) else {
                return nil
            }
            return match.displayIndex - 1
        }

        static func resolvedBlankCurrentSlideIndex(
            currentSlideIndex: Int?,
            nextSlideText: String?,
            preferredDisplayIndex: Int?,
            ranges: [ProPresenterGroupRange]
        ) -> Int? {
            if let currentSlideIndex {
                return currentSlideIndex
            }

            guard let nextSlideText else { return nil }
            let normalizedNextText = normalizeSlideText(nextSlideText)
            guard !normalizedNextText.isEmpty,
                  let nextMatch = bestExactTextMatch(
                    for: normalizedNextText,
                    in: ranges,
                    preferredDisplayIndex: preferredDisplayIndex.map { $0 + 1 }
                  ),
                  nextMatch.displayIndex > 1 else {
                return nil
            }

            return nextMatch.displayIndex - 2
        }

        static func bestExactTextMatch(
            for normalizedText: String,
            in ranges: [ProPresenterGroupRange],
            preferredDisplayIndex: Int?
        ) -> (range: ProPresenterGroupRange, offset: Int, displayIndex: Int)? {
            let matches = exactTextMatches(for: normalizedText, in: ranges)
            guard !matches.isEmpty else { return nil }
            if matches.count == 1 {
                return matches[0]
            }

            guard let preferredDisplayIndex else { return nil }
            let sorted = matches.sorted {
                let lhsDistance = abs($0.displayIndex - preferredDisplayIndex)
                let rhsDistance = abs($1.displayIndex - preferredDisplayIndex)
                if lhsDistance == rhsDistance {
                    return $0.displayIndex < $1.displayIndex
                }
                return lhsDistance < rhsDistance
            }
            guard let best = sorted.first else { return nil }
            let bestDistance = abs(best.displayIndex - preferredDisplayIndex)
            let secondDistance = sorted.dropFirst().first.map { abs($0.displayIndex - preferredDisplayIndex) }
            guard bestDistance <= 1 else { return nil }
            if let secondDistance, secondDistance == bestDistance {
                return nil
            }
            return best
        }

        private static func exactTextMatches(
            for normalizedText: String,
            in ranges: [ProPresenterGroupRange]
        ) -> [(range: ProPresenterGroupRange, offset: Int, displayIndex: Int)] {
            guard !normalizedText.isEmpty else { return [] }
            var matches: [(range: ProPresenterGroupRange, offset: Int, displayIndex: Int)] = []
            for range in ranges {
                for (offset, text) in range.slideTexts.enumerated() where normalizeSlideText(text) == normalizedText {
                    matches.append((range, offset, range.start + offset))
                }
            }
            return matches
        }

        private static func normalizeSlideText(_ text: String) -> String {
            let lowered = text.lowercased()
            let spaced = lowered
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
            let parts = spaced.split(whereSeparator: { $0.isWhitespace })
            return parts.joined(separator: " ")
        }
    }

    private func tick(moduleID: UUID, config: ProPresenterModuleConfig) async {
        guard let selectedProfileID = config.connectionProfileID else {
            var state = stateByModuleID[moduleID] ?? State()
            clearCachedPresentationState(&state, isConnected: false)
            state.lastError = "No ProPresenter profile selected"
            state.lastUpdated = Date()
            state.lastResponseSummary = "ERROR: No ProPresenter profile selected"
            var dict = stateByModuleID
            dict[moduleID] = state
            stateByModuleID = dict
            return
        }

        guard ProPresenterProfilesStore.loadProfile(id: selectedProfileID) != nil else {
            var state = stateByModuleID[moduleID] ?? State()
            clearCachedPresentationState(&state, isConnected: false)
            state.lastError = "Selected ProPresenter profile is unavailable"
            state.lastUpdated = Date()
            state.lastResponseSummary = "ERROR: Selected ProPresenter profile is unavailable"
            var dict = stateByModuleID
            dict[moduleID] = state
            stateByModuleID = dict
            return
        }

        let currentSourceKey = sourceKey(for: config)
        do {
            let conn = ProPresenterConnection(profileID: config.connectionProfileID)

            // Best-effort pull connection info for logging
            let host = conn.settings.host
            let port = conn.settings.port
            let password = conn.settings.password
            let profileDesc = config.connectionProfileID?.uuidString ?? "ACTIVE"
            let path = config.dataMode.requestPath(messageTarget: config.messageTarget)
            let previousError = stateByModuleID[moduleID]?.lastError
            let beforeChangeSnapshot = Self.changeSnapshot(from: stateByModuleID[moduleID] ?? State())
            var s = stateByModuleID[moduleID] ?? State()
            if s.lastSourceKey != currentSourceKey {
                resetStateForSourceChange(&s, sourceKey: currentSourceKey)
            }
            s.lastRequestDescription = "\(host):\(port)  \(path)  [profile: \(profileDesc)]"
            var dict0 = stateByModuleID
            dict0[moduleID] = s
            stateByModuleID = dict0

            debugLog("Requesting \(s.lastRequestDescription ?? "")")

            func parseAudienceMessages(from value: JSONValue) -> [AudienceMessageOption] {
                let normalizedValue = value.decodedJSONValueIfJSONString() ?? value
                let arr: [JSONValue]
                if case .array(let direct) = normalizedValue {
                    arr = direct
                } else if case .object(let obj) = normalizedValue,
                          case .array(let nested) = obj["messages"] {
                    arr = nested
                } else {
                    return []
                }
                func truthy(_ value: JSONValue?) -> Bool {
                    guard let value else { return false }
                    switch value {
                    case .bool(let b):
                        return b
                    case .string(let s):
                        return s.lowercased() == "true" || s == "1"
                    case .number(let n):
                        return n != 0
                    default:
                        return false
                    }
                }
                var options: [AudienceMessageOption] = []
                for item in arr {
                    guard case .object(let obj) = item else { continue }
                    let idValue = obj["id"]
                    var id = ""
                    var name = ""
                    if case .object(let idObj) = idValue {
                        id = idObj["uuid"]?.asString()
                            ?? idObj["name"]?.asString()
                            ?? ""
                        name = idObj["name"]?.asString()
                            ?? idObj["uuid"]?.asString()
                            ?? "Message"
                    } else if let directID = obj["uuid"]?.asString() ?? obj["id"]?.asString() {
                        id = directID
                        name = obj["name"]?.asString() ?? directID
                    }
                    let raw = obj["message"]?.asString() ?? ""
                    let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isActive = truthy(obj["is_active"])
                    let isVisible = obj["visible_on_network"].map(truthy) ?? true
                    if id.isEmpty { continue }
                    options.append(
                        AudienceMessageOption(
                            id: id,
                            name: name.isEmpty ? "Message" : name,
                            message: message,
                            isActive: isActive,
                            isVisible: isVisible
                        )
                    )
                }
                return options
            }

            func extractMessageText(from value: JSONValue) -> String? {
                let normalizedValue = value.decodedJSONValueIfJSONString() ?? value
                func firstString(in value: JSONValue?, keys: [String]) -> String? {
                    guard let value else { return nil }
                    for key in keys {
                        if let string = value[key]?.asString() {
                            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty || trimmed == "null" { continue }
                            return trimmed
                        }
                    }
                    return nil
                }

                func messageFromArray(_ arr: [JSONValue]) -> String? {
                    func truthy(_ value: JSONValue?) -> Bool {
                        guard let value else { return false }
                        switch value {
                        case .bool(let b):
                            return b
                        case .string(let s):
                            return s.lowercased() == "true" || s == "1"
                        case .number(let n):
                            return n != 0
                        default:
                            return false
                        }
                    }
                    func messageFromObject(_ obj: [String: JSONValue]) -> String? {
                        if let raw = obj["message"]?.asString() {
                            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && trimmed != "null" { return trimmed }
                        }
                        return nil
                    }

                    // Prefer active message
                    for item in arr {
                        if case .object(let obj) = item,
                           truthy(obj["is_active"]),
                           let msg = messageFromObject(obj) {
                            return msg
                        }
                    }

                    // Fallback to first non-empty message
                    for item in arr {
                        if case .object(let obj) = item,
                           let msg = messageFromObject(obj) {
                            return msg
                        }
                    }
                    return nil
                }

                if case .array(let arr) = normalizedValue, let msg = messageFromArray(arr) {
                    return msg
                }

                if let raw = normalizedValue.asString() {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed != "null" {
                        return trimmed
                    }
                }

                return firstString(in: normalizedValue, keys: ["message", "text", "value", "content"])
                    ?? firstString(in: normalizedValue["data"], keys: ["message", "text", "value", "content"])
                    ?? firstString(in: normalizedValue["message"], keys: ["message", "text", "value", "content"])
                    ?? firstString(in: normalizedValue["stage"], keys: ["message", "text", "value", "content"])
                    ?? firstString(in: normalizedValue["stageMessage"], keys: ["message", "text", "value", "content"])
                    ?? firstString(in: normalizedValue["current"], keys: ["message", "text", "value", "content"])
            }

            let (json, usedPath, audienceOptions): (JSONValue, String, [AudienceMessageOption]) = try await {
                guard config.dataMode == .stageMessage, config.messageTarget == .audience else {
                    let direct = try await conn.request(path, method: "GET") as JSONValue
                    return (direct, path, [])
                }

                let candidatePaths = [
                    "/v1/messages",
                    "/v1/message",
                    "/v1/message/active",
                    "/v1/audience/message"
                ]

                var lastJSON: JSONValue = .null
                var lastPath = path
                var lastOptions: [AudienceMessageOption] = []

                if let listJSON = try? await conn.request("/v1/messages", method: "GET") as JSONValue {
                    lastOptions = parseAudienceMessages(from: listJSON)
                    lastJSON = listJSON
                    lastPath = "/v1/messages"
                    if lastOptions.contains(where: { $0.isActive && !$0.message.isEmpty }) {
                        return (listJSON, "/v1/messages", lastOptions)
                    }
                }

                for candidate in candidatePaths {
                    if let candidateJSON = try? await conn.request(candidate, method: "GET") as JSONValue {
                        lastJSON = candidateJSON
                        lastPath = candidate
                        if lastOptions.isEmpty {
                            lastOptions = parseAudienceMessages(from: candidateJSON)
                        }
                        if let text = extractMessageText(from: candidateJSON),
                           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return (candidateJSON, candidate, lastOptions)
                        }
                    }
                }
                return (lastJSON, lastPath, lastOptions)
            }()

            s.lastRequestDescription = "\(host):\(port)  \(usedPath)  [profile: \(profileDesc)]"
            var dict0b = stateByModuleID
            s.lastAudienceMessages = audienceOptions
            dict0b[moduleID] = s
            stateByModuleID = dict0b

            let jsonPreview = json.debugCompactString(maxLength: 700)
            // Timers: keep a structured copy for UI pickers.
            if config.dataMode == .timersCurrent {
                let timers = parseTimers(from: json)
                var sTimers = self.stateByModuleID[moduleID] ?? State()
                sTimers.lastTimers = timers
                var dTimers = self.stateByModuleID
                dTimers[moduleID] = sTimers
                self.stateByModuleID = dTimers
            } else {
                if var sTimers = self.stateByModuleID[moduleID], !sTimers.lastTimers.isEmpty {
                    sTimers.lastTimers = []
                    var dTimers = self.stateByModuleID
                    dTimers[moduleID] = sTimers
                    self.stateByModuleID = dTimers
                }
            }
            // For slide modes, also fetch the active presentation so we can display its name in the header.
            // Some ProPresenter versions return non-JSON for certain endpoints, so we use a raw fetch with fallbacks.
            var activePresentationName: String? = nil
            var currentSlideIndex: Int? = nil
            var presentationTotal: Int? = nil
            var presentationGroupName: String? = nil
            var presentationGroupColor: CodableColor? = nil
            let shouldUseGroupInfo = config.showGroupName || config.showGroupColor || config.showSlideNumbers
            if config.dataMode.isSlideMode {
                let (name, usedPath, preview, err, resolvedTotal) = await fetchActivePresentationName(
                    host: host,
                    port: port,
                    password: password
                )
                activePresentationName = name
                presentationTotal = resolvedTotal
                // Authoritative 0-based slide position (nil if unsupported or nothing is live).
                currentSlideIndex = await fetchCurrentSlideIndex(host: host, port: port, password: password)

                // Some ProPresenter arrangement payloads report a slide index in the
                // source song's full sequence while the active presentation exposes only
                // the selected arrangement's slides. Keep the displayed position within
                // the active presentation's reported range (for example 42 of 21 -> 21 of 21).
                if let index = currentSlideIndex, let total = presentationTotal, total > 0, index >= total {
                    currentSlideIndex = index % total
                }

                var sPres = self.stateByModuleID[moduleID] ?? State()
                if sPres.status.presentationName != activePresentationName {
                    sPres.lastSlideTotal = nil
                    sPres.lastSlideTotalUpdated = nil
                    sPres.lastAPISlideIndex = nil
                    sPres.lastGroupName = nil
                    sPres.lastGroupColor = nil
                    sPres.lastGroupRanges = []
                    sPres.lastGroupRangesUpdated = nil
                    sPres.lastGroupSlideIndex = nil
                    sPres.lastGroupSummary = nil
                }
                sPres.lastPresentationRequest = "\(host):\(port)  \(usedPath)  [profile: \(profileDesc)]"
                sPres.lastPresentationJSONPreview = preview.isEmpty ? nil : preview
                sPres.lastPresentationError = err

                sPres.lastAPISlideIndex = currentSlideIndex

                if presentationGroupName == nil {
                    presentationGroupName = sPres.lastGroupName
                    presentationGroupColor = sPres.lastGroupColor
                }

                let now = Date()
                let lastFetch = sPres.lastSlideTotalUpdated ?? .distantPast
                let timeRefreshDue = now.timeIntervalSince(lastFetch) > 2
                let shouldRefreshGroups = shouldUseGroupInfo
                    && ProPresenterSlideIdentity.shouldRefreshGroupsSoon(
                        hasRanges: !sPres.lastGroupRanges.isEmpty,
                        lastMatchedRawIndex: sPres.lastGroupSlideIndex,
                        currentRawIndex: currentSlideIndex,
                        timeRefreshDue: timeRefreshDue
                    )
                if presentationTotal == nil || presentationGroupName == nil || presentationGroupColor == nil || shouldRefreshGroups {
                    if let cached = sPres.lastSlideTotal {
                        presentationTotal = presentationTotal ?? cached
                    }

                    let refreshInterval: TimeInterval = shouldRefreshGroups ? 0.5 : 5
                    if now.timeIntervalSince(lastFetch) > refreshInterval {
                        let displayIndex = currentSlideIndex.map { $0 + 1 }
                        let (total, groupName, groupColor, groupRanges, totalPath, totalPreview, totalErr) = await fetchActivePresentationSlideTotal(
                            host: host,
                            port: port,
                            password: password,
                            slideIndex: displayIndex,
                            slideUUID: sPres.status.slideUUID,
                            slideText: sPres.status.slideText,
                            slideLabel: sPres.status.slideLabel
                        )
                        sPres.lastSlideTotalRequest = "\(host):\(port)  \(totalPath)  [profile: \(profileDesc)]"
                        sPres.lastSlideTotalJSONPreview = totalPreview.isEmpty ? nil : totalPreview
                        sPres.lastSlideTotalError = totalErr
                        if let total {
                            presentationTotal = total
                            sPres.lastSlideTotal = total
                            sPres.lastSlideTotalUpdated = now
                        }
                        if let groupName {
                            presentationGroupName = groupName
                            sPres.lastGroupName = groupName
                        }
                        if let groupColor {
                            presentationGroupColor = groupColor
                            sPres.lastGroupColor = groupColor
                        }
                        if !groupRanges.isEmpty {
                            sPres.lastGroupRanges = groupRanges
                            sPres.lastGroupRangesUpdated = now
                            sPres.lastGroupSummary = summarizeGroupRanges(groupRanges)
                        } else {
                            sPres.lastGroupSummary = nil
                        }
                        if let totalErr, !totalErr.isEmpty {
                            self.debugLog("Slide total fetch note: \(totalErr)")
                        }
                        if !totalPreview.isEmpty {
                            self.debugLog("Slide total preview (\(totalPath)): \(totalPreview)")
                        }
                    }
                }

                var dPres = self.stateByModuleID
                dPres[moduleID] = sPres
                self.stateByModuleID = dPres

                if let err, !err.isEmpty {
                    self.debugLog("Active presentation fetch note: \(err)")
                }
                if !preview.isEmpty {
                    self.debugLog("Active presentation preview (\(usedPath)): \(preview)")
                }
            }

            var normalized = normalize(json: json, mode: config.dataMode, presentationName: activePresentationName)

            if normalized.slideTotal == nil, let presentationTotal {
                normalized.slideTotal = presentationTotal
            }
            if shouldUseGroupInfo, let presentationGroupName {
                normalized.groupName = presentationGroupName
            }
            if shouldUseGroupInfo, let presentationGroupColor {
                normalized.groupColor = presentationGroupColor
            }
            if config.dataMode == .stageMessage, config.messageTarget == .audience {
                if let active = audienceOptions.first(where: { $0.isActive && $0.isVisible && !$0.message.isEmpty }) {
                    normalized.slideText = active.message
                } else {
                    normalized.slideText = nil
                }
            }

            let latestStateForGroup = (stateByModuleID[moduleID] ?? State())
            let groupRangesForMatch = latestStateForGroup.lastGroupRanges
            var matchedGroupSlideIndex: Int? = nil
            // ProPresenter's slide_index is authoritative, so no text/UUID guessing is needed when
            // we have it. The inference below is only a fallback for servers without that endpoint.
            let preferredDisplayIndex = latestStateForGroup.lastGroupSlideIndex.map { $0 + 1 }
            if let currentSlideIndex {
                normalized.slideIndex = currentSlideIndex
                if shouldUseGroupInfo,
                   let match = groupRangesForMatch.first(where: { currentSlideIndex + 1 >= $0.start && currentSlideIndex + 1 <= $0.end }) {
                    normalized.groupName = match.name
                    normalized.groupColor = match.color
                    matchedGroupSlideIndex = currentSlideIndex
                }
            }

            if currentSlideIndex == nil,
               !groupRangesForMatch.isEmpty,
               let slideUUID = normalized.slideUUID,
               !slideUUID.isEmpty,
               let match = groupRangesForMatch.first(where: { $0.slideUUIDs.contains(slideUUID) }),
               let uuidOffset = match.slideUUIDs.firstIndex(of: slideUUID) {
                // UUID uniquely identifies the slide's exact position within its group — use it
                // to set slideIndex even when slideText is blank. This is far more reliable than
                // the text-matching fallback below, which breaks on repeated/duplicate slide text
                // and non-linear navigation. Range `start` is a 1-based display index; slideIndex
                // is stored 0-based (see displayIndex(for:) in the UI layer).
                let uuidDisplayIndex = match.start + uuidOffset
                let uuidRawIndex = uuidDisplayIndex - 1
                normalized.slideIndex = uuidRawIndex
                matchedGroupSlideIndex = uuidRawIndex
                if shouldUseGroupInfo {
                    normalized.groupName = match.name
                    normalized.groupColor = match.color
                }
            }

            let shouldInferSlideIndex = config.dataMode.isSlideMode && (config.showSlideNumbers || config.showGroupName || config.showGroupColor)

            if shouldInferSlideIndex,
               currentSlideIndex == nil,
               !groupRangesForMatch.isEmpty,
               let resolvedIndex = ProPresenterSlideIdentity.resolvedCurrentSlideIndex(
                currentSlideIndex: normalized.slideIndex,
                currentSlideText: normalized.slideText,
                preferredDisplayIndex: preferredDisplayIndex,
                ranges: groupRangesForMatch
               ) {
                normalized.slideIndex = resolvedIndex
                let displayIndex = resolvedIndex + 1
                if config.showGroupName || config.showGroupColor,
                   let match = groupRangesForMatch.first(where: { displayIndex >= $0.start && displayIndex <= $0.end }) {
                    matchedGroupSlideIndex = resolvedIndex
                    if normalized.groupName != match.name || normalized.groupColor != match.color {
                        normalized.groupName = match.name
                        normalized.groupColor = match.color
                    }
                }
            }

            // Fallback: infer blank-slide position from the next slide's text only when neither
            // ProPresenter nor the UUID lookup above provided a concrete slideIndex. Kept as a
            // last resort — text matching breaks on repeated/duplicate slide text.
            if shouldInferSlideIndex,
               currentSlideIndex == nil,
               normalized.slideIndex == nil,
               !groupRangesForMatch.isEmpty,
               (normalized.slideText?.isEmpty ?? true),
               let resolvedBlankIndex = ProPresenterSlideIdentity.resolvedBlankCurrentSlideIndex(
                currentSlideIndex: normalized.slideIndex,
                nextSlideText: normalized.nextSlideText,
                preferredDisplayIndex: preferredDisplayIndex,
                ranges: groupRangesForMatch
               ) {
                normalized.slideIndex = resolvedBlankIndex
                let displayIndex = resolvedBlankIndex + 1
                if let currentMatch = groupRangesForMatch.first(where: { displayIndex >= $0.start && displayIndex <= $0.end }) {
                    matchedGroupSlideIndex = resolvedBlankIndex
                    if config.showGroupName || config.showGroupColor {
                        normalized.groupName = currentMatch.name
                        normalized.groupColor = currentMatch.color
                    }
                }
            }

            let shouldFetchThumbnails = config.slideContentMode == .thumbnail && config.dataMode.isSlideMode
            let thumbnailQuality = 400
            s = stateByModuleID[moduleID] ?? State()
            if shouldFetchThumbnails {
                let playlistInfo = await fetchActivePlaylistItemIndex(host: host, port: port, password: password)
                s.lastPlaylistItemIndex = playlistInfo.index
                if let playlistItemIndex = playlistInfo.index,
                   let currentIndex = normalized.slideIndex {
                    let needsCurrent = s.lastThumbnailPlaylistItemIndex != playlistItemIndex
                        || s.lastThumbnailCurrentIndex != currentIndex
                        || s.lastThumbnailQuality != thumbnailQuality
                    if needsCurrent, let data = await fetchSlideThumbnail(
                        host: host,
                        port: port,
                        password: password,
                        playlistItemIndex: playlistItemIndex,
                        slideIndex: currentIndex,
                        quality: thumbnailQuality
                    ) {
                        s.lastThumbnailCurrentData = data
                        s.lastThumbnailCurrentIndex = currentIndex
                        s.lastThumbnailPlaylistItemIndex = playlistItemIndex
                        s.lastThumbnailQuality = thumbnailQuality
                    }

                    if config.dataMode.supportsNextPreview {
                        let nextIndex = currentIndex + 1
                        if let total = normalized.slideTotal, nextIndex >= total {
                            s.lastThumbnailNextIndex = nil
                            s.lastThumbnailNextData = nil
                        } else {
                            let needsNext = s.lastThumbnailPlaylistItemIndex != playlistItemIndex
                                || s.lastThumbnailNextIndex != nextIndex
                                || s.lastThumbnailQuality != thumbnailQuality
                            if needsNext, let data = await fetchSlideThumbnail(
                                host: host,
                                port: port,
                                password: password,
                                playlistItemIndex: playlistItemIndex,
                                slideIndex: nextIndex,
                                quality: thumbnailQuality
                            ) {
                                s.lastThumbnailNextData = data
                                s.lastThumbnailNextIndex = nextIndex
                                s.lastThumbnailPlaylistItemIndex = playlistItemIndex
                                s.lastThumbnailQuality = thumbnailQuality
                            }
                        }
                    }
                }
            }

            if let matchedGroupSlideIndex {
                s.lastGroupSlideIndex = matchedGroupSlideIndex
            }
            #if DEBUG
            if beforeChangeSnapshot.slideIndex != normalized.slideIndex || beforeChangeSnapshot.slideUUID != normalized.slideUUID {
                let text = (normalized.slideText ?? "").replacingOccurrences(of: "\n", with: " ").prefix(40)
                print("[ProPresenterService][slide-debug] pres=\(normalized.presentationName ?? "nil") apiIndex=\(currentSlideIndex.map(String.init) ?? "nil") slideIndex=\(normalized.slideIndex.map(String.init) ?? "nil") display=\(normalized.slideIndex.map { String($0 + 1) } ?? "nil")/\(normalized.slideTotal.map(String.init) ?? "nil") group=\(normalized.groupName ?? "nil") text=\"\(text)\"")
            }
            #endif
            s.status = normalized
            s.lastError = nil
            s.lastUpdated = Date()
            s.lastResponseSummary = "OK (JSON received)"
            s.lastJSONPreview = jsonPreview
            var dict1 = stateByModuleID
            dict1[moduleID] = s
            stateByModuleID = dict1

            let afterChangeSnapshot = Self.changeSnapshot(from: s)
            let changes = Self.detectChanges(before: beforeChangeSnapshot, after: afterChangeSnapshot)
            if !changes.isEmpty {
                let resolvedProfileId = ProPresenterProfilesStore.resolvedProfileIdentity(configuredProfileId: config.connectionProfileID)
                for change in changes {
                    let event: DashboardGraph.ProPresenterTriggerEvent
                    // The notification's `value` is deliberately the identifying name (message
                    // name / timer name), not the changed content/state -- ProPresenterTriggerConfig's
                    // Filter matches against "message named X" / "timer named X" per the design spec,
                    // not against the new message text or timer running-state. The discarded second
                    // field in .messageChanged/.timerChanged (ChangeKind's own `text`/`value`) is only
                    // used by detectChanges' own tests, not propagated past this point.
                    let value: String?
                    // Numeric payload for downstream condition/action nodes -- slide index for
                    // slideChanged, a parsed timer value for timerChanged (looked up from the
                    // timer's raw `time` field, since the diffed `value` above is deliberately
                    // the timer's state string, not a number), nil otherwise.
                    let numberValue: Double?
                    switch change {
                    case .slideChanged(let label, let index):
                        event = .slideChanged
                        value = label
                        numberValue = index.map(Double.init)
                    case .presentationChanged(let name):
                        event = .presentationChanged
                        value = name
                        numberValue = nil
                    case .messageChanged(let name, _):
                        event = .messageChanged
                        value = name
                        numberValue = nil
                    case .timerChanged(let name, _):
                        event = .timerChanged
                        value = name
                        let rawTime = s.lastTimers.first(where: { ($0.name ?? $0.uuid ?? "timer") == name })?.time
                        numberValue = Self.parseNumericTimerValue(rawTime)
                    }
                    NotificationCenter.default.post(
                        name: .relayProPresenterStateDidChange,
                        object: nil,
                        userInfo: [
                            "moduleId": moduleID,
                            "resolvedProfileId": resolvedProfileId as Any,
                            "event": event.rawValue,
                            "value": value as Any,
                            "numberValue": numberValue as Any
                        ]
                    )
                }
            }

            if previousError != nil {
                let requestDesc = s.lastRequestDescription ?? "Unknown"
                print("[ProPresenter] Recovered \(requestDesc)")
            }

            debugLog("Success for module \(moduleID). \(s.lastRequestDescription ?? "")")
            debugLog("JSON: \(jsonPreview)")
        } catch {
            if shouldTreatAsNoPresentation(error: error) {
                resetPollBackoff(for: currentSourceKey)
                var s = stateByModuleID[moduleID] ?? State()
                s.status = ProPresenterSlideStatus(
                    isConnected: true,
                    presentationName: s.status.presentationName,
                    arrangementName: s.status.arrangementName,
                    slideText: nil,
                    slideNotes: nil,
                    slideIndex: nil,
                    slideTotal: nil,
                    slideLabel: config.dataMode.primaryLabel,
                    slideUUID: nil,
                    nextSlideText: nil,
                    nextSlideNotes: nil,
                    nextSlideUUID: nil
                )
                s.lastError = nil
                s.lastUpdated = Date()
                s.lastResponseSummary = "No active presentation"
                var dict2 = stateByModuleID
                dict2[moduleID] = s
                stateByModuleID = dict2

                debugLog("No active presentation for module \(moduleID). \(s.lastRequestDescription ?? "")")
                return
            }

            let previousError = stateByModuleID[moduleID]?.lastError
            var s = stateByModuleID[moduleID] ?? State()
            let errorSummary = summarizeError(error)
            if isTransportDisconnectError(error) {
                recordTransportFailure(for: currentSourceKey)
                clearCachedPresentationState(&s, isConnected: false)
            } else {
                resetPollBackoff(for: currentSourceKey)
            }
            s.status = ProPresenterSlideStatus(
                isConnected: false,
                presentationName: s.status.presentationName,
                arrangementName: s.status.arrangementName,
                slideText: s.status.slideText,
                slideNotes: s.status.slideNotes,
                slideIndex: s.status.slideIndex,
                slideTotal: s.status.slideTotal,
                slideLabel: s.status.slideLabel,
                slideUUID: s.status.slideUUID,
                nextSlideText: s.status.nextSlideText,
                nextSlideNotes: s.status.nextSlideNotes,
                nextSlideUUID: s.status.nextSlideUUID
            )
            s.lastError = errorSummary
            s.lastUpdated = Date()
            s.lastResponseSummary = "ERROR: \(errorSummary)"
            var dict2 = stateByModuleID
            dict2[moduleID] = s
            stateByModuleID = dict2

            if previousError != errorSummary {
                let requestDesc = s.lastRequestDescription ?? "Unknown"
                print("[ProPresenter] Error \(requestDesc) — \(errorSummary)")
            }

            let requestDesc = s.lastRequestDescription ?? "Unknown"
            logDiagnosticError("Error \(requestDesc) — \(errorSummary)", key: "propresenter_\(moduleID)_\(requestDesc)")
            debugLog("Failure for module \(moduleID). \(s.lastRequestDescription ?? ""). Error: \(errorSummary)")
            return
        }

        resetPollBackoff(for: currentSourceKey)
    }

    /// Extracts the current slide's 0-based cue index from `GET /v1/presentation/slide_index`,
    /// whose shape is `{"presentation_index": {"index": Int, "presentation_id": {...}}}` (or
    /// `{"presentation_index": null}` when nothing is live). This is the ONLY authoritative slide
    /// position ProPresenter exposes -- `presentation.id.index` on `/v1/presentation/active` is the
    /// presentation's position in its playlist, not a slide index.
    static func extractSlideIndex(from json: JSONValue) -> Int? {
        guard let index = json["presentation_index"]?["index"]?.asInt(), index >= 0 else { return nil }
        return index
    }

    /// Current slide index (0-based) for the live presentation, or nil if unavailable.
    private func fetchCurrentSlideIndex(host: String, port: Int, password: String) async -> Int? {
        guard let data = try? await httpGetRaw(host: host, port: port, path: "/v1/presentation/slide_index", password: password),
              let json = tryDecodeJSONValue(data) else { return nil }
        return Self.extractSlideIndex(from: json)
    }

    static func extractPresentationName(from json: JSONValue) -> String? {
        // Try common shapes/keys seen in ProPresenter HTTP responses.
        // We keep this schema-safe and opportunistic.
        let candidates: [String?] = [
            json["name"]?.asString(),
            json["presentationName"]?.asString(),
            json["title"]?.asString(),
            // GET /v1/presentation/active nests the name under presentation.id.name (confirmed
            // against ProPresenter's published OpenAPI spec) rather than presentation.name --
            // missing this made name resolution always fall through to /v1/presentation/focused,
            // which reflects the operator's UI selection, not what's actually live on screen.
            json["presentation"]?["id"]?["name"]?.asString(),
            json["presentation"]?["name"]?.asString(),
            json["presentation"]?["presentationName"]?.asString(),
            json["presentation"]?["title"]?.asString(),
            json["data"]?["name"]?.asString(),
            json["data"]?["presentationName"]?.asString(),
            json["data"]?["title"]?.asString(),
            json["current"]?["name"]?.asString(),
            json["current"]?["title"]?.asString(),
            // Additional nested shapes for active presentation title
            json["presentation"]?["data"]?["name"]?.asString(),
            json["presentation"]?["data"]?["title"]?.asString(),
            json["data"]?["presentation"]?["name"]?.asString(),
            json["data"]?["presentation"]?["title"]?.asString(),
            json["current"]?["presentation"]?["name"]?.asString(),
            json["current"]?["presentation"]?["title"]?.asString(),
            json["active"]?["name"]?.asString(),
            json["active"]?["title"]?.asString(),
            json["activePresentation"]?["name"]?.asString(),
            json["activePresentation"]?["title"]?.asString()
        ]

        for c in candidates {
            if let c, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return c.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    private func parseTimers(from json: JSONValue) -> [TimerItem] {
        func asTimerObject(_ v: JSONValue) -> TimerItem? {
            guard case .object(let obj) = v else { return nil }
            let uuid = obj["uuid"]?.asString() ?? obj["id"]?.asString()
            let name = obj["name"]?.asString() ?? obj["label"]?.asString()
            let time = obj["time"]?.asString()
                ?? obj["current_time"]?.asString()
                ?? obj["currentTime"]?.asString()
                ?? obj["remaining"]?.asString()
            let state = obj["state"]?.asString() ?? obj["status"]?.asString()
            if uuid == nil && name == nil && time == nil { return nil }
            return TimerItem(uuid: uuid, name: name, time: time, state: state)
        }

        func unwrap(_ v: JSONValue) -> JSONValue {
            if case .object(let o) = v {
                if let timers = o["timers"] { return timers }
                if let data = o["data"] { return data }
            }
            return v
        }

        let root = unwrap(json)
        switch root {
        case .array(let arr):
            return arr.compactMap(asTimerObject)
        case .object(let obj):
            let keys = obj.keys.sorted()
            return keys.compactMap { k in obj[k].flatMap(asTimerObject) }
        default:
            return []
        }
    }
	/// Best-effort mapping from ProPresenter’s JSON to a stable shape for the UI.
    /// Extracts a slide's uuid from a `/v1/status/slide` "current"/"next" object.
    /// ProPresenter sometimes nests identity as `uuid: {uuid, name}` rather than a flat string,
    /// so `asString()` on the nested object silently returns nil — check the nested form first.
    /// Lowercased so it can be matched against `slideUUID(from:)` in the groups-endpoint parser,
    /// which returns different casing depending on the ProPresenter version/endpoint.
    private func extractSlideUUID(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        let candidates = [
            value["uuid"]?.asString(),
            value["uuid"]?["uuid"]?.asString(),
            value["id"]?["uuid"]?.asString(),
            value["id"]?.asString()
        ]
        for candidate in candidates {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate.lowercased()
            }
        }
        return nil
    }

	private func normalize(json: JSONValue, mode: ProPresenterDataMode, presentationName: String?) -> ProPresenterSlideStatus {
		let indexKeys = [
			"slideIndex",
			"slideNumber",
			"slide_number",
			"presentationSlideIndex",
			"presentationIndex",
			"currentSlideIndex",
			"current_slide_index",
			"currentIndex",
			"index",
			"number"
		]
		let totalKeys = [
			"slideCount",
			"slide_count",
			"slidesCount",
			"slides_count",
			"slideTotal",
			"slide_total",
			"totalSlides",
			"total_slides",
			"presentationSlideCount",
			"presentationCount",
			"count",
			"total",
			"size",
			"length"
		]

		func firstInt(in value: JSONValue?, keys: [String]) -> Int? {
			guard let value else { return nil }
			for key in keys {
				if let number = value[key]?.asInt() {
					return number
				}
			}
			return nil
		}

		func candidateObjects(from value: JSONValue?) -> [JSONValue] {
			guard let value else { return [] }
			var candidates: [JSONValue] = [value]
			let directKeys = ["presentation", "slide", "slides", "current", "next", "data"]
			for key in directKeys {
				if let v = value[key] { candidates.append(v) }
			}
			if let presentation = value["presentation"] {
				let nestedKeys = ["current", "next", "slide", "slides", "data"]
				for key in nestedKeys {
					if let v = presentation[key] { candidates.append(v) }
				}
			}
			return candidates
		}

		func slidePosition(from value: JSONValue?, fallback: JSONValue) -> (index: Int?, total: Int?) {
			let candidates = candidateObjects(from: value) + candidateObjects(from: fallback)
			let index = candidates.compactMap { firstInt(in: $0, keys: indexKeys) }.first
			let total = candidates.compactMap { firstInt(in: $0, keys: totalKeys) }.first
			return (index, total)
		}

		switch mode {
		case .slideCurrentNext:
			// {"current": {"text":..., "notes":..., "uuid":...}, "next": {...}}
			let currentText =
				json["current"]?["text"]?.asString()
                ?? json["current"]?["content"]?.asString()
                ?? json["text"]?.asString()
            let currentNotes =
                json["current"]?["notes"]?.asString()
                ?? json["notes"]?.asString()

            let nextText =
                json["next"]?["text"]?.asString()
                ?? json["next"]?["content"]?.asString()
            let nextNotes =
                json["next"]?["notes"]?.asString()

            let currentUUID = extractSlideUUID(from: json["current"])
			let nextUUID = extractSlideUUID(from: json["next"])

			let currentPosition = slidePosition(from: json["current"], fallback: json)

				return ProPresenterSlideStatus(
					isConnected: true,
					presentationName: presentationName,
					arrangementName: nil,
					slideText: currentText ?? currentNotes,
                    slideNotes: currentNotes,
					slideIndex: currentPosition.index,
					slideTotal: currentPosition.total,
					slideLabel: mode.primaryLabel,
					slideUUID: currentUUID,
					nextSlideText: nextText ?? nextNotes,
                    nextSlideNotes: nextNotes,
					nextSlideUUID: nextUUID
				)

        case .slideCurrentOnly:
            let currentText =
                json["current"]?["text"]?.asString()
                ?? json["current"]?["content"]?.asString()
                ?? json["text"]?.asString()
            let currentNotes =
                json["current"]?["notes"]?.asString()
                ?? json["notes"]?.asString()

			let currentUUID = extractSlideUUID(from: json["current"])

			let currentPosition = slidePosition(from: json["current"], fallback: json)

				return ProPresenterSlideStatus(
					isConnected: true,
					presentationName: presentationName,
					slideText: currentText ?? currentNotes,
                    slideNotes: currentNotes,
					slideIndex: currentPosition.index,
					slideTotal: currentPosition.total,
					slideLabel: mode.primaryLabel,
					slideUUID: currentUUID,
					nextSlideText: nil,
                    nextSlideNotes: nil,
					nextSlideUUID: nil
				)

        case .slideNextOnly:
            let nextText =
                json["next"]?["text"]?.asString()
                ?? json["next"]?["content"]?.asString()
            let nextNotes =
                json["next"]?["notes"]?.asString()

			let nextUUID = extractSlideUUID(from: json["next"])

			let nextPosition = slidePosition(from: json["next"], fallback: json)

				return ProPresenterSlideStatus(
					isConnected: true,
					presentationName: presentationName,
					slideText: nextText ?? nextNotes,
                    slideNotes: nextNotes,
					slideIndex: nextPosition.index,
					slideTotal: nextPosition.total,
					slideLabel: mode.primaryLabel,
					slideUUID: nextUUID,
					nextSlideText: nil,
                    nextSlideNotes: nil,
					nextSlideUUID: nil
				)

        case .timersCurrent:
            // `GET /v1/timers/current` can return either:
            // - an array of timer objects
            // - an object with a `timers` key
            // - other version-dependent shapes
            // We normalize to a readable multi-line list.

            func renderTimerObject(_ obj: [String: JSONValue]) -> String? {
                let name = obj["name"]?.asString()
                    ?? obj["label"]?.asString()
                    ?? obj["id"]?.asString()
                    ?? obj["uuid"]?.asString()

                let time = obj["time"]?.asString()
                    ?? obj["current_time"]?.asString()
                    ?? obj["currentTime"]?.asString()
                    ?? obj["remaining"]?.asString()

                let state = obj["state"]?.asString()
                    ?? obj["status"]?.asString()

                // If we have at least a name or time, show it.
                if (name?.isEmpty == false) || (time?.isEmpty == false) {
                    var parts: [String] = []
                    if let name, !name.isEmpty { parts.append(name) }
                    if let time, !time.isEmpty {
                        parts.append(time)
                    }
                    if let state, !state.isEmpty {
                        parts.append(state)
                    }
                    return parts.joined(separator: "  •  ")
                }

                return nil
            }

            func renderTimers(from value: JSONValue) -> String {
                switch value {
                case .array(let arr):
                    // Most common: array of timer objects.
                    let lines = arr.compactMap { v -> String? in
                        if case .object(let o) = v {
                            return renderTimerObject(o)
                        }
                        return v.asString()
                    }
                    if !lines.isEmpty { return lines.joined(separator: "\n") }
                    return value.debugCompactString(maxLength: 700)

                case .object(let obj):
                    // Some versions: {"timers": [...] } or a keyed dict of timers.
                    if let timers = obj["timers"] {
                        return renderTimers(from: timers)
                    }

                    // If it's a keyed dictionary of timers, render each entry.
                    let keys = obj.keys.sorted()
                    let lines = keys.compactMap { k -> String? in
                        let v = obj[k] ?? .null
                        if case .object(let o) = v {
                            // Prefer the embedded name/time; otherwise prefix with key.
                            if let rendered = renderTimerObject(o) { return rendered }
                        }
                        if let s = v.asString(), !s.isEmpty {
                            return "\(k): \(s)"
                        }
                        return nil
                    }
                    if !lines.isEmpty { return lines.joined(separator: "\n") }
                    return value.debugCompactString(maxLength: 700)

                default:
                    if let s = value.asString(), !s.isEmpty { return s }
                    return value.debugCompactString(maxLength: 700)
                }
            }

            // Try common roots first.
            var rendered: String = ""
            if case .object(let obj) = json {
                if let timers = obj["timers"] {
                    rendered = renderTimers(from: timers)
                } else if let data = obj["data"] {
                    rendered = renderTimers(from: data)
                } else {
                    rendered = renderTimers(from: json)
                }
            } else {
                rendered = renderTimers(from: json)
            }

            return ProPresenterSlideStatus(
                isConnected: true,
                presentationName: nil,
                slideText: rendered.isEmpty ? nil : rendered,
                slideIndex: nil,
                slideTotal: nil,
                slideLabel: mode.primaryLabel,
                slideUUID: nil,
                nextSlideText: nil,
                nextSlideUUID: nil
            )

        case .timerVideoCountdown:
            // `GET /v1/timer/video_countdown` returns the current countdown value.
            let value = json.asString() ?? json["data"]?.asString() ?? json.debugCompactString(maxLength: 200)
            return ProPresenterSlideStatus(
                isConnected: true,
                presentationName: nil,
                slideText: value,
                slideIndex: nil,
                slideTotal: nil,
                slideLabel: mode.primaryLabel,
                slideUUID: nil,
                nextSlideText: nil,
                nextSlideUUID: nil
            )

        case .stageMessage:
            // `GET /v1/stage/message` returns the current stage message text.
            let normalizedJSON = json.decodedJSONValueIfJSONString() ?? json
            func firstString(in value: JSONValue?, keys: [String]) -> String? {
                guard let value else { return nil }
                for key in keys {
                    if let string = value[key]?.asString() {
                        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || trimmed == "null" { continue }
                        return trimmed
                    }
                }
                return nil
            }

            func messageFromArray(_ arr: [JSONValue]) -> String? {
                func truthy(_ value: JSONValue?) -> Bool {
                    guard let value else { return false }
                    switch value {
                    case .bool(let b):
                        return b
                    case .string(let s):
                        return s.lowercased() == "true" || s == "1"
                    case .number(let n):
                        return n != 0
                    default:
                        return false
                    }
                }
                func messageFromObject(_ obj: [String: JSONValue]) -> String? {
                    if let raw = obj["message"]?.asString() {
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "null" { return trimmed }
                    }
                    return nil
                }

                for item in arr {
                    if case .object(let obj) = item,
                       truthy(obj["is_active"]),
                       let msg = messageFromObject(obj) {
                        return msg
                    }
                }

                for item in arr {
                    if case .object(let obj) = item,
                       let msg = messageFromObject(obj) {
                        return msg
                    }
                }
                return nil
            }

            let value = normalizedJSON.asString()
                ?? {
                    if case .array(let arr) = normalizedJSON {
                        return messageFromArray(arr)
                    }
                    return nil
                }()
                ?? firstString(in: normalizedJSON, keys: ["message", "text", "value", "content"])
                ?? firstString(in: normalizedJSON["data"], keys: ["message", "text", "value", "content"])
                ?? firstString(in: normalizedJSON["message"], keys: ["message", "text", "value", "content"])
                ?? firstString(in: normalizedJSON["stage"], keys: ["message", "text", "value", "content"])
                ?? firstString(in: normalizedJSON["stageMessage"], keys: ["message", "text", "value", "content"])
                ?? firstString(in: normalizedJSON["current"], keys: ["message", "text", "value", "content"])
                ?? ""
            let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalValue = (cleanedValue == "null" || cleanedValue.isEmpty) ? "" : cleanedValue
            return ProPresenterSlideStatus(
                isConnected: true,
                presentationName: nil,
                slideText: finalValue.isEmpty ? nil : finalValue,
                slideIndex: nil,
                slideTotal: nil,
                slideLabel: mode.primaryLabel,
                slideUUID: nil,
                nextSlideText: nil,
                nextSlideUUID: nil
            )
        }
    }
}

// MARK: - Tile UI

private struct ProPresenterModePill: View {
    let text: String
    let textColor: Color
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }
}

private struct ProPresenterInfoCard: View {
    let title: String
    let text: String
    let font: Font
    let maxLines: Int?
    let textColor: Color
    let titleColor: Color
    let titleLeadingColor: Color?
    let headerBackgroundColor: Color?
    let headerPillColor: Color?
    let headerGroupText: String?
    let headerGroupColor: Color
    let headerAccessoryText: String?
    let headerAccessoryColor: Color
    let headerTextColor: Color
    let headerFont: Font
    let thumbnailImage: Image?
    let textAlignment: TextAlignment
    let horizontalAlignment: Alignment
    let fixedHeight: CGFloat?
    let flashEnabled: Bool
    let flashColor: Color?
    let flashStartDate: Date?
    let flashRepeatCount: Int
    let flashIndefinite: Bool
    let flashInterval: TimeInterval

    init(
        title: String,
        text: String,
        font: Font = .callout,
        maxLines: Int? = nil,
        textColor: Color = .primary,
        titleColor: Color = .secondary,
        titleLeadingColor: Color? = nil,
        headerBackgroundColor: Color? = nil,
        headerPillColor: Color? = nil,
        headerGroupText: String? = nil,
        headerGroupColor: Color = .primary,
        headerAccessoryText: String? = nil,
        headerAccessoryColor: Color = .primary,
        headerTextColor: Color = .primary,
        headerFont: Font = .caption2.weight(.semibold),
        thumbnailImage: Image? = nil,
        textAlignment: TextAlignment = .leading,
        horizontalAlignment: Alignment = .leading,
        fixedHeight: CGFloat? = nil,
        flashEnabled: Bool = false,
        flashColor: Color? = nil,
        flashStartDate: Date? = nil,
        flashRepeatCount: Int = 3,
        flashIndefinite: Bool = false,
        flashInterval: TimeInterval = 0.6
    ) {
        self.title = title
        self.text = text
        self.font = font
        self.maxLines = maxLines
        self.textColor = textColor
        self.titleColor = titleColor
        self.titleLeadingColor = titleLeadingColor
        self.headerBackgroundColor = headerBackgroundColor
        self.headerPillColor = headerPillColor
        self.headerGroupText = headerGroupText
        self.headerGroupColor = headerGroupColor
        self.headerAccessoryText = headerAccessoryText
        self.headerAccessoryColor = headerAccessoryColor
        self.headerTextColor = headerTextColor
        self.headerFont = headerFont
        self.thumbnailImage = thumbnailImage
        self.textAlignment = textAlignment
        self.horizontalAlignment = horizontalAlignment
        self.fixedHeight = fixedHeight
        self.flashEnabled = flashEnabled
        self.flashColor = flashColor
        self.flashStartDate = flashStartDate
        self.flashRepeatCount = flashRepeatCount
        self.flashIndefinite = flashIndefinite
        self.flashInterval = flashInterval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let headerBackgroundColor {
                HStack(spacing: 6) {
                    if let titleLeadingColor {
                        Circle()
                            .fill(titleLeadingColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(title)
                        .font(headerFont)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black)
                        .clipShape(Capsule())
                    if let headerGroupText, !headerGroupText.isEmpty {
                        Text(headerGroupText)
                            .font(headerFont)
                            .foregroundStyle(headerGroupColor)
                    }
                    Spacer(minLength: 0)
                    if let headerAccessoryText, !headerAccessoryText.isEmpty {
                        Text(headerAccessoryText)
                            .font(headerFont)
                            .foregroundStyle(headerAccessoryColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(headerBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if let headerPillColor {
                HStack(spacing: 6) {
                    if let titleLeadingColor {
                        Circle()
                            .fill(titleLeadingColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(title)
                        .font(headerFont)
                        .foregroundStyle(headerTextColor)
                    if let headerGroupText, !headerGroupText.isEmpty {
                        Text(headerGroupText)
                            .font(headerFont)
                            .foregroundStyle(headerGroupColor)
                    }
                    Spacer(minLength: 0)
                    if let headerAccessoryText, !headerAccessoryText.isEmpty {
                        Text(headerAccessoryText)
                            .font(headerFont)
                            .foregroundStyle(headerAccessoryColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(headerPillColor)
                .clipShape(Capsule())
            } else {
                HStack(spacing: 6) {
                    if let titleLeadingColor {
                        Circle()
                            .fill(titleLeadingColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(title)
                        .font(headerFont)
                        .foregroundStyle(titleColor)
                }
            }

            if let thumbnailImage {
                thumbnailImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if flashEnabled, let flashColor, let flashStartDate {
                TimelineView(.animation(minimumInterval: flashInterval)) { context in
                    let elapsed = context.date.timeIntervalSince(flashStartDate)
                    let tick = Int(max(0, elapsed) / flashInterval)
                    let effectiveRepeats = max(0, flashRepeatCount)
                    let maxTicks = effectiveRepeats * 2
                    let shouldFlash = flashIndefinite || (effectiveRepeats > 0 && tick < maxTicks)
                    let useFlash = shouldFlash && (tick % 2 == 0)
                    Text(text)
                        .font(font)
                        .foregroundStyle(useFlash ? flashColor : textColor)
                        .shadow(color: useFlash ? flashColor.opacity(0.7) : .clear, radius: useFlash ? 3 : 0)
                        .frame(maxWidth: .infinity, alignment: horizontalAlignment)
                        .multilineTextAlignment(textAlignment)
                        .lineLimit(maxLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: horizontalAlignment)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(maxLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: horizontalAlignment)
        .frame(minHeight: fixedHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
    }
}

struct ProPresenterModuleView: View {
    let moduleID: UUID
    @Binding var config: ProPresenterModuleConfig
    @ObservedObject var service: ProPresenterService
    let isLiveMode: Bool

    @State private var hasSeededConfig: Bool = false
    @State private var pollingOwnerID: UUID = UUID()
    @State private var lastStageMessageText: String = ""
    @State private var lastAudienceMessageText: String = ""
    @State private var stageFlashStart: Date? = nil
    @State private var audienceFlashStart: Date? = nil
    @State private var lastStageMessageReceivedAt: Date? = nil
    @State private var lastAudienceMessageReceivedAt: Date? = nil

    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering

    @AppStorage("dashboard_live_mode_enabled") private var liveModeEnabled: Bool = false
    @State private var probeState: ProPresenterProbeState = .idle
    @State private var probeTask: Task<Void, Never>? = nil

    private var effectiveLiveMode: Bool { !isLANSnapshotRendering && (isLiveMode || liveModeEnabled) }

    // Saved profiles store (written by DashboardProPresenterSettingsView)
    @AppStorage("propresenter_profiles") private var profilesData: Data = Data()

    private var profiles: [ProPresenterConnectionProfile] {
        guard !profilesData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ProPresenterConnectionProfile].self, from: profilesData)) ?? []
    }

    private var sortedProfiles: [ProPresenterConnectionProfile] {
        profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func preferredProfileID() -> UUID? {
        if let activeID = ProPresenterProfilesStore.activeProfileID(),
           sortedProfiles.contains(where: { $0.id == activeID }) {
            return activeID
        }
        return sortedProfiles.first?.id
    }

    private func hasValidSelectedProfile(_ profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return profiles.contains(where: { $0.id == profileID })
    }

    private func resolvedProfileDisplayForEdit() -> String {
        if let id = config.connectionProfileID,
           let p = profiles.first(where: { $0.id == id }) {
            return p.name
        }
        return sortedProfiles.isEmpty ? "No Profile Selected" : "Missing Profile"
    }

    private func resolvedProfileDisplay() -> String {
        if let id = config.connectionProfileID,
           let p = profiles.first(where: { $0.id == id }) {
            return p.name
        }
        return sortedProfiles.isEmpty ? "No Profile Selected" : "Missing Profile"
    }

    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    private var headerFontSize: CGFloat {
        max(9, baseFontSize * 0.5)
    }

    private var headerFont: Font {
        .system(size: headerFontSize, weight: .semibold)
    }

    private var primaryFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    private var resolvedPrimaryColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? .white
    }

    private var resolvedSecondaryColor: Color {
        resolvedPrimaryColor.opacity(0.7)
    }

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

    private var messageTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter
    }

    private func formattedMessageTimestamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        return messageTimestampFormatter.string(from: date)
    }

    private func thumbnailImage(from data: Data?) -> Image? {
        guard let data else { return nil }
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #endif
        return nil
    }

    private func handleMessageChange(text: String, target: ProPresenterMessageTarget) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if target == .stage {
            if trimmed.isEmpty {
                lastStageMessageText = ""
                stageFlashStart = nil
                return
            }
            if trimmed != lastStageMessageText {
                lastStageMessageText = trimmed
                stageFlashStart = Date()
                lastStageMessageReceivedAt = Date()
            }
        } else {
            if trimmed.isEmpty {
                lastAudienceMessageText = ""
                audienceFlashStart = nil
                return
            }
            if trimmed != lastAudienceMessageText {
                lastAudienceMessageText = trimmed
                audienceFlashStart = Date()
                lastAudienceMessageReceivedAt = Date()
            }
        }
    }

    private func seedConfigIfNeeded() {
        guard !hasSeededConfig else { return }

        var updated = config
        var didUpdate = false

        if updated.id != moduleID {
            updated.id = moduleID
            didUpdate = true
        }

        if !hasValidSelectedProfile(updated.connectionProfileID),
           let preferredProfileID = preferredProfileID() {
            updated.connectionProfileID = preferredProfileID
            didUpdate = true
        }

        if didUpdate {
            config = updated
            service.setConfig(moduleID: moduleID, config: updated)
        }

        hasSeededConfig = true
    }

    private func startProbe() {
        probeTask?.cancel()
        probeState = .checking
        let connection = ProPresenterConnection(profileID: config.connectionProfileID)
        probeTask = Task { @MainActor in
            do {
                try await ProPresenterSettingsConnectionProbe.testHTTP(
                    host: connection.settings.host,
                    port: connection.settings.port,
                    password: connection.settings.password,
                    timeout: 3.0
                )
                guard !Task.isCancelled else { return }
                probeState = .reachable
            } catch {
                guard !Task.isCancelled else { return }
                probeState = .unreachable
            }
        }
    }

    private func cancelProbe() {
        probeTask?.cancel()
        probeTask = nil
        probeState = .idle
    }

    private var probeColor: Color {
        switch probeState {
        case .idle, .checking: return .yellow
        case .reachable: return .green
        case .unreachable: return .red
        }
    }

    private var probeStatusText: String {
        switch probeState {
        case .idle, .checking: return "Checking…"
        case .reachable: return "Connected"
        case .unreachable: return "Unreachable"
        }
    }

    private var probeIcon: String {
        switch probeState {
        case .idle, .checking: return "circle.dotted"
        case .reachable: return "checkmark.circle.fill"
        case .unreachable: return "xmark.circle.fill"
        }
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
        private func displayIndex(for status: ProPresenterSlideStatus, state: ProPresenterService.State) -> Int? {
            if let slideIndex = status.slideIndex {
                return slideIndex + 1
            }
            return nil
        }

    private func slideNumberText(for status: ProPresenterSlideStatus, state: ProPresenterService.State) -> String? {
        guard config.showSlideNumbers, config.dataMode.isSlideMode else { return nil }
        guard let displayIndex = displayIndex(for: status, state: state) else { return nil }

            let total = status.slideTotal
            if let total, total > 0 {
                return "Slide \(displayIndex)/\(total)"
            }
            return "Slide \(displayIndex)"
            }

        private func proPresenterSlideNumberText(status: ProPresenterSlideStatus, state: ProPresenterService.State) -> String {
            guard config.showSlideNumbers else { return "" }
            guard let displayIndex = displayIndex(for: status, state: state) else { return "" }
            let total = status.slideTotal
        if let total, total > 0 { return "\(displayIndex)/\(total)" }
        return "\(displayIndex)"
    }

    private func normalizeSlideTextForMatch(_ text: String) -> String {
        let lowered = text.lowercased()
        let spaced = lowered
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let parts = spaced.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

	private func proPresenterGroupText(status: ProPresenterSlideStatus) -> String {
		guard config.showGroupName else { return "" }
		return status.groupName ?? ""
	}

    private func unwrapMessagePreview(_ preview: String?) -> String? {
        guard let preview else { return nil }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "null" {
            return nil
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            let inner = String(trimmed.dropFirst().dropLast())
            let unescaped = inner.replacingOccurrences(of: "\\\"", with: "\"")
            let cleaned = unescaped.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned == "null" ? nil : cleaned
        }
        return trimmed
    }

		func timerLine(_ t: ProPresenterService.TimerItem) -> String {
		var parts: [String] = []
		if let n = t.name, !n.isEmpty { parts.append(n) }
        if let tm = t.time, !tm.isEmpty { parts.append(tm) }
        if let st = t.state, !st.isEmpty { parts.append(st) }
        return parts.isEmpty ? (t.name ?? t.uuid ?? "Timer") : parts.joined(separator: "  •  ")
    }
	var body: some View {
		let state = service.stateByModuleID[moduleID] ?? .init()
		let connected = state.status.isConnected || (state.lastUpdated != nil && state.lastError == nil)
		let arrangementSuffix: String = {
			guard config.showPresentationName, config.showArrangementName else { return "" }
			let arrangement = state.status.arrangementName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			return arrangement.isEmpty ? "" : " · \(arrangement)"
		}()
		let currentThumbnail = config.slideContentMode == .thumbnail ? thumbnailImage(from: state.lastThumbnailCurrentData) : nil
						let nextThumbnail = config.slideContentMode == .thumbnail ? thumbnailImage(from: state.lastThumbnailNextData) : nil
        // ProPresenter's REST API (confirmed against its published OpenAPI spec) never reports
        // whether a slide holds video/image media -- /v1/status/slide returns only text/notes/uuid,
        // so a slide with no text is indistinguishable from a genuinely blank one. "[No Text]" avoids
        // claiming a specific (and often wrong) state for slides that are actually showing media.
        let currentSlideFallbackText = "[No Text]"
        let nextSlideFallbackText = "[No Text]"
			let baseTitle: String = {
            if config.dataMode == .stageMessage {
                return config.messageTarget.displayName
            }
            if state.status.slideLabel?.isEmpty == false {
                return state.status.slideLabel ?? config.dataMode.primaryLabel
            }
            return config.dataMode.primaryLabel
        }()
		let slideNumber = slideNumberText(for: state.status, state: state).map(applyCapitalization)
		let defaultTitle = ([applyCapitalization(baseTitle), slideNumber].compactMap { $0 }).joined(separator: " • ")
		let headerInfo = proPresenterSlideNumberText(status: state.status, state: state)
		let headerGroupText = proPresenterGroupText(status: state.status)
		let fallbackGroupText = state.status.groupName ?? state.lastGroupName ?? headerGroupText
		let headerTitle = "Current"
        let showHeaderBar = config.dataMode.isSlideMode
        let showGroupName = config.showGroupName
        let showGroupColor = config.showGroupColor
        let headerBarColor: Color? = showGroupColor
            ? (state.status.groupColor?.swiftUIColor ?? Color.blue)
            : Color(.sRGB, white: 0.18, opacity: 1)
        let headerPillColor: Color? = showGroupColor
            ? Color.black
            : Color(.sRGB, white: 0.18, opacity: 1)
        let headerGroupTextForLayout = showGroupName ? headerGroupText : fallbackGroupText
        let headerTextColorForLayout: Color = .white
        let headerGroupColorForLayout: Color = showGroupName ? headerTextColorForLayout : .clear
        let reservedLines = config.dataMode.isSlideMode ? max(1, config.maxPreviewLines) : 2
			let headerHeight: CGFloat = showHeaderBar ? (headerFontSize + 16) : 0
		let cardPadding: CGFloat = 20
		let currentTextHeight = (baseFontSize * 1.15) * CGFloat(reservedLines)
		let currentCardHeight = currentTextHeight + headerHeight + cardPadding
		let nextTextHeight = (baseFontSize * 0.85) * CGFloat(reservedLines)
		let nextCardHeight = nextTextHeight + headerHeight + cardPadding
		let nextGroupMatch: ProPresenterService.ProPresenterGroupRange? = {
                guard !state.lastGroupRanges.isEmpty else { return nil }
                if let nextText = state.status.nextSlideText,
                   !nextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let normalizedNext = normalizeSlideTextForMatch(nextText)
                    if !normalizedNext.isEmpty {
                        return state.lastGroupRanges.first(where: { range in
                            range.slideTexts.contains { normalizeSlideTextForMatch($0) == normalizedNext }
                        })
                    }
                }
                guard let displayIndex = displayIndex(for: state.status, state: state) else { return nil }
			let nextDisplayIndex = displayIndex + 1
			return state.lastGroupRanges.first(where: { nextDisplayIndex >= $0.start && nextDisplayIndex <= $0.end })
		}()
        let nextHeaderGroupText: String = {
            let trimmedMatch = nextGroupMatch?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedMatch.isEmpty {
                return trimmedMatch
            }
            let trimmedFallback = fallbackGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedFallback
        }()
        let nextHeaderGroupTextForLayout: String = {
            return showGroupName ? nextHeaderGroupText : nextHeaderGroupText
        }()
        let nextHeaderGroupColorForLayout: Color = showGroupName ? headerTextColorForLayout : .clear
        let nextHeaderBarColor: Color? = {
            guard showGroupColor else { return headerBarColor }
            return nextGroupMatch?.color?.swiftUIColor ?? headerBarColor
        }()
		let nextHeaderInfo: String = {
            guard config.showSlideNumbers else { return "" }
            guard let displayIndex = displayIndex(for: state.status, state: state) else { return "" }
            let total = state.status.slideTotal
            let nextIndex = displayIndex + 1
            if let total, total > 0 {
                return "\(nextIndex)/\(total)"
            }
            return "\(nextIndex)"
        }()
		let primaryTitle = showHeaderBar ? headerTitle : defaultTitle
        let shouldShowPrimaryCard = true
        let messageFlashEnabled: Bool = {
            guard config.dataMode == .stageMessage else { return false }
            if config.messageTarget == .stage {
                return config.stageMessageFlashEnabled
            }
            return config.audienceMessageFlashEnabled
        }()
        let messageFlashColor: Color? = {
            guard config.dataMode == .stageMessage else { return nil }
            let color = (config.messageTarget == .stage)
                ? config.stageMessageFlashColor
                : config.audienceMessageFlashColor
            if let color { return color.swiftUIColor }
            return messageFlashEnabled ? .red : nil
        }()
        let messageFlashRepeatCount: Int = {
            guard config.dataMode == .stageMessage else { return 0 }
            return config.messageTarget == .stage
                ? config.stageMessageFlashRepeatCount
                : config.audienceMessageFlashRepeatCount
        }()
        let messageFlashIndefinite: Bool = {
            guard config.dataMode == .stageMessage else { return false }
            return config.messageTarget == .stage
                ? config.stageMessageFlashIndefinite
                : config.audienceMessageFlashIndefinite
        }()
        let messageFlashStartDate: Date? = {
            guard config.dataMode == .stageMessage else { return nil }
            return config.messageTarget == .stage ? stageFlashStart : audienceFlashStart
        }()
        let messageLastReceivedText: String? = {
            guard config.dataMode == .stageMessage else { return nil }
            let date = config.messageTarget == .stage ? lastStageMessageReceivedAt : lastAudienceMessageReceivedAt
            guard let formatted = formattedMessageTimestamp(date) else { return nil }
            return "Last received: \(formatted)"
        }()

        let resolvedCurrentThumbnail: Image? = (config.dataMode.isSlideMode && config.slideContentMode == .thumbnail) ? currentThumbnail : nil
        let resolvedNextThumbnail: Image? = (config.dataMode.supportsNextPreview && config.slideContentMode == .thumbnail) ? nextThumbnail : nil

        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: baseFontSize * 0.9, weight: .semibold))
                    .foregroundStyle(effectiveLiveMode ? (connected ? .green : .red) : probeColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(applyCapitalization(resolvedProfileDisplay()))
                        .font(.system(size: baseFontSize * 0.9, weight: primaryFontWeight))
                        .foregroundStyle(resolvedPrimaryColor)
                        .lineLimit(1)

                    if config.showPresentationName {
                        if let pres = state.status.presentationName, !pres.isEmpty {
                            Text(applyCapitalization(pres) + arrangementSuffix)
                                .font(.system(size: baseFontSize * 0.65, weight: .regular))
                                .foregroundStyle(resolvedSecondaryColor)
                                .lineLimit(1)
                        } else {
                            if config.dataMode.isSlideMode {
                                // Fallback: show connection details if presentation name is unavailable.
                                let hostPort = state.lastRequestDescription
                                    .map { desc -> String in
                                        if let range = desc.range(of: "  ") {
                                            return String(desc[..<range.lowerBound])
                                        }
                                        return desc
                                    }

                                if let hostPort, !hostPort.isEmpty {
                                    Text(hostPort)
                                        .font(.system(size: baseFontSize * 0.65, weight: .regular))
                                        .foregroundStyle(resolvedSecondaryColor)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    ProPresenterModePill(
                        text: config.dataMode.displayName,
                        textColor: resolvedSecondaryColor,
                        fontSize: headerFontSize
                    )
                    if !shouldShowPrimaryCard, let slideNumber {
                        Text(slideNumber)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(resolvedSecondaryColor)
                            .lineLimit(1)
                    }
                }
            }
            // Primary content — only shown in live mode or when frozen data exists
            if effectiveLiveMode || state.lastUpdated != nil {
			if shouldShowPrimaryCard {
				let isTimerLike = (config.dataMode == .timerVideoCountdown || config.dataMode == .timersCurrent)
				let font: Font = isTimerLike
                ? .system(size: baseFontSize * 1.05, weight: primaryFontWeight, design: .monospaced)
                : .system(size: baseFontSize * 0.85, weight: primaryFontWeight)

                // Slides: respect preview lines; Timers can use a few lines.
                let slideMax = max(1, config.maxPreviewLines)
                let maxLines: Int? = isTimerLike ? 6 : (slideMax >= 6 ? nil : slideMax)
                let useThumbnailMode = (config.slideContentMode == .thumbnail)
                let useNotesMode = (config.slideContentMode == .notes)

                let displayedText: String? = {
                    if useThumbnailMode {
                        return nil
                    }
                    if useNotesMode {
                        if let notes = state.status.slideNotes, !notes.isEmpty {
                            return notes
                        }
                        return nil
                    }
                    if let text = state.status.slideText, !text.isEmpty {
                        if config.dataMode == .timersCurrent, connected {
                            let sel = (config.selectedTimerUUID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !sel.isEmpty,
                               let match = state.lastTimers.first(where: { $0.id == sel }) {
                                return timerLine(match)
                            }
                        }
                        return text
                    }
                    return nil
                }()

	                let fallbackText: String = {
	                    if config.dataMode.isSlideMode {
	                        if useThumbnailMode {
	                            return "Thumbnail unavailable"
	                        }
	                        return currentSlideFallbackText
	                    }
                    if config.dataMode == .timerVideoCountdown {
                        return "No countdown selected"
                    }
                    if config.dataMode == .timersCurrent {
                        return "No timers available"
                    }
                    return "No data yet."
                }()

				if useThumbnailMode, let thumbnail = resolvedCurrentThumbnail {
						ProPresenterInfoCard(
							title: primaryTitle,
							text: "",
							font: font,
							maxLines: 1,
							textColor: resolvedPrimaryColor,
							titleColor: resolvedSecondaryColor,
							titleLeadingColor: nil,
							headerBackgroundColor: showHeaderBar ? headerBarColor : nil,
							headerPillColor: showHeaderBar ? headerPillColor : nil,
							headerGroupText: showHeaderBar ? headerGroupTextForLayout : nil,
							headerGroupColor: headerGroupColorForLayout,
                            headerAccessoryText: showHeaderBar ? headerInfo : nil,
                            headerAccessoryColor: headerTextColorForLayout,
                            headerTextColor: headerTextColorForLayout,
                            headerFont: headerFont,
                            thumbnailImage: thumbnail,
                            textAlignment: resolvedTextAlignment,
                            horizontalAlignment: resolvedHorizontalAlignment,
							fixedHeight: isTimerLike ? nil : currentCardHeight,
							flashEnabled: messageFlashEnabled,
							flashColor: messageFlashColor,
							flashStartDate: messageFlashStartDate,
							flashRepeatCount: messageFlashRepeatCount,
							flashIndefinite: messageFlashIndefinite
						)
					} else if let text = displayedText, !text.isEmpty {
					ProPresenterInfoCard(
						title: primaryTitle,
						text: applyCapitalization(text),
						font: font,
						maxLines: maxLines,
                        textColor: resolvedPrimaryColor,
                        titleColor: resolvedSecondaryColor,
                        titleLeadingColor: nil,
                        headerBackgroundColor: showHeaderBar ? headerBarColor : nil,
                        headerPillColor: showHeaderBar ? headerPillColor : nil,
                        headerGroupText: showHeaderBar ? headerGroupTextForLayout : nil,
                        headerGroupColor: headerGroupColorForLayout,
                    headerAccessoryText: showHeaderBar ? headerInfo : nil,
                    headerAccessoryColor: headerTextColorForLayout,
                    headerTextColor: headerTextColorForLayout,
                    headerFont: headerFont,
                    thumbnailImage: resolvedCurrentThumbnail,
                    textAlignment: resolvedTextAlignment,
                    horizontalAlignment: resolvedHorizontalAlignment,
                    fixedHeight: isTimerLike ? nil : currentCardHeight,
                    flashEnabled: messageFlashEnabled,
                    flashColor: messageFlashColor,
                    flashStartDate: messageFlashStartDate,
                    flashRepeatCount: messageFlashRepeatCount,
                    flashIndefinite: messageFlashIndefinite
                )
            } else if connected {
                ProPresenterInfoCard(
						title: primaryTitle,
						text: applyCapitalization(fallbackText),
						font: font,
						maxLines: maxLines,
                        textColor: resolvedPrimaryColor,
                        titleColor: resolvedSecondaryColor,
                        titleLeadingColor: nil,
                        headerBackgroundColor: showHeaderBar ? headerBarColor : nil,
                        headerPillColor: showHeaderBar ? headerPillColor : nil,
                        headerGroupText: showHeaderBar ? headerGroupTextForLayout : nil,
                        headerGroupColor: headerGroupColorForLayout,
                    headerAccessoryText: showHeaderBar ? headerInfo : nil,
                    headerAccessoryColor: headerTextColorForLayout,
                    headerTextColor: headerTextColorForLayout,
                    headerFont: headerFont,
                    thumbnailImage: resolvedCurrentThumbnail,
                    textAlignment: resolvedTextAlignment,
                    horizontalAlignment: resolvedHorizontalAlignment,
                    fixedHeight: isTimerLike ? nil : currentCardHeight,
                    flashEnabled: messageFlashEnabled,
                    flashColor: messageFlashColor,
                    flashStartDate: messageFlashStartDate,
                    flashRepeatCount: messageFlashRepeatCount,
                    flashIndefinite: messageFlashIndefinite
                )
                }
            } else if !connected {
                let message = (state.lastError?.isEmpty == false) ? state.lastError! : "Connection error."
                ProPresenterInfoCard(
                    title: applyCapitalization(config.dataMode.primaryLabel),
                    text: applyCapitalization(message),
                    font: .system(size: baseFontSize * 0.85, weight: primaryFontWeight),
                    maxLines: 3,
                    textColor: resolvedPrimaryColor,
                    titleColor: resolvedSecondaryColor,
                    textAlignment: resolvedTextAlignment,
                    horizontalAlignment: resolvedHorizontalAlignment
                )
            }

            if config.dataMode == .stageMessage, let messageLastReceivedText {
                Text(messageLastReceivedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Next preview (slides only)
            if config.dataMode.supportsNextPreview {
                if config.slideContentMode == .thumbnail {
                    if let thumbnail = resolvedNextThumbnail {
                        let nextHeaderTitle = showHeaderBar ? "Next" : applyCapitalization("Next")
                        ProPresenterInfoCard(
                            title: nextHeaderTitle,
                            text: "",
                            font: .system(size: baseFontSize * 0.75, weight: .regular),
                            maxLines: 1,
                            textColor: resolvedPrimaryColor,
                            titleColor: resolvedSecondaryColor,
                            headerBackgroundColor: showHeaderBar ? nextHeaderBarColor : nil,
                            headerPillColor: showHeaderBar ? headerPillColor : nil,
                            headerGroupText: showHeaderBar ? nextHeaderGroupTextForLayout : nil,
                            headerGroupColor: nextHeaderGroupColorForLayout,
                            headerAccessoryText: showHeaderBar ? nextHeaderInfo : nil,
                            headerAccessoryColor: headerTextColorForLayout,
                            headerTextColor: headerTextColorForLayout,
                            headerFont: headerFont,
                            thumbnailImage: thumbnail,
                            textAlignment: resolvedTextAlignment,
                            horizontalAlignment: resolvedHorizontalAlignment,
                            fixedHeight: nextCardHeight
                        )
                    }
                } else if config.slideContentMode == .notes,
                          let nextNotes = state.status.nextSlideNotes {
                    let slideMax = max(1, config.maxPreviewLines)
                    let nextMaxLines: Int? = (slideMax >= 6 ? nil : slideMax)

	                    let nextHeaderTitle = showHeaderBar ? "Next" : applyCapitalization("Next")
	                    let nextDisplayText: String = {
	                        if nextNotes.isEmpty { return nextSlideFallbackText }
	                        return applyCapitalization(nextNotes)
	                    }()
                    ProPresenterInfoCard(
                        title: nextHeaderTitle,
                        text: nextDisplayText,
                        font: .system(size: baseFontSize * 0.75, weight: .regular),
                        maxLines: nextMaxLines,
                        textColor: resolvedPrimaryColor,
                        titleColor: resolvedSecondaryColor,
                        headerBackgroundColor: showHeaderBar ? nextHeaderBarColor : nil,
                        headerPillColor: showHeaderBar ? headerPillColor : nil,
                        headerGroupText: showHeaderBar ? nextHeaderGroupTextForLayout : nil,
                        headerGroupColor: nextHeaderGroupColorForLayout,
                        headerAccessoryText: showHeaderBar ? nextHeaderInfo : nil,
                        headerAccessoryColor: headerTextColorForLayout,
                        headerTextColor: headerTextColorForLayout,
                        headerFont: headerFont,
                        thumbnailImage: resolvedNextThumbnail,
                        textAlignment: resolvedTextAlignment,
                        horizontalAlignment: resolvedHorizontalAlignment,
                        fixedHeight: nextCardHeight
                    )
                } else if let next = state.status.nextSlideText {
                    // Match primary slide truncation behavior.
                    let slideMax = max(1, config.maxPreviewLines)
                    let nextMaxLines: Int? = (slideMax >= 6 ? nil : slideMax)

	                    let nextHeaderTitle = showHeaderBar ? "Next" : applyCapitalization("Next")
	                    let nextDisplayText: String = {
	                        if next.isEmpty { return nextSlideFallbackText }
	                        return applyCapitalization(next)
	                    }()
                    ProPresenterInfoCard(
                        title: nextHeaderTitle,
                        text: nextDisplayText,
                        font: .system(size: baseFontSize * 0.75, weight: .regular),
                        maxLines: nextMaxLines,
                        textColor: resolvedPrimaryColor,
                        titleColor: resolvedSecondaryColor,
                        headerBackgroundColor: showHeaderBar ? nextHeaderBarColor : nil,
                        headerPillColor: showHeaderBar ? headerPillColor : nil,
                        headerGroupText: showHeaderBar ? nextHeaderGroupTextForLayout : nil,
                        headerGroupColor: nextHeaderGroupColorForLayout,
                        headerAccessoryText: showHeaderBar ? nextHeaderInfo : nil,
                        headerAccessoryColor: headerTextColorForLayout,
                        headerTextColor: headerTextColorForLayout,
                        headerFont: headerFont,
                        thumbnailImage: resolvedNextThumbnail,
                        textAlignment: resolvedTextAlignment,
                        horizontalAlignment: resolvedHorizontalAlignment,
                        fixedHeight: nextCardHeight
                    )
                }
            }

            // Optional debug (per data mode)
            if config.showDebugInfo {
                if let req = state.lastRequestDescription, !req.isEmpty {
                    Text(req)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                if let resp = state.lastResponseSummary, !resp.isEmpty {
                    Text(resp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                if let err = state.lastError, !err.isEmpty {
                    let shouldShowError = config.dataMode.isSlideMode || err != "No active presentation"
                    if shouldShowError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                }

                switch config.dataMode {
                case .slideCurrentNext, .slideCurrentOnly, .slideNextOnly:
                    if let presReq = state.lastPresentationRequest, !presReq.isEmpty {
                        Text(presReq)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    if let presErr = state.lastPresentationError, !presErr.isEmpty {
                        Text("Presentation name: \(presErr)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }

                    if let presJSON = state.lastPresentationJSONPreview, !presJSON.isEmpty {
                        Text(presJSON)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(10)
                    }

                    if let totalReq = state.lastSlideTotalRequest, !totalReq.isEmpty {
                        Text(totalReq)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    if let totalErr = state.lastSlideTotalError, !totalErr.isEmpty {
                        Text("Slide total: \(totalErr)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }

                    if let totalJSON = state.lastSlideTotalJSONPreview, !totalJSON.isEmpty {
                        Text(totalJSON)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(10)
                    }

                    if let summary = state.lastGroupSummary, !summary.isEmpty {
                        Text("Group ranges: \(summary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }

                    let rawIndex = state.status.slideIndex
                    let apiSlideIndex = state.lastAPISlideIndex
                    let resolvedDisplay = displayIndex(for: state.status, state: state)
                    let groupName = state.status.groupName ?? "(nil)"
                    Text("Slide index: \(rawIndex.map(String.init) ?? "nil")  API: \(apiSlideIndex.map(String.init) ?? "nil")  Display: \(resolvedDisplay.map(String.init) ?? "nil")  Group: \(groupName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    let slideUUID = state.status.slideUUID ?? "(nil)"
                    let uuidMatch = state.status.slideUUID.map { uuid in
                        state.lastGroupRanges.contains { $0.slideUUIDs.contains(uuid) }
                    }
                    let uuidMatchText = uuidMatch == nil ? "nil" : (uuidMatch! ? "yes" : "no")
                    Text("Slide UUID: \(slideUUID)  UUID match: \(uuidMatchText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    if connected,
                       (state.status.slideText == nil || state.status.slideText?.isEmpty == true),
                       (state.status.nextSlideText == nil || state.status.nextSlideText?.isEmpty == true),
                       let preview = state.lastJSONPreview,
                       !preview.isEmpty {
                        Text(preview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(10)
                    }

                case .timersCurrent, .timerVideoCountdown, .stageMessage:
                    if config.dataMode == .stageMessage {
                        Text("Message target: \(config.messageTarget.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                        if let messageText = state.status.slideText?.trimmingCharacters(in: .whitespacesAndNewlines), !messageText.isEmpty {
                            Text("Message text: \(messageText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                        } else if config.messageTarget == .stage,
                                  let previewText = unwrapMessagePreview(state.lastJSONPreview),
                                  !previewText.isEmpty {
                            Text("Message text: \(previewText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                    if let preview = state.lastJSONPreview, !preview.isEmpty {
                        Text(preview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(10)
                    }
                }
            }
            if !effectiveLiveMode {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                    Text("Updates paused · Enable live mode")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
            }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: probeIcon)
                        .foregroundStyle(probeColor)
                    Text(probeStatusText)
                        .font(.system(size: baseFontSize * 0.7))
                        .foregroundStyle(probeColor)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .onAppear {
            guard !isLANSnapshotRendering else { return }
            if effectiveLiveMode {
                service.startPolling(moduleID: moduleID, config: config, ownerID: pollingOwnerID)
            } else {
                startProbe()
            }
        }
        .onChange(of: isLiveMode, initial: false) { _, newLive in
            guard !isLANSnapshotRendering else { return }
            if newLive || liveModeEnabled {
                cancelProbe()
                service.startPolling(moduleID: moduleID, config: config, ownerID: pollingOwnerID)
            } else {
                service.stopPolling(moduleID: moduleID, ownerID: pollingOwnerID)
                startProbe()
            }
        }
        .onChange(of: liveModeEnabled, initial: false) { _, newLive in
            guard !isLANSnapshotRendering else { return }
            if newLive || isLiveMode {
                cancelProbe()
                service.startPolling(moduleID: moduleID, config: config, ownerID: pollingOwnerID)
            } else {
                service.stopPolling(moduleID: moduleID, ownerID: pollingOwnerID)
                startProbe()
            }
        }
        .onChange(of: config.dataMode, initial: false) { _, _ in
            service.setConfig(moduleID: moduleID, config: config)
            if effectiveLiveMode, !isLANSnapshotRendering {
                service.startPolling(moduleID: moduleID, config: config, ownerID: pollingOwnerID)
            }
            if config.dataMode != .stageMessage {
                lastStageMessageText = ""
                lastAudienceMessageText = ""
                stageFlashStart = nil
                audienceFlashStart = nil
            }
        }
        .onChange(of: config.connectionProfileID, initial: false) { _, _ in
            service.setConfig(moduleID: moduleID, config: config)
            guard !isLANSnapshotRendering else { return }
            if effectiveLiveMode {
                service.startPolling(moduleID: moduleID, config: config, ownerID: pollingOwnerID)
            } else {
                startProbe()
            }
        }
        .onChange(of: config.pollIntervalOverride, initial: false) { _, _ in
            service.setConfig(moduleID: moduleID, config: config)
            if effectiveLiveMode, !isLANSnapshotRendering {
                service.startPolling(moduleID: moduleID, config: config, ownerID: pollingOwnerID)
            }
        }
        .onChange(of: config.selectedTimerUUID, initial: false) { _, _ in
            service.setConfig(moduleID: moduleID, config: config)
        }
        .onChange(of: state.status.slideText, initial: false) { _, newValue in
            guard config.dataMode == .stageMessage else { return }
            handleMessageChange(text: newValue ?? "", target: config.messageTarget)
        }
        .onChange(of: config.messageTarget, initial: false) { _, newValue in
            guard config.dataMode == .stageMessage else { return }
            let text = state.status.slideText ?? ""
            handleMessageChange(text: text, target: newValue)
        }
        .onChange(of: config.stageMessageFlashEnabled, initial: false) { _, enabled in
            guard config.dataMode == .stageMessage else { return }
            if enabled {
                handleMessageChange(text: state.status.slideText ?? "", target: .stage)
            } else {
                stageFlashStart = nil
            }
        }
        .onChange(of: config.audienceMessageFlashEnabled, initial: false) { _, enabled in
            guard config.dataMode == .stageMessage else { return }
            if enabled {
                handleMessageChange(text: state.status.slideText ?? "", target: .audience)
            } else {
                audienceFlashStart = nil
            }
        }
        .onDisappear {
            guard !isLANSnapshotRendering else { return }
            service.stopPolling(moduleID: moduleID, ownerID: pollingOwnerID)
            cancelProbe()
        }
        .onAppear {
            seedConfigIfNeeded()
            if config.dataMode == .stageMessage {
                handleMessageChange(text: state.status.slideText ?? "", target: config.messageTarget)
            }
        }
    }
}

// MARK: - Edit UI (module settings in your edit panel)

struct ProPresenterModuleEditView: View {
    let moduleID: UUID
    @ObservedObject var service: ProPresenterService
    @Binding var config: ProPresenterModuleConfig

    init(moduleID: UUID, service: ProPresenterService = ProPresenterModulePlugin.sharedService, config: Binding<ProPresenterModuleConfig>) {
        self.moduleID = moduleID
        self.service = service
        self._config = config
    }

    // Saved profiles store (written by DashboardProPresenterSettingsView)
    @AppStorage("propresenter_profiles") private var profilesData: Data = Data()

    private var profiles: [ProPresenterConnectionProfile] {
        guard !profilesData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ProPresenterConnectionProfile].self, from: profilesData)) ?? []
    }

    private var sortedProfiles: [ProPresenterConnectionProfile] {
        profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func preferredProfileID() -> UUID? {
        if let activeID = ProPresenterProfilesStore.activeProfileID(),
           sortedProfiles.contains(where: { $0.id == activeID }) {
            return activeID
        }
        return sortedProfiles.first?.id
    }

    private func hasValidSelectedProfile(_ profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return profiles.contains(where: { $0.id == profileID })
    }

    private func seedSelectedProfileIfNeeded() {
        guard !hasValidSelectedProfile(config.connectionProfileID),
              let preferredProfileID = preferredProfileID() else { return }
        config.connectionProfileID = preferredProfileID
    }

    private func resolvedProfileDisplayForEdit() -> String {
        if let id = config.connectionProfileID,
           let p = profiles.first(where: { $0.id == id }) {
            return p.name
        }
        return sortedProfiles.isEmpty ? "No Profile Selected" : "Missing Profile"
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func previewLinesRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                config.maxPreviewLines = max(1, config.maxPreviewLines - 1)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)

            Text("\(config.maxPreviewLines)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            Button {
                config.maxPreviewLines = min(6, config.maxPreviewLines + 1)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            VStack(alignment: .leading, spacing: 8) {
                Text("Connection")
                    .font(.headline)

                HStack {
                    Text("Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(
                        "",
                        selection: Binding<String>(
                            get: {
                                if let id = config.connectionProfileID,
                                   profiles.contains(where: { $0.id == id }) {
                                    return id.uuidString
                                }
                                return sortedProfiles.first?.id.uuidString ?? ""
                            },
                            set: { newValue in
                                config.connectionProfileID = UUID(uuidString: newValue)
                            }
                        )
                    ) {
                        ForEach(sortedProfiles) { p in
                            Text(p.name).tag(p.id.uuidString)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .disabled(sortedProfiles.isEmpty)
                }

                if sortedProfiles.isEmpty {
                    Text("Create a ProPresenter connection profile in Settings before using this module.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Display")
                    .font(.headline)

                HStack {
                    Text("Type")
                    Spacer()
                    Picker("", selection: $config.dataMode) {
                        ForEach(ProPresenterDataMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                Text("This controls which ProPresenter endpoint the module polls (slides, timers, etc.).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

				// Timers picker (only in settings UI)
				if config.dataMode == .timersCurrent {
                    let timers = service.stateByModuleID[moduleID]?.lastTimers ?? []

                    HStack {
                        Text("Timer")
                        Spacer()
                        Picker(
                            "",
                            selection: Binding<String>(
                                get: { config.selectedTimerUUID ?? "" },
                                set: { newValue in
                                    config.selectedTimerUUID = newValue.isEmpty ? nil : newValue
                                }
                            )
                        ) {
                            Text("All Timers").tag("")
                            ForEach(timers) { t in
                                Text(t.name ?? t.uuid ?? "Timer").tag(t.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220)
                    }

                    if timers.isEmpty {
                        Text("No timers detected yet. (The module must be connected and polling Timers.)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
				}

				if config.dataMode == .stageMessage {
                    HStack {
                        Text("Message target")
                        Spacer()
                        Picker("", selection: $config.messageTarget) {
                            ForEach(ProPresenterMessageTarget.allCases) { target in
                                Text(target.displayName).tag(target)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }

                    let isStageTarget = config.messageTarget == .stage
                    let flashEnabledBinding = Binding<Bool>(
                        get: { isStageTarget ? config.stageMessageFlashEnabled : config.audienceMessageFlashEnabled },
                        set: { newValue in
                            if isStageTarget {
                                config.stageMessageFlashEnabled = newValue
                            } else {
                                config.audienceMessageFlashEnabled = newValue
                            }
                        }
                    )
                    let flashColorBinding = Binding<Color>(
                        get: {
                            let color = isStageTarget ? config.stageMessageFlashColor : config.audienceMessageFlashColor
                            return color?.swiftUIColor ?? .red
                        },
                        set: { newValue in
                            let codable = CodableColor(newValue)
                            if isStageTarget {
                                config.stageMessageFlashColor = codable
                            } else {
                                config.audienceMessageFlashColor = codable
                            }
                        }
                    )
                    let flashRepeatBinding = Binding<Int>(
                        get: {
                            isStageTarget ? config.stageMessageFlashRepeatCount : config.audienceMessageFlashRepeatCount
                        },
                        set: { newValue in
                            let clamped = max(1, newValue)
                            if isStageTarget {
                                config.stageMessageFlashRepeatCount = clamped
                            } else {
                                config.audienceMessageFlashRepeatCount = clamped
                            }
                        }
                    )
                    let flashIndefiniteBinding = Binding<Bool>(
                        get: { isStageTarget ? config.stageMessageFlashIndefinite : config.audienceMessageFlashIndefinite },
                        set: { newValue in
                            if isStageTarget {
                                config.stageMessageFlashIndefinite = newValue
                            } else {
                                config.audienceMessageFlashIndefinite = newValue
                            }
                        }
                    )

                    toggleRow("Flash text", isOn: flashEnabledBinding)

                    ColorPicker("Flash color", selection: flashColorBinding, supportsOpacity: false)
                        .disabled(!flashEnabledBinding.wrappedValue)

                    HStack {
                        Text("Flash repeats")
                        Spacer()
                        Text("\(flashRepeatBinding.wrappedValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper(value: flashRepeatBinding, in: 1...20, step: 1) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                    .disabled(!flashEnabledBinding.wrappedValue || flashIndefiniteBinding.wrappedValue)

                    toggleRow("Repeat indefinitely", isOn: flashIndefiniteBinding)
                        .disabled(!flashEnabledBinding.wrappedValue)
				}
				if config.dataMode != .stageMessage {
											if config.dataMode == .slideCurrentNext || config.dataMode == .slideCurrentOnly || config.dataMode == .slideNextOnly {
							HStack {
								Text("Slide content")
								Spacer()
								Picker("", selection: $config.slideContentMode) {
									ForEach(ProPresenterSlideContentMode.allCases) { mode in
										Text(mode.displayName).tag(mode)
									}
								}
								.pickerStyle(.segmented)
								.frame(maxWidth: 220)
							}
						}
						toggleRow("Show presentation name", isOn: $config.showPresentationName)
					toggleRow("Show arrangement name", isOn: $config.showArrangementName)
						.disabled(!config.showPresentationName)
				}
				if config.dataMode == .slideCurrentNext || config.dataMode == .slideCurrentOnly || config.dataMode == .slideNextOnly {
					toggleRow("Show slide numbers", isOn: $config.showSlideNumbers)
					toggleRow("Show group name", isOn: $config.showGroupName)
					toggleRow("Show group color", isOn: $config.showGroupColor)
					if config.slideContentMode != .thumbnail {
                        previewLinesRow("Preview lines")
                    }
				}
                    #if DEBUG || BETA
					toggleRow("Show debug info", isOn: $config.showDebugInfo)
                    #endif
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .onAppear {
            seedSelectedProfileIfNeeded()
        }
        .onChange(of: profilesData, initial: false) { _, _ in
            seedSelectedProfileIfNeeded()
        }
    }
}
// MARK: - Module Plugin Wrapper

struct ProPresenterModulePlugin: DashboardModulePlugin {
    static let sharedService = ProPresenterService()

    static var kind: DashboardModuleKind { .proPresenter }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let cfgBinding = Binding<ProPresenterModuleConfig>(
            get: { module.wrappedValue.proPresenterConfig ?? ProPresenterModuleConfig() },
            set: { module.wrappedValue.proPresenterConfig = $0 }
        )
        var cfg = module.wrappedValue.proPresenterConfig ?? ProPresenterModuleConfig()
        if cfg.id != module.wrappedValue.id {
            cfg.id = module.wrappedValue.id
        }

        sharedService.setConfig(moduleID: module.wrappedValue.id, config: cfg)
        return AnyView(ProPresenterModuleView(moduleID: module.wrappedValue.id, config: cfgBinding, service: sharedService, isLiveMode: isLiveMode))
    }
    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("ProPresenter")
                    .font(.headline)
                Text("Manage ProPresenter profiles in Settings → ProPresenter. Select a profile per module in the inspector.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        )
    }
}
