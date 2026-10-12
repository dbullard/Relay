import SwiftUI

struct DashboardTileBackgroundFill: View {
    let tile: DashboardTileModel
    let cornerRadius: CGFloat

    private var backgroundColor: Color {
        let style = tile.backgroundStyle
        let opacity = tile.backgroundOpacity

        let baseColor: Color
        if let modelColor = tile.backgroundCustomColor?.swiftUIColor {
            baseColor = modelColor
        } else {
            baseColor = style.color
        }

        return baseColor.opacity(opacity)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if let gradient = tile.backgroundGradient {
            shape
                .fill(
                    LinearGradient(
                        colors: [gradient.startColor.swiftUIColor, gradient.endColor.swiftUIColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(tile.backgroundOpacity)
        } else {
            shape.fill(backgroundColor)
        }
    }
}
