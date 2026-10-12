import Foundation
import Observation

enum NDIStreamSuspensionReason: String, Codable, CaseIterable, Hashable {
    case none
    case hiddenTile
    case inactiveTab
    case tinyTile
    case overBudget
    case userPaused
}

struct NDIStreamSnapshot: Identifiable, Equatable {
    let id: String
    var sourceID: String
    var interfaceID: String?
    var qualityTier: NDIModuleModel.QualityTier
    var tabID: UUID
    var subscriberCount: Int
    var suspensionReason: NDIStreamSuspensionReason
    var estimatedFPS: Double
}

enum NDIAcquireResult {
    case stream(NDIManagedStream)
    case overBudget
}

@MainActor
@Observable
final class NDIManagedStream: Identifiable {
    let id: String
    let pipeline: NDIFramePipeline

    var snapshot: NDIStreamSnapshot

    private let controller: NDIReceiverController

    init(id: String, snapshot: NDIStreamSnapshot, controller: NDIReceiverController) {
        self.id = id
        self.snapshot = snapshot
        self.controller = controller
        self.pipeline = controller.pipeline
    }

    func start() { controller.start() }
    func stop() { controller.stop() }
    func setSuspended(_ reason: NDIStreamSuspensionReason?) { controller.setSuspended(reason) }
}

@MainActor
@Observable
final class NDIStreamRegistry {
    static let shared = NDIStreamRegistry()

    private(set) var activeStreams: [String: NDIManagedStream] = [:]

    // Internal init exposed for testability; use .shared in production code.
    init() {}

    func ndiModuleCount(forTab tabID: UUID) -> Int {
        let tabStreams = activeStreams.values.filter { $0.snapshot.tabID == tabID }
        return tabStreams.count
    }

    func acquireStream(
        for model: NDIModuleModel,
        resolvedInterfaceID: String?,
        tabID: UUID
    ) -> NDIAcquireResult {
        let streamID = [
            model.sourceID.trimmingCharacters(in: .whitespacesAndNewlines),
            resolvedInterfaceID ?? "auto",
            model.qualityTier.rawValue,
            "\(model.fpsCap)",
            tabID.uuidString
        ].joined(separator: "::")

        if let existing = activeStreams[streamID] {
            existing.snapshot.subscriberCount += 1
            return .stream(existing)
        }

        // Enforce per-tab budget (2 distinct active streams max)
        if ndiModuleCount(forTab: tabID) >= 2 {
            return .overBudget
        }

        let nextSnapshot = NDIStreamSnapshot(
            id: streamID,
            sourceID: model.sourceID,
            interfaceID: resolvedInterfaceID,
            qualityTier: model.qualityTier,
            tabID: tabID,
            subscriberCount: 1,
            suspensionReason: .none,
            estimatedFPS: min(Double(model.fpsCap), model.qualityTier.defaultFPS)
        )

        let selectedSource = NDIDiscoveryService.shared.sources.first(where: { $0.id == model.sourceID })

        let receiverConfig = NDIReceiverConfiguration(
            sourceID: model.sourceID,
            sourceName: selectedSource?.name ?? model.sourceName,
            sourceURLAddress: selectedSource?.urlAddress,
            interfaceID: resolvedInterfaceID,
            qualityTier: model.qualityTier,
            fpsCap: model.fpsCap,
            audioEnabled: model.audioEnabled,
            preferLowLatency: model.preferLowLatency
        )
        let controller = NDIReceiverController(configuration: receiverConfig)
        let managed = NDIManagedStream(id: streamID, snapshot: nextSnapshot, controller: controller)
        managed.start()
        activeStreams[streamID] = managed
        return .stream(managed)
    }

    func release(streamID: String) {
        guard let stream = activeStreams[streamID] else { return }
        stream.snapshot.subscriberCount -= 1
        if stream.snapshot.subscriberCount <= 0 {
            stream.stop()
            activeStreams.removeValue(forKey: streamID)
        }
    }
}
