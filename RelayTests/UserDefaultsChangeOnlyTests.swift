import XCTest
@testable import Relay

final class UserDefaultsChangeOnlyTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "UserDefaultsChangeOnlyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func countChanges(_ body: () -> Void) -> Int {
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return count
    }

    func testSameValueDoesNotWrite() {
        defaults.set("a", forKey: "k")
        defaults.set(true, forKey: "b")
        defaults.set(Data([1, 2, 3]), forKey: "d")
        let writes = countChanges {
            defaults.setIfChanged("a", forKey: "k")
            defaults.setIfChanged(true, forKey: "b")
            defaults.setIfChanged(Data([1, 2, 3]), forKey: "d")
        }
        XCTAssertEqual(writes, 0)
    }

    func testDifferentValueWrites() {
        defaults.set("a", forKey: "k")
        let writes = countChanges { defaults.setIfChanged("b", forKey: "k") }
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(defaults.string(forKey: "k"), "b")
    }

    func testNewKeyWrites() {
        defaults.setIfChanged(42, forKey: "n")
        XCTAssertEqual(defaults.integer(forKey: "n"), 42)
    }

    func testRemoveIfPresentSkipsMissingKey() {
        let writes = countChanges { defaults.removeIfPresent(forKey: "missing") }
        XCTAssertEqual(writes, 0)
    }

    func testNilRemovesExistingKey() {
        defaults.set("a", forKey: "k")
        defaults.setIfChanged(nil, forKey: "k")
        XCTAssertNil(defaults.object(forKey: "k"))
    }
}
