//
//  ResolumeDisplayMode.swift
//  Relay
//
//  Created by David Bullard on 12/17/25.
//

//
//  ResolumeModule.swift
//  Relay
//
//  Dashboard module wrapper for Resolume using ResolumeConnection (REST).
//

import SwiftUI
import Foundation
import Combine

// MARK: - Config

public enum ResolumeDisplayMode: String, CaseIterable, Identifiable, Codable {
    case finalOutput
    case timecode
    case clipList
    case customPath

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .finalOutput: return "Final Output"
        case .timecode:    return "Timecode"
        case .clipList:    return "Clip List"
        case .customPath:  return "Custom Path"
        }
    }

    /// Default “poll path” per mode.
    /// Update these to match the exact endpoints you decide to use.
    public var defaultPath: String {
        switch self {
        case .finalOutput: return "/api/v1/composition"
        case .timecode:    return "/api/v1/composition"
        case .clipList:    return "/api/v1/composition"
        case .customPath:  return "/api/v1/composition"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "finalOutput", "final_output", "final-output":
            self = .finalOutput
        case "timecode":
            self = .timecode
        case "clipList", "clip_list", "clips":
            self = .clipList
        case "customPath":
            self = .customPath
        case "composition", "layers", "parameters":
            self = .finalOutput
        default:
            self = .finalOutput
        }
    }
}
struct ResolumeModuleModel: Codable, Equatable {
    var profileID: UUID?
    var displayMode: ResolumeDisplayMode
    var deckID: Int?
    var layerID: Int?
    var clipID: Int?

    init(
        profileID: UUID? = nil,
        displayMode: ResolumeDisplayMode = .finalOutput,
        deckID: Int? = nil,
        layerID: Int? = nil,
        clipID: Int? = nil
    ) {
        self.profileID = profileID
        self.displayMode = displayMode
        self.deckID = deckID
        self.layerID = layerID
        self.clipID = clipID
    }

    static func `default`() -> ResolumeModuleModel {
        ResolumeModuleModel()
    }
}
// MARK: - Plugin wrapper

/// Minimal plugin wrapper so the dashboard can render and edit a Resolume module.
/// We’ll wire this to the real per-module config binding once the DashboardModuleModel
/// has a `resolumeConfig` field (mirroring ProPresenter/Shure).
struct ResolumeModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .resolume(ResolumeModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        // `resolumeConfig` may be optional on the model; seed a default if needed.
        var cfg = module.wrappedValue.resolumeConfig ?? ResolumeModuleConfig()
        // Keep config id aligned with the module id so lookups/logging stay consistent.
        cfg.id = module.wrappedValue.id
        if module.wrappedValue.resolumeConfig == nil {
            module.wrappedValue.resolumeConfig = cfg
        }
        return AnyView(
            ResolumeModuleView(config: cfg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                if showsHeader.wrappedValue {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.tv")
                        Text("Resolume")
                            .font(.headline)
                        Spacer()
                    }
                }

                Text("Resolume connections are configured in Settings → Resolume.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Per-tile module display options (mode, polling interval, etc.) are configured from the tile Edit View.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Done") {
                        onPersist()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
        )
    }
}

public struct ResolumeModuleConfig: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()

    /// If set, the module will use the corresponding saved profile from Settings → Resolume.
    public var profileID: UUID? = nil

    /// Fallback endpoint used when profileID is nil or cannot be resolved.
    public var endpoint: ResolumeEndpoint

    public var pollIntervalSeconds: Double = 0.5
    public var displayMode: ResolumeDisplayMode = .finalOutput

    /// Only used when displayMode == .customPath
    public var customPath: String = "/api/v1/composition"

    public var showTitle: Bool = true
    public var showDebugJSONPreview: Bool = false
    public var showThumbnails: Bool = true
    public var thumbnailSize: Double = 44

    public init(
        profileID: UUID? = nil,
        endpoint: ResolumeEndpoint = .init(host: "127.0.0.1", port: 8080),
        pollIntervalSeconds: Double = 0.5,
        displayMode: ResolumeDisplayMode = .finalOutput,
        customPath: String = "/api/v1/composition",
        showTitle: Bool = true,
        showDebugJSONPreview: Bool = false,
        showThumbnails: Bool = true,
        thumbnailSize: Double = 44
    ) {
        self.profileID = profileID
        self.endpoint = endpoint
        self.pollIntervalSeconds = pollIntervalSeconds
        self.displayMode = displayMode
        self.customPath = customPath
        self.showTitle = showTitle
        self.showDebugJSONPreview = showDebugJSONPreview
        self.showThumbnails = showThumbnails
        self.thumbnailSize = thumbnailSize
    }
}

private struct ResolumeLayerSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let activeClipName: String?
    let activeClipThumbnailURL: URL?
}

private struct ResolumeClipSummary: Identifiable, Hashable {
    let id: String
    let layerName: String?
    let clipName: String
    let thumbnailURL: URL?
}

// MARK: - Module View

public struct ResolumeModuleView: View {
    public let config: ResolumeModuleConfig

    @Environment(\.tileTextFormatting) private var tileTextFormatting

    @StateObject private var connection = ResolumeConnection.shared

    @State private var compositionFields: (name: String?, bpm: String?, state: String?, timecode: String?) = (nil, nil, nil, nil)
    @State private var compositionDebugPreview: String? = nil
    @State private var layerSummaries: [ResolumeLayerSummary] = []
    @State private var activeClipSummaries: [ResolumeClipSummary] = []
    @State private var speedValue: Double? = nil
    @State private var masterValue: Double? = nil
    @State private var compositionPollTask: Task<Void, Never>? = nil
    @State private var lastCompositionLogAt: Date? = nil
    @State private var lastCompositionLogSignature: String = ""
    @State private var lastTransportProbeAt: Date? = nil
    @State private var transportProbeCache: (state: String?, timecode: String?) = (nil, nil)
    @State private var transportProbeDisabledUntil: Date? = nil
    @State private var transportProbePermanentlyUnavailable: Bool = false

    private var profilesStore: ResolumeProfilesStore { ResolumeConnection.shared.profilesStore }

    public init(config: ResolumeModuleConfig) {
        self.config = config
    }

    // MARK: - Text Formatting Helpers
    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    private var primaryFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    private var resolvedPrimaryColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }

    private var resolvedSecondaryColor: Color {
        resolvedPrimaryColor.opacity(0.7)
    }

    private var resolvedTextAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var resolvedHorizontalAlignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func applyCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Group {
                switch connection.state {
                case .idle, .connecting:
                    Text(applyCapitalization("Connecting…"))
                        .font(.system(size: baseFontSize * 0.8, weight: .regular))
                        .foregroundStyle(resolvedSecondaryColor)

                case .connected:
                    content

                case .error(let msg):
                    Text(applyCapitalization("Error: \(msg)"))
                        .font(.system(size: baseFontSize * 0.8, weight: .regular))
                        .foregroundStyle(resolvedSecondaryColor)
                }
            }
        }
        .onAppear {
            // Always connect + start polling from the currently resolved profile/endpoint.
            connection.connect(endpoint: resolvedEndpoint)
            connection.startPolling(intervalSeconds: config.pollIntervalSeconds, compositionPath: pollPath)
            startCompositionPollingIfNeeded()
        }
        .onChange(of: config.profileID, initial: false) { _, _ in
            // When the profile changes, swap endpoints immediately.
            connection.connect(endpoint: resolvedEndpoint)
            connection.startPolling(intervalSeconds: config.pollIntervalSeconds, compositionPath: pollPath)
            startCompositionPollingIfNeeded()
        }
        .onChange(of: config.endpoint, initial: false) { _, _ in
            // Endpoint is a fallback; still allow manual overrides if no profile is selected.
            if config.profileID == nil {
                connection.connect(endpoint: resolvedEndpoint)
                connection.startPolling(intervalSeconds: config.pollIntervalSeconds, compositionPath: pollPath)
                startCompositionPollingIfNeeded()
            }
        }
        .onChange(of: config.pollIntervalSeconds, initial: false) { _, _ in
            connection.startPolling(intervalSeconds: config.pollIntervalSeconds, compositionPath: pollPath)
            startCompositionPollingIfNeeded()
        }
        .onChange(of: config.displayMode, initial: false) { _, enabled in
            // Refresh connection + polling when display type changes.
            connection.connect(endpoint: resolvedEndpoint)
            connection.startPolling(intervalSeconds: config.pollIntervalSeconds, compositionPath: pollPath)
            startCompositionPollingIfNeeded()
        }
        .onChange(of: config.customPath, initial: false) { _, enabled in
            if config.displayMode == .customPath {
                // Path changes should refresh connection + polling as well.
                connection.connect(endpoint: resolvedEndpoint)
                connection.startPolling(intervalSeconds: config.pollIntervalSeconds, compositionPath: pollPath)
                startCompositionPollingIfNeeded()
            }
        }
        .onDisappear {
            stopCompositionPolling()
        }
    }

    private var resolvedEndpoint: ResolumeEndpoint {
        // Prefer explicitly selected profile endpoint.
        // If none selected, fall back to the first enabled profile from Settings.
        let store = ResolumeConnection.shared.profilesStore
        if let ep = store.resolvedEndpoint(for: config.profileID) {
            return ep
        }
        if config.profileID == nil, let fallbackID = store.firstEnabledProfileID(),
           let ep = store.resolvedEndpoint(for: fallbackID) {
            return ep
        }
        return config.endpoint
    }

    private var resolvedProfileName: String? {
        let store = ResolumeConnection.shared.profilesStore
        return store.resolvedProfileName(for: config.profileID)
    }

    private var pollPath: String {
        if config.displayMode == .customPath {
            return config.customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "/api/v1/composition"
            : config.customPath
        }
        return "/api/v1/composition"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(connectionStateColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(applyCapitalization(config.showTitle ? (resolvedProfileName ?? connection.snapshot.compositionName ?? "Resolume") : ""))
                    .font(.system(size: baseFontSize * 0.9, weight: primaryFontWeight))
                    .foregroundStyle(resolvedPrimaryColor)
                    .lineLimit(1)
                    .opacity(config.showTitle ? 1 : 0)

                Text(resolvedEndpoint.display)
                    .font(.system(size: baseFontSize * 0.65, weight: .regular))
                    .foregroundStyle(resolvedSecondaryColor)
            }

            Spacer()

            Text(applyCapitalization(config.displayMode.label))
                .font(.system(size: baseFontSize * 0.65, weight: .semibold))
                .foregroundStyle(resolvedSecondaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var connectionStateColor: Color {
        switch connection.state {
        case .connected: return .green
        case .error: return .red
        case .connecting: return .yellow
        case .idle: return .gray
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Friendly “default” content for each mode when debug is off.
            if !config.showDebugJSONPreview {
                switch config.displayMode {
                case .finalOutput:
                    finalOutputSummary
                case .timecode:
                    timecodeSummary
                case .clipList:
                    activeClipsSummary
                case .customPath:
                    Text(applyCapitalization("Connected ✓"))
                        .font(.system(size: baseFontSize * 0.8, weight: .regular))
                        .foregroundStyle(resolvedSecondaryColor)
                    Text("Polling: \(pollPath)")
                        .font(.system(size: baseFontSize * 0.65, weight: .regular))
                        .foregroundStyle(resolvedSecondaryColor)
                }
            } else {
                Text(applyCapitalization("Connected ✓"))
                    .font(.system(size: baseFontSize * 0.8, weight: .regular))
                    .foregroundStyle(resolvedSecondaryColor)
                Text("Polling: \(pollPath)")
                    .font(.system(size: baseFontSize * 0.65, weight: .regular))
                    .foregroundStyle(resolvedSecondaryColor)
            }

            if let preview = (compositionDebugPreview ?? connection.snapshot.rawJSONPreview), config.showDebugJSONPreview {
                Text(preview)
                    .font(.system(size: baseFontSize * 0.6, weight: .regular, design: .monospaced))
                    .foregroundStyle(resolvedSecondaryColor)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
                    .multilineTextAlignment(resolvedTextAlignment)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var finalOutputSummary: some View {
        let fields = compositionFields
        return VStack(alignment: .leading, spacing: 6) {
            infoRow("Output", fields.name)
            infoRow("State", fields.state)
            infoRow("Timecode", fields.timecode)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var timecodeSummary: some View {
        let tc = compositionFields.timecode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = (tc?.isEmpty == false) ? tc! : "—"
        return Text(display)
            .font(.system(size: baseFontSize * 1.2, weight: .semibold, design: .monospaced))
            .foregroundStyle(resolvedPrimaryColor)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var compositionSummary: some View {
        let fields = compositionFields
        return VStack(alignment: .leading, spacing: 6) {
            infoRow("Name", fields.name)
            infoRow("BPM", fields.bpm)
            infoRow("State", fields.state)
            infoRow("Timecode", fields.timecode)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var layersSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if layerSummaries.isEmpty {
                Text(applyCapitalization("No layers available"))
                    .font(.system(size: baseFontSize * 0.7, weight: .regular))
                    .foregroundStyle(resolvedSecondaryColor)
            } else {
                ForEach(layerSummaries) { layer in
                    HStack(alignment: .center, spacing: 10) {
                        thumbnailView(for: layer.activeClipThumbnailURL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(applyCapitalization(layer.name))
                                .font(.system(size: baseFontSize * 0.65, weight: .regular))
                                .foregroundStyle(resolvedSecondaryColor)
                            Text(applyCapitalization(layer.activeClipName ?? "—"))
                                .multilineTextAlignment(resolvedTextAlignment)
                                .lineLimit(2)
                                .font(.system(size: baseFontSize * 0.65, weight: .semibold))
                                .foregroundStyle(resolvedPrimaryColor)
                        }
                        Spacer(minLength: 12)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activeClipsSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if activeClipSummaries.isEmpty {
                Text(applyCapitalization("No active clips"))
                    .font(.system(size: baseFontSize * 0.7, weight: .regular))
                    .foregroundStyle(resolvedSecondaryColor)
            } else {
                ForEach(activeClipSummaries) { clip in
                    HStack(alignment: .center, spacing: 10) {
                        thumbnailView(for: clip.thumbnailURL)
                        VStack(alignment: .leading, spacing: 2) {
                            if let layerName = clip.layerName, !layerName.isEmpty {
                                Text(applyCapitalization(layerName))
                                    .font(.system(size: baseFontSize * 0.6, weight: .regular))
                                    .foregroundStyle(resolvedSecondaryColor)
                            }
                            Text(applyCapitalization(clip.clipName))
                                .font(.system(size: baseFontSize * 0.65, weight: .semibold))
                                .foregroundStyle(resolvedPrimaryColor)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var parameterSummary: some View {
        let fields = compositionFields
        let speedText = speedValue.map { String(format: "%.2fx", $0) }
        let masterText = masterValue.map { String(format: "%.2f", $0) }
        return VStack(alignment: .leading, spacing: 6) {
            infoRow("Name", fields.name)
            infoRow("BPM", fields.bpm)
            infoRow("Speed", speedText)
            infoRow("Master", masterText)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(applyCapitalization(label))
                .font(.system(size: baseFontSize * 0.65, weight: .regular))
                .foregroundStyle(resolvedSecondaryColor)
            Spacer(minLength: 12)
            Text(applyCapitalization((value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? value! : "—"))
                .multilineTextAlignment(resolvedTextAlignment)
                .lineLimit(2)
                .font(.system(size: baseFontSize * 0.65, weight: .semibold))
                .foregroundStyle(resolvedPrimaryColor)
        }
    }

    private func buildLayerSummaries(from dict: [String: Any]) -> (layers: [ResolumeLayerSummary], activeClips: [ResolumeClipSummary]) {
        guard let layers = dict["layers"] as? [[String: Any]] else { return ([], []) }

        var summaries: [ResolumeLayerSummary] = []
        var activeClips: [ResolumeClipSummary] = []

        for (layerIndex, layer) in layers.enumerated() {
            let layerName = paramString(layer, key: "name") ?? "Layer"
            let activeClip = activeClipInfo(from: layer)
            let layerID = extractStableID(from: layer) ?? "layer-\(layerIndex)"
            summaries.append(
                ResolumeLayerSummary(
                    id: layerID,
                    name: layerName,
                    activeClipName: activeClip?.name,
                    activeClipThumbnailURL: activeClip?.thumbnailURL
                )
            )
            if let activeClip {
                let clipID = activeClip.id
                activeClips.append(
                    ResolumeClipSummary(
                        id: clipID,
                        layerName: layerName,
                        clipName: activeClip.name,
                        thumbnailURL: activeClip.thumbnailURL
                    )
                )
            }
        }

        return (summaries, activeClips)
    }

    private func activeClipInfo(from layer: [String: Any]) -> (id: String, name: String, thumbnailURL: URL?)? {
        guard let clips = layer["clips"] as? [[String: Any]] else { return nil }

        let preferredStates: Set<String> = ["Connected", "Connected & previewing", "Previewing"]
        for (clipIndex, clip) in clips.enumerated() {
            if let state = paramString(clip, key: "connected"), preferredStates.contains(state) {
                if let name = paramString(clip, key: "name") {
                    let clipID = extractStableID(from: clip) ?? "clip-\(clipIndex)"
                    return (clipID, name, clipThumbnailURL(from: clip))
                }
            }
        }

        // Fallback: show selected clip name when no clip is explicitly connected.
        for (clipIndex, clip) in clips.enumerated() {
            if paramBool(clip, key: "selected") == true {
                if let name = paramString(clip, key: "name") {
                    let clipID = extractStableID(from: clip) ?? "clip-\(clipIndex)"
                    return (clipID, name, clipThumbnailURL(from: clip))
                }
            }
        }

        return nil
    }

    private func extractStableID(from dict: [String: Any]) -> String? {
        if let raw = dict["id"] as? NSNumber {
            return raw.stringValue
        }
        if let raw = dict["id"] as? String, !raw.isEmpty {
            return raw
        }
        if let param = dict["id"] as? [String: Any], let value = param["value"] {
            if let number = value as? NSNumber { return number.stringValue }
            if let str = value as? String, !str.isEmpty { return str }
        }
        return nil
    }

    private func clipThumbnailURL(from clip: [String: Any]) -> URL? {
        guard let thumb = clip["thumbnail"] as? [String: Any],
              let path = thumb["path"] as? String,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        if path.contains("thumbnail/dummy") { return nil }
        guard let base = resolvedEndpoint.baseURL else { return nil }
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(clean)
    }

    private func thumbnailView(for url: URL?) -> AnyView {
        guard config.showThumbnails else {
            return AnyView(EmptyView())
        }

        let size: CGFloat = max(20, CGFloat(config.thumbnailSize))
        if let url {
            return AnyView(
                AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                case .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                @unknown default:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            )
        }

        return AnyView(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
                .frame(width: size, height: size)
        )
    }

    private func paramString(_ dict: [String: Any], key: String) -> String? {
        guard let param = dict[key] as? [String: Any] else { return nil }
        if let value = param["value"] as? String { return value }
        if let value = param["value"] as? CustomStringConvertible { return value.description }
        return nil
    }

    private func paramBool(_ dict: [String: Any], key: String) -> Bool? {
        guard let param = dict[key] as? [String: Any] else { return nil }
        if let value = param["value"] as? Bool { return value }
        return nil
    }

    private func resolvedCompositionFields() -> (name: String?, bpm: String?, state: String?, timecode: String?) {
        return compositionFields
    }

    // MARK: - Local composition polling (full payload, non-truncated)

    private func stopCompositionPolling() {
        compositionPollTask?.cancel()
        compositionPollTask = nil
    }

    private func startCompositionPollingIfNeeded() {
        // Poll composition payload for all built-in modes (composition/layers/clips/parameters).
        guard config.displayMode != .customPath else {
            stopCompositionPolling()
            return
        }

        // Restart task each time we call this to pick up endpoint/path/interval changes.
        stopCompositionPolling()

        let endpoint = resolvedEndpoint
        let path = pollPath
        let interval = max(0.2, config.pollIntervalSeconds)

        compositionPollTask = Task {
            while !Task.isCancelled {
                await fetchAndParseComposition(endpoint: endpoint, path: path)

                // Sleep between polls
                let nanos = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    @MainActor
    private func fetchAndParseComposition(endpoint: ResolumeEndpoint, path: String) async {
        var trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.hasPrefix("/") { trimmedPath = "/" + trimmedPath }

        let urlString = "http://\(endpoint.host):\(endpoint.port)\(trimmedPath)"
        guard let url = URL(string: urlString) else {
            compositionFields = (resolvedProfileName ?? connection.snapshot.compositionName ?? "—", nil, nil, nil)
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // Keep name but clear the dynamic fields.
                compositionFields = (resolvedProfileName ?? connection.snapshot.compositionName ?? "—", nil, nil, nil)

                let now = Date()
                let shouldLogNow = (lastCompositionLogAt == nil) || (now.timeIntervalSince(lastCompositionLogAt!) > 5)

                if config.showDebugJSONPreview {
                    let bodyPreview = prettyJSONString(from: data, maxChars: 2000)
                    compositionDebugPreview = "HTTP \(http.statusCode) for \(urlString)\n\n\(bodyPreview)"
                    print("[ResolumeModule] Composition HTTP \(http.statusCode) for \(urlString)")
                } else {
                    compositionDebugPreview = nil
                    if shouldLogNow {
                        lastCompositionLogAt = now
                        print("[ResolumeModule] Composition HTTP \(http.statusCode) for \(urlString)")
                    }
                }
                return
            }

            // Debug preview (pretty printed, but still safe to truncate for UI)
            if config.showDebugJSONPreview {
                compositionDebugPreview = prettyJSONString(from: data, maxChars: 4000)
                print("[ResolumeModule] Composition payload OK (\(data.count) bytes) from \(urlString)")
            } else {
                compositionDebugPreview = nil
            }

            // Parse JSON
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = obj as? [String: Any] else {
                // Helpful logging (throttled) when we can't cast JSON to a dictionary.
                let now = Date()
                let shouldLogNow = (lastCompositionLogAt == nil) || (now.timeIntervalSince(lastCompositionLogAt!) > 5)
                if shouldLogNow {
                    lastCompositionLogAt = now
                    print("[ResolumeModule] Composition parse: JSON root was not a dictionary for \(urlString)")
                }
                compositionFields = (resolvedProfileName ?? connection.snapshot.compositionName ?? "—", nil, nil, nil)
                return
            }

            // Name
            let nameFromJSON = extractString(dict, paths: [
                "name.value",
                "name",
                "composition.name",
                "compositionName",
                "composition.name.value"
            ])
            let name = resolvedProfileName ?? nameFromJSON ?? connection.snapshot.compositionName

            // BPM (Resolume often nests tempo under tempocontroller/master)
            let bpmDouble = extractDouble(dict, paths: [
                "bpm",
                "tempo",
                "composition.bpm",
                "composition.tempo",
                "master.bpm",
                "master.tempo",
                "tempocontroller.bpm",
                "tempocontroller.tempo",
                "tempocontroller.bpm.value",
                "tempocontroller.tempo.value",
                "master.bpm.value",
                "master.tempo.value"
            ])
            let bpm: String? = bpmDouble.map { String(format: "%.1f", $0) }

            masterValue = extractDouble(dict, paths: [
                "master.value",
                "master"
            ])

            // State
            var state: String? = nil
            if let playing = extractBool(dict, paths: [
                "playing",
                "isPlaying",
                "transport.playing",
                "composition.playing",
                "master.playing",
                "master.isPlaying",
                "master.transport.playing",
                "dashboard.playing",
                "dashboard.isPlaying",
                "selected.playing",
                "selected.isPlaying",
                "playing.value",
                "isPlaying.value",
                "transport.playing.value",
                "composition.playing.value",
                "master.playing.value",
                "master.isPlaying.value",
                "master.transport.playing.value",
                "dashboard.playing.value",
                "dashboard.isPlaying.value",
                "selected.playing.value",
                "selected.isPlaying.value"
            ]) {
                state = playing ? "Playing" : "Stopped"
            } else if let s = extractString(dict, paths: [
                "state",
                "transport.state",
                "composition.state"
            ]) {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    state = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
                }
            }
            // Heuristic fallback: many Resolume builds don’t expose a global transport endpoint,
            // but *do* expose a composition-level speed control. If speed is 0, we treat that as Stopped.
            if state == nil {
                if let speed = extractDouble(dict, paths: [
                    "speed",
                    "speed.value",
                    "composition.speed",
                    "composition.speed.value",
                    "master.speed",
                    "master.speed.value",
                    "dashboard.speed",
                    "dashboard.speed.value",
                    "selected.speed",
                    "selected.speed.value"
                ]) {
                    speedValue = speed
                    // Any non-zero speed implies running.
                    state = (abs(speed) > 0.0001) ? "Playing" : "Stopped"
                }
            }

            // Timecode (often nested under master/dashboard)
            var timecode = extractString(dict, paths: [
                "timecode",
                "timecodeString",
                "transport.timecode",
                "composition.timecode",
                "master.timecode",
                "master.timecodeString",
                "master.transport.timecode",
                "dashboard.timecode",
                "dashboard.timecodeString",
                "dashboard.transport.timecode",
                "timecode.value",
                "timecodeString.value",
                "transport.timecode.value",
                "composition.timecode.value",
                "master.timecode.value",
                "master.timecodeString.value",
                "master.transport.timecode.value",
                "dashboard.timecode.value",
                "dashboard.timecodeString.value",
                "dashboard.transport.timecode.value"
            ])

            // If the composition payload doesn't expose transport fields, try a secondary probe.
            // Throttle this so we don't double-request every poll.
            if state == nil || timecode == nil {
                let now = Date()

                // If we already determined transport endpoints are unavailable for this Resolume build,
                // never probe again this run.
                if transportProbePermanentlyUnavailable {
                    if state == nil { state = transportProbeCache.state }
                    if timecode == nil { timecode = transportProbeCache.timecode }
                }
                // If we previously learned transport endpoints are unavailable (all 404),
                // don't keep probing every poll.
                else if let disabledUntil = transportProbeDisabledUntil, now < disabledUntil {
                    if state == nil { state = transportProbeCache.state }
                    if timecode == nil { timecode = transportProbeCache.timecode }
                } else {
                    let shouldProbe = (lastTransportProbeAt == nil) || (now.timeIntervalSince(lastTransportProbeAt!) > 1.0)
                    if shouldProbe {
                        lastTransportProbeAt = now
                        let probed = await probeTransportFields(endpoint: endpoint)
                        transportProbeCache = probed
                        if state == nil { state = probed.state }
                        if timecode == nil { timecode = probed.timecode }
                    } else {
                        // Use last known probe values if we recently checked.
                        if state == nil { state = transportProbeCache.state }
                        if timecode == nil { timecode = transportProbeCache.timecode }
                    }
                }
            }

            let summaries = buildLayerSummaries(from: dict)
            if layerSummaries != summaries.layers {
                layerSummaries = summaries.layers
            }
            if activeClipSummaries != summaries.activeClips {
                activeClipSummaries = summaries.activeClips
            }

            compositionFields = (name ?? "—", bpm, state, timecode)

            // Throttled diagnostics so we can see what the endpoint is actually returning.
            // - Always logs *occasionally* when the key fields we care about are missing.
            // - Logs more verbosely when Show Debug JSON Preview is enabled.
            let now = Date()
            let missingCount = [bpm, state, timecode].filter { $0 == nil }.count
            let shouldLogNow = (lastCompositionLogAt == nil) || (now.timeIntervalSince(lastCompositionLogAt!) > 5)

            // Build a small signature so we don't spam identical lines.
            let signature = "name=\(name ?? "—")|bpm=\(bpm ?? "—")|state=\(state ?? "—")|tc=\(timecode ?? "—")"

            if config.showDebugJSONPreview {
                // When debug is enabled, log every poll (but still keep it compact).
                print("[ResolumeModule] Composition fields (debug): \(signature)")
            } else if missingCount > 0 && shouldLogNow {
                lastCompositionLogAt = now

                let topKeys = dict.keys.sorted().prefix(30).joined(separator: ", ")
                print("[ResolumeModule] Composition fields missing (\(missingCount)) from \(urlString)")
                print("[ResolumeModule]   extracted: \(signature)")
                print("[ResolumeModule]   top-level keys: \(topKeys)")
                // Include a small excerpt of the payload so we can spot transport/timecode fields
                // without requiring the full debug preview UI toggle.
                let excerpt = prettyJSONString(from: data, maxChars: 1200)
                    .replacingOccurrences(of: "\n", with: " ")
                print("[ResolumeModule]   json excerpt: \(excerpt)")
                // Surface keys under common containers so we can find play/timecode quickly.
                if let master = dict["master"] as? [String: Any] {
                    let mk = master.keys.sorted().prefix(40).joined(separator: ", ")
                    print("[ResolumeModule]   master keys: \(mk)")
                }
                if let dashboard = dict["dashboard"] as? [String: Any] {
                    let dk = dashboard.keys.sorted().prefix(40).joined(separator: ", ")
                    print("[ResolumeModule]   dashboard keys: \(dk)")
                }
                if let selected = dict["selected"] as? [String: Any] {
                    let sk = selected.keys.sorted().prefix(40).joined(separator: ", ")
                    print("[ResolumeModule]   selected keys: \(sk)")
                }

                // Try to surface likely candidates for bpm/state/timecode without printing the whole JSON.
                let bpmCandidates = diagnosticLeafMatches(dict, keyMatches: { $0.lowercased().contains("bpm") || $0.lowercased().contains("tempo") })
                if !bpmCandidates.isEmpty {
                    let lines = bpmCandidates.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
                    print("[ResolumeModule]   bpm candidates: \(lines)")
                }

                let playCandidates = diagnosticLeafMatches(dict, keyMatches: { k in
                    let l = k.lowercased()

                    if l.hasPrefix("display") || l.contains("display_") || l.contains("displayname")
                        || l.contains("display_name") || l.contains("displayunits") || l.contains("display_units") {
                        return false
                    }

                    if l == "playing" || l == "isplaying" || l == "paused" || l == "ispaused" || l == "running" || l == "isrunning" {
                        return true
                    }

                    // Broader keywords
                    if l.contains("play") || l.contains("pause") || l.contains("stop") { return true }
                    if l.contains("transport") || l.contains("playback") { return true }
                    if l.contains("state") || l.contains("status") || l.contains("mode") { return true }
                    if l == "speed" { return true }

                    return false
                })
                if !playCandidates.isEmpty {
                    let lines = playCandidates.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
                    print("[ResolumeModule]   state candidates: \(lines)")
                }

                let tcCandidates = diagnosticLeafMatches(dict, keyMatches: { k in
                    let l = k.lowercased()

                    // Skip file metadata keys that commonly include durations.
                    if l.contains("fileinfo") { return false }

                    if l.hasPrefix("display") || l.contains("display_") || l.contains("displayname")
                        || l.contains("display_name") || l.contains("displayunits") || l.contains("display_units") {
                        return false
                    }

                    if l.contains("timecode") || l.contains("smpte") || l == "tc" { return true }

                    // Broader timeline/progress/time keys
                    if l.contains("timeline") || l.contains("playhead") || l.contains("position") { return true }
                    if l.contains("time") || l.contains("clock") || l.contains("elapsed") { return true }
                    // Avoid treating clip durations as timecode.
                    if l.contains("duration") { return false }

                    if l == "frame" || l == "frames" || l.contains("frame_") || l.contains("framecount") || l.contains("frame_count") {
                        return true
                    }

                    return false
                })
                if !tcCandidates.isEmpty {
                    let lines = tcCandidates.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
                    print("[ResolumeModule]   timecode candidates: \(lines)")
                }
            }
        } catch {
            // If fetch/parse fails, keep name but clear dynamics.
            compositionFields = (resolvedProfileName ?? connection.snapshot.compositionName ?? "—", nil, nil, nil)

            let now = Date()
            let shouldLogNow = (lastCompositionLogAt == nil) || (now.timeIntervalSince(lastCompositionLogAt!) > 5)

            if config.showDebugJSONPreview {
                compositionDebugPreview = "Request failed for \(urlString)\n\n\(error.localizedDescription)"
                print("[ResolumeModule] Composition request FAILED for \(urlString): \(error)")
            } else {
                compositionDebugPreview = nil
                if shouldLogNow {
                    lastCompositionLogAt = now
                    print("[ResolumeModule] Composition request FAILED for \(urlString): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Transport probe (state/timecode)

    @MainActor
    private func probeTransportFields(endpoint: ResolumeEndpoint) async -> (state: String?, timecode: String?) {
        // Try a handful of likely endpoints. We don't know which ones your Resolume build exposes,
        // so we probe a few and extract common keys.
        let candidates: [String] = [
            "/api/v1/transport",
            "/api/v1/transport/state",
            "/api/v1/transport/timecode",
            "/api/v1/transport/play",
            "/api/v1/composition/transport",
            "/api/v1/timecode",
            "/api/v1/composition/timecode",
            "/api/v1/master",
            "/api/v1/composition/master",
            "/api/v1/dashboard",
            "/api/v1/selected"
        ]

        // Track statuses so we can see which endpoints exist (200) vs. missing/blocked (404/401/etc.)
        var attempts: [(String, Int?)] = []

        for path in candidates {
            var p = path
            if !p.hasPrefix("/") { p = "/" + p }
            let urlString = "http://\(endpoint.host):\(endpoint.port)\(p)"
            guard let url = URL(string: urlString) else { continue }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                attempts.append((urlString, statusCode))

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    continue
                }

                let obj = try JSONSerialization.jsonObject(with: data, options: [])

                // Some endpoints may return a dict, others arrays; handle dict-only for now.
                guard let dict = obj as? [String: Any] else { continue }

                // State
                var state: String? = nil
                if let playing = extractBool(dict, paths: [
                    "playing",
                    "isPlaying",
                    "transport.playing",
                    "transport.isPlaying",
                    "master.playing",
                    "master.isPlaying",
                    "composition.playing",
                    "composition.isPlaying",
                    "playing.value",
                    "isPlaying.value",
                    "transport.playing.value",
                    "transport.isPlaying.value",
                    "master.playing.value",
                    "master.isPlaying.value"
                ]) {
                    state = playing ? "Playing" : "Stopped"
                } else if let s = extractString(dict, paths: [
                    "state",
                    "transport.state",
                    "master.state",
                    "composition.state"
                ]) {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        state = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
                    }
                }

                // Timecode
                let tc = extractString(dict, paths: [
                    "timecode",
                    "timecodeString",
                    "transport.timecode",
                    "transport.timecodeString",
                    "master.timecode",
                    "master.timecodeString",
                    "composition.timecode",
                    "composition.timecodeString",
                    "timecode.value",
                    "timecodeString.value",
                    "transport.timecode.value",
                    "transport.timecodeString.value"
                ])

                // If we found either, return.
                if state != nil || tc != nil {
                    print("[ResolumeModule] Transport probe hit: \(urlString) state=\(state ?? "—") tc=\(tc ?? "—")")
                    return (state: state, timecode: tc)
                }
            } catch {
                // If the request failed (DNS/timeout/etc.), record the attempt without a status.
                if attempts.last?.0 != urlString {
                    attempts.append((urlString, nil))
                }
                continue
            }
        }
        // If every candidate came back 404, this Resolume build likely doesn't expose transport endpoints.
        // Disable probing briefly to avoid log spam / extra requests, and also set a permanent flag for this run.
        if !attempts.isEmpty {
            let codes = attempts.compactMap { $0.1 }
            if !codes.isEmpty, codes.allSatisfy({ $0 == 404 }) {
                transportProbeDisabledUntil = Date().addingTimeInterval(60)
                transportProbePermanentlyUnavailable = true
                print("[ResolumeModule] Transport endpoints unavailable (all 404). Disabling transport probe for this run.")
                // Don’t also print the miss list when we already know every endpoint is 404.
                return (state: nil, timecode: nil)
            }
        }

        // Miss: print a compact list of what we tried and what HTTP status came back.
        if !attempts.isEmpty {
            let compact = attempts.prefix(12).map { url, code in
                "\(url) -> \(code.map(String.init) ?? "?")"
            }.joined(separator: " | ")
            print("[ResolumeModule] Transport probe miss. Tried: \(compact)")
        }

        return (state: nil, timecode: nil)
    }

    private func prettyJSONString(from data: Data, maxChars: Int) -> String {
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            let s = String(data: pretty, encoding: .utf8) ?? ""
            if maxChars > 0, s.count > maxChars {
                return String(s.prefix(maxChars))
            }
            return s
        } catch {
            let s = String(data: data, encoding: .utf8) ?? ""
            if maxChars > 0, s.count > maxChars {
                return String(s.prefix(maxChars))
            }
            return s
        }
    }

    // MARK: - Lightweight JSON extraction helpers

    /// Recursively collects leaf values for keys matching a predicate, returning (path, valueString).
    /// Used for diagnostics when expected fields are missing.
    private func diagnosticLeafMatches(
        _ any: Any,
        path: String = "",
        keyMatches: (String) -> Bool,
        maxResults: Int = 12
    ) -> [(String, String)] {
        var results: [(String, String)] = []

        func addResult(_ p: String, _ v: String) {
            guard results.count < maxResults else { return }
            results.append((p, v))
        }

        func walk(_ node: Any, _ currentPath: String) {
            if results.count >= maxResults { return }

            if let d = node as? [String: Any] {
                for (k, v) in d {
                    if results.count >= maxResults { break }
                    let nextPath = currentPath.isEmpty ? k : currentPath + "." + k
                    if keyMatches(k) {
                        if let s = v as? String {
                            addResult(nextPath, s)
                        } else if let n = v as? NSNumber {
                            addResult(nextPath, n.stringValue)
                        } else if let b = v as? Bool {
                            addResult(nextPath, b ? "true" : "false")
                        }
                    }
                    walk(v, nextPath)
                }
            } else if let a = node as? [Any] {
                for (idx, v) in a.enumerated() {
                    if results.count >= maxResults { break }
                    let nextPath = currentPath + "[\(idx)]"
                    walk(v, nextPath)
                }
            }
        }

        walk(any, path)
        return results
    }

    // MARK: - Snapshot JSON access (avoid relying on truncated previews)

    private func snapshotJSONData() -> Data? {
        // 1) If the snapshot already exposes Data, prefer it.
        if let d = mirrorExtractData(connection.snapshot, keys: [
            "rawJSONData",
            "lastJSONData",
            "jsonData",
            "payloadData",
            "rawData"
        ]) {
            return d
        }

        // 2) If the snapshot exposes a full JSON string, use it.
        if let s = mirrorExtractString(connection.snapshot, keys: [
            "rawJSONString",
            "rawJSON",
            "jsonString",
            "payloadString"
        ]), let d = s.data(using: .utf8) {
            return d
        }

        // 3) Fall back to the preview string (may be truncated / invalid JSON)
        if let s = connection.snapshot.rawJSONPreview, let d = s.data(using: .utf8) {
            // Log so we know we're parsing a potentially-truncated representation.
            print("[ResolumeModule] Composition parse: using rawJSONPreview (len=\(s.count))")
            return d
        }

        return nil
    }

    private func mirrorExtractString(_ any: Any, keys: [String]) -> String? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label), let v = child.value as? String {
                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func mirrorExtractData(_ any: Any, keys: [String]) -> Data? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label) {
                if let v = child.value as? Data { return v }
                if let v = child.value as? NSData { return v as Data }
            }
        }
        return nil
    }

    private func extractValue(_ dict: [String: Any], path: String) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = dict
        for p in parts {
            if let d = current as? [String: Any], let next = d[p] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    private func extractString(_ dict: [String: Any], paths: [String]) -> String? {
        for p in paths {
            if let v = extractValue(dict, path: p) as? String {
                let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s }
            }
        }
        return nil
    }

    private func extractDouble(_ dict: [String: Any], paths: [String]) -> Double? {
        for p in paths {
            let v = extractValue(dict, path: p)
            if let d = v as? Double { return d }
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String, let d = Double(s) { return d }
        }
        return nil
    }

    private func extractBool(_ dict: [String: Any], paths: [String]) -> Bool? {
        for p in paths {
            let v = extractValue(dict, path: p)
            if let b = v as? Bool { return b }
            if let n = v as? NSNumber { return n.boolValue }
            if let s = v as? String {
                let lowered = s.lowercased()
                if lowered == "true" { return true }
                if lowered == "false" { return false }
            }
        }
        return nil
    }
}

// MARK: - Settings View (for DashboardTileEditView)

public struct ResolumeModuleSettingsView: View {
    @Binding public var config: ResolumeModuleConfig

    private var profilesStore: ResolumeProfilesStore { ResolumeConnection.shared.profilesStore }

    public init(config: Binding<ResolumeModuleConfig>) {
        self._config = config
    }

    public var body: some View {
        GroupBox("Resolume") {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    Text("Profile")

                    Picker("", selection: Binding<UUID>(
                        get: {
                            // Force a real profile selection (no manual mode).
                            if let id = config.profileID { return id }
                            if let fallback = profilesStore.firstEnabledProfileID() { return fallback }
                            // If there are no profiles, generate a stable placeholder; picker will be disabled.
                            return profilesStore.profiles.first?.id ?? UUID()
                        },
                        set: { newValue in
                            config.profileID = newValue
                        }
                    )) {
                        ForEach(profilesStore.profiles, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(profilesStore.profiles.isEmpty)

                    Spacer()

                    // Show resolved endpoint as a hint
                    if let ep = profilesStore.resolvedEndpoint(for: config.profileID ?? profilesStore.firstEnabledProfileID()) {
                        Text(ep.display)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear {
                    // If nothing is set yet, default to the first enabled profile.
                    if config.profileID == nil {
                        config.profileID = profilesStore.firstEnabledProfileID() ?? profilesStore.profiles.first?.id
                    }
                }


                HStack {
                    Text("Display")
                    Picker("", selection: $config.displayMode) {
                        ForEach(ResolumeDisplayMode.allCases.filter { $0 != .customPath }) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Poll")
                    Slider(value: $config.pollIntervalSeconds, in: 0.2...5.0, step: 0.1)
                    Text(String(format: "%.1fs", config.pollIntervalSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Toggle("Show title", isOn: $config.showTitle)
                Toggle("Show debug JSON preview", isOn: $config.showDebugJSONPreview)
                Toggle("Show clip thumbnails", isOn: $config.showThumbnails)

                if config.showThumbnails {
                    HStack {
                        Text("Thumbnail size")
                        Slider(value: $config.thumbnailSize, in: 24...96, step: 2)
                        Text(String(format: "%.0f", config.thumbnailSize))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                Text("Tip: Start with “Composition” then expand to Layers/Clips once you confirm the exact endpoints you want to render.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private var numberFormatter: NumberFormatter {
        let nf = NumberFormatter()
        nf.minimum = 1
        nf.maximum = 65535
        nf.maximumFractionDigits = 0
        return nf
    }
}

// MARK: - ResolumeProfilesStore helpers (mirror-safe)

private extension ResolumeProfilesStore {
    /// Returns a user-facing name for the profile ID if we can find it.
    func resolvedProfileName(for id: UUID?) -> String? {
        guard let id else { return nil }
        guard let profileAny = profiles.first(where: { _profileHasID($0, id: id) }) else { return nil }
        return _extractString(profileAny, keys: ["name", "profileName", "title", "label", "displayName"])
    }

    /// Returns an endpoint for the profile ID if we can find host/ip/address + port.
    func resolvedEndpoint(for id: UUID?) -> ResolumeEndpoint? {
        guard let id else { return nil }
        guard let profileAny = profiles.first(where: { _profileHasID($0, id: id) }) else { return nil }

        // Host/IP/address (try common keys first)
        var host = _extractString(profileAny, keys: ["host", "ip", "address", "hostname", "ipAddress", "server", "baseURL", "baseUrl", "url", "restURL", "restUrl", "endpointString", "hostPort"])
            ?? _extractStringFromNestedEndpoint(profileAny)

        // If we still don't have a host, try to find any "host:port" string anywhere on the profile.
        var inferredPortFromString: Int? = nil
        if host == nil {
            if let hp = _extractHostPortFromAnyString(profileAny) {
                host = hp.host
                inferredPortFromString = hp.port
            }
        }

        // Some stores may keep a combined string like "10.0.0.5:8080" in one of the host-ish fields.
        if let h = host, h.contains(":") {
            let parts = h.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                host = parts[0]
                if inferredPortFromString == nil {
                    inferredPortFromString = Int(parts[1])
                }
            }
        }

        // Port
        var port = _extractInt(profileAny, keys: ["port", "httpPort", "restPort", "restAPIShorthandPort", "apiPort"])
            ?? _extractIntFromNestedEndpoint(profileAny)

        // If we inferred a port from a "host:port" string, use it as a fallback.
        if port == nil {
            port = inferredPortFromString
        }

        guard let host, !host.isEmpty, let port else { return nil }
        return ResolumeEndpoint(host: host, port: port)
    }

    /// Best-effort: return the first profile marked enabled/active.
    /// If the store doesn’t expose an enabled flag, this will return the first profile’s ID.
    func firstEnabledProfileID() -> UUID? {
        // Prefer an enabled/active profile if that flag exists.
        if let any = profiles.first(where: { _profileIsEnabled($0) }) {
            return _extractUUID(any, keys: ["id", "uuid", "profileID"])
        }
        // Otherwise, just take the first.
        guard let first = profiles.first else { return nil }
        return _extractUUID(first, keys: ["id", "uuid", "profileID"])
    }

    func _profileIsEnabled(_ any: Any) -> Bool {
        // Common boolean fields
        if let v = _extractBool(any, keys: ["enabled", "isEnabled", "active", "isActive"]) {
            return v
        }
        // Sometimes stored as an Int (0/1)
        if let i = _extractInt(any, keys: ["enabled", "isEnabled", "active", "isActive"]) {
            return i != 0
        }
        return false
    }

    func _extractBool(_ any: Any, keys: [String]) -> Bool? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label) {
                if let v = child.value as? Bool { return v }
            }
        }
        return nil
    }

    // MARK: - Mirror helpers

    func _profileHasID(_ any: Any, id: UUID) -> Bool {
        if let v = _extractUUID(any, keys: ["id", "uuid", "profileID"]) {
            return v == id
        }
        return false
    }

    func _extractUUID(_ any: Any, keys: [String]) -> UUID? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label), let v = child.value as? UUID { return v }
        }
        return nil
    }

    func _extractString(_ any: Any, keys: [String]) -> String? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label), let v = child.value as? String { return v }
        }
        return nil
    }

    func _extractInt(_ any: Any, keys: [String]) -> Int? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label) {
                if let v = child.value as? Int { return v }
                if let v = child.value as? Int16 { return Int(v) }
                if let v = child.value as? Int32 { return Int(v) }
                if let v = child.value as? Int64 { return Int(v) }
                if let v = child.value as? UInt16 { return Int(v) }
                if let v = child.value as? UInt32 { return Int(v) }
                if let v = child.value as? UInt64 { return Int(v) }
            }
        }
        return nil
    }

    func _extractStringFromNestedEndpoint(_ any: Any) -> String? {
        // If the profile stores an `endpoint` struct/class, try to pull host/ip/address from it.
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if label.lowercased().contains("endpoint") {
                return _extractString(child.value, keys: ["host", "ip", "address", "hostname", "ipAddress", "server", "baseURL", "baseUrl", "url"])
            }
        }
        return nil
    }

    func _extractIntFromNestedEndpoint(_ any: Any) -> Int? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let label = child.label else { continue }
            if label.lowercased().contains("endpoint") {
                return _extractInt(child.value, keys: ["port", "httpPort", "restPort", "apiPort"])
            }
        }
        return nil
    }

    /// Attempts to find an IPv4 host:port pair from ANY string property on the profile.
    /// This is a safety net for when the stored model uses unexpected property names.
    func _extractHostPortFromAnyString(_ any: Any) -> (host: String, port: Int)? {
        let m = Mirror(reflecting: any)
        for child in m.children {
            guard let s = child.value as? String else { continue }

            // Fast path: contains something that looks like "x.x.x.x:port"
            // We avoid regex here for simplicity; just validate parts.
            if let hp = _parseHostPort(from: s) {
                return hp
            }
        }

        // Also check a single nested object named like "endpoint" or "restEndpoint".
        for child in m.children {
            guard let label = child.label?.lowercased(), label.contains("endpoint") else { continue }
            let nested = Mirror(reflecting: child.value)
            for nestedChild in nested.children {
                if let s = nestedChild.value as? String, let hp = _parseHostPort(from: s) {
                    return hp
                }
            }
        }

        return nil
    }

    func _parseHostPort(from s: String) -> (host: String, port: Int)? {
        // Strip scheme if present
        var candidate = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("http://") {
            candidate = String(candidate.dropFirst("http://".count))
        } else if candidate.hasPrefix("https://") {
            candidate = String(candidate.dropFirst("https://".count))
        }

        // Chop any path/query
        if let slash = candidate.firstIndex(of: "/") {
            candidate = String(candidate[..<slash])
        }
        if let q = candidate.firstIndex(of: "?") {
            candidate = String(candidate[..<q])
        }

        let parts = candidate.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let host = parts[0]
        guard let port = Int(parts[1]), port > 0, port <= 65535 else { return nil }

        // Very light IPv4-ish validation (allow hostnames too, but ensure it's not empty)
        guard !host.isEmpty else { return nil }
        return (host, port)
    }
}
