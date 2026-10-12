import SwiftUI

enum TileSelectionSource {
    case canvas
    case overviewTiles
    case overviewGroup
}

struct GridBackground: View {
    let gridSize: CGFloat
    /// 0.0 ... 1.0 - user-controlled multiplier for the grid line opacity.
    let lineOpacity: Double

    var body: some View {
        let opacity = min(1.0, max(0.0, lineOpacity))

        Group {
            if gridSize <= 0 || opacity <= 0 {
                Color.clear
            } else {
                Canvas { context, size in
                    let width = size.width
                    let height = size.height

                    #if os(macOS)
                    let minorOpacity = 0.55 * opacity
                    let majorOpacity = 0.85 * opacity
                    let minorWidth: CGFloat = 1.2
                    let majorWidth: CGFloat = 2.0
                    #else
                    let minorOpacity = 0.40 * opacity
                    let majorOpacity = 0.70 * opacity
                    let minorWidth: CGFloat = 1.0
                    let majorWidth: CGFloat = 1.8
                    #endif

                    let majorEvery = 5

                    // Minor vertical lines.
                    var index = 0
                    var x: CGFloat = 0
                    while x <= width {
                        if index % majorEvery != 0 {
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                            context.stroke(path, with: .color(.white.opacity(minorOpacity)), lineWidth: minorWidth)
                            context.stroke(path, with: .color(.black.opacity(minorOpacity * 0.22)), lineWidth: minorWidth)
                        }
                        index += 1
                        x += gridSize
                    }

                    // Minor horizontal lines.
                    index = 0
                    var y: CGFloat = 0
                    while y <= height {
                        if index % majorEvery != 0 {
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                            context.stroke(path, with: .color(.white.opacity(minorOpacity)), lineWidth: minorWidth)
                            context.stroke(path, with: .color(.black.opacity(minorOpacity * 0.22)), lineWidth: minorWidth)
                        }
                        index += 1
                        y += gridSize
                    }

                    // Major vertical lines.
                    index = 0
                    x = 0
                    while x <= width {
                        if index % majorEvery == 0 {
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                            context.stroke(path, with: .color(.white.opacity(majorOpacity)), lineWidth: majorWidth)
                            context.stroke(path, with: .color(.black.opacity(majorOpacity * 0.18)), lineWidth: majorWidth)
                        }
                        index += 1
                        x += gridSize
                    }

                    // Major horizontal lines.
                    index = 0
                    y = 0
                    while y <= height {
                        if index % majorEvery == 0 {
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                            context.stroke(path, with: .color(.white.opacity(majorOpacity)), lineWidth: majorWidth)
                            context.stroke(path, with: .color(.black.opacity(majorOpacity * 0.18)), lineWidth: majorWidth)
                        }
                        index += 1
                        y += gridSize
                    }

                    var border = Path()
                    border.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                    context.stroke(border, with: .color(.white.opacity(0.04)), lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Simple bottom fade overlay to visually indicate that content is clipped
/// when a module is constrained by a max height.
///
/// We only draw the fade when the rendered height is effectively equal
/// to the provided `maxHeight`, which implies that the view is hitting
/// its vertical cap and may be clipping additional content. If the view
/// is shorter than `maxHeight`, no fade is shown.
@ViewBuilder
func bottomFadeOverlay(maxHeight: CGFloat?) -> some View {
    if let maxHeight, maxHeight > 0 {
        GeometryReader { geo in
            let renderedHeight = geo.size.height
            let epsilon: CGFloat = 0.5

            // Only show the fade if we're essentially "full" height.
            if abs(renderedHeight - maxHeight) <= epsilon {
                let fadeHeight: CGFloat = min(16, max(8, renderedHeight * 0.2))
                LinearGradient(
                    gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.2)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    } else {
        EmptyView()
    }
}
