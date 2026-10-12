//
//  ActionGraphNodeView.swift
//  Relay
//
//  Created by David Bullard on 1/13/26.
//


import SwiftUI
import Combine

// MARK: - Action Node Metadata

/// Centralized metadata for graph Action nodes.
/// Keeps `GraphDashboardView` from accumulating switch statements.
enum DashboardActionKind: String, CaseIterable {
    case sendAllConsoles = "action.sendAllConsoles"
    case oscSend = "action.oscSend"
    case notify = "action.notify"
    case lanNotify = "action.lanNotify"
    case appControl = "action.appControl"
    case midiSend = "action.midiSend"
    case proPresenterTrigger = "action.proPresenterTrigger"
    case smartLightControl = "action.smartLightControl"
    case shureSend = "action.shureSend"
    case sennheiserSend = "action.sennheiserSend"

    init?(key: String) {
        self.init(rawValue: key)
    }

    var title: String {
        switch self {
        case .sendAllConsoles: return "Send to All Consoles"
        case .oscSend: return "OSC Send"
        case .notify: return "Notify"
        case .lanNotify: return "LAN Notification"
        case .appControl: return "In-App Action"
        case .midiSend: return "MIDI Send"
        case .proPresenterTrigger: return "ProPresenter Trigger"
        case .smartLightControl: return "Smart Light Control"
        case .shureSend: return "Shure Wireless"
        case .sennheiserSend: return "Sennheiser Wireless"
        }
    }

    var subtitle: String {
        switch self {
        case .sendAllConsoles: return "Send snapshots/assignments to all connected consoles"
        case .oscSend: return "Send a custom OSC message"
        case .notify: return "Post an in-app notification"
        case .lanNotify: return "Send a notification to Relay peers on LAN"
        case .appControl: return "Control Relay UI and document actions"
        case .midiSend: return "Send MIDI note, CC, PC, or SysEx"
        case .proPresenterTrigger: return "Trigger a ProPresenter action"
        case .smartLightControl: return "Control smart lights, plugs, and scenes"
        case .shureSend: return "Send control commands to a Shure receiver"
        case .sennheiserSend: return "Send control commands to a Sennheiser receiver"
        }
    }

    var systemImage: String {
        switch self {
        case .sendAllConsoles: return "bolt.fill"
        case .oscSend: return "paperplane"
        case .notify: return "bell"
        case .lanNotify: return "wifi"
        case .appControl: return "macwindow.on.rectangle"
        case .midiSend: return "pianokeys"
        case .proPresenterTrigger: return "play.rectangle.on.rectangle"
        case .smartLightControl: return "lightbulb.2"
        case .shureSend: return "dot.radiowaves.left.and.right"
        case .sennheiserSend: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Convenience helpers when you only have a raw key string.
struct DashboardActionDescriptor {
    static func kind(for key: String) -> DashboardActionKind? { DashboardActionKind(key: key) }
    static func title(for key: String) -> String { DashboardActionKind(key: key)?.title ?? "Action" }
    static func subtitle(for key: String) -> String { DashboardActionKind(key: key)?.subtitle ?? "" }
    static func systemImage(for key: String) -> String { DashboardActionKind(key: key)?.systemImage ?? "bolt.fill" }
}

/// Backwards-compatible pure helpers (mirrors older GraphDashboardView helpers).
@inline(__always) func actionTitle(for key: String) -> String {
    DashboardActionDescriptor.title(for: key)
}

@inline(__always) func actionSubtitle(for key: String) -> String {
    DashboardActionDescriptor.subtitle(for: key)
}

@inline(__always) func actionSystemImage(for key: String) -> String {
    DashboardActionDescriptor.systemImage(for: key)
}

///// Notification names for action nodes (keeps strings centralized).
//enum ActionNodeNotifications {
//    static let sendAllConsoles = Notification.Name("Relay.ActionNode.SendAllConsoles")
//    static let oscSend = Notification.Name("Relay.ActionNode.OSCSend")
//    static let notify = Notification.Name("Relay.ActionNode.Notify")
//    static let applyGraph = Notification.Name("Relay.ActionNode.ApplyGraph")
//}
//
///// Payload keys for ActionNodeNotifications userInfo dictionaries.
//enum ActionNodeUserInfoKeys {
//    static let nodeId = "nodeId"
//    static let includeAssignments = "includeAssignments"
//    static let includeSnapshots = "includeSnapshots"
//    static let staggerMs = "staggerMs"
//}

// MARK: - Trigger Notifications

/// Posted when a trigger node (ex: OSC Receive) fires and should execute downstream actions.
enum TriggerNodeNotifications {
    static let fired = Notification.Name("Relay.TriggerNode.Fired")
}

enum TriggerNodeUserInfoKeys {
    static let triggerNodeId = "triggerNodeId"
    static let source = "source"
    static let timestamp = "timestamp"
    static let payloadText = "payloadText"
    static let payloadNumber = "payloadNumber"
    static let payloadBoolean = "payloadBoolean"
    static let address = "address"
    static let localPort = "localPort"
}

/// Process-wide store of trigger-node fire stats keyed by node id.
/// Survives view re-mounts so a node's "Pressed: N • Last: …" stays accurate
/// when the user switches between Canvas and Automation views.
final class TriggerFireTracker: ObservableObject {
    static let shared = TriggerFireTracker()

    struct Stats: Equatable {
        var count: Int = 0
        var lastFiredAt: Date? = nil
    }

    @Published private(set) var stats: [UUID: Stats] = [:]

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: TriggerNodeNotifications.fired,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleFired(note)
        }
    }

    private func handleFired(_ note: Notification) {
        guard let id = note.userInfo?[TriggerNodeUserInfoKeys.triggerNodeId] as? UUID else { return }
        var s = stats[id] ?? Stats()
        s.count += 1
        s.lastFiredAt = Date()
        stats[id] = s
    }

    func count(for id: UUID) -> Int { stats[id]?.count ?? 0 }
    func lastFired(for id: UUID) -> Date? { stats[id]?.lastFiredAt }
}

// MARK: - OSC Send Validation

struct OSCSendValidation {

    /// Ensure OSC address is non-empty and begins with a leading "/" without
    /// stripping characters while the user is still typing.
    static func normalizedAddress(_ raw: String) -> String {
        if raw.isEmpty { return "/" }
        return raw.hasPrefix("/") ? raw : "/" + raw
    }

    /// Trim whitespace; allow IPv4, IPv6 literals, or hostnames (lightweight check).
    /// This is intentionally permissive; transport layer should be the source of truth.
    static func normalizedHost(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Port must be non-zero to be useful.
    static func isPortValid(_ port: UInt16) -> Bool {
        port != 0
    }

    /// Minimal "can run" gate for UI.
    static func canRun(host: String, port: UInt16, address: String) -> Bool {
        let h = normalizedHost(host)
        if h.isEmpty { return false }
        if !isPortValid(port) { return false }
        let a = normalizedAddress(address)
        return !a.isEmpty && a.hasPrefix("/")
    }
}

struct NameRefreshDeviceOptionsEditor: View {
    @Binding var options: AppControlRefreshDeviceOptions
    @ObservedObject private var externalDevicesStore = ExternalDevicesStore.shared

    private var availableDevices: [ExternalDeviceConfig] {
        externalDevicesStore.devices
            .filter(\.isNameRefreshTarget)
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind.displayName < rhs.kind.displayName
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Refresh Scope")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Refresh Scope", selection: $options.targetScope) {
                ForEach(AppControlRefreshDeviceOptions.TargetScope.allCases, id: \.self) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.menu)

            if options.targetScope == .selectedDevices {
                if availableDevices.isEmpty {
                    Text("No supported refresh targets are available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(availableDevices) { device in
                            Toggle(
                                device.nameRefreshTargetLabel,
                                isOn: Binding(
                                    get: { options.selectedDeviceIDs.contains(device.id) },
                                    set: { isSelected in
                                        var ids = options.selectedDeviceIDs.filter { $0 != device.id }
                                        if isSelected {
                                            ids.append(device.id)
                                        }
                                        options.selectedDeviceIDs = ids
                                    }
                                )
                            )
#if os(macOS)
                            .toggleStyle(.checkbox)
#endif
                        }
                    }
                }
            }
        }
    }
}

/// A reusable SwiftUI view for graph-only Action nodes.
/// - Receives links (receiver nub on LEFT)
/// - Shows title/subtitle + Run button
/// - Hosts action-specific settings (Send All / Send OSC, etc.) via injected content.
enum ActionNodeWarningStyle {
    case warning
    case error
}

struct ActionGraphNodeView<Settings: View>: View {

    // Identity / display
    let nodeId: UUID
    let title: String
    let subtitle: String
    let systemImage: String
    let nodeTypeLabel: String
    let nodeTypeAccessibilityLabel: String
    let nodeTypeBadgeColor: Color
    let nodeTintColor: Color

    // Selection / linking visuals
    let isSelected: Bool
    let isHoverReceiver: Bool
    let isLinkingTarget: Bool

    // Actions
    let onTapSelect: () -> Void
    let onRun: () -> Void

    // Settings UI (provided by caller)
    @ViewBuilder let settings: () -> Settings

    let warningText: String?
    let warningStyle: ActionNodeWarningStyle
    let isRunning: Bool
    let onDismissWarning: (() -> Void)?

    init(
        nodeId: UUID,
        title: String,
        subtitle: String,
        systemImage: String = "bolt.fill",
        nodeTypeLabel: String = "ACTION",
        nodeTypeAccessibilityLabel: String = "Action node",
        nodeTypeBadgeColor: Color = Color.green.opacity(0.22),
        nodeTintColor: Color = Color.green.opacity(0.10),
        warningText: String? = nil,
        warningStyle: ActionNodeWarningStyle = .warning,
        isRunning: Bool = false,
        onDismissWarning: (() -> Void)? = nil,
        isSelected: Bool,
        isHoverReceiver: Bool,
        isLinkingTarget: Bool,
        onTapSelect: @escaping () -> Void,
        onRun: @escaping () -> Void,
        @ViewBuilder settings: @escaping () -> Settings
    ) {
        self.nodeId = nodeId
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.nodeTypeLabel = nodeTypeLabel
        self.nodeTypeAccessibilityLabel = nodeTypeAccessibilityLabel
        self.nodeTypeBadgeColor = nodeTypeBadgeColor
        self.nodeTintColor = nodeTintColor
        self.warningText = warningText
        self.warningStyle = warningStyle
        self.isRunning = isRunning
        self.onDismissWarning = onDismissWarning
        self.isSelected = isSelected
        self.isHoverReceiver = isHoverReceiver
        self.isLinkingTarget = isLinkingTarget
        self.onTapSelect = onTapSelect
        self.onRun = onRun
        self.settings = settings
    }

    var body: some View {
        GraphNodeChromeContainer(
            tint: nodeTintColor,
            border: Color.white.opacity(0.10),
            isSelected: isSelected,
            isHoverReceiver: isHoverReceiver,
            showsError: warningStyle == .error && warningText != nil,
            leadingOverlay: AnyView(receiverNub)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                settings()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { onTapSelect() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(title) \(nodeTypeAccessibilityLabel.lowercased())"))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)

                    if let warningText {
                        Group {
                            if warningStyle == .error, let onDismissWarning {
                                Button(action: onDismissWarning) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.red)
                                }
                                .buttonStyle(.plain)
                                .help("\(warningText)\n\nClick to dismiss warning.")
                                .accessibilityLabel("Dismiss warning")
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(warningStyle == .error ? Color.red : Color.yellow)
                                    .help(warningText)
                                    .accessibilityLabel(warningText)
                            }
                        }
                    }

                    Text(nodeTypeLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(nodeTypeBadgeColor)
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(nodeTypeAccessibilityLabel)

                    Spacer(minLength: 0)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: {
                #if DEBUG
                print("[ActionNode] Run tapped nodeId=\(nodeId) title=\(title)")
                #endif
                onRun()
            }) {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRunning ? "Refreshing…" : "Run")
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.runButtonCornerRadius)
                        .fill(Color.white.opacity(GraphNodeStyleTokens.runButtonFillOpacity))
                )
            }
            .buttonStyle(.plain)
            .disabled(isLinkingTarget || isRunning)
        }
    }

    private var receiverNub: some View {
        Circle()
            .fill(isHoverReceiver ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.55))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .offset(x: -5)
            .accessibilityLabel("Link input")
    }
}

// MARK: - Repeater (Utility) Node

struct RepeaterGraphNodeView<Settings: View>: View {
    private let utilityCategory: GraphNodeCategory = .utility

    let nodeId: UUID
    let outputCount: Int
    let connectedOutputCount: Int
    let isSelected: Bool
    let isHoverReceiver: Bool
    let isLinkingTarget: Bool
    let onTapSelect: () -> Void
    let onRun: () -> Void
    let onOutputDragChanged: ((Int, DragGesture.Value) -> Void)?
    let onOutputDragEnded: ((Int, DragGesture.Value) -> Void)?

    @ViewBuilder let settings: () -> Settings

    init(
        nodeId: UUID,
        outputCount: Int,
        connectedOutputCount: Int,
        isSelected: Bool,
        isHoverReceiver: Bool,
        isLinkingTarget: Bool,
        onTapSelect: @escaping () -> Void,
        onRun: @escaping () -> Void,
        onOutputDragChanged: ((Int, DragGesture.Value) -> Void)? = nil,
        onOutputDragEnded: ((Int, DragGesture.Value) -> Void)? = nil,
        @ViewBuilder settings: @escaping () -> Settings
    ) {
        self.nodeId = nodeId
        self.outputCount = outputCount
        self.connectedOutputCount = connectedOutputCount
        self.isSelected = isSelected
        self.isHoverReceiver = isHoverReceiver
        self.isLinkingTarget = isLinkingTarget
        self.onTapSelect = onTapSelect
        self.onRun = onRun
        self.onOutputDragChanged = onOutputDragChanged
        self.onOutputDragEnded = onOutputDragEnded
        self.settings = settings
    }

    var body: some View {
        GraphNodeChromeContainer(
            tint: utilityCategory.tintColor,
            border: utilityCategory.borderColor,
            isSelected: isSelected,
            isHoverReceiver: isHoverReceiver,
            leadingOverlay: AnyView(receiverNub),
            trailingOverlay: AnyView(outputNubs.overlay(outputHitTargets))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                settings()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { onTapSelect() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Repeater utility node"))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat")
                .imageScale(.medium)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Repeater")
                        .font(.headline)

                    Text("UTILITY")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(utilityCategory.badgeColor)
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Utility node")

                    Spacer(minLength: 0)
                }

                Text("Repeat downstream actions with a delay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: {
                #if DEBUG
                print("[RepeaterNode] Run tapped nodeId=\(nodeId)")
                #endif
                onRun()
            }) {
                Text("Test")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                            .fill(Color.white.opacity(GraphNodeStyleTokens.runButtonFillOpacity))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isLinkingTarget)
        }
    }

    private var receiverNub: some View {
        Circle()
            .fill(isHoverReceiver ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.55))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .offset(x: -5)
            .accessibilityLabel("Link input")
    }

    private var outputNubs: some View {
        let total = max(1, outputCount)
        return VStack(spacing: 14) {
            ForEach(0..<total, id: \.self) { index in
                let isFilled = index < connectedOutputCount
                ZStack {
                    Circle()
                        .fill(isFilled ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.70))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
                        )

                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.75))
                }
            }
        }
        .padding(.trailing, -5)
        .allowsHitTesting(false)
        .accessibilityLabel("Link outputs")
    }

    private var outputHitTargets: some View {
        let total = max(1, outputCount)
        return VStack(spacing: 14) {
            ForEach(0..<total, id: \.self) { index in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 56, height: 22)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named("GraphSceneSpace"))
                            .onChanged { value in
                                onOutputDragChanged?(index, value)
                            }
                            .onEnded { value in
                                onOutputDragEnded?(index, value)
                            }
                    )
                    .accessibilityLabel("Link output")
            }
        }
        .padding(.trailing, -14)
        .offset(x: 14)
    }
}

struct DelayGraphNodeView<Settings: View>: View {
    private let utilityCategory: GraphNodeCategory = .utility

    let nodeId: UUID
    let isSelected: Bool
    let isHoverReceiver: Bool
    let isLinkingTarget: Bool
    let onTapSelect: () -> Void
    let onRun: () -> Void
    let onOutputDragChanged: ((DragGesture.Value) -> Void)?
    let onOutputDragEnded: ((DragGesture.Value) -> Void)?
    @ViewBuilder let settings: () -> Settings

    init(
        nodeId: UUID,
        isSelected: Bool,
        isHoverReceiver: Bool,
        isLinkingTarget: Bool,
        onTapSelect: @escaping () -> Void,
        onRun: @escaping () -> Void,
        onOutputDragChanged: ((DragGesture.Value) -> Void)? = nil,
        onOutputDragEnded: ((DragGesture.Value) -> Void)? = nil,
        @ViewBuilder settings: @escaping () -> Settings
    ) {
        self.nodeId = nodeId
        self.isSelected = isSelected
        self.isHoverReceiver = isHoverReceiver
        self.isLinkingTarget = isLinkingTarget
        self.onTapSelect = onTapSelect
        self.onRun = onRun
        self.onOutputDragChanged = onOutputDragChanged
        self.onOutputDragEnded = onOutputDragEnded
        self.settings = settings
    }

    var body: some View {
        GraphNodeChromeContainer(
            tint: utilityCategory.tintColor,
            border: utilityCategory.borderColor,
            isSelected: isSelected,
            isHoverReceiver: isHoverReceiver,
            leadingOverlay: AnyView(receiverNub),
            trailingOverlay: AnyView(outputNub.overlay(outputHitTarget))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                settings()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { onTapSelect() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Delay utility node"))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .imageScale(.medium)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Delay")
                        .font(.headline)

                    Text("UTILITY")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(utilityCategory.badgeColor)
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Utility node")

                    Spacer(minLength: 0)
                }

                Text("Wait before passing a trigger downstream.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: {
                #if DEBUG
                print("[DelayNode] Run tapped nodeId=\(nodeId)")
                #endif
                onRun()
            }) {
                Text("Test")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                            .fill(Color.white.opacity(GraphNodeStyleTokens.runButtonFillOpacity))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isLinkingTarget)
        }
    }

    private var receiverNub: some View {
        Circle()
            .fill(isHoverReceiver ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.55))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .offset(x: -5)
            .accessibilityLabel("Link input")
    }

    private var outputNub: some View {
        Circle()
            .fill(Color.white.opacity(0.70))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .padding(.trailing, -5)
            .allowsHitTesting(false)
            .accessibilityLabel("Link output")
    }

    private var outputHitTarget: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 56, height: 22)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("GraphSceneSpace"))
                    .onChanged { value in
                        onOutputDragChanged?(value)
                    }
                    .onEnded { value in
                        onOutputDragEnded?(value)
                    }
            )
            .padding(.trailing, -14)
            .offset(x: 14)
            .accessibilityLabel("Link output")
    }
}

struct ConditionGraphNodeView<Settings: View>: View {
    private let utilityCategory: GraphNodeCategory = .utility

    let nodeId: UUID
    let trueConnected: Bool
    let falseConnected: Bool
    let isSelected: Bool
    let isHoverReceiver: Bool
    let isLinkingTarget: Bool
    let onTapSelect: () -> Void
    let onRun: () -> Void
    let onOutputDragChanged: ((GraphAutomationTraversal.UtilityBranch, DragGesture.Value) -> Void)?
    let onOutputDragEnded: ((GraphAutomationTraversal.UtilityBranch, DragGesture.Value) -> Void)?
    let warningText: String?
    let warningStyle: ActionNodeWarningStyle
    let onDismissWarning: (() -> Void)?
    @ViewBuilder let settings: () -> Settings

    var body: some View {
        GraphNodeChromeContainer(
            tint: utilityCategory.tintColor,
            border: utilityCategory.borderColor,
            isSelected: isSelected,
            isHoverReceiver: isHoverReceiver,
            showsError: warningStyle == .error && warningText != nil,
            leadingOverlay: AnyView(receiverNub),
            trailingOverlay: AnyView(outputNubs.overlay(outputHitTargets))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow

                if let warningText, !warningText.isEmpty {
                    warningPill(text: warningText)
                }

                settings()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { onTapSelect() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("If Else utility node"))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .imageScale(.medium)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("If / Else")
                        .font(.headline)

                    Text("UTILITY")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(utilityCategory.badgeColor)
                        )
                        .foregroundStyle(.secondary)

                    if isGraphConditionalsFeatureEnabled {
                        BetaBadgeView(fontSize: 9, backgroundOpacity: 0.08, borderOpacity: 0.12)
                    }

                    Spacer(minLength: 0)
                }

                Text("Branch downstream flow using payload or variable values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onRun) {
                Text("Test")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                            .fill(Color.white.opacity(GraphNodeStyleTokens.runButtonFillOpacity))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isLinkingTarget)
        }
    }

    private var receiverNub: some View {
        Circle()
            .fill(isHoverReceiver ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.55))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .offset(x: -5)
    }

    private var outputNubs: some View {
        VStack(spacing: 14) {
            branchNub(title: "T", isConnected: trueConnected, tint: .green)
            branchNub(title: "F", isConnected: falseConnected, tint: .red)
        }
        .padding(.trailing, -5)
        .allowsHitTesting(false)
    }

    private func branchNub(title: String, isConnected: Bool, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(isConnected ? tint.opacity(0.95) : Color.white.opacity(0.70))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
                )

            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.75))
        }
    }

    private var outputHitTargets: some View {
        VStack(spacing: 14) {
            hitTarget(branch: .`true`)
            hitTarget(branch: .`false`)
        }
        .padding(.trailing, -14)
        .offset(x: 14)
    }

    private func hitTarget(branch: GraphAutomationTraversal.UtilityBranch) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 56, height: 22)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("GraphSceneSpace"))
                    .onChanged { value in
                        onOutputDragChanged?(branch, value)
                    }
                    .onEnded { value in
                        onOutputDragEnded?(branch, value)
                    }
            )
    }

    private func warningPill(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warningStyle == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.caption)
                .foregroundStyle(warningStyle == .error ? Color.red.opacity(0.95) : Color.orange.opacity(0.95))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let onDismissWarning {
                Button(action: onDismissWarning) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .stroke(
                    warningStyle == .error ? Color.red.opacity(0.20) : Color.orange.opacity(0.18),
                    lineWidth: GraphNodeStyleTokens.borderStrokeWidth
                )
        )
    }
}

struct SmartLightGraphNodeView<Settings: View>: View {
    private let actionCategory: GraphNodeCategory = .actions

    let nodeId: UUID
    let successConnected: Bool
    let failureConnected: Bool
    let stateConnected: Bool
    let showOutputPorts: Bool
    let isSelected: Bool
    let isHoverReceiver: Bool
    let isLinkingTarget: Bool
    let warningText: String?
    let warningStyle: ActionNodeWarningStyle
    let isRunning: Bool
    let onDismissWarning: (() -> Void)?
    let onTapSelect: () -> Void
    let onRun: () -> Void
    let onOutputDragChanged: ((String, DragGesture.Value) -> Void)?
    let onOutputDragEnded: ((String, DragGesture.Value) -> Void)?
    @ViewBuilder let settings: () -> Settings

    var body: some View {
        GraphNodeChromeContainer(
            tint: actionCategory.tintColor,
            border: actionCategory.borderColor,
            isSelected: isSelected,
            isHoverReceiver: isHoverReceiver,
            leadingOverlay: AnyView(receiverNub),
            trailingOverlay: AnyView(outputNubs.overlay(outputHitTargets))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow

                if let warningText, !warningText.isEmpty {
                    warningPill(text: warningText)
                }

                settings()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { onTapSelect() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Smart Light action node"))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.2")
                .imageScale(.medium)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Smart Light Control")
                        .font(.headline)

                    Text("ACTION")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(actionCategory.badgeColor)
                        )
                        .foregroundStyle(.secondary)

                    if SmartLightFeatureFlags.isEnabled {
                        BetaBadgeView(fontSize: 9, backgroundOpacity: 0.08, borderOpacity: 0.12)
                    }

                    Spacer(minLength: 0)
                }

                Text("Control smart lights, plugs, and scenes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onRun) {
                Text(isRunning ? "Running..." : "Run")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                            .fill(Color.white.opacity(GraphNodeStyleTokens.runButtonFillOpacity))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isLinkingTarget || isRunning)
        }
    }

    private var receiverNub: some View {
        Circle()
            .fill(isHoverReceiver ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.55))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .offset(x: -5)
            .accessibilityLabel("Link input")
    }

    private var outputNubs: some View {
        VStack(spacing: 14) {
            if showOutputPorts || successConnected {
                branchNub(title: "S", isConnected: successConnected, tint: .green)
            }
            if showOutputPorts || failureConnected {
                branchNub(title: "F", isConnected: failureConnected, tint: .red)
            }
            if showOutputPorts || stateConnected {
                branchNub(title: "T", isConnected: stateConnected, tint: .blue)
            }
        }
        .padding(.trailing, -5)
        .allowsHitTesting(false)
        .accessibilityLabel("Action outputs")
    }

    private func branchNub(title: String, isConnected: Bool, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(isConnected ? tint.opacity(0.95) : Color.white.opacity(0.70))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.55), lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
                )

            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.75))
        }
    }

    private var outputHitTargets: some View {
        VStack(spacing: 14) {
            if showOutputPorts || successConnected {
                hitTarget(kind: "success")
                    .help("Success — fires when the light command completes without error.")
            }
            if showOutputPorts || failureConnected {
                hitTarget(kind: "failure")
                    .help("Failure — fires when the command fails (unreachable, bad key, etc.).")
            }
            if showOutputPorts || stateConnected {
                hitTarget(kind: "currentState")
                    .help("State — fires after success and carries the device's current state (power, brightness, color).")
            }
        }
        .padding(.trailing, -14)
        .offset(x: 14)
    }

    private func hitTarget(kind: String) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 56, height: 22)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("GraphSceneSpace"))
                    .onChanged { value in
                        onOutputDragChanged?(kind, value)
                    }
                    .onEnded { value in
                        onOutputDragEnded?(kind, value)
                    }
            )
    }

    private func warningPill(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warningStyle == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.caption)
                .foregroundStyle(warningStyle == .error ? Color.red.opacity(0.95) : Color.orange.opacity(0.95))

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let onDismissWarning {
                Button(action: onDismissWarning) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius)
                .stroke(
                    warningStyle == .error ? Color.red.opacity(0.20) : Color.orange.opacity(0.18),
                    lineWidth: GraphNodeStyleTokens.borderStrokeWidth
                )
        )
    }
}

struct StableGraphTextField: View {
    let titleKey: LocalizedStringKey
    @Binding var text: String

    @State private var draftText: String = ""
    @State private var isEditing: Bool = false

    init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.titleKey = titleKey
        self._text = text
        self._draftText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(
            titleKey,
            text: Binding(
                get: { draftText },
                set: { newValue in
                    draftText = newValue
                    text = newValue
                }
            ),
            onEditingChanged: { editing in
                isEditing = editing
                if !editing, draftText != text {
                    draftText = text
                }
            }
        )
        .textFieldStyle(.roundedBorder)
        .onChange(of: text, initial: true) { _, newValue in
            guard !isEditing else { return }
            if draftText != newValue {
                draftText = newValue
            }
        }
    }
}

struct DelayActionSettingsView: View {
    @Binding var delayMs: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Delay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Stepper(value: $delayMs, in: 0...10000, step: 50) {
                    EmptyView()
                }
                .labelsHidden()

                Text("\(delayMs) ms")
                    .font(.caption)
            }
        }
    }
}

struct RepeaterActionSettingsView: View {
    @Binding var outputCount: Int
    @Binding var repeatCount: Int
    @Binding var delayMs: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Outputs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Stepper(value: $outputCount, in: 1...8, step: 1) {
                    EmptyView()
                }
                .labelsHidden()

                Text("\(outputCount)")
                    .font(.caption)
            }

            HStack(spacing: 10) {
                Text("Repeats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Stepper(value: $repeatCount, in: 1...50, step: 1) {
                    EmptyView()
                }
                .labelsHidden()

                Text("\(repeatCount)x")
                    .font(.caption)
            }

            HStack(spacing: 10) {
                Text("Delay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Stepper(value: $delayMs, in: 0...5000, step: 50) {
                    EmptyView()
                }
                .labelsHidden()

                Text("\(delayMs) ms")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Action Settings Subviews

/// Settings UI for the "Send to All Consoles" action.
/// Caller provides bindings so this view stays decoupled from the graph model.
struct SendAllActionSettingsView: View {
    @Binding var includeAssignments: Bool
    @Binding var includeSnapshots: Bool
    @Binding var staggerMs: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include assignments", isOn: $includeAssignments)
                .toggleStyle(.switch)

            Toggle("Include snapshots", isOn: $includeSnapshots)
                .toggleStyle(.switch)

            HStack {
                Text("Stagger")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Stepper(value: $staggerMs, in: 0...2000, step: 20) {
                    EmptyView()
                }
                .labelsHidden()

                Text("\(Int(staggerMs)) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }
}

/// Settings UI for the "Send OSC" action.
/// Caller provides bindings so this view stays decoupled from the graph model.
struct OSCSendActionSettingsView: View {
    private enum ArgumentKind: String, CaseIterable, Identifiable {
        case int32
        case float32
        case string
        case blob
        case `true`
        case `false`
        case null
        case impulse
        case timetag

        var id: String { rawValue }

        var title: String {
            switch self {
            case .int32: return "Int32"
            case .float32: return "Float32"
            case .string: return "String"
            case .blob: return "Blob"
            case .true: return "True"
            case .false: return "False"
            case .null: return "Null"
            case .impulse: return "Impulse"
            case .timetag: return "Timetag"
            }
        }

        init(value: DashboardGraph.OSCSendActionArgument.Value) {
            switch value {
            case .int32: self = .int32
            case .float32: self = .float32
            case .string: self = .string
            case .blobBase64: self = .blob
            case .true: self = .true
            case .false: self = .false
            case .null: self = .null
            case .impulse: self = .impulse
            case .timetag: self = .timetag
            }
        }

        var defaultValue: DashboardGraph.OSCSendActionArgument.Value {
            switch self {
            case .int32: return .int32(0)
            case .float32: return .float32(0)
            case .string: return .string("")
            case .blob: return .blobBase64("")
            case .true: return .true
            case .false: return .false
            case .null: return .null
            case .impulse: return .impulse
            case .timetag: return .timetag(0)
            }
        }
    }

    @Binding var targetIP: String
    @Binding var targetPort: UInt16
    @Binding var address: String
    @Binding var arguments: [DashboardGraph.OSCSendActionArgument]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send OSC")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("IP")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                TextField("192.168.1.100", text: Binding(
                    get: { targetIP },
                    set: { targetIP = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ))
                .textFieldStyle(.roundedBorder)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("Port")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                TextField("8000", text: Binding(
                    get: { targetPort == 0 ? "" : String(targetPort) },
                    set: { newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.isEmpty {
                            targetPort = 0
                        } else if let n = UInt16(filtered) {
                            targetPort = n
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("Address")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                TextField("/path", text: Binding(
                    get: { address },
                    set: { newValue in
                        address = OSCSendValidation.normalizedAddress(newValue)
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Arguments")
                    .font(.caption)
                    .opacity(0.8)

                ForEach(arguments.indices, id: \.self) { index in
                    argumentRow(at: index)
                }

                Button {
                    arguments.append(.init(value: .string("")))
                } label: {
                    Label("Add Argument", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func argumentRow(at index: Int) -> some View {
        HStack(spacing: 6) {
            Picker("Argument type", selection: Binding(
                get: { ArgumentKind(value: arguments[index].value) },
                set: { arguments[index].value = $0.defaultValue }
            )) {
                ForEach(ArgumentKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 108)

            argumentValueEditor(at: index)

            Button {
                arguments.swapAt(index, index - 1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == arguments.startIndex)

            Button {
                arguments.swapAt(index, index + 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == arguments.index(before: arguments.endIndex))

            Button(role: .destructive) {
                arguments.remove(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func argumentValueEditor(at index: Int) -> some View {
        switch arguments[index].value {
        case .int32(let value):
            TextField("Value", text: Binding(
                get: { String(value) },
                set: { if let parsed = Int32($0) { arguments[index].value = .int32(parsed) } }
            ))
            .textFieldStyle(.roundedBorder)
        case .float32(let value):
            TextField("Value", text: Binding(
                get: { String(value) },
                set: { if let parsed = Float($0) { arguments[index].value = .float32(parsed) } }
            ))
            .textFieldStyle(.roundedBorder)
        case .string(let value):
            TextField("Value", text: Binding(
                get: { value },
                set: { arguments[index].value = .string($0) }
            ))
            .textFieldStyle(.roundedBorder)
        case .blobBase64(let value):
            TextField("Base64", text: Binding(
                get: { value },
                set: { arguments[index].value = .blobBase64($0) }
            ))
            .textFieldStyle(.roundedBorder)
        case .timetag(let value):
            TextField("Timetag", text: Binding(
                get: { String(value) },
                set: { if let parsed = UInt64($0) { arguments[index].value = .timetag(parsed) } }
            ))
            .textFieldStyle(.roundedBorder)
        case .true, .false, .null, .impulse:
            Text("No value")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum ProPresenterTriggerAction: String, CaseIterable, Identifiable {
    case mediaNext
    case mediaPrevious
    case audioNext
    case audioPrevious
    case next
    case previous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mediaNext: return "Media Bin Next"
        case .mediaPrevious: return "Media Bin Previous"
        case .audioNext: return "Audio Next"
        case .audioPrevious: return "Audio Previous"
        case .next: return "Slide Next"
        case .previous: return "Slide Previous"
        }
    }

    var path: String {
        switch self {
        case .mediaNext: return "/v1/trigger/media/next"
        case .mediaPrevious: return "/v1/trigger/media/previous"
        case .audioNext: return "/v1/trigger/audio/next"
        case .audioPrevious: return "/v1/trigger/audio/previous"
        case .next: return "/v1/trigger/next"
        case .previous: return "/v1/trigger/previous"
        }
    }

    static func fromPath(_ path: String) -> ProPresenterTriggerAction? {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.allCases.first(where: { $0.path == normalized })
    }
}

struct ProPresenterTriggerActionSettingsView: View {
    @Binding var profileId: UUID?
    @Binding var triggerPath: String
    let profiles: [ProPresenterConnectionProfile]
    let showMissingProfilesWarning: Bool

    private var selectedAction: Binding<ProPresenterTriggerAction> {
        Binding(
            get: { ProPresenterTriggerAction.fromPath(triggerPath) ?? .next },
            set: { triggerPath = $0.path }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ProPresenter Trigger")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("Profile")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                Picker("Profile", selection: $profileId) {
                    Text("Active / Global").tag(UUID?.none)
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text("Trigger")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                Picker("Trigger", selection: selectedAction) {
                    ForEach(ProPresenterTriggerAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showMissingProfilesWarning {
                Label("No ProPresenter connections configured.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct MIDISendActionSettingsView: View {
    @Binding var destinationUniqueID: Int32?
    @Binding var messageKind: MIDIMessageKind
    @Binding var channel: Int
    @Binding var note: Int
    @Binding var velocity: Int
    @Binding var program: Int
    @Binding var control: Int
    @Binding var value: Int
    @Binding var sysexHex: String

    @State private var destinations: [MIDIDestinationOption] = MIDIDestinationDiscovery.currentDestinations()

    private func refreshDestinationsList() {
        MIDISendManager.shared.refreshDestinations()
        destinations = MIDIDestinationDiscovery.currentDestinations()
        if let selected = destinationUniqueID, !destinations.contains(where: { $0.id == selected }) {
            destinationUniqueID = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send MIDI")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("Device")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                Picker("MIDI Destination", selection: $destinationUniqueID) {
                    Text("Default").tag(Int32?.none)
                    ForEach(destinations) { option in
                        Text(option.name).tag(Optional(option.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Refresh") {
                    refreshDestinationsList()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                Text("Type")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                Picker("Message Type", selection: $messageKind) {
                    Text("Note On").tag(MIDIMessageKind.noteOn)
                    Text("Note Off").tag(MIDIMessageKind.noteOff)
                    Text("Program Change").tag(MIDIMessageKind.programChange)
                    Text("Control Change").tag(MIDIMessageKind.controlChange)
                    Text("SysEx").tag(MIDIMessageKind.sysex)
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text("Channel")
                    .font(.caption)
                    .opacity(0.8)
                    .frame(width: 60, alignment: .leading)

                Menu {
                    ForEach(1...16, id: \.self) { value in
                        Button("Ch \(value)") {
                            channel = value
                        }
                    }
                } label: {
                    Text("Ch \(channel)")
                        .font(.caption)
                        .frame(width: 70, alignment: .leading)
                }

                Spacer(minLength: 0)
            }

            if messageKind == .noteOn || messageKind == .noteOff {
                HStack(spacing: 10) {
                    Text("Note")
                        .font(.caption)
                        .opacity(0.8)
                        .frame(width: 60, alignment: .leading)

                    TextField("60", value: $note, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Text("Velocity")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("100", value: $velocity, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Spacer(minLength: 0)
                }
            }

            if messageKind == .programChange {
                HStack(spacing: 10) {
                    Text("Program")
                        .font(.caption)
                        .opacity(0.8)
                        .frame(width: 60, alignment: .leading)

                    TextField("0", value: $program, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                    Spacer(minLength: 0)
                }
            }

            if messageKind == .controlChange {
                HStack(spacing: 10) {
                    Text("CC")
                        .font(.caption)
                        .opacity(0.8)
                        .frame(width: 60, alignment: .leading)

                    TextField("1", value: $control, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Text("Value")
                        .font(.caption)
                        .opacity(0.8)

                    TextField("0", value: $value, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Spacer(minLength: 0)
                }
            }

            if messageKind == .sysex {
                HStack(spacing: 10) {
                    Text("SysEx")
                        .font(.caption)
                        .opacity(0.8)
                        .frame(width: 60, alignment: .leading)

                    TextField("F0 7E 7F 09 01 F7", text: $sysexHex)
                        .textFieldStyle(.roundedBorder)

                    Spacer(minLength: 0)
                }
            }
        }
        .onChange(of: note) { _, newValue in
            note = max(0, min(127, newValue))
        }
        .onChange(of: velocity) { _, newValue in
            velocity = max(0, min(127, newValue))
        }
        .onChange(of: program) { _, newValue in
            program = max(0, min(127, newValue))
        }
        .onChange(of: control) { _, newValue in
            control = max(0, min(127, newValue))
        }
        .onChange(of: value) { _, newValue in
            value = max(0, min(127, newValue))
        }
        .onAppear {
            refreshDestinationsList()
        }
    }
}
