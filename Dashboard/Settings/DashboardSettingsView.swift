//
//  DashboardSettingsView.swift
//  Relay
//
//  Created by David Bullard on 11/17/25.
//


import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum DashboardSettingsInitialSelection {
    case general
    case audio(AudioInputsConfigView.Tab)
}

/// High-level settings container for the Relay Dashboard.
/// This hosts multiple settings pages (General, Planning Center, etc.).
struct DashboardSettingsView: View {
    private enum SettingsPage: String, CaseIterable, Identifiable {
        case general = "General"
        case audio = "Audio"
        case externalConnections = "External Connections"
        case integrations = "Integrations"
        case devices = "External Devices"
        case controlInputs = "External Control"
        case lan = "Sync & Mirror"
        case access = "Access"
        case help = "Help"
        case preview = "Preview"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .audio: return "mic"
            case .externalConnections: return "link.badge.plus"
            case .integrations: return "key"
            case .devices: return "externaldrive.connected.to.line.below"
            case .lan: return "wifi"
            case .controlInputs: return "dot.radiowaves.left.and.right"
            case .access: return "hand.raised"
            case .help: return "questionmark.circle"
            case .preview: return "testtube.2"
            }
        }

        var tutorialAnchorID: String? {
            switch self {
            case .externalConnections: return "settings.externalConnections"
            case .devices: return "settings.externalDevices"
            case .audio: return "settings.audio"
            default: return nil
            }
        }
    }

    @State private var selection: SettingsPage = .general
    @State private var initialAudioTab: AudioInputsConfigView.Tab
    @Environment(\.dismiss) private var dismiss
#if os(iOS)
    @State private var phoneNavigationPath: [SettingsPage] = []
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
#endif

    init(initialSelection: DashboardSettingsInitialSelection = .general) {
        switch initialSelection {
        case .general:
            _selection = State(initialValue: .general)
            _initialAudioTab = State(initialValue: .measurement)
        case .audio(let tab):
            _selection = State(initialValue: .audio)
            _initialAudioTab = State(initialValue: tab)
        }
    }

    @ViewBuilder
    private func detail(for page: SettingsPage) -> some View {
        switch page {
        case .general:
            GeneralDashboardSettingsPane()
        case .audio:
            AudioInputsConfigView(initialTab: initialAudioTab, presentationStyle: .embedded)
        case .externalConnections:
            ExternalConnectionsSettingsView()
        case .integrations:
            DashboardIntegrationsSettingsView()
        case .devices:
            ExternalDevicesSettingsView()
        case .lan:
            DashboardLANSettingsView()
        case .controlInputs:
            ControlInputsSettingsView()
        case .access:
            DashboardAccessSettingsView()
        case .help:
            DashboardHelpSettingsView()
        case .preview:
            DashboardPreviewSettingsView()
        }
    }

    @ViewBuilder
    private func sidebarLabel(for page: SettingsPage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: page.iconName)
            Text(page.rawValue)
        }
    }

    var body: some View {
#if os(macOS)
        HStack(spacing: 0) {
            // Sidebar
            List(selection: $selection) {
                ForEach(SettingsPage.allCases) { page in
                    sidebarLabel(for: page)
                        .tag(page)
                        .tutorialAnchor(page.tutorialAnchorID ?? "settings.\(page.id)")
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

            Divider()

            // Content area
            VStack(alignment: .leading, spacing: 0) {
                detail(for: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(12)
            }
                .frame(minWidth: 520, minHeight: 520)
        }
        .frame(minWidth: 820, minHeight: 560)
#else
        if isIPad {
            // iPad: two-column layout
            NavigationSplitView {
                List {
                    ForEach(SettingsPage.allCases.filter { $0 != .access }) { page in
                        Button { selection = page } label: {
                            HStack(spacing: 8) {
                                Image(systemName: page.iconName)
                                Text(page.rawValue)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selection == page
                                ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.15))
                                : nil
                        )
                        .tutorialAnchor(page.tutorialAnchorID ?? "settings.\(page.id)")
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            } detail: {
                detail(for: selection)
                    .navigationTitle(selection.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            // iPhone: NavigationStack
            NavigationStack(path: $phoneNavigationPath) {
                List {
                    ForEach(SettingsPage.allCases.filter { $0 != .access }) { page in
                        NavigationLink(value: page) {
                            sidebarLabel(for: page)
                        }
                        .tutorialAnchor(page.tutorialAnchorID ?? "settings.\(page.id)")
                    }
                }
                .navigationTitle("Settings")
                .navigationDestination(for: SettingsPage.self) { page in
                    detail(for: page)
                        .navigationTitle(page.rawValue)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
#endif
    }
}

#if os(macOS)
#endif

/// Combined settings page for external integrations (PCO, ProPresenter, NDI).
struct ExternalConnectionsSettingsView: View {
    enum ConnectionPage: String, CaseIterable, Identifiable {
        case pco = "Planning Center"
        case propresenter = "ProPresenter"
        case liveStream = "Live Stream"
        case smartLights = "Smart Lights"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .pco: return "link"
            case .liveStream: return "dot.radiowaves.left.and.right"
            case .propresenter: return "play.rectangle.on.rectangle"
            case .smartLights: return "lightbulb.2"
            }
        }
    }

    @State private var selection: ConnectionPage = .pco
#if os(iOS)
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
#endif

    private var visiblePages: [ConnectionPage] {
        ConnectionPage.allCases.filter { page in
            if page == .liveStream {
                return LiveStreamFeatureFlags.isEnabled
            }
            if page == .smartLights {
                return SmartLightFeatureFlags.isEnabled
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("External Connections")
                .font(.title2.bold())

            Text("Configure integrations for Planning Center, live streaming, and ProPresenter.")
                .font(.footnote)
                .foregroundStyle(.secondary)

#if os(macOS)
            ConnectionSegmentedControl(
                selection: $selection,
                visiblePages: visiblePages
            )
            .padding(.bottom, 4)

            Group {
                switch selection {
                case .pco:
                    DashboardPCOSettingsView()
                case .liveStream:
                    DashboardLiveStreamSettingsView()
                case .propresenter:
                    DashboardProPresenterSettingsView()
                case .smartLights:
                    DashboardSmartLightsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#else
            if isIPad {
                Picker("Connection", selection: $selection) {
                    ForEach(visiblePages) { page in
                        Text(page.rawValue)
                            .tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                Group {
                    switch selection {
                    case .pco:
                        DashboardPCOSettingsView()
                    case .liveStream:
                        DashboardLiveStreamSettingsView()
                    case .propresenter:
                        DashboardProPresenterSettingsView()
                    case .smartLights:
                        DashboardSmartLightsSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // iPhone: show each integration as a navigation list.
                List {
                    ForEach(visiblePages) { page in
                        NavigationLink(value: page) {
                            HStack(spacing: 8) {
                                Label(page.rawValue, systemImage: page.iconName)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: ConnectionPage.self) { page in
                    Group {
                        switch page {
                        case .pco:
                            DashboardPCOSettingsView()
                        case .liveStream:
                            DashboardLiveStreamSettingsView()
                        case .propresenter:
                            DashboardProPresenterSettingsView()
                        case .smartLights:
                            DashboardSmartLightsSettingsView()
                        }
                    }
                    .navigationTitle(page.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
#endif
        }
        .padding(24)
    }

#if os(macOS)
    private struct ConnectionSegmentedControl: View {
        @Binding var selection: ConnectionPage
        let visiblePages: [ConnectionPage]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(visiblePages.enumerated()), id: \.element) { index, page in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1)
                    }
                    segment(page)
                }
            }
            .frame(height: 30)
            .background(Color.white.opacity(0.06), in: Capsule())
        }

        private func segment(_ page: ConnectionPage) -> some View {
            let isSelected = selection == page
            let firstPage = visiblePages.first
            let lastPage = visiblePages.last
            return Button {
                selection = page
            } label: {
                HStack(spacing: 6) {
                    Text(page.rawValue)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    AsymmetricRoundedRect(
                        topLeft: page == firstPage ? 14 : 0,
                        topRight: page == lastPage ? 14 : 0,
                        bottomLeft: page == firstPage ? 14 : 0,
                        bottomRight: page == lastPage ? 14 : 0
                    )
                    .fill(isSelected ? Color.blue : Color.clear)
                )
                .padding(2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: selection)
        }
    }
#endif
}

#if os(macOS)
private struct AsymmetricRoundedRect: Shape {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = min(min(topLeft, rect.width / 2), rect.height / 2)
        let tr = min(min(topRight, rect.width / 2), rect.height / 2)
        let bl = min(min(bottomLeft, rect.width / 2), rect.height / 2)
        let br = min(min(bottomRight, rect.width / 2), rect.height / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        return path
    }
}
#endif

struct DashboardHelpSettingsView: View {
    @State private var showCopiedToast = false
    @State private var showingReport = false
    @StateObject private var diagnostics = RelayDiagnosticsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Help")
                .font(.title2.bold())

            Text("Export logs for support and debugging. This includes connection details, LAN activity, and OSC events.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button("Export Logs…") {
                        NotificationCenter.default.post(name: .prodLinkExportLogsRequested, object: nil)
                    }

                    Button("Copy Diagnostic Summary") {
                        let summary = buildDiagnosticSummary()
                        copyToPasteboard(summary)
                        showCopiedToast = true
                    }
                }

                HStack(spacing: 12) {
                    Button("Report a Bug…") {
                        showingReport = true
                    }

                    Button("Contact Support") {
                        RelaySupportContact.openSupportEmail()
                    }

                    Button("Help Center") {
                        RelaySupportContact.openHelpCenter()
                    }
                    .dashboardLinkButtonStyle()
                }
            }
            .padding(.top, 4)

            if showCopiedToast {
                Text("Copied to clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCopiedToast = false
                            }
                        }
                    }
            }

            Text("Logs may include connection endpoints, device names, and OSC paths. Please review before sharing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)


            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingReport) {
            RelayBugReportSheet()
        }
    }

    private func buildDiagnosticSummary() -> String {
        diagnostics.diagnosticSummary()
    }

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct RelayBugReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var message = ""
    @State private var includeDiagnostics = false
    @State private var diagnosticSummary = RelayDiagnosticsStore.shared.diagnosticSummary()
    @State private var openedOnGitHub = false
    @State private var copiedDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Report a Bug").font(.title2.bold())
                Text("Describe what happened, what you expected, and how to reproduce it. Relay opens a prefilled GitHub issue in your browser. Nothing is sent until you submit it there, and you need a free GitHub account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Your report").font(.headline)
                TextEditor(text: $message)
                    .frame(minHeight: 120)
                    .accessibilityLabel("Bug report description")

                Toggle("Include diagnostic summary", isOn: $includeDiagnostics)
                if includeDiagnostics {
                    Text("Review or edit the summary first. It may contain device names, connection addresses, file paths, and recent errors. GitHub issues are public.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $diagnosticSummary)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 140)
                        .accessibilityLabel("Diagnostic summary to include")
                }

                if openedOnGitHub {
                    Text(copiedDiagnostics
                         ? "Opened GitHub. The full diagnostic summary is on your clipboard; paste it into the issue."
                         : "Opened GitHub. Review the issue there and submit it.")
                        .font(.callout)
                }
                HStack {
                    Button(openedOnGitHub ? "Done" : "Cancel") { dismiss() }
                    Spacer()
                    Button("Open on GitHub") { openIssue() }
                        .buttonStyle(.borderedProminent)
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }

    private func openIssue() {
        guard let report = GitHubIssueReport.make(
            message: message,
            diagnostics: includeDiagnostics ? diagnosticSummary : nil
        ) else { return }
        copiedDiagnostics = report.diagnosticsNeedPasting
        if report.diagnosticsNeedPasting {
            #if os(iOS)
            UIPasteboard.general.string = diagnosticSummary
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnosticSummary, forType: .string)
            #endif
        }
        openURL(report.url)
        openedOnGitHub = true
    }
}

struct DashboardPreviewSettingsView: View {
    @StateObject private var loggingPrefs = WirelessLoggingPreferences.shared
    @AppStorage(RelayBuildConfig.previewFeaturesKey) private var previewFeaturesOn: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.title2.bold())

                GroupBox("Preview features") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable preview features", isOn: $previewFeaturesOn)

                        Text("Preview features are still being tested and may change. They include newer automation triggers, smart lights, extra DAW protocols, and newer device models. Restart Relay after changing this setting.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                if RelayBuildConfig.isPreviewEnabled {
                    wirelessLoggingSection
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var wirelessLoggingSection: some View {
        GroupBox("Wireless Diagnostics Logging") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Verbose wireless tracing is only active when preview features are on (or in debug builds), after restarting Relay.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Verbose Shure logging", isOn: $loggingPrefs.shureMasterEnabled)

                if loggingPrefs.shureMasterEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(WirelessLoggingPreferences.ShureFamily.allCases) { family in
                            Toggle(family.rawValue, isOn: shureFamilyBinding(for: family))
                        }

                        Button("Reset Shure Defaults") {
                            loggingPrefs.resetShureToDefaults()
                        }
                        .font(.caption)
                    }
                    .padding(.leading, 16)
                }

                Divider()

                Toggle("Verbose Sennheiser logging", isOn: $loggingPrefs.sennheiserMasterEnabled)

                if loggingPrefs.sennheiserMasterEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(WirelessLoggingPreferences.SennheiserFamily.allCases) { family in
                            Toggle(family.rawValue, isOn: sennheiserFamilyBinding(for: family))
                        }

                        Button("Reset Sennheiser Defaults") {
                            loggingPrefs.resetSennheiserToDefaults()
                        }
                        .font(.caption)
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func shureFamilyBinding(for family: WirelessLoggingPreferences.ShureFamily) -> Binding<Bool> {
        Binding(
            get: { loggingPrefs.isFamilyEnabled(family) },
            set: { loggingPrefs.setFamilyEnabled(family, $0) }
        )
    }

    private func sennheiserFamilyBinding(for family: WirelessLoggingPreferences.SennheiserFamily) -> Binding<Bool> {
        Binding(
            get: { loggingPrefs.isFamilyEnabled(family) },
            set: { loggingPrefs.setFamilyEnabled(family, $0) }
        )
    }

}

/// Placeholder for general dashboard settings.
struct GeneralDashboardSettingsPane: View {
    @AppStorage("dashboard_personImageFolder") private var personImageFolder: String = ""
    @AppStorage("dashboard_personImageFolderBookmark") private var personImageFolderBookmarkData: Data?
    @AppStorage("dashboard_gridSize") private var gridSizeSetting: Double = 20.0
    @AppStorage("gridBackgroundOpacity") private var gridBackgroundOpacity: Double = 0.35
    @AppStorage("dashboard_file_autosave_enabled") private var fileAutosaveEnabled: Bool = false
    @AppStorage("dashboard_live_mode_canvas_behavior") private var liveModeCanvasBehaviorRaw: String = LiveModeCanvasBehavior.fitToScreen.rawValue
    @AppStorage("dashboard_live_mode_window_behavior") private var liveModeWindowBehaviorRaw: String = LiveModeWindowBehavior.keepCurrentSize.rawValue
#if DEBUG
    @State private var isShowingFactoryResetConfirmation: Bool = false
#if os(iOS)
    @State private var isShowingFactoryResetCompleteIOS: Bool = false
#endif
#endif

    /// Global setting controlling whether tiles are allowed to overlap
    /// in Z-space on the dashboard.
    @AppStorage("dashboard_allowTileOverlap") private var allowTileOverlap: Bool = true

    @AppStorage("dashboard_colorSchemePreference") private var colorSchemePreferenceRaw: String = ColorSchemePreference.system.rawValue

    private var colorSchemePreference: Binding<ColorSchemePreference> {
        Binding(
            get: { ColorSchemePreference(rawValue: colorSchemePreferenceRaw) ?? .system },
            set: { colorSchemePreferenceRaw = $0.rawValue }
        )
    }

    private var liveModeCanvasBehavior: Binding<LiveModeCanvasBehavior> {
        Binding(
            get: { LiveModeCanvasBehavior(rawValue: liveModeCanvasBehaviorRaw) ?? .fitToScreen },
            set: { liveModeCanvasBehaviorRaw = $0.rawValue }
        )
    }

    private var liveModeWindowBehavior: Binding<LiveModeWindowBehavior> {
        Binding(
            get: { LiveModeWindowBehavior(rawValue: liveModeWindowBehaviorRaw) ?? .keepCurrentSize },
            set: { liveModeWindowBehaviorRaw = $0.rawValue }
        )
    }

    @State private var showingPersonFolderPicker: Bool = false


    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                Text("General Settings")
                    .font(.title2.bold())

                Text("Configure global dashboard appearance and layout behavior.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox("Appearance") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose how Relay looks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Appearance", selection: colorSchemePreference) {
                            ForEach(ColorSchemePreference.allCases, id: \.self) { preference in
                                Text(preference.label).tag(preference)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                GroupBox("Layout & Grid") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Grid")
                            .font(.headline)

                        Text("Controls snap-to-grid and background visibility.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Grid size")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Slider(
                                    value: $gridSizeSetting,
                                    in: 8...160,
                                    onEditingChanged: { editing in
                                        // Snap to 2pt increments when the user releases the knob.
                                        if !editing {
                                            gridSizeSetting = (gridSizeSetting / 2.0).rounded() * 2.0
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity)

                                Text("\(Int(gridSizeSetting)) pt")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }

                            GridRow {
                                Text("Grid opacity")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Slider(
                                    value: $gridBackgroundOpacity,
                                    in: 0.0...1.0,
                                    onEditingChanged: { editing in
                                        // Snap to 1% increments when the user releases the knob.
                                        if !editing {
                                            gridBackgroundOpacity = (gridBackgroundOpacity * 100.0).rounded() / 100.0
                                        }
                                    }
                                )
                                .frame(maxWidth: .infinity)

                                Text("\(Int(gridBackgroundOpacity * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        Toggle(isOn: $allowTileOverlap) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow tiles to overlap")
                                Text("When off, dropping a tile on another reverts the move.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Live Mode") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Configure what happens when entering Live Mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Canvas")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Picker("Canvas", selection: liveModeCanvasBehavior) {
                                    ForEach(LiveModeCanvasBehavior.allCases, id: \.self) { behavior in
                                        Text(behavior.label).tag(behavior)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

#if os(macOS)
                            GridRow {
                                Text("Window")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)

                                Picker("Window", selection: liveModeWindowBehavior) {
                                    ForEach(LiveModeWindowBehavior.allCases, id: \.self) { behavior in
                                        Text(behavior.label).tag(behavior)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
#endif
                        }
                    }
                }

                GroupBox("Saving") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $fileAutosaveEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Autosave saved dashboards")
                                Text("When enabled, changes to dashboards that already have a file location are written back automatically.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Person Images Folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose a folder of headshots. Images are matched by name (e.g. \"First Last.png\").")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(personImageFolder.isEmpty ? "No folder selected" : personImageFolder)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack {
                            Button("Choose Folder…") {
                                choosePersonImageFolder()
                            }
#if os(iOS)
                            .fileImporter(
                                isPresented: $showingPersonFolderPicker,
                                allowedContentTypes: [.folder],
                                allowsMultipleSelection: false
                            ) { result in
                                switch result {
                                case .success(let urls):
                                    guard let url = urls.first else { return }
                                    // For iCloud Drive / provider-backed URLs, create the bookmark while coordinating
                                    // access and while the security scope is active. Otherwise `bookmarkData(...)`
                                    // can fail with "doesn't exist" even though the folder is real.
                                    let didStart = url.startAccessingSecurityScopedResource()
                                    defer {
                                        if didStart {
                                            url.stopAccessingSecurityScopedResource()
                                        }
                                    }

                                    var coordinatorError: NSError?
                                    let coordinator = NSFileCoordinator()

                                    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
                                        do {
                                            let bookmark = try coordinatedURL.bookmarkData(
                                                options: [.minimalBookmark],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil
                                            )
                                            personImageFolderBookmarkData = bookmark

                                            // Store a friendly label for the UI.
                                            personImageFolder = coordinatedURL.lastPathComponent
                                        } catch {
                                            print("[GeneralDashboardSettingsPane] Failed to create bookmark for person image folder (iOS):", error.localizedDescription)
                                            personImageFolderBookmarkData = nil
                                            personImageFolder = ""
                                        }
                                    }

                                    if let coordinatorError {
                                        print("[GeneralDashboardSettingsPane] Folder coordination error (iOS):", coordinatorError.localizedDescription)
                                    }
                                case .failure(let error):
                                    print("[GeneralDashboardSettingsPane] Folder pick cancelled/failed:", error.localizedDescription)
                                }
                            }
#endif

                            if !personImageFolder.isEmpty {
                                Button("Clear") {
                                    personImageFolder = ""
                                    personImageFolderBookmarkData = nil
                                }
                            }

                            Spacer()
                        }
                    }
                }

#if DEBUG
                GroupBox("Debug") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Reset Auto-Save Announcement") {
                            UserDefaults.standard.removeObject(forKey: "autosave_announcement_shown_v1")
                        }
                        .buttonStyle(.bordered)

                        Divider()
                            .padding(.vertical, 4)

                        Button("Factory Reset…") {
                            isShowingFactoryResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .alert("Factory Reset?", isPresented: $isShowingFactoryResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        DebugFactoryReset.perform()
#if os(iOS)
                        isShowingFactoryResetCompleteIOS = true
#endif
                    }
                } message: {
                    Text("Wipes all local app configuration — devices, audio inputs, connections, onboarding state, window/UI prefs, cached feeds — back to a fresh install. Your Pro license (Keychain-based) is not affected.\n\nOn macOS the app relaunches automatically.")
                }
#if os(iOS)
                .alert("Reset Complete", isPresented: $isShowingFactoryResetCompleteIOS) {
                    Button("OK") {}
                } message: {
                    Text("Force-quit and reopen Relay to finish applying the reset.")
                }
#endif
#endif

                Color.clear
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .toggleStyle(.switch)
    }

    /// Folder picker. On macOS uses NSOpenPanel; on iOS uses a Document Picker via `.fileImporter`.
    private func choosePersonImageFolder() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                personImageFolderBookmarkData = bookmark
                personImageFolder = url.path
            } catch {
                print("[GeneralDashboardSettingsPane] Failed to create bookmark for person image folder:", error.localizedDescription)
                personImageFolderBookmarkData = nil
                personImageFolder = ""
            }
        }
#else
        // iOS: present the Document Picker (handled by `.fileImporter` attached to the button).
        showingPersonFolderPicker = true
#endif
    }
}
