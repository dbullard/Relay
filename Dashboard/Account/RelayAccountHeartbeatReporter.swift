import Foundation

struct RelayAccountHeartbeatStatus: Equatable {
    var isEligible: Bool = false
    var isRunning: Bool = false
    var message: String = "Diagnostics heartbeat has not started."
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastFailureMessage: String?
}

@MainActor
final class RelayAccountHeartbeatReporter {
    private let service: RelayAccountServicing
    private let isUsageDiagnosticsEnabled: @MainActor () -> Bool
    private let sessionToken: @MainActor () -> String?
    private let isSessionVerified: @MainActor () -> Bool
    private let statusChanged: @MainActor (RelayAccountHeartbeatStatus) -> Void
    private let installationId: UUID
    private let platform: String
    private let appVersion: String
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var isApplicationActive = false
    private var reportingTask: Task<Void, Never>?
    private var reportingTaskID: UUID?
    private var status = RelayAccountHeartbeatStatus()

    init(
        service: RelayAccountServicing,
        isUsageDiagnosticsEnabled: @escaping @MainActor () -> Bool,
        sessionToken: @escaping @MainActor () -> String?,
        isSessionVerified: @escaping @MainActor () -> Bool,
        statusChanged: @escaping @MainActor (RelayAccountHeartbeatStatus) -> Void = { _ in },
        installationId: UUID? = nil,
        platform: String? = nil,
        appVersion: String? = nil,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            try? await Task.sleep(for: .seconds(interval))
        }
    ) {
        self.service = service
        self.isUsageDiagnosticsEnabled = isUsageDiagnosticsEnabled
        self.sessionToken = sessionToken
        self.isSessionVerified = isSessionVerified
        self.statusChanged = statusChanged
        self.installationId = installationId ?? Self.loadInstallationId()
        self.platform = platform ?? Self.currentPlatform
        self.appVersion = appVersion ?? Self.currentAppVersion
        self.sleep = sleep
        publishStatus(message: ineligibilityMessage ?? "Diagnostics heartbeat is ready.")
    }

    deinit {
        reportingTask?.cancel()
    }

    func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
        refreshEligibility()
    }

    func refreshEligibility() {
        guard isEligible else {
            stop()
            publishStatus(message: ineligibilityMessage ?? "Diagnostics heartbeat is paused.")
            return
        }

        guard reportingTask == nil else {
            publishStatus(message: "Diagnostics heartbeat is running.", isRunning: true)
            return
        }
        let taskID = UUID()
        reportingTaskID = taskID
        publishStatus(message: "Diagnostics heartbeat is starting.", isRunning: true)
        reportingTask = Task { [weak self] in
            await self?.reportWhileEligible(taskID: taskID)
        }
    }

    func stop() {
        reportingTask?.cancel()
        reportingTask = nil
        reportingTaskID = nil
        publishStatus(message: ineligibilityMessage ?? "Diagnostics heartbeat is stopped.")
    }

    private var isEligible: Bool {
        isApplicationActive && isUsageDiagnosticsEnabled() && isSessionVerified() && normalizedToken != nil
    }

    private var normalizedToken: String? {
        guard let token = sessionToken()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        return token
    }

    private var ineligibilityMessage: String? {
        if !isApplicationActive {
            return "Waiting for Relay to become active."
        }

        if !isUsageDiagnosticsEnabled() {
            return "Diagnostics sharing is off."
        }

        if !isSessionVerified() {
            return "Sign in to Relay Account to count this device as active."
        }

        if normalizedToken == nil {
            return "Relay Account session token is missing."
        }

        return nil
    }

    private func reportWhileEligible(taskID: UUID) async {
        defer {
            if reportingTaskID == taskID {
                reportingTask = nil
                reportingTaskID = nil
            }
        }

        while !Task.isCancelled {
            guard isEligible, let token = normalizedToken else { return }

            let attemptDate = Date()
            publishStatus(
                message: "Sending diagnostics heartbeat.",
                isRunning: true,
                lastAttemptAt: attemptDate
            )

            do {
                try await service.sendHeartbeat(
                    token: token,
                    request: RelayAccountHeartbeatRequest(
                        installationId: installationId,
                        platform: platform,
                        appVersion: appVersion
                    )
                )
                publishStatus(
                    message: "Diagnostics heartbeat sent.",
                    isRunning: true,
                    lastAttemptAt: attemptDate,
                    lastSuccessAt: Date(),
                    lastFailureMessage: nil
                )
            } catch {
                publishStatus(
                    message: "Diagnostics heartbeat failed; Relay will retry.",
                    isRunning: true,
                    lastAttemptAt: attemptDate,
                    lastFailureMessage: error.localizedDescription
                )
                await sleep(60)
                continue
            }

            await sleep(120)
        }
    }

    private func publishStatus(
        message: String,
        isRunning: Bool? = nil,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastFailureMessage: String? = nil
    ) {
        status.isEligible = isEligible
        status.isRunning = isRunning ?? (reportingTask != nil)
        status.message = message
        if let lastAttemptAt {
            status.lastAttemptAt = lastAttemptAt
        }
        if let lastSuccessAt {
            status.lastSuccessAt = lastSuccessAt
        }
        status.lastFailureMessage = lastFailureMessage
        statusChanged(status)
    }

    private static let installationIdKey = "relay_usage_diagnostics_installation_id"

    private static func loadInstallationId() -> UUID {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: installationIdKey), let existing = UUID(uuidString: raw) {
            return existing
        }

        let installationId = UUID()
        defaults.set(installationId.uuidString, forKey: installationIdKey)
        return installationId
    }

    private static var currentPlatform: String {
#if os(macOS)
        "macos"
#else
        "ios"
#endif
    }

    private static var currentAppVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? version! : "0"
    }
}
