import XCTest
@testable import Relay

final class LicenseKeychainStoreTests: XCTestCase {
    private var store: LicenseKeychainStore!
    private let testKey = "LicenseKeychainStoreTests.testKey"

    override func setUp() {
        super.setUp()
        store = LicenseKeychainStore()
        store.clear(forKey: testKey)
    }

    override func tearDown() {
        store.clear(forKey: testKey)
        store = nil
        super.tearDown()
    }

    func test_saveString_thenLoad_roundTrips() {
        let saved = store.saveString("hello", forKey: testKey)

        XCTAssertTrue(saved)
        XCTAssertEqual(store.loadString(forKey: testKey), "hello")
    }

    func test_saveString_overwritesExistingValue() {
        store.saveString("first", forKey: testKey)

        let saved = store.saveString("second", forKey: testKey)

        XCTAssertTrue(saved)
        XCTAssertEqual(store.loadString(forKey: testKey), "second")
    }

    func test_clear_onExistingKey_returnsTrue() {
        store.saveString("value", forKey: testKey)

        XCTAssertTrue(store.clear(forKey: testKey))
        XCTAssertNil(store.loadString(forKey: testKey))
    }

    func test_clear_onAlreadyAbsentKey_returnsTrueNotFalse() {
        // Clearing a key that was never set (or already cleared) is not a
        // failure — it must not be reported as one.
        XCTAssertTrue(store.clear(forKey: testKey))
    }

    func test_clearAll_allSucceed_returnsTrue() {
        let keyA = testKey + ".a"
        let keyB = testKey + ".b"
        store.saveString("a", forKey: keyA)
        store.saveString("b", forKey: keyB)
        defer {
            store.clear(forKey: keyA)
            store.clear(forKey: keyB)
        }

        XCTAssertTrue(store.clearAll(keys: [keyA, keyB]))
    }

    func test_saveString_nilValue_clearsExistingValue() {
        store.saveString("value", forKey: testKey)

        let cleared = store.saveString(nil, forKey: testKey)

        XCTAssertTrue(cleared)
        XCTAssertNil(store.loadString(forKey: testKey))
    }
}
