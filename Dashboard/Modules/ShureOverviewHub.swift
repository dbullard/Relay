import Foundation
import Combine

/// Whether an overview channel represents a microphone receiver channel
/// or an in-ear-monitor (IEM) transmitter channel. Drives both tab
/// placement and audio-level bucketing.
enum ShureOverviewChannelKind: String {
    case mic
    case iem
}

/// How much detail an overview tile wants for its per-channel audio
/// activity indicator, and therefore how fast the underlying device
/// telemetry needs to refresh. Ordered cheapest-to-most-demanding so the
/// Hub can reconcile multiple tiles by taking the max.
enum ShureOverviewAudioActivityMode: Int, Codable, CaseIterable, Hashable, Comparable {
    case off
    case signalLight
    case meter

    static func < (lhs: ShureOverviewAudioActivityMode, rhs: ShureOverviewAudioActivityMode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension ShureOverviewAudioActivityMode {
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .signalLight: return "Signal light"
        case .meter: return "Meter"
        }
    }
}

/// Reconciles every currently-live overview tile's requested audio activity
/// mode into the single mode the Hub actually runs at. `ShureOverviewHub`
/// applies one Hub-wide telemetry rate to every device (see
/// `applyRateTiers`), so if any live tile wants `.meter`, the whole Hub
/// runs at the meter rate.
enum ShureOverviewAudioModeReconciler {
    static func effectiveMode(
        requestedModes: [UUID: ShureOverviewAudioActivityMode],
        liveInstances: Set<UUID>
    ) -> ShureOverviewAudioActivityMode {
        requestedModes
            .filter { liveInstances.contains($0.key) }
            .values
            .max() ?? .off
    }
}

/// Flags real, measured strain using diagnostics the app already collects
/// (`ShureWirelessService`'s per-device `ShureTelemetryDiagnosticsSnapshot`),
/// instead of an invented channel-count ceiling. Strained when the measured
/// parse+snapshot-build time is eating too much of the polling budget, or
/// when the device is actively dropping coalesced telemetry updates.
enum ShureOverviewPerformanceStrainEvaluator {
    static let busyBudgetFraction: Double = 0.7

    // At high channel counts in meter mode, per-channel updates routinely
    // arrive faster than the shared snapshot-publish interval and get
    // folded together rather than lost -- that's intentional coalescing,
    // not overload, and it produces a small but constantly-climbing
    // "dropped" count even on a perfectly healthy rig (observed up to
    // ~80/sec on a real 44-channel session where parse/snapshot time was
    // nowhere near budget). Flagging on any increase at all made the
    // banner show up essentially always once channel count got high
    // enough. Only treat it as strain once the rate is well past what
    // routine coalescing produces.
    static let droppedPerSecondStrainThreshold: Double = 150

    static func isStrained(
        diagnostics: ShureTelemetryDiagnosticsSnapshot,
        pollingIntervalSeconds: TimeInterval,
        previousDroppedCount: Int,
        elapsedSeconds: TimeInterval
    ) -> Bool {
        let budgetMilliseconds = pollingIntervalSeconds * 1000
        let busyMilliseconds = diagnostics.averageParseTimeMilliseconds + diagnostics.averageSnapshotBuildTimeMilliseconds
        if busyMilliseconds > budgetMilliseconds * busyBudgetFraction {
            return true
        }
        guard elapsedSeconds > 0 else { return false }
        let newDrops = diagnostics.droppedCoalescedUpdateCount - previousDroppedCount
        guard newDrops > 0 else { return false }
        return Double(newDrops) / elapsedSeconds > droppedPerSecondStrainThreshold
    }
}

/// Maps a raw `ShureTelemetryChannelSnapshot.audioLevel` into a coarse
/// 0-5 "segment count" for the overview's audio activity bar.
///
/// Mic receivers report `AUDIO_LVL` in a small ~0-20 range, so a linear
/// scale is used. PSM/IEM transmitters report `AUDIO_IN_LVL_*` across a
/// much wider range (often tens of thousands), so a log10 scale is used,
/// matching the banding already used by `psmAudioBarCount` in
/// `ShureWirelessModule.swift`, scaled down from 0-8 to 0-5.
enum ShureOverviewAudioBucket {
    /// Total meter segments, shared by Overview and the single-tile mic
    /// meter. The last one is the dedicated clip/overage segment (driven by
    /// the receiver's own clip bit, never by level), so `levelSegmentCount`
    /// segments carry the actual level.
    static let segmentCount = 10
    static let levelSegmentCount = segmentCount - 1

    /// Fraction of the 0-20 normalized mic scale that is treated as the
    /// meter's floor. Axient reports dBFS + 120 scaled onto 0-20, so 0.5 is
    /// -60 dBFS: everything quieter (room noise, idle hiss) shows nothing
    /// instead of climbing through the bottom half of the meter, which made
    /// normal speech read 1-2 segments hotter than a console.
    static let micFloorFraction = 0.5

    static func micSegments(level: Double) -> Int {
        guard level.isFinite, level > 0 else { return 0 }
        let normalized = min(max(level / 20.0, 0.0), 1.0)
        let aboveFloor = max(normalized - micFloorFraction, 0.0) / (1.0 - micFloorFraction)
        return Int((aboveFloor * Double(levelSegmentCount)).rounded())
    }

    static func bucket(level: Double?, isMuted: Bool, kind: ShureOverviewChannelKind) -> Int {
        guard !isMuted, let level, level.isFinite, level > 0 else { return 0 }

        switch kind {
        case .mic:
            return micSegments(level: level)
        case .iem:
            let logMin: Double = 2.0
            let logMax: Double = 6.0
            let logVal = log10(max(level, pow(10.0, logMin)))
            let ratio = (logVal - logMin) / (logMax - logMin)
            let normalized = min(max(ratio, 0.0), 1.0)
            return Int((normalized * Double(levelSegmentCount)).rounded())
        }
    }
}

/// Translates the total number of overview channels across all eligible
/// Shure devices, plus the Hub-wide reconciled `ShureOverviewAudioActivityMode`,
/// into the device-side `METER_RATE` (milliseconds) and the fallback
/// `SAMPLE 0 ALL` polling/publish interval (seconds) the overview should
/// request.
///
/// Signal light (and Off, which needs the same underlying battery/RF/name/
/// status cadence but no audio granularity) uses a cheaper table than
/// today's previous default, since a live/not-live dot tolerates coarser
/// sampling than a 5-segment bar. Meter uses a faster table than today's
/// previous default, funded by that headroom. Both tables still back off
/// as channel count grows, to keep parse/render load flat; Meter's worst
/// case (500ms) stays well under the 1000ms top tier that prompted this
/// work. These numbers are a starting point — validate them against
/// `ShureTelemetryDiagnosticsSnapshot` on a real or simulated large rig
/// rather than treating them as final.
enum ShureOverviewRateTier {
    static func meterRateMilliseconds(forTotalChannelCount count: Int, mode: ShureOverviewAudioActivityMode) -> Int {
        switch mode {
        case .off, .signalLight:
            switch count {
            case ...8: return 300
            case 9...16: return 600
            case 17...24: return 900
            default: return 1200
            }
        case .meter:
            switch count {
            case ...8: return 100
            case 9...16: return 200
            case 17...24: return 350
            default: return 500
            }
        }
    }

    static func overviewPollingInterval(forTotalChannelCount count: Int, mode: ShureOverviewAudioActivityMode) -> TimeInterval {
        switch mode {
        case .off, .signalLight:
            switch count {
            case ...8: return 0.4
            case 9...16: return 0.6
            case 17...24: return 0.9
            default: return 1.2
            }
        case .meter:
            switch count {
            case ...8: return 0.15
            case 9...16: return 0.3
            case 17...24: return 0.45
            default: return 0.6
            }
        }
    }
}

/// Chooses one due Axient channel at a time so the Overview can compensate
/// for receivers that accept `METER_RATE` but do not publish usable meter
/// frames continuously. Ordering by oldest poll keeps the extra RMS requests
/// evenly distributed rather than sending a burst for every channel at once.
enum ShureAxientOverviewMeterPollScheduler {
    static func nextChannel(
        among channels: [Int],
        lastPolledAt: [Int: Date],
        now: Date,
        minimumInterval: TimeInterval
    ) -> Int? {
        channels
            .sorted()
            .filter { channelIndex in
                guard let lastPolled = lastPolledAt[channelIndex] else { return true }
                return now.timeIntervalSince(lastPolled) >= minimumInterval
            }
            .min { lhs, rhs in
                let lhsDate = lastPolledAt[lhs] ?? .distantPast
                let rhsDate = lastPolledAt[rhs] ?? .distantPast
                if lhsDate == rhsDate { return lhs < rhs }
                return lhsDate < rhsDate
            }
    }
}

/// Instance-agnostic per-channel telemetry computed once by
/// `ShureOverviewHub` and shared by every `ShureOverviewModuleView`
/// instance. Per-tile concerns (device scope, thresholds, sort order,
/// hide-offline) are layered on top by `ShureOverviewViewModel`.
struct ShureOverviewRawChannel: Identifiable, Equatable {
    let id: String
    let deviceID: UUID
    let deviceName: String
    let channelIndex: Int
    let kind: ShureOverviewChannelKind
    let userAssignedName: String?
    let discoveredName: String?
    let fallbackName: String
    let displayName: String
    let normalizedSortName: String
    let frequency: String?
    let batteryPercent: Int?
    let rfBars: Int?
    let audioBucket: Int
    let audioOverload: Bool
    let transmitterState: ShureTelemetryTransmitterState
    let transmitterPresent: Bool?
    let isConnected: Bool
    let isReconnecting: Bool
    let isTransmitterOff: Bool
    let isWarmupActive: Bool
    let lastTelemetry: Date?
}

/// Singleton source of truth for raw, per-channel Shure telemetry across
/// every eligible device. Owns a single overview-consumer registration per
/// `ShureWirelessService` so any number of `ShureOverviewModuleView`
/// instances share one subscription, one recompute pipeline, and one
/// dynamic METER_RATE/polling-rate decision per device.
@MainActor
final class ShureOverviewHub: ObservableObject {
    static let shared = ShureOverviewHub()

    @Published private(set) var rawChannels: [ShureOverviewRawChannel] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var blinkPhase: Bool = false
    @Published private(set) var effectiveAudioMode: ShureOverviewAudioActivityMode = .off
    @Published private(set) var isPerformanceStrained: Bool = false

    private let store = ExternalDevicesStore.shared
    private var services: [UUID: ShureWirelessService] = [:]
    private var deviceSnapshots: [UUID: ShureTelemetryDeviceSnapshot] = [:]
    private var serviceTokens: [UUID: AnyCancellable] = [:]
    private let consumerID = UUID()
    private var storeToken: AnyCancellable?
    private var recomputeToken: AnyCancellable?
    private var staleSweepTimer: AnyCancellable?
    private let recomputeSubject = PassthroughSubject<Void, Never>()
    private var currentThrottleInterval: TimeInterval = 0.3
    /// The channel-count-scaled tier value from the last applyRateTiers
    /// call -- the throttle interval used whenever nothing is currently
    /// "on". refreshThrottleIntervalForActivity() picks between this and
    /// the fast single-tile-equivalent rate.
    private var baseThrottleInterval: TimeInterval = 0.3
    private var previousDroppedCounts: [UUID: Int] = [:]
    private var previousStrainCheckAt: Date?
    /// Minimum span between drop-rate strain evaluations, independent of
    /// how often recompute() itself runs. recompute() is throttled to
    /// currentThrottleInterval, which can be as short as 0.2s whenever a
    /// channel-detail tile is open -- computing "drops per second" from
    /// whatever happened to land in one such window is extremely noisy:
    /// confirmed live on a 21+ device rig, a single 200ms tick with as few
    /// as ~30 coalesced-update drops (routine clustering, not overload --
    /// see droppedPerSecondStrainThreshold's own comment) computes as
    /// "over 150/sec" in isolation even though the sustained rate over
    /// several seconds was a fraction of that, producing exactly the
    /// randomly-flashing strain banner this was reported as. Evaluating
    /// over a longer, steadier window smooths that out while still
    /// catching genuine sustained overload within a few seconds.
    private static let minimumStrainEvaluationInterval: TimeInterval = 2.0

    private var registeredInstances: Set<UUID> = []
    private var liveInstances: Set<UUID> = []
    private var liveModeActivatedAt: Date?
    private var requestedAudioModes: [UUID: ShureOverviewAudioActivityMode] = [:]
    private let telemetryWarmupInterval: TimeInterval = 4
    private var blinkTimer: AnyCancellable?
    private static let blinkAlertStaleTimeoutSeconds: TimeInterval = 8

    private var isLive: Bool { !liveInstances.isEmpty }

    private init() {
        storeToken = store.$devices.sink { [weak self] _ in
            self?.refreshServices()
            self?.requestRecompute()
        }
        staleSweepTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.requestRecompute() }
        rebuildRecomputePipeline()
        refreshServices()
        recompute()
    }

    /// Requests a recompute. Multiple requests within the current throttle
    /// window collapse into a single recompute — this is what prevents N
    /// near-simultaneous telemetry publishes (e.g. on Live Mode entry) from
    /// triggering N full rebuilds.
    func requestRecompute() {
        recomputeSubject.send()
    }

    /// Whether at least one registered tile instance currently has Live
    /// Mode enabled. The hub connects/streams telemetry iff this is true.
    var isHubLive: Bool { isLive }

    func registerInstance(_ id: UUID) {
        registeredInstances.insert(id)
        refreshServices()
    }

    func unregisterInstance(_ id: UUID) {
        registeredInstances.remove(id)
        requestedAudioModes.removeValue(forKey: id)
        let wasLive = isLive
        liveInstances.remove(id)
        if wasLive != isLive {
            setHubLive(isLive)
        }
        refreshServices()
    }

    func setInstanceLiveMode(_ id: UUID, enabled: Bool) {
        guard registeredInstances.contains(id) else { return }
        let wasLive = isLive
        if enabled {
            liveInstances.insert(id)
        } else {
            liveInstances.remove(id)
        }
        if wasLive != isLive {
            setHubLive(isLive)
        }
        refreshServices()
    }

    /// Reports the audio activity mode a specific overview tile wants.
    /// Multiple tiles can request different modes; `applyRateTiers` reconciles
    /// them into the one Hub-wide rate via `ShureOverviewAudioModeReconciler`.
    func setInstanceAudioMode(_ id: UUID, mode: ShureOverviewAudioActivityMode) {
        guard registeredInstances.contains(id) else { return }
        guard requestedAudioModes[id] != mode else { return }
        requestedAudioModes[id] = mode
        refreshServices()
    }

    private func setHubLive(_ live: Bool) {
        liveModeActivatedAt = live ? Date() : nil
        // A fresh Live Mode activation (or turning it off) is the one clean
        // "new episode" boundary for the strain latch below -- see
        // updatePerformanceStrain for why it otherwise never auto-clears.
        isPerformanceStrained = false
        previousDroppedCounts.removeAll()
        previousStrainCheckAt = nil
        for service in services.values {
            service.setLiveModeEnabled(live)
            service.setOverviewConsumerVisible(consumerID, visible: live)
        }
        requestRecompute()
        updateBlinkTimer()
    }

    /// Runs a shared 1Hz clock that toggles `blinkPhase` only while the hub
    /// is live AND at least one channel is in an alert state (offline,
    /// stale beyond the default timeout, or with no telemetry yet outside
    /// the warmup window). With nothing to flag, the timer stops entirely —
    /// no continuous render-loop animation.
    private func updateBlinkTimer() {
        let now = Date()
        let hasAlert = isLive && rawChannels.contains { channel in
            guard !channel.isTransmitterOff else { return false }
            if !channel.isConnected { return true }
            if channel.isWarmupActive { return false }
            guard let lastTelemetry = channel.lastTelemetry else { return true }
            return now.timeIntervalSince(lastTelemetry) > Self.blinkAlertStaleTimeoutSeconds
        }

        if hasAlert {
            guard blinkTimer == nil else { return }
            blinkTimer = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.blinkPhase.toggle()
                }
        } else {
            blinkTimer?.cancel()
            blinkTimer = nil
            blinkPhase = false
        }
    }

    private func rebuildRecomputePipeline() {
        recomputeToken?.cancel()
        recomputeToken = recomputeSubject
            .throttle(for: .seconds(currentThrottleInterval), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.recompute() }
    }

    private func refreshServices() {
        let eligibleDevices = store.devices
            .filter { $0.kind == .shureWireless }
            .filter(Self.isTelemetryEligibleDevice(_:))
        let deviceIDs = Set(eligibleDevices.map(\.id))

        for removed in services.keys where !deviceIDs.contains(removed) {
            services[removed]?.removeConsumer(consumerID)
            serviceTokens[removed]?.cancel()
            serviceTokens.removeValue(forKey: removed)
            services.removeValue(forKey: removed)
            deviceSnapshots.removeValue(forKey: removed)
            previousDroppedCounts.removeValue(forKey: removed)
        }

        for device in eligibleDevices where services[device.id] == nil {
            let service = ShureWirelessService.shared(for: device.id)
            services[device.id] = service
            service.setDevice(id: device.id)
            service.setLiveModeEnabled(isLive)
            service.setOverviewConsumerVisible(consumerID, visible: isLive)
            deviceSnapshots[device.id] = service.telemetrySnapshot
            serviceTokens[device.id] = service.$telemetrySnapshot.sink { [weak self] snapshot in
                self?.deviceSnapshots[device.id] = snapshot
                self?.requestRecompute()
                self?.refreshThrottleIntervalForActivity()
            }
        }

        applyRateTiers(eligibleDevices: eligibleDevices)
    }

    /// Speeds up (or relaxes) the hub-wide recompute throttle to track
    /// whether anything on the system is actually "on" right now.
    ///
    /// Per-device request-rate and snapshot-publish speedups (see
    /// ShureWirelessService's per-channel METER_RATE and
    /// snapshotPublishInterval) don't help if this hub's own recompute --
    /// the step that actually rebuilds the rows every ShureOverviewModuleView
    /// renders -- still only fires at baseThrottleInterval, the static,
    /// total-channel-count-scaled tier value. Confirmed by a customer still
    /// seeing Overview meters far slower than the single-tile module's after
    /// both of those upstream fixes landed: this throttle sits downstream of
    /// both and was still gating everything to the slow tier regardless.
    /// Runs on every snapshot publish (cheap -- just an activity check
    /// across already-held service references) rather than only at
    /// device-list-lifecycle events, so a channel switching on/off updates
    /// this promptly instead of waiting for the next registration change.
    private func refreshThrottleIntervalForActivity() {
        let now = Date()
        let target = services.values.contains { $0.hasAnyOnChannel(now: now) }
            ? 0.15
            : baseThrottleInterval
        guard target != currentThrottleInterval else { return }
        currentThrottleInterval = target
        rebuildRecomputePipeline()
    }

    private func applyRateTiers(eligibleDevices: [ExternalDeviceConfig]) {
        let totalChannels = eligibleDevices.reduce(0) { $0 + max($1.effectiveShureChannelCount, 1) }
        let mode = ShureOverviewAudioModeReconciler.effectiveMode(
            requestedModes: requestedAudioModes,
            liveInstances: liveInstances
        )
        effectiveAudioMode = mode
        let meterRateMs = ShureOverviewRateTier.meterRateMilliseconds(forTotalChannelCount: totalChannels, mode: mode)
        let pollingInterval = ShureOverviewRateTier.overviewPollingInterval(forTotalChannelCount: totalChannels, mode: mode)

        for service in services.values {
            service.setOverviewMeterRateMilliseconds(meterRateMs)
            service.setOverviewPollingInterval(pollingInterval)
        }

        baseThrottleInterval = pollingInterval
        refreshThrottleIntervalForActivity()
    }

    private func updatePerformanceStrain(eligibleDevices: [ExternalDeviceConfig]) {
        let now = Date()
        // Skip entirely (leaving isPerformanceStrained and the dropped-count
        // baselines untouched) until enough time has passed since the last
        // evaluation -- see minimumStrainEvaluationInterval for why. The
        // very first check (previousStrainCheckAt == nil) still runs
        // immediately to establish that baseline.
        if let previousStrainCheckAt,
           now.timeIntervalSince(previousStrainCheckAt) < Self.minimumStrainEvaluationInterval {
            return
        }
        let elapsedSeconds = previousStrainCheckAt.map { now.timeIntervalSince($0) } ?? 0
        // Connection setup for every eligible device happens all at once
        // right as Live Mode turns on, which briefly inflates measured
        // parse/snapshot timing before it settles -- without this gate the
        // strain banner flagged on essentially every Live Mode start, not
        // just genuine ongoing strain. Reuses the same warmup window as
        // per-channel telemetry warmup for consistency. Baselines (dropped
        // counts) still get seeded during warmup so there's no artificial
        // spike the moment the window ends.
        let isWithinStrainWarmup: Bool = {
            guard let activatedAt = liveModeActivatedAt else { return false }
            return now.timeIntervalSince(activatedAt) < telemetryWarmupInterval
        }()
        var strained = false
        for device in eligibleDevices {
            guard let snapshot = deviceSnapshots[device.id] else { continue }
            let diagnostics = snapshot.diagnostics
            // On first observation of a device, seed the dropped-count
            // baseline to its current value rather than 0. A service can
            // already have accumulated drops before the Hub started
            // watching it (e.g. another consumer was already live); seeding
            // at 0 would make that pre-existing count look like a spike on
            // the very first recompute. The busy-time check still runs
            // normally on this first pass.
            let previousDropped = previousDroppedCounts[device.id] ?? diagnostics.droppedCoalescedUpdateCount
            if !isWithinStrainWarmup, ShureOverviewPerformanceStrainEvaluator.isStrained(
                diagnostics: diagnostics,
                pollingIntervalSeconds: currentThrottleInterval,
                previousDroppedCount: previousDropped,
                elapsedSeconds: elapsedSeconds
            ) {
                strained = true
            }
            previousDroppedCounts[device.id] = diagnostics.droppedCoalescedUpdateCount
        }
        previousStrainCheckAt = now
        // Latches: once genuinely strained, stays flagged for the rest of
        // this Live Mode session rather than auto-clearing the moment a
        // later check comes back clean. Intentional -- the point of the
        // banner is to let the user make one deliberate call (accept the
        // cost, or switch to Signal light), not to flicker in and out as
        // strain naturally comes and goes on a busy rig. The only resets
        // are a fresh Live Mode activation (setHubLive) and the user's own
        // dismiss action in the view.
        if strained {
            isPerformanceStrained = true
        }
    }

    private func recompute() {
        let now = Date()
        let eligibleDevices = store.devices
            .filter { $0.kind == .shureWireless }
            .filter(Self.isTelemetryEligibleDevice(_:))

        var built: [ShureOverviewRawChannel] = []
        for device in eligibleDevices {
            guard let snapshot = deviceSnapshots[device.id] else { continue }
            let channelCount = max(device.effectiveShureChannelCount, 1)
            let kind: ShureOverviewChannelKind = Self.isIEMDevice(device) ? .iem : .mic

            for channel in 1...channelCount {
                let channelSnapshot = snapshot.channelSnapshot(for: channel)
                let userAssignedName = Self.userAssignedChannelName(for: device, channelIndex: channel)
                let discoveredName = Self.normalizedName(channelSnapshot?.channelName)
                let fallbackName = "CH \(channel)"
                let displayName = userAssignedName ?? discoveredName ?? fallbackName
                let normalizedSortName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let transmitterState = channelSnapshot?.transmitterState ?? .unknown
                let lastTelemetry = Self.latestTelemetry(channelSnapshot: channelSnapshot, deviceSnapshot: snapshot)
                let warmupActive = isWarmupActive(now: now, lastTelemetry: lastTelemetry, snapshot: snapshot)
                let audioBucket = ShureOverviewAudioBucket.bucket(
                    level: channelSnapshot?.audioLevel,
                    isMuted: channelSnapshot?.isMuted ?? false,
                    kind: kind
                )
                // Muted mirrors audioBucket's own muted handling above --
                // showing a lit clip segment alongside an otherwise fully
                // dim (muted) meter would read as contradictory.
                let audioOverload = (channelSnapshot?.isMuted ?? false) ? false : (channelSnapshot?.audioOverload ?? false)

                built.append(
                    ShureOverviewRawChannel(
                        id: channelSnapshot?.id ?? "\(device.id.uuidString)-\(channel)",
                        deviceID: device.id,
                        deviceName: device.name,
                        channelIndex: channel,
                        kind: kind,
                        userAssignedName: userAssignedName,
                        discoveredName: discoveredName,
                        fallbackName: fallbackName,
                        displayName: displayName,
                        normalizedSortName: normalizedSortName,
                        frequency: channelSnapshot?.frequencyLabel,
                        batteryPercent: channelSnapshot?.batteryPercent,
                        rfBars: channelSnapshot?.rfBars,
                        audioBucket: audioBucket,
                        audioOverload: audioOverload,
                        transmitterState: transmitterState,
                        transmitterPresent: channelSnapshot?.transmitterPresent,
                        isConnected: snapshot.isConnected,
                        isReconnecting: snapshot.isReconnecting,
                        isTransmitterOff: transmitterState == .off,
                        isWarmupActive: warmupActive,
                        lastTelemetry: lastTelemetry
                    )
                )
            }
        }

        rawChannels = built
        lastUpdated = now
        updateBlinkTimer()
        updatePerformanceStrain(eligibleDevices: eligibleDevices)
    }

    private func isWarmupActive(now: Date, lastTelemetry: Date?, snapshot: ShureTelemetryDeviceSnapshot) -> Bool {
        guard isLive, snapshot.isConnected else { return false }
        guard let activatedAt = liveModeActivatedAt else { return false }
        let warmupExpiresAt = activatedAt.addingTimeInterval(telemetryWarmupInterval)
        guard now < warmupExpiresAt else { return false }
        guard lastTelemetry == nil || now.timeIntervalSince(activatedAt) < 2 else { return false }
        return true
    }

    private static func isIEMDevice(_ device: ExternalDeviceConfig) -> Bool {
        if let model = device.shureNetworkModel {
            switch model {
            case .p10t, .psm900, .adtd, .adtq:
                return true
            default:
                break
            }
        }
        let code = (device.shureModelIdentifier ?? "").uppercased()
        let name = device.name.uppercased()
        return code.contains("P10T") || code.contains("PSM900") || code.contains("ADTD") || code.contains("ADTQ") || name.contains("PSM")
    }

    private static func isTelemetryEligibleDevice(_ device: ExternalDeviceConfig) -> Bool {
        guard device.kind == .shureWireless else { return false }
        if let model = device.shureNetworkModel, model == .psm900 {
            return false
        }
        let code = (device.shureModelIdentifier ?? "").uppercased()
        let name = device.name.uppercased()
        if code == "PSM900" || name.contains("PSM 900") || name.contains("PSM900") {
            return false
        }
        return true
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func userAssignedChannelName(for device: ExternalDeviceConfig, channelIndex: Int) -> String? {
        if channelIndex == 1, let name = normalizedName(device.psmChannel1Name) {
            return name
        }
        if channelIndex == 2, let name = normalizedName(device.psmChannel2Name) {
            return name
        }
        return normalizedName(device.shureChannelNames[channelIndex])
    }

    private static func latestTelemetry(channelSnapshot: ShureTelemetryChannelSnapshot?, deviceSnapshot: ShureTelemetryDeviceSnapshot) -> Date? {
        [
            channelSnapshot?.lastAudioAt,
            channelSnapshot?.lastBatteryAt,
            channelSnapshot?.lastRFAt,
            channelSnapshot?.lastHeardAt,
            deviceSnapshot.lastHeardAt
        ].compactMap { $0 }.max()
    }
}
