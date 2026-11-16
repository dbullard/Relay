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
    }
}

extension GraphNodeCategory {
    /// Node fill when shown compact; stronger than `tintColor` so the category reads zoomed out.
    var compactTintColor: Color { accentColor.opacity(0.18) }
    /// Node border when shown compact.
    var compactBorderColor: Color { accentColor.opacity(0.55) }
}
