import SwiftUI

/// Small floating "W × H" readout shown above a tile while it is being
/// resized.
struct DashboardTileResizeSizeHUD: View {
    let size: CGSize

    var body: some View {
        Text("\(Int(size.width.rounded())) × \(Int(size.height.rounded()))")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.75), in: Capsule())
    }
}
