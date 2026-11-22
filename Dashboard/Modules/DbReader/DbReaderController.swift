import Foundation
import SwiftUI
import Combine

// MARK: - Output Store

final class DbReaderOutputStore {
    static let shared = DbReaderOutputStore()
    private let queue = DispatchQueue(label: "DbReaderOutputStore")
    private var payloadByModuleId: [UUID: DbReaderOutputPayload] = [:]

    func update(moduleId: UUID, tileId: UUID, payload: DbReaderOutputPayload) {
        queue.async {
            self.payloadByModuleId[moduleId] = payload
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .dbReaderDidPublish,
                    object: nil,
                    userInfo: ["moduleId": moduleId, "tileId": tileId, "payload": payload]
                )
            }
        }
    }

    func payload(for moduleId: UUID) -> DbReaderOutputPayload {
        queue.sync { payloadByModuleId[moduleId] ?? .empty }
    }

    func clear(moduleId: UUID, tileId: UUID) {
        let payload = DbReaderOutputPayload(
            spl: 0,
            peak: 0,
            rawDbFS: 0,
            rawPeakDbFS: 0,
            weighting: .z,
            timeWeighting: .fast,
            caSlow: nil,
            timestamp: Date(),
            isStale: true
        )
        update(moduleId: moduleId, tileId: tileId, payload: payload)
    }
}

// MARK: - Controller Store (persistent per moduleId)

@MainActor
final class DbReaderControllerStore {
    static let shared = DbReaderControllerStore()
    private var controllers: [UUID: DbReaderController] = [:]

    func controller(moduleId: UUID, tileId: UUID, settings: DbReaderModuleModel) -> DbReaderController {
        if let existing = controllers[moduleId] {
            existing.updateTileId(tileId)
            existing.updateSettings(settings)
            return existing
        }
        let created = DbReaderController(moduleId: moduleId, tileId: tileId, settings: settings)
        controllers[moduleId] = created
        return created
    }

    /// Stops and forgets the controllers for modules that left a document. A meter keeps
    /// running while its tile is merely off-screen in Live Mode (it feeds automation and
    /// shared values), so deletion is the only thing that should shut it down. If the
    /// deletion is undone, the tile's view simply creates a fresh controller.
    func evict(moduleIds: Set<UUID>) {
        for id in moduleIds {
            guard let controller = controllers.removeValue(forKey: id) else { continue }
            controller.shutdown()
        }
    }
}

// MARK: - Controller

@MainActor
final class DbReaderController: ObservableObject {
    private(set) var currentSpl: Double = 0
    private(set) var currentSplSlow: Double = 0
    private(set) var currentZSlow: Double = 0
    private(set) var displaySpl: Double = 0
    private(set) var averagingProgress: Double = 0
    private(set) var currentPeak: Double = 0
    private(set) var rawDbFS: Double = 0
    private(set) var rawPeakDbFS: Double = 0
    private(set) var rawAWeightedDbFS: Double = Double.nan
    private(set) var rawAcDbFS: Double = Double.nan
    private(set) var rawDcDbFS: Double = Double.nan
    private(set) var historyAll: [DbSample] = []
    private(set) var historyWindowed: [DbSample] = []
    private(set) var graphHistoryWindowed: [DbSample] = []
    private(set) var frozenPayload: DbReaderOutputPayload = .empty
    private(set) var frozenHistory: [DbSample] = []
    private(set) var frozenGraphHistory: [DbSample] = []
    private(set) var frozenAveragingProgress: Double = 0
    private(set) var cachedGraphAveragedValues: [Double] = []
    @Published private var displaySnapshot: DbReaderDisplaySnapshot = .empty

    private var previewHistory: [DbSample] = []
    private(set) var isRunning: Bool = false
    @Published var statusText: String = ""
    private(set) var clippingWarning: Bool = false
    private(set) var headroomDb: Double = 0
    private(set) var noiseFloorDbFS: Double = 0

    private let moduleId: UUID
    private var tileId: UUID
    var settings: DbReaderModuleModel

    private var isLiveMode: Bool = false
    private var isTileActive: Bool = false
    private var isPreviewActive: Bool = false

    var lastPublishTime: TimeInterval = 0
    private var peakHold: Double = -Double.greatestFiniteMagnitude  // "—" until the first reading; 0 hid negative (uncalibrated) levels
    var aSlowMaxHold: Double = 0
    private var rawPeakDbfsMaxHold: Double = -Double.greatestFiniteMagnitude
    var lastSampleRate: Double = 0

    private var recentNoiseFloor: [(timestamp: Date, value: Double)] = []
    private var recentDisplaySamples: [(timestamp: Date, value: Double)] = []
    private var recentZSlowSamples: [(timestamp: Date, value: Double)] = []
    private var debugPublishCounter: Int = 0

    private var onSettingsChange: ((DbReaderModuleModel) -> Void)?

    // Subscription state
    private var splSubscriptionID: UUID?
    private var splTask: Task<Void, Never>?
    private var currentInputID: UUID?

    /// Start of the current Leq window: the processor's running energy totals at that
    /// moment. Leq over the window is (total now − total at start) / (samples now −
    /// samples at start), which covers every audio sample — not just the ones that happen
    /// to land on a display tick — and survives payloads dropped by the stream.
    /// Totals are kept for every weighting so switching weighting mid-window stays exact.
    fileprivate struct LeqWindow {
        var aPower: Double
        var cPower: Double
        var zPower: Double
        var sampleCount: Double
        /// Wall-clock start, used for averagingProgress and the window reset.
        var startTime: Date
    }
    private var leqWindow: LeqWindow?
    /// Set once the module is deleted. Its view can still call setLiveMode/setTileActive
    /// for a frame while it is torn down; those calls must not restart the microphone.
    private var isShutDown = false
    /// True while the input has stopped delivering audio.
    private(set) var isSignalStale: Bool = false

    init(moduleId: UUID, tileId: UUID, settings: DbReaderModuleModel) {
        self.moduleId = moduleId
        self.tileId = tileId

        self.settings = settings
    }

    deinit {
        splTask?.cancel()
        if let subID = splSubscriptionID {
            Task { await AudioAnalysisEngine.shared.unsubscribeSPL(id: subID) }
        }
    }

    func updateTileId(_ tileId: UUID) {
        self.tileId = tileId
    }

    func setSettingsChangeHandler(_ handler: @escaping (DbReaderModuleModel) -> Void) {
        onSettingsChange = handler
    }

    func updateSettings(_ settings: DbReaderModuleModel) {
        let inputChanged = settings.inputID != self.settings.inputID
        let averagingChanged = settings.averagingEnabled != self.settings.averagingEnabled
            || settings.averagingWindowSeconds != self.settings.averagingWindowSeconds
        let meterChanged = averagingChanged
            || settings.weighting != self.settings.weighting
            || settings.timeWeighting != self.settings.timeWeighting
        let wasRunning = isRunning

        if settings != self.settings {
            onSettingsChange?(settings)
        }

        self.settings = settings

        if averagingChanged {
            recentDisplaySamples.removeAll()
            leqWindow = nil
            displaySpl = 0
            averagingProgress = 0
        }

        if meterChanged {
            // The "Max" readout tracks the peak of displaySpl, which depends on
            // weighting/time-weighting/averaging — restart it so it doesn't mix
            // peaks captured under different meter settings.
            peakHold = -Double.greatestFiniteMagnitude
        }

        if inputChanged, wasRunning {
            stopSubscription()
        }
        updateRunState()
    }

    func setLiveMode(_ isLive: Bool) {
        let wasLive = isLiveMode
        isLiveMode = isLive
        if isLive && !wasLive {
            recentDisplaySamples.removeAll()
            leqWindow = nil
            averagingProgress = 0
            aSlowMaxHold = 0
            rawPeakDbfsMaxHold = -Double.greatestFiniteMagnitude
            #if DEBUG
            let samples = historyAll.prefix(10).map { String(format: "%.2f", $0.spl) }
            let sampleText = samples.isEmpty ? "[]" : "[" + samples.joined(separator: ", ") + "]"
            print("[DbReader] Live mode enter: weight=\(settings.weighting.rawValue) time=\(settings.timeWeighting.rawValue) averaging=\(settings.averagingEnabled) samples=\(sampleText)")
            #endif
        }
        updateRunState()
    }

    func setTileActive(_ isActive: Bool) {
        isTileActive = isActive
        updateRunState()
    }

    func setPreviewActive(_ isActive: Bool) {
        isPreviewActive = isActive
        updateRunState()
    }

    /// Permanently stops metering (the module was deleted).
    func shutdown() {
        isShutDown = true
        isTileActive = false
        isPreviewActive = false
        isLiveMode = false
        stopSubscription()
    }

    func reset() {
        resetDisplay(keepHistoryAll: false)
    }


    func resetDisplay(keepHistoryAll: Bool) {
        currentSpl = 0
        currentSplSlow = 0
        currentZSlow = 0
        displaySpl = 0
        averagingProgress = 0
        currentPeak = 0
        rawDbFS = 0
        rawPeakDbFS = 0
        rawAWeightedDbFS = Double.nan
        rawAcDbFS = Double.nan
        rawDcDbFS = Double.nan
        clippingWarning = false
        headroomDb = 0
        noiseFloorDbFS = 0
        peakHold = -Double.greatestFiniteMagnitude
        aSlowMaxHold = 0
        rawPeakDbfsMaxHold = -Double.greatestFiniteMagnitude
        leqWindow = nil
        lastPublishTime = 0
        recentNoiseFloor.removeAll()
        recentDisplaySamples.removeAll()
        recentZSlowSamples.removeAll()
        historyWindowed.removeAll()
        graphHistoryWindowed.removeAll()
        previewHistory.removeAll()
        if !keepHistoryAll {
            historyAll.removeAll()
        }
        frozenPayload = .empty
        frozenHistory.removeAll()
        frozenGraphHistory.removeAll()
        frozenAveragingProgress = 0
        cachedGraphAveragedValues = []
        if isTileActive && isLiveMode {
            DbReaderOutputStore.shared.clear(moduleId: moduleId, tileId: tileId)
        }
    }

    func calibrate(externalDb: Double) {
        guard let inputID = settings.inputID,
              let idx = AudioInputsConfigStore.shared.inputs.firstIndex(where: { $0.id == inputID })
        else { return }
        let currentCal = AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb
        // currentZSlow = actualRaw + currentCal (cal is baked in by AudioInputProcessor)
        // We want newCal such that actualRaw + newCal = externalDb
        // newCal = externalDb - actualRaw = externalDb - (currentZSlow - currentCal)
        AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb = externalDb - currentZSlow + currentCal
    }

    func calibrate(targetDb: Double, usingAverageSpl averageSpl: Double) {
        guard let inputID = settings.inputID,
              let idx = AudioInputsConfigStore.shared.inputs.firstIndex(where: { $0.id == inputID })
        else { return }
        let currentCal = AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb
        // averageSpl = actualAvg + currentCal
        // newCal = targetDb - actualAvg = targetDb - (averageSpl - currentCal)
        AudioInputsConfigStore.shared.inputs[idx].calibrationOffsetDb = targetDb - averageSpl + currentCal
    }

    private func updateRunState() {
        guard !isShutDown else { stopSubscription(); return }
        let shouldRun = (settings.isEnabled && settings.isArmedByUser && isLiveMode && isTileActive)
            || (isPreviewActive && settings.isEnabled)
        if shouldRun {
            startSubscriptionIfNeeded()
        } else {
            stopSubscription()
        }
    }

    struct CalibrationStats {
        let average: Double
        let min: Double
        let max: Double
    }

    func calibrationStats(windowSeconds: TimeInterval = 5) -> CalibrationStats? {
        let now = Date()
        let source = recentZSlowSamples
        let samples = source.filter { now.timeIntervalSince($0.timestamp) <= windowSeconds }
        guard !samples.isEmpty else { return nil }
        let values = samples.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        let total = values.reduce(0.0, +)
        return CalibrationStats(average: total / Double(values.count), min: minValue, max: maxValue)
    }

    private func startSubscriptionIfNeeded() {
        guard let inputID = settings.inputID,
              let config = AudioInputsConfigStore.shared.input(for: inputID) else {
            isRunning = false
            return
        }
        guard inputID != currentInputID else { return }
        stopSubscription()
        currentInputID = inputID
        isRunning = true
        statusText = ""
        lastPublishTime = 0
        // Hold `self` only per payload, never for the stream's lifetime.
        splTask = Task { [weak self] in
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeSPL(to: inputID, config: config)
            // stopSubscription() may have run while subscribeSPL was in flight. It found no
            // subscription ID to cancel, so this task must release the subscription itself —
            // otherwise the mic keeps running with nobody listening.
            guard !Task.isCancelled, let owner = self else {
                await AudioAnalysisEngine.shared.unsubscribeSPL(id: subID)
                return
            }
            owner.splSubscriptionID = subID
            for await payload in stream {
                guard !Task.isCancelled, let owner = self else { break }
                owner.handleSPLPayload(payload)
            }
        }
    }

    private func stopSubscription() {
        splTask?.cancel()
        splTask = nil
        if let subID = splSubscriptionID {
            Task { await AudioAnalysisEngine.shared.unsubscribeSPL(id: subID) }
            splSubscriptionID = nil
        }
        currentInputID = nil
        isRunning = false
        if isSignalStale {
            isSignalStale = false
            statusText = ""
        }
        if isTileActive && isLiveMode {
            DbReaderOutputStore.shared.clear(moduleId: moduleId, tileId: tileId)
        }
    }

    func handleSPLPayload(_ payload: SPLPayload) {
        if payload.isStale {
            handleSignalLost()
            return
        }
        if isSignalStale {
            isSignalStale = false
            statusText = ""
        }

        lastSampleRate = payload.sampleRate

        // Map all weightings
        rawDbFS = payload.rawDbFS
        rawPeakDbFS = payload.rawPeakDbFS
        clippingWarning = payload.clippingWarning
        headroomDb = payload.headroomDb
        noiseFloorDbFS = payload.noiseFloorDbFS
        rawAWeightedDbFS = payload.aFast
        rawAcDbFS = payload.cFast
        rawDcDbFS = Double.nan

        // Noise-floor and calibration-window tracking happen in publish(), at the
        // throttled publish rate, rather than here on every audio buffer.
        let timestamp = payload.timestamp

        // Build weights snapshot
        let weights = DbWeightingSnapshot(
            aFast: payload.aFast,
            aSlow: payload.aSlow,
            cFast: payload.cFast,
            cSlow: payload.cSlow,
            zFast: payload.zFast,
            zSlow: payload.zSlow,
            caFast: payload.caFast,
            caSlow: payload.caSlow
        )

        // Select SPL based on weighting + time weighting
        let rawSpl: Double
        switch settings.weighting {
        case .a:
            rawSpl = settings.timeWeighting == .fast ? payload.aFast : payload.aSlow
        case .c:
            rawSpl = settings.timeWeighting == .fast ? payload.cFast : payload.cSlow
        case .z:
            rawSpl = settings.timeWeighting == .fast ? payload.zFast : payload.zSlow
        case .ca:
            rawSpl = settings.timeWeighting == .fast ? payload.caFast : payload.caSlow
        }
        // Payload values already carry the AudioInputConfig calibration offset —
        // applied once in AudioInputProcessor. Do NOT add settings.calibrationOffsetDb here.
        let calibrated = rawSpl

        currentSpl = calibrated
        currentSplSlow = payload.caSlow
        currentZSlow = payload.zSlow

        aSlowMaxHold = max(aSlowMaxHold, payload.aSlow)
        rawPeakDbfsMaxHold = max(rawPeakDbfsMaxHold, payload.rawPeakDbFS)

        // Peak hold for the "Max" readout is updated from displaySpl in publish(),
        // once averaging (if enabled) has been applied for this tick — so it
        // always tracks what the meter is currently displaying.
        // rawPeakDbFS is uncalibrated; the peak readout is in calibrated dB like the meter.
        currentPeak = max(payload.rawPeakDbFS + payload.calibrationOffsetDb, peakHold, calibrated)

        // Open the Leq window on the first payload after averaging starts (every payload,
        // not just publish ticks, so no audio before the first tick is missed).
        let averaging = settings.averagingEnabled && isLiveMode
        if averaging, leqWindow == nil {
            leqWindow = LeqWindow(payload: payload)
        } else if !averaging {
            leqWindow = nil
        }

        // Throttle publish to publishHz
        let now = Date().timeIntervalSince1970
        let publishInterval = 1.0 / max(1.0, settings.publishHz)
        guard (now - lastPublishTime) >= publishInterval else { return }
        lastPublishTime = now

        // Leq energy averaging from the processor's running energy totals (see LeqWindow).
        // Powers already include the calibration offset.
        //
        // C-A special case: Leq(C) − Leq(A), preserving the C-A differential.
        // Using only A power (as a plain LAeqA) would match a dBA tile exactly,
        // which defeats the purpose of the C-A weighting.
        if averaging, let window = leqWindow {
            func leqDb(_ powerSum: Double, _ samples: Double, fallback: Double) -> Double {
                let mean = samples > 0 ? powerSum / samples : fallback
                return mean > 1e-12 ? 10 * log10(mean) : -120
            }
            let samples = payload.cumulativeSampleCount - window.sampleCount
            let aDb = leqDb(payload.cumulativeAPower - window.aPower, samples, fallback: payload.aInstantPower)
            let cDb = leqDb(payload.cumulativeCPower - window.cPower, samples, fallback: payload.cInstantPower)
            let zDb = leqDb(payload.cumulativeZPower - window.zPower, samples, fallback: payload.zInstantPower)
            switch settings.weighting {
            case .a: displaySpl = aDb
            case .c: displaySpl = cDb
            case .z: displaySpl = zDb
            case .ca: displaySpl = cDb - aDb
            }

            let elapsed = timestamp.timeIntervalSince(window.startTime)
            averagingProgress = min(1.0, elapsed / settings.averagingWindowSeconds)
            if elapsed >= settings.averagingWindowSeconds {
                // The next window starts exactly where this one ended, so no audio falls
                // between windows.
                leqWindow = LeqWindow(payload: payload)
            }
        } else {
            displaySpl = calibrated
            averagingProgress = 0
        }

        let caSlow = settings.weighting == .ca ? payload.caSlow : nil as Double?
        let peakValue = currentPeak

        publish(
            spl: calibrated,
            peak: peakValue,
            rawDbFS: payload.rawDbFS,
            rawPeakDbFS: payload.rawPeakDbFS,
            rawAWeightedDbFS: payload.aFast,
            rawAcDbFS: payload.cFast,
            rawDcDbFS: Double.nan,
            timestamp: timestamp,
            caSlow: caSlow,
            weights: weights,
            zSlowDb: payload.zSlow
        )
    }

    /// The input stopped delivering audio: show that instead of freezing on the last level,
    /// and tell downstream consumers the value is stale.
    private func handleSignalLost() {
        guard !isSignalStale else { return }
        isSignalStale = true
        statusText = "No signal from input"
        leqWindow = nil
        averagingProgress = 0
        lastPublishTime = 0
        if isTileActive && isLiveMode {
            DbReaderOutputStore.shared.clear(moduleId: moduleId, tileId: tileId)
        }
        publishDisplaySnapshot()
    }

    func publish(
        spl: Double,
        peak: Double,
        rawDbFS: Double,
        rawPeakDbFS: Double,
        rawAWeightedDbFS: Double,
        rawAcDbFS: Double,
        rawDcDbFS: Double,
        timestamp: Date,
        caSlow: Double?,
        weights: DbWeightingSnapshot?,
        zSlowDb: Double?
    ) {
        currentSpl = spl
        currentSplSlow = caSlow ?? 0
        if let zSlowDb {
            currentZSlow = zSlowDb
            recentZSlowSamples.append((timestamp: timestamp, value: zSlowDb))
            let cutoff = timestamp.addingTimeInterval(-5)
            recentZSlowSamples.removeAll { $0.timestamp < cutoff }
        }
        // displaySpl and averagingProgress are managed by the caller (handleSPLPayload)
        currentPeak = peak
        self.rawDbFS = rawDbFS
        self.rawPeakDbFS = rawPeakDbFS
        self.rawAWeightedDbFS = rawAWeightedDbFS
        self.rawAcDbFS = rawAcDbFS
        self.rawDcDbFS = rawDcDbFS

        rawPeakDbfsMaxHold = max(rawPeakDbfsMaxHold, rawPeakDbFS)
        peakHold = max(peakHold, displaySpl)
        // clippingWarning and headroomDb are digital-domain (dBFS) metrics that must not
        // include the acoustic calibration offset. They are already set correctly from
        // payload.clippingWarning / payload.headroomDb in handleSPLPayload — do not
        // overwrite them here using the calibrated rawPeakDbFS.

        recentNoiseFloor.append((timestamp: timestamp, value: rawDbFS))
        let cutoff = timestamp.addingTimeInterval(-5)
        recentNoiseFloor.removeAll { $0.timestamp < cutoff }
        if let minValue = recentNoiseFloor.map(\.value).min() {
            noiseFloorDbFS = minValue
        }

        let sample = DbSample(
            id: UUID(),
            timestamp: timestamp,
            graphTimestamp: timestamp.timeIntervalSinceReferenceDate,
            spl: spl,
            peak: peak,
            rawDbFS: rawDbFS,
            rawPeakDbFS: rawPeakDbFS
        )

        if isTileActive {
            historyAll.append(sample)
            trimHistory(now: timestamp)

            let payload = DbReaderOutputPayload(
                spl: spl,
                peak: peak,
                rawDbFS: rawDbFS,
                rawPeakDbFS: rawPeakDbFS,
                weighting: settings.weighting,
                timeWeighting: settings.timeWeighting,
                caSlow: caSlow,
                timestamp: timestamp,
                isStale: false
            )
            DbReaderOutputStore.shared.update(moduleId: moduleId, tileId: tileId, payload: payload)
            #if DEBUG
            if let weights {
                debugPublishCounter += 1
                if debugPublishCounter % 10 == 0 {
                    let fastText = String(format: "%.2f", weights.aFast)
                    let slowText = String(format: "%.2f", weights.aSlow)
                    let zFastText = String(format: "%.2f", weights.zFast)
                    let zSlowText = String(format: "%.2f", weights.zSlow)
                    let rawText = String(format: "%.2f", rawDbFS)
                    let rawPeakText = String(format: "%.2f", rawPeakDbFS)
                    let splText = String(format: "%.2f", spl)
                    print("[DbReader] A fast=\(fastText) slow=\(slowText) | Z fast=\(zFastText) slow=\(zSlowText) | raw=\(rawText) peak=\(rawPeakText) | time=\(settings.timeWeighting.rawValue) spl=\(splText)")
                }
            }
            #endif
            frozenPayload = payload
            frozenHistory = historyWindowed
            frozenGraphHistory = graphHistoryWindowed
            frozenAveragingProgress = averagingProgress
        } else if isPreviewActive {
            previewHistory.append(sample)
            trimPreviewHistory(now: timestamp)
        }
        publishDisplaySnapshot()
    }

    private func publishDisplaySnapshot() {
        displaySnapshot = DbReaderDisplaySnapshot(
            currentSpl: currentSpl,
            currentSplSlow: currentSplSlow,
            currentZSlow: currentZSlow,
            displaySpl: displaySpl,
            averagingProgress: averagingProgress,
            currentPeak: currentPeak,
            rawDbFS: rawDbFS,
            rawPeakDbFS: rawPeakDbFS,
            rawAWeightedDbFS: rawAWeightedDbFS,
            rawAcDbFS: rawAcDbFS,
            rawDcDbFS: rawDcDbFS,
            clippingWarning: clippingWarning,
            headroomDb: headroomDb,
            noiseFloorDbFS: noiseFloorDbFS,
            frozenPayload: frozenPayload,
            frozenAveragingProgress: frozenAveragingProgress
        )
    }

    /// First index in `historyAll` whose timestamp is >= `date`. History is appended in
    /// time order, so a binary search replaces the linear scans that ran every publish.
    private func historyIndex(atOrAfter date: Date) -> Int {
        var low = 0, high = historyAll.count
        while low < high {
            let mid = (low + high) / 2
            if historyAll[mid].timestamp < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func trimHistory(now: Date) {
        let maxAge = settings.historyMaxSeconds
        // Drop everything older than maxAge in one pass instead of repeated removeFirst().
        let expired = historyIndex(atOrAfter: now.addingTimeInterval(-maxAge))
        if expired > 0 { historyAll.removeFirst(expired) }
        let windowAge = settings.historyWindowSeconds
        let windowStart = now.addingTimeInterval(-windowAge)
        let visibleStartIndex = historyIndex(atOrAfter: windowStart)
        historyWindowed = visibleStartIndex < historyAll.endIndex
            ? Array(historyAll[visibleStartIndex...])
            : []

        let averageLookback = settings.graphLineMode == .averageSpl ? settings.averagingWindowSeconds : 0
        let graphStart = windowStart.addingTimeInterval(-max(0, averageLookback))
        let firstNeededIndex = historyIndex(atOrAfter: graphStart)
        if firstNeededIndex < historyAll.endIndex {
            let startIndex = firstNeededIndex > historyAll.startIndex
                ? historyAll.index(before: firstNeededIndex)
                : firstNeededIndex
            graphHistoryWindowed = Array(historyAll[startIndex...])
        } else {
            graphHistoryWindowed = []
        }
        cachedGraphAveragedValues = Self.computeAveragedValues(
            samples: historyWindowed,
            windowSeconds: settings.averagingWindowSeconds
        )
    }

    private func trimPreviewHistory(now: Date) {
        let windowAge = max(5, settings.historyWindowSeconds)
        previewHistory.removeAll { now.timeIntervalSince($0.timestamp) > windowAge }
    }


    func formattedPeakHold() -> String {
        if peakHold <= -200 { return "—" }
        return String(format: "%.1f", peakHold)
    }

    nonisolated static func computeAveragedValues(samples: [DbSample], windowSeconds: Double) -> [Double] {
        guard windowSeconds > 0 else { return samples.map(\.spl) }
        var result: [Double] = []
        result.reserveCapacity(samples.count)
        var sum = 0.0
        var startIndex = 0

        for index in samples.indices {
            let sample = samples[index]
            sum += sample.spl
            let cutoff = sample.timestamp.addingTimeInterval(-windowSeconds)
            while startIndex <= index, samples[startIndex].timestamp < cutoff {
                sum -= samples[startIndex].spl
                startIndex += 1
            }
            let count = index - startIndex + 1
            result.append(sum / Double(max(1, count)))
        }
        return result
    }
}

// MARK: - CSV Export

enum DbReaderCSVBuilder {
    static func build(samples: [DbSample], includeRaw: Bool, includePeak: Bool) -> String {
        var lines: [String] = []
        lines.append("# SPL Meter Export")
        lines.append("# Generated: \(ISO8601DateFormatter().string(from: Date()))")
        var header = ["timestamp_iso", "spl"]
        if includePeak { header.append("peak") }
        if includeRaw { header.append("raw_dbfs") }
        if includePeak { header.append("raw_peak_dbfs") }
        lines.append(header.joined(separator: ","))

        let iso = ISO8601DateFormatter()
        for s in samples {
            var row: [String] = [
                iso.string(from: s.timestamp),
                String(format: "%.3f", s.spl)
            ]
            if includePeak { row.append(String(format: "%.3f", s.peak)) }
            if includeRaw { row.append(String(format: "%.3f", s.rawDbFS)) }
            if includePeak { row.append(String(format: "%.3f", s.rawPeakDbFS)) }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

extension DateFormatter {
    static let dbReaderFileStamp: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return df
    }()
}

#if os(iOS)
final class DbReaderFileExporter: NSObject, UIDocumentPickerDelegate {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func present() {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(picker, animated: true)
        }
    }
}
#endif

fileprivate extension DbReaderController.LeqWindow {
    init(payload: SPLPayload) {
        self.init(aPower: payload.cumulativeAPower,
                  cPower: payload.cumulativeCPower,
                  zPower: payload.cumulativeZPower,
                  sampleCount: payload.cumulativeSampleCount,
                  startTime: payload.timestamp)
    }
}
