import SwiftUI

struct NDIVideoSurfaceView: View {
    let presentation: NDIPipelinePresentation?
    let displayMode: NDIModuleModel.DisplayMode
    let pipeline: NDIFramePipeline?

    var body: some View {
        Group {
#if os(macOS)
            // Status (and Retry) is drawn once, by NDIModuleView, not here.
            NDIVideoSurfaceRepresentable(
                presentation: presentation,
                pipeline: pipeline,
                displayMode: displayMode
            )
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
#endif
        }
    }
}
