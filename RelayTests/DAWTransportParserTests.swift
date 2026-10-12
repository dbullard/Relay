import XCTest
@testable import Relay

@MainActor
final class DAWTransportParserTests: XCTestCase {

    func testProToolsCaptureHasHuiPingAndDoesNotEmitStatusMessagesAsCounterText() throws {
        let logURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pro-tools-hui-capture", withExtension: "log"))
        let log = try String(contentsOf: logURL, encoding: .utf8)
        let packets = try DAWTransportLogFixture.packets(from: log)

        XCTAssertTrue(packets.contains { DAWTransportCommandEncoder.containsHUIPingRequest($0) })

        let parser = DAWHUIDisplayParser()
        var emittedTexts: [String] = []
        for packet in packets {
            if let update = parser.consume(bytes: packet) {
                emittedTexts.append(update.text)
            }
        }

        XCTAssertFalse(emittedTexts.contains { $0.localizedCaseInsensitiveContains("Pro Tools") })
        XCTAssertFalse(emittedTexts.contains { $0.localizedCaseInsensitiveContains("dial") })
    }

    func testHuiDisplayIgnoresNonCounterTextCommands() {
        let parser = DAWHUIDisplayParser()

        XCTAssertNil(parser.consume(bytes: [0xF0, 0x00, 0x00, 0x66, 0x05, 0x00, 0x10, 0x08, 0x20, 0x20, 0x20, 0x20, 0xF7]))
        XCTAssertNil(parser.consume(bytes: [0xF0, 0x00, 0x00, 0x66, 0x05, 0x00, 0x12, 0x00, 0x50, 0x72, 0x6F, 0x20, 0x54, 0x6F, 0x6F, 0x6C, 0x73, 0x20, 0xF7]))
    }

    func testHuiDisplayPreservesStableCounterAcrossLeftTruncatedRefresh() throws {
        let parser = DAWHUIDisplayParser()

        _ = parser.consume(bytes: huiWholeDisplay("56:10:10"))
        let truncated = try XCTUnwrap(parser.consume(bytes: huiWholeDisplay(" 6:10:10")))

        // ":" encodes as 0x20 which decodes as space; left-truncated preservation still works
        XCTAssertEqual(truncated.text, "56 10 10")
    }

    func testHuiDisplayShortUpdatesAccumulateFromZeroNotFromAPositionByte() throws {
        // Short HUI display payloads have been assumed, twice (May 19 and again
        // July 14), to lead with a start-offset byte into the 8-digit buffer.
        // Both times that assumption broke the counter on real Pro Tools hardware
        // and had to be reverted. Every short payload is decoded as a plain
        // 0-indexed write of the digits present, same as a full buffer write.
        let logURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pro-tools-hui-capture", withExtension: "log"))
        let log = try String(contentsOf: logURL, encoding: .utf8)
        let packets = try DAWTransportLogFixture.packets(from: log)

        let parser = DAWHUIDisplayParser()
        let emittedTexts = packets.compactMap { parser.consume(bytes: $0)?.text }

        XCTAssertEqual(emittedTexts, ["55", "00", "35", "93", "143", "194", "257", "315", "356"])
    }

    func testClassifierRecognizesCommonCounterFormats() {
        let bars = DAWCounterClassifier.classify(
            rawText: "56|10|120",
            explicitFeedbackMode: nil,
            dawType: .proToolsHUI
        )
        XCTAssertEqual(bars.displayText, "56.10.120")
        XCTAssertEqual(bars.kind, .barsBeats)

        let timecode = DAWCounterClassifier.classify(
            rawText: "01:02:03:04",
            explicitFeedbackMode: nil,
            dawType: .logicProHUI
        )
        XCTAssertEqual(timecode.displayText, "01:02:03:04")
        XCTAssertEqual(timecode.kind, .timecode)

        let raw = DAWCounterClassifier.classify(
            rawText: "Loop Start",
            explicitFeedbackMode: nil,
            dawType: .cubaseNuendoHUI
        )
        XCTAssertEqual(raw.displayText, "Loop Start")
        XCTAssertEqual(raw.kind, .unknown)
        XCTAssertEqual(raw.confidence, .rawFallback)
    }

    func testMTCQuarterFrameProducesTimecodeAfterCompleteSet() throws {
        let parser = DAWMTCParser()
        let pieces: [UInt8] = [
            0x04, // frame low = 4
            0x10, // frame high = 0
            0x23, // second low = 3
            0x30, // second high = 0
            0x42, // minute low = 2
            0x50, // minute high = 0
            0x61, // hour low = 1
            0x70  // hour high/rate = 0, 24fps
        ]

        var update: DAWMTCUpdate?
        for piece in pieces {
            update = parser.consumeQuarterFrame(piece)
        }

        let finalUpdate = try XCTUnwrap(update)
        XCTAssertEqual(finalUpdate.timecode.formatted, "01:02:03:04")
        XCTAssertEqual(finalUpdate.detectedFrameRate, .fps24)
    }

    private func huiWholeDisplay(_ text: String) -> [UInt8] {
        let encoded = Array(text.padding(toLength: 8, withPad: " ", startingAt: 0).prefix(8)).reversed().map { character -> UInt8 in
            switch character {
            case "0"..."9":
                return UInt8(String(character))!
            case ":":
                return 0x20
            case " ":
                return 0x20
            default:
                return 0x20
            }
        }
        return [0xF0, 0x00, 0x00, 0x66, 0x05, 0x00, 0x11] + encoded + [0xF7]
    }
}
