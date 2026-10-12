import XCTest
@testable import Relay

final class ExternalDeviceKindIconTests: XCTestCase {
    func testWirelessBrandsShareExternalDeviceCategoryIcon() {
        XCTAssertEqual(
            ExternalDeviceKind.shureWireless.systemImage,
            ExternalDeviceKind.sennheiserWireless.systemImage
        )
    }

    func testVisibleKindsSortAlphabeticallyByDisplayName() {
        let visibleKinds: [ExternalDeviceKind] = [
            .audioConsole,
            .vistaConsole,
            .shureWireless,
            .sennheiserWireless
        ]

        XCTAssertEqual(
            ExternalDeviceKind.sortedByDisplayName(visibleKinds),
            [.audioConsole, .sennheiserWireless, .shureWireless, .vistaConsole]
        )
    }
}
