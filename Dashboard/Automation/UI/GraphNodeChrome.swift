import SwiftUI

enum GraphNodeStyleTokens {
    static let cornerRadius: CGFloat = 14
    static let secondaryCornerRadius: CGFloat = 10
    static let popupCornerRadius: CGFloat = 12
    static let contentPadding: CGFloat = 14
    static let selectionStrokeWidth: CGFloat = 2
    static let borderStrokeWidth: CGFloat = 1
    static let baseFillOpacity: Double = 0.06
    static let elevatedFillOpacity: Double = 0.08
    static let highlightFillOpacity: Double = 0.03
    static let subtleFillOpacity: Double = 0.05
    static let secondaryBorderOpacity: Double = 0.12
    static let subtleBorderOpacity: Double = 0.08
    static let cardFillOpacity: Double = 0.06
    static let runButtonCornerRadius: CGFloat = 10
    static let runButtonHorizontalPadding: CGFloat = 12
    static let runButtonVerticalPadding: CGFloat = 6
    static let runButtonFillOpacity: Double = 0.08
}

struct GraphNodeChromeContainer<Content: View>: View {
    let contentPadding: CGFloat
    let tint: Color
    let border: Color
    let isSelected: Bool
    let isHoverReceiver: Bool
    let showsError: Bool
    let errorTint: Color
    let errorBorder: Color
    let leadingOverlay: AnyView?
    let trailingOverlay: AnyView?
    @ViewBuilder let content: () -> Content

    init(
        contentPadding: CGFloat = GraphNodeStyleTokens.contentPadding,
        tint: Color,
        border: Color,
        isSelected: Bool,
        isHoverReceiver: Bool,
        showsError: Bool = false,
        errorTint: Color = Color.red.opacity(0.18),
        errorBorder: Color = Color.red.opacity(0.55),
        leadingOverlay: AnyView? = nil,
        trailingOverlay: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.contentPadding = contentPadding
        self.tint = tint
        self.border = border
        self.isSelected = isSelected
        self.isHoverReceiver = isHoverReceiver
        self.showsError = showsError
        self.errorTint = errorTint
        self.errorBorder = errorBorder
        self.leadingOverlay = leadingOverlay
        self.trailingOverlay = trailingOverlay
        self.content = content
    }

    var body: some View {
        content()
            .padding(contentPadding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                        .fill(Color.white.opacity(GraphNodeStyleTokens.baseFillOpacity))
                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                        .fill(showsError ? errorTint : tint)
                        .blendMode(.screen)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                    .stroke(showsError ? errorBorder : border, lineWidth: GraphNodeStyleTokens.borderStrokeWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                    .stroke(isHoverReceiver ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: GraphNodeStyleTokens.selectionStrokeWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GraphNodeStyleTokens.cornerRadius)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: GraphNodeStyleTokens.selectionStrokeWidth)
            )
            .overlay(alignment: .leading) {
                leadingOverlay
            }
            .overlay(alignment: .trailing) {
                trailingOverlay
            }
            .contentShape(Rectangle())
    }
}

/// Name label for an output port nub. Drawn just outside the node's trailing edge, above
/// the link line, so node content can't cover it — AppKit-backed text fields always draw
/// above SwiftUI, and warnings/controls run right up to the node edge.
struct GraphOutputPortLabel: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.overlay(alignment: .trailing) {
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                .frame(width: 120, alignment: .leading)
                // Leading edge sits 9pt right of the node edge (the nub reaches +5pt).
                .alignmentGuide(.trailing) { _ in -9 }
                .offset(y: -11)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func graphOutputPortLabel(_ text: String) -> some View {
        modifier(GraphOutputPortLabel(text: text))
    }
}

/// Icon, title, subtitle and detail line shown for a node when the canvas is zoomed out
/// (or in performance mode). Shared by the summary cards and the utility nodes' compact mode.
struct GraphNodeCompactSummary: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let detail: String?
    let accent: Color
    /// Height of the content area, so a compact node can keep its full form's footprint and
    /// switching forms at the zoom threshold doesn't make nodes jump in size.
    var minHeight: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: GraphNodeStyleTokens.secondaryCornerRadius, style: .continuous)
                        .fill(accent.opacity(0.18))
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
            }
        }
        // Top-aligned so the title sits where the full node's header does.
        .frame(minHeight: minHeight, alignment: .topLeading)
    }
}

/// Content height for a compact node that should match its full form's measured height,
/// given the compact form's vertical padding on each side.
func graphNodeCompactContentHeight(fullHeight: CGFloat?, padding: CGFloat) -> CGFloat? {
    guard let fullHeight, fullHeight > 1 else { return nil }
    return max(0, fullHeight - padding * 2)
}

extension GraphNodeCategory {
    /// Node fill when shown compact; stronger than `tintColor` so the category reads zoomed out.
    var compactTintColor: Color { accentColor.opacity(0.18) }
    /// Node border when shown compact.
    var compactBorderColor: Color { accentColor.opacity(0.55) }
}

// MARK: - Action run status

/// Running / Sent / Failed line for an action node, with the error text visible on the node
/// (not only in a tooltip, which iPad and VoiceOver can't reach).
struct GraphActionRunStatusRow: View {
    let status: GraphActionRunStatus
    let onDismiss: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch status {
            case .running:
                ProgressView()
                    .controlSize(.mini)
                Text("Sending…")
                    .font(.caption.weight(.semibold))
            case .succeeded(let detail):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .accessibilityHidden(true)
                Text("Sent")
                    .font(.caption.weight(.semibold))
                if !detail.isEmpty, detail != "Sent" {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            case .failed(let message):
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(Color.red)
                    .accessibilityHidden(true)
                Text("Failed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if status.isFailure, let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .frame(minWidth: graphMinimumHitTarget, minHeight: graphMinimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(status.isFailure ? Color.red.opacity(0.14) : Color.white.opacity(0.05))
        )
        .transition(.opacity)
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: status)
        .accessibilityElement(children: .combine)
    }
}

/// A node warning/error written out on the node, paired with its icon.
struct GraphNodeMessageRow: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isError ? Color.red : Color.yellow)
                .accessibilityHidden(true)
            Text(isError ? "Error:" : "Warning:")
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Live Mode confirmation

/// A hardware write that needs a yes while Live Mode is on.
struct GraphLiveConfirmation: Identifiable {
    let id = UUID()
    /// Names the target, e.g. "Send to “FOH X32”?".
    let title: String
    let message: String
    let confirmLabel: String
    let action: () -> Void
}

/// Key Live Mode is stored under (see DashboardRootView).
let graphLiveModeStorageKey = "dashboard_live_mode_enabled"

extension View {
    /// Shows `pending` as a confirmation dialog; Confirm runs its action.
    func graphLiveConfirmationDialog(_ pending: Binding<GraphLiveConfirmation?>) -> some View {
        confirmationDialog(
            pending.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { confirmation in
            Button(confirmation.confirmLabel) {
                confirmation.action()
            }
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: { confirmation in
            Text(confirmation.message)
        }
    }
}

// MARK: - Ports

/// Smallest hit target for graph controls: 28pt on macOS, 44pt on iPad.
#if os(macOS)
let graphMinimumHitTarget: CGFloat = 28
#else
let graphMinimumHitTarget: CGFloat = 44
#endif

/// Hit area for an output port, larger than its drawn frame so the visuals and port layout
/// (which link geometry depends on) stay the same. It grows outward, past the node edge,
/// and vertically up to `maxHeight` so stacked ports (20pt + 14pt spacing) don't overlap.
struct GraphPortHitShape: Shape {
    var maxHeight: CGFloat = 34

    func path(in rect: CGRect) -> Path {
        let height = min(maxHeight, max(rect.height, graphMinimumHitTarget))
        let width = max(rect.width + 12, graphMinimumHitTarget + 8)
        return Path(CGRect(
            x: rect.maxX + 12 - width,
            y: rect.midY - height / 2,
            width: width,
            height: height
        ))
    }
}

/// Hover ring and pointer cursor for an output port. Apply to the port's ZStack (drawn
/// frame trailing-aligned, nub centered on the trailing edge).
struct GraphPortHoverFeedback: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                Circle()
                    .stroke(Color.accentColor.opacity(isHovering ? 0.9 : 0), lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .offset(x: 9)
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
            #if os(macOS)
            .pointerStyle(.link)
            #else
            .hoverEffect(.highlight)
            #endif
    }
}

extension View {
    func graphPortHoverFeedback() -> some View {
        modifier(GraphPortHoverFeedback())
    }
}

// MARK: - Node link menus

/// A node or link listed in a node's "Connect to…" / "Delete Link" menu.
struct GraphNodeMenuTarget: Identifiable, Equatable {
    let id: UUID
    let name: String
}

/// Menu items built only when the menu opens (its body is evaluated lazily), so listing
/// compatible nodes doesn't run on every graph render.
struct GraphNodeMenuTargetList: View {
    let emptyText: String
    let targets: () -> [GraphNodeMenuTarget]
    let onSelect: (UUID) -> Void

    var body: some View {
        let items = targets()
        if items.isEmpty {
            Text(emptyText)
        } else {
            ForEach(items) { item in
                Button(item.name) { onSelect(item.id) }
            }
        }
    }
}

/// "Connect to <node>" accessibility actions, so VoiceOver and keyboard users can link
/// nodes without dragging a port.
struct GraphNodeConnectAccessibility: ViewModifier {
    let targets: () -> [GraphNodeMenuTarget]
    let onConnect: (UUID) -> Void

    func body(content: Content) -> some View {
        content.accessibilityActions {
            GraphNodeConnectActionList(targets: targets, onConnect: onConnect)
        }
    }
}

private struct GraphNodeConnectActionList: View {
    let targets: () -> [GraphNodeMenuTarget]
    let onConnect: (UUID) -> Void

    var body: some View {
        ForEach(targets()) { target in
            Button("Connect to \(target.name)") { onConnect(target.id) }
        }
    }
}
