import XCTest
@testable import Relay

final class VenueConsoleServiceTests: XCTestCase {
    func testFilledAddressSubstitutesChannel() {
        XCTAssertEqual(
            VenueConsoleService.filledAddress(template: "/relay/ch/{channel}/mute", channel: 5),
            "/relay/ch/5/mute"
        )
    }

    func testFilledAddressSubstitutesChannelAtStartOrEnd() {
        XCTAssertEqual(VenueConsoleService.filledAddress(template: "{channel}", channel: 12), "12")
    }

    func testFilledAddressSubstitutesScene() {
        XCTAssertEqual(
            VenueConsoleService.filledAddress(template: "/relay/scene/{scene}/recall", scene: "3.00"),
            "/relay/scene/3.00/recall"
        )
    }

    func testFilledAddressLeavesTemplateUnchangedWithoutPlaceholder() {
        XCTAssertEqual(
            VenueConsoleService.filledAddress(template: "/relay/fixed/address", channel: 7),
            "/relay/fixed/address"
        )
    }
}
