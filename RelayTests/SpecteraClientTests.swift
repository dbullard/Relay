import XCTest
@testable import Relay

@MainActor
final class SpecteraClientTests: XCTestCase {
    func test_specteraModel_usesSSCv2Metadata() {
        let model = SennheiserNetworkModel.specteraBaseStation

        XCTAssertEqual(model.defaultPort, 443)
        XCTAssertEqual(model.protocolKind, .sscv2Spectera)
        XCTAssertEqual(model.channelCount, 0)
        XCTAssertTrue(model.supportsNetwork)
        XCTAssertFalse(model.supportsSscV1Control)
    }

    func test_specteraUsesItsOwnDiagnosticsLoggingFamily() {
        XCTAssertEqual(
            WirelessLoggingPreferences.resolveSennheiserFamily(from: SennheiserNetworkModel.specteraBaseStation.rawValue),
            .spectera
        )
    }

    func test_certificateFingerprint_isSHA256WithColonSeparatedHex() {
        XCTAssertEqual(
            SpecteraCertificateTrust.fingerprint(for: Data("abc".utf8)),
            "BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD"
        )
    }

    func test_makeRequest_usesHTTPSBasicAuthAndSpecteraPort() {
        let request = SpecteraClient.makeRequest(
            host: "192.168.1.90",
            path: "/api/mts/paired/all",
            password: "relay-test-password"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://192.168.1.90:443/api/mts/paired/all")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Basic Y29udHJvbFNlbm5oZWlzZXI6cmVsYXktdGVzdC1wYXNzd29yZA=="
        )
    }

    func test_makeSnapshots_usesMobileUIDAsStableRemoteID() {
        let deviceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let snapshots = SpecteraClient.makeSnapshots(
            deviceID: deviceID,
            deviceName: "Spectera A",
            pairedDevices: [
                .init(mtUID: "mt-2", name: "Pastor", isConnected: true, micAudioLinkID: "2", isMicAudioLinkActive: true)
            ]
        )

        XCTAssertEqual(snapshots.map(\.channelRemoteID), ["mt-2"])
        XCTAssertEqual(snapshots.map(\.channelName), ["Pastor"])
    }

    func test_subscriptionResources_watchPairedDevices() {
        XCTAssertEqual(
            SpecteraClient.subscriptionResources,
            ["/api/mts/paired/all"]
        )
    }

    func test_pairedMobileDevice_decodesSchema17NumericIdentifiers() throws {
        let data = Data("""
        {
          "mtUid": 16789965,
          "name": "SEK",
          "state": "Connected",
          "micAudiolinkId": 39,
          "micAudiolinkActive": true
        }
        """.utf8)

        let device = try JSONDecoder().decode(SpecteraClient.PairedMobileDevice.self, from: data)

        XCTAssertEqual(device.mtUID, "16789965")
        XCTAssertEqual(device.micAudioLinkID, "39")
        XCTAssertTrue(device.hasActiveMicAudioLink)
    }
}
