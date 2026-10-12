import Foundation
import Observation

struct NDISourceDescriptor: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var hostName: String?
    var interfaceHint: String?
    var urlAddress: String?
}

@MainActor
@Observable
final class NDIDiscoveryService {
    static let shared = NDIDiscoveryService()

    private let discoveryBackend: any NDISDKDiscovering
    private var refreshTask: Task<Void, Never>?
    private var pendingPreferredInterfaceID: String?

    private(set) var interfaces: [NDIInterfaceDescriptor] = []
    private(set) var sources: [NDISourceDescriptor] = []
    private(set) var lastRefreshDate: Date?

    // Default-parameter call site evaluates in a nonisolated context before the
    // init body runs on the main actor. makeDiscoveryBackend() is nonisolated so
    // this is safe; the explicit form makes the call site unambiguous for Swift 6.
    private init(discoveryBackend: any NDISDKDiscovering = NDISDKFactory.makeDiscoveryBackend()) {
        self.discoveryBackend = discoveryBackend
        refreshInterfaces()
    }

    func refreshInterfaces() {
        interfaces = NDIInterfaceEnumerator.currentInterfaces()
        lastRefreshDate = Date()
    }

    func interfaceDescriptor(id: String?) -> NDIInterfaceDescriptor? {
        guard let id else { return nil }
        return interfaces.first(where: { $0.id == id })
    }

    func requestSourceRefresh(preferredInterfaceID: String? = nil) {
        pendingPreferredInterfaceID = preferredInterfaceID

        guard refreshTask == nil else { return }

        refreshTask = Task.detached(priority: .utility) { [weak self, backend = discoveryBackend] in
            guard let self else { return }

            while !Task.isCancelled {
                let preferredInterfaceID = await MainActor.run { () -> String? in
                    let next = self.pendingPreferredInterfaceID
                    self.pendingPreferredInterfaceID = nil
                    return next
                }

                let newSources = await backend.refreshSources(preferredInterfaceID: preferredInterfaceID)

                let shouldContinue = await MainActor.run { () -> Bool in
                    self.sources = newSources
                    self.lastRefreshDate = Date()

                    if self.pendingPreferredInterfaceID == nil {
                        self.refreshTask = nil
                        return false
                    }

                    return true
                }

                if !shouldContinue {
                    break
                }
            }
        }
    }

    func refreshSources(preferredInterfaceID: String? = nil) async {
        sources = await discoveryBackend.refreshSources(preferredInterfaceID: preferredInterfaceID)
        lastRefreshDate = Date()
    }

    func shouldRefreshSources(
        preferredInterfaceID: String? = nil,
        selectedSourceID: String? = nil,
        maxAge: TimeInterval = 5
    ) -> Bool {
        let normalizedSelectedSourceID = selectedSourceID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedSelectedSourceID,
           !normalizedSelectedSourceID.isEmpty,
           !sources.contains(where: { $0.id == normalizedSelectedSourceID }) {
            return true
        }

        guard let lastRefreshDate else { return true }
        return Date().timeIntervalSince(lastRefreshDate) > maxAge
    }
}
