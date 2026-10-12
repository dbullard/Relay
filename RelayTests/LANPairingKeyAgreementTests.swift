import XCTest
import CryptoKit
@testable import Relay

final class LANPairingKeyAgreementTests: XCTestCase {
    func testBothSidesDeriveSameSecretAndSAS() throws {
        let joiner = LANPairingKeyAgreement.makeKeyPair()
        let host = LANPairingKeyAgreement.makeKeyPair()
        let s1 = try LANPairingKeyAgreement.deriveSecret(privateKey: joiner.privateKey, peerPublicBase64: host.publicBase64, requestId: "R1")
        let s2 = try LANPairingKeyAgreement.deriveSecret(privateKey: host.privateKey, peerPublicBase64: joiner.publicBase64, requestId: "R1")
        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s1.count, 32)
        let a = LANPairingKeyAgreement.shortAuthString(joinerPublicBase64: joiner.publicBase64, hostPublicBase64: host.publicBase64, secret: s1)
        let b = LANPairingKeyAgreement.shortAuthString(joinerPublicBase64: joiner.publicBase64, hostPublicBase64: host.publicBase64, secret: s2)
        XCTAssertEqual(a, b)
        XCTAssertNotNil(a.range(of: #"^\d{4} \d{4}$"#, options: .regularExpression))
    }

    func testDifferentRequestIdGivesDifferentSecret() throws {
        let j = LANPairingKeyAgreement.makeKeyPair(), h = LANPairingKeyAgreement.makeKeyPair()
        let a = try LANPairingKeyAgreement.deriveSecret(privateKey: j.privateKey, peerPublicBase64: h.publicBase64, requestId: "R1")
        let b = try LANPairingKeyAgreement.deriveSecret(privateKey: j.privateKey, peerPublicBase64: h.publicBase64, requestId: "R2")
        XCTAssertNotEqual(a, b)
    }

    func testMitmSubstitutionChangesSAS() throws {
        let j = LANPairingKeyAgreement.makeKeyPair(), h = LANPairingKeyAgreement.makeKeyPair(), m = LANPairingKeyAgreement.makeKeyPair()
        let sJH = try LANPairingKeyAgreement.deriveSecret(privateKey: j.privateKey, peerPublicBase64: h.publicBase64, requestId: "R")
        let sJM = try LANPairingKeyAgreement.deriveSecret(privateKey: j.privateKey, peerPublicBase64: m.publicBase64, requestId: "R")
        let honest = LANPairingKeyAgreement.shortAuthString(joinerPublicBase64: j.publicBase64, hostPublicBase64: h.publicBase64, secret: sJH)
        let attacked = LANPairingKeyAgreement.shortAuthString(joinerPublicBase64: j.publicBase64, hostPublicBase64: m.publicBase64, secret: sJM)
        XCTAssertNotEqual(honest, attacked)
    }

    func testBadPublicKeyThrows() {
        let j = LANPairingKeyAgreement.makeKeyPair()
        XCTAssertThrowsError(try LANPairingKeyAgreement.deriveSecret(privateKey: j.privateKey, peerPublicBase64: "AAAA", requestId: "R"))
    }

    func testInMemorySecretStore() {
        let store = InMemoryPairingSecretStore()
        XCTAssertNil(store.secret(for: "D1"))
        store.setSecret(Data([1, 2, 3]), for: "D1")
        XCTAssertEqual(store.secret(for: "D1"), Data([1, 2, 3]))
        store.setSecret(nil, for: "D1")
        XCTAssertNil(store.secret(for: "D1"))
    }
}
