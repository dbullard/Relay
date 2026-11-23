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
    private var suppressedUntil: Date?

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

    /// An undo or redo ran: the step being coalesced no longer exists, so the next change
    /// must open a new one (otherwise it folds into nothing and redo survives it).
    mutating func reset() {
        isContinuousEditActive = false
        currentActionName = nil
        lastActivity = nil
    }

    /// Changes before `date` register no undo step. Used while a settings view rebuilt after
    /// an undo/redo writes its defaults as it appears; registering those would clear redo
    /// and recreate the step that was just undone.
    mutating func suppressRegistrations(until date: Date) {
        suppressedUntil = date
    }

    /// Returns true when the caller should register a new undo step for `actionName`.
    mutating func shouldRegisterUndo(actionName: String, now: Date = Date()) -> Bool {
        if let suppressedUntil {
            if now < suppressedUntil { return false }
            self.suppressedUntil = nil
        }
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

/// Decides whether a change to the edited tile's modules is an undo/redo restore that the
/// inspector must re-seed its module settings from.
enum InspectorModuleRestore {
    /// How soon after an undo/redo a module change still counts as its restore.
    static let window: TimeInterval = 1

    /// - `local`: the inspector's own copy, which its edits update before they reach the tile.
    /// - A change that adds or removes modules is never a restore here: the settings view is
    ///   rebuilt anyway because its identity includes the module ids.
    /// - Never while a slider is being dragged, so a restore can't rebuild it mid-drag.
    static func isRestore<M: Identifiable & Equatable>(
        local: [M],
        incoming: [M],
        lastUndoRedoAt: Date?,
        isDragging: Bool,
        now: Date = Date()
    ) -> Bool {
        guard !isDragging, incoming != local else { return false }
        guard let lastUndoRedoAt, now.timeIntervalSince(lastUndoRedoAt) < window else { return false }
        return Set(local.map(\.id)) == Set(incoming.map(\.id))
    }
}
