import XCTest
@testable import Relay

@MainActor
final class FreeEditionTests: XCTestCase {
    private let overrideKey = "subscription_forcePro"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: overrideKey)
        super.tearDown()
    }

    func test_proIsOnImmediately_beforeAnyRefresh() {
        let manager = SubscriptionManager.shared
        XCTAssertTrue(manager.hasPro)
        XCTAssertTrue(manager.effectivePro)
    }

    func test_proStaysOnAfterEntitlementRefresh() async {
        let manager = SubscriptionManager.shared
        await manager.refreshEntitlements()
        await manager.refreshEntitlements(forceSync: true)
        XCTAssertTrue(manager.hasPro)
        XCTAssertTrue(manager.effectivePro)
        XCTAssertFalse(manager.isChecking)
    }

    func test_debugOverrideCannotTurnProOff() async {
        // In a DEBUG build the value 1 means "force Pro off" for the old paywall.
        UserDefaults.standard.set(1, forKey: overrideKey)
        let manager = SubscriptionManager.shared
        await manager.refreshEntitlements()
        XCTAssertTrue(manager.hasPro)
    }

    func test_refreshEntitlementsMakesNoLicenseOrAccountRequests() async {
        URLProtocol.registerClass(FreeEditionNetworkSpy.self)
        defer { URLProtocol.unregisterClass(FreeEditionNetworkSpy.self) }
        FreeEditionNetworkSpy.reset()

        // Positive control: the fake transport sees requests and fails them offline.
        let probe = URL(string: "https://relay-free-test.invalid/api/licensing/validate")!
        _ = try? await URLSession.shared.data(from: probe)
        XCTAssertEqual(FreeEditionNetworkSpy.requestCount, 1)
        FreeEditionNetworkSpy.reset()

        let manager = SubscriptionManager.shared
        await manager.refreshEntitlements()
        await manager.refreshEntitlements(forceSync: true)
        XCTAssertEqual(FreeEditionNetworkSpy.requestCount, 0)
        XCTAssertTrue(manager.hasPro)
        XCTAssertTrue(manager.effectivePro)
        XCTAssertFalse(manager.isChecking)
    }

    func test_expiredOrDisabledLegacyLicenseCannotDisablePro() async {
        let manager = SubscriptionManager.shared
        let coordinator = LicenseCoordinator.shared
        for message in ["License expired", "License disabled"] {
            coordinator.handleNetworkFailure(RelayLicensingClient.ClientError(message: message))
            XCTAssertFalse(coordinator.isLicensed)
            await manager.refreshEntitlements(forceSync: true)
            XCTAssertTrue(manager.hasPro)
            XCTAssertTrue(manager.effectivePro)
        }
    }

    func test_supportURLIsTheCommunityRepository() {
        XCTAssertEqual(RelayLicensingConfig.supportURL.absoluteString, "https://github.com/dbullard/Relay")
    }
}

private final class FreeEditionNetworkSpy: URLProtocol, @unchecked Sendable {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func record() { lock.withLock { count += 1 } }
        func reset() { lock.withLock { count = 0 } }
        var requestCount: Int { lock.withLock { count } }
    }

    private static let recorder = Recorder()
    static var requestCount: Int { recorder.requestCount }
    static func reset() { recorder.reset() }

    override class func canInit(with request: URLRequest) -> Bool {
        let path = request.url?.path ?? ""
        return path.hasPrefix("/api/licensing/") || path == "/api/me/entitlements"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recorder.record()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
