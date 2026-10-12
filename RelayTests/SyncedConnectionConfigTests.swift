import XCTest
import Foundation
@testable import Relay

@MainActor
final class SyncedConnectionConfigTests: XCTestCase {

    private func makeTab(tileID: UUID, moduleID: UUID, kind: DashboardModuleKind, configure: (inout DashboardModuleModel) -> Void = { _ in }) -> DashboardTab {
        var module = DashboardModuleModel(kind: kind, order: 0, id: moduleID)
        configure(&module)
        let tile = DashboardTileModel(id: tileID, kind: .empty, modules: [module], offset: .zero)
        return DashboardTab(name: "Stage Plot", tiles: [tile])
    }

    private func module(in tab: DashboardTab) -> DashboardModuleModel {
        tab.tiles[0].modules![0]
    }

    // MARK: - ProPresenter (config struct mixes connection + display fields)

    func testProPresenterConnectionProfileIDIsPreservedFromCurrent() {
        let tileID = UUID()
        let moduleID = UUID()
        let localProfileID = UUID()
        let peerProfileID = UUID()

        let current = makeTab(tileID: tileID, moduleID: moduleID, kind: .proPresenter) {
            $0.proPresenterConfig = ProPresenterModuleConfig()
            $0.proPresenterConfig?.connectionProfileID = localProfileID
            $0.proPresenterConfig?.showPresentationName = true
        }
        let incoming = makeTab(tileID: tileID, moduleID: moduleID, kind: .proPresenter) {
            $0.proPresenterConfig = ProPresenterModuleConfig()
            $0.proPresenterConfig?.connectionProfileID = peerProfileID
            $0.proPresenterConfig?.showPresentationName = false
        }

        let result = preservingLocalConnectionConfig(incoming: incoming, current: current)
        let resultModule = module(in: result)

        XCTAssertEqual(resultModule.proPresenterConfig?.connectionProfileID, localProfileID, "connection profile must stay local")
        XCTAssertEqual(resultModule.proPresenterConfig?.showPresentationName, false, "non-connection display prefs should still sync from the peer")
    }

    // MARK: - RTA (audio input reference embedded in the module's associated value)

    func testRTAInputIDIsPreservedFromCurrent() {
        let tileID = UUID()
        let moduleID = UUID()
        let localInputID = UUID()
        let peerInputID = UUID()

        let current = makeTab(tileID: tileID, moduleID: moduleID, kind: .rta(RTAModuleModel(inputID: localInputID, showPeakHold: true)))
        let incoming = makeTab(tileID: tileID, moduleID: moduleID, kind: .rta(RTAModuleModel(inputID: peerInputID, showPeakHold: false)))

        let result = preservingLocalConnectionConfig(incoming: incoming, current: current)

        guard case .rta(let resultModel) = module(in: result).kind else {
            return XCTFail("expected .rta")
        }
        XCTAssertEqual(resultModel.inputID, localInputID, "audio input assignment must stay local — it references this device's own AudioInputsConfigStore")
        XCTAssertEqual(resultModel.showPeakHold, false, "non-connection display prefs should still sync from the peer")
    }

    func testRTAInputIDNotClearedWhenPeerHasNoInputSelected() {
        // Mirrors the reported bug: a "blank" joining device with no configured audio inputs
        // pushes inputID == nil; the host's real assignment must survive that push.
        let tileID = UUID()
        let moduleID = UUID()
        let localInputID = UUID()

        let current = makeTab(tileID: tileID, moduleID: moduleID, kind: .rta(RTAModuleModel(inputID: localInputID)))
        let incoming = makeTab(tileID: tileID, moduleID: moduleID, kind: .rta(RTAModuleModel(inputID: nil)))

        let result = preservingLocalConnectionConfig(incoming: incoming, current: current)

        guard case .rta(let resultModel) = module(in: result).kind else {
            return XCTFail("expected .rta")
        }
        XCTAssertEqual(resultModel.inputID, localInputID)
    }

    // MARK: - NDI (mixed connection fields + display fields inside one associated model)

    func testNDIConnectionFieldsPreservedButDisplayPrefsSync() {
        let tileID = UUID()
        let moduleID = UUID()

        var localNDI = NDIModuleModel()
        localNDI.sourceID = "LOCAL-SOURCE"
        localNDI.sourceName = "Local Camera"
        localNDI.interfaceSelection = .specific("en0")
        localNDI.qualityTier = .preview

        var peerNDI = NDIModuleModel()
        peerNDI.sourceID = "PEER-SOURCE"
        peerNDI.sourceName = "Peer Camera"
        peerNDI.interfaceSelection = .globalPreferred
        peerNDI.qualityTier = .live

        let current = makeTab(tileID: tileID, moduleID: moduleID, kind: .ndi(localNDI))
        let incoming = makeTab(tileID: tileID, moduleID: moduleID, kind: .ndi(peerNDI))

        let result = preservingLocalConnectionConfig(incoming: incoming, current: current)

        guard case .ndi(let resultModel) = module(in: result).kind else {
            return XCTFail("expected .ndi")
        }
        XCTAssertEqual(resultModel.sourceID, "LOCAL-SOURCE")
        XCTAssertEqual(resultModel.sourceName, "Local Camera")
        XCTAssertEqual(resultModel.interfaceSelection, .specific("en0"))
        XCTAssertEqual(resultModel.qualityTier, .live, "quality tier is a display/perf preference, not a connection — it should sync")
    }

    // MARK: - DAW Transport (MIDI connection identifiers)

    func testDAWTransportMIDIFieldsArePreservedFromCurrent() {
        let tileID = UUID()
        let moduleID = UUID()

        var localConfig = DAWTransportModuleConfiguration()
        localConfig.midiInputSourceID = 111
        localConfig.midiOutputDestinationID = 222
        localConfig.connectionName = "Local Pro Tools"
        localConfig.showTimer = true

        var peerConfig = DAWTransportModuleConfiguration()
        peerConfig.midiInputSourceID = 999
        peerConfig.midiOutputDestinationID = 888
        peerConfig.connectionName = "Peer Pro Tools"
        peerConfig.showTimer = false

        let current = makeTab(tileID: tileID, moduleID: moduleID, kind: .dawTransport) {
            $0.dawTransportConfig = localConfig
        }
        let incoming = makeTab(tileID: tileID, moduleID: moduleID, kind: .dawTransport) {
            $0.dawTransportConfig = peerConfig
        }

        let result = preservingLocalConnectionConfig(incoming: incoming, current: current)
        let resultConfig = module(in: result).dawTransportConfig

        XCTAssertEqual(resultConfig?.midiInputSourceID, 111)
        XCTAssertEqual(resultConfig?.midiOutputDestinationID, 222)
        XCTAssertEqual(resultConfig?.connectionName, "Local Pro Tools")
        XCTAssertEqual(resultConfig?.showTimer, false, "non-connection display prefs should still sync from the peer")
    }

    // MARK: - Sanity: ordinary content still replicates from the peer

    func testNonConnectionTabContentStillSyncsFromIncoming() {
        let tileID = UUID()
        let moduleID = UUID()

        let current = makeTab(tileID: tileID, moduleID: moduleID, kind: .text(TextModuleModel(content: AttributedString("old"))))
        var incoming = makeTab(tileID: tileID, moduleID: moduleID, kind: .text(TextModuleModel(content: AttributedString("new"))))
        incoming.name = "Renamed by peer"

        let result = preservingLocalConnectionConfig(incoming: incoming, current: current)

        XCTAssertEqual(result.name, "Renamed by peer")
        guard case .text(let resultModel) = module(in: result).kind else {
            return XCTFail("expected .text")
        }
        XCTAssertEqual(String(resultModel.content.characters), "new")
    }
}
