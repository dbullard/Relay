import SwiftUI

struct NDIModuleModel: Codable, Equatable, Hashable {
    enum InterfaceSelection: Codable, Equatable, Hashable {
        case auto
        case globalPreferred
        case specific(String)

        private enum CodingKeys: String, CodingKey {
            case type
            case interfaceID
        }

        private enum Kind: String, Codable {
            case auto
            case globalPreferred
            case specific
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .type)
            switch kind {
            case .auto:
                self = .auto
            case .globalPreferred:
                self = .globalPreferred
            case .specific:
                self = .specific(try container.decode(String.self, forKey: .interfaceID))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .auto:
                try container.encode(Kind.auto, forKey: .type)
            case .globalPreferred:
                try container.encode(Kind.globalPreferred, forKey: .type)
            case .specific(let interfaceID):
                try container.encode(Kind.specific, forKey: .type)
                try container.encode(interfaceID, forKey: .interfaceID)
            }
        }
    }

    enum QualityTier: String, Codable, CaseIterable, Identifiable, Hashable {
        case poster
        case preview
        case live

        var id: String { rawValue }

        var title: String {
            switch self {
            case .poster: return "Poster"
            case .preview: return "Preview"
            case .live: return "Live"
            }
        }

        var defaultFPS: Double {
            switch self {
            case .poster: return 1
            case .preview: return 15
            case .live: return 30
            }
        }
    }

    enum DisplayMode: String, Codable, CaseIterable, Identifiable, Hashable {
        case fit
        case fill

        var id: String { rawValue }
    }

    var sourceID: String = ""
    var sourceName: String = ""
    var interfaceSelection: InterfaceSelection = .globalPreferred
    var qualityTier: QualityTier = .preview
    var fpsCap: Int = 15
    var audioEnabled: Bool = false
    var allowAutoFallback: Bool = true
    var preferLowLatency: Bool = true
    var showOverlay: Bool = true
    var isMuted: Bool = true
    var displayMode: DisplayMode = .fit
    var lastKnownResolution: String = ""
}

struct NDIModuleView: View {
    @Binding var model: NDIModuleModel
    let moduleID: UUID
    let tabID: UUID
    let isLiveMode: Bool

    @State private var streamID: String?
    @State private var activeStream: NDIManagedStream?
    @State private var isOverBudget: Bool = false
    @State private var discoveryService = NDIDiscoveryService.shared
    @State private var streamRegistry = NDIStreamRegistry.shared

    var body: some View {
        ZStack {
            NDIVideoSurfaceView(
                presentation: currentPresentation,
                displayMode: model.displayMode,
                pipeline: activeStream?.pipeline
            )
            .overlay(alignment: .topTrailing) {
                if shouldShowReconnectBadge {
                    Text("Reconnecting…")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                        .padding(8)
                }
            }
            .overlay(alignment: .top) {
                headerOverlay
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
            }
            .overlay(alignment: .bottomLeading) {
                bottomOverlay
                    .padding(14)
            }
            .overlay {
                if shouldShowCenteredStatus {
                    centeredStatusOverlay
                        .padding(24)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear(perform: attachStream)
        .onDisappear(perform: detachStream)
        // Single computed key so one atomic model update (e.g. quality changing
        // both qualityTier + fpsCap) fires exactly one reattach, not two.
        .onChange(of: streamConfigKey, initial: false) { _, _ in reattachStream() }
    }

    private var displayTitle: String {
        let trimmed = model.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !model.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return model.sourceID }
        return "NDI Feed"
    }

    /// Single string that encodes every field that should trigger a stream restart.
    /// Using one key means an atomic model update (e.g. quality sets both qualityTier
    /// and fpsCap) fires exactly ONE onChange, not one per changed field.
    private var streamConfigKey: String {
        // Use the normalised fps (qualityTier.defaultFPS) rather than model.fpsCap
        // directly so a stale persisted fpsCap doesn't create a spurious new stream.
        let normalisedFPS = Int(model.qualityTier.defaultFPS)
        let ifaceToken: String
        switch model.interfaceSelection {
        case .auto: ifaceToken = "auto"
        case .globalPreferred: ifaceToken = "global"
        case .specific(let id): ifaceToken = id
        }
        return [
            model.sourceID,
            ifaceToken,
            model.qualityTier.rawValue,
            "\(normalisedFPS)",
            "\(model.audioEnabled)",
            "\(model.preferLowLatency)",
            "\(model.allowAutoFallback)"
        ].joined(separator: "::")
    }

    private var displayedResolutionText: String? {
        if let latest = activeStream?.pipeline.latestResolutionText,
           !latest.isEmpty {
            return latest
        }
        let trimmed = model.lastKnownResolution.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var resolvedInterfaceLabel: String {
        switch model.interfaceSelection {
        case .auto:
            return "Auto"
        case .globalPreferred:
            if let interfaceID = NDIPreferencesStore.load().preferredInterfaceID,
               let interface = discoveryService.interfaceDescriptor(id: interfaceID) {
                return "Global • \(interface.displayName)"
            }
            return "Global • Auto"
        case .specific(let interfaceID):
            return discoveryService.interfaceDescriptor(id: interfaceID)?.displayName ?? interfaceID
        }
    }

    private var pipeline: NDIFramePipeline? {
        activeStream?.pipeline
    }

    private var headerOverlay: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(displayTitle, systemImage: "dot.radiowaves.left.and.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 12)

            chromePill(model.qualityTier.title.uppercased(), prominence: .strong)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Only show status text when there's an actual status to communicate —
            // nil presentation means .connected with live video; no overlay needed.
            if shouldShowBottomStatusText, let headline = currentPresentation?.headline {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    if let subtitle = statusSubtitleText {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                    }
                }
            }

            if model.showOverlay {
                overlayMetrics
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: overlayWidth, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.70),
                    Color.black.opacity(0.38)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .opacity(shouldShowBottomOverlay ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: shouldShowBottomOverlay)
        .allowsHitTesting(false)
    }

    private var centeredStatusOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: centeredStatusSymbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))

            Text(currentPresentation?.headline ?? "Waiting for stream")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            if let subtitle = statusSubtitleText {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        .allowsHitTesting(false)
    }

    private var overlayMetrics: some View {
        VStack(alignment: .leading, spacing: 5) {
            detailRow("NIC", resolvedInterfaceLabel)
            detailRow("Mode", model.qualityTier.title)
            detailRow("Scale", model.displayMode.rawValue.capitalized)
            detailRow("FPS Cap", "\(model.fpsCap)")
            if let fps = pipeline?.latestFPSText, !fps.isEmpty {
                detailRow("FPS", fps)
            }
            if let resolution = displayedResolutionText {
                detailRow("Resolution", resolution)
            }
            if let pixelFormat = pipeline?.latestFrame?.pixelFormat.rawValue,
               !pixelFormat.isEmpty {
                detailRow("Format", pixelFormat.uppercased())
            }
            if let activeStream {
                detailRow("Stream", activeStream.snapshot.id)
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white.opacity(0.84))
    }

    private var shouldShowCenteredStatus: Bool {
        pipeline?.latestFrame == nil
    }

    private var shouldShowBottomStatusText: Bool {
        model.showOverlay || pipeline?.latestFrame == nil
    }

    private var shouldShowBottomOverlay: Bool {
        model.showOverlay || pipeline?.latestFrame == nil
    }

    private var overlayWidth: CGFloat {
        model.showOverlay ? 260 : 300
    }

    private var centeredStatusSymbolName: String {
        guard let pipeline else { return "play.rectangle.on.rectangle" }
        switch pipeline.state {
        case .idle:
            return "dot.radiowaves.left.and.right"
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return "play.rectangle.on.rectangle"
        case .disconnected:
            return "wifi.exclamationmark"
        case .suspended:
            return "pause.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var statusSubtitleText: String? {
        if let sub = currentPresentation?.subtitle { return sub }
        let details: [String] = [displayedResolutionText, pipeline?.latestFPSText]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        return details.isEmpty ? nil : details.joined(separator: " • ")
    }

    private var currentPresentation: NDIPipelinePresentation? {
        if isOverBudget {
            return NDIErrorPresenter.presentation(for: .suspended(.overBudget), sourceName: nil, retryCount: 0)
        }
        guard let pipeline = activeStream?.pipeline else {
            return NDIErrorPresenter.presentation(for: .idle, sourceName: nil, retryCount: 0)
        }
        return NDIErrorPresenter.presentation(
            for: pipeline.state,
            sourceName: model.sourceName.nilIfEmpty,
            retryCount: pipeline.retryCount,
            onRetry: { reattachStream() }
        )
    }

    private var shouldShowReconnectBadge: Bool {
        guard let pipeline = activeStream?.pipeline else { return false }
        return pipeline.retryCount > 0 && pipeline.retryCount <= 3
    }

    private func chromePill(_ text: String, prominence: ChromePillProminence) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(prominence == .strong ? 0.96 : 0.88))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(prominence == .strong ? Color.black.opacity(0.38) : Color.white.opacity(0.12))
            )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
    }

    private func attachStream() {
        let resolvedInterfaceID = resolveInterfaceID()
        if shouldAutoRefreshSourcesOnAppear,
           discoveryService.shouldRefreshSources(
            preferredInterfaceID: resolvedInterfaceID,
            selectedSourceID: model.sourceID
           ) {
            discoveryService.requestSourceRefresh(preferredInterfaceID: resolvedInterfaceID)
        }

        // Normalise fpsCap to the quality tier's default so a stale persisted model
        // (e.g. qualityTier=.live, fpsCap=15 from before quality drove fps) always
        // starts the right receiver without requiring a settings re-save.
        var normalisedModel = model
        normalisedModel.fpsCap = Int(model.qualityTier.defaultFPS)

        let result = streamRegistry.acquireStream(
            for: normalisedModel,
            resolvedInterfaceID: resolvedInterfaceID,
            tabID: tabID
        )
        switch result {
        case .stream(let managed):
            streamID = managed.id
            activeStream = managed
            isOverBudget = false
        case .overBudget:
            streamID = nil
            activeStream = nil
            isOverBudget = true
        }
    }

    private func detachStream() {
        guard let streamID else { return }
        streamRegistry.release(streamID: streamID)
        self.streamID = nil
        activeStream = nil
        isOverBudget = false
    }

    private func reattachStream() {
        detachStream()
        attachStream()
    }

    private func resolveInterfaceID() -> String? {
        switch model.interfaceSelection {
        case .auto:
            return nil
        case .globalPreferred:
            return NDIPreferencesStore.load().preferredInterfaceID
        case .specific(let interfaceID):
            return interfaceID
        }
    }

    private var shouldAutoRefreshSourcesOnAppear: Bool {
        true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private enum ChromePillProminence {
    case subtle
    case strong
}

struct NDIModuleSettingsView: View {
    @Binding var model: NDIModuleModel
    let onPersist: () -> Void

    @State private var discoveryService = NDIDiscoveryService.shared
    @State private var showManualSourceInfo: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Source
            settingsSectionHeader("NDI® Source")

            Group {
                Picker("NDI® Source", selection: sourceSelectionBinding) {
                    Text("Unassigned").tag("")
                    ForEach(discoveryService.sources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    discoveryService.requestSourceRefresh(preferredInterfaceID: preferredInterfaceIDForDiscovery)
                } label: {
                    Label("Refresh Sources", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup("Can't find your source?", isExpanded: $showManualSourceInfo) {
                    Text("NDI discovery requires the source to be on the same network segment. Check that the sending device is on the same subnet as this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // MARK: Video
            settingsSectionHeader("Video")

            Group {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Quality", selection: qualityBinding) {
                        ForEach(NDIModuleModel.QualityTier.allCases) { tier in
                            Text(tier.title).tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(qualityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Scale", selection: displayModeBinding) {
                        ForEach(NDIModuleModel.DisplayMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("Show overlay", isOn: showOverlayBinding)
            }
            .padding(.bottom, 16)

            // MARK: Network
            settingsSectionHeader("Network")

            Group {
                #if os(macOS)
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Network Interface", selection: interfaceSelectionTokenBinding) {
                        Text("Auto").tag("auto")
                        Text("Use Global Preferred").tag("global")
                        ForEach(discoveryService.interfaces) { iface in
                            Text("\(iface.displayName) • \(iface.statusSummary)").tag("specific:\(iface.id)")
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Inherits the interface set in NDI global settings unless overridden here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Allow NIC fallback", isOn: allowAutoFallbackBinding)
                #else
                Text("Network interface selection is managed automatically on iPad.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif

                Toggle("Prefer low latency", isOn: preferLowLatencyBinding)
            }
            .padding(.bottom, 16)

            // MARK: Audio
            settingsSectionHeader("Audio")

            Group {
                Toggle("Enable audio", isOn: audioEnabledBinding)
                if model.audioEnabled {
                    Toggle("Mute in tile", isOn: mutedBinding)
                }
            }
            .padding(.bottom, 24)

            // MARK: NDI® Attribution
            Divider()
            ndiAttributionFooter
                .padding(.top, 12)
        }
        .onAppear {
            discoveryService.refreshInterfaces()
            if shouldAutoRefreshSourcesOnAppear,
               discoveryService.shouldRefreshSources(
                preferredInterfaceID: preferredInterfaceIDForDiscovery,
                selectedSourceID: model.sourceID,
                maxAge: 10
               ) {
                discoveryService.requestSourceRefresh(preferredInterfaceID: preferredInterfaceIDForDiscovery)
            }
        }
        .onChange(of: discoveryService.sources, initial: false) { _, _ in
            reconcileSourceSelection()
        }
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
    }

    private var qualityDescription: String {
        switch model.qualityTier {
        case .poster:  return "1 fps — minimal CPU impact"
        case .preview: return "15 fps — suitable for monitoring"
        case .live:    return "30 fps — full quality"
        }
    }

    private var ndiAttributionFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Powered by NDI®")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("NDI® is a registered trademark of Vizrt NDI AB")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("Learn more: ndi.video", destination: URL(string: "https://ndi.video")!)
                .font(.caption)
        }
    }

    // MARK: - Bindings

    private var sourceSelectionBinding: Binding<String> {
        Binding(
            get: {
                guard !model.sourceID.isEmpty else { return "" }
                return discoveryService.sources.contains(where: { $0.id == model.sourceID }) ? model.sourceID : ""
            },
            set: { newID in
                if newID.isEmpty {
                    model.sourceID = ""
                    model.sourceName = ""
                } else {
                    model.sourceID = newID
                    if let source = discoveryService.sources.first(where: { $0.id == newID }) {
                        model.sourceName = source.name
                    }
                }
                onPersist()
            }
        )
    }

    private var qualityBinding: Binding<NDIModuleModel.QualityTier> {
        Binding(
            get: { model.qualityTier },
            set: { newTier in
                // Write both fields atomically through the binding to avoid double-persist
                var updated = model
                updated.qualityTier = newTier
                updated.fpsCap = Int(newTier.defaultFPS)
                model = updated
                onPersist()
            }
        )
    }

    private var displayModeBinding: Binding<NDIModuleModel.DisplayMode> {
        Binding(get: { model.displayMode }, set: { model.displayMode = $0; onPersist() })
    }

    private var showOverlayBinding: Binding<Bool> {
        Binding(get: { model.showOverlay }, set: { model.showOverlay = $0; onPersist() })
    }

    private var preferLowLatencyBinding: Binding<Bool> {
        Binding(get: { model.preferLowLatency }, set: { model.preferLowLatency = $0; onPersist() })
    }

    private var allowAutoFallbackBinding: Binding<Bool> {
        Binding(get: { model.allowAutoFallback }, set: { model.allowAutoFallback = $0; onPersist() })
    }

    private var audioEnabledBinding: Binding<Bool> {
        Binding(get: { model.audioEnabled }, set: { model.audioEnabled = $0; onPersist() })
    }

    private var mutedBinding: Binding<Bool> {
        Binding(get: { model.isMuted }, set: { model.isMuted = $0; onPersist() })
    }

    private var preferredInterfaceIDForDiscovery: String? {
        switch model.interfaceSelection {
        case .auto: return nil
        case .globalPreferred: return NDIPreferencesStore.load().preferredInterfaceID
        case .specific(let id): return id
        }
    }

    private var interfaceSelectionTokenBinding: Binding<String> {
        Binding(
            get: {
                switch model.interfaceSelection {
                case .auto: return "auto"
                case .globalPreferred: return "global"
                case .specific(let id): return "specific:\(id)"
                }
            },
            set: { newValue in
                if newValue == "auto" {
                    model.interfaceSelection = .auto
                } else if newValue == "global" {
                    model.interfaceSelection = .globalPreferred
                } else if newValue.hasPrefix("specific:") {
                    model.interfaceSelection = .specific(String(newValue.dropFirst("specific:".count)))
                }
                onPersist()
            }
        )
    }

    private func reconcileSourceSelection() {
        guard !model.sourceID.isEmpty else { return }
        guard !discoveryService.sources.isEmpty else { return }
        guard !discoveryService.sources.contains(where: { $0.id == model.sourceID }) else { return }
        model.sourceID = ""
        model.sourceName = ""
        onPersist()
    }

    private var shouldAutoRefreshSourcesOnAppear: Bool {
        true
    }
}

struct DashboardNDISettingsView: View {
    @State private var discoveryService = NDIDiscoveryService.shared
    @State private var preferredInterfaceID: String = ""
    @State private var allowAutoFallback: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NDI")
                .font(.title2.bold())

            Text("Choose the network interface Relay should prefer for NDI discovery and receive. Modules can inherit this default or pin a specific NIC.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Preferred Interface", selection: $preferredInterfaceID) {
                Text("Auto").tag("")
                ForEach(discoveryService.interfaces) { interface in
                    Text("\(interface.displayName) • \(interface.statusSummary)").tag(interface.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: preferredInterfaceID, initial: false) { _, _ in persist() }

            Toggle("Allow automatic fallback when preferred NIC is unavailable", isOn: $allowAutoFallback)
                .onChange(of: allowAutoFallback, initial: false) { _, _ in persist() }

            VStack(alignment: .leading, spacing: 8) {
                Text("Detected Interfaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(discoveryService.interfaces) { interface in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(interface.displayName)
                            Text(interface.statusSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if interface.id == preferredInterfaceID {
                            Text("Preferred")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.blue.opacity(0.18)))
                        }
                    }
                }
            }

            Divider()
            ndiAttributionFooter
                .padding(.top, 8)

            Spacer()
        }
        .padding(24)
        .onAppear {
            discoveryService.refreshInterfaces()
            let prefs = NDIPreferencesStore.load()
            preferredInterfaceID = prefs.preferredInterfaceID ?? ""
            allowAutoFallback = prefs.allowAutoFallback
            if shouldAutoRefreshSourcesOnAppear {
                discoveryService.requestSourceRefresh(preferredInterfaceID: preferredInterfaceID.isEmpty ? nil : preferredInterfaceID)
            }
        }
    }

    private var ndiAttributionFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Powered by NDI®")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("NDI® is a registered trademark of Vizrt NDI AB")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("Learn more: ndi.video", destination: URL(string: "https://ndi.video")!)
                .font(.caption)
        }
    }

    private func persist() {
        NDIPreferencesStore.save(
            NDIGlobalPreferences(
                preferredInterfaceID: preferredInterfaceID.isEmpty ? nil : preferredInterfaceID,
                allowAutoFallback: allowAutoFallback
            )
        )
    }

    private var shouldAutoRefreshSourcesOnAppear: Bool {
#if os(iOS)
        false
#else
        true
#endif
    }
}

enum NDIModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .ndi(NDIModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        _ = tile
        let tabID = tab.wrappedValue.id

        let modelBinding = Binding<NDIModuleModel>(
            get: {
                if case .ndi(let model) = module.wrappedValue.kind {
                    return model
                }
                return NDIModuleModel()
            },
            set: { newValue in
                var updated = module.wrappedValue
                updated.kind = .ndi(newValue)
                module.wrappedValue = updated
            }
        )

        return AnyView(
            NDIModuleView(
                model: modelBinding,
                moduleID: module.wrappedValue.id,
                tabID: tabID,
                isLiveMode: isLiveMode
            )
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        _ = showsHeader
        _ = onPersist
        return AnyView(EmptyView())
    }
}
