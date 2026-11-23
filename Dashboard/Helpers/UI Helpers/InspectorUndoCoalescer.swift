import Foundation

/// Decides whether an inspector edit opens a new undo step or folds into the current one.
///
/// Every inspector change registers a whole-document undo snapshot. A slider drag or a
/// colour-panel drag sends dozens of changes, which used to become dozens of undo steps.
///
/// - During a continuous edit (between a slider's `onEditingChanged(true)` and `(false)`),
///   only the first change registers a step.
/// - Repeated changes with the same action name within `window` of each other also fold
///   into one step. This covers controls without begin/end callbacks (colour panels, steppers)
///   and the slider's final value, which can arrive just after `onEditingChanged(false)`.
struct InspectorUndoCoalescer {
    static let defaultWindow: TimeInterval = 0.6

    let window: TimeInterval
    private(set) var isContinuousEditActive = false
    private var currentActionName: String?
    private var lastActivity: Date?

    init(window: TimeInterval = InspectorUndoCoalescer.defaultWindow) {
        self.window = window
    }

    /// A drag started: its first change gets its own undo step.
    mutating func beginContinuousEdit() {
        isContinuousEditActive = true
        currentActionName = nil
    }

    mutating func endContinuousEdit(now: Date = Date()) {
        isContinuousEditActive = false
        if currentActionName != nil {
            lastActivity = now
        }
    }

    /// Returns true when the caller should register a new undo step for `actionName`.
    mutating func shouldRegisterUndo(actionName: String, now: Date = Date()) -> Bool {
        defer { lastActivity = now }
        if actionName == currentActionName {
            if isContinuousEditActive { return false }
            if let lastActivity, now.timeIntervalSince(lastActivity) < window { return false }
        }
        currentActionName = actionName
        return true
    }

    /// Coalescing key for an edit to one module's settings: edits to the same module fold
    /// together, while the same kind of edit on another module starts its own undo step.
    static func moduleKey(actionName: String, moduleID: UUID) -> String {
        "\(actionName)#\(moduleID.uuidString)"
    }
}
