import XCTest
@testable import Relay

final class RelayAccountKeychainStoreTests: XCTestCase {
    private var store: RelayAccountKeychainStore!

    override func setUp() {
        super.setUp()
        store = RelayAccountKeychainStore.shared
        store.deleteRelayAccountToken()
    }

    override func tearDown() {
        store.deleteRelayAccountToken()
        store = nil
        super.tearDown()
    }

    func test_saveRelayAccountToken_thenLoad_roundTrips() {
        let saved = store.saveRelayAccountToken("token_abc")

        XCTAssertTrue(saved)
        XCTAssertEqual(store.loadRelayAccountToken(), "token_abc")
    }

    func test_deleteRelayAccountToken_onExistingToken_returnsTrue() {
        store.saveRelayAccountToken("token_abc")

        XCTAssertTrue(store.deleteRelayAccountToken())
        XCTAssertNil(store.loadRelayAccountToken())
    }

    func test_deleteRelayAccountToken_onAlreadyAbsentToken_returnsTrueNotFalse() {
        XCTAssertTrue(store.deleteRelayAccountToken())
    }

    func test_sessionTokenSetter_savesRetrievableToken() {
        store.sessionToken = "token_xyz"

        XCTAssertEqual(store.loadRelayAccountToken(), "token_xyz")
    }
}
