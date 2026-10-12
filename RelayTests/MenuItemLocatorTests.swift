import XCTest
import AppKit
@testable import Relay

final class MenuItemLocatorTests: XCTestCase {

    func test_firstItem_findsTopLevelMatch() {
        let menu = NSMenu()
        let target = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(target)

        let found = MenuItemLocator.firstItem(in: menu, withAction: #selector(NSWindow.performClose(_:)))

        XCTAssertTrue(found === target)
    }

    func test_firstItem_findsNestedMatchInSubmenu() {
        let menu = NSMenu()
        let fileMenuItem = NSMenuItem()
        let submenu = NSMenu()
        let target = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        submenu.addItem(NSMenuItem(title: "New", action: nil, keyEquivalent: ""))
        submenu.addItem(target)
        fileMenuItem.submenu = submenu
        menu.addItem(fileMenuItem)

        let found = MenuItemLocator.firstItem(in: menu, withAction: #selector(NSWindow.performClose(_:)))

        XCTAssertTrue(found === target)
    }

    func test_firstItem_returnsNilWhenNoMatch() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Other", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: ""))

        let found = MenuItemLocator.firstItem(in: menu, withAction: #selector(NSWindow.performClose(_:)))

        XCTAssertNil(found)
    }
}
