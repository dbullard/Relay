import XCTest
import AppKit
@testable import Relay

@MainActor
final class LiveModeMenuBarControllerTests: XCTestCase {

    func testHidesOnlyWhenLiveAndFullScreen() {
        XCTAssertTrue(LiveModeMenuBarPolicy.shouldHideMenuBar(isLiveMode: true, isFullScreen: true))
        XCTAssertFalse(LiveModeMenuBarPolicy.shouldHideMenuBar(isLiveMode: true, isFullScreen: false))
        XCTAssertFalse(LiveModeMenuBarPolicy.shouldHideMenuBar(isLiveMode: false, isFullScreen: true))
        XCTAssertFalse(LiveModeMenuBarPolicy.shouldHideMenuBar(isLiveMode: false, isFullScreen: false))
    }

    func testHiddenOptionsSwapAutoHideForHide() {
        let hidden = LiveModeMenuBarPolicy.hiddenOptions(
            from: [.fullScreen, .autoHideMenuBar, .autoHideDock, .autoHideToolbar]
        )
        XCTAssertEqual(hidden, [.fullScreen, .hideMenuBar, .hideDock, .autoHideToolbar])
    }

    func testRestoreReturnsBaseOptions() {
        let c = LiveModeMenuBarController()
        let base: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]

        let hidden = c.apply(hide: true, current: base)
        XCTAssertTrue(hidden.contains(.hideMenuBar))
        XCTAssertFalse(hidden.contains(.autoHideMenuBar))
        XCTAssertEqual(c.savedBaseOptions, base)

        // A second hide must not overwrite the saved base with the hidden set.
        _ = c.apply(hide: true, current: hidden)
        XCTAssertEqual(c.savedBaseOptions, base)

        XCTAssertEqual(c.apply(hide: false, current: hidden), base)
        XCTAssertNil(c.savedBaseOptions)
    }
}
