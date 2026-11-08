import XCTest
@testable import Relay

final class DashboardModuleCatalogTests: XCTestCase {

    func test_ndiModule_isAvailableInCatalogAndMarkedBeta() {
        let items = DashboardModuleCatalog.all(
            initialPerson: nil,
            tileID: UUID(),
            ndiModuleCount: 0
        )

        let ndiItem = items.first { $0.id == "ndi" }

        XCTAssertNotNil(ndiItem)
        XCTAssertEqual(ndiItem?.title, "NDI® Feed")
        XCTAssertTrue(ndiItem?.isBeta == true)
    }
}
