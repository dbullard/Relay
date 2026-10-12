//
//  DashboardUndoManager.swift
//  Relay
//
//  Created by David Bullard on 11/20/25.
//


import Foundation
import Combine

/// Centralized undo/redo history for the dashboard tabs.
///
/// This type does **not** own the current `tabs` state; instead it
/// keeps snapshots of previous and future states and returns them to
/// the caller on undo/redo. `DashboardRootView` (or any other owner)
/// remains the source of truth for the live `tabs` array.
final class DashboardUndoManager: ObservableObject {
    
    let objectWillChange = ObservableObjectPublisher()
    
    /// The most recent time a snapshot was recorded. Used to coalesce
    /// rapid-fire edits (like slider drags) into a single undo step.
    private var lastSnapshotDate: Date? = nil
    
    /// Minimum time interval between distinct undo snapshots. Any calls
    /// to `pushSnapshot` that occur within this window from the last
    /// snapshot will be ignored, so the earliest state is preserved.
    private let coalescingInterval: TimeInterval = 0.4
    
    private var undoStack: [[DashboardTab]] = []
    private var redoStack: [[DashboardTab]] = []

    /// Records a snapshot of the current tabs before a mutation.
    ///
    /// This method also time-coalesces rapid calls (e.g., from slider drags)
    /// into a single undo step: if it is called again within
    /// `coalescingInterval` seconds of the previous snapshot, the new call
    /// is ignored so that the earliest pre-edit state is preserved.
    func pushSnapshot(_ tabs: [DashboardTab]) {
        let now = Date()
        if let last = lastSnapshotDate,
           now.timeIntervalSince(last) < coalescingInterval {
            // Within coalescing window: keep the older snapshot so that one
            // undo step jumps back to the state before the first change.
            return
        }
        
        undoStack.append(tabs)
        // Any new edit invalidates the redo history.
        redoStack.removeAll()
        lastSnapshotDate = now
    }

    /// Steps back to the previous snapshot, if any, returning the
    /// restored tabs array. The caller is responsible for assigning
    /// this back into their live state.
    func undo(current tabs: [DashboardTab]) -> [DashboardTab]? {
        guard let previous = undoStack.popLast() else { return nil }
        // Current state becomes redo candidate.
        redoStack.append(tabs)
        return previous
    }

    /// Steps forward to the next snapshot (if undo has been used),
    /// returning the restored tabs array.
    func redo(current tabs: [DashboardTab]) -> [DashboardTab]? {
        guard let next = redoStack.popLast() else { return nil }
        // Current state becomes undo candidate again.
        undoStack.append(tabs)
        return next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
}
