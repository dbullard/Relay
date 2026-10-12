import SwiftUI

#if os(macOS)
import AppKit

struct NDIVideoSurfaceRepresentable: NSViewRepresentable {
    let presentation: NDIPipelinePresentation?
    let pipeline: NDIFramePipeline?
    let displayMode: NDIModuleModel.DisplayMode

    func makeNSView(context: Context) -> NDIVideoSurfaceHostingView {
        let view = NDIVideoSurfaceHostingView()
        view.apply(pipeline: pipeline, displayMode: displayMode)
        return view
    }

    func updateNSView(_ nsView: NDIVideoSurfaceHostingView, context: Context) {
        nsView.apply(pipeline: pipeline, displayMode: displayMode)
    }
}

final class NDIVideoSurfaceHostingView: NSView {
    private let backgroundLayer = CAGradientLayer()
    private let videoImageLayer = CALayer()
    private let videoGradientLayer = CAGradientLayer()
    private let vignetteLayer = CAGradientLayer()
    private let programBarLayer = CALayer()
    private let previewPaneLayers: [CALayer] = (0..<4).map { _ in CALayer() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        backgroundLayer.colors = [
            NSColor(calibratedWhite: 0.07, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.16, alpha: 1.0).cgColor
        ]
        backgroundLayer.startPoint = CGPoint(x: 0, y: 1)
        backgroundLayer.endPoint = CGPoint(x: 1, y: 0)

        videoImageLayer.contentsGravity = .resizeAspect
        videoImageLayer.masksToBounds = true

        videoGradientLayer.startPoint = CGPoint(x: 0, y: 1)
        videoGradientLayer.endPoint = CGPoint(x: 1, y: 0)
        videoGradientLayer.colors = [
            NSColor(calibratedRed: 0.20, green: 0.28, blue: 0.48, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.16, alpha: 1.0).cgColor
        ]

        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 1)
        vignetteLayer.endPoint = CGPoint(x: 0.5, y: 0)
        vignetteLayer.colors = [
            NSColor.black.withAlphaComponent(0.10).cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.32).cgColor
        ]
        vignetteLayer.locations = [0.0, 0.55, 1.0]

        programBarLayer.cornerRadius = 6
        programBarLayer.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor

        for paneLayer in previewPaneLayers {
            paneLayer.cornerRadius = 8
            paneLayer.borderWidth = 1
            paneLayer.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            paneLayer.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        }

        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(videoGradientLayer)
        layer?.addSublayer(videoImageLayer)
        for paneLayer in previewPaneLayers {
            layer?.addSublayer(paneLayer)
        }
        layer?.addSublayer(programBarLayer)
        layer?.addSublayer(vignetteLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        videoGradientLayer.frame = bounds
        videoImageLayer.frame = bounds
        vignetteLayer.frame = bounds

        let inset = min(max(16, bounds.width * 0.04), 28)
        let paneSpacing: CGFloat = 10
        let contentBounds = bounds.insetBy(dx: inset, dy: inset)
        let paneWidth = max(48, (contentBounds.width - paneSpacing) / 2)
        let paneHeight = max(36, (contentBounds.height - paneSpacing) / 2)
        for (index, paneLayer) in previewPaneLayers.enumerated() {
            let row = CGFloat(index / 2)
            let column = CGFloat(index % 2)
            paneLayer.frame = CGRect(
                x: contentBounds.minX + column * (paneWidth + paneSpacing),
                y: contentBounds.maxY - paneHeight - row * (paneHeight + paneSpacing),
                width: paneWidth,
                height: paneHeight
            )
        }
        programBarLayer.frame = CGRect(
            x: max(inset, bounds.width - inset - 88),
            y: inset,
            width: 82,
            height: 8
        )
    }

    func apply(pipeline: NDIFramePipeline?, displayMode: NDIModuleModel.DisplayMode) {
        applyVideoContent(pipeline: pipeline, displayMode: displayMode)
    }

    private func applyVideoContent(pipeline: NDIFramePipeline?, displayMode: NDIModuleModel.DisplayMode) {
        if let cgImage = pipeline?.latestFrame?.cgImage {
            videoImageLayer.contents = cgImage
            videoImageLayer.isHidden = false
            videoImageLayer.contentsGravity = displayMode == .fill ? .resizeAspectFill : .resizeAspect
            videoGradientLayer.isHidden = true
            previewPaneLayers.forEach { $0.isHidden = true }
            programBarLayer.isHidden = true
            vignetteLayer.isHidden = false
            return
        }

        videoImageLayer.contents = nil
        videoImageLayer.isHidden = true
        videoGradientLayer.isHidden = false
        previewPaneLayers.forEach { $0.isHidden = false }
        programBarLayer.isHidden = false
        vignetteLayer.isHidden = false
        applySyntheticVideoFrame(pipeline: pipeline)
    }

    private func applySyntheticVideoFrame(pipeline: NDIFramePipeline?) {
        let frameNumber = pipeline?.latestFrameNumber ?? 0
        let sourceSeed = UInt64(abs((pipeline?.connectionInfo?.sourceName ?? "ndi").hashValue))
        let phase = CGFloat((frameNumber + sourceSeed) % 240) / 240.0

        let hueA = phase
        let hueB = (phase + 0.14).truncatingRemainder(dividingBy: 1.0)
        videoGradientLayer.colors = [
            NSColor(calibratedHue: hueA, saturation: 0.55, brightness: 0.82, alpha: 1.0).cgColor,
            NSColor(calibratedHue: hueB, saturation: 0.62, brightness: 0.28, alpha: 1.0).cgColor
        ]

        let activeIndex = Int((frameNumber / 12) % UInt64(max(1, previewPaneLayers.count)))
        for (index, paneLayer) in previewPaneLayers.enumerated() {
            let panePhase = CGFloat((frameNumber + UInt64(index * 13)) % 120) / 120.0
            let brightness = index == activeIndex ? 0.86 : 0.42 + panePhase * 0.16
            let alpha: CGFloat = index == activeIndex ? 0.92 : 0.72
            paneLayer.backgroundColor = NSColor(
                calibratedHue: (phase + CGFloat(index) * 0.08).truncatingRemainder(dividingBy: 1.0),
                saturation: 0.42,
                brightness: brightness,
                alpha: alpha
            ).cgColor
            paneLayer.borderColor = (index == activeIndex
                ? NSColor.white.withAlphaComponent(0.34)
                : NSColor.white.withAlphaComponent(0.10)).cgColor
        }

        let normalized = CGFloat((frameNumber % 90)) / 90.0
        var barFrame = programBarLayer.frame
        let minX = bounds.minX + 12
        let maxX = max(minX, bounds.maxX - barFrame.width - 12)
        barFrame.origin.x = minX + (maxX - minX) * normalized
        programBarLayer.frame = barFrame
        programBarLayer.opacity = pipeline?.latestFrame == nil ? 0.25 : 0.95
    }
}
#endif
