import SwiftUI

enum DashboardTileSnapEdge: Hashable {
    case left
    case right
    case top
    case bottom
}

struct DashboardTileSnapHighlightOverlay: View {
    let activeEdges: Set<DashboardTileSnapEdge>
    let isLiveMode: Bool

    var body: some View {
        if !isLiveMode, !activeEdges.isEmpty {
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let snapColor = Color(red: 0.63, green: 0.36, blue: 0.86).opacity(0.95)
                let thickness: CGFloat = 3
                let outset: CGFloat = 4
                let extendedWidth = width + (outset * 2)
                let extendedHeight = height + (outset * 2)

                ZStack {
                    if activeEdges.contains(.left) {
                        Rectangle()
                            .fill(snapColor)
                            .frame(width: thickness, height: extendedHeight)
                            .position(x: -outset + (thickness / 2), y: height / 2)
                    }
                    if activeEdges.contains(.right) {
                        Rectangle()
                            .fill(snapColor)
                            .frame(width: thickness, height: extendedHeight)
                            .position(x: width + outset - (thickness / 2), y: height / 2)
                    }
                    if activeEdges.contains(.top) {
                        Rectangle()
                            .fill(snapColor)
                            .frame(width: extendedWidth, height: thickness)
                            .position(x: width / 2, y: -outset + (thickness / 2))
                    }
                    if activeEdges.contains(.bottom) {
                        Rectangle()
                            .fill(snapColor)
                            .frame(width: extendedWidth, height: thickness)
                            .position(x: width / 2, y: height + outset - (thickness / 2))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
