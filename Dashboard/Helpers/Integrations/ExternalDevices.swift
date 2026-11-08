//
//  ExternalDeviceKind.swift
//  Relay
//
//  Created by David Bullard on 11/19/25.
//


//
//  ExternalDevices.swift
//  Relay
//
//  Created by David Bullard on 11/19/25.
//

import Foundation
import SwiftUI
import Combine

/// High-level category of external device.
/// Expand this as you add more integration types.
enum ExternalDeviceKind: String, Codable, CaseIterable, Identifiable {
    case audioConsole
    case vistaConsole
    case shureWireless
    case sennheiserWireless
    /// Deprecated: hidden from UI (kept for backwards compatibility).
    case lightingConsole
    /// Deprecated: hidden from UI (kept for backwards compatibility).
    case genericOsc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .audioConsole:        return "Audio Console"
        case .vistaConsole:        return "Vista Console"
        case .shureWireless:       return "Shure Wireless"
        case .sennheiserWireless:  return "Sennheiser Wireless"
        case .lightingConsole:     return "Lighting Console"
        case .genericOsc:          return "Generic OSC Device"
        }
    }

    var systemImage: String {
        switch self {
        case .audioConsole:        return "slider.horizontal.3"
        case .vistaConsole:        return "light.beacon.max"
        case .shureWireless:       return "dot.radiowaves.left.and.right"
        case .sennheiserWireless:  return "dot.radiowaves.left.and.right"
        case .lightingConsole:     return "light.max"
        case .genericOsc:          return "waveform"
        }
    }

    static func sortedByDisplayName(_ kinds: [ExternalDeviceKind]) -> [ExternalDeviceKind] {
        kinds.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

/// Known Shure network-capable receiver models.
enum ShureNetworkModel: String, CaseIterable, Identifiable, Codable {
    case ad4q = "AD4Q"
    case ad4d = "AD4D"
    case ad4  = "AD4"
    case anx4 = "ANX4"
    case adtd = "ADTD"
    case adtq = "ADTQ"
    case ulxd4q = "ULXD4Q"
    case ulxd4d = "ULXD4D"
    case ulxd4  = "ULXD4"
    case qlxd4  = "QLXD4"
    case slxd4d = "SLXD4D"
    case slxd4  = "SLXD4"
    case p10t   = "P10T"
    case psm900 = "PSM900"

    var id: String { rawValue }

    var isBetaOnly: Bool {
        switch self {
        case .anx4, .adtd, .adtq:
            return true
        default:
            return false
        }
    }

    var isAvailableInCurrentBuild: Bool {
        !isBetaOnly || RelayBuildConfig.isPreviewEnabled
    }

    var displayName: String {
        switch self {
        case .ad4q:   return "Axient Digital AD4Q (4-channel)"
        case .ad4d:   return "Axient Digital AD4D (2-channel)"
        case .ad4:    return "Axient Digital AD4 (1-channel)"
        case .anx4:   return "Axient Digital ANX4 (license‑expandable)"
        case .adtd:   return "Axient Digital PSM ADT (license‑expandable, IEM)"
        case .adtq:   return "Axient Digital PSM ADTQ (license‑expandable, IEM)"
        case .ulxd4q: return "ULX-D ULXD4Q (4-channel)"
        case .ulxd4d: return "ULX-D ULXD4D (2-channel)"
        case .ulxd4:  return "ULX-D ULXD4 (1-channel)"
        case .qlxd4:  return "QLX-D QLXD4 (1-channel)"
        case .slxd4d: return "SLX-D SLXD4D (2-channel)"
        case .slxd4:  return "SLX-D SLXD4 (1-channel)"
        case .p10t:   return "PSM 1000 P10T (2-channel)"
        case .psm900: return "PSM 900 P9T (1-channel)"
        }
    }

    var channelCount: Int {
        switch self {
        case .ad4q, .ulxd4q, .anx4, .adtq:
            return 4
        case .ad4d, .ulxd4d, .slxd4d, .p10t, .adtd:
            return 2
        default:
            return 1
        }
    }

    var supportsNetwork: Bool {
        switch self {
        case .psm900:
            return false
        default:
            return true
        }
    }

    static func from(deviceName: String) -> ShureNetworkModel? {
        let upper = deviceName.uppercased()
        if upper.contains("MCR AD") || upper.contains("MCR_AD") {
            return .anx4
        }
        if upper.contains("UXLD1") || upper.contains("ULXD1") {
            return .ulxd4
        }
        if upper.contains("PSM 900") {
            return .psm900
        }
        return Self.selectionCases
            .sorted { $0.rawValue.count > $1.rawValue.count }
            .first(where: { upper.contains($0.rawValue) })
    }

    static func mostSpecific(from texts: [String?]) -> ShureNetworkModel? {
        var best: ShureNetworkModel?

        for text in texts {
            guard let text else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let upper = trimmed.uppercased()
            let candidate: ShureNetworkModel?
            if let exact = Self.selectionCases.first(where: { $0.rawValue == upper }) {
                candidate = exact
            } else {
                candidate = from(deviceName: upper)
            }

            guard let candidate else { continue }
            if let currentBest = best {
                if candidate.rawValue.count > currentBest.rawValue.count {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    static var selectionCases: [ShureNetworkModel] {
        allCases.filter(\.isAvailableInCurrentBuild)
    }
}

enum ShureAnx4Mode: String, CaseIterable, Identifiable, Codable {
    case axient = "Axient"
    case ulxd = "ULX-D"

    var id: String { rawValue }
    var displayName: String { rawValue }
    var maxChannels: Int {
        switch self {
        case .axient: return 16
        case .ulxd: return 24
        }
    }
}

enum ShureTransportMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case udpPreferred = "udp_preferred"
    case tcpOnly = "tcp_only"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .udpPreferred:
            return "UDP Preferred"
        case .tcpOnly:
            return "TCP Only"
        }
    }

    var helpText: String {
        switch self {
        case .auto:
            return "Use TCP command strings (recommended). Same as TCP Only below."
        case .udpPreferred:
            return "Use the older UDP connection instead. Only needed if this receiver doesn't have TCP command strings enabled in its Network Services menu."
        case .tcpOnly:
            return "Use TCP command strings only. This is the default and recommended setting."
        }
    }
}

enum VenueOSCTransportMode: String, CaseIterable, Identifiable, Codable {
    case tcp
    case udp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tcp: return "TCP Client"
        case .udp: return "UDP"
        }
    }
}

/// Known Sennheiser wireless families commonly deployed in venues.
enum SennheiserNetworkModel: String, CaseIterable, Identifiable, Codable {
    case ewdxEm2 = "EW-DX EM 2"
    case ewdxEm2Dante = "EW-DX EM 2 Dante"
    case ewdxEm4Dante = "EW-DX EM 4 Dante"
    case em6000 = "EM 6000"
    case specteraBaseStation = "Spectera Base Station"

    case ewG4_100 = "EW G4 100"
    case ewG4_300 = "EW G4 300"
    case ewG4_500 = "EW G4 500"
    case ewG3 = "EW G3"

    case ewIemG4 = "EW IEM G4"
    case srIemG4 = "SR IEM G4"
    case iem2000 = "2000 IEM"
    case ek300IemG3 = "EK 300 IEM G3"
    case xswIem = "XSW IEM"

    var id: String { rawValue }

    enum Category: String {
        case mic
        case iem
    }

    var category: Category {
        switch self {
        case .ewIemG4, .srIemG4, .iem2000, .ek300IemG3, .xswIem:
            return .iem
        default:
            return .mic
        }
    }

    var displayName: String {
        switch self {
        case .ewdxEm2:
            return "EW-DX EM 2 (2-channel)"
        case .ewdxEm2Dante:
            return "EW-DX EM 2 Dante (2-channel)"
        case .ewdxEm4Dante:
            return "EW-DX EM 4 Dante (4-channel)"
        case .em6000:
            return "Digital 6000 EM 6000 (2-channel)"
        case .specteraBaseStation:
            return "Spectera Base Station"
        case .ewG4_100:
            return "Evolution Wireless G4 100 Series"
        case .ewG4_300:
            return "Evolution Wireless G4 300 Series"
        case .ewG4_500:
            return "Evolution Wireless G4 500 Series"
        case .ewG3:
            return "Evolution Wireless G3"
        case .ewIemG4:
            return "EW IEM G4 (stereo IEM)"
        case .srIemG4:
            return "SR IEM G4 (stereo transmitter)"
        case .iem2000:
            return "2000 IEM Series (SR/EK 2000)"
        case .ek300IemG3:
            return "EK 300 IEM G3"
        case .xswIem:
            return "XS Wireless IEM (XSW IEM)"
        }
    }

    var channelCount: Int {
        switch self {
        case .ewdxEm4Dante:
            return 4
        case .ewdxEm2, .ewdxEm2Dante, .em6000:
            return 2
        case .specteraBaseStation:
            return 0
        default:
            return 1
        }
    }

    var supportsNetwork: Bool {
        switch self {
        case .ewdxEm2, .ewdxEm2Dante, .ewdxEm4Dante, .em6000,
             .specteraBaseStation, .ewG4_300, .ewG4_500, .ewG3, .ewIemG4, .srIemG4:
            return true
        default:
            return false
        }
    }

    var isSupportedNow: Bool {
        switch self {
        case .ewdxEm2, .ewdxEm2Dante, .ewdxEm4Dante, .em6000,
             .specteraBaseStation, .ewG4_300, .ewG4_500, .ewG3, .ewIemG4, .srIemG4:
            return true
        default:
            return false
        }
    }

    static var supportedCases: [SennheiserNetworkModel] {
        allCases.filter { $0.isSupportedNow }
    }

    static var unsupportedCases: [SennheiserNetworkModel] {
        allCases.filter { !$0.isSupportedNow }
    }

    enum ProtocolKind: String, Codable {
        case sscV1Udp
        case sscv2Spectera
        case d6000Udp
        case mcpV1
        case unknown
    }

    var protocolKind: ProtocolKind {
        switch self {
        case .ewdxEm2, .ewdxEm2Dante, .ewdxEm4Dante:
            return .sscV1Udp
        case .em6000:
            return .d6000Udp
        case .specteraBaseStation:
            return .sscv2Spectera
        case .ewG4_100, .ewG4_300, .ewG4_500, .ewG3, .ewIemG4, .srIemG4, .iem2000, .ek300IemG3, .xswIem:
            return .mcpV1
        }
    }

    var defaultPort: Int {
        switch protocolKind {
        case .sscV1Udp:
            return 45
        case .sscv2Spectera:
            return 443
        case .d6000Udp:
            return 6970
        case .mcpV1:
            return 53212
        case .unknown:
            return 0
        }
    }

    var supportsSscV1Control: Bool {
        switch self {
        case .ewdxEm2, .ewdxEm2Dante, .ewdxEm4Dante:
            return true
        default:
            return false
        }
    }

    static func from(deviceName: String) -> SennheiserNetworkModel? {
        let upper = deviceName.uppercased()

        if upper.contains("EW-DX") {
            if upper.contains("EM 4") { return .ewdxEm4Dante }
            if upper.contains("EM 2") {
                if upper.contains("DANTE") { return .ewdxEm2Dante }
                return .ewdxEm2
            }
        }

        if upper.contains("EM 6000") || upper.contains("DIGITAL 6000") { return .em6000 }
        if upper.contains("SPECTERA") { return .specteraBaseStation }

        if upper.contains("EW IEM") && upper.contains("G4") { return .ewIemG4 }
        if upper.contains("SR IEM") && upper.contains("G4") { return .srIemG4 }
        if upper.contains("XSW IEM") || upper.contains("XS WIRELESS IEM") { return .xswIem }
        if upper.contains("2000 IEM") || upper.contains("SR 2000") || upper.contains("EK 2000") { return .iem2000 }
        if upper.contains("EK 300") && upper.contains("IEM") { return .ek300IemG3 }

        if upper.contains("G4") {
            if upper.contains("100") { return .ewG4_100 }
            if upper.contains("300") { return .ewG4_300 }
            if upper.contains("500") { return .ewG4_500 }
            return .ewG4_300
        }

        if upper.contains("G3") { return .ewG3 }

        return nil
    }
}

/// Known audio console families/models for Graph + OSC connector selection.
/// Stored as a stable identifier string in `ExternalDeviceConfig.consoleModelIdentifier`.
enum AudioConsoleModel: String, CaseIterable, Identifiable, Codable {
    case digico = "DiGiCo"

    case behringerX32 = "Behringer_X32"
    case midasM32 = "Midas_M32"

    case allenHeathDlive = "AH_dLive"
    case allenHeathAvantis = "AH_Avantis"
    case allenHeathSq = "AH_SQ"
    case allenHeathQu = "AH_Qu"

    case yamahaDm7 = "Yamaha_DM7"
    case yamahaRivage = "Yamaha_Rivage"
    case yamahaClQl = "Yamaha_CL_QL"

    case behringerWing = "Behringer_Wing"

    case avidVenueS6L = "Avid_VenueS6L"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .digico: return "DiGiCo"

        case .behringerX32: return "Behringer X32"
        case .midasM32: return "Midas M32"

        case .allenHeathDlive: return "Allen & Heath dLive"
        case .allenHeathAvantis: return "Allen & Heath Avantis"
        case .allenHeathSq: return "Allen & Heath SQ"
        case .allenHeathQu: return "Allen & Heath Qu Series"

        case .yamahaDm7: return "Yamaha DM7 / DM7 Compact"
        case .yamahaRivage: return "Yamaha RIVAGE PM"
        case .yamahaClQl: return "Yamaha CL / QL"

        case .behringerWing: return "Behringer WING"

        case .avidVenueS6L: return "Avid VENUE S6L"
        }
    }
}

extension AudioConsoleModel {
    static func from(identifier: String) -> AudioConsoleModel? {
        if let model = AudioConsoleModel(rawValue: identifier) {
            return model
        }

        // Legacy Qu-series identifiers (consolidated).
        let legacyQuIdentifiers: Set<String> = [
            "AH_Qu5", "AH_Qu6", "AH_Qu7",
            "AH_Qu5D", "AH_Qu6D", "AH_Qu7D"
        ]
        if legacyQuIdentifiers.contains(identifier) {
            return .allenHeathQu
        }

        return nil
    }

    static var betaOrDebugOnlyModels: Set<AudioConsoleModel> {
        [
            .allenHeathDlive,
            .allenHeathAvantis,
            .allenHeathSq,
            .behringerWing,
            .avidVenueS6L
        ]
    }

    static var debugOnlyModels: Set<AudioConsoleModel> {
        [
            .yamahaDm7,
            .yamahaRivage,
            .yamahaClQl
        ]
    }

    static var selectionCases: [AudioConsoleModel] {
        if RelayBuildConfig.isPreviewEnabled {
            return allCases
        }
        return allCases.filter { !betaOrDebugOnlyModels.contains($0) && !debugOnlyModels.contains($0) }
    }
}

enum ConsoleTransport: String, CaseIterable, Codable {
    case osc
    case tcp
    case midi
    case unknown
}

enum ConsoleCapabilitySupport: String, Codable {
    case supported
    case unsupported
    case unknown
}

struct ConsoleCapabilities: Hashable, Codable {
    var channelNameChange: ConsoleCapabilitySupport
    var sceneRecall: ConsoleCapabilitySupport
    var sceneStore: ConsoleCapabilitySupport
    var transports: [ConsoleTransport]

    /// Per-channel mute/level/pan via a trigger-linked "Standard Console Action".
    /// Distinct from sceneRecall/sceneStore/channelNameChange, which predate this system.
    var channelMute: ConsoleCapabilitySupport = .unsupported
    var channelLevel: ConsoleCapabilitySupport = .unsupported
    var channelPan: ConsoleCapabilitySupport = .unsupported

    /// True if this console can create or rename snapshots from rundown data.
    /// Derived from sceneStore (DiGiCo) or show-control cue support (X32/M32).
    var canManageSnapshots: Bool { sceneStore == .supported }

    static let unknown = ConsoleCapabilities(
        channelNameChange: .unknown,
        sceneRecall: .unknown,
        sceneStore: .unknown,
        transports: [.unknown]
    )
}

extension AudioConsoleModel {
    var isBeta: Bool {
        switch self {
        case .digico, .behringerX32, .midasM32:
            return false
        default:
            return true
        }
    }

    /// Capability matrix used by the app UI. This reflects current connector support.
    var capabilities: ConsoleCapabilities {
        switch self {
        case .digico:
            return ConsoleCapabilities(
                channelNameChange: .supported,
                sceneRecall: .unsupported,
                sceneStore: .supported,
                transports: [.osc, .midi]
            )

        case .behringerX32, .midasM32:
            return ConsoleCapabilities(
                channelNameChange: .supported,
                sceneRecall: .supported,
                sceneStore: .supported,
                transports: [.osc, .midi],
                channelMute: .supported,
                channelLevel: .supported,
                channelPan: .supported
            )

        case .allenHeathDlive, .allenHeathAvantis:
            return ConsoleCapabilities(
                channelNameChange: .supported,
                sceneRecall: .supported,
                sceneStore: .unsupported,
                transports: [.tcp]
            )

        case .allenHeathSq:
            return ConsoleCapabilities(
                channelNameChange: .supported,
                sceneRecall: .supported,
                sceneStore: .unsupported,
                transports: [.tcp]
            )

        case .allenHeathQu:
            return ConsoleCapabilities(
                channelNameChange: .unsupported,
                sceneRecall: .supported,
                sceneStore: .unsupported,
                transports: [.tcp, .midi]
            )

        case .yamahaDm7, .yamahaRivage:
            return ConsoleCapabilities(
                channelNameChange: .supported,
                sceneRecall: .supported,
                sceneStore: .unsupported,
                transports: [.osc, .midi],
                channelMute: .supported,
                channelLevel: .supported,
                channelPan: .supported
            )
        case .yamahaClQl:
            return ConsoleCapabilities(
                channelNameChange: .unsupported,
                sceneRecall: .supported,
                sceneStore: .unsupported,
                transports: [.midi]
            )

        case .behringerWing:
            return ConsoleCapabilities(
                channelNameChange: .unsupported,
                sceneRecall: .supported,
                sceneStore: .unsupported,
                transports: [.osc],
                channelMute: .supported,
                channelLevel: .supported,
                channelPan: .supported
            )

        case .avidVenueS6L:
            return ConsoleCapabilities(
                channelNameChange: .unsupported,
                sceneRecall: .supported,
                sceneStore: .unsupported,
                transports: [.osc],
                channelMute: .supported,
                channelLevel: .supported,
                channelPan: .supported
            )
        }
    }
}

extension ExternalDeviceConfig {
    var audioConsoleModel: AudioConsoleModel? {
        guard let modelId = consoleModelIdentifier,
              let model = AudioConsoleModel.from(identifier: modelId) else {
            return nil
        }
        return model
    }

    /// Capabilities for the configured audio console model, if known.
    var consoleCapabilities: ConsoleCapabilities {
        guard let model = audioConsoleModel else {
            return .unknown
        }
        return model.capabilities
    }

    var shureNetworkModel: ShureNetworkModel? {
        ShureNetworkModel.mostSpecific(from: [
            shureModelIdentifier,
            name,
            shureDeviceIDName,
            shureDiscoveryFCTN,
            shureDiscoveryUACN
        ])
    }

    /// Canonical Shure channel count: manual override, then the
    /// auto-detected licensed count (ANX4/ADTD/ADTQ), then the resolved
    /// model's fixed default. Falls back to raw model-string matching
    /// instead of `shureNetworkModel` so this still resolves correctly for
    /// beta-only models (ANX4/ADTD/ADTQ) even in a Release build, where
    /// `shureNetworkModel` is gated to nil.
    ///
    /// Every call site that needs a Shure device's channel count should go
    /// through this property rather than reading `shureNetworkModel?.channelCount`
    /// directly — that skips the override/detected tiers and silently caps
    /// licensed devices at the model's fixed default.
    var effectiveShureChannelCount: Int {
        if let overrideCount = shureChannelCountOverride, overrideCount > 0 {
            return overrideCount
        }
        if let detectedCount = shureDetectedChannelCount, detectedCount > 0 {
            return detectedCount
        }
        let model = (shureModelIdentifier ?? "").uppercased()
        let upperName = name.uppercased()

        // PSM 1000 transmitter (P10T) is always 2 channels.
        if model.contains("P10T") || model.contains("PSM1000") || upperName.contains("P10T") {
            return 2
        }

        // 4-channel receivers.
        if model.contains("4Q") { return 4 }           // AD4Q, ULXD4Q, etc.
        if model.contains("ANX4") || model.contains("ADTQ") { return 4 }
        if upperName.contains("MCR AD") || upperName.contains("MCR_AD") { return 4 }

        // 2-channel receivers.
        if model.contains("4D") { return 2 }           // AD4D, ULXD4D, SLXD4D, etc.
        if model.contains("ADTD") { return 2 }

        // 1-channel receivers.
        if model == "AD4" || model == "ULXD4" || model == "QLXD4" || model == "SLXD4" {
            return 1
        }

        // Safe fallback: assume 2.
        return 2
    }

    var sennheiserNetworkModel: SennheiserNetworkModel? {
        if let code = sennheiserModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty,
           let model = SennheiserNetworkModel(rawValue: code) {
            return model
        }
        return SennheiserNetworkModel.from(deviceName: name)
    }

    var shureSupportsDestinationCommands: Bool {
        shureNetworkModel?.supportsNetwork ?? false
    }

    var sennheiserSupportsDestinationCommands: Bool {
        sennheiserNetworkModel?.supportsNetwork ?? false
    }
}
/// Generic external device definition.
/// For now we keep the core fields that all network-ish devices share.
/// If you need more specific options (e.g. console type, Shure family, etc.),
/// we can add per-kind metadata later.
struct ExternalDeviceConfig: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: ExternalDeviceKind

    /// Optional audio console model identifier (e.g. DiGiCo_Q338, X32, dLive_S7000).
    /// Used by the Graph + ConsoleConnector layer to select the correct implementation.
    var consoleModelIdentifier: String? = nil

    /// Global enable toggle for this device.
    var isEnabled: Bool = true

    /// X32/M32: UDP listen port for replies/meters (default 8000 when nil).
    var consoleListenPort: UInt16? = nil

    /// Legacy parity: whether the console already has snapshots and we need to offset indices.
    var consoleExistingSnapshots: Bool = false

    /// Legacy parity: how many snapshots already exist on the console.
    var consoleExistingSnapshotCount: Int = 0

    /// Allen & Heath: submodel selector (e.g. "dlive_surface" or "dlive_mixrack").
    var consoleSubmodelIdentifier: String? = nil

    /// Allen & Heath: use TLS for MIDI-over-TCP if the console is configured for TLS-only.
    var consoleUseTLS: Bool = false

    /// Allen & Heath: TLS user profile (dLive) and password for TLS authentication.
    var consoleTLSUserProfile: UInt8? = nil
    var consoleTLSPassword: String? = nil

    /// Allen & Heath: base MIDI channel (0-15). If nil, defaults to 0x0B.
    var consoleBaseMidiChannel: UInt8? = nil

    /// Yamaha: DM7 scene bank selector (scene_a or scene_b).
    var yamahaDm7SceneBank: String = "scene_a"

    /// Yamaha: MIDI Program Change -> Scene mapping.
    var yamahaProgramChangeMappings: [YamahaProgramChangeMapping] = []

    /// Yamaha: optional MIDI input source UniqueID for scene recall feedback.
    var yamahaMidiInputSourceID: Int32? = nil

    /// Yamaha: optional MIDI destination UniqueID for scene recall (CL/QL).
    var yamahaMidiOutputDestinationID: Int32? = nil

    /// Avid VENUE S6L: transport mode for the OSC connection (TCP client or UDP unicast) —
    /// must match whichever connection slot the operator configured on the console.
    var venueTransportMode: VenueOSCTransportMode? = nil

    /// Avid VENUE S6L: OSC address templates for Standard Console Actions. `{channel}` is
    /// substituted with the 1-based channel index (mute/level/pan); `{scene}` with the
    /// trimmed scene identifier (scene recall). Empty/nil means that action silently no-ops —
    /// VENUE has no fixed address scheme, so these must match an Event configured on the
    /// console itself. See docs/superpowers/specs/2026-07-30-avid-venue-s6l-integration-design.md.
    var venueMuteAddressTemplate: String? = nil
    var venueLevelAddressTemplate: String? = nil
    var venuePanAddressTemplate: String? = nil
    var venueSceneRecallAddressTemplate: String? = nil

    // MARK: - DiGiCo: Imported Show RTF (Input Channels)

    struct DiGiCoInputChannel: Codable, Hashable, Identifiable {
        var id: Int { channel }
        let channel: Int
        let stereo: Bool
        let name: String

        /// Convenience for mapping: stereo channels represent two inputs (channel and channel+1).
        var inputs: [Int] { stereo ? [channel, channel + 1] : [channel] }
    }

    /// Known DiGiCo console models with their channel capacities.
    /// Used to pre-fill max scan counts when the user selects a model.
    enum DiGiCoConsoleModel: String, Codable, CaseIterable, Identifiable {
        case sd7          = "SD7 / SD7Q"
        case quantumSeven = "Quantum 7"
        case sd5          = "SD5 / SD5Q"
        case quantum338   = "Quantum 338 / Q338"
        case sd12_96      = "SD12 96"
        case sd12         = "SD12"
        case quantum225   = "Quantum 225"
        case sd10         = "SD10"
        case sd9          = "SD9 / SD9B"
        case sd11         = "SD11"
        case sdRack       = "SD Rack (engine only)"
        case other        = "Other"

        var id: String { rawValue }

        /// Known safe channel counts for each scan type.
        /// These reflect published DiGiCo maximums — the early-stop will trim the scan
        /// to what the console actually has, so setting a generous upper bound is safe.
        struct Capacities {
            let inputs: Int
            let auxOutputs: Int
            let groupOutputs: Int
            let matrixOutputs: Int
            let controlGroups: Int
        }

        var capacities: Capacities {
            switch self {
            case .sd7, .sd5:
                return Capacities(inputs: 256, auxOutputs: 128, groupOutputs: 48, matrixOutputs: 48, controlGroups: 24)
            case .quantumSeven:
                return Capacities(inputs: 256, auxOutputs: 128, groupOutputs: 64, matrixOutputs: 48, controlGroups: 24)
            case .quantum338:
                return Capacities(inputs: 128, auxOutputs: 48, groupOutputs: 24, matrixOutputs: 16, controlGroups: 12)
            case .sd12_96:
                return Capacities(inputs: 96, auxOutputs: 48, groupOutputs: 16, matrixOutputs: 12, controlGroups: 12)
            case .sd12:
                return Capacities(inputs: 72, auxOutputs: 36, groupOutputs: 16, matrixOutputs: 12, controlGroups: 12)
            case .sd10:
                return Capacities(inputs: 96, auxOutputs: 48, groupOutputs: 24, matrixOutputs: 16, controlGroups: 12)
            case .quantum225:
                return Capacities(inputs: 48, auxOutputs: 24, groupOutputs: 16, matrixOutputs: 12, controlGroups: 12)
            case .sd9:
                return Capacities(inputs: 48, auxOutputs: 24, groupOutputs: 16, matrixOutputs: 8, controlGroups: 12)
            case .sd11:
                return Capacities(inputs: 36, auxOutputs: 24, groupOutputs: 12, matrixOutputs: 8, controlGroups: 8)
            case .sdRack:
                return Capacities(inputs: 48, auxOutputs: 24, groupOutputs: 16, matrixOutputs: 8, controlGroups: 8)
            case .other:
                return Capacities(inputs: 256, auxOutputs: 128, groupOutputs: 128, matrixOutputs: 64, controlGroups: 64)
            }
        }

        /// Returns `digicoMaxScanCounts` dict keyed by `DiGiCoChannelType.rawValue`.
        var maxScanCounts: [String: Int] {
            let c = capacities
            return [
                "inputChannel":  c.inputs,
                "auxOutput":     c.auxOutputs,
                "groupOutput":   c.groupOutputs,
                "matrixOutput":  c.matrixOutputs,
                "controlGroup":  c.controlGroups,
            ]
        }
    }

    struct DiGiCoDiscoveredChannel: Codable, Hashable, Identifiable {
        var id: String { "\(channelType.rawValue)-\(index)" }
        let channelType: DashboardGraph.DiGiCoChannelType
        let index: Int
        let name: String
        var consoleName: String?
        var sessionFilename: String?
        var syncedAt: Date?
        var bankName: String?
        var bankSection: String?
        var bankPage: Int?
        var bankLayer: Int?
        var bankStripPosition: Int?
    }

    /// Last imported RTF filename (for display).
    var digicoRTFFileName: String? = nil

    /// Last import timestamp.
    var digicoRTFImportedAt: Date? = nil

    /// Parsed input channels from the imported DiGiCo show RTF.
    var digicoInputChannels: [DiGiCoInputChannel] = []
    /// Channel assignments for people/labels -> console input channel number.
    /// Key is a stable label (e.g. "Soprano 1 — Beth Selph").
    var consoleChannelAssignments: [String: Int] = [:]
  
    var consoleNameFormat: String = "first"

    var consoleNameCasing: String = "upper"

    // Snapshot naming preferences (Graph snapshot workflow)
    // casing: "title" | "upper"
    var consoleSnapshotNameCasing: String = "title"

    /// If enabled, apply heuristic shortening to snapshot names.
    var consoleSnapshotShortenEnabled: Bool = false

    /// Target max length for smart shortened snapshot names.
    var consoleSnapshotShortenLimit: Int = 20

    var consolePositionChannelDefaults: [String: Int] = [:]
    
    var host: String
    var port: UInt16
    var digicoReceivePort: UInt16? = nil
    var digicoDiscoveredChannels: [DiGiCoDiscoveredChannel] = []
    var digicoOSCSyncedAt: Date? = nil
    var digicoOSCConsoleName: String? = nil
    var digicoOSCSessionFilename: String? = nil
    var digicoLocalListenPort: UInt16? = nil
    var digicoMaxScanCounts: [String: Int] = [:]
    var digicoConsoleModel: DiGiCoConsoleModel? = nil

    var shureModelIdentifier: String? = nil
    var sennheiserModelIdentifier: String? = nil
    var vistaConsoleTarget: String? = nil
    /// Optional notes / label.
    var notes: String?

    /// Cached Shure channel names discovered from the network.
    /// Keyed by channel index (1-based).
    var shureChannelNames: [Int: String] = [:]

    /// Optional manual channel count override (used for licensed/virtual channel devices like ANX4 / ADTD / ADTQ).
    var shureChannelCountOverride: Int? = nil
    /// Channel count auto-detected from the device's licensed-channel command string
    /// (ANX4 / ADTD / ADTQ only). Used when no manual override is set.
    var shureDetectedChannelCount: Int? = nil
    /// ANX4 mode (Axient or ULX-D), which affects the max channel count.
    var shureAnx4Mode: ShureAnx4Mode? = nil

    /// Timestamp for the last successful channel sync/refresh for this device.
    var lastChannelSyncAt: Date? = nil

    /// Optional Shure device ID name (from SLP acn-uacn or device handshake).
    var shureDeviceIDName: String? = nil

    /// Shure SLP discovery: controller CID and descriptive fields (optional).
    var shureDiscoveryCID: UUID? = nil
    var shureDiscoveryUACN: String? = nil
    var shureDiscoveryFCTN: String? = nil
    var shureTransportMode: ShureTransportMode? = nil
    var shureSdtHost: String? = nil
    var shureSdtPort: UInt16? = nil

    /// PSM 1000 / P10T session port used for UDP label bootstrap (ephemeral).
    /// Optional because it is not discoverable via SLP and may change.
    var psmSessionPort: UInt16? = nil
    /// PSM 1000 / P10T session host (esta.sdt), if advertised via SLP.
    var psmSessionHost: String? = nil

    /// Optional DDL URL from SLP discovery (device-description).
    var shureDiscoveryDDLURL: String? = nil

    /// Optional manual channel names for PSM1000 (P10T) two‑channel units.
    /// These override live channel names because PSM transmitters do not report CHAN_NAME over the protocol.
    var psmChannel1Name: String? = nil
    var psmChannel2Name: String? = nil

    // MARK: - Codable (backwards compatible)

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case consoleModelIdentifier
        case isEnabled
        case consoleListenPort
        case consoleExistingSnapshots
        case consoleExistingSnapshotCount
        case consoleSubmodelIdentifier
        case consoleUseTLS
        case consoleTLSUserProfile
        case consoleTLSPassword
        case consoleBaseMidiChannel
        case yamahaDm7SceneBank
        case yamahaProgramChangeMappings
        case yamahaMidiInputSourceID
        case yamahaMidiOutputDestinationID
        case digicoRTFFileName
        case digicoRTFImportedAt
        case digicoInputChannels
        case consoleChannelAssignments
        case consoleNameFormat
        case consoleNameCasing
        case consoleSnapshotNameCasing
        case consoleSnapshotShortenEnabled
        case consoleSnapshotShortenLimit
        case consolePositionChannelDefaults
        case host
        case port
        case digicoReceivePort
        case digicoDiscoveredChannels
        case digicoOSCSyncedAt
        case digicoOSCConsoleName
        case digicoOSCSessionFilename
        case digicoLocalListenPort
        case digicoMaxScanCounts
        case digicoConsoleModel
        case shureModelIdentifier
        case sennheiserModelIdentifier
        case vistaConsoleTarget
        case psmSessionPort
        case psmSessionHost
        case notes
        case shureChannelNames
        case shureChannelCountOverride
        case shureDetectedChannelCount
        case shureAnx4Mode
        case lastChannelSyncAt
        case shureDeviceIDName
        case shureDiscoveryCID
        case shureDiscoveryUACN
        case shureDiscoveryFCTN
        case shureTransportMode
        case shureSdtHost
        case shureSdtPort
        case shureDiscoveryDDLURL
        case psmChannel1Name
        case psmChannel2Name
        case venueTransportMode
        case venueMuteAddressTemplate
        case venueLevelAddressTemplate
        case venuePanAddressTemplate
        case venueSceneRecallAddressTemplate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Core fields
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.kind = try c.decode(ExternalDeviceKind.self, forKey: .kind)
        self.host = try c.decode(String.self, forKey: .host)
        self.port = try c.decode(UInt16.self, forKey: .port)

        // Newer / optional fields (use decodeIfPresent + defaults for backwards compatibility)
        self.consoleModelIdentifier = try c.decodeIfPresent(String.self, forKey: .consoleModelIdentifier)
        if let modelId = self.consoleModelIdentifier {
            let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("DiGiCo_") {
                self.consoleModelIdentifier = AudioConsoleModel.digico.rawValue
            }
        }

        // ✅ Critical fix: older files may not have this key
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        self.consoleListenPort = try c.decodeIfPresent(UInt16.self, forKey: .consoleListenPort)
        self.consoleExistingSnapshots = try c.decodeIfPresent(Bool.self, forKey: .consoleExistingSnapshots) ?? false
        self.consoleExistingSnapshotCount = try c.decodeIfPresent(Int.self, forKey: .consoleExistingSnapshotCount) ?? 0
        self.consoleSubmodelIdentifier = try c.decodeIfPresent(String.self, forKey: .consoleSubmodelIdentifier)
        self.consoleUseTLS = try c.decodeIfPresent(Bool.self, forKey: .consoleUseTLS) ?? false
        self.consoleTLSUserProfile = try c.decodeIfPresent(UInt8.self, forKey: .consoleTLSUserProfile)
        self.consoleTLSPassword = try c.decodeIfPresent(String.self, forKey: .consoleTLSPassword)
        self.consoleBaseMidiChannel = try c.decodeIfPresent(UInt8.self, forKey: .consoleBaseMidiChannel)

        self.yamahaDm7SceneBank = try c.decodeIfPresent(String.self, forKey: .yamahaDm7SceneBank) ?? "scene_a"
        self.yamahaProgramChangeMappings = try c.decodeIfPresent([YamahaProgramChangeMapping].self, forKey: .yamahaProgramChangeMappings) ?? []
        self.yamahaMidiInputSourceID = try c.decodeIfPresent(Int32.self, forKey: .yamahaMidiInputSourceID)
        self.yamahaMidiOutputDestinationID = try c.decodeIfPresent(Int32.self, forKey: .yamahaMidiOutputDestinationID)

        self.digicoRTFFileName = try c.decodeIfPresent(String.self, forKey: .digicoRTFFileName)
        self.digicoRTFImportedAt = try c.decodeIfPresent(Date.self, forKey: .digicoRTFImportedAt)
        self.digicoInputChannels = try c.decodeIfPresent([DiGiCoInputChannel].self, forKey: .digicoInputChannels) ?? []

        self.consoleChannelAssignments = try c.decodeIfPresent([String: Int].self, forKey: .consoleChannelAssignments) ?? [:]
        self.consoleNameFormat = try c.decodeIfPresent(String.self, forKey: .consoleNameFormat) ?? "first"
        self.consoleNameCasing = try c.decodeIfPresent(String.self, forKey: .consoleNameCasing) ?? "upper"
        self.consoleSnapshotNameCasing = try c.decodeIfPresent(String.self, forKey: .consoleSnapshotNameCasing) ?? "title"
        self.consoleSnapshotShortenEnabled = try c.decodeIfPresent(Bool.self, forKey: .consoleSnapshotShortenEnabled) ?? false
        self.consoleSnapshotShortenLimit = try c.decodeIfPresent(Int.self, forKey: .consoleSnapshotShortenLimit) ?? 20
        self.consolePositionChannelDefaults = try c.decodeIfPresent([String: Int].self, forKey: .consolePositionChannelDefaults) ?? [:]

        self.shureModelIdentifier = try c.decodeIfPresent(String.self, forKey: .shureModelIdentifier)
        self.sennheiserModelIdentifier = try c.decodeIfPresent(String.self, forKey: .sennheiserModelIdentifier)
        self.vistaConsoleTarget = try c.decodeIfPresent(String.self, forKey: .vistaConsoleTarget)
        self.psmSessionPort = try c.decodeIfPresent(UInt16.self, forKey: .psmSessionPort)
        self.psmSessionHost = try c.decodeIfPresent(String.self, forKey: .psmSessionHost)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.shureChannelNames = try c.decodeIfPresent([Int: String].self, forKey: .shureChannelNames) ?? [:]
        self.shureChannelCountOverride = try c.decodeIfPresent(Int.self, forKey: .shureChannelCountOverride)
        self.shureDetectedChannelCount = try c.decodeIfPresent(Int.self, forKey: .shureDetectedChannelCount)
        self.shureAnx4Mode = try c.decodeIfPresent(ShureAnx4Mode.self, forKey: .shureAnx4Mode)
        self.lastChannelSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastChannelSyncAt)
        self.shureDeviceIDName = try c.decodeIfPresent(String.self, forKey: .shureDeviceIDName)
        self.shureDiscoveryCID = try c.decodeIfPresent(UUID.self, forKey: .shureDiscoveryCID)
        self.shureDiscoveryUACN = try c.decodeIfPresent(String.self, forKey: .shureDiscoveryUACN)
        self.shureDiscoveryFCTN = try c.decodeIfPresent(String.self, forKey: .shureDiscoveryFCTN)
        self.shureTransportMode = try c.decodeIfPresent(ShureTransportMode.self, forKey: .shureTransportMode)
        self.shureSdtHost = try c.decodeIfPresent(String.self, forKey: .shureSdtHost)
        self.shureSdtPort = try c.decodeIfPresent(UInt16.self, forKey: .shureSdtPort)
        self.shureDiscoveryDDLURL = try c.decodeIfPresent(String.self, forKey: .shureDiscoveryDDLURL)

        self.psmChannel1Name = try c.decodeIfPresent(String.self, forKey: .psmChannel1Name)
        self.psmChannel2Name = try c.decodeIfPresent(String.self, forKey: .psmChannel2Name)
        self.digicoReceivePort = try c.decodeIfPresent(UInt16.self, forKey: .digicoReceivePort)
        self.digicoDiscoveredChannels = try c.decodeIfPresent([DiGiCoDiscoveredChannel].self, forKey: .digicoDiscoveredChannels) ?? []
        self.digicoOSCSyncedAt = try c.decodeIfPresent(Date.self, forKey: .digicoOSCSyncedAt)
        self.digicoOSCConsoleName = try c.decodeIfPresent(String.self, forKey: .digicoOSCConsoleName)
        self.digicoOSCSessionFilename = try c.decodeIfPresent(String.self, forKey: .digicoOSCSessionFilename)
        self.digicoLocalListenPort = try c.decodeIfPresent(UInt16.self, forKey: .digicoLocalListenPort)
        self.digicoMaxScanCounts = try c.decodeIfPresent([String: Int].self, forKey: .digicoMaxScanCounts) ?? [:]
        self.digicoConsoleModel = try c.decodeIfPresent(DiGiCoConsoleModel.self, forKey: .digicoConsoleModel)
        self.venueTransportMode = try c.decodeIfPresent(VenueOSCTransportMode.self, forKey: .venueTransportMode)
        self.venueMuteAddressTemplate = try c.decodeIfPresent(String.self, forKey: .venueMuteAddressTemplate)
        self.venueLevelAddressTemplate = try c.decodeIfPresent(String.self, forKey: .venueLevelAddressTemplate)
        self.venuePanAddressTemplate = try c.decodeIfPresent(String.self, forKey: .venuePanAddressTemplate)
        self.venueSceneRecallAddressTemplate = try c.decodeIfPresent(String.self, forKey: .venueSceneRecallAddressTemplate)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(consoleModelIdentifier, forKey: .consoleModelIdentifier)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encodeIfPresent(consoleListenPort, forKey: .consoleListenPort)
        try c.encode(consoleExistingSnapshots, forKey: .consoleExistingSnapshots)
        try c.encode(consoleExistingSnapshotCount, forKey: .consoleExistingSnapshotCount)
        try c.encodeIfPresent(consoleSubmodelIdentifier, forKey: .consoleSubmodelIdentifier)
        try c.encode(consoleUseTLS, forKey: .consoleUseTLS)
        try c.encodeIfPresent(consoleTLSUserProfile, forKey: .consoleTLSUserProfile)
        try c.encodeIfPresent(consoleTLSPassword, forKey: .consoleTLSPassword)
        try c.encodeIfPresent(consoleBaseMidiChannel, forKey: .consoleBaseMidiChannel)
        try c.encode(yamahaDm7SceneBank, forKey: .yamahaDm7SceneBank)
        try c.encode(yamahaProgramChangeMappings, forKey: .yamahaProgramChangeMappings)
        try c.encodeIfPresent(yamahaMidiInputSourceID, forKey: .yamahaMidiInputSourceID)
        try c.encodeIfPresent(yamahaMidiOutputDestinationID, forKey: .yamahaMidiOutputDestinationID)
        try c.encodeIfPresent(digicoRTFFileName, forKey: .digicoRTFFileName)
        try c.encodeIfPresent(digicoRTFImportedAt, forKey: .digicoRTFImportedAt)
        try c.encode(digicoInputChannels, forKey: .digicoInputChannels)
        try c.encode(consoleChannelAssignments, forKey: .consoleChannelAssignments)
        try c.encode(consoleNameFormat, forKey: .consoleNameFormat)
        try c.encode(consoleNameCasing, forKey: .consoleNameCasing)
        try c.encode(consoleSnapshotNameCasing, forKey: .consoleSnapshotNameCasing)
        try c.encode(consoleSnapshotShortenEnabled, forKey: .consoleSnapshotShortenEnabled)
        try c.encode(consoleSnapshotShortenLimit, forKey: .consoleSnapshotShortenLimit)
        try c.encode(consolePositionChannelDefaults, forKey: .consolePositionChannelDefaults)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encodeIfPresent(shureModelIdentifier, forKey: .shureModelIdentifier)
        try c.encodeIfPresent(sennheiserModelIdentifier, forKey: .sennheiserModelIdentifier)
        try c.encodeIfPresent(vistaConsoleTarget, forKey: .vistaConsoleTarget)
        try c.encodeIfPresent(psmSessionPort, forKey: .psmSessionPort)
        try c.encodeIfPresent(psmSessionHost, forKey: .psmSessionHost)
        try c.encodeIfPresent(notes, forKey: .notes)
        if !shureChannelNames.isEmpty {
            try c.encode(shureChannelNames, forKey: .shureChannelNames)
        }
        try c.encodeIfPresent(shureChannelCountOverride, forKey: .shureChannelCountOverride)
        try c.encodeIfPresent(shureDetectedChannelCount, forKey: .shureDetectedChannelCount)
        try c.encodeIfPresent(shureAnx4Mode, forKey: .shureAnx4Mode)
        try c.encodeIfPresent(lastChannelSyncAt, forKey: .lastChannelSyncAt)
        try c.encodeIfPresent(shureDeviceIDName, forKey: .shureDeviceIDName)
        try c.encodeIfPresent(shureDiscoveryCID, forKey: .shureDiscoveryCID)
        try c.encodeIfPresent(shureDiscoveryUACN, forKey: .shureDiscoveryUACN)
        try c.encodeIfPresent(shureDiscoveryFCTN, forKey: .shureDiscoveryFCTN)
        try c.encodeIfPresent(shureTransportMode, forKey: .shureTransportMode)
        try c.encodeIfPresent(shureSdtHost, forKey: .shureSdtHost)
        try c.encodeIfPresent(shureSdtPort, forKey: .shureSdtPort)
        try c.encodeIfPresent(shureDiscoveryDDLURL, forKey: .shureDiscoveryDDLURL)
        try c.encodeIfPresent(psmChannel1Name, forKey: .psmChannel1Name)
        try c.encodeIfPresent(psmChannel2Name, forKey: .psmChannel2Name)
        try c.encodeIfPresent(digicoReceivePort, forKey: .digicoReceivePort)
        if !digicoDiscoveredChannels.isEmpty {
            try c.encode(digicoDiscoveredChannels, forKey: .digicoDiscoveredChannels)
        }
        try c.encodeIfPresent(digicoOSCSyncedAt, forKey: .digicoOSCSyncedAt)
        try c.encodeIfPresent(digicoOSCConsoleName, forKey: .digicoOSCConsoleName)
        try c.encodeIfPresent(digicoOSCSessionFilename, forKey: .digicoOSCSessionFilename)
        try c.encodeIfPresent(digicoLocalListenPort, forKey: .digicoLocalListenPort)
        if !digicoMaxScanCounts.isEmpty {
            try c.encode(digicoMaxScanCounts, forKey: .digicoMaxScanCounts)
        }
        try c.encodeIfPresent(digicoConsoleModel, forKey: .digicoConsoleModel)
        try c.encodeIfPresent(venueTransportMode, forKey: .venueTransportMode)
        try c.encodeIfPresent(venueMuteAddressTemplate, forKey: .venueMuteAddressTemplate)
        try c.encodeIfPresent(venueLevelAddressTemplate, forKey: .venueLevelAddressTemplate)
        try c.encodeIfPresent(venuePanAddressTemplate, forKey: .venuePanAddressTemplate)
        try c.encodeIfPresent(venueSceneRecallAddressTemplate, forKey: .venueSceneRecallAddressTemplate)
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: ExternalDeviceKind,
        host: String,
        port: UInt16,
        consoleModelIdentifier: String? = nil,
        digicoRTFFileName: String? = nil,
        digicoRTFImportedAt: Date? = nil,
        digicoInputChannels: [DiGiCoInputChannel] = [],
        digicoReceivePort: UInt16? = nil,
        isEnabled: Bool = true,
        consoleListenPort: UInt16? = nil,
        consoleExistingSnapshots: Bool = false,
        consoleExistingSnapshotCount: Int = 0,
        consoleSubmodelIdentifier: String? = nil,
        consoleUseTLS: Bool = false,
        consoleTLSUserProfile: UInt8? = nil,
        consoleTLSPassword: String? = nil,
        consoleBaseMidiChannel: UInt8? = nil,
        yamahaDm7SceneBank: String = "scene_a",
        yamahaProgramChangeMappings: [YamahaProgramChangeMapping] = [],
        yamahaMidiInputSourceID: Int32? = nil,
        yamahaMidiOutputDestinationID: Int32? = nil,
        consoleChannelAssignments: [String: Int] = [:],
        consoleNameFormat: String = "first",
        consoleNameCasing: String = "upper",
        consoleSnapshotNameCasing: String = "title",
        consoleSnapshotShortenEnabled: Bool = false,
        consoleSnapshotShortenLimit: Int = 20,
        consolePositionChannelDefaults: [String: Int] = [:],
        shureModelIdentifier: String? = nil,
        sennheiserModelIdentifier: String? = nil,
        vistaConsoleTarget: String? = nil,
        notes: String? = nil,
        shureChannelNames: [Int: String] = [:],
        shureChannelCountOverride: Int? = nil,
        shureDetectedChannelCount: Int? = nil,
        shureAnx4Mode: ShureAnx4Mode? = nil,
        lastChannelSyncAt: Date? = nil,
        shureDeviceIDName: String? = nil,
        psmSessionPort: UInt16? = nil,
        psmSessionHost: String? = nil,
        shureDiscoveryCID: UUID? = nil,
        shureDiscoveryUACN: String? = nil,
        shureDiscoveryFCTN: String? = nil,
        shureTransportMode: ShureTransportMode? = nil,
        shureSdtHost: String? = nil,
        shureSdtPort: UInt16? = nil,
        shureDiscoveryDDLURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.consoleModelIdentifier = consoleModelIdentifier
        self.digicoRTFFileName = digicoRTFFileName
        self.digicoRTFImportedAt = digicoRTFImportedAt
        self.digicoInputChannels = digicoInputChannels
        self.digicoReceivePort = digicoReceivePort
        self.isEnabled = isEnabled
        self.consoleListenPort = consoleListenPort
        self.consoleExistingSnapshots = consoleExistingSnapshots
        self.consoleExistingSnapshotCount = consoleExistingSnapshotCount
        self.consoleSubmodelIdentifier = consoleSubmodelIdentifier
        self.consoleUseTLS = consoleUseTLS
        self.consoleTLSUserProfile = consoleTLSUserProfile
        self.consoleTLSPassword = consoleTLSPassword
        self.consoleBaseMidiChannel = consoleBaseMidiChannel
        self.yamahaDm7SceneBank = yamahaDm7SceneBank
        self.yamahaProgramChangeMappings = yamahaProgramChangeMappings
        self.yamahaMidiInputSourceID = yamahaMidiInputSourceID
        self.yamahaMidiOutputDestinationID = yamahaMidiOutputDestinationID
        self.consoleChannelAssignments = consoleChannelAssignments
        self.consoleNameFormat = consoleNameFormat
        self.consoleNameCasing = consoleNameCasing
        self.consoleSnapshotNameCasing = consoleSnapshotNameCasing
        self.consoleSnapshotShortenEnabled = consoleSnapshotShortenEnabled
        self.consoleSnapshotShortenLimit = consoleSnapshotShortenLimit
        self.consolePositionChannelDefaults = consolePositionChannelDefaults
        self.shureModelIdentifier = shureModelIdentifier
        self.sennheiserModelIdentifier = sennheiserModelIdentifier
        self.vistaConsoleTarget = vistaConsoleTarget
        self.notes = notes
        self.shureChannelNames = shureChannelNames
        self.shureChannelCountOverride = shureChannelCountOverride
        self.shureDetectedChannelCount = shureDetectedChannelCount
        self.shureAnx4Mode = shureAnx4Mode
        self.lastChannelSyncAt = lastChannelSyncAt
        self.shureDeviceIDName = shureDeviceIDName
        self.psmSessionPort = psmSessionPort
        self.psmSessionHost = psmSessionHost
        self.shureDiscoveryCID = shureDiscoveryCID
        self.shureDiscoveryUACN = shureDiscoveryUACN
        self.shureDiscoveryFCTN = shureDiscoveryFCTN
        self.shureTransportMode = shureTransportMode
        self.shureSdtHost = shureSdtHost
        self.shureSdtPort = shureSdtPort
        self.shureDiscoveryDDLURL = shureDiscoveryDDLURL
    }
}

extension ExternalDeviceConfig {
    var isNameRefreshTarget: Bool {
        switch kind {
        case .shureWireless:
            return true
        case .audioConsole:
            guard isEnabled else { return false }
            switch audioConsoleModel {
            case .behringerX32, .midasM32, .allenHeathDlive, .allenHeathAvantis, .allenHeathSq:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    var nameRefreshTargetLabel: String {
        switch kind {
        case .audioConsole:
            return "Console • \(name)"
        case .shureWireless:
            return "Shure • \(name)"
        case .sennheiserWireless:
            return "Sennheiser • \(name)"
        default:
            return name
        }
    }
}

@MainActor
final class ExternalDevicesStore: ObservableObject {
    static let shared = ExternalDevicesStore()

    @Published var devices: [ExternalDeviceConfig] = [] {
        didSet { persist() }
    }
    @Published var shureSelectedChannel: ShureSelectedChannel? = nil

    // MARK: - Shure channel-name cache (for dropdown labels)

    /// Channel names discovered from Shure devices. Keyed by deviceID -> channelIndex -> name.
    /// This is intentionally lightweight and persisted only in memory.
    @Published private(set) var shureChannelNameCache: [UUID: [Int: String]] = [:]

    /// Used to throttle automatic name refresh so settings doesn't spam the network.
    private var lastShureNameRefreshAt: Date? = nil

    /// True when at least one Shure Wireless module is present on any dashboard tab.
    @Published private(set) var hasActiveShureModule: Bool = false

    // MARK: - Sennheiser channel-name cache (for dropdown labels)

    /// Channel names discovered from Sennheiser devices. Keyed by deviceID -> channelIndex -> name.
    /// Lightweight and persisted only in memory.
    @Published private(set) var sennheiserChannelNameCache: [UUID: [Int: String]] = [:]

    /// Store a channel name discovered from the Shure protocol.
    func cacheShureChannelName(deviceID: UUID, channelIndex: Int, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateShureChannelName(deviceID: deviceID, channelIndex: channelIndex, name: cleaned)
        var perDevice = shureChannelNameCache[deviceID] ?? [:]
        if perDevice[channelIndex] == cleaned { return }
        perDevice[channelIndex] = cleaned
        shureChannelNameCache[deviceID] = perDevice
    }

    /// Lookup a cached channel name if available.
    func cachedShureChannelName(deviceID: UUID, channelIndex: Int) -> String? {
        shureChannelNameCache[deviceID]?[channelIndex]
    }

    /// For the settings dropdown: prefer (1) PSM manual names, then (2) cached CHAN_NAME, then (3) fallback.
    func shureChannelDisplayLabel(device: ExternalDeviceConfig, channelIndex: Int) -> String {
        let model = (device.shureModelIdentifier ?? "").uppercased()
        let upperName = device.name.uppercased()
        let isP10T = (model == "P10T") || upperName.contains("P10T")
        let isPSM900 = model.contains("PSM900") || upperName.contains("PSM 900") || upperName.contains("PSM900")

        if isP10T || isPSM900 {
            if channelIndex == 1, let n = device.psmChannel1Name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(n) — \(device.name) — CH \(channelIndex)"
            }
            if channelIndex == 2, let n = device.psmChannel2Name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(n) — \(device.name) — CH \(channelIndex)"
            }
        }

        if let cached = cachedShureChannelName(deviceID: device.id, channelIndex: channelIndex) {
            return "\(cached) — \(device.name) — CH \(channelIndex)"
        }

        if let stored = device.shureChannelNames[channelIndex], !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(stored) — \(device.name) — CH \(channelIndex)"
        }

        return "\(device.name) — CH \(channelIndex)"
    }

    /// Store a channel name discovered from a Sennheiser network API.
    func cacheSennheiserChannelName(deviceID: UUID, channelIndex: Int, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var perDevice = sennheiserChannelNameCache[deviceID] ?? [:]
        if perDevice[channelIndex] == cleaned { return }
        perDevice[channelIndex] = cleaned
        sennheiserChannelNameCache[deviceID] = perDevice
    }

    /// Lookup a cached Sennheiser channel name if available.
    func cachedSennheiserChannelName(deviceID: UUID, channelIndex: Int) -> String? {
        sennheiserChannelNameCache[deviceID]?[channelIndex]
    }

    /// For dropdown labels: prefer cached name, else fallback.
    func sennheiserChannelDisplayLabel(device: ExternalDeviceConfig, channelIndex: Int) -> String {
        if let cached = cachedSennheiserChannelName(deviceID: device.id, channelIndex: channelIndex) {
            return "\(cached) — \(device.name) — CH \(channelIndex)"
        }
        return "\(device.name) — CH \(channelIndex)"
    }

    /// Update whether any Shure module is active on the dashboard.
    func setShureModuleActive(_ isActive: Bool) {
        if hasActiveShureModule == isActive { return }
        hasActiveShureModule = isActive
    }

    /// One-shot refresh hook for Shure channel names (throttled).
    /// Call this when a Shure module is added / its settings inspector appears.
    func requestShureNameRefreshIfNeeded(throttleSeconds: TimeInterval = 45) {
        guard hasActiveShureModule else { return }
        let now = Date()
        if let last = lastShureNameRefreshAt, now.timeIntervalSince(last) < throttleSeconds {
            return
        }
        lastShureNameRefreshAt = now

        // The actual network fetch lives in ShureWirelessService; this store just provides the UX hook.
        ShureWirelessService.refreshChannelNamesIfNeeded(throttleSeconds: throttleSeconds)
    }

    /// Manual refresh for all Shure devices (unthrottled).
    func refreshShureChannelNames() {
        let devicesSnapshot = devices.filter { $0.kind == .shureWireless }
        guard !devicesSnapshot.isEmpty else { return }
        Task.detached(priority: .utility) {
            for device in devicesSnapshot {
                await MainActor.run { [weak self] in
                    self?.updateDevice(id: device.id) { device in
                        device.lastChannelSyncAt = Date()
                    }
                    ShureWirelessService.refreshChannelNames(for: device)
                    ShureWirelessService.refreshDeviceIDName(for: device)
                }
            }
        }
    }

    /// Manual refresh for a single Shure device (unthrottled).
    func refreshShureChannelNames(for device: ExternalDeviceConfig) {
        Task.detached(priority: .utility) {
            await MainActor.run { [weak self] in
                self?.updateDevice(id: device.id) { device in
                    device.lastChannelSyncAt = Date()
                }
                ShureWirelessService.refreshChannelNames(for: device)
                ShureWirelessService.refreshDeviceIDName(for: device)
            }
        }
    }

    /// Manual refresh for a single Shure device ID name (unthrottled).
    func refreshShureDeviceIDName(for device: ExternalDeviceConfig) {
        Task.detached(priority: .utility) {
            await MainActor.run {
                ShureWirelessService.refreshDeviceIDName(for: device)
            }
        }
    }

    /// Manual refresh for a single Shure device's auto-detected licensed
    /// channel count (unthrottled).
    func refreshShureDetectedChannelCount(for device: ExternalDeviceConfig) {
        Task.detached(priority: .utility) {
            await MainActor.run {
                ShureWirelessService.refreshLicensedChannelCount(for: device)
            }
        }
    }

    /// Persist an auto-detected licensed channel count onto the device itself.
    /// Ignored if the user has already set a manual override.
    func updateShureDetectedChannelCount(deviceID: UUID, count: Int) {
        guard count > 0 else { return }
        updateDevice(id: deviceID) { device in
            guard device.shureChannelCountOverride == nil else { return }
            guard device.shureDetectedChannelCount != count else { return }
            device.shureDetectedChannelCount = count
        }
    }

    /// Persist a discovered channel name onto the device itself.
    func updateShureChannelName(deviceID: UUID, channelIndex: Int, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateDevice(id: deviceID) { device in
            if device.shureChannelNames[channelIndex] == cleaned { return }
            device.shureChannelNames[channelIndex] = cleaned
        }
    }

    /// Persist a discovered Shure device ID name onto the device itself.
    func updateShureDeviceIDName(deviceID: UUID, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateDevice(id: deviceID) { device in
            let previousDeviceIDName = device.shureDeviceIDName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentDisplayName = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let isUdpOnlyShureDevice: Bool = {
                switch device.shureNetworkModel {
                case .anx4, .adtd, .adtq:
                    return true
                default:
                    return false
                }
            }()
            let preferredUdpDisplayName: String? = {
                let modelCode = device.shureModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !modelCode.isEmpty { return modelCode }
                let fctn = device.shureDiscoveryFCTN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !fctn.isEmpty { return fctn }
                let uacn = device.shureDiscoveryUACN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !uacn.isEmpty { return uacn }
                return nil
            }()
            let shouldNormalizeUdpDisplayName = isUdpOnlyShureDevice && (
                currentDisplayName.isEmpty
                    || currentDisplayName.caseInsensitiveCompare(cleaned) == .orderedSame
                    || (previousDeviceIDName?.caseInsensitiveCompare(currentDisplayName) == .orderedSame)
            )

            if device.shureDeviceIDName == cleaned && !shouldNormalizeUdpDisplayName { return }
            device.shureDeviceIDName = cleaned
            if device.kind == .shureWireless, isUdpOnlyShureDevice {
                if shouldNormalizeUdpDisplayName, let preferredUdpDisplayName {
                    device.name = preferredUdpDisplayName
                }
            } else if device.kind == .shureWireless {
                device.name = cleaned
            }
        }
    }

    struct Snapshot: Codable {
        var devices: [ExternalDeviceConfig]
        var shureSelectedChannel: ShureSelectedChannel?

        private enum CodingKeys: String, CodingKey {
            case devices
            case shureSelectedChannel
        }

        init(devices: [ExternalDeviceConfig], shureSelectedChannel: ShureSelectedChannel?) {
            self.devices = devices
            self.shureSelectedChannel = shureSelectedChannel
        }

        init(from decoder: Decoder) throws {
            // Preferred (new) format: keyed object
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
                self.devices = try keyed.decodeIfPresent([ExternalDeviceConfig].self, forKey: .devices) ?? []
                self.shureSelectedChannel = try keyed.decodeIfPresent(ShureSelectedChannel.self, forKey: .shureSelectedChannel)
                return
            }

            // Legacy format: snapshot was stored as a raw array of devices
            let single = try decoder.singleValueContainer()
            self.devices = try single.decode([ExternalDeviceConfig].self)
            self.shureSelectedChannel = nil
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(devices, forKey: .devices)
            try c.encodeIfPresent(shureSelectedChannel, forKey: .shureSelectedChannel)
        }
    }

    /// Explicitly save the current external device configuration to persistent storage.
    /// This can be called from higher-level "Save" flows to keep things in sync.
    func savePersistentState() {
        persist()
    }

    /// Capture a snapshot of the current external device configuration for embedding
    /// into a dashboard or show file.
    func currentSnapshot() -> Snapshot {
        Snapshot(
            devices: devices,
            shureSelectedChannel: shureSelectedChannel
        )
    }

    /// Apply a previously captured snapshot (e.g. from a dashboard or show file)
    /// to restore external device configuration.
    func applySnapshot(_ snapshot: Snapshot) {
        devices = snapshot.devices
        shureSelectedChannel = snapshot.shureSelectedChannel
    }
    /// Merge a snapshot into the current configuration.
    /// - Keeps existing devices.
    /// - Adds new devices that don't match an existing device.
    /// - Updates matching devices' metadata while preserving the existing UUID.
    ///
    /// Matching strategy: same `kind` + `host` + `port` (stable across Mac/iPad).
    func mergeSnapshot(_ snapshot: Snapshot) {
        func key(for d: ExternalDeviceConfig) -> String {
            let host = d.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !host.isEmpty {
                if d.kind == .shureWireless {
                    if d.port != 0 {
                        return "\(d.kind.rawValue)|\(host)|\(d.port)"
                    }
                    return "\(d.kind.rawValue)|\(host)"
                }
                if d.port != 0 {
                    return "\(d.kind.rawValue)|\(host)|\(d.port)"
                }
            }

            let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !name.isEmpty {
                let model = (d.consoleModelIdentifier ?? d.shureModelIdentifier ?? d.sennheiserModelIdentifier ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return "\(d.kind.rawValue)|name:\(name)|model:\(model)"
            }

            return "\(d.kind.rawValue)|id:\(d.id.uuidString.lowercased())"
        }

        // Index current devices by stable key
        var currentByKey: [String: Int] = [:]
        for (idx, d) in devices.enumerated() {
            currentByKey[key(for: d)] = idx
        }

        // Merge devices
        for incoming in snapshot.devices {
            let k = key(for: incoming)

            if let existingIndex = currentByKey[k] {
                // Update metadata but keep existing UUID
                var updated = devices[existingIndex]
                updated.name = incoming.name
                updated.notes = incoming.notes
                if let model = incoming.shureModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !model.isEmpty {
                    updated.shureModelIdentifier = model
                }
                if let overrideCount = incoming.shureChannelCountOverride, overrideCount > 0 {
                    updated.shureChannelCountOverride = overrideCount
                }
                if let mode = incoming.shureAnx4Mode {
                    updated.shureAnx4Mode = mode
                }
                if let model = incoming.sennheiserModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !model.isEmpty {
                    updated.sennheiserModelIdentifier = model
                }
                if let deviceName = incoming.shureDeviceIDName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !deviceName.isEmpty {
                    updated.shureDeviceIDName = deviceName
                }
                if let port = incoming.psmSessionPort {
                    updated.psmSessionPort = port
                }
                if let host = incoming.psmSessionHost?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !host.isEmpty {
                    updated.psmSessionHost = host
                }
                if let name = incoming.psmChannel1Name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    updated.psmChannel1Name = name
                }
                if let name = incoming.psmChannel2Name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    updated.psmChannel2Name = name
                }
                if let cid = incoming.shureDiscoveryCID {
                    updated.shureDiscoveryCID = cid
                }
                if let uacn = incoming.shureDiscoveryUACN?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !uacn.isEmpty {
                    updated.shureDiscoveryUACN = uacn
                }
                if let fctn = incoming.shureDiscoveryFCTN?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !fctn.isEmpty {
                    updated.shureDiscoveryFCTN = fctn
                }
                if let sdtHost = incoming.shureSdtHost?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !sdtHost.isEmpty {
                    updated.shureSdtHost = sdtHost
                }
                if let sdtPort = incoming.shureSdtPort {
                    updated.shureSdtPort = sdtPort
                }
                if let ddl = incoming.shureDiscoveryDDLURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !ddl.isEmpty {
                    updated.shureDiscoveryDDLURL = ddl
                }
                if let consoleModel = incoming.consoleModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !consoleModel.isEmpty {
                    updated.consoleModelIdentifier = consoleModel
                }
                updated.isEnabled = incoming.isEnabled
                updated.consoleListenPort = incoming.consoleListenPort
                updated.consoleExistingSnapshots = incoming.consoleExistingSnapshots
                updated.consoleExistingSnapshotCount = incoming.consoleExistingSnapshotCount
                updated.consoleSubmodelIdentifier = incoming.consoleSubmodelIdentifier
                updated.consoleUseTLS = incoming.consoleUseTLS
                updated.consoleTLSUserProfile = incoming.consoleTLSUserProfile
                updated.consoleTLSPassword = incoming.consoleTLSPassword
                updated.consoleBaseMidiChannel = incoming.consoleBaseMidiChannel
                updated.yamahaDm7SceneBank = incoming.yamahaDm7SceneBank
                updated.yamahaProgramChangeMappings = incoming.yamahaProgramChangeMappings
                updated.yamahaMidiInputSourceID = incoming.yamahaMidiInputSourceID
                updated.yamahaMidiOutputDestinationID = incoming.yamahaMidiOutputDestinationID
                updated.consoleChannelAssignments = incoming.consoleChannelAssignments
                updated.consoleNameFormat = incoming.consoleNameFormat
                updated.consoleNameCasing = incoming.consoleNameCasing
                updated.consolePositionChannelDefaults = incoming.consolePositionChannelDefaults
                updated.venueTransportMode = incoming.venueTransportMode
                updated.venueMuteAddressTemplate = incoming.venueMuteAddressTemplate
                updated.venueLevelAddressTemplate = incoming.venueLevelAddressTemplate
                updated.venuePanAddressTemplate = incoming.venuePanAddressTemplate
                updated.venueSceneRecallAddressTemplate = incoming.venueSceneRecallAddressTemplate
                updated.digicoRTFFileName = incoming.digicoRTFFileName
                updated.digicoRTFImportedAt = incoming.digicoRTFImportedAt
                updated.digicoInputChannels = incoming.digicoInputChannels
                updated.digicoDiscoveredChannels = incoming.digicoDiscoveredChannels
                updated.digicoOSCConsoleName = incoming.digicoOSCConsoleName
                updated.digicoOSCSessionFilename = incoming.digicoOSCSessionFilename
                updated.digicoOSCSyncedAt = incoming.digicoOSCSyncedAt
                if let receivePort = incoming.digicoReceivePort {
                    updated.digicoReceivePort = receivePort
                }
                // digicoLocalListenPort and digicoMaxScanCounts are device-local preferences — not merged
                devices[existingIndex] = updated
            } else {
                // Add new device
                devices.append(incoming)
                currentByKey[k] = devices.count - 1
            }
        }

        // Shure selection merge:
        // Keep local selection if set; otherwise try to adopt incoming selection.
        if shureSelectedChannel == nil, let incomingSel = snapshot.shureSelectedChannel {
            if let incomingDevice = snapshot.devices.first(where: { $0.id == incomingSel.deviceID }) {
                let k = key(for: incomingDevice)
                if let idx = currentByKey[k] {
                    shureSelectedChannel = ShureSelectedChannel(
                        deviceID: devices[idx].id,
                        channelIndex: incomingSel.channelIndex
                    )
                }
            }
        }
    }

    /// Decode and replace external devices from raw data.
    /// Accepts both the new Snapshot object format and the legacy `[ExternalDeviceConfig]` array.
    func applySnapshotData(_ data: Data) {
        let decoder = JSONDecoder()
        if let snap = try? decoder.decode(Snapshot.self, from: data) {
            applySnapshot(snap)
            return
        }
        if let legacyDevices = try? decoder.decode([ExternalDeviceConfig].self, from: data) {
            applySnapshot(Snapshot(devices: legacyDevices, shureSelectedChannel: nil))
            return
        }
        print("[ExternalDevicesStore] Failed to decode snapshot data")
    }

    /// Decode and merge external devices from raw data.
    /// Accepts both the new Snapshot object format and the legacy `[ExternalDeviceConfig]` array.
    func mergeSnapshotData(_ data: Data) {
        let decoder = JSONDecoder()
        if let snap = try? decoder.decode(Snapshot.self, from: data) {
            mergeSnapshot(snap)
            return
        }
        if let legacyDevices = try? decoder.decode([ExternalDeviceConfig].self, from: data) {
            mergeSnapshot(Snapshot(devices: legacyDevices, shureSelectedChannel: nil))
            return
        }
        print("[ExternalDevicesStore] Failed to decode snapshot data")
    }
    private let storageKey = "external_devices_v1"

    // Debounced persistence to avoid blocking UI during rapid edits (pickers/auto-assign).
    private let persistQueue = DispatchQueue(label: "ExternalDevicesStore.persist", qos: .utility)
    private var persistWorkItem: DispatchWorkItem?

    private init() {
        load()
    }

    // MARK: CRUD

    @discardableResult
    func addDevice(
        name: String = "New Device",
        kind: ExternalDeviceKind = .audioConsole,
        host: String = "192.168.1.100",
        port: UInt16 = 8000,
        consoleModelIdentifier: String? = nil,
        consoleSubmodelIdentifier: String? = nil,
        shureModelIdentifier: String? = nil,
        shureDeviceIDName: String? = nil,
        psmSessionHost: String? = nil,
        psmSessionPort: UInt16? = nil,
        shureDiscoveryCID: UUID? = nil,
        shureDiscoveryUACN: String? = nil,
        shureDiscoveryFCTN: String? = nil,
        shureSdtHost: String? = nil,
        shureSdtPort: UInt16? = nil,
        shureDiscoveryDDLURL: String? = nil
    ) -> ExternalDeviceConfig {
        let device = ExternalDeviceConfig(
            name: name,
            kind: kind,
            host: host,
            port: port,
            consoleModelIdentifier: consoleModelIdentifier,
            consoleSubmodelIdentifier: consoleSubmodelIdentifier,
            shureModelIdentifier: shureModelIdentifier,
            shureDeviceIDName: shureDeviceIDName,
            psmSessionPort: psmSessionPort,
            psmSessionHost: psmSessionHost,
            shureDiscoveryCID: shureDiscoveryCID,
            shureDiscoveryUACN: shureDiscoveryUACN,
            shureDiscoveryFCTN: shureDiscoveryFCTN,
            shureSdtHost: shureSdtHost,
            shureSdtPort: shureSdtPort,
            shureDiscoveryDDLURL: shureDiscoveryDDLURL
        )
        devices.append(device)
        return device
    }

    func removeDevices(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
    }

    func updateDevice(_ device: ExternalDeviceConfig) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            // Skip no-op writes: assigning an unchanged value still fires the
            // `devices` didSet -> persist() -> UserDefaults write -> CFPrefs KVO
            // storm. Hot callers (channel-name re-reports, discovery, live sync)
            // frequently pass identical data during live mode.
            guard devices[index] != device else { return }
            devices[index] = device
        }
    }

    func device(withID id: UUID) -> ExternalDeviceConfig? {
        devices.first(where: { $0.id == id })
    }

    func devices(ofKind kind: ExternalDeviceKind) -> [ExternalDeviceConfig] {
        devices.filter { $0.kind == kind }
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            devices = []
            shureSelectedChannel = nil
            return
        }

        let decoder = JSONDecoder()
        do {
            let state = try decoder.decode(Snapshot.self, from: data)
            devices = state.devices
            shureSelectedChannel = state.shureSelectedChannel
        } catch {
            // Snapshot decoding already tries legacy, so landing here means total failure.
            print("[ExternalDevicesStore] Failed to decode devices: \(error)")
            devices = []
            shureSelectedChannel = nil
        }
    }

    private func persist() {
        // Capture a value snapshot on the MainActor, then encode/write on a background queue.
        let state = Snapshot(
            devices: devices,
            shureSelectedChannel: shureSelectedChannel
        )

        // Debounce disk/encoding work; many rapid mutations can occur while editing.
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [storageKey] in
            do {
                let data = try JSONEncoder().encode(state)
                UserDefaults.standard.set(data, forKey: storageKey)
            } catch {
                print("[ExternalDevicesStore] Failed to encode devices: \(error)")
            }
        }
        persistWorkItem = item
        // 250ms feels instant to users but collapses a burst of writes into one.
        persistQueue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
    func updateDevice(id: UUID, mutate: (inout ExternalDeviceConfig) -> Void) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        var copy = devices[idx]
        mutate(&copy)
        // Skip no-op writes: an unchanged reassignment still fires the `devices`
        // didSet -> persist() -> UserDefaults write -> app-wide CFPrefs KVO
        // storm. Many hot-path callers (e.g. updateShureChannelName re-reporting
        // an already-known name) leave `copy` identical.
        guard copy != devices[idx] else { return }
        devices[idx] = copy
        // `devices` didSet will call persist() (debounced).
    }
    
}
extension ExternalDevicesStore {
    struct ShureSelectedChannel: Codable, Equatable {
        var deviceID: UUID
        var channelIndex: Int
    }
}
