import Foundation
import Observation

@MainActor
@Observable
final class NDIFramePipeline {
    nonisolated enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(String)
        case suspended(NDIStreamSuspensionReason)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var latestFrame: NDIFrame?
    private(set) var connectionInfo: NDIReceiverConnectionInfo?
    private(set) var droppedFrameCount: Int = 0
    private(set) var receivedFrameCount: Int = 0
    private(set) var latestFrameNumber: UInt64 = 0
    private(set) var retryCount: Int = 0

    var latestResolutionText: String {
        if let latestFrame { return latestFrame.resolutionText }
        if let connectionInfo { return "\(Int(connectionInfo.resolution.width))x\(Int(connectionInfo.resolution.height))" }
        return ""
    }

    var latestFPSText: String {
        if let latestFrame { return String(format: "%.0f fps", latestFrame.estimatedFPS) }
        if let connectionInfo, connectionInfo.frameRate > 0 { return String(format: "%.0f fps", connectionInfo.frameRate) }
        return ""
    }

    func applySnapshot(_ snapshot: NDIFrameProcessor.Snapshot) {
        state = snapshot.state
        latestFrame = snapshot.latestFrame
        connectionInfo = snapshot.connectionInfo
        droppedFrameCount = snapshot.droppedFrameCount
        receivedFrameCount = snapshot.receivedFrameCount
        latestFrameNumber = snapshot.latestFrameNumber
        retryCount = snapshot.retryCount
    }

}
