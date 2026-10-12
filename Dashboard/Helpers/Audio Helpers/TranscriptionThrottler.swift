import Foundation

final class TranscriptionThrottler {
    private var lastPublish: Date = .distantPast
    private var scheduledTask: Task<Void, Never>?

    deinit {
        scheduledTask?.cancel()
    }

    func publish(isFinal: Bool, targetHz: Double, publish: @escaping () -> Void) {
        let minInterval = max(0.05, 1.0 / max(1.0, targetHz))
        if isFinal {
            scheduledTask?.cancel()
            scheduledTask = nil
            lastPublish = Date()
            publish()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastPublish)
        if elapsed >= minInterval {
            lastPublish = now
            publish()
            return
        }

        scheduledTask?.cancel()
        let delay = minInterval - elapsed
        scheduledTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.lastPublish = Date()
            publish()
        }
    }

    /// Cancels any pending throttled publish. Callers that are tearing down the
    /// session that owns this throttler should call this explicitly rather than
    /// relying on `deinit` -- an extra strong reference kept alive elsewhere
    /// (even briefly) would otherwise let a stale publish still fire after the
    /// caller believes the session has stopped.
    func cancel() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }
}
