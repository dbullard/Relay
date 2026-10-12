import Foundation

/// Pure framing check for the hand-rolled HTTP listener. No sockets, so it is unit-testable.
enum HTTPRequestLimits {
    static let maxHeaderBytes = 16 * 1024
    static let maxBodyBytes = 16 * 1024 * 1024
    static let idleTimeout: TimeInterval = 10

    enum Verdict: Equatable { case needMore, ready, headersTooLarge, bodyTooLarge, malformed }

    static func evaluate(buffer: Data) -> Verdict {
        guard let terminator = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeaderBytes ? .headersTooLarge : .needMore
        }
        let headerLength = buffer.distance(from: buffer.startIndex, to: terminator.lowerBound)
        guard headerLength <= maxHeaderBytes else { return .headersTooLarge }

        let headerString = String(decoding: buffer[buffer.startIndex..<terminator.lowerBound], as: UTF8.self)
        var declared = 0
        for line in headerString.split(separator: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "content-length" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let parsed = Int(value), parsed >= 0 else { return .malformed }
            declared = parsed
            break
        }
        guard declared <= maxBodyBytes else { return .bodyTooLarge }

        let bodyBytes = buffer.distance(from: terminator.upperBound, to: buffer.endIndex)
        return bodyBytes >= declared ? .ready : .needMore
    }
}
