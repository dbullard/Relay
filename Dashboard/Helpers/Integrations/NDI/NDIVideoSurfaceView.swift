import SwiftUI

struct NDIVideoSurfaceView: View {
    let presentation: NDIPipelinePresentation?
    let displayMode: NDIModuleModel.DisplayMode
    let pipeline: NDIFramePipeline?

    var body: some View {
        Group {
#if os(macOS)
            NDIVideoSurfaceRepresentable(
                presentation: presentation,
                pipeline: pipeline,
                displayMode: displayMode
            )
            .overlay {
                // Show status overlay when no live video frame is available
                if pipeline?.latestFrame?.cgImage == nil, let presentation {
                    statusOverlay(presentation: presentation)
                }
            }
#else
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                if let cgImage = pipeline?.latestFrame?.cgImage {
                    Image(decorative: cgImage, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: displayMode == .fill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .overlay {
                if pipeline?.latestFrame?.cgImage == nil, let presentation {
                    statusOverlay(presentation: presentation)
                }
            }
#endif
        }
    }

    private func statusOverlay(presentation: NDIPipelinePresentation) -> some View {
        VStack(spacing: 8) {
#if os(iOS)
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
#endif
            Text(presentation.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            if let subtitle = presentation.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if case .retryNow(let action) = presentation.recoveryAction {
                Button("Retry Now", action: action)
                    .font(.caption.weight(.semibold))
                    .padding(.top, 4)
            }
        }
        .padding(16)
    }
}
