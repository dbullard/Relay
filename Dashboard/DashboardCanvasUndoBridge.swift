//
//  DashboardCanvasUndoBridge.swift
//  Relay
//

#if canImport(SwiftUI)
import SwiftUI
#endif
import Foundation

/// Records canvas edits as whole-document undo steps on the window's `UndoManager`.
///
/// A step snapshots the tabs, the selected tab and the shared automation graph. The shared
/// graph lives outside `tabs` (`universalGraph`), and canvas edits such as Delete Tiles prune
/// links and node settings from it, so a snapshot of `tabs` alone could not put them back.
///
/// Undo and redo re-register each other, so a step can be undone, redone and undone again.
/// The bridge is a class because `UndoManager` needs a class target.
final class DashboardCanvasUndoBridge: NSObject {
    struct Snapshot: Equatable {
        var tabs: [DashboardTab]
        var selectedTabIndex: Int
        var universalGraph: DashboardGraph?
    }

    private var tabs: Binding<[DashboardTab]>?
    private var selectedTabIndex: Binding<Int>?
    private var universalGraph: Binding<DashboardGraph?>?
    private var hasUnsavedChanges: Binding<Bool>?

    func bind(
        tabs: Binding<[DashboardTab]>,
        selectedTabIndex: Binding<Int>,
        universalGraph: Binding<DashboardGraph?>,
        hasUnsavedChanges: Binding<Bool>
    ) {
        self.tabs = tabs
        self.selectedTabIndex = selectedTabIndex
        self.universalGraph = universalGraph
        self.hasUnsavedChanges = hasUnsavedChanges
    }

    /// The current document state, or nil before `bind` has run.
    func currentSnapshot() -> Snapshot? {
        guard let tabs, let selectedTabIndex else { return nil }
        return Snapshot(
            tabs: tabs.wrappedValue,
            selectedTabIndex: selectedTabIndex.wrappedValue,
            universalGraph: universalGraph?.wrappedValue
        )
    }

    /// Call before a canvas edit: registers an undo step that returns to the current state.
    func registerUndo(actionName: String, undoManager: UndoManager?) {
        guard let undoManager, let before = currentSnapshot() else { return }
        registerRestore(of: before, actionName: actionName, undoManager: undoManager)
    }

    private func registerRestore(of snapshot: Snapshot, actionName: String, undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: self) { bridge in
            // Registering inside an undo puts the step on the redo stack (and inside a redo,
            // back on the undo stack), so each direction can always be reversed.
            if let current = bridge.currentSnapshot() {
                bridge.registerRestore(of: current, actionName: actionName, undoManager: undoManager)
            }
            bridge.apply(snapshot)
        }
        undoManager.setActionName(actionName)
    }

    private func apply(_ snapshot: Snapshot) {
        tabs?.wrappedValue = snapshot.tabs
        if snapshot.tabs.isEmpty {
            selectedTabIndex?.wrappedValue = 0
        } else {
            selectedTabIndex?.wrappedValue = min(max(snapshot.selectedTabIndex, 0), snapshot.tabs.count - 1)
        }
        if let universalGraph, universalGraph.wrappedValue != snapshot.universalGraph {
            universalGraph.wrappedValue = snapshot.universalGraph
        }
        hasUnsavedChanges?.wrappedValue = true
    }
}
