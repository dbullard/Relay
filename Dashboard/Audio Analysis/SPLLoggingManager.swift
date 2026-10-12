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

    // Max-hold trackers per input (reset on startLogging)
    private var aSlowMax: [UUID: Double] = [:]
    private var rawPeakMax: [UUID: Double] = [:]

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
        aSlowMax.removeAll()
        rawPeakMax.removeAll()

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
            aSlowMax.removeValue(forKey: removedID)
            rawPeakMax.removeValue(forKey: removedID)
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
        aSlowMax[input.id] = -Double.greatestFiniteMagnitude
        rawPeakMax[input.id] = -Double.greatestFiniteMagnitude

        let inputID = input.id
        let task = Task { [weak self] in
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeSPL(
                to: inputID, config: input)
            defer {
                Task { await AudioAnalysisEngine.shared.unsubscribeSPL(id: subID) }
            }
            for await payload in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    guard let self, let logger = self.activeSessions[inputID] else { return }
                    self.aSlowMax[inputID] = max(
                        self.aSlowMax[inputID] ?? -Double.greatestFiniteMagnitude,
                        payload.aSlow)
                    self.rawPeakMax[inputID] = max(
                        self.rawPeakMax[inputID] ?? -Double.greatestFiniteMagnitude,
                        payload.rawPeakDbFS)
                    logger.append(
                        payload: payload,
                        calibrationOffsetDb: input.calibrationOffsetDb,
                        aSlowMax: self.aSlowMax[inputID] ?? 0,
                        rawPeakDbfsMax: self.rawPeakMax[inputID] ?? 0
                    )
                }
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
