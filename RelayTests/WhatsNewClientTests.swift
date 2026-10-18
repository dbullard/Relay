import XCTest
@testable import Relay

final class WhatsNewClientTests: XCTestCase {

    func test_feedURL_appendsChannelQueryItem() {
        let baseURL = URL(string: "https://api.example.com")!

        let url = WhatsNewClient.feedURL(baseURL: baseURL, channel: "beta")

        XCTAssertEqual(url.path, "/api/whats-new")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems, [URLQueryItem(name: "channel", value: "beta")])
    }

    func test_feedURL_usesReleaseChannel() {
        let baseURL = URL(string: "https://api.example.com")!

        let url = WhatsNewClient.feedURL(baseURL: baseURL, channel: "release")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems, [URLQueryItem(name: "channel", value: "release")])
    }
}
