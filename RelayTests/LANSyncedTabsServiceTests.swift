import XCTest
import Network
@testable import Relay

@MainActor
final class LANSyncedTabsServiceTests: XCTestCase {

    /// Removes LAN settings keys so each test starts from documented defaults
    /// (sharing enabled, pairing not effectively required).
    func resetLANDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "lan_pairing_enabled")
        defaults.removeObject(forKey: "lan_pairing_code")
        defaults.removeObject(forKey: "lan_sharing_enabled")
        defaults.removeObject(forKey: "lan_allow_unpaired_read")
        defaults.removeObject(forKey: "lan_browser_view_only_enabled")
        defaults.removeObject(forKey: "lan_paired_devices")
    }

    /// Requests are now authorized by per-device trust rather than a shared pairing code.
    /// Route-level tests that exercise gated endpoints need the calling "device" pre-trusted
    /// before the service under test is constructed (pairedDevices loads once at init).
    private static let testClientDeviceId = "TEST-CLIENT-DEVICE"

    private func trustTestClientDevice() {
        let paired = DevicePairingStore.setEnabled(
            true,
            deviceId: Self.testClientDeviceId,
            deviceName: "Test Client",
            deviceKind: nil,
            in: [:]
        )
        DevicePairingStore.save(paired)
    }

    func testVariableSharingSwitchOnlyGatesComputerWideEndpoint() {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        let peer = makeTestPeer(deviceId: Self.testClientDeviceId, deviceName: "Test Client", deviceKind: .mac)
        service.setSyncedTabs([(
            groupID: "GROUP-ONE", tabName: "Shared Tab", exportedTabJSON: Data("{}".utf8),
            version: SyncedTabVersion(revision: 1, editedAt: 1, editedByDeviceID: service.localDeviceID),
            lastEditedByDeviceName: service.localDeviceName, tileCount: 0, moduleTypes: [], schemaVersion: 1
        )])
        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-ONE"))

        XCTAssertTrue(statusLine(service.route(request: makeRequest(method: "GET", path: "/linkedVariables/v1"))).contains("200"))
        service.setVariableSharing(false, for: peer)
        XCTAssertTrue(statusLine(service.route(request: makeRequest(method: "GET", path: "/linkedVariables/v1"))).contains("403"))
        XCTAssertTrue(statusLine(service.route(request: makeRequest(method: "GET", path: "/syncedVariables/v1?groupID=GROUP-ONE"))).contains("200"))
        XCTAssertTrue(statusLine(service.route(request: makeRequest(method: "GET", path: "/syncedPresence"))).contains("204"))
        XCTAssertEqual(DevicePairingStore.status(for: Self.testClientDeviceId, in: service.pairedDevices), .paired)
    }

    func testFreshServiceHasEmptySyncedState() {
        resetLANDefaults()
        let service = LANSharedTabsService()

        XCTAssertTrue(service.syncedRemoteManifests.isEmpty)
        XCTAssertTrue(service.localSyncedGroupIDs.isEmpty)
        XCTAssertTrue(service.pendingSyncedSnapshots.isEmpty)
        XCTAssertFalse(service.localDeviceID.isEmpty)
        XCTAssertFalse(service.localDeviceName.isEmpty)
    }

    func testPersonPhotoRouteRejectsTraversal() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoRoute-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: root.appendingPathComponent("secret.txt"))
        try Data("jpg".utf8).write(to: photos.appendingPathComponent("a.jpg"))
        defer { try? FileManager.default.removeItem(at: root) }
        service.setPersonImageFolderPath(photos.path)

        XCTAssertTrue(statusLine(service.route(request: makeRequest(method: "GET", path: "/localPersonPhoto/a.jpg"))).contains("200"))
        XCTAssertTrue(statusLine(service.route(request: makeRequest(method: "GET", path: "/localPersonPhoto/..%2Fsecret.txt"))).contains("404"))
        XCTAssertTrue(statusLine(service.route(request: makeRequest(method: "GET", path: "/localPersonPhoto/../secret.txt"))).contains("404"))
    }

    func testSyncedTabStopRequiresAuthorization() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.markGroupAsJoined("GROUP-X")
        let body = try JSONEncoder().encode(SyncedTabStopPayload(groupID: "GROUP-X", deviceID: "H", deviceName: "Host"))

        let anon = service.route(request: makeRequest(method: "POST", path: "/syncedTab/stop", body: body, deviceId: nil))
        XCTAssertTrue(statusLine(anon).contains("401"))
        XCTAssertFalse(service.hostStoppedGroupIDs.contains("GROUP-X"))

        let authed = service.route(request: makeRequest(method: "POST", path: "/syncedTab/stop", body: body))
        XCTAssertTrue(statusLine(authed).contains("200"))
        XCTAssertTrue(service.hostStoppedGroupIDs.contains("GROUP-X"))
    }

    func testSyncedTabsHidesSubscriberIDsFromStrangers() {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.setSyncedTabs([(
            groupID: "GROUP-ONE", tabName: "Shared Tab", exportedTabJSON: Data("{}".utf8),
            version: SyncedTabVersion(revision: 1, editedAt: 1, editedByDeviceID: service.localDeviceID),
            lastEditedByDeviceName: service.localDeviceName, tileCount: 0, moduleTypes: [], schemaVersion: 1
        )])
        let authed = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-ONE"))
        XCTAssertTrue(String(decoding: authed, as: UTF8.self).contains(Self.testClientDeviceId))
        let anon = service.route(request: makeRequest(method: "GET", path: "/syncedTabs", deviceId: nil))
        XCTAssertFalse(String(decoding: anon, as: UTF8.self).contains(Self.testClientDeviceId))
    }

    func testPairRequestSanitizesNameAndCapsPendingQueue() throws {
        resetLANDefaults()
        let service = LANSharedTabsService(pairingSecretStore: InMemoryPairingSecretStore())
        func pair(_ i: Int, name: String) -> String {
            let json = #"{"requestId":"R\#(i)","deviceId":"D\#(i)","deviceName":"\#(name)","reason":"join"}"#
            let b = Data(json.utf8)
            return "POST /pair/request HTTP/1.1\r\nHost: x\r\nX-Relay-Device-Id: D\(i)\r\nContent-Length: \(b.count)\r\n\r\n\(json)"
        }
        _ = service.route(request: pair(0, name: String(repeating: "A", count: 300)))
        XCTAssertEqual(service.pendingPairingRequests.first?.payload.deviceName.count, 40)
        for i in 1..<10 { _ = service.route(request: pair(i, name: "Dev")) }
        XCTAssertEqual(service.pendingPairingRequests.count, PairingInputSanitizer.maxPendingRequests)
    }

    // MARK: - HTTP helpers

    private func makeRequest(method: String, path: String, body: Data? = nil, deviceId: String? = testClientDeviceId, legacyCode: String? = nil) -> String {
        var request = "\(method) \(path) HTTP/1.1\r\nHost: relay.local\r\n"
        if let deviceId {
            request += "X-Relay-Device-Id: \(deviceId)\r\n"
        }
        if let legacyCode {
            request += "X-Relay-Pairing: \(legacyCode)\r\n"
        }
        if let body {
            request += "Content-Length: \(body.count)\r\n"
        }
        request += "\r\n"
        if let body {
            request += String(decoding: body, as: UTF8.self)
        }
        return request
    }

    func testLegacyPairingCodeAuthorizesOlderRelayClientWithoutDeviceID() {
        resetLANDefaults()
        UserDefaults.standard.set("shared-secret", forKey: "lan_pairing_code")
        let service = LANSharedTabsService()

        let response = service.route(request: makeRequest(
            method: "GET",
            path: "/syncedTab/UNKNOWN-GROUP",
            deviceId: nil,
            legacyCode: "shared-secret"
        ))

        // Authentication passed; the requested group simply does not exist.
        XCTAssertTrue(statusLine(response).contains("404"))
    }

    func testLegacyCodeCannotBypassModernDeviceApproval() {
        resetLANDefaults()
        UserDefaults.standard.set("shared-secret", forKey: "lan_pairing_code")
        let service = LANSharedTabsService()

        let response = service.route(request: makeRequest(
            method: "GET",
            path: "/syncedTab/UNKNOWN-GROUP",
            deviceId: "UNTRUSTED-MODERN-CLIENT",
            legacyCode: "shared-secret"
        ))

        XCTAssertTrue(statusLine(response).contains("401"))
    }

    private func decodeJSONBody<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let response = String(decoding: data, as: UTF8.self)
        guard let separatorRange = response.range(of: "\r\n\r\n") else {
            throw NSError(domain: "LANSyncedTabsServiceTests", code: 1)
        }
        let bodyString = String(response[separatorRange.upperBound...])
        return try JSONDecoder().decode(T.self, from: Data(bodyString.utf8))
    }

    private func statusLine(_ data: Data) -> String {
        let response = String(decoding: data, as: UTF8.self)
        return response.components(separatedBy: "\r\n").first ?? ""
    }

    // MARK: - GET /syncedTabs

    func testRouteSyncedTabsReturnsEmptyManifestsInitially() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()

        let response = service.route(request: makeRequest(method: "GET", path: "/syncedTabs"))
        XCTAssertTrue(statusLine(response).contains("200"))

        let decoded = try decodeJSONBody(response, as: SyncedTabsResponse.self)
        XCTAssertTrue(decoded.manifests.isEmpty)
    }

    /// Discovery must work for an UNTRUSTED caller — a device has to be able to see that a
    /// Synced Tab exists before it can ever request pairing to join it. Gating discovery
    /// itself behind trust is a chicken-and-egg deadlock: nothing could ever get paired,
    /// because the only way to initiate pairing (tapping Join on a discovered manifest)
    /// requires already seeing a manifest that discovery refuses to return.
    func testRouteSyncedTabsIsVisibleToUnauthorizedCaller() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        service.setSyncedTabs([
            (
                groupID: "GROUP-DISCOVERY",
                tabName: "Stage Plot",
                exportedTabJSON: Data("{}".utf8),
                version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID),
                lastEditedByDeviceName: service.localDeviceName,
                tileCount: 3,
                moduleTypes: [],
                schemaVersion: 1
            )
        ])

        // No X-Relay-Device-Id header at all — an untrusted, unidentified caller.
        let response = service.route(request: makeRequest(method: "GET", path: "/syncedTabs", deviceId: nil))
        XCTAssertTrue(statusLine(response).contains("200"), "discovery must succeed for an unpaired caller")

        let decoded = try decodeJSONBody(response, as: SyncedTabsResponse.self)
        XCTAssertEqual(decoded.manifests.first?.tabName, "Stage Plot")
    }

    // MARK: - GET /syncedTabs live subscriber tracking

    func testSyncedTabsJoinedQueryRecordsLiveSubscriberForAuthorizedCaller() {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.setSyncedTabs([
            (
                groupID: "GROUP-LIVE",
                tabName: "Stage Plot",
                exportedTabJSON: Data("{}".utf8),
                version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID),
                lastEditedByDeviceName: service.localDeviceName,
                tileCount: 1,
                moduleTypes: [],
                schemaVersion: 1
            )
        ])

        let response = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-LIVE"))
        XCTAssertTrue(statusLine(response).contains("200"))

        XCTAssertTrue(service.liveSubscriberDeviceIDs(for: "GROUP-LIVE").contains(Self.testClientDeviceId))
    }

    func testSyncedTabsJoinedQueryIgnoresUnauthorizedCaller() {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()
        service.setSyncedTabs([
            (
                groupID: "GROUP-UNTRUSTED",
                tabName: "Stage Plot",
                exportedTabJSON: Data("{}".utf8),
                version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID),
                lastEditedByDeviceName: service.localDeviceName,
                tileCount: 1,
                moduleTypes: [],
                schemaVersion: 1
            )
        ])

        // deviceId header is present (via makeRequest's default) but that device was never paired.
        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-UNTRUSTED"))

        XCTAssertTrue(
            service.liveSubscriberDeviceIDs(for: "GROUP-UNTRUSTED").isEmpty,
            "an unpaired caller must not be able to claim subscriber status"
        )
    }

    func testSyncedTabsJoinedQueryIgnoresGroupTheHostDoesNotHost() {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        // Host has no synced tabs at all — GROUP-FOREIGN is not one of its hosted groups.
        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-FOREIGN"))

        XCTAssertTrue(service.liveSubscriberDeviceIDs(for: "GROUP-FOREIGN").isEmpty)
    }

    func testSyncedTabsJoinedQuerySupportsMultipleGroupIDs() {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.setSyncedTabs([
            (groupID: "GROUP-A", tabName: "Tab A", exportedTabJSON: Data("{}".utf8), version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID), lastEditedByDeviceName: service.localDeviceName, tileCount: 1, moduleTypes: [], schemaVersion: 1),
            (groupID: "GROUP-B", tabName: "Tab B", exportedTabJSON: Data("{}".utf8), version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID), lastEditedByDeviceName: service.localDeviceName, tileCount: 1, moduleTypes: [], schemaVersion: 1)
        ])

        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-A,GROUP-B"))

        XCTAssertTrue(service.liveSubscriberDeviceIDs(for: "GROUP-A").contains(Self.testClientDeviceId))
        XCTAssertTrue(service.liveSubscriberDeviceIDs(for: "GROUP-B").contains(Self.testClientDeviceId))
    }

    func testSyncedTabsResponseIncludesLiveSubscribersForHostedGroups() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.setSyncedTabs([
            (groupID: "GROUP-BROADCAST", tabName: "Stage Plot", exportedTabJSON: Data("{}".utf8), version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID), lastEditedByDeviceName: service.localDeviceName, tileCount: 1, moduleTypes: [], schemaVersion: 1)
        ])

        // First poll records the caller as a live subscriber...
        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-BROADCAST"))

        // ...and a second poll from a paired peer should see that subscriber reflected back in
        // the response body (strangers get empty sets; see testSyncedTabsHidesSubscriberIDsFromStrangers).
        let response = service.route(request: makeRequest(method: "GET", path: "/syncedTabs"))
        XCTAssertTrue(statusLine(response).contains("200"))

        let decoded = try decodeJSONBody(response, as: SyncedTabsResponse.self)
        XCTAssertEqual(decoded.manifests.first?.groupID, "GROUP-BROADCAST")
        XCTAssertTrue(
            decoded.liveSubscribersByGroupID?["GROUP-BROADCAST"]?.contains(Self.testClientDeviceId) ?? false,
            "the response should broadcast the host's live-subscriber knowledge so subscribers can see it too"
        )
    }

    func testLiveSubscriberEntryExpiresAfterTTL() async throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.setSyncedTabs([
            (groupID: "GROUP-TTL", tabName: "Stage Plot", exportedTabJSON: Data("{}".utf8), version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID), lastEditedByDeviceName: service.localDeviceName, tileCount: 1, moduleTypes: [], schemaVersion: 1)
        ])

        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-TTL"))
        XCTAssertTrue(service.liveSubscriberDeviceIDs(for: "GROUP-TTL").contains(Self.testClientDeviceId))

        try await Task.sleep(nanoseconds: 4_300_000_000)

        XCTAssertTrue(
            service.liveSubscriberDeviceIDs(for: "GROUP-TTL").isEmpty,
            "entry should expire once the TTL elapses without a fresh poll"
        )
    }

    func testLiveSubscriberSurvivesRapidRepoll() async throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.setSyncedTabs([
            (groupID: "GROUP-REPOLL", tabName: "Stage Plot", exportedTabJSON: Data("{}".utf8), version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID), lastEditedByDeviceName: service.localDeviceName, tileCount: 1, moduleTypes: [], schemaVersion: 1)
        ])

        // First poll starts a 4s expiry timer (deadline ~t=4.0, measuring from here).
        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-REPOLL"))
        XCTAssertTrue(service.liveSubscriberDeviceIDs(for: "GROUP-REPOLL").contains(Self.testClientDeviceId))

        // Re-poll at t≈2.5s — well before the first timer's deadline (still a "rapid" repoll
        // relative to the 4s TTL), cancelling the first expiry task and starting a second one
        // with its own deadline at t≈6.5s. The bug: the cancelled first task's `try?` swallowed
        // cancellation and deleted the entry the second task had just inserted, once its
        // original ~4.0s deadline arrived.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        _ = service.route(request: makeRequest(method: "GET", path: "/syncedTabs?joined=GROUP-REPOLL"))

        // Assert at t≈5.0s: comfortably past the first task's original ~4.0s deadline (where
        // the bug would have deleted the entry), and comfortably before the second task's own
        // ~6.5s deadline (so this isn't racing a legitimate expiry).
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertTrue(
            service.liveSubscriberDeviceIDs(for: "GROUP-REPOLL").contains(Self.testClientDeviceId),
            "a re-poll before the previous expiry fired must not let the stale task delete the fresh entry"
        )
    }

    // MARK: - GET /sharedTabs

    /// Same root cause as testRouteSyncedTabsIsVisibleToUnauthorizedCaller: Mirror discovery
    /// must also work for an untrusted caller, or a device could never see a Mirror tab exists
    /// in order to request pairing to import it.
    func testRouteSharedTabsIsVisibleToUnauthorizedCaller() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        service.setSharedTabs([
            (shareId: "SHARE-DISCOVERY", tabName: "Lyrics", exportedTabJSON: Data("{}".utf8), tileCount: 2, moduleTypes: [], schemaVersion: 1)
        ])

        let response = service.route(request: makeRequest(method: "GET", path: "/sharedTabs", deviceId: nil))
        XCTAssertTrue(statusLine(response).contains("200"), "discovery must succeed for an unpaired caller")

        let manifests = try decodeJSONBody(response, as: [LANSharedTabManifest].self)
        XCTAssertEqual(manifests.first?.tabName, "Lyrics")
    }

    // MARK: - POST /syncedTab/push + GET /syncedTab/<groupID>

    func testRouteSyncedTabPushAppliesNewerSnapshotAndQueuesPending() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.markGroupAsJoined("GROUP-1")

        let snapshot = SyncedTabSnapshot(
            groupID: "GROUP-1",
            tabName: "Stage Plot",
            exportedTabJSON: Data("{\"name\":\"Stage Plot\"}".utf8),
            schemaVersion: 1,
            version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: "DEVICE-A"),
            lastEditedByDeviceName: "Booth Mac",
            hash: "hash-1"
        )
        let body = try JSONEncoder().encode(snapshot)

        let pushResponse = service.route(request: makeRequest(method: "POST", path: "/syncedTab/push", body: body))
        XCTAssertTrue(statusLine(pushResponse).contains("200"))

        XCTAssertEqual(service.pendingSyncedSnapshots.count, 1)
        XCTAssertEqual(service.pendingSyncedSnapshots.first?.groupID, "GROUP-1")
        XCTAssertTrue(service.joinedSyncGroupIDs.contains("GROUP-1"))

        let fetchResponse = service.route(request: makeRequest(method: "GET", path: "/syncedTab/GROUP-1"))
        XCTAssertTrue(statusLine(fetchResponse).contains("200"))
        let fetched = try decodeJSONBody(fetchResponse, as: SyncedTabSnapshot.self)
        XCTAssertEqual(fetched.version.revision, 1)
        XCTAssertEqual(fetched.tabName, "Stage Plot")
    }

    func testRouteSyncedTabPushIgnoresOlderSnapshot() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.markGroupAsJoined("GROUP-2")

        let newer = SyncedTabSnapshot(
            groupID: "GROUP-2",
            tabName: "Stage Plot",
            exportedTabJSON: Data("{\"rev\":2}".utf8),
            schemaVersion: 1,
            version: SyncedTabVersion(revision: 2, editedAt: 2000, editedByDeviceID: "DEVICE-A"),
            lastEditedByDeviceName: "Booth Mac",
            hash: "hash-newer"
        )
        _ = service.route(request: makeRequest(method: "POST", path: "/syncedTab/push", body: try JSONEncoder().encode(newer)))

        let older = SyncedTabSnapshot(
            groupID: "GROUP-2",
            tabName: "Stage Plot",
            exportedTabJSON: Data("{\"rev\":1}".utf8),
            schemaVersion: 1,
            version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: "DEVICE-A"),
            lastEditedByDeviceName: "Booth Mac",
            hash: "hash-older"
        )
        let response = service.route(request: makeRequest(method: "POST", path: "/syncedTab/push", body: try JSONEncoder().encode(older)))
        XCTAssertTrue(statusLine(response).contains("200"))

        let body = String(decoding: response, as: UTF8.self)
        XCTAssertTrue(body.contains("\"applied\":false"))

        let fetchResponse = service.route(request: makeRequest(method: "GET", path: "/syncedTab/GROUP-2"))
        let fetched = try decodeJSONBody(fetchResponse, as: SyncedTabSnapshot.self)
        XCTAssertEqual(fetched.version.revision, 2)
    }

    func testRouteSyncedTabFetchReturns404ForUnknownGroup() {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()

        let response = service.route(request: makeRequest(method: "GET", path: "/syncedTab/UNKNOWN-GROUP"))
        XCTAssertTrue(statusLine(response).contains("404"))
    }

    // MARK: - setSyncedTabs / consumePendingSyncedSnapshots

    func testSetSyncedTabsPublishesManifestAndServesSnapshot() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()

        service.setSyncedTabs([
            (
                groupID: "GROUP-1",
                tabName: "Stage Plot",
                exportedTabJSON: Data("{\"name\":\"Stage Plot\"}".utf8),
                version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: service.localDeviceID),
                lastEditedByDeviceName: service.localDeviceName,
                tileCount: 3,
                moduleTypes: ["shure"],
                schemaVersion: 1
            )
        ])

        XCTAssertEqual(service.localSyncedGroupIDs, ["GROUP-1"])

        let manifestsResponse = service.route(request: makeRequest(method: "GET", path: "/syncedTabs"))
        let decoded = try decodeJSONBody(manifestsResponse, as: SyncedTabsResponse.self)
        let manifests = decoded.manifests
        XCTAssertEqual(manifests.count, 1)
        XCTAssertEqual(manifests.first?.tabName, "Stage Plot")
        XCTAssertEqual(manifests.first?.summary.tileCount, 3)

        let snapshotResponse = service.route(request: makeRequest(method: "GET", path: "/syncedTab/GROUP-1"))
        let snapshot = try decodeJSONBody(snapshotResponse, as: SyncedTabSnapshot.self)
        XCTAssertEqual(snapshot.tabName, "Stage Plot")
        XCTAssertEqual(snapshot.version.revision, 1)
    }

    func testConsumePendingSyncedSnapshotsDrainsQueue() throws {
        resetLANDefaults()
        trustTestClientDevice()
        let service = LANSharedTabsService()
        service.markGroupAsJoined("GROUP-3")

        let snapshot = SyncedTabSnapshot(
            groupID: "GROUP-3",
            tabName: "Stage Plot",
            exportedTabJSON: Data("{}".utf8),
            schemaVersion: 1,
            version: SyncedTabVersion(revision: 1, editedAt: 1000, editedByDeviceID: "DEVICE-A"),
            lastEditedByDeviceName: "Booth Mac",
            hash: "hash-3"
        )
        _ = service.route(request: makeRequest(method: "POST", path: "/syncedTab/push", body: try JSONEncoder().encode(snapshot)))
        XCTAssertEqual(service.pendingSyncedSnapshots.count, 1)

        let drained = service.consumePendingSyncedSnapshots()
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained.first?.groupID, "GROUP-3")
        XCTAssertTrue(service.pendingSyncedSnapshots.isEmpty)
    }

    // MARK: - POST /pair/request + GET /pair/status

    func testPairRequestFromNewDeviceIsPendingAndAppearsInQueue() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let payload = PairingRequestPayload(requestId: "req-1", deviceId: "device-a", deviceName: "MacBook", deviceKind: .macbook, reason: "import a shared tab")
        let response = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))
        XCTAssertTrue(statusLine(response).contains("202"))
        let json = try decodeJSONBody(response, as: [String: String].self)
        XCTAssertEqual(json["status"], "pending")
        XCTAssertEqual(service.pendingPairingRequests.count, 1)
        XCTAssertEqual(service.pendingPairingRequests.first?.payload.deviceId, "device-a")

        let statusResponse = service.route(request: makeRequest(method: "GET", path: "/pair/status?requestId=req-1"))
        let statusJSON = try decodeJSONBody(statusResponse, as: [String: String].self)
        XCTAssertEqual(statusJSON["status"], "pending")
    }

    func testSecondPairRequestFromSameDeviceReplacesFirstPendingEntry() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let first = PairingRequestPayload(requestId: "req-2a", deviceId: "device-b", deviceName: "iPad", deviceKind: .ipad, reason: "join a Synced Tab")
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(first)))
        XCTAssertEqual(service.pendingPairingRequests.count, 1)

        let second = PairingRequestPayload(requestId: "req-2b", deviceId: "device-b", deviceName: "iPad", deviceKind: .ipad, reason: "import a shared tab")
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(second)))

        XCTAssertEqual(service.pendingPairingRequests.count, 1, "a retry from the same device should replace, not duplicate")
        XCTAssertEqual(service.pendingPairingRequests.first?.id, "req-2b")
    }

    func testPairRequestFromAlreadyPairedDeviceIsApprovedImmediately() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let payload = PairingRequestPayload(requestId: "req-3a", deviceId: "device-c", deviceName: "iPhone", deviceKind: .iphone, reason: "join a Synced Tab")
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))
        guard let pending = service.pendingPairingRequests.first(where: { $0.payload.deviceId == "device-c" }) else {
            return XCTFail("expected a pending request")
        }
        service.approvePairingRequest(pending)
        XCTAssertTrue(service.pendingPairingRequests.isEmpty)

        let secondPayload = PairingRequestPayload(requestId: "req-3b", deviceId: "device-c", deviceName: "iPhone", deviceKind: .iphone, reason: "import a shared tab")
        let response = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(secondPayload)))
        let json = try decodeJSONBody(response, as: [String: String].self)
        XCTAssertEqual(json["status"], "approved")
        XCTAssertTrue(service.pendingPairingRequests.isEmpty, "an already-trusted device must not surface a new prompt")

        let statusResponse = service.route(request: makeRequest(method: "GET", path: "/pair/status?requestId=req-3b"))
        let statusJSON = try decodeJSONBody(statusResponse, as: [String: String].self)
        XCTAssertEqual(statusJSON["status"], "approved")
    }

    func testManualConnectRequestsApprovalEvenWhenHostRetainedOldTrust() throws {
        resetLANDefaults()
        let previouslyTrusted = DevicePairingStore.setEnabled(
            true, deviceId: "device-connect", deviceName: "MacBook", deviceKind: .macbook, in: [:]
        )
        DevicePairingStore.save(previouslyTrusted)
        let service = LANSharedTabsService()

        let payload = PairingRequestPayload(
            requestId: "req-connect-reapproval",
            deviceId: "device-connect",
            deviceName: "MacBook",
            deviceKind: .macbook,
            reason: "connect"
        )
        let response = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))

        XCTAssertEqual(try decodeJSONBody(response, as: [String: String].self)["status"], "pending")
        XCTAssertEqual(service.pendingPairingRequests.map(\.id), ["req-connect-reapproval"])
    }

    func testDenyingManualConnectRevokesHostRetainedTrust() throws {
        resetLANDefaults()
        let previouslyTrusted = DevicePairingStore.setEnabled(
            true, deviceId: "device-connect-deny", deviceName: "MacBook", deviceKind: .macbook, in: [:]
        )
        DevicePairingStore.save(previouslyTrusted)
        let service = LANSharedTabsService()
        let payload = PairingRequestPayload(
            requestId: "req-connect-deny",
            deviceId: "device-connect-deny",
            deviceName: "MacBook",
            deviceKind: .macbook,
            reason: "connect"
        )
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))
        guard let pending = service.pendingPairingRequests.first else { return XCTFail("expected approval request") }

        service.denyPairingRequest(pending)

        XCTAssertEqual(DevicePairingStore.status(for: "device-connect-deny", in: service.pairedDevices), .blocked)
    }

    // MARK: - setDeviceEnabled resolving an in-flight handshake

    private func makeTestPeer(deviceId: String, deviceName: String, deviceKind: LANDeviceKind?) -> LANSharedTabsService.Peer {
        LANSharedTabsService.Peer(
            endpointKey: "127.0.0.1:9999",
            deviceId: deviceId,
            deviceName: deviceName,
            deviceKind: deviceKind,
            requiresPairing: true,
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: 9999)!,
            lastSeen: Date()
        )
    }

    func testSetDeviceEnabledTrueResolvesPendingRequestAsApproved() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let payload = PairingRequestPayload(requestId: "req-6", deviceId: "device-f", deviceName: "iPad", deviceKind: .ipad, reason: "join a Synced Tab")
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))
        XCTAssertEqual(service.pendingPairingRequests.count, 1)

        let peer = makeTestPeer(deviceId: "device-f", deviceName: "iPad", deviceKind: .ipad)
        service.setDeviceEnabled(true, for: peer)

        XCTAssertTrue(service.pendingPairingRequests.isEmpty, "approving via Settings must resolve the stale approval-sheet prompt")

        let statusResponse = service.route(request: makeRequest(method: "GET", path: "/pair/status?requestId=req-6"))
        let statusJSON = try decodeJSONBody(statusResponse, as: [String: String].self)
        XCTAssertEqual(statusJSON["status"], "approved", "the joiner's poll must see the Settings-toggle decision, not a stale pending state")
    }

    func testSetDeviceEnabledFalseResolvesPendingRequestAsDenied() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let payload = PairingRequestPayload(requestId: "req-7", deviceId: "device-g", deviceName: "MacBook", deviceKind: .macbook, reason: "import a shared tab")
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))
        XCTAssertEqual(service.pendingPairingRequests.count, 1)

        let peer = makeTestPeer(deviceId: "device-g", deviceName: "MacBook", deviceKind: .macbook)
        service.setDeviceEnabled(false, for: peer)

        XCTAssertTrue(service.pendingPairingRequests.isEmpty)

        let statusResponse = service.route(request: makeRequest(method: "GET", path: "/pair/status?requestId=req-7"))
        let statusJSON = try decodeJSONBody(statusResponse, as: [String: String].self)
        XCTAssertEqual(statusJSON["status"], "denied")
    }

    func testForgetDeviceRemovesTrustEntirely() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let peer = makeTestPeer(deviceId: "device-h", deviceName: "iPad", deviceKind: .ipad)
        service.setDeviceEnabled(true, for: peer)
        XCTAssertEqual(DevicePairingStore.status(for: "device-h", in: service.pairedDevices), .paired)

        service.forgetDevice(peer)

        XCTAssertEqual(DevicePairingStore.status(for: "device-h", in: service.pairedDevices), .notPaired, "forgetting must fully remove the entry, not just block it")
    }

    func testForgetDeviceResolvesPendingRequestAsDenied() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let payload = PairingRequestPayload(requestId: "req-8", deviceId: "device-i", deviceName: "MacBook", deviceKind: .macbook, reason: "join a Synced Tab")
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))
        XCTAssertEqual(service.pendingPairingRequests.count, 1)

        let peer = makeTestPeer(deviceId: "device-i", deviceName: "MacBook", deviceKind: .macbook)
        service.forgetDevice(peer)

        XCTAssertTrue(service.pendingPairingRequests.isEmpty)

        let statusResponse = service.route(request: makeRequest(method: "GET", path: "/pair/status?requestId=req-8"))
        let statusJSON = try decodeJSONBody(statusResponse, as: [String: String].self)
        XCTAssertEqual(statusJSON["status"], "denied")
    }

    func testPairRequestFromBlockedDeviceIsSilentlyDenied() throws {
        resetLANDefaults()
        let blocked = DevicePairingStore.setEnabled(false, deviceId: "device-d", deviceName: "Blocked iPad", deviceKind: .ipad, in: [:])
        DevicePairingStore.save(blocked)
        defer { UserDefaults.standard.removeObject(forKey: "lan_paired_devices") }

        let service = LANSharedTabsService()
        XCTAssertEqual(DevicePairingStore.status(for: "device-d", in: service.pairedDevices), .blocked)

        let payload = PairingRequestPayload(requestId: "req-4", deviceId: "device-d", deviceName: "Blocked iPad", deviceKind: .ipad, reason: "join a Synced Tab")
        let response = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(payload)))
        let json = try decodeJSONBody(response, as: [String: String].self)
        XCTAssertEqual(json["status"], "denied")
        XCTAssertTrue(service.pendingPairingRequests.isEmpty, "a blocked device's request must never surface a prompt")
    }

    func testPairRequestDuringCooldownIsDenied() throws {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        let service = LANSharedTabsService()

        let firstPayload = PairingRequestPayload(requestId: "req-5a", deviceId: "device-e", deviceName: "iPhone", deviceKind: .iphone, reason: "join a Synced Tab")
        _ = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(firstPayload)))
        guard let pending = service.pendingPairingRequests.first(where: { $0.payload.deviceId == "device-e" }) else {
            return XCTFail("expected a pending request")
        }
        service.denyPairingRequest(pending)
        XCTAssertTrue(service.pendingPairingRequests.isEmpty)

        let secondPayload = PairingRequestPayload(requestId: "req-5b", deviceId: "device-e", deviceName: "iPhone", deviceKind: .iphone, reason: "join a Synced Tab")
        let response = service.route(request: makeRequest(method: "POST", path: "/pair/request", body: try JSONEncoder().encode(secondPayload)))
        let json = try decodeJSONBody(response, as: [String: String].self)
        XCTAssertEqual(json["status"], "denied")
        XCTAssertTrue(service.pendingPairingRequests.isEmpty)
    }

    func testPairStatusReturns400WhenRequestIdMissing() {
        resetLANDefaults()
        let service = LANSharedTabsService()
        let response = service.route(request: makeRequest(method: "GET", path: "/pair/status"))
        XCTAssertTrue(statusLine(response).contains("400"))
    }

    func testPairStatusReturns404WhenSharingDisabled() {
        resetLANDefaults()
        UserDefaults.standard.set(false, forKey: "lan_sharing_enabled")
        defer { UserDefaults.standard.removeObject(forKey: "lan_sharing_enabled") }
        let service = LANSharedTabsService()
        let response = service.route(request: makeRequest(method: "GET", path: "/pair/status?requestId=anything"))
        XCTAssertTrue(statusLine(response).contains("404"))
    }

    func testAuthFailureStateTrueFor401() {
        XCTAssertEqual(LANSharedTabsService.authFailureState(forPresencePollStatusCode: 401), true)
    }

    func testAuthFailureStateTrueFor403() {
        XCTAssertEqual(LANSharedTabsService.authFailureState(forPresencePollStatusCode: 403), true)
    }

    func testAuthFailureStateFalseFor200() {
        XCTAssertEqual(LANSharedTabsService.authFailureState(forPresencePollStatusCode: 200), false)
    }

    func testAuthFailureStateFalseFor204() {
        XCTAssertEqual(LANSharedTabsService.authFailureState(forPresencePollStatusCode: 204), false)
    }

    func testAuthFailureStateNilForOtherStatusCodes() {
        XCTAssertNil(LANSharedTabsService.authFailureState(forPresencePollStatusCode: 500))
        XCTAssertNil(LANSharedTabsService.authFailureState(forPresencePollStatusCode: 404))
        XCTAssertNil(LANSharedTabsService.authFailureState(forPresencePollStatusCode: -1))
    }

    func testForgetDeviceClearsAuthFailedFlagForThatPeer() {
        resetLANDefaults()
        let service = LANSharedTabsService()
        let peer = makeTestPeer(deviceId: "TEST-FORGET-DEVICE", deviceName: "Test Device", deviceKind: nil)

        // Simulate a prior auth failure for this peer the same way the /syncedPresence
        // poll would have recorded it.
        service.recordAuthFailureForTesting(endpointKey: peer.endpointKey)
        XCTAssertTrue(service.isAuthFailedForTesting(endpointKey: peer.endpointKey))

        service.forgetDevice(peer)

        XCTAssertFalse(service.isAuthFailedForTesting(endpointKey: peer.endpointKey))
    }

    func testApplyingStalePeerCleanupRemovesStalePeerManifestAndAuthFailedFlag() {
        let freshPeer = makeTestPeer(deviceId: "FRESH-DEVICE", deviceName: "Fresh Device", deviceKind: nil)
        let stalePeer = LANSharedTabsService.Peer(
            endpointKey: "127.0.0.1:8888",
            deviceId: "STALE-DEVICE",
            deviceName: "Stale Device",
            deviceKind: nil,
            requiresPairing: true,
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: 8888)!,
            lastSeen: Date().addingTimeInterval(-999)
        )
        let cutoff = Date().addingTimeInterval(-60)

        let result = LANSharedTabsService.applyingStalePeerCleanup(
            peers: [freshPeer, stalePeer],
            peerManifests: [freshPeer.endpointKey: [], stalePeer.endpointKey: []],
            authFailedPeerEndpointKeys: [freshPeer.endpointKey, stalePeer.endpointKey],
            cutoff: cutoff
        )

        XCTAssertTrue(result.removedAny)
        XCTAssertEqual(result.peers, [freshPeer])
        XCTAssertEqual(Set(result.peerManifests.keys), [freshPeer.endpointKey])
        XCTAssertEqual(result.authFailedPeerEndpointKeys, [freshPeer.endpointKey])
    }

    func testApplyingStalePeerCleanupIsNoOpWhenNoPeersAreStale() {
        let freshPeer = makeTestPeer(deviceId: "FRESH-DEVICE", deviceName: "Fresh Device", deviceKind: nil)
        let cutoff = Date().addingTimeInterval(-60)

        let result = LANSharedTabsService.applyingStalePeerCleanup(
            peers: [freshPeer],
            peerManifests: [freshPeer.endpointKey: []],
            authFailedPeerEndpointKeys: [freshPeer.endpointKey],
            cutoff: cutoff
        )

        XCTAssertFalse(result.removedAny)
        XCTAssertEqual(result.peers, [freshPeer])
        XCTAssertEqual(Set(result.peerManifests.keys), [freshPeer.endpointKey])
        XCTAssertEqual(result.authFailedPeerEndpointKeys, [freshPeer.endpointKey])
    }

    // A peer that goes stale must take its cached synced-tab manifests and presence with it.
    // Leftover manifests kept joined groups "visible" forever, so orphan detection (and the
    // host-reappeared force-refetch it drives) never fired until the app was restarted.
    func testApplyingStalePeerCleanupRemovesStalePeerSyncedManifestsAndPresence() {
        let freshPeer = makeTestPeer(deviceId: "FRESH-DEVICE", deviceName: "Fresh Device", deviceKind: nil)
        let stalePeer = LANSharedTabsService.Peer(
            endpointKey: "127.0.0.1:8888",
            deviceId: "STALE-DEVICE",
            deviceName: "Stale Device",
            deviceKind: nil,
            requiresPairing: true,
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: 8888)!,
            lastSeen: Date().addingTimeInterval(-999)
        )
        let manifest = SyncedTabManifest(
            groupID: "group-1",
            tabName: "Stage",
            deviceID: "STALE-DEVICE",
            deviceName: "Stale Device",
            version: SyncedTabVersion(revision: 1, editedAt: 0, editedByDeviceID: "STALE-DEVICE"),
            summary: SyncedTabManifest.Summary(tileCount: 0, moduleTypes: [])
        )
        let presence = SyncedPresencePayload(deviceID: "STALE-DEVICE", deviceName: "Stale Device", editingByGroup: [:])

        let result = LANSharedTabsService.applyingStalePeerCleanup(
            peers: [freshPeer, stalePeer],
            peerManifests: [:],
            peerSyncedManifests: [freshPeer.endpointKey: [], stalePeer.endpointKey: [manifest]],
            peerPresence: [stalePeer.endpointKey: presence],
            authFailedPeerEndpointKeys: [],
            cutoff: Date().addingTimeInterval(-60)
        )

        XCTAssertEqual(Set(result.peerSyncedManifests.keys), [freshPeer.endpointKey])
        XCTAssertTrue(result.peerPresence.isEmpty)
    }

    // Plain `.bonjour` browsing never delivers TXT records (metadata is always .none), which
    // made every peer's deviceId fall back to its computer name and broke pairing trust.
    func testBrowseDescriptorRequestsTXTRecords() {
        let descriptor = LANSharedTabsService.makeBrowseDescriptor(serviceType: "_relay._tcp", domain: "local.")
        guard case .bonjourWithTXTRecord(let type, let domain) = descriptor else {
            return XCTFail("Expected .bonjourWithTXTRecord, got \(descriptor)")
        }
        XCTAssertEqual(type, "_relay._tcp")
        XCTAssertEqual(domain, "local.")
    }

    // Notify nodes targeting a specific peer saved `peer.deviceId`, which older builds set to
    // the computer's name (TXT records were never read). Those saved targets must keep matching
    // now that deviceId is the real per-install ID.
    func testNotifyTargetMatchesDeviceIdEndpointKeyOrLegacyName() {
        let peer = LANSharedTabsService.Peer(
            endpointKey: "192.168.1.5:38475",
            deviceId: "UUID-FOH",
            deviceName: "FOH Mac mini",
            deviceKind: nil,
            requiresPairing: true,
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: 38475)!,
            lastSeen: Date()
        )
        XCTAssertTrue(peer.matchesSavedTarget("UUID-FOH"))
        XCTAssertTrue(peer.matchesSavedTarget("192.168.1.5:38475"))
        XCTAssertTrue(peer.matchesSavedTarget("FOH Mac mini"))
        XCTAssertFalse(peer.matchesSavedTarget("PG-WC-BOH"))
        XCTAssertFalse(peer.matchesSavedTarget(""))
    }

    // A failed listener (sleep/wake, network change, port in use) is restarted with capped
    // exponential backoff so a persistent failure can't spin in a tight loop.
    func testListenerRestartDelayBacksOffAndCaps() {
        XCTAssertEqual(LANSharedTabsService.listenerRestartDelay(afterConsecutiveFailures: 1), 2)
        XCTAssertEqual(LANSharedTabsService.listenerRestartDelay(afterConsecutiveFailures: 2), 4)
        XCTAssertEqual(LANSharedTabsService.listenerRestartDelay(afterConsecutiveFailures: 3), 8)
        XCTAssertEqual(LANSharedTabsService.listenerRestartDelay(afterConsecutiveFailures: 10), 30)
    }

    // A computer on an older build that started pairing saved this device under its name, so it
    // rejects our requests with 401 while we still show it as Paired. Any paired peer that is
    // rejecting us — not only one hosting a joined tab — should offer Reconnect, which sends a
    // fresh request the older build will prompt for and then trust by deviceId.
    func testPeerNeedsReconnectOnlyWhenPairedAndRejectingRequests() {
        resetLANDefaults()
        UserDefaults.standard.removeObject(forKey: "lan_paired_devices")
        defer { UserDefaults.standard.removeObject(forKey: "lan_paired_devices") }
        let service = LANSharedTabsService()
        let peer = makeTestPeer(deviceId: "OLD-BUILD-DEVICE", deviceName: "Old Mac", deviceKind: nil)

        service.recordAuthFailureForTesting(endpointKey: peer.endpointKey)
        XCTAssertFalse(service.peerNeedsReconnect(peer), "Unpaired peers already show Connect")

        service.setDeviceEnabled(true, for: peer)
        XCTAssertTrue(service.peerNeedsReconnect(peer))

        service.setPeerEnabled(true, for: peer) // clears the auth-failure flag
        XCTAssertFalse(service.peerNeedsReconnect(peer))
    }
}
