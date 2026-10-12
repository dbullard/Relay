import SwiftUI

struct ModuleCornerClip: ViewModifier {
    let radius: CGFloat
    let style: ModuleCornerStyle
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(
                ModuleCorners(
                    radius: radius,
                    style: style
                )
            )
        } else {
            content
        }
    }
}

struct DashboardTileTitleBadge: View {
    let name: String

    private var titleText: String {
        let rawTitle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawTitle.isEmpty ? "Tile" : rawTitle
    }

    var body: some View {
        Text(titleText)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.45))
            )
            .padding(8)
    }
}

struct DashboardEmptyTilePlaceholder: View {
    let contentPadding: CGFloat

    private var hint: String {
        #if os(iOS)
        "Double-tap to add content and edit."
        #else
        "Double-click to add content and edit."
        #endif
    }

    var body: some View {
        VStack(spacing: 8) {
            DashboardSymbolImage("square.grid.2x2")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
            Text("Empty Tile")
                .font(.headline)
                .foregroundStyle(.white)
            Text(hint)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(contentPadding)
    }
}
