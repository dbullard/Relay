import Foundation

enum DAWTransportLogFixtureError: Error, CustomStringConvertible, Equatable {
    case malformedHexToken(String, line: Int)
    case emptyFixture

    var description: String {
        switch self {
        case let .malformedHexToken(token, line):
            return "malformedHexToken(\"\(token)\", line: \(line))"
        case .emptyFixture:
            return "emptyFixture"
        }
    }
}

enum DAWTransportLogFixture {
    static func packets(from log: String, allowEmpty: Bool = false) throws -> [[UInt8]] {
        var packets: [[UInt8]] = []
        for (lineIndex, rawLine) in log.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            guard let bytesRange = line.range(of: "bytes=") else { continue }

            let bytesText = line[bytesRange.upperBound...]
            var packet: [UInt8] = []
            for tokenSubstring in bytesText.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let token = String(tokenSubstring)
                guard token.count == 2, let value = UInt8(token, radix: 16) else {
                    throw DAWTransportLogFixtureError.malformedHexToken(token, line: lineIndex + 1)
                }
                packet.append(value)
            }
            packets.append(packet)
        }

        if packets.isEmpty && !allowEmpty {
            throw DAWTransportLogFixtureError.emptyFixture
        }

        return packets
    }
}
