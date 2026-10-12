import Foundation
import CryptoKit

enum LANRequestSigner {
    static let maxClockSkew: TimeInterval = 60

    private static func canonical(method: String, target: String, timestamp: Int, nonce: String, body: Data) -> Data {
        let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return Data("\(method.uppercased())\n\(target)\n\(timestamp)\n\(nonce)\n\(bodyHash)".utf8)
    }

    static func signature(secret: Data, method: String, target: String, timestamp: Int, nonce: String, body: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: canonical(method: method, target: target, timestamp: timestamp, nonce: nonce, body: body),
            using: SymmetricKey(data: secret))
        return Data(mac).base64EncodedString()
    }

    static func verify(secret: Data, signature: String, method: String, target: String, timestamp: Int,
                       nonce: String, body: Data, now: Date) -> Bool {
        guard abs(now.timeIntervalSince1970 - Double(timestamp)) <= maxClockSkew,
              let sig = Data(base64Encoded: signature) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            sig,
            authenticating: canonical(method: method, target: target, timestamp: timestamp, nonce: nonce, body: body),
            using: SymmetricKey(data: secret))
    }
}
