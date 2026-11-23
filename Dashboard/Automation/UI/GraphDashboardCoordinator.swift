import SwiftUI
import Combine

final class GraphDashboardRuntimeCoordinator: ObservableObject {
    func configureBindings(
        runtime: GraphAutomationRuntime,
        tabProvider: @escaping () -> DashboardTab,
        updater: @escaping (_ tabId: UUID, _ graph: DashboardGraph) -> Void
    ) {
        runtime.setActiveTabProvider(tabProvider)
        runtime.setActiveTabGraphUpdater(updater)
    }

    func activate(
        runtime: GraphAutomationRuntime,
        tabProvider: @escaping () -> DashboardTab,
        updater: @escaping (_ tabId: UUID, _ graph: DashboardGraph) -> Void
    ) {
        configureBindings(runtime: runtime, tabProvider: tabProvider, updater: updater)
        runtime.setEnabled(true)
    }
}

final class GraphDashboardNotificationHub: ObservableObject {
    @Published var addNodeRequestedTick: Int = 0
    @Published var dismissPopoversTick: Int = 0
    @Published var sendAllRequestedTick: Int = 0

    @Published var sendAllDelayMs: Double = 180
    @Published var sendAllIncludeAssignments: Bool = true
    @Published var sendAllIncludeSnapshots: Bool = true

    private var cancellables: Set<AnyCancellable> = []

    init(center: NotificationCenter = .default) {
        center.publisher(for: Notification.Name("Relay.GraphAddNodeRequested"))
            .sink { [weak self] _ in
                self?.addNodeRequestedTick &+= 1
            }
            .store(in: &cancellables)

        center.publisher(for: Notification.Name("Relay.GraphDismissPopovers"))
            .sink { [weak self] _ in
                self?.dismissPopoversTick &+= 1
            }
            .store(in: &cancellables)

        center.publisher(for: Notification.Name("Relay.GraphSendAllToConsolesRequested"))
            .sink { [weak self] note in
                guard let self else { return }
                self.sendAllDelayMs = (note.userInfo?["delayMs"] as? Double) ?? 180
                self.sendAllIncludeAssignments = (note.userInfo?["includeAssignments"] as? Bool) ?? true
                self.sendAllIncludeSnapshots = (note.userInfo?["includeSnapshots"] as? Bool) ?? true
                self.sendAllRequestedTick &+= 1
            }
            .store(in: &cancellables)
    }
}

final class GraphDashboardUndoProxy: NSObject, ObservableObject {
    var snapshot: (() -> Data?)?
    var restore: ((Data?) -> Void)?

    func register(actionName: String, before: Data?, undoManager: UndoManager?) {
        guard let undoManager else { return }

        // UndoManager does not retain its target, and this proxy is a @StateObject of a
        // view that is rebuilt on every tab switch. Capturing `self` in the handler keeps
        // the proxy alive for as long as an undo/redo step refers to it; otherwise
        // Edit ▸ Undo after switching tabs calls into a freed object.
        undoManager.registerUndo(withTarget: self) { [self] _ in
            let redoState = snapshot?()
            register(actionName: actionName, before: redoState, undoManager: undoManager)
            restore?(before)
        }
        undoManager.setActionName(actionName)
    }

    /// Undo for state that lives outside the graph (console channel assignments are stored on
    /// the device in ExternalDevicesStore). `apply` installs a value and returns the value it
    /// replaced, which becomes the redo step.
    func registerValueUndo<Value>(
        actionName: String,
        previous: Value,
        undoManager: UndoManager?,
        apply: @escaping (Value) -> Value
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [self] _ in
            let replaced = apply(previous)
            registerValueUndo(actionName: actionName, previous: replaced, undoManager: undoManager, apply: apply)
        }
        undoManager.setActionName(actionName)
    }
}
