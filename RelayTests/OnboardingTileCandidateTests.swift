import XCTest
@testable import Relay

final class OnboardingTileCandidateTests: XCTestCase {

    func test_candidateForShureDevice_bindsSelectedChannelToDeviceID() {
        let device = ExternalDeviceConfig(name: "Shure Rack", kind: .shureWireless, host: "192.168.1.50", port: 2202)

        let candidate = OnboardingTileCandidateFactory.candidate(for: device)

        XCTAssertEqual(candidate?.title, "Shure Rack")
        XCTAssertEqual(candidate?.module.kind, .shureWireless)
        XCTAssertEqual(candidate?.module.shureConfig?.selectedChannel?.deviceID, device.id)
        XCTAssertEqual(candidate?.module.shureConfig?.selectedChannel?.channelIndex, 1)
    }

    func test_candidateForSennheiserDevice_bindsExternalDeviceID() {
        let device = ExternalDeviceConfig(name: "Sennheiser Rack", kind: .sennheiserWireless, host: "192.168.1.51", port: 45)

        let candidate = OnboardingTileCandidateFactory.candidate(for: device)

        XCTAssertEqual(candidate?.module.sennheiserConfig?.externalDeviceID, device.id)
        XCTAssertEqual(candidate?.module.sennheiserConfig?.channelIndex, 1)
    }

    func test_candidateForConsoleDevices_isNil() {
        let audioConsole = ExternalDeviceConfig(name: "X32", kind: .audioConsole, host: "192.168.1.52", port: 10023)
        let vistaConsole = ExternalDeviceConfig(name: "Vista", kind: .vistaConsole, host: "192.168.1.53", port: 80)

        XCTAssertNil(OnboardingTileCandidateFactory.candidate(for: audioConsole))
        XCTAssertNil(OnboardingTileCandidateFactory.candidate(for: vistaConsole))
    }

    func test_candidateForAudioInput_bindsInputID() {
        let input = AudioInputConfig(name: "FOH Mic")

        let candidate = OnboardingTileCandidateFactory.candidate(for: input)

        XCTAssertEqual(candidate.title, "FOH Mic")
        if case .rta(let model) = candidate.module.kind {
            XCTAssertEqual(model.inputID, input.id)
        } else {
            XCTFail("Expected .rta module kind")
        }
    }

    func test_candidateForCatalogEntry_buildsModuleFromEntryKind() {
        let entries = OnboardingStarterTileCatalog.availableEntries()
        guard let textEntry = entries.first(where: { $0.id == "text" }) else {
            XCTFail("Expected 'text' entry in starter tile catalog")
            return
        }

        let candidate = OnboardingTileCandidateFactory.candidate(for: textEntry)

        XCTAssertEqual(candidate.title, "Text")
        if case .text = candidate.module.kind {
            // expected
        } else {
            XCTFail("Expected .text module kind, got \(candidate.module.kind)")
        }
    }

    func test_candidateForCatalogEntry_generatesFreshID() {
        let entries = OnboardingStarterTileCatalog.availableEntries()
        guard let timeEntry = entries.first(where: { $0.id == "time" }) else {
            XCTFail("Expected 'time' entry in starter tile catalog")
            return
        }

        let first = OnboardingTileCandidateFactory.candidate(for: timeEntry)
        let second = OnboardingTileCandidateFactory.candidate(for: timeEntry)

        XCTAssertNotEqual(first.id, second.id)
    }

    func test_candidateForShureDevice_setsWirelessIconAndSubtitle() {
        let device = ExternalDeviceConfig(name: "Shure Rack", kind: .shureWireless, host: "192.168.1.50", port: 2202)

        let candidate = OnboardingTileCandidateFactory.candidate(for: device)

        XCTAssertEqual(candidate?.systemImage, "dot.radiowaves.left.and.right")
        XCTAssertEqual(candidate?.subtitle, "Wireless mic + IEM status")
    }

    func test_candidateForAudioInput_setsWaveformIconAndSubtitle() {
        let input = AudioInputConfig(name: "FOH Mic")

        let candidate = OnboardingTileCandidateFactory.candidate(for: input)

        XCTAssertEqual(candidate.systemImage, "waveform")
        XCTAssertEqual(candidate.subtitle, "Real-time frequency analyzer")
    }

    func test_candidateForCatalogEntry_copiesSubtitleAndIconFromEntry() {
        let entries = OnboardingStarterTileCatalog.availableEntries()
        guard let textEntry = entries.first(where: { $0.id == "text" }) else {
            XCTFail("Expected 'text' entry in starter tile catalog")
            return
        }

        let candidate = OnboardingTileCandidateFactory.candidate(for: textEntry)

        XCTAssertEqual(candidate.subtitle, textEntry.subtitle)
        XCTAssertEqual(candidate.systemImage, textEntry.systemImage)
    }
}
