import XCTest
@testable import Relay

@MainActor
final class DAWTransportProfileTests: XCTestCase {

    func testAllCurrentProfilesHaveExpectedCommandProtocols() {
        let expectations: [(DAWTransportType, DAWTransportCommandMode, [UInt8])] = [
            (.proToolsHUI, .hui, [0xB0, 0x0F, 0x0E, 0xB0, 0x2F, 0x44]),
            (.logicProHUI, .hui, [0xB0, 0x0F, 0x0E, 0xB0, 0x2F, 0x44]),
            (.reaperHUI, .hui, [0xB0, 0x0F, 0x0E, 0xB0, 0x2F, 0x44]),
            (.cubaseNuendoHUI, .hui, [0xB0, 0x0F, 0x0E, 0xB0, 0x2F, 0x44]),
            (.digitalPerformerHUI, .hui, [0xB0, 0x0F, 0x0E, 0xB0, 0x2F, 0x44]),
            (.genericHUI, .hui, [0xB0, 0x0F, 0x0E, 0xB0, 0x2F, 0x44]),
            (.reaperMCU, .mcu, [0x90, 0x5E, 0x7F]),
            (.genericMTCMMC, .mmc, [0xF0, 0x7F, 0x7F, 0x06, 0x02, 0xF7])
        ]

        for (dawType, commandMode, expectedPlayBytes) in expectations {
            var configuration = DAWTransportModuleConfiguration()
            configuration.dawType = dawType
            configuration.commandMode = commandMode

            let bytes = DAWTransportCommandEncoder.encode(
                command: .play,
                configuration: configuration,
                isInputConnected: true,
                isOutputConnected: true
            )

            XCTAssertEqual(bytes, expectedPlayBytes, "Unexpected play bytes for \(dawType)")
        }
    }

    func testAutomaticModeUsesProfilePreferredCommandProtocol() {
        var huiConfiguration = DAWTransportModuleConfiguration()
        huiConfiguration.dawType = .logicProHUI
        huiConfiguration.commandMode = .automatic
        XCTAssertEqual(
            DAWTransportCommandEncoder.encode(command: .stop, configuration: huiConfiguration, isInputConnected: true, isOutputConnected: true),
            [0xB0, 0x0F, 0x0E, 0xB0, 0x2F, 0x43]
        )

        var mcuConfiguration = DAWTransportModuleConfiguration()
        mcuConfiguration.dawType = .reaperMCU
        mcuConfiguration.commandMode = .automatic
        XCTAssertEqual(
            DAWTransportCommandEncoder.encode(command: .stop, configuration: mcuConfiguration, isInputConnected: true, isOutputConnected: true),
            [0x90, 0x5D, 0x7F]
        )

        var mtcConfiguration = DAWTransportModuleConfiguration()
        mtcConfiguration.dawType = .genericMTCMMC
        mtcConfiguration.commandMode = .automatic
        XCTAssertEqual(
            DAWTransportCommandEncoder.encode(command: .stop, configuration: mtcConfiguration, isInputConnected: true, isOutputConnected: true),
            [0xF0, 0x7F, 0x7F, 0x06, 0x01, 0xF7]
        )
    }

    func testSyntheticDisplayClassificationAcrossCurrentProfiles() {
        let cases: [(DAWTransportType, String, DAWCounterKind, String, DAWCounterSource)] = [
            (.logicProHUI, "12|3|240", .barsBeats, "12.3.240", .huiDisplay),
            (.reaperHUI, "Loop Start", .unknown, "Loop Start", .huiDisplay),
            (.reaperMCU, "42.04.120", .barsBeats, "42.04.120", .mcuDisplay),
            (.cubaseNuendoHUI, "01:02:03:04", .timecode, "01:02:03:04", .huiDisplay),
            (.digitalPerformerHUI, "100+12", .feetFrames, "100+12", .huiDisplay),
            (.genericMTCMMC, "01:02:03:04", .timecode, "01:02:03:04", .mtc)
        ]

        for (dawType, rawText, expectedKind, expectedDisplay, source) in cases {
            let display = DAWCounterClassifier.classify(
                rawText: rawText,
                explicitFeedbackMode: nil,
                dawType: dawType,
                source: source
            )

            XCTAssertEqual(display.kind, expectedKind, "Unexpected kind for \(dawType)")
            XCTAssertEqual(display.displayText, expectedDisplay, "Unexpected display for \(dawType)")
        }
    }

    func testConnectionLabelUsesCustomNameBeforeMIDIPortName() {
        var configuration = DAWTransportModuleConfiguration.default()
        configuration.dawType = .proToolsHUI
        configuration.connectionName = "FOH Pro Tools"

        let label = DAWTransportConnectionLabelResolver.resolve(
            configuration: configuration,
            midiOutputName: "Studio MacBook Pro",
            midiInputName: "Studio MacBook Pro Input"
        )

        XCTAssertEqual(label.title, "FOH Pro Tools")
        XCTAssertEqual(label.subtitle, "Pro Tools HUI")
    }

    func testConnectionLabelUsesMIDIPortNameWhenConnectionNameIsEmpty() {
        var configuration = DAWTransportModuleConfiguration.default()
        configuration.dawType = .proToolsHUI
        configuration.connectionName = "   "

        let label = DAWTransportConnectionLabelResolver.resolve(
            configuration: configuration,
            midiOutputName: "Studio MacBook Pro",
            midiInputName: nil
        )

        XCTAssertEqual(label.title, "Studio MacBook Pro")
        XCTAssertEqual(label.subtitle, "Pro Tools HUI")
    }

    func testConnectionLabelFallsBackToInputNameWhenOutputNameIsUnavailable() {
        var configuration = DAWTransportModuleConfiguration.default()
        configuration.dawType = .genericHUI

        let label = DAWTransportConnectionLabelResolver.resolve(
            configuration: configuration,
            midiOutputName: nil,
            midiInputName: "Playback Mac Input"
        )

        XCTAssertEqual(label.title, "Playback Mac Input")
        XCTAssertEqual(label.subtitle, "Generic HUI")
    }

    func testConnectionLabelFallsBackToSelectedDAWProfileWhenNoConnectionTargetIsKnown() {
        let expectations: [(DAWTransportType, String)] = [
            (.proToolsHUI, "Pro Tools HUI"),
            (.logicProHUI, "Logic Pro HUI"),
            (.reaperHUI, "REAPER HUI"),
            (.genericHUI, "Generic HUI")
        ]

        for (dawType, expectedTitle) in expectations {
            var configuration = DAWTransportModuleConfiguration.default()
            configuration.dawType = dawType

            let label = DAWTransportConnectionLabelResolver.resolve(
                configuration: configuration,
                midiOutputName: nil,
                midiInputName: nil
            )

            XCTAssertEqual(label.title, expectedTitle, "Unexpected fallback title for \(dawType)")
            XCTAssertNil(label.subtitle)
        }
    }

    func testConfigurationRoundTripPreservesCustomConnectionName() throws {
        var configuration = DAWTransportModuleConfiguration.default()
        configuration.dawType = .proToolsHUI
        configuration.connectionName = "FOH Pro Tools"

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(DAWTransportModuleConfiguration.self, from: data)

        XCTAssertEqual(decoded.connectionName, "FOH Pro Tools")
        XCTAssertEqual(decoded.resolvedConnectionName, "FOH Pro Tools")
    }
}
