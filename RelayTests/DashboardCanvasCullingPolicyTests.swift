import XCTest
@testable import Relay

/// One assertion per `DashboardModuleKind` case so a future reviewer can see
/// at a glance what's claimed about each one, and so adding a case (a compile
/// error in `DashboardCanvasCullingPolicy.holdsLiveResource`'s exhaustive
/// switch) also forces a decision here.
final class DashboardCanvasCullingPolicyTests: XCTestCase {

    // MARK: - Holds a live resource (socket / stream / continuous poll / audio /
    // OSC tap) -- must never be culled.

    func testNDIHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.ndi(NDIModuleModel())))
    }

    func testWebpageHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.webpage(WebpageModuleModel())))
    }

    func testYouTubeStreamMonitorHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.youtubeStreamMonitor(YouTubeStreamMonitorModuleModel())))
    }

    func testLiveTranscriptionHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.liveTranscription(LiveTranscriptionModuleModel())))
    }

    func testRTAHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.rta(RTAModuleModel())))
    }

    func testSpectrographHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.spectrograph(SpectrogramModuleModel())))
    }

    func testDAWTransportHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.dawTransport))
    }

    func testTimecodeHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.timecode))
    }

    func testProPresenterHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.proPresenter))
    }

    func testShureWirelessHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.shureWireless))
    }

    func testShureOverviewHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.shureOverview))
    }

    func testSennheiserWirelessHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.sennheiserWireless))
    }

    func testResolumeHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.resolume(ResolumeModuleModel())))
    }

    func testDbReaderHoldsLiveResource() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.holdsLiveResource(.dbReader(DbReaderModuleModel())))
    }

    // MARK: - Static/derived content -- safe to cull.

    func testPersonDoesNotHoldLiveResource() {
        let person = PersonTileModel(name: "Jane Doe", role: "Vocalist", initials: "JD")
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.person(person)))
    }

    func testPCORundownDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.pcoRundown))
    }

    func testPCOTeamAssignmentsDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.pcoTeamAssignments))
    }

    func testRosterTeamAssignmentsDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.rosterTeamAssignments))
    }

    func testRosterPickerDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.rosterPicker(RosterPickerModuleModel())))
    }

    func testTextDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.text(TextModuleModel())))
    }

    func testImageDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.image(ImageModuleModel())))
    }

    func testDocumentDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.document(DocumentModuleModel())))
    }

    func testSeparatorDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.separator(SeparatorModuleModel())))
    }

    func testTimeDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.time))
    }

    func testButtonDoesNotHoldLiveResource() {
        XCTAssertFalse(DashboardCanvasCullingPolicy.holdsLiveResource(.button(ButtonModuleModel())))
    }

    // MARK: - isCullable(_:) tile-level wrapper

    func testTileWithNoModulesIsCullable() {
        let tile = DashboardTileModel(id: UUID(), kind: .empty, offset: .zero, size: nil)
        XCTAssertTrue(DashboardCanvasCullingPolicy.isCullable(tile))
    }

    func testTileWithEmptyModulesArrayIsCullable() {
        var tile = DashboardTileModel(id: UUID(), kind: .empty, offset: .zero, size: nil)
        tile.modules = []
        XCTAssertTrue(DashboardCanvasCullingPolicy.isCullable(tile))
    }

    func testTileWithOnlyStaticModulesIsCullable() {
        var tile = DashboardTileModel(id: UUID(), kind: .empty, offset: .zero, size: nil)
        tile.modules = [
            DashboardModuleModel(kind: .text(TextModuleModel()), order: 0),
            DashboardModuleModel(kind: .pcoRundown, order: 1),
        ]
        XCTAssertTrue(DashboardCanvasCullingPolicy.isCullable(tile))
    }

    func testTileWithOneLiveModuleAmongStaticOnesIsNotCullable() {
        var tile = DashboardTileModel(id: UUID(), kind: .empty, offset: .zero, size: nil)
        tile.modules = [
            DashboardModuleModel(kind: .text(TextModuleModel()), order: 0),
            DashboardModuleModel(kind: .ndi(NDIModuleModel()), order: 1),
        ]
        XCTAssertFalse(DashboardCanvasCullingPolicy.isCullable(tile))
    }

    // MARK: - shouldRender(tile:visibleTileIDs:isSelected:isEditing:isDraggingAnywhereOnCanvas:)
    //
    // This is the exact OR-chain `DashboardTileCanvas` uses to decide whether
    // to mount a tile, extracted so it can be regression-tested independently
    // of the view body. Each test isolates one branch of the chain.

    private func offscreenCullableTile() -> DashboardTileModel {
        DashboardTileModel(id: UUID(), kind: .empty, offset: CGSize(width: 5000, height: 5000), size: nil)
    }

    func testShouldRenderTrueWhenCullingDisabled() {
        // `visibleTileIDs == nil` is how the canvas signals culling is off --
        // must always render regardless of every other input.
        XCTAssertTrue(DashboardCanvasCullingPolicy.shouldRender(
            tile: offscreenCullableTile(), visibleTileIDs: nil,
            isSelected: false, isEditing: false, isDraggingAnywhereOnCanvas: false))
    }

    func testShouldRenderTrueForLiveResourceTileEvenWhenOffscreenAndNotInVisibleSet() {
        var tile = offscreenCullableTile()
        tile.modules = [DashboardModuleModel(kind: .ndi(NDIModuleModel()), order: 0)]
        XCTAssertTrue(DashboardCanvasCullingPolicy.shouldRender(
            tile: tile, visibleTileIDs: [],
            isSelected: false, isEditing: false, isDraggingAnywhereOnCanvas: false))
    }

    func testShouldRenderTrueWhenTileIDInVisibleSet() {
        let tile = DashboardTileModel(id: UUID(), kind: .empty, offset: .zero, size: nil)
        XCTAssertTrue(DashboardCanvasCullingPolicy.shouldRender(
            tile: tile, visibleTileIDs: [tile.id],
            isSelected: false, isEditing: false, isDraggingAnywhereOnCanvas: false))
    }

    func testShouldRenderFalseForOffscreenCullableUninvolvedTile() {
        // The one case where the tile should actually be culled: cullable,
        // off-screen, unselected, not being edited, and no drag in progress.
        XCTAssertFalse(DashboardCanvasCullingPolicy.shouldRender(
            tile: offscreenCullableTile(), visibleTileIDs: [],
            isSelected: false, isEditing: false, isDraggingAnywhereOnCanvas: false))
    }

    func testShouldRenderTrueWhenSelectedEvenIfOffscreen() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.shouldRender(
            tile: offscreenCullableTile(), visibleTileIDs: [],
            isSelected: true, isEditing: false, isDraggingAnywhereOnCanvas: false))
    }

    func testShouldRenderTrueWhenEditingEvenIfOffscreen() {
        XCTAssertTrue(DashboardCanvasCullingPolicy.shouldRender(
            tile: offscreenCullableTile(), visibleTileIDs: [],
            isSelected: false, isEditing: true, isDraggingAnywhereOnCanvas: false))
    }

    func testShouldRenderTrueWhileDraggingAnywhereOnCanvasEvenIfOffscreenAndUnselected() {
        // Guards the drag-anywhere exemption: an unrelated, unselected,
        // off-screen tile must still render for the whole duration of any
        // drag gesture on the canvas -- see the doc comment on
        // `isDraggingAnywhereOnCanvas` for why this is coarser than gating on
        // the specific dragged tile's ID.
        XCTAssertTrue(DashboardCanvasCullingPolicy.shouldRender(
            tile: offscreenCullableTile(), visibleTileIDs: [],
            isSelected: false, isEditing: false, isDraggingAnywhereOnCanvas: true))
    }
}
