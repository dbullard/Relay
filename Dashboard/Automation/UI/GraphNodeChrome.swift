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
