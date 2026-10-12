import Foundation
import CryptoKit

enum LANPairingKeyAgreement {
    struct KeyPair {
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        var publicBase64: String { privateKey.publicKey.rawRepresentation.base64EncodedString() }
    }

    enum AgreementError: Error { case invalidPeerKey }

    static func makeKeyPair() -> KeyPair { KeyPair(privateKey: Curve25519.KeyAgreement.PrivateKey()) }

    static func deriveSecret(privateKey: Curve25519.KeyAgreement.PrivateKey, peerPublicBase64: String, requestId: String) throws -> Data {
        guard let raw = Data(base64Encoded: peerPublicBase64),
              let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw),
              let shared = try? privateKey.sharedSecretFromKeyAgreement(with: peer) else {
            throw AgreementError.invalidPeerKey
        }
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(requestId.utf8),
            sharedInfo: Data("relay-lan-pairing-v1".utf8),
            outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    /// 8-digit code both people compare on screen: "1234 5678".
    static func shortAuthString(joinerPublicBase64: String, hostPublicBase64: String, secret: Data) -> String {
        var input = Data("relay-lan-sas-v1|".utf8)
        input.append(Data(joinerPublicBase64.utf8)); input.append(0)
        input.append(Data(hostPublicBase64.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: secret))
        let bytes = Array(mac.prefix(4))
        let value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 100_000_000
        let digits = String(format: "%08d", value)
        return "\(digits.prefix(4)) \(digits.suffix(4))"
    }
}
