import SwiftUI

struct GraphDashboardCanvasView<Content: View, Popover: View>: View {
    let geoSize: CGSize
    let isWorkEnabled: Bool
    @Binding var showAddNodePopover: Bool
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat
    let onBackgroundDoubleTap: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let popover: () -> Popover

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    guard isWorkEnabled, !showAddNodePopover else { return }
                    onBackgroundDoubleTap()
                }

            ZStack(alignment: .topLeading) {
                ZStack {
                    content()
                }
                .frame(width: geoSize.width, height: geoSize.height, alignment: .topLeading)
                .coordinateSpace(.named("GraphSpace"))
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(x: pan.width, y: pan.height)
            }
            .frame(width: geoSize.width, height: geoSize.height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(!showAddNodePopover)
            .viewportPanZoom(
                pan: $pan,
                zoom: $zoom,
                isEnabled: isWorkEnabled && !showAddNodePopover,
                showsControls: false,
                blocksOverScrollableViews: false
            )

            if showAddNodePopover {
                popover()
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
    }
}
