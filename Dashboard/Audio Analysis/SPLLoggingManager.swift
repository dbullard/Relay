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

    var settings: SPLLoggingSettings

    /// Where settings persist. Tests pass a throwaway suite: unit tests run inside a copy
    /// of Relay that shares the real app's `UserDefaults`, so the default store would
    /// overwrite the user's logging folder and on/off state.
    @ObservationIgnored private let defaults: UserDefaults
    /// The inputs to log. Tests pass a fixed list so no real audio device is opened.
    @ObservationIgnored private let inputsProvider: () -> [AudioInputConfig]

    /// Where logs go when no folder is chosen, or the chosen one can't be used:
    /// `~/Documents/Relay/SPL Logs` in the app. Tests pass a temporary folder.
    @ObservationIgnored let defaultFolderURL: URL

    /// Non-nil when the last `startLogging()` call failed to open any log files.
    /// Cleared when logging stops or a new successful session starts.
    var folderAccessError: String? = nil

    /// Set when logging is running in the default folder because the chosen folder
    /// couldn't be written (e.g. an unmounted drive). Cleared on the next start or stop.
    var folderFallbackNotice: String? = nil

    /// The folder the current logging session writes to; nil when not logging.
    private(set) var activeFolderURL: URL? = nil

    // Runtime state — not persisted
    private var activeSessions: [UUID: SPLInputLogger] = [:]
    private var subscriptionTasks: [UUID: Task<Void, Never>] = [:]

    /// One CSV row per input per interval. Payloads arrive once per audio buffer (~94 per
    /// second at 512 frames / 48 kHz); logging each one produced ~60 MB per input per hour.
    nonisolated static let logIntervalSeconds: TimeInterval = 1.0

    init(defaults: UserDefaults = .standard,
         defaultFolderURL: URL = SPLInputLogger.defaultFolderURL(),
         inputsProvider: @escaping () -> [AudioInputConfig] = { AudioInputsConfigStore.shared.inputs }) {
        self.defaults = defaults
        self.defaultFolderURL = defaultFolderURL
        self.inputsProvider = inputsProvider
        self.settings = SPLLoggingSettings.load(from: defaults)
        // A folder inside the system's temporary directory is never a deliberate choice
        // (it came from test runs sharing the app's settings) and macOS purges it, so logs
        // written there would quietly disappear. Go back to the default folder.
        if !settings.folderPath.isEmpty, Self.isTemporaryLocation(settings.folderPath) {
            settings.folderPath = ""
            settings.folderBookmarkData = nil
            saveSettings()
        }
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

        var folderURL = resolvedFolderURL()
        var bookmarkData = settings.folderBookmarkData
        let sessionId = UUID()
        let sessionStart = Date()
        let inputs = inputsProvider()

        var startedCount = startSessions(inputs, sessionId: sessionId, sessionStart: sessionStart,
                                         folderURL: folderURL, bookmarkData: bookmarkData)

        // The chosen folder couldn't be written (unmounted drive, revoked access): keep the
        // choice for next time, but log to the default folder now rather than not at all.
        let usedChosenFolder = !settings.folderPath.isEmpty
        if !inputs.isEmpty, startedCount == 0, usedChosenFolder {
            let chosenPath = settings.folderPath
            folderURL = defaultFolderURL
            bookmarkData = nil
            startedCount = startSessions(inputs, sessionId: sessionId, sessionStart: sessionStart,
                                         folderURL: folderURL, bookmarkData: nil)
            if startedCount > 0 {
                folderFallbackNotice = "Couldn't write to \"\(chosenPath)\". Logging to \"\(folderURL.path)\" instead."
            }
        }

        // Only mark logging active if at least one session opened successfully.
        // If no inputs are configured yet, treat as success (sessions will open via observeInputChanges).
        if inputs.isEmpty || startedCount > 0 {
            settings.isLogging = true
            folderAccessError = nil
            activeFolderURL = folderURL
        } else {
            // All sessions failed to open, even in the default folder — likely a file-access
            // problem (e.g. TCC denied Documents on this launch).
            settings.isLogging = false
            folderAccessError = "Can't write to \"\(folderURL.path)\". Choose a different folder or grant access in System Settings › Privacy & Security › Files and Folders."
        }
        saveSettings()
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
        folderFallbackNotice = nil
        activeFolderURL = nil
        saveSettings()
    }

    /// Clears the chosen folder so logs go to the default folder. Takes effect the next
    /// time logging starts, like choosing a folder.
    func useDefaultFolder() {
        settings.folderPath = ""
        settings.folderBookmarkData = nil
        folderAccessError = nil
        saveSettings()
    }

    private func startSessions(_ inputs: [AudioInputConfig], sessionId: UUID, sessionStart: Date,
                               folderURL: URL, bookmarkData: Data?) -> Int {
        var started = 0
        for input in inputs where startSession(for: input, sessionId: sessionId, sessionStart: sessionStart,
                                               folderURL: folderURL, bookmarkData: bookmarkData) {
            started += 1
        }
        return started
    }

    /// True for paths inside the system temporary directories.
    nonisolated static func isTemporaryLocation(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let tempRoots = [
            FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path,
            URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path,
            "/private/var/folders", "/var/folders", "/private/tmp", "/tmp"
        ]
        return tempRoots.contains { root in
            let r = root.hasSuffix("/") ? String(root.dropLast()) : root
            return resolved == r || resolved.hasPrefix(r + "/")
        }
    }

    /// Persists `settings` to this manager's store.
    func saveSettings() {
        settings.save(to: defaults)
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
            _ = inputsProvider()
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
        let currentInputs = inputsProvider()
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
        return defaultFolderURL
    }
}
