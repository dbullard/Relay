import Foundation
import SwiftUI
import Combine

@MainActor
final class RTAController: ObservableObject {
    /// Latest processed bands for each subscribed source, keyed by input ID.
    @Published private(set) var bandsBySource: [UUID: [RTABand]] = [:]
    @Published private(set) var isRunning: Bool = false

    private struct Subscription {
        var processor: RTABandProcessor
        var task: Task<Void, Never>?
        var subID: UUID?
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private(set) var settings: RTAModuleModel

    /// Latest computed bands per source, written on every FFT frame (off the publish cadence).
    private var latestBands: [UUID: [RTABand]] = [:]
    private var latestBandsDirty: Bool = false
    private var publishTask: Task<Void, Never>?

    /// Bands for the primary source, for callers that only care about `inputID`.
    var bands: [RTABand] {
        settings.inputID.flatMap { bandsBySource[$0] } ?? []
    }

    init(settings: RTAModuleModel) {
        self.settings = settings
        startPublishLoop()
    }

    deinit {
        publishTask?.cancel()
        for (_, sub) in subscriptions {
            sub.task?.cancel()
            if let subID = sub.subID {
                let id = subID
                Task { await AudioAnalysisEngine.shared.unsubscribeFFT(id: id) }
            }
        }
    }

    /// Coalesces per-source band updates (which arrive at up to ~23Hz *per source* at
    /// 1/48-octave) onto a single ~30Hz cadence, so adding more overlay sources doesn't
    /// multiply the rate at which `RTAViews.body` re-renders and redraws the whole canvas.
    private func startPublishLoop() {
        publishTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                guard let self else { return }
                if self.latestBandsDirty {
                    self.latestBandsDirty = false
                    self.bandsBySource = self.latestBands
                }
            }
        }
    }

    func updateSettings(_ newSettings: RTAModuleModel) {
        let resolutionChanged = newSettings.bandResolution != settings.bandResolution
            || newSettings.frequencyRangeLow != settings.frequencyRangeLow
            || newSettings.frequencyRangeHigh != settings.frequencyRangeHigh
        settings = newSettings
        if !newSettings.isEnabled {
            stopAll()
        } else if resolutionChanged {
            stopAll()
            syncSubscriptions()
        } else {
            syncSubscriptions()
        }
    }

    func setLiveMode(_ isLive: Bool) {
        if isLive && settings.isEnabled { syncSubscriptions() } else { stopAll() }
    }

    func setTileActive(_ isActive: Bool) {
        if isActive && settings.isEnabled { syncSubscriptions() } else { stopAll() }
    }

    // MARK: - Subscription management

    /// Primary source followed by any additional overlay sources, de-duplicated and order-preserved.
    private var desiredSourceIDs: [UUID] {
        var ids: [UUID] = []
        if let primary = settings.inputID { ids.append(primary) }
        for id in settings.additionalInputIDs where !ids.contains(id) { ids.append(id) }
        return ids
    }

    private func syncSubscriptions() {
        guard settings.isEnabled else { stopAll(); return }
        let desired = Set(desiredSourceIDs)

        for id in subscriptions.keys where !desired.contains(id) {
            stopSubscription(for: id)
        }
        for id in desired where subscriptions[id] == nil {
            startSubscription(for: id)
        }
        isRunning = !subscriptions.isEmpty
    }

    private func startSubscription(for inputID: UUID) {
        guard let config = AudioInputsConfigStore.shared.input(for: inputID) else { return }
        let processor = RTABandProcessor(resolution: settings.bandResolution,
                                          frequencyRangeLow: settings.frequencyRangeLow,
                                          frequencyRangeHigh: settings.frequencyRangeHigh)
        var sub = Subscription(processor: processor, task: nil, subID: nil)
        let resolution = settings.bandResolution
        // Hold `self` only briefly (per frame), never for the stream's lifetime: a strong
        // capture kept the controller alive forever, so deinit never cancelled the FFT and
        // analysis kept running after the tile was removed.
        sub.task = Task { [weak self] in
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeFFT(
                to: inputID, config: config, resolution: resolution)
            // stopSubscription may have run while subscribeFFT was in-flight on the
            // AudioAnalysisEngine actor — in that case subscriptions[inputID] is already
            // gone and the subID will never be stored, leaking FFT computation indefinitely.
            // Detect cancellation (or a released controller) and clean up before the leak can occur.
            if !Task.isCancelled, let owner = self {
                owner.subscriptions[inputID]?.subID = subID
            } else {
                await AudioAnalysisEngine.shared.unsubscribeFFT(id: subID)
                return
            }
            for await frame in stream {
                guard !Task.isCancelled, let owner = self else { break }
                guard let p = owner.subscriptions[inputID]?.processor else { break }
                let timeSmoothing = owner.settings.timeSmoothing
                let peakHoldDecayDbPerSec = owner.settings.peakHoldDecayDbPerSec
                // Runs on the RTABandProcessor actor, off the main actor, so the
                // per-band aggregation (largest at 1/48-octave) doesn't block UI.
                let updated = await p.process(frame: frame,
                                               timeSmoothing: timeSmoothing,
                                               peakHoldDecayDbPerSec: peakHoldDecayDbPerSec)
                guard !Task.isCancelled else { break }
                owner.latestBands[inputID] = updated
                owner.latestBandsDirty = true
            }
        }
        subscriptions[inputID] = sub
    }

    private func stopSubscription(for inputID: UUID) {
        guard let sub = subscriptions.removeValue(forKey: inputID) else { return }
        sub.task?.cancel()
        if let subID = sub.subID {
            let id = subID
            Task { await AudioAnalysisEngine.shared.unsubscribeFFT(id: id) }
        }
        latestBands.removeValue(forKey: inputID)
        bandsBySource.removeValue(forKey: inputID)
    }

    private func stopAll() {
        for id in Array(subscriptions.keys) { stopSubscription(for: id) }
        isRunning = false
    }
}
