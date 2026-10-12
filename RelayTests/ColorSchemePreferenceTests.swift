import XCTest
import SwiftUI
@testable import Relay

final class ColorSchemePreferenceTests: XCTestCase {
    func testSystemMapsToNilColorScheme() {
        XCTAssertNil(ColorSchemePreference.system.colorScheme)
    }

    func testLightMapsToLightColorScheme() {
        XCTAssertEqual(ColorSchemePreference.light.colorScheme, .light)
    }

    func testDarkMapsToDarkColorScheme() {
        XCTAssertEqual(ColorSchemePreference.dark.colorScheme, .dark)
    }

    func testRawValuesUsedForAppStorage() {
        XCTAssertEqual(ColorSchemePreference.light.rawValue, "light")
        XCTAssertEqual(ColorSchemePreference.dark.rawValue, "dark")
        XCTAssertEqual(ColorSchemePreference.system.rawValue, "system")
    }

    func testInitFromUnknownRawValueReturnsNil() {
        XCTAssertNil(ColorSchemePreference(rawValue: "sepia"))
    }

    func testAllCasesOrderedForSegmentedPicker() {
        // Picker in GeneralDashboardSettingsPane displays cases in this order: Light, Dark, System.
        XCTAssertEqual(ColorSchemePreference.allCases, [.light, .dark, .system])
    }

    func testLabels() {
        XCTAssertEqual(ColorSchemePreference.light.label, "Light")
        XCTAssertEqual(ColorSchemePreference.dark.label, "Dark")
        XCTAssertEqual(ColorSchemePreference.system.label, "System")
    }
}
