import XCTest
@testable import Relay

final class TileEditorHeaderTitleTests: XCTestCase {
    func testSingleTileShowsItsName() {
        XCTAssertEqual(TileEditorCopy.headerTitle(tileName: "Stage Left Mic", selectedTileCount: 1), "Stage Left Mic")
    }

    func testNameIsTrimmed() {
        XCTAssertEqual(TileEditorCopy.headerTitle(tileName: "  Lyrics \n", selectedTileCount: 1), "Lyrics")
    }

    func testUnnamedTileFallsBack() {
        XCTAssertEqual(TileEditorCopy.headerTitle(tileName: "", selectedTileCount: 1), "Untitled Tile")
        XCTAssertEqual(TileEditorCopy.headerTitle(tileName: "   ", selectedTileCount: 1), "Untitled Tile")
    }

    func testMultiSelectionShowsCount() {
        XCTAssertEqual(TileEditorCopy.headerTitle(tileName: "Stage Left Mic", selectedTileCount: 3), "3 Tiles")
        XCTAssertEqual(TileEditorCopy.headerTitle(tileName: "", selectedTileCount: 2), "2 Tiles")
    }

    func testZeroCountIsTreatedAsSingleTile() {
        XCTAssertEqual(TileEditorCopy.headerTitle(tileName: "Clock", selectedTileCount: 0), "Clock")
    }
}

final class ModuleSettingsUndoTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 2_000)

    func testActionNameNamesTheModule() {
        XCTAssertEqual(TileEditorCopy.moduleSettingsActionName("Sennheiser"), "Change Sennheiser Settings")
        XCTAssertEqual(TileEditorCopy.moduleSettingsActionName("SPL Meter"), "Change SPL Meter Settings")
    }

    func testModuleKeyDiffersPerModule() {
        let a = UUID(), b = UUID()
        let name = TileEditorCopy.moduleSettingsActionName("Text")
        XCTAssertEqual(
            InspectorUndoCoalescer.moduleKey(actionName: name, moduleID: a),
            InspectorUndoCoalescer.moduleKey(actionName: name, moduleID: a)
        )
        XCTAssertNotEqual(
            InspectorUndoCoalescer.moduleKey(actionName: name, moduleID: a),
            InspectorUndoCoalescer.moduleKey(actionName: name, moduleID: b)
        )
    }

    func testBurstOfTypingInOneModuleIsOneStep() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        let key = InspectorUndoCoalescer.moduleKey(actionName: "Change Text Settings", moduleID: UUID())
        var registered = 0
        for i in 0..<20 where coalescer.shouldRegisterUndo(actionName: key, now: t0.addingTimeInterval(Double(i) * 0.15)) {
            registered += 1
        }
        XCTAssertEqual(registered, 1)
        // A pause starts the next step.
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: key, now: t0.addingTimeInterval(10)))
    }

    func testSameEditOnAnotherModuleIsItsOwnStep() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        let first = InspectorUndoCoalescer.moduleKey(actionName: "Change Text Settings", moduleID: UUID())
        let second = InspectorUndoCoalescer.moduleKey(actionName: "Change Text Settings", moduleID: UUID())
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: first, now: t0))
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: second, now: t0.addingTimeInterval(0.1)))
    }
}
