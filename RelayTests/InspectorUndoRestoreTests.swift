import XCTest
@testable import Relay

final class InspectorUndoCoalescerResetTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 3_000)

    func testTypingRightAfterUndoOpensANewStep() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        let key = InspectorUndoCoalescer.moduleKey(actionName: "Change Text Settings", moduleID: UUID())
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: key, now: t0))
        XCTAssertFalse(coalescer.shouldRegisterUndo(actionName: key, now: t0.addingTimeInterval(0.2)))
        // ⌘Z removes that step; typing again within the window must register a new one.
        coalescer.reset()
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: key, now: t0.addingTimeInterval(0.4)))
    }

    func testResetEndsAStuckDrag() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        coalescer.beginContinuousEdit()
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "A", now: t0))
        coalescer.reset()
        XCTAssertFalse(coalescer.isContinuousEditActive)
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "A", now: t0.addingTimeInterval(5)))
    }

    func testSuppressedChangesRegisterNothingAndDontFoldTheNextEdit() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        coalescer.suppressRegistrations(until: t0.addingTimeInterval(0.5))
        XCTAssertFalse(coalescer.shouldRegisterUndo(actionName: "Seed", now: t0))
        XCTAssertFalse(coalescer.shouldRegisterUndo(actionName: "Seed", now: t0.addingTimeInterval(0.3)))
        // After the window the same key opens a step: suppressed writes didn't start one.
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "Seed", now: t0.addingTimeInterval(0.6)))
    }
}

final class InspectorModuleRestoreTests: XCTestCase {
    private struct Item: Identifiable, Equatable {
        let id: Int
        var value: String
    }

    private let t0 = Date(timeIntervalSinceReferenceDate: 4_000)
    private let local = [Item(id: 1, value: "a"), Item(id: 2, value: "b")]
    private var restored: [Item] { [Item(id: 1, value: "old"), Item(id: 2, value: "b")] }

    func testChangedValueRightAfterUndoIsARestore() {
        XCTAssertTrue(InspectorModuleRestore.isRestore(
            local: local, incoming: restored, lastUndoRedoAt: t0, isDragging: false, now: t0.addingTimeInterval(0.1)
        ))
    }

    func testOwnEditIsNotARestore() {
        XCTAssertFalse(InspectorModuleRestore.isRestore(
            local: local, incoming: local, lastUndoRedoAt: t0, isDragging: false, now: t0.addingTimeInterval(0.1)
        ))
    }

    func testNoRecentUndoIsNotARestore() {
        XCTAssertFalse(InspectorModuleRestore.isRestore(
            local: local, incoming: restored, lastUndoRedoAt: nil, isDragging: false, now: t0
        ))
        XCTAssertFalse(InspectorModuleRestore.isRestore(
            local: local, incoming: restored, lastUndoRedoAt: t0, isDragging: false, now: t0.addingTimeInterval(2)
        ))
    }

    func testAddedOrRemovedModulesAreNotARestore() {
        XCTAssertFalse(InspectorModuleRestore.isRestore(
            local: local, incoming: [local[0]], lastUndoRedoAt: t0, isDragging: false, now: t0.addingTimeInterval(0.1)
        ))
        XCTAssertFalse(InspectorModuleRestore.isRestore(
            local: local, incoming: local + [Item(id: 3, value: "c")], lastUndoRedoAt: t0, isDragging: false,
            now: t0.addingTimeInterval(0.1)
        ))
    }

    func testNeverDuringADrag() {
        XCTAssertFalse(InspectorModuleRestore.isRestore(
            local: local, incoming: restored, lastUndoRedoAt: t0, isDragging: true, now: t0.addingTimeInterval(0.1)
        ))
    }
}
