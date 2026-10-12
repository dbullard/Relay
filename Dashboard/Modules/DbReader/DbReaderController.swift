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
    private(set) var estimatedFrequencyHz: Double = Double.nan
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
    private var peakHold: Double = 0
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

    // LAeq energy accumulators — accumulate linear power (not dB) for correct averaging.
    // For C-A mode leqPowerAccumulator holds C power and leqCaAuxAccumulator holds A power;
    // displaySpl = 10·log10(avgC) - 10·log10(avgA) so the differential is preserved.
    private var leqPowerAccumulator: Double = 0
    private var leqCaAuxAccumulator: Double = 0   // A power, only used when weighting == .ca
    private var leqSampleCount: Int = 0
    // Wall-clock start of the current LAeq window, used to drive averagingProgress
    // and the window reset — sample-tick counts don't reliably track real elapsed
    // time because the publish rate can fall short of publishHz.
    private var leqWindowStartTime: Date?

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
            leqPowerAccumulator = 0
            leqCaAuxAccumulator = 0
            leqSampleCount = 0
            leqWindowStartTime = nil
            displaySpl = 0
            averagingProgress = 0
        }

        if meterChanged {
            // The "Max" readout tracks the peak of displaySpl, which depends on
            // weighting/time-weighting/averaging — restart it so it doesn't mix
            // peaks captured under different meter settings.
            peakHold = 0
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
            leqPowerAccumulator = 0
            leqCaAuxAccumulator = 0
            leqSampleCount = 0
            leqWindowStartTime = nil
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
        estimatedFrequencyHz = Double.nan
        clippingWarning = false
        headroomDb = 0
        noiseFloorDbFS = 0
        peakHold = 0
        aSlowMaxHold = 0
        rawPeakDbfsMaxHold = -Double.greatestFiniteMagnitude
        leqPowerAccumulator = 0
        leqCaAuxAccumulator = 0
        leqSampleCount = 0
        leqWindowStartTime = nil
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
        splTask = Task { [weak self] in
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeSPL(to: inputID, config: config)
            await MainActor.run { self?.splSubscriptionID = subID }
            for await payload in stream {
                guard let self else { break }
                await MainActor.run { self.handleSPLPayload(payload) }
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
        if isTileActive && isLiveMode {
            DbReaderOutputStore.shared.clear(moduleId: moduleId, tileId: tileId)
        }
    }

    func handleSPLPayload(_ payload: SPLPayload) {
        guard !payload.isStale else { return }

        lastSampleRate = payload.sampleRate

        // Map all weightings
        rawDbFS = payload.rawDbFS
        rawPeakDbFS = payload.rawPeakDbFS
        clippingWarning = payload.clippingWarning
        headroomDb = payload.headroomDb
        noiseFloorDbFS = payload.noiseFloorDbFS
        estimatedFrequencyHz = payload.estimatedFrequencyHz
        rawAWeightedDbFS = payload.aFast
        rawAcDbFS = payload.cFast
        rawDcDbFS = Double.nan

        // Noise floor tracking
        let timestamp = payload.timestamp
        recentNoiseFloor.append((timestamp: timestamp, value: payload.rawDbFS))
        let noiseFloorCutoff = timestamp.addingTimeInterval(-5)
        recentNoiseFloor.removeAll { $0.timestamp < noiseFloorCutoff }
        if let minValue = recentNoiseFloor.map(\.value).min() {
            noiseFloorDbFS = minValue
        }

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

        recentZSlowSamples.append((timestamp: timestamp, value: currentZSlow))
        let zSlowCutoff = timestamp.addingTimeInterval(-5)
        recentZSlowSamples.removeAll { $0.timestamp < zSlowCutoff }

        aSlowMaxHold = max(aSlowMaxHold, payload.aSlow)
        rawPeakDbfsMaxHold = max(rawPeakDbfsMaxHold, payload.rawPeakDbFS)

        // Peak hold for the "Max" readout is updated from displaySpl in publish(),
        // once averaging (if enabled) has been applied for this tick — so it
        // always tracks what the meter is currently displaying.
        currentPeak = max(payload.rawPeakDbFS, peakHold, calibrated)

        // Throttle publish to publishHz
        let now = Date().timeIntervalSince1970
        let publishInterval = 1.0 / max(1.0, settings.publishHz)
        guard (now - lastPublishTime) >= publishInterval else { return }
        lastPublishTime = now

        // LAeq energy averaging.
        // Instant powers are already scaled by linCal in AudioInputProcessor, so
        // 10·log10(avgPower) already includes the acoustic calibration offset.
        //
        // C-A special case: accumulate C and A power separately so the averaged
        // display is LAeqC − LAeqA, preserving the C-A differential.
        // Using only A power (as a plain LAeqA) would match a dBA tile exactly,
        // which defeats the purpose of the C-A weighting.
        let instantPower: Double
        let instantCaAux: Double?   // non-nil only for C-A mode
        switch settings.weighting {
        case .a:
            instantPower = payload.aInstantPower
            instantCaAux = nil
        case .ca:
            instantPower = payload.cInstantPower   // C power → main accumulator
            instantCaAux = payload.aInstantPower   // A power → aux accumulator
        case .c:
            instantPower = payload.cInstantPower
            instantCaAux = nil
        case .z:
            instantPower = payload.zInstantPower
            instantCaAux = nil
        }

        if settings.averagingEnabled && isLiveMode {
            if leqWindowStartTime == nil { leqWindowStartTime = timestamp }

            leqPowerAccumulator += instantPower
            if let aux = instantCaAux { leqCaAuxAccumulator += aux }
            leqSampleCount += 1
            let avgPower = leqPowerAccumulator / Double(leqSampleCount)

            if settings.weighting == .ca {
                // Averaged C-A = LAeqC − LAeqA
                let avgAux = leqCaAuxAccumulator / Double(leqSampleCount)
                let leqC = avgPower > 1e-12 ? 10 * log10(avgPower) : -120
                let leqA = avgAux  > 1e-12 ? 10 * log10(avgAux)   : -120
                displaySpl = leqC - leqA
            } else {
                displaySpl = avgPower > 1e-12 ? 10 * log10(avgPower) : -120
            }

            // Drive progress off real elapsed time, not sample-tick counts —
            // the publish rate can fall short of publishHz, which previously
            // made the window take longer than averagingWindowSeconds to complete.
            let elapsed = timestamp.timeIntervalSince(leqWindowStartTime ?? timestamp)
            averagingProgress = min(1.0, elapsed / settings.averagingWindowSeconds)
            if elapsed >= settings.averagingWindowSeconds {
                leqPowerAccumulator = 0
                leqCaAuxAccumulator = 0
                leqSampleCount = 0
                leqWindowStartTime = nil
            }
        } else {
            displaySpl = calibrated
            averagingProgress = 0
            leqPowerAccumulator = 0
            leqCaAuxAccumulator = 0
            leqSampleCount = 0
            leqWindowStartTime = nil
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
            estimatedFrequencyHz: payload.estimatedFrequencyHz,
            timestamp: timestamp,
            caSlow: caSlow,
            weights: weights,
            zSlowDb: payload.zSlow
        )
    }

    func publish(
        spl: Double,
        peak: Double,
        rawDbFS: Double,
        rawPeakDbFS: Double,
        rawAWeightedDbFS: Double,
        rawAcDbFS: Double,
        rawDcDbFS: Double,
        estimatedFrequencyHz: Double,
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
        self.estimatedFrequencyHz = estimatedFrequencyHz

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
            estimatedFrequencyHz: estimatedFrequencyHz,
            clippingWarning: clippingWarning,
            headroomDb: headroomDb,
            noiseFloorDbFS: noiseFloorDbFS,
            frozenPayload: frozenPayload,
            frozenAveragingProgress: frozenAveragingProgress
        )
    }

    private func trimHistory(now: Date) {
        let maxAge = settings.historyMaxSeconds
        while let first = historyAll.first,
              now.timeIntervalSince(first.timestamp) > maxAge {
            historyAll.removeFirst()
        }
        let windowAge = settings.historyWindowSeconds
        let windowStart = now.addingTimeInterval(-windowAge)
        let visibleStartIndex = historyAll.firstIndex { $0.timestamp >= windowStart } ?? historyAll.endIndex
        historyWindowed = visibleStartIndex < historyAll.endIndex
            ? Array(historyAll[visibleStartIndex...])
            : []

        let averageLookback = settings.graphLineMode == .averageSpl ? settings.averagingWindowSeconds : 0
        let graphStart = windowStart.addingTimeInterval(-max(0, averageLookback))
        let firstNeededIndex = historyAll.firstIndex { $0.timestamp >= graphStart } ?? historyAll.endIndex
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
