import Foundation

actor NDIFrameProcessor {

    struct Snapshot {
        var state: NDIFramePipeline.State = .idle
        var latestFrame: NDIFrame?
        var connectionInfo: NDIReceiverConnectionInfo?
        var lastFrameDate: Date?
        var droppedFrameCount: Int = 0
        var receivedFrameCount: Int = 0
        var latestFrameNumber: UInt64 = 0
        var retryCount: Int = 0
        var revision: UInt64 = 0
    }

    private var snapshot = Snapshot()
    /// Minimum seconds between accepted frames. Set by the controller from fpsCap.
    private var minimumFrameInterval: TimeInterval = 0
    private var lastAcceptedFrameDate: Date?

    func setFrameRateCap(_ fps: Double) {
        minimumFrameInterval = fps > 0 ? 1.0 / fps : 0
    }

    func process(_ event: NDIReceiverEvent) {
        switch event {
        case .connecting:
            snapshot.state = .connecting
            snapshot.revision &+= 1

        case .connected(let info):
            snapshot.connectionInfo = info
            snapshot.state = .connected
            snapshot.revision &+= 1

        case .frame(let frame):
            // Frame-rate cap: drop frames that arrive too soon after the last accepted one.
            // This gives poster (1 fps), preview (15 fps), and live (30 fps) real differences.
            if minimumFrameInterval > 0,
               let lastAccepted = lastAcceptedFrameDate,
               frame.timestamp.timeIntervalSince(lastAccepted) < minimumFrameInterval {
                return // drop — too soon
            }
            lastAcceptedFrameDate = frame.timestamp

            if let last = snapshot.lastFrameDate,
               frame.timestamp.timeIntervalSince(last) > 1.5 {
                snapshot.droppedFrameCount += 1
            }
            snapshot.latestFrame = frame
            snapshot.lastFrameDate = frame.timestamp
            snapshot.receivedFrameCount += 1
            snapshot.latestFrameNumber = frame.frameNumber
            snapshot.state = .connected
            snapshot.revision &+= 1

        case .disconnected(let reason):
            let hadActiveSession: Bool
            switch snapshot.state {
            case .connected, .disconnected, .suspended:
                hadActiveSession = true
            case .idle, .connecting, .failed:
                hadActiveSession = snapshot.connectionInfo != nil || snapshot.lastFrameDate != nil || snapshot.receivedFrameCount > 0
            }
            let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedReason: String? = (trimmed?.isEmpty == false) ? trimmed : nil
            snapshot.latestFrame = nil
            snapshot.connectionInfo = nil
            if let normalizedReason, hadActiveSession {
                snapshot.state = .disconnected(normalizedReason)
            } else {
                snapshot.state = .idle
            }
            snapshot.revision &+= 1

        case .failed(let message):
            snapshot.state = .failed(message)
            snapshot.retryCount += 1
            snapshot.revision &+= 1
        }
    }

    func currentSnapshot() -> Snapshot { snapshot }

    func resetRetry() {
        snapshot.retryCount = 0
        snapshot.revision &+= 1
    }

    func setSuspended(_ reason: NDIStreamSuspensionReason?) {
        guard let reason, reason != .none else {
            if case .suspended = snapshot.state {
                snapshot.state = snapshot.latestFrame == nil ? .idle : .connected
                snapshot.revision &+= 1
            }
            return
        }
        snapshot.state = .suspended(reason)
        snapshot.revision &+= 1
    }
}

