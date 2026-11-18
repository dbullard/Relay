import XCTest
@testable import Relay

final class TouchInputDiagnosticsTests: XCTestCase {
    private let suiteName = "TouchInputDiagnosticsTests"
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        super.tearDown()
    }

    func testDisabledByDefault() {
        XCTAssertFalse(TouchInputDiagnostics.isEnabled(defaults: suite))
    }

    func testEnabledWhenFlagSet() {
        suite.set(true, forKey: TouchInputDiagnostics.defaultsKey)
        XCTAssertTrue(TouchInputDiagnostics.isEnabled(defaults: suite))
    }
}
