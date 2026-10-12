import XCTest
@testable import Relay

@MainActor
final class RelayAccountHeartbeatReporterTests: XCTestCase {
    func test_doesNotSendWithoutConsent() async {
        let service = HeartbeatService()
        let reporter = makeReporter(service: service, isEnabled: { false })

        reporter.setApplicationActive(true)
        await Task.yield()

        XCTAssertTrue(service.requests.isEmpty)
    }

    func test_doesNotSendWithoutSession() async {
        let service = HeartbeatService()
        let reporter = makeReporter(service: service, token: { nil })

        reporter.setApplicationActive(true)
        await Task.yield()

        XCTAssertTrue(service.requests.isEmpty)
    }

    func test_doesNotSendWithUnverifiedStoredSession() async {
        let service = HeartbeatService()
        let reporter = makeReporter(service: service, isSessionVerified: { false })

        reporter.setApplicationActive(true)
        await Task.yield()

        XCTAssertTrue(service.requests.isEmpty)
    }

    func testSendsImmediatelyWhenSessionBecomesVerified() async {
        let service = HeartbeatService()
        var isSessionVerified = false
        let reporter = makeReporter(service: service, isSessionVerified: { isSessionVerified })

        reporter.setApplicationActive(true)
        await Task.yield()
        XCTAssertTrue(service.requests.isEmpty)

        isSessionVerified = true
        reporter.refreshEligibility()
        await waitUntil { service.requests.count == 1 }

        reporter.stop()
    }

    func testSendsImmediatelyAfterForegroundActivation() async {
        let service = HeartbeatService()
        let reporter = makeReporter(service: service)

        reporter.setApplicationActive(true)
        await waitUntil { service.requests.count == 1 }

        XCTAssertEqual(service.requests[0].installationId.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(service.requests[0].platform, "macos")
        XCTAssertEqual(service.requests[0].appVersion, "1.2.3")
        reporter.stop()
    }

    func testSendsAgainAfterInjected120SecondSleeper() async {
        let service = HeartbeatService()
        let sleeper = HeartbeatSleeper()
        let reporter = makeReporter(service: service, sleeper: sleeper.sleep)

        reporter.setApplicationActive(true)
        await waitUntil { service.requests.count == 1 }
        await sleeper.waitForSleep()
        await sleeper.resumeNext()
        await waitUntil { service.requests.count == 2 }

        let intervals = await sleeper.requestedIntervals()
        XCTAssertEqual(intervals.first, 120)
        reporter.stop()
    }

    func testStopsOnBackground() async {
        let service = HeartbeatService()
        let sleeper = HeartbeatSleeper()
        let reporter = makeReporter(service: service, sleeper: sleeper.sleep)

        reporter.setApplicationActive(true)
        await waitUntil { service.requests.count == 1 }
        await sleeper.waitForSleep()
        reporter.setApplicationActive(false)
        await sleeper.resumeNext()
        await Task.yield()

        XCTAssertEqual(service.requests.count, 1)
    }

    func testStopsAfterLogoutRefresh() async {
        let service = HeartbeatService()
        let sleeper = HeartbeatSleeper()
        var token: String? = "session-token"
        let reporter = makeReporter(service: service, token: { token }, sleeper: sleeper.sleep)

        reporter.setApplicationActive(true)
        await waitUntil { service.requests.count == 1 }
        await sleeper.waitForSleep()
        token = nil
        reporter.refreshEligibility()
        await sleeper.resumeNext()
        await Task.yield()

        XCTAssertEqual(service.requests.count, 1)
    }

    func testStopsAfterConsentRevocation() async {
        let service = HeartbeatService()
        let sleeper = HeartbeatSleeper()
        var isEnabled = true
        let reporter = makeReporter(service: service, isEnabled: { isEnabled }, sleeper: sleeper.sleep)

        reporter.setApplicationActive(true)
        await waitUntil { service.requests.count == 1 }
        await sleeper.waitForSleep()
        isEnabled = false
        reporter.refreshEligibility()
        await sleeper.resumeNext()
        await Task.yield()

        XCTAssertEqual(service.requests.count, 1)
    }

    private func makeReporter(
        service: HeartbeatService,
        isEnabled: @escaping @MainActor () -> Bool = { true },
        token: @escaping @MainActor () -> String? = { "session-token" },
        isSessionVerified: @escaping @MainActor () -> Bool = { true },
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { _ in
            try? await Task.sleep(for: .seconds(120))
        }
    ) -> RelayAccountHeartbeatReporter {
        RelayAccountHeartbeatReporter(
            service: service,
            isUsageDiagnosticsEnabled: isEnabled,
            sessionToken: token,
            isSessionVerified: isSessionVerified,
            installationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            platform: "macos",
            appVersion: "1.2.3",
            sleep: sleeper
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met", file: file, line: line)
    }
}

private final class HeartbeatService: RelayAccountServicing {
    var requests: [RelayAccountHeartbeatRequest] = []

    func sendHeartbeat(token: String, request: RelayAccountHeartbeatRequest) async throws {
        requests.append(request)
    }

    func requestMagicLink(email: String, codeChallenge: String?) async throws -> RelayAccountMagicLinkResponse { fatalError() }
    func exchangeAuthCode(code: String, codeVerifier: String) async throws -> String { fatalError() }
    func validateSession(token: String) async throws -> RelayAccountSessionResponse { fatalError() }
    func fetchAccount(token: String) async throws -> RelayAccountSessionResponse { fatalError() }
    func fetchEntitlements(token: String) async throws -> RelayAccountEntitlementsResponse { fatalError() }
    func linkLegacyLicense(token: String, licenseKey: String) async throws { fatalError() }
    func activateLinkedLicense(token: String, request: RelayAccountActivateLinkedLicenseRequest) async throws -> RelayAccountActivateLinkedLicenseResponse { fatalError() }
    func deactivateLinkedLicense(token: String, request: RelayAccountDeactivateLinkedLicenseRequest) async throws -> RelayAccountDeactivateLinkedLicenseResponse { fatalError() }
    func linkAppStoreSubscription(token: String, request: RelayAccountLinkAppStoreSubscriptionRequest) async throws { fatalError() }
    func logout(token: String) async throws { fatalError() }
    func deleteAccount(token: String) async throws { fatalError() }
}

private actor HeartbeatSleeper {
    private var intervals: [TimeInterval] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_ interval: TimeInterval) async {
        intervals.append(interval)
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitForSleep() async {
        while continuations.isEmpty {
            await Task.yield()
        }
    }

    func resumeNext() {
        continuations.removeFirst().resume()
    }

    func requestedIntervals() -> [TimeInterval] { intervals }
}
