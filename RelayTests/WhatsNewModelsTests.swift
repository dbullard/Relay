import XCTest
@testable import Relay

final class WhatsNewModelsTests: XCTestCase {

    func test_decodesFeedFromJSON() throws {
        let json = """
        {
          "releases": [
            {
              "version": "2.4.0",
              "date": "2026-06-28",
              "features": [
                {
                  "icon": "waveform",
                  "iconColor": "#3498db",
                  "title": "Word Trigger Sync",
                  "description": "Standalone nodes now stay in sync with canvas-backed transcription config automatically."
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let feed = try JSONDecoder().decode(WhatsNewFeed.self, from: json)

        XCTAssertEqual(feed.releases.count, 1)
        XCTAssertEqual(feed.releases[0].version, "2.4.0")
        XCTAssertEqual(feed.releases[0].date, "2026-06-28")
        XCTAssertEqual(feed.releases[0].features.count, 1)
        XCTAssertEqual(feed.releases[0].features[0].icon, "waveform")
        XCTAssertEqual(feed.releases[0].features[0].iconColor, "#3498db")
        XCTAssertEqual(feed.releases[0].features[0].title, "Word Trigger Sync")
    }

    func test_isNewerRelayVersion_handlesMultiDigitSegmentsNumerically() {
        XCTAssertTrue("2.10.0".isNewerRelayVersion(than: "2.9.0"))
        XCTAssertFalse("2.9.0".isNewerRelayVersion(than: "2.10.0"))
        XCTAssertFalse("2.4.0".isNewerRelayVersion(than: "2.4.0"))
        XCTAssertTrue("2.4.1".isNewerRelayVersion(than: "2.4.0"))
    }

    func test_relayHexColorComponents_parsesHexWithHashPrefix() throws {
        let components = try XCTUnwrap(relayHexColorComponents("#3498db"))
        XCTAssertEqual(components.red, Double(0x34) / 255, accuracy: 0.001)
        XCTAssertEqual(components.green, Double(0x98) / 255, accuracy: 0.001)
        XCTAssertEqual(components.blue, Double(0xdb) / 255, accuracy: 0.001)
    }

    func test_relayHexColorComponents_parsesHexWithoutHashPrefix() {
        XCTAssertNotNil(relayHexColorComponents("3498db"))
    }

    func test_relayHexColorComponents_returnsNilForInvalidHex() {
        XCTAssertNil(relayHexColorComponents("not-a-color"))
        XCTAssertNil(relayHexColorComponents("#123"))
    }

    func test_formattedDate_parsesPlainDate() {
        let release = WhatsNewRelease(version: "1.0.0", date: "2026-07-12", features: [])

        let formatted = release.formattedDate

        XCTAssertFalse(formatted.contains("T"))
        XCTAssertTrue(formatted.contains("2026"))
    }

    func test_formattedDate_parsesISO8601WithFractionalSeconds() {
        let release = WhatsNewRelease(version: "1.0.0", date: "2026-07-12T18:13:47.912Z", features: [])

        let formatted = release.formattedDate

        XCTAssertFalse(formatted.contains("T"))
        XCTAssertFalse(formatted.contains("Z"))
        XCTAssertTrue(formatted.contains("2026"))
    }

    func test_formattedDate_parsesISO8601WithoutFractionalSeconds() {
        let release = WhatsNewRelease(version: "1.0.0", date: "2026-07-12T18:13:47Z", features: [])

        let formatted = release.formattedDate

        XCTAssertFalse(formatted.contains("T"))
        XCTAssertTrue(formatted.contains("2026"))
    }

    func test_formattedDate_fallsBackToRawStringWhenUnparseable() {
        let release = WhatsNewRelease(version: "1.0.0", date: "not-a-date", features: [])

        XCTAssertEqual(release.formattedDate, "not-a-date")
    }
}
