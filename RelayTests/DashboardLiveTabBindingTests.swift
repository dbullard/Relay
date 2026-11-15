import XCTest
import SwiftUI
@testable import Relay

/// Regression tests for the tab binding `DashboardTileContainer` hands to module
/// views. It used to read the tab value captured at the container's last render,
/// so each `tab.x = v` write replaced the whole tab with that old copy. The PCO
/// rundown tile sets several fields in a row after a fetch, so only the last one
/// survived and the fresh rundown rows were dropped, leaving the cached service
/// on screen.
@MainActor
final class DashboardLiveTabBindingTests: XCTestCase {

    /// Wires a coordinator to an in-memory "root" the way `DashboardRootView` does.
    private func makeCoordinator(root: Ref<[DashboardTab]>) -> DashboardCanvasActionCoordinator {
        let coordinator = DashboardCanvasActionCoordinator()
        coordinator.onGetTab = { tabID in root.value.first { $0.id == tabID } }
        coordinator.onSetTab = { newValue in
            guard let index = root.value.firstIndex(where: { $0.id == newValue.id }) else { return }
            root.value[index] = newValue
        }
        return coordinator
    }

    func testSequentialFieldWritesAllPersist() {
        let renderTimeTab = DashboardTab(id: UUID(), name: "Sunday", tiles: [])
        let root = Ref([renderTimeTab])
        let coordinator = makeCoordinator(root: root)
        let tab = coordinator.liveTabBinding(fallback: renderTimeTab)

        // Mirrors PCOTileView.refreshTabPCOAssignments writing a fresh snapshot.
        tab.wrappedValue.pcoSnapshotKey = "new-key"
        tab.wrappedValue.pcoRundownSnapshotTitles = ["Fresh song"]
        tab.wrappedValue.name = "Sunday (refreshed)"

        let stored = root.value[0]
        XCTAssertEqual(stored.pcoSnapshotKey, "new-key")
        XCTAssertEqual(stored.pcoRundownSnapshotTitles, ["Fresh song"])
        XCTAssertEqual(stored.name, "Sunday (refreshed)")
    }

    /// A long-running task (e.g. the Live-mode refresh loop) holds a binding made
    /// from an old render. Its write must not put back fields that changed since,
    /// such as a snapshot saved by the settings sheet's "Refresh Data".
    func testWriteFromOldBindingDoesNotRevertNewerChanges() {
        let renderTimeTab = DashboardTab(id: UUID(), name: "Sunday", tiles: [])
        let root = Ref([renderTimeTab])
        let coordinator = makeCoordinator(root: root)
        let oldBinding = coordinator.liveTabBinding(fallback: renderTimeTab)

        root.value[0].pcoSnapshotKey = "refreshed-elsewhere"
        oldBinding.wrappedValue.name = "Renamed"

        XCTAssertEqual(root.value[0].pcoSnapshotKey, "refreshed-elsewhere")
        XCTAssertEqual(root.value[0].name, "Renamed")
    }

    func testFallsBackToRenderTimeTabWhenRootCannotResolveIt() {
        let renderTimeTab = DashboardTab(id: UUID(), name: "Sunday", tiles: [])
        let coordinator = DashboardCanvasActionCoordinator()
        let tab = coordinator.liveTabBinding(fallback: renderTimeTab)

        XCTAssertEqual(tab.wrappedValue, renderTimeTab)
    }
}

private final class Ref<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
