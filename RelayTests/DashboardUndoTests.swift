import XCTest
import SwiftUI
@testable import Relay

/// Canvas undo (`DashboardCanvasUndoBridge`) and Automation graph undo
/// (`GraphDashboardUndoProxy`) share the window's `UndoManager`.
@MainActor
final class DashboardUndoTests: XCTestCase {

    /// Mutable stand-in for the dashboard's `@State` (tabs, selection, shared graph).
    private final class DocumentState {
        var tabs: [DashboardTab] = []
        var selectedTabIndex = 0
        var universalGraph: DashboardGraph?
        var hasUnsavedChanges = false
    }

    private var state: DocumentState!
    private var undoManager: UndoManager!
    private var canvasBridge: DashboardCanvasUndoBridge!

    override func setUp() async throws {
        try await super.setUp()
        state = DocumentState()
        state.tabs = [DashboardTab(name: "Main", tiles: [])]
        state.universalGraph = DashboardGraph()

        undoManager = UndoManager()
        undoManager.groupsByEvent = false

        canvasBridge = DashboardCanvasUndoBridge()
        let s = state!
        canvasBridge.bind(
            tabs: Binding(get: { s.tabs }, set: { s.tabs = $0 }),
            selectedTabIndex: Binding(get: { s.selectedTabIndex }, set: { s.selectedTabIndex = $0 }),
            universalGraph: Binding(get: { s.universalGraph }, set: { s.universalGraph = $0 }),
            hasUnsavedChanges: Binding(get: { s.hasUnsavedChanges }, set: { s.hasUnsavedChanges = $0 })
        )
    }

    // MARK: - Helpers

    /// One user action = one undo group, as an event-driven UndoManager would make it.
    private func step(_ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    private func makeTile(named name: String) -> DashboardTileModel {
        let person = PersonTileModel(name: name, role: "", initials: "X")
        let module = DashboardModuleModel(kind: .person(person), order: 0, id: UUID())
        return DashboardTileModel(name: name, kind: .person(person), modules: [module], offset: .zero)
    }

    /// A graph undo proxy wired to the shared graph, the way the Automation view wires it
    /// (graph snapshots are encoded with the persistence adapter).
    private func makeGraphProxy() -> GraphDashboardUndoProxy {
        let proxy = GraphDashboardUndoProxy()
        let s = state!
        proxy.snapshot = { s.universalGraph.flatMap(GraphDashboardPersistenceAdapter.encodeGraph) }
        proxy.restore = { data in
            s.universalGraph = data.flatMap(GraphDashboardPersistenceAdapter.decodeGraph)
        }
        return proxy
    }

    private var graphNodeKeys: [String] {
        state.universalGraph?.moduleGroupNodeInstances.map(\.groupKey) ?? []
    }

    // MARK: - Canvas undo

    func testCanvasUndoRestoresSharedGraphPrunedByTheEdit() {
        let tile = makeTile(named: "Alex")
        state.tabs[0].tiles = [tile]
        let link = GraphLink(fromTileId: tile.id, fromPortId: "a", toTileId: UUID(), toPortId: "b", kind: .patch)
        state.universalGraph?.links = [link]

        // Delete Tiles removes the tile and prunes its links from the shared graph.
        step {
            canvasBridge.registerUndo(actionName: "Delete Tiles", undoManager: undoManager)
            state.tabs[0].tiles.removeAll()
            state.universalGraph?.links.removeAll()
        }

        undoManager.undo()
        XCTAssertEqual(state.tabs[0].tiles.map(\.id), [tile.id])
        XCTAssertEqual(state.universalGraph?.links, [link], "Undo must bring back the tile's links in the shared graph")
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testCanvasStepCanBeUndoneRedoneAndUndoneAgain() {
        let tile = makeTile(named: "Alex")
        step {
            canvasBridge.registerUndo(actionName: "Add Tile", undoManager: undoManager)
            state.tabs[0].tiles.append(tile)
        }

        undoManager.undo()
        XCTAssertTrue(state.tabs[0].tiles.isEmpty)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        XCTAssertEqual(state.tabs[0].tiles.map(\.id), [tile.id])
        XCTAssertTrue(undoManager.canUndo, "Redo must put the step back on the undo stack")
        XCTAssertEqual(undoManager.undoActionName, "Add Tile")

        undoManager.undo()
        XCTAssertTrue(state.tabs[0].tiles.isEmpty)
    }

    // MARK: - Graph undo

    func testGraphUndoStillWorksAfterTheAutomationViewIsGone() {
        weak var weakProxy: GraphDashboardUndoProxy?
        // Pools are drained explicitly so the release checks don't depend on autorelease timing.
        autoreleasepool {
            let proxy = makeGraphProxy()
            weakProxy = proxy
            let before = proxy.snapshot?()
            step {
                state.universalGraph?.moduleGroupNodeInstances.append(.init(groupKey: "utility.counter"))
                proxy.register(actionName: "Add Node", before: before, undoManager: undoManager)
            }
            // Leaving this scope stands in for a tab switch rebuilding the Automation view,
            // which drops its @StateObject proxy.
        }
        XCTAssertNotNil(weakProxy, "A registered undo step must keep its proxy alive")

        autoreleasepool {
            undoManager.undo()
            XCTAssertEqual(graphNodeKeys, [])
            undoManager.redo()
            XCTAssertEqual(graphNodeKeys, ["utility.counter"])
        }

        autoreleasepool { undoManager.removeAllActions() }
        XCTAssertNil(weakProxy, "The proxy is released once no undo step refers to it")
    }

    /// The flow from the bug report: add a canvas tile, then add a graph node in Automation.
    /// Each Undo reverses only the most recent edit, and nothing is skipped.
    func testCanvasAndGraphStepsUndoInOrder() {
        let tile = makeTile(named: "Clock")
        let proxy = makeGraphProxy()

        step {
            canvasBridge.registerUndo(actionName: "Add Tile", undoManager: undoManager)
            state.tabs[0].tiles.append(tile)
        }
        step {
            let before = proxy.snapshot?()
            state.universalGraph?.moduleGroupNodeInstances.append(.init(groupKey: "utility.counter"))
            proxy.register(actionName: "Add Node", before: before, undoManager: undoManager)
        }

        XCTAssertEqual(undoManager.undoActionName, "Add Node")
        undoManager.undo()
        XCTAssertEqual(graphNodeKeys, [], "First Undo removes the graph node")
        XCTAssertEqual(state.tabs[0].tiles.map(\.id), [tile.id], "and leaves the canvas tile")

        XCTAssertEqual(undoManager.undoActionName, "Add Tile")
        undoManager.undo()
        XCTAssertTrue(state.tabs[0].tiles.isEmpty)
        XCTAssertFalse(undoManager.canUndo)

        undoManager.redo()
        XCTAssertEqual(state.tabs[0].tiles.map(\.id), [tile.id])
        XCTAssertEqual(graphNodeKeys, [])
        undoManager.redo()
        XCTAssertEqual(graphNodeKeys, ["utility.counter"])
        XCTAssertFalse(undoManager.canRedo)
    }
}
