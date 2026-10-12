import SwiftUI

/// Auto-scans all network-discoverable hardware (Qu, X32/M32, Wing, Shure
/// Wireless, Sennheiser Wireless) via the same ExternalDeviceDiscoveryService used
/// by ExternalDevicesSettingsView, and lets the user add found devices with one tap.
/// (DiGiCo consoles have no discovery probe and are add-manually-only elsewhere in the app.)
struct OnboardingDevicesStepView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var discoveryService = ExternalDeviceDiscoveryService()
    @State private var addedResultKeys: Set<String> = []

    /// External device discovery is Pro-only everywhere else in the app
    /// (ExternalDevicesSettingsView); this step must not let free users bypass that.
    private var isLocked: Bool { !subscriptionManager.hasPro }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(discoveryService.statusText)
                    .foregroundStyle(.secondary)
                Spacer()
                if discoveryService.isScanning {
                    ProgressView()
                }
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(discoveryService.results) { result in
                        let isAdded = addedResultKeys.contains(discoveryKey(for: result))
                        Button {
                            add(result)
                        } label: {
                            OnboardingChecklistRow(
                                icon: result.kind.systemImage,
                                title: result.name,
                                subtitle: result.kind.displayName
                            ) {
                                if isAdded {
                                    Label("Added", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Add")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isAdded)
                    }
                }
            }
        }
        .padding(20)
        .onboardingProLocked(isLocked)
        .onAppear {
            guard !isLocked else { return }
            discoveryService.startScan()
        }
        .onDisappear { discoveryService.stopScan() }
    }

    /// Stable identity for a discovery result across re-announce/re-resolve events, which
    /// generate a fresh `ExternalDeviceDiscoveryResult.id` (a UUID) mid-scan. Mirrors
    /// `ExternalDevicesSettingsView.discoveryKey(for:)`.
    private func discoveryKey(for result: ExternalDeviceDiscoveryResult) -> String {
        "\(result.kind.rawValue)|\(result.storedHost)|\(resolvedDiscoveryPort(for: result))"
    }

    /// Shure Wireless devices' real TCP control port is always 2202, regardless of the
    /// port carried by the discovery result (SLP fallback discovery reports 8427, which is
    /// not the control port). Mirrors `ExternalDevicesSettingsView.resolvedDiscoveryPort(for:)`.
    private func resolvedDiscoveryPort(for result: ExternalDeviceDiscoveryResult) -> UInt16 {
        if result.kind == .shureWireless {
            return 2202
        }
        return result.port
    }

    private func add(_ result: ExternalDeviceDiscoveryResult) {
        let resolvedPort = resolvedDiscoveryPort(for: result)
        _ = ExternalDevicesStore.shared.addDevice(
            name: result.name,
            kind: result.kind,
            host: result.storedHost,
            port: resolvedPort,
            consoleModelIdentifier: result.consoleModelIdentifier,
            consoleSubmodelIdentifier: result.consoleSubmodelIdentifier,
            shureDiscoveryCID: result.shureCID,
            shureDiscoveryUACN: result.shureUacn,
            shureDiscoveryFCTN: result.shureFctn,
            shureSdtHost: result.shureSdtHost,
            shureSdtPort: result.shureSdtPort,
            shureDiscoveryDDLURL: result.shureDdlURL
        )
        addedResultKeys.insert(discoveryKey(for: result))
    }
}
