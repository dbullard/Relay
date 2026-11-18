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

/// Drives `LiveModeMenuBarController` against fake presentation options and full-screen state.
@MainActor
final class LiveModeMenuBarControllerWindowTests: XCTestCase {
    private let base: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]
    private var options: NSApplication.PresentationOptions = []
    private var fullScreenWindows: Set<ObjectIdentifier> = []
    private var controller: LiveModeMenuBarController!
    private var windowA: NSWindow!
    private var windowB: NSWindow!

    override func setUp() {
        super.setUp()
        options = base
        windowA = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        windowB = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        fullScreenWindows = [ObjectIdentifier(windowA)]
        controller = LiveModeMenuBarController(environment: .init(
            presentationOptions: { [unowned self] in self.options },
            setPresentationOptions: { [unowned self] in self.options = $0 },
            isFullScreen: { [unowned self] in self.fullScreenWindows.contains(ObjectIdentifier($0)) }
        ))
    }

    override func tearDown() {
        controller = nil
        windowA = nil
        windowB = nil
        super.tearDown()
    }

    func testHidesWhenLiveAndDashboardWindowFullScreen() {
        controller.setWindow(windowA)
        controller.update(isLiveMode: true)
        XCTAssertTrue(options.contains(.hideMenuBar))
    }

    func testRestoresWhenLeavingLiveMode() {
        controller.setWindow(windowA)
        controller.update(isLiveMode: true)
        controller.update(isLiveMode: false)
        XCTAssertEqual(options, base)
    }

    func testDoesNotHideMidTransitionBeforeFullScreenOptionsApply() {
        // styleMask already says full screen, but AppKit hasn't switched to the
        // full-screen presentation options yet: assigning now would hide without .fullScreen.
        options = []
        controller.setWindow(windowA)
        controller.update(isLiveMode: true)
        XCTAssertEqual(options, [])
        XCTAssertNil(controller.savedBaseOptions)
    }

    func testSwitchingWindowWhileHiddenRestoresFirst() {
        controller.setWindow(windowA)
        controller.update(isLiveMode: true)
        controller.setWindow(windowB) // windowB is not full screen
        XCTAssertEqual(options, base, "menu bar must not stay hidden when the tracked window changes")
        XCTAssertNil(controller.savedBaseOptions)
    }

    func testExitingFullScreenWhileHiddenDiscardsSavedOptions() {
        controller.setWindow(windowA)
        controller.update(isLiveMode: true)
        // AppKit leaves full screen and resets the options itself.
        fullScreenWindows = []
        options = []
        controller.windowFullScreenStateDidChange()
        XCTAssertEqual(options, [], "must not assign full-screen options outside full screen")
        XCTAssertNil(controller.savedBaseOptions)
    }
}
