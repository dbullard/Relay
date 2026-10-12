import Foundation

/// A tile the Review & Create step proposes, built from something the user has
/// configured (a device, an audio input). `isIncluded` drives the checklist;
/// unchecking removes it from the live preview and the final dashboard.
/// `subtitle`/`systemImage` are display-only, used by OnboardingChecklistRow.
struct OnboardingTileCandidate: Identifiable, Equatable {
    let id: UUID
    let title: String
    let module: DashboardModuleModel
    var isIncluded: Bool = true
    var subtitle: String = ""
    var systemImage: String = "square.grid.2x2"
}

enum OnboardingTileCandidateFactory {
    /// Devices without a corresponding dashboard module (audio consoles, Vista
    /// consoles) are omitted — not every configured device becomes a tile.
    static func candidate(for device: ExternalDeviceConfig) -> OnboardingTileCandidate? {
        switch device.kind {
        case .shureWireless:
            let config = ShureModuleConfig(
                selectedChannel: ExternalDevicesStore.ShureSelectedChannel(deviceID: device.id, channelIndex: 1)
            )
            let module = DashboardModuleModel(kind: .shureWireless, order: 0, shureConfig: config)
            return OnboardingTileCandidate(
                id: UUID(),
                title: device.name,
                module: module,
                subtitle: "Wireless mic + IEM status",
                systemImage: device.kind.systemImage
            )

        case .sennheiserWireless:
            let config = SennheiserWirelessModuleConfig(externalDeviceID: device.id, channelIndex: 1)
            let module = DashboardModuleModel(kind: .sennheiserWireless, order: 0, sennheiserConfig: config)
            return OnboardingTileCandidate(
                id: UUID(),
                title: device.name,
                module: module,
                subtitle: "Wireless mic + IEM status",
                systemImage: device.kind.systemImage
            )

        case .audioConsole, .vistaConsole, .lightingConsole, .genericOsc:
            return nil
        }
    }

    /// Every configured audio input becomes an RTA meter tile by default.
    static func candidate(for input: AudioInputConfig) -> OnboardingTileCandidate {
        let model = RTAModuleModel(inputID: input.id)
        let module = DashboardModuleModel(kind: .rta(model), order: 0)
        return OnboardingTileCandidate(
            id: UUID(),
            title: input.name,
            module: module,
            subtitle: "Real-time frequency analyzer",
            systemImage: "waveform"
        )
    }

    /// Builds a candidate directly from a starter-tile catalog entry, using the entry's
    /// already-fully-initialized default `kind` (e.g. `.text(TextModuleModel(...))`), and
    /// copying its display subtitle/icon straight from the catalog.
    static func candidate(for entry: DashboardModuleCatalogItem) -> OnboardingTileCandidate {
        OnboardingTileCandidate(
            id: UUID(),
            title: entry.title,
            module: DashboardModuleModel(kind: entry.kind, order: 0),
            subtitle: entry.subtitle,
            systemImage: entry.systemImage
        )
    }
}
