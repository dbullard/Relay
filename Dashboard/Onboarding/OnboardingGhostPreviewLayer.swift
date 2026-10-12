import SwiftUI

/// Renders dashed ghost-outline previews of the Review & Create step's checked
/// tile candidates, before they become real DashboardTileModels. Visually mirrors
/// DashboardSnapRegionPreviewLayer's dashed-outline stroke style, but is driven
/// by a plain frame dictionary instead of a live drag session.
struct OnboardingGhostPreviewLayer: View {
    let frames: [UUID: CGRect]
    let titlesByID: [UUID: String]

    private static let outlineColor = Color(red: 0.63, green: 0.36, blue: 0.86)

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(frames.keys), id: \.self) { candidateID in
                if let rect = frames[candidateID] {
                    outline(for: rect, title: titlesByID[candidateID] ?? "")
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func outline(for rect: CGRect, title: String) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(Self.outlineColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            Text(title)
                .font(.caption)
                .foregroundStyle(Self.outlineColor)
                .padding(4)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}
