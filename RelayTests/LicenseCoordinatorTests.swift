import XCTest
@testable import Relay

@MainActor
final class LicenseCoordinatorTests: XCTestCase {
    func test_handleNetworkFailure_expiredDoesNotReport() {
        let coordinator = LicenseCoordinator.shared
        let before = RelayDiagnosticsStore.shared.recentErrorsSummary()

        coordinator.handleNetworkFailure(RelayLicensingClient.ClientError(message: "License expired"))

        XCTAssertEqual(coordinator.status, .expired)
        XCTAssertEqual(RelayDiagnosticsStore.shared.recentErrorsSummary(), before)
    }

    func test_handleNetworkFailure_disabledDoesNotReport() {
        let coordinator = LicenseCoordinator.shared
        let before = RelayDiagnosticsStore.shared.recentErrorsSummary()

        coordinator.handleNetworkFailure(RelayLicensingClient.ClientError(message: "License disabled"))

        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertEqual(RelayDiagnosticsStore.shared.recentErrorsSummary(), before)
    }

    func test_handleNetworkFailure_genericFailureReportsThrottled() {
        let coordinator = LicenseCoordinator.shared

        coordinator.handleNetworkFailure(RelayLicensingClient.ClientError(message: "Connection lost"))

        XCTAssertEqual(coordinator.status, .networkError(lastKnown: coordinator.entitlement))
        XCTAssertTrue(RelayDiagnosticsStore.shared.recentErrorsSummary().contains("Connection lost"))
    }
}
