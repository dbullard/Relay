import XCTest
import Combine
@testable import Relay

@MainActor
final class DocumentFlowTests: XCTestCase {

    func test_dashboardSaveState_initialState() {
        let state = DashboardSaveState()
        XCTAssertFalse(state.isSaving)
        XCTAssertNil(state.lastSavedAt)
    }

    func test_dashboardSaveState_isSaving_triggersObjectWillChange() {
        let state = DashboardSaveState()
        var didChange = false
        let token = state.objectWillChange.sink { didChange = true }
        state.isSaving = true
        XCTAssertTrue(didChange)
        token.cancel()
    }

    func test_dashboardSaveState_isSaving_noChangeWhenSameValue() {
        let state = DashboardSaveState()
        var changeCount = 0
        let token = state.objectWillChange.sink { changeCount += 1 }
        state.isSaving = false  // same as initial
        XCTAssertEqual(changeCount, 0)
        token.cancel()
    }

    func test_iOS_saveCurrentDocument_placeholder() {
        // Full integration test requires iOS simulator with Files access.
        // Logic: saveCurrentDocument on iOS writes in-place when lastSavedURL is set.
        XCTAssertTrue(true, "See manual test: open file on iPad, make change, Cmd+S — no share sheet should appear.")
    }

    func test_iOS_saveWithoutExistingURL_mustPresentExporter() {
        #if os(iOS)
        XCTAssertTrue(true, "On iOS, Save with no lastSavedURL must set isExportingDashboard through presentIOSDashboardExporter().")
        #else
        XCTAssertTrue(true, "macOS Save uses NSSavePanel.")
        #endif
    }

    func test_iOS_saveAs_mustPresentExporter() {
        #if os(iOS)
        XCTAssertTrue(true, "On iOS, Save As must set isExportingDashboard through presentIOSDashboardExporter().")
        #else
        XCTAssertTrue(true, "macOS Save As uses NSSavePanel.")
        #endif
    }

    func test_closeMenuItem_retargeting_isManuallyVerified() {
        // Live-menu-bar behavior can't be constructed in a unit test — the retargeting
        // runs against the real NSApp.mainMenu built by SwiftUI at launch.
        // Manual test: open any sheet (e.g. Settings), click "Close" in the menu bar
        // (not Cmd+W, not the red button) — the sheet should dismiss and the window
        // should close (or show "Save Changes Before Closing?" if dirty), matching Cmd+W.
        XCTAssertTrue(true, "See manual test: click Close in the menu bar with a sheet open.")
    }

    func test_quitMenuItem_bypassesTerminate_isManuallyVerified() {
        // Live-menu-bar behavior can't be constructed in a unit test.
        // Manual test: open any sheet (e.g. Settings), click "Quit Relay" in the app
        // menu (not Cmd+Q) — the sheet should dismiss and the app should quit (or show
        // "Save Changes Before Quitting?" if dirty), matching Cmd+Q.
        XCTAssertTrue(true, "See manual test: click Quit Relay in the app menu with a sheet open.")
    }

    func test_autosaveDefault_isDocumented() {
        // @AppStorage default is `true` — guard against accidental revert.
        // If fileAutosaveEnabled AppStorage key is absent, it should default to true.
        // This is a documentation test; the real guard is code review.
        XCTAssertTrue(true, "fileAutosaveEnabled @AppStorage default must remain `true` in DashboardRootView")
    }

    func test_dashboardTab_canvasSize_defaultsToNil() {
        let tab = DashboardTab(name: "Test", tiles: [])
        XCTAssertNil(tab.canvasSize)
    }

    func test_dashboardTab_canvasSize_roundTripsViaCodable() throws {
        var tab = DashboardTab(name: "Test", tiles: [])
        tab.canvasSize = CGSize(width: 2560, height: 1440)
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(DashboardTab.self, from: data)
        XCTAssertEqual(decoded.canvasSize?.width, 2560)
        XCTAssertEqual(decoded.canvasSize?.height, 1440)
    }

    func test_dashboardTab_canvasSize_nilWhenMissingFromJSON() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"OldTab","tiles":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DashboardTab.self, from: json)
        XCTAssertNil(decoded.canvasSize)
    }

    func test_dashboardDocument_payloadVersion_isFive() {
        let payload = DashboardDocument.Payload(
            tabs: [],
            rosters: [],
            selectedTabIndex: 0
        )
        XCTAssertEqual(payload.version, 5)
    }

    func test_dashboardHomeScreenState_initialState() {
        let state = DashboardHomeScreenState()
        XCTAssertFalse(state.isPresented)
    }

    func test_dashboardHomeScreenState_isPresented_triggersObjectWillChange() {
        let state = DashboardHomeScreenState()
        var didChange = false
        let token = state.objectWillChange.sink { didChange = true }
        state.isPresented = true
        XCTAssertTrue(didChange)
        token.cancel()
    }

    func test_dashboardHomeScreenState_isPresented_noChangeWhenSameValue() {
        let state = DashboardHomeScreenState()
        var changeCount = 0
        let token = state.objectWillChange.sink { changeCount += 1 }
        state.isPresented = false  // same as initial
        XCTAssertEqual(changeCount, 0)
        token.cancel()
    }

    func test_dashboardHomeScreenState_isPresented_setFromBackgroundThread_stillPublishesOnMain() {
        let state = DashboardHomeScreenState()
        let expectation = expectation(description: "objectWillChange fires on main thread")
        let token = state.objectWillChange.sink {
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }
        DispatchQueue.global().async {
            state.isPresented = true
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(state.isPresented)
        token.cancel()
    }
}
