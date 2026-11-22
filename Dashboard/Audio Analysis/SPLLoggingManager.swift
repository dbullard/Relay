import Foundation
import Observation

// MARK: - SPLLoggingManager
//
// Owns the full SPL logging lifecycle. One SPLInputLogger per audio input.
// Start/stop are explicit user actions — independent of Live Mode.

@MainActor
@Observable
final class SPLLoggingManager {
    static let shared = SPLLoggingManager()

    var settings: SPLLoggingSettings = SPLLoggingSettings.load()

    /// Non-nil when the last `startLogging()` call failed to open any log files.
    /// Cleared when logging stops or a new successful session starts.
    var folderAccessError: String? = nil

    // Runtime state — not persisted
    private var activeSessions: [UUID: SPLInputLogger] = [:]
    private var subscriptionTasks: [UUID: Task<Void, Never>] = [:]

    /// One CSV row per input per interval. Payloads arrive once per audio buffer (~94 per
    /// second at 512 frames / 48 kHz); logging each one produced ~60 MB per input per hour.
    nonisolated static let logIntervalSeconds: TimeInterval = 1.0

    init() {
        if settings.isLogging {
            Task {
                await Task.yield()
                await startLogging()
            }
        }
    }

    func startLogging() async {
        // Idempotent: stop any existing session first
        await stopLogging()

        let folderURL = resolvedFolderURL()
        let bookmarkData = settings.folderBookmarkData
        let sessionId = UUID()
        let sessionStart = Date()
        let inputs = AudioInputsConfigStore.shared.inputs

        var startedCount = 0
        for input in inputs {
            if startSession(for: input, sessionId: sessionId, sessionStart: sessionStart, folderURL: folderURL, bookmarkData: bookmarkData) {
                startedCount += 1
            }
        }

        // Only mark logging active if at least one session opened successfully.
        // If no inputs are configured yet, treat as success (sessions will open via observeInputChanges).
        if inputs.isEmpty || startedCount > 0 {
            settings.isLogging = true
            folderAccessError = nil
        } else {
            // All sessions failed to open — likely a file-access/permissions problem with the
            // selected folder (e.g. TCC denied Desktop/Documents/Downloads on this launch).
            settings.isLogging = false
            let displayPath = settings.folderPath.isEmpty
                ? resolvedFolderURL().path
                : settings.folderPath
            folderAccessError = "Can't write to \"\(displayPath)\". Choose a different folder or grant access in System Settings › Privacy & Security › Files and Folders."
        }
        settings.save()
        if settings.isLogging {
            observeInputChanges(folderURL: folderURL, bookmarkData: bookmarkData, sessionId: sessionId, sessionStart: sessionStart)
        }
    }

    func stopLogging() async {
        for (_, task) in subscriptionTasks { task.cancel() }
        subscriptionTasks.removeAll()
        for (_, logger) in activeSessions { logger.close() }
        activeSessions.removeAll()

        settings.isLogging = false
        folderAccessError = nil
        settings.save()
    }

    func toggleLogging() async {
        if settings.isLogging {
            await stopLogging()
        } else {
            await startLogging()
        }
    }

    // MARK: - Input Observation

    private func observeInputChanges(folderURL: URL, bookmarkData: Data?, sessionId: UUID, sessionStart: Date) {
        withObservationTracking {
            _ = AudioInputsConfigStore.shared.inputs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.settings.isLogging else { return }
                self.reconcileInputs(folderURL: folderURL, bookmarkData: bookmarkData, sessionId: sessionId, sessionStart: sessionStart)
                // Re-arm the observation
                self.observeInputChanges(folderURL: folderURL, bookmarkData: bookmarkData, sessionId: sessionId, sessionStart: sessionStart)
            }
        }
    }

    private func reconcileInputs(folderURL: URL, bookmarkData: Data?, sessionId: UUID, sessionStart: Date) {
        let currentInputs = AudioInputsConfigStore.shared.inputs
        let currentIDs = Set(currentInputs.map(\.id))
        let activeIDs = Set(activeSessions.keys)

        // Remove sessions for inputs that no longer exist
        for removedID in activeIDs.subtracting(currentIDs) {
            subscriptionTasks[removedID]?.cancel()
            subscriptionTasks.removeValue(forKey: removedID)
            activeSessions[removedID]?.close()
            activeSessions.removeValue(forKey: removedID)
        }

        // Add sessions for new inputs
        for input in currentInputs where !activeIDs.contains(input.id) {
            startSession(for: input, sessionId: sessionId, sessionStart: sessionStart, folderURL: folderURL, bookmarkData: bookmarkData)
        }
    }

    // MARK: - Helpers

    /// Returns `true` if the logger was successfully created; `false` if file access failed.
    @discardableResult
    private func startSession(for input: AudioInputConfig,
                               sessionId: UUID,
                               sessionStart: Date,
                               folderURL: URL,
                               bookmarkData: Data?) -> Bool {
        guard let logger = SPLInputLogger(
            input: input,
            sessionId: sessionId,
            sessionStart: sessionStart,
            folderURL: folderURL,
            bookmarkData: bookmarkData
        ) else { return false }

        activeSessions[input.id] = logger
        logger.onWriteFailure = { [weak self] message in
            Task { @MainActor [weak self] in self?.folderAccessError = message }
        }

        let inputID = input.id
        // Runs off the main actor: per-buffer accumulation is cheap, and the only hop that
        // remains is the logger's own write queue, once per interval.
        let task = Task.detached(priority: .utility) {
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeSPL(
                to: inputID, config: input)
            defer {
                Task { await AudioAnalysisEngine.shared.unsubscribeSPL(id: subID) }
            }
            var aSlowMax = -Double.greatestFiniteMagnitude
            var rawPeakMax = -Double.greatestFiniteMagnitude
            var intervalStart: SPLPayload?
            var zFastMax = -Double.greatestFiniteMagnitude
            for await payload in stream {
                guard !Task.isCancelled else { break }
                guard !payload.isStale else {
                    // Input dropped out: don't log the gap as silence; restart the interval
                    // when audio returns.
                    intervalStart = nil
                    continue
                }
                aSlowMax = max(aSlowMax, payload.aSlow)
                rawPeakMax = max(rawPeakMax, payload.rawPeakDbFS)
                zFastMax = max(zFastMax, payload.zFast)
                guard let start = intervalStart else {
                    intervalStart = payload
                    continue
                }
                guard payload.timestamp.timeIntervalSince(start.timestamp) >= Self.logIntervalSeconds else {
                    continue
                }
                let samples = payload.cumulativeSampleCount - start.cumulativeSampleCount
                func leq(_ now: Double, _ then: Double, fallback: Double) -> Double {
                    let mean = samples > 0 ? (now - then) / samples : fallback
                    return mean > 1e-12 ? 10 * log10(mean) : -120
                }
                let stats = SPLInputLogger.IntervalStats(
                    zFastMax: zFastMax,
                    leqA: leq(payload.cumulativeAPower, start.cumulativeAPower, fallback: payload.aInstantPower),
                    leqC: leq(payload.cumulativeCPower, start.cumulativeCPower, fallback: payload.cInstantPower),
                    leqZ: leq(payload.cumulativeZPower, start.cumulativeZPower, fallback: payload.zInstantPower)
                )
                logger.append(
                    payload: payload,
                    // From the payload, so the column follows recalibration mid-session.
                    calibrationOffsetDb: payload.calibrationOffsetDb,
                    aSlowMax: aSlowMax,
                    rawPeakDbfsMax: rawPeakMax,
                    interval: stats
                )
                intervalStart = payload
                zFastMax = payload.zFast
            }
        }
        subscriptionTasks[input.id] = task
        return true
    }

    private func resolvedFolderURL() -> URL {
        // Return the plain path URL. SPLInputLogger.init handles security-scoped
        // access independently via its `bookmarkData` parameter. Returning a
        // security-scoped URL here (without calling startAccessingSecurityScopedResource)
        // can create a stale scope that prevents fallback to the plain path.
        if !settings.folderPath.isEmpty {
            return URL(fileURLWithPath: settings.folderPath)
        }
        return SPLInputLogger.defaultFolderURL()
    }
}
