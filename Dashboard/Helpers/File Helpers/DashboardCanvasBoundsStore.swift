//
//  DashboardCanvasBoundsStore.swift
//  Relay
//
//  Created by David Bullard on 2/2/26.
//

import Foundation
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Stores the user-defined “document size” for the dashboard canvas.
/// Think Photoshop artboard: content lives in document coordinates; the window is just a viewport.
///
/// Notes:
/// - Uses AppStorage so it persists per-install.
/// - Provides sensible presets and clamps to avoid absurd sizes.
/// - Also owns shared prompt-state + a reusable prompt view for choosing canvas bounds.
@MainActor
final class DashboardCanvasBoundsStore: ObservableObject {
    static let shared = DashboardCanvasBoundsStore()

    private static let canvasSizeMigrationVersion = 2

    // Persisted values (AppStorage works on macOS/iOS)
    @AppStorage("dashboard_canvas_width") private var storedWidth: Double = 1920
    @AppStorage("dashboard_canvas_height") private var storedHeight: Double = 1080
    @AppStorage("dashboard_canvas_size_migration_version") private var migrationVersion: Int = 0

    /// Minimum/maximum allowed document size (points).
    static let minSize = CGSize(width: 640, height: 360)
    static let maxSize = CGSize(width: 20000, height: 20000)

    var size: CGSize {
        get {
            CGSize(
                width: clamp(storedWidth, min: Self.minSize.width, max: Self.maxSize.width),
                height: clamp(storedHeight, min: Self.minSize.height, max: Self.maxSize.height)
            )
        }
        set {
            storedWidth = clamp(newValue.width, min: Self.minSize.width, max: Self.maxSize.width)
            storedHeight = clamp(newValue.height, min: Self.minSize.height, max: Self.maxSize.height)
            objectWillChange.send()
        }
    }

    enum BuiltinPreset: String, CaseIterable, Identifiable {
        case screen
        case p1280x720
        case p1920x1080
        case p2560x1440
        case p3840x2160
        case p1080x1920
        case macbookAir13
        case macbookPro14
        case macbookPro16
        case imac24
        case studioDisplay
        case proDisplayXDR
        case ipadMini
        case ipad11
        case ipad129
        case ipad10

        var id: String { rawValue }

        var label: String {
            switch self {
            case .screen: return "Screen Bounds"
            case .p1280x720: return "1280×720"
            case .p1920x1080: return "1920×1080"
            case .p2560x1440: return "2560×1440"
            case .p3840x2160: return "3840×2160"
            case .p1080x1920: return "1080×1920 (Portrait)"
            case .macbookAir13: return "MacBook Air 13\""
            case .macbookPro14: return "MacBook Pro 14\""
            case .macbookPro16: return "MacBook Pro 16\""
            case .imac24: return "iMac 24\""
            case .studioDisplay: return "Studio Display"
            case .proDisplayXDR: return "Pro Display XDR"
            case .ipadMini: return "iPad mini"
            case .ipad11: return "iPad 11\""
            case .ipad129: return "iPad 12.9\""
            case .ipad10: return "iPad 10.9\""
            }
        }

        var fixedSize: CGSize? {
            switch self {
            case .screen: return nil
            case .p1280x720: return CGSize(width: 1280, height: 720)
            case .p1920x1080: return CGSize(width: 1920, height: 1080)
            case .p2560x1440: return CGSize(width: 2560, height: 1440)
            case .p3840x2160: return CGSize(width: 3840, height: 2160)
            case .p1080x1920: return CGSize(width: 1080, height: 1920)
            case .macbookAir13: return CGSize(width: 1280, height: 832)
            case .macbookPro14: return CGSize(width: 1512, height: 982)
            case .macbookPro16: return CGSize(width: 1728, height: 1117)
            case .imac24: return CGSize(width: 2240, height: 1260)
            case .studioDisplay: return CGSize(width: 2560, height: 1440)
            case .proDisplayXDR: return CGSize(width: 3008, height: 1692)
            case .ipadMini: return CGSize(width: 1133, height: 744)
            case .ipad11: return CGSize(width: 1194, height: 834)
            case .ipad129: return CGSize(width: 1366, height: 1024)
            case .ipad10: return CGSize(width: 1180, height: 820)
            }
        }
    }

    struct CanvasPreset: Identifiable, Hashable, Codable {
        var id: UUID
        var name: String
        var width: Double
        var height: Double

        init(id: UUID = UUID(), name: String, width: Double, height: Double) {
            self.id = id
            self.name = name
            self.width = width
            self.height = height
        }

        var size: CGSize { CGSize(width: width, height: height) }
        var label: String { "\(name) — \(Int(width))×\(Int(height))" }
    }

    struct PresetOption: Identifiable, Hashable {
        let id: String
        let label: String
        let size: CGSize?
        let isCustom: Bool
        let isUserPreset: Bool
    }

    private let userPresetsKey = "dashboard_canvas_user_presets_v1"
    @Published var userPresets: [CanvasPreset] = [] {
        didSet { saveUserPresets() }
    }

    func presetOptions() -> [PresetOption] {
        var options: [PresetOption] = BuiltinPreset.allCases.map { preset in
            PresetOption(
                id: builtinPresetID(preset),
                label: preset.label,
                size: preset.fixedSize,
                isCustom: false,
                isUserPreset: false
            )
        }

        options.append(contentsOf: userPresets.map { preset in
            PresetOption(
                id: userPresetID(preset.id),
                label: preset.label,
                size: preset.size,
                isCustom: false,
                isUserPreset: true
            )
        })

        options.append(
            PresetOption(
                id: customPresetID,
                label: "Custom…",
                size: nil,
                isCustom: true,
                isUserPreset: false
            )
        )
        return options
    }

    func presetOption(for id: String) -> PresetOption? {
        if id == customPresetID {
            return PresetOption(id: customPresetID, label: "Custom…", size: nil, isCustom: true, isUserPreset: false)
        }
        if let builtin = builtinPreset(from: id) {
            return PresetOption(
                id: builtinPresetID(builtin),
                label: builtin.label,
                size: builtin.fixedSize,
                isCustom: false,
                isUserPreset: false
            )
        }
        if let presetID = userPresetUUID(from: id),
           let preset = userPresets.first(where: { $0.id == presetID }) {
            return PresetOption(
                id: userPresetID(preset.id),
                label: preset.label,
                size: preset.size,
                isCustom: false,
                isUserPreset: true
            )
        }
        return nil
    }

    func applyPresetOption(_ option: PresetOption) {
        if let s = option.size {
            size = s
        } else if option.id == customPresetID {
            size = resolvedPromptCanvasSize()
        } else if let builtin = builtinPreset(from: option.id), builtin == .screen {
            size = currentScreenBoundsSize()
        }
    }

    // MARK: - Screen Bounds

    func currentScreenBoundsSize() -> CGSize {
        #if os(macOS)
        if let s = NSScreen.main {
            return s.frame.size
        }
        return CGSize(width: 1920, height: 1080)
        #else
        // `UIScreen.main` is deprecated (iOS 16+) and, on multi-scene iPads, isn't
        // guaranteed to be the screen this app is actually running on. Resolve the
        // screen through the active window scene instead; this is still the physical
        // display's bounds (the "Screen Bounds" preset is deliberately about matching
        // a monitor/output size, not the app window's size), just not via the
        // deprecated global singleton.
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            return scene.screen.bounds.size
        }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.screen.bounds.size
        }
        return CGSize(width: 1920, height: 1080)
        #endif
    }

    #if os(macOS)
    private func legacyMacDisplayPixelPresetMap() -> [CGSize: CGSize] {
        [
            CGSize(width: 2560, height: 1664): CGSize(width: 1280, height: 832),
            CGSize(width: 3024, height: 1964): CGSize(width: 1512, height: 982),
            CGSize(width: 3456, height: 2234): CGSize(width: 1728, height: 1117),
            CGSize(width: 4480, height: 2520): CGSize(width: 2240, height: 1260),
            CGSize(width: 5120, height: 2880): CGSize(width: 2560, height: 1440),
            CGSize(width: 6016, height: 3384): CGSize(width: 3008, height: 1692),
            CGSize(width: 2266, height: 1488): CGSize(width: 1133, height: 744),
            CGSize(width: 2388, height: 1668): CGSize(width: 1194, height: 834),
            CGSize(width: 2732, height: 2048): CGSize(width: 1366, height: 1024),
            CGSize(width: 2360, height: 1640): CGSize(width: 1180, height: 820)
        ]
    }

    private func migratedLegacyCanvasSizeIfNeeded() -> CGSize? {
        let legacySize = CGSize(width: storedWidth, height: storedHeight)

        for (pixelSize, pointSize) in legacyMacDisplayPixelPresetMap() {
            if abs(legacySize.width - pixelSize.width) < 0.5,
               abs(legacySize.height - pixelSize.height) < 0.5 {
                return pointSize
            }
        }

        if let screen = NSScreen.main {
            let pixelLikeSize = CGSize(
                width: screen.frame.width * screen.backingScaleFactor,
                height: screen.frame.height * screen.backingScaleFactor
            )
            if abs(legacySize.width - pixelLikeSize.width) < 0.5,
               abs(legacySize.height - pixelLikeSize.height) < 0.5 {
                return screen.frame.size
            }
        }

        return nil
    }
    #endif

    private func runCanvasSizeMigrationIfNeeded() {
        guard migrationVersion < Self.canvasSizeMigrationVersion else { return }

        #if os(macOS)
        if let migratedSize = migratedLegacyCanvasSizeIfNeeded() {
            storedWidth = migratedSize.width
            storedHeight = migratedSize.height
            promptWidth = migratedSize.width
            promptHeight = migratedSize.height
        }
        #endif

        migrationVersion = Self.canvasSizeMigrationVersion
    }

    // MARK: - Prompt State (shared UI)

    enum Purpose: Equatable {
        case newDashboard
        case resizeCurrent
    }

    @Published var promptPresetID: String = "builtin:p1920x1080"
    @Published var promptWidth: Double = 1920
    @Published var promptHeight: Double = 1080

    /// Seed the prompt fields from the current canvas bounds.
    func seedPromptFromCurrentCanvas(width: Double, height: Double, defaultPresetID: String = "custom") {
        promptWidth = (width > 0) ? width : 1920
        promptHeight = (height > 0) ? height : 1080
        promptPresetID = defaultPresetID

        // If a fixed preset is chosen, sync fields to it.
        syncPromptFieldsToPresetIfNeeded()
    }

    /// Keep width/height fields in sync when using a fixed preset (including screen).
    func syncPromptFieldsToPresetIfNeeded() {
        guard let option = presetOption(for: promptPresetID) else { return }
        guard !option.isCustom else { return }

        let s: CGSize = {
            if let builtin = builtinPreset(from: option.id), builtin == .screen {
                return currentScreenBoundsSize()
            }
            return option.size ?? CGSize(width: 1920, height: 1080)
        }()

        promptWidth = s.width
        promptHeight = s.height
    }

    /// Resolved size from the prompt (screen/fixed/custom) with clamping.
    func resolvedPromptCanvasSize() -> CGSize {
        if let option = presetOption(for: promptPresetID) {
            if let builtin = builtinPreset(from: option.id), builtin == .screen {
                return currentScreenBoundsSize()
            }
            if let s = option.size {
                return s
            }
        }

        // Clamp to the same bounds as `size`.
        let w = clamp(promptWidth, min: Self.minSize.width, max: Self.maxSize.width)
        let h = clamp(promptHeight, min: Self.minSize.height, max: Self.maxSize.height)
        return CGSize(width: w, height: h)
    }

    func addUserPreset(name: String, width: Double, height: Double) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let preset = CanvasPreset(name: trimmed, width: width, height: height)
        userPresets.append(preset)
        return preset.id
    }

    func removeUserPreset(id: UUID) {
        userPresets.removeAll { $0.id == id }
        if promptPresetID == userPresetID(id) {
            promptPresetID = customPresetID
        }
    }

    func selectUserPreset(id: UUID) {
        promptPresetID = userPresetID(id)
    }

    func selectedUserPresetID() -> UUID? {
        userPresetUUID(from: promptPresetID)
    }

    private func loadUserPresets() {
        guard let raw = UserDefaults.standard.string(forKey: userPresetsKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CanvasPreset].self, from: data)
        else {
            userPresets = []
            return
        }
        userPresets = decoded
    }

    private func saveUserPresets() {
        guard let data = try? JSONEncoder().encode(userPresets),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        UserDefaults.standard.set(raw, forKey: userPresetsKey)
    }

    private let customPresetID = "custom"

    fileprivate func builtinPresetID(_ preset: BuiltinPreset) -> String {
        "builtin:\(preset.rawValue)"
    }

    private func userPresetID(_ id: UUID) -> String {
        "user:\(id.uuidString)"
    }

    fileprivate func builtinPreset(from id: String) -> BuiltinPreset? {
        guard id.hasPrefix("builtin:") else { return nil }
        let raw = id.replacingOccurrences(of: "builtin:", with: "")
        return BuiltinPreset(rawValue: raw)
    }

    private func userPresetUUID(from id: String) -> UUID? {
        guard id.hasPrefix("user:") else { return nil }
        let raw = id.replacingOccurrences(of: "user:", with: "")
        return UUID(uuidString: raw)
    }

    private func clamp(_ v: Double, min: CGFloat, max: CGFloat) -> Double {
        Double(Swift.min(max, Swift.max(min, CGFloat(v))))
    }

    init() {
        loadUserPresets()
        runCanvasSizeMigrationIfNeeded()

        let widthKey = "dashboard_canvas_width"
        let heightKey = "dashboard_canvas_height"
        let hasStoredWidth = UserDefaults.standard.object(forKey: widthKey) != nil
        let hasStoredHeight = UserDefaults.standard.object(forKey: heightKey) != nil

        // First launch: seed to current screen bounds instead of the 1920x1080 default.
        if !hasStoredWidth && !hasStoredHeight {
            let screenSize = currentScreenBoundsSize()
            storedWidth = screenSize.width
            storedHeight = screenSize.height
            promptWidth = screenSize.width
            promptHeight = screenSize.height
            promptPresetID = builtinPresetID(.screen)
        }

        if userPresets.isEmpty == false, promptPresetID == "builtin:p1920x1080" {
            promptPresetID = customPresetID
        }
    }
}

private struct PresetCard: View {
    let title: String
    let detail: String
    let size: CGSize?
    let isSelected: Bool
    let action: () -> Void

    private var boxSize: CGSize {
        let maxBox = CGSize(width: 70, height: 44)
        guard let size else {
            return CGSize(width: maxBox.width * 0.9, height: maxBox.height * 0.6)
        }
        let scale = min(maxBox.width / max(size.width, 1), maxBox.height / max(size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 84, height: 52)
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                        .frame(width: boxSize.width, height: boxSize.height)
                    Text(detail.isEmpty ? title : detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(8)
            .frame(minWidth: 108, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Prompt UI

struct DashboardCanvasSizePromptView: View {
    @ObservedObject var store: DashboardCanvasBoundsStore
    @Binding var isPresented: Bool
    let purpose: DashboardCanvasBoundsStore.Purpose
    let onResetToDocumentDefault: (() -> Void)?
    let onApply: (CGSize) -> Void

    init(
        store: DashboardCanvasBoundsStore,
        isPresented: Binding<Bool>,
        purpose: DashboardCanvasBoundsStore.Purpose,
        onResetToDocumentDefault: (() -> Void)? = nil,
        onApply: @escaping (CGSize) -> Void
    ) {
        self.store = store
        self._isPresented = isPresented
        self.purpose = purpose
        self.onResetToDocumentDefault = onResetToDocumentDefault
        self.onApply = onApply
    }

    private enum Field: Hashable {
        case width
        case height
    }

    @FocusState private var focusedField: Field?
    @State private var lastFocusedField: Field? = nil
    @State private var newPresetName: String = ""
    @State private var isSavingPreset: Bool = false
    @State private var selectedTab: PresetTab = .common

    private enum PresetTab: String, CaseIterable, Identifiable {
        case common = "Common"
        case appleDisplays = "Apple Displays"
        case ipad = "iPad"
        case saved = "Saved"
        case custom = "Custom"

        var id: String { rawValue }
    }

    private var commonPresets: [DashboardCanvasBoundsStore.BuiltinPreset] {
        [.screen, .p1920x1080, .p2560x1440, .p3840x2160, .p1080x1920, .p1280x720]
    }

    private func availableTabs(hasSaved: Bool) -> [PresetTab] {
        var tabs: [PresetTab] = [.common, .appleDisplays, .ipad]
        if hasSaved {
            tabs.append(.saved)
        }
        tabs.append(.custom)
        return tabs
    }

    private var macPresets: [DashboardCanvasBoundsStore.BuiltinPreset] {
        [.macbookAir13, .macbookPro14, .macbookPro16, .imac24, .studioDisplay, .proDisplayXDR]
    }

    private var ipadPresets: [DashboardCanvasBoundsStore.BuiltinPreset] {
        [.ipadMini, .ipad11, .ipad129, .ipad10]
    }

    private var presetGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), spacing: 12),
            GridItem(.flexible(minimum: 120), spacing: 12),
            GridItem(.flexible(minimum: 120), spacing: 12),
            GridItem(.flexible(minimum: 120), spacing: 12)
        ]
    }

    private func displaySize(for preset: DashboardCanvasBoundsStore.BuiltinPreset) -> CGSize? {
        if preset == .screen {
            return store.currentScreenBoundsSize()
        }
        return preset.fixedSize
    }

    private func sizeLabel(_ size: CGSize?) -> String {
        guard let size else { return "" }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    @ViewBuilder
    private func presetSection(
        title: String,
        presets: [DashboardCanvasBoundsStore.BuiltinPreset],
        selectedID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: presetGridColumns, alignment: .leading, spacing: 12) {
                ForEach(presets, id: \.id) { preset in
                    let id = store.builtinPresetID(preset)
                    let size = displaySize(for: preset)
                    PresetCard(
                        title: preset.label,
                        detail: preset == .screen ? "Matches current display" : sizeLabel(size),
                        size: size,
                        isSelected: selectedID == id
                    ) {
                        store.promptPresetID = id
                    }
                }
            }
        }
    }

    var body: some View {
        let selectedOption = store.presetOption(for: store.promptPresetID)
        let options = store.presetOptions()
        let userOptions = options.filter { $0.isUserPreset }
        let hasSaved = userOptions.isEmpty == false
        let tabs = availableTabs(hasSaved: hasSaved)

        VStack(alignment: .leading, spacing: 12) {
            Text(purpose == .resizeCurrent ? "Change Dashboard Size" : "New Dashboard")
                .font(.headline)

            HStack(alignment: .top, spacing: 18) {
                leftPresetPanel(tabs: tabs, hasSaved: hasSaved, userOptions: userOptions)
                rightPresetPanel(selectedOption: selectedOption)
            }
            .onAppear {
                store.syncPromptFieldsToPresetIfNeeded()
                if !hasSaved, selectedTab == .saved {
                    selectedTab = .common
                }
            }
            .onChange(of: store.promptPresetID, initial: false) { _, _ in
                store.syncPromptFieldsToPresetIfNeeded()
            }
            .onChange(of: store.promptWidth, initial: false) { _, _ in
                if store.promptPresetID != "custom" {
                    store.promptPresetID = "custom"
                }
            }
            .onChange(of: store.promptHeight, initial: false) { _, _ in
                if store.promptPresetID != "custom" {
                    store.promptPresetID = "custom"
                }
            }
            .onChange(of: userOptions.count, initial: false) { _, newCount in
                if newCount == 0, selectedTab == .saved {
                    selectedTab = .common
                }
            }

            if selectedOption?.isUserPreset == true, let userID = store.selectedUserPresetID() {
                Button("Delete Preset", role: .destructive) {
                    store.removeUserPreset(id: userID)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 880, minHeight: 520)
        .onAppear {
            SharedSecondTicker.shared.setPaused(true)
            if selectedOption?.isCustom == true {
                focusedField = .width
                lastFocusedField = .width
            }
        }
        .onChange(of: store.promptPresetID, initial: false) { _, _ in
            if store.promptPresetID == "custom", focusedField == nil {
                focusedField = .width
                lastFocusedField = .width
            }
        }
        .onChange(of: focusedField, initial: false) { _, newValue in
            if let newValue {
                lastFocusedField = newValue
                return
            }
        }
        .onDisappear {
            SharedSecondTicker.shared.setPaused(false)
        }
    }

    @ViewBuilder
    private func leftPresetPanel(
        tabs: [PresetTab],
        hasSaved: Bool,
        userOptions: [DashboardCanvasBoundsStore.PresetOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Presets", selection: $selectedTab) {
                ForEach(tabs) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case .common:
                        presetSection(title: "Common", presets: commonPresets, selectedID: store.promptPresetID)
                    case .appleDisplays:
                        presetSection(title: "Apple Displays", presets: macPresets, selectedID: store.promptPresetID)
                    case .ipad:
                        presetSection(title: "iPad", presets: ipadPresets, selectedID: store.promptPresetID)
                    case .saved:
                        if hasSaved {
                            LazyVGrid(columns: presetGridColumns, alignment: .leading, spacing: 12) {
                                ForEach(userOptions) { option in
                                    let title = option.label.components(separatedBy: " — ").first ?? option.label
                                    PresetCard(
                                        title: title,
                                        detail: sizeLabel(option.size),
                                        size: option.size,
                                        isSelected: store.promptPresetID == option.id
                                    ) {
                                        store.promptPresetID = option.id
                                    }
                                }
                            }
                        } else {
                            Text("No saved presets yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .custom:
                        LazyVGrid(columns: presetGridColumns, alignment: .leading, spacing: 12) {
                            PresetCard(
                                title: "Custom…",
                                detail: "Set your own size",
                                size: nil,
                                isSelected: store.promptPresetID == "custom"
                            ) {
                                store.promptPresetID = "custom"
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rightPresetPanel(selectedOption: DashboardCanvasBoundsStore.PresetOption?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preset Details")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Width")
                        .font(.caption)
                    TextField("Width", value: $store.promptWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .focused($focusedField, equals: .width)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Height")
                        .font(.caption)
                    TextField("Height", value: $store.promptHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .focused($focusedField, equals: .height)
                }
            }

            HStack(spacing: 8) {
                Button {
                    isSavingPreset = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $isSavingPreset, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save Preset")
                            .font(.headline)
                        TextField("Preset name", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Cancel") {
                                isSavingPreset = false
                            }
                            Spacer()
                            Button("Save") {
                                let size = store.resolvedPromptCanvasSize()
                                if let id = store.addUserPreset(name: newPresetName, width: size.width, height: size.height) {
                                    store.selectUserPreset(id: id)
                                    newPresetName = ""
                                    isSavingPreset = false
                                }
                            }
                            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(12)
                    .frame(width: 220)
                }
            }

            if store.promptPresetID != "custom" {
                Text("Editing size switches to Custom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let s: CGSize = {
                if let option = selectedOption {
                    if let builtin = store.builtinPreset(from: option.id), builtin == .screen {
                        return store.currentScreenBoundsSize()
                    }
                    if let size = option.size {
                        return size
                    }
                }
                return CGSize(width: store.promptWidth, height: store.promptHeight)
            }()

            Text("Selected: \(Int(s.width)) × \(Int(s.height))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }

                Spacer()

                if purpose == .resizeCurrent, let onReset = onResetToDocumentDefault {
                    Button("Use Default") {
                        onReset()
                        isPresented = false
                    }
                    .foregroundStyle(.secondary)
                }

                Button(purpose == .resizeCurrent ? "Apply" : "Create") {
                    let size = store.resolvedPromptCanvasSize()
                    isPresented = false
                    onApply(size)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 220, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }
}
