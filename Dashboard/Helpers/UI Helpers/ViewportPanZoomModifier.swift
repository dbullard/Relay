//
//  ViewportPanZoomModifier.swift
//  Relay
//
//  Created by David Bullard on 1/6/26.
//


import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
import WebKit
#endif

/// Reusable pan/zoom controller that updates external bindings.
///
/// This modifier is intentionally generic so it can be reused across multiple surfaces
/// (e.g., a node graph, a canvas, a timeline, etc.).
///
/// Important: This modifier does NOT apply transforms to the content itself.
/// It only updates `pan` and `zoom` bindings so the host view can decide how to
/// map between its model-space and view-space.
struct ViewportPanZoomModifier: ViewModifier {
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat
    @Binding var isInteracting: Bool

    var isEnabled: Bool = true
    var showsControls: Bool = true
    var blocksOverScrollableViews: Bool = true
    var blocksOverWebViews: Bool = false

    // Tuning
    var zoomRange: ClosedRange<CGFloat> = 0.25...3.00
    var zoomStep: CGFloat = 0.12

    // Gesture state
    @State private var baseZoom: CGFloat = 1.0
    @State private var basePan: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var isZoomPopoverPresented: Bool = false

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .onAppear {
                    viewportSize = proxy.size
                }
                .onChange(of: proxy.size, initial: false) { _, newSize in
                    viewportSize = newSize
                }
                .overlay(alignment: .bottom) {
                    if isEnabled && showsControls {
                        HStack {
                            Spacer(minLength: 0)
                            ViewportPanZoomControls(
                                pan: $pan,
                                zoom: $zoom,
                                zoomRange: zoomRange,
                                zoomStep: zoomStep
                            )
                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 12)
                    }
                }
                .onChange(of: isEnabled, initial: false) { _, enabled in
                    if !enabled {
                        isZoomPopoverPresented = false
                        isInteracting = false
                    }
                }
                #if os(macOS)
                // On macOS we capture both scroll-pan and trackpad pinch-zoom in the NSView overlay
                // so pinch continues to work even though the overlay sits above the content.
                .overlay(
                    TrackpadPanZoomEventMonitor(
                        pan: $pan,
                        zoom: $zoom,
                        isInteracting: $isInteracting,
                        zoomRange: zoomRange,
                        isEnabled: isEnabled,
                        blocksOverScrollableViews: blocksOverScrollableViews,
                        blocksOverWebViews: blocksOverWebViews
                    )
                )
                #else
                // iOS/iPadOS:
                // - Single-finger gestures should interact with content (nodes).
                // - Two-finger pan should control viewport.
                // - Pinch should control zoom.
                .overlay(TouchPanZoomOverlay(pan: $pan, zoom: $zoom, isInteracting: $isInteracting, zoomRange: zoomRange, isEnabled: isEnabled))
                #endif
                .onAppear {
                    baseZoom = zoom
                    basePan = pan
                }
        }
    }
    private func applyZoom(_ newZoom: CGFloat, anchor: CGPoint) {
        let clamped = clamp(newZoom, zoomRange.lowerBound, zoomRange.upperBound)
        let oldZ = zoom
        guard oldZ > 0, abs(clamped - oldZ) > 0.00001 else { return }

        let s = clamped / oldZ
        // Keep the content point under the screen anchor stationary.
        // anchorScreen = anchorViewPoint * oldZoom + pan
        let anchorScreen = CGPoint(
            x: (anchor.x * oldZ) + pan.width,
            y: (anchor.y * oldZ) + pan.height
        )
        let newPanW = (pan.width * s) + ((1.0 - s) * anchorScreen.x)
        let newPanH = (pan.height * s) + ((1.0 - s) * anchorScreen.y)

        zoom = clamped
        pan = CGSize(width: newPanW, height: newPanH)

        baseZoom = zoom
        basePan = pan
    }

    private var defaultZoomAnchor: CGPoint {
        CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5)
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard isEnabled else { return }
                let proposed = baseZoom * value.magnification
                zoom = clamp(proposed, zoomRange.lowerBound, zoomRange.upperBound)
            }
            .onEnded { _ in
                baseZoom = zoom
            }
    }

    // MARK: - Controls

    private let zoomPresets: [CGFloat] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00]

    // Controls moved to ViewportPanZoomControls for reuse outside scaled content.

    private func zoomIn() {
        applyZoom(zoom + zoomStep, anchor: defaultZoomAnchor)
    }

    private func zoomOut() {
        applyZoom(zoom - zoomStep, anchor: defaultZoomAnchor)
    }

    private func reset() {
        zoom = 1.0
        pan = .zero
        baseZoom = zoom
        basePan = pan
    }

private func clamp<T: Comparable>(_ value: T, _ lo: T, _ hi: T) -> T {
        min(max(value, lo), hi)
    }
}

struct ViewportPanZoomControls: View {
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat

    var zoomRange: ClosedRange<CGFloat> = 0.25...3.00
    var zoomStep: CGFloat = 0.12
    var contentSize: CGSize? = nil
    var viewportSize: CGSize? = nil
    var onActualSize: (() -> Void)? = nil
    var onFitToWindow: (() -> Void)? = nil

    @State private var isZoomPopoverPresented: Bool = false

    private let zoomPresets: [CGFloat] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00]

    var body: some View {
        GeometryReader { proxy in
            controls(defaultZoomAnchor: CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 44)
    }

    private func controls(defaultZoomAnchor: CGPoint) -> some View {
        HStack(spacing: 10) {
            Button { zoomIn(anchor: defaultZoomAnchor) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)

            Button { zoomOut(anchor: defaultZoomAnchor) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)

            Button {
                isZoomPopoverPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.85))
                }
                .frame(minWidth: 60, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isZoomPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zoom")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.bottom, 2)

                    ForEach(zoomPresets, id: \.self) { z in
                        Button {
                            applyZoom(z, anchor: defaultZoomAnchor)
                            isZoomPopoverPresented = false
                        } label: {
                            let pct = Int((z * 100).rounded())
                            HStack {
                                Text("\(pct)%")
                                Spacer(minLength: 12)
                                if abs(z - zoom) < 0.00001 {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(abs(z - zoom) < 0.00001 ? 0.08 : 0.0))
                        )
                    }

                    Divider().padding(.vertical, 2)

                    Button {
                        actualSize()
                        isZoomPopoverPresented = false
                    } label: {
                        Label("Actual Size (100%)", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)

                    Button {
                        fitToWindow()
                        isZoomPopoverPresented = false
                    } label: {
                        Label("Fit to Window", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(minWidth: 180)
            }

            Button { fitToWindow() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Fit canvas to window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 6)
    }

    private func zoomIn(anchor: CGPoint) {
        applyZoom(zoom + zoomStep, anchor: anchor)
    }

    private func zoomOut(anchor: CGPoint) {
        applyZoom(zoom - zoomStep, anchor: anchor)
    }

    private func actualSize() {
        if let onActualSize {
            onActualSize()
            return
        }

        zoom = 1.0
        if let contentSize, let viewportSize, viewportSize.width > 0, viewportSize.height > 0 {
            let targetWidth = contentSize.width * zoom
            let targetHeight = contentSize.height * zoom
            pan = CGSize(
                width: (viewportSize.width - targetWidth) * 0.5,
                height: (viewportSize.height - targetHeight) * 0.5
            )
        } else {
            pan = .zero
        }
    }

    private func fitToWindow() {
        if let onFitToWindow {
            onFitToWindow()
            return
        }

        guard let contentSize, let viewportSize,
              contentSize.width > 0, contentSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else {
            actualSize()
            return
        }

        let fittedZoom = clamp(
            min(viewportSize.width / contentSize.width, viewportSize.height / contentSize.height),
            zoomRange.lowerBound,
            zoomRange.upperBound
        )
        let targetWidth = contentSize.width * fittedZoom
        let targetHeight = contentSize.height * fittedZoom

        zoom = fittedZoom
        pan = CGSize(
            width: (viewportSize.width - targetWidth) * 0.5,
            height: (viewportSize.height - targetHeight) * 0.5
        )
    }

    private func applyZoom(_ newZoom: CGFloat, anchor: CGPoint) {
        let clamped = clamp(newZoom, zoomRange.lowerBound, zoomRange.upperBound)
        let oldZ = zoom
        guard oldZ > 0, abs(clamped - oldZ) > 0.00001 else { return }

        let s = clamped / oldZ
        let anchorScreen = CGPoint(
            x: (anchor.x * oldZ) + pan.width,
            y: (anchor.y * oldZ) + pan.height
        )
        let newPanW = (pan.width * s) + ((1.0 - s) * anchorScreen.x)
        let newPanH = (pan.height * s) + ((1.0 - s) * anchorScreen.y)

        zoom = clamped
        pan = CGSize(width: newPanW, height: newPanH)
    }

    private func clamp<T: Comparable>(_ value: T, _ lo: T, _ hi: T) -> T {
        min(max(value, lo), hi)
    }
}

#if os(iOS)
/// iOS/iPadOS overlay that captures *two-finger* pan and pinch-zoom WITHOUT breaking single-finger interactions.
///
/// Implementation detail: we attach recognizers to the containing UIWindow so we don't depend on hit-testing
/// of a transparent overlay (which can prevent the second touch from ever reaching us).
private struct TouchPanZoomOverlay: UIViewRepresentable {
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat
    @Binding var isInteracting: Bool

    var zoomRange: ClosedRange<CGFloat>
    var isEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        let v = AnchorView()
        v.isUserInteractionEnabled = false // never intercept taps/drags; window recognizers do the work

        context.coordinator.anchorView = v
        context.coordinator.panBinding = $pan
        context.coordinator.zoomBinding = $zoom
        context.coordinator.interactionBinding = $isInteracting
        context.coordinator.zoomRange = zoomRange
        context.coordinator.isEnabled = isEnabled

        // Attach as soon as we land in a window.
        v.onDidMoveToWindow = { [weak coordinator = context.coordinator] in
            coordinator?.ensureAttachedToWindowIfPossible()
        }

        // Also try once on the next runloop in case updateUIView hasn't fired yet.
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.ensureAttachedToWindowIfPossible()
        }

        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.anchorView = uiView
        context.coordinator.panBinding = $pan
        context.coordinator.zoomBinding = $zoom
        context.coordinator.interactionBinding = $isInteracting
        context.coordinator.zoomRange = zoomRange
        context.coordinator.isEnabled = isEnabled

        context.coordinator.ensureAttachedToWindowIfPossible()
        if let av = uiView as? AnchorView {
            av.onDidMoveToWindow = { [weak coordinator = context.coordinator] in
                coordinator?.ensureAttachedToWindowIfPossible()
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachFromWindow()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(pan: $pan, zoom: $zoom, isInteracting: $isInteracting, zoomRange: zoomRange, isEnabled: isEnabled)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Updated in updateUIView
        weak var anchorView: UIView?
        var panBinding: Binding<CGSize>
        var zoomBinding: Binding<CGFloat>
        var interactionBinding: Binding<Bool>
        var zoomRange: ClosedRange<CGFloat>
        var isEnabled: Bool

        private var basePan: CGSize = .zero
        private var baseZoom: CGFloat = 1.0
        private var isPanning: Bool = false
        private var isPinching: Bool = false

        private weak var attachedWindow: UIWindow?
        private lazy var panGR: UIPanGestureRecognizer = {
            let gr = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            gr.minimumNumberOfTouches = 2
            gr.maximumNumberOfTouches = 2
            gr.cancelsTouchesInView = false
            gr.delegate = self
            return gr
        }()

        private lazy var pinchGR: UIPinchGestureRecognizer = {
            let gr = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            gr.cancelsTouchesInView = false
            gr.delegate = self
            return gr
        }()

        init(pan: Binding<CGSize>, zoom: Binding<CGFloat>, isInteracting: Binding<Bool>, zoomRange: ClosedRange<CGFloat>, isEnabled: Bool) {
            self.panBinding = pan
            self.zoomBinding = zoom
            self.interactionBinding = isInteracting
            self.zoomRange = zoomRange
            self.isEnabled = isEnabled
        }

        func ensureAttachedToWindowIfPossible() {
            guard let v = anchorView, let win = v.window else { return }
            if attachedWindow === win { return }
            detachFromWindow()
            attachedWindow = win
            win.addGestureRecognizer(panGR)
            win.addGestureRecognizer(pinchGR)
        }

        func detachFromWindow() {
            if let win = attachedWindow {
                win.removeGestureRecognizer(panGR)
                win.removeGestureRecognizer(pinchGR)
            }
            attachedWindow = nil
        }

        // Allow pinch + 2-finger pan to be recognized together.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            isEnabled
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled, let anchorView else { return false }
            // Only activate when the touch is inside the SwiftUI region where this overlay is placed.
            let p = touch.location(in: anchorView)
            return anchorView.bounds.contains(p)
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard isEnabled else { return }

            switch gr.state {
            case .began:
                basePan = panBinding.wrappedValue
                isPanning = true
                interactionBinding.wrappedValue = isPanning || isPinching
            case .changed:
                let t = gr.translation(in: gr.view)
                panBinding.wrappedValue = CGSize(
                    width: basePan.width + t.x,
                    height: basePan.height + t.y
                )
                isPanning = true
                interactionBinding.wrappedValue = isPanning || isPinching
            case .ended, .cancelled, .failed:
                isPanning = false
                interactionBinding.wrappedValue = isPanning || isPinching
            default:
                break
            }
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard isEnabled else { return }

            switch gr.state {
            case .began:
                baseZoom = zoomBinding.wrappedValue
                isPinching = true
                interactionBinding.wrappedValue = isPanning || isPinching
            case .changed:
                let oldZ = zoomBinding.wrappedValue
                let proposed = baseZoom * gr.scale
                let newZ = clamp(proposed, zoomRange.lowerBound, zoomRange.upperBound)

                guard oldZ > 0, abs(newZ - oldZ) > 0.00001 else {
                    zoomBinding.wrappedValue = newZ
                    return
                }

                // Anchor zoom to the pinch center inside the SwiftUI region.
                let anchor: CGPoint
                if let av = anchorView, let win = av.window {
                    let pWin = gr.location(in: win)
                    if let superview = av.superview {
                        anchor = superview.convert(pWin, from: win)
                    } else {
                        anchor = av.convert(pWin, from: win)
                    }
                } else {
                    anchor = gr.location(in: gr.view)
                }

                let s = newZ / oldZ
                let p = panBinding.wrappedValue
                let anchorScreen = anchor
                let newPanW = (p.width * s) + ((1.0 - s) * anchorScreen.x)
                let newPanH = (p.height * s) + ((1.0 - s) * anchorScreen.y)

                zoomBinding.wrappedValue = newZ
                panBinding.wrappedValue = CGSize(width: newPanW, height: newPanH)
                isPinching = true
                interactionBinding.wrappedValue = isPanning || isPinching
            case .ended, .cancelled, .failed:
                isPinching = false
                interactionBinding.wrappedValue = isPanning || isPinching
            default:
                break
            }
        }
    }

    /// Empty anchor view; SwiftUI sizes/positions it. We attach recognizers to its window.
    private final class AnchorView: UIView {
        var onDidMoveToWindow: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onDidMoveToWindow?()
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            nil
        }
    }
}
#endif

#if os(macOS)
/// Observes trackpad two-finger scroll (pan) and pinch (zoom) WITHOUT intercepting mouse hit-testing.
/// This keeps normal click/drag interactions (node dragging) working.
private struct TrackpadPanZoomEventMonitor: NSViewRepresentable {
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat
    @Binding var isInteracting: Bool
    var zoomRange: ClosedRange<CGFloat>
    var isEnabled: Bool
    var blocksOverScrollableViews: Bool
    var blocksOverWebViews: Bool

    func makeNSView(context: Context) -> NSView {
        let v = PassthroughView()
        context.coordinator.attach(to: v)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.zoomRange = zoomRange
        context.coordinator.panBinding = $pan
        context.coordinator.zoomBinding = $zoom
        context.coordinator.interactionBinding = $isInteracting
        context.coordinator.blocksOverScrollableViews = blocksOverScrollableViews
        context.coordinator.blocksOverWebViews = blocksOverWebViews
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pan: $pan,
            zoom: $zoom,
            isInteracting: $isInteracting,
            zoomRange: zoomRange,
            isEnabled: isEnabled,
            blocksOverScrollableViews: blocksOverScrollableViews,
            blocksOverWebViews: blocksOverWebViews
        )
    }

    final class Coordinator {
        // Bindings updated in updateNSView
        var panBinding: Binding<CGSize>
        var zoomBinding: Binding<CGFloat>
        var interactionBinding: Binding<Bool>
        var zoomRange: ClosedRange<CGFloat>
        var isEnabled: Bool
        var blocksOverScrollableViews: Bool
        var blocksOverWebViews: Bool

        private weak var view: NSView?
        private var scrollMonitor: Any?
        private var magnifyMonitor: Any?
        private var interactionEndWorkItem: DispatchWorkItem?

        init(
            pan: Binding<CGSize>,
            zoom: Binding<CGFloat>,
            isInteracting: Binding<Bool>,
            zoomRange: ClosedRange<CGFloat>,
            isEnabled: Bool,
            blocksOverScrollableViews: Bool,
            blocksOverWebViews: Bool
        ) {
            self.panBinding = pan
            self.zoomBinding = zoom
            self.interactionBinding = isInteracting
            self.zoomRange = zoomRange
            self.isEnabled = isEnabled
            self.blocksOverScrollableViews = blocksOverScrollableViews
            self.blocksOverWebViews = blocksOverWebViews
        }

        /// Marks the viewport as actively interacting, and schedules a debounced
        /// reset back to `false` after a short pause with no further pan/zoom
        /// events. Phase-based tracking (`NSEvent.phase`/`.momentumPhase`) isn't
        /// usable here because plain mouse wheels -- which this monitor
        /// explicitly supports -- don't reliably report phases at all.
        private func markInteracting() {
            interactionEndWorkItem?.cancel()
            if !interactionBinding.wrappedValue {
                interactionBinding.wrappedValue = true
            }
            let workItem = DispatchWorkItem { [weak self] in
                self?.interactionBinding.wrappedValue = false
            }
            interactionEndWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

        func attach(to view: NSView) {
            self.view = view

            // Observe scrollWheel and magnify events locally. Consume handled viewport gestures so
            // an underlying mounted surface does not also pan/zoom in response to the same event.
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handleScroll(event) ? nil : event
            }
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self else { return event }
                return self.handleMagnify(event) ? nil : event
            }
        }

        func detach() {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
            if let m = magnifyMonitor { NSEvent.removeMonitor(m) }
            scrollMonitor = nil
            magnifyMonitor = nil
            view = nil
            interactionEndWorkItem?.cancel()
            interactionEndWorkItem = nil
        }

        private func isEventInsideView(_ event: NSEvent) -> Bool {
            guard isEnabled, let view, let viewWindow = view.window else { return false }
            // Only respond to events in our own window. Auxiliary windows owned
            // by the app (e.g. the Sparkle update / release-notes panel) deliver
            // events here too via the local monitor; without this guard we'd
            // both pan the dashboard and consume the event before the other
            // window's scroll views could react to it.
            guard let eventWindow = event.window, eventWindow === viewWindow else { return false }
            let locInWindow = event.locationInWindow

            var ancestor: NSView? = view.superview
            while let container = ancestor {
                let locInContainer = container.convert(locInWindow, from: nil)
                if container.bounds.contains(locInContainer) {
                    return true
                }
                ancestor = container.superview
            }

            let locInView = view.convert(locInWindow, from: nil)
            return view.bounds.contains(locInView)
        }
        
        private func isEventOverScrollableView(_ event: NSEvent) -> Bool {
            // Prefer the window from the event; fall back to our view's window.
            guard let view else { return false }
            let window = event.window ?? view.window
            guard let window, let contentView = window.contentView else { return false }

            // IMPORTANT: `event.locationInWindow` is already in the window/contentView coordinate space
            // for hit-testing. Converting it again can break hit-testing and cause the canvas to scroll
            // underneath overlays.
            let locInWindow = event.locationInWindow
            let hit = contentView.hitTest(locInWindow)

            // Treat the floating top toolbar pill HUD as a scroll-blocking region so scroll wheel
            // events over the toolbar do NOT pan/zoom the canvas underneath.
            func isInsideToolbarPill(_ candidate: NSView?) -> Bool {
                var cur = candidate
                while let v = cur {
                    if v.accessibilityIdentifier() == "DashboardTopToolbarPillHUD" { return true }
                    if let id = v.identifier?.rawValue, id == "DashboardTopToolbarPillHUD" { return true }
                    cur = v.superview
                }
                return false
            }

            if isInsideToolbarPill(hit) {
                return true
            }

            // Also consider first responder (often inside an NSScrollView during scrolling)
            let firstResponderView = window.firstResponder as? NSView

            func isInsideWebView(_ candidate: NSView?) -> Bool {
                var cur = candidate

                while let v = cur {
                    if v is WKWebView { return true }
                    cur = v.superview
                }
                return false
            }

            func isInsideScrollable(_ candidate: NSView?) -> Bool {
                var cur = candidate

                while let v = cur {
                    if v is WKWebView { return false }
                    if let scrollView = v as? NSScrollView {
                        return scrollViewHasScrollableOverflow(scrollView)
                    }
                    if v is NSScroller { return true }
                    cur = v.superview
                }
                return false
            }

            if isInsideWebView(hit) {
                return blocksOverWebViews
            }

            guard blocksOverScrollableViews else { return false }

            if isInsideScrollable(hit) {
                return true
            }

            // Only let the first responder block viewport panning when it is part of the same
            // subtree under the pointer. A focused scroll view elsewhere in the window should not
            // disable graph pan/zoom for the whole automation surface.
            if let hit, let firstResponderView {
                let responderSharesHitSubtree =
                    hit.isDescendant(of: firstResponderView)
                    || firstResponderView.isDescendant(of: hit)
                    || hit === firstResponderView

                if responderSharesHitSubtree {
                    if isInsideWebView(firstResponderView) {
                        return false
                    }
                    return isInsideScrollable(firstResponderView)
                }
            }

            return false
        }

        private func scrollViewHasScrollableOverflow(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return false }

            let visibleRect = scrollView.contentView.documentVisibleRect
            let documentFrame = documentView.frame.integral
            let epsilon: CGFloat = 1.0

            // Note: don't gate this on hasVerticalScroller/hasHorizontalScroller —
            // SwiftUI's ScrollView(...).scrollIndicators(.hidden) hides the scroller
            // but remains scrollable, and we still need to let it consume the event.
            let canScrollVertically = documentFrame.height - visibleRect.height > epsilon
            let canScrollHorizontally = documentFrame.width - visibleRect.width > epsilon

            return canScrollVertically || canScrollHorizontally
        }

        private func handleScroll(_ event: NSEvent) -> Bool {
            guard isEventInsideView(event) else { return false }

            // If the cursor is over a scrollable control (like a node's internal list),
            // do not treat scroll as viewport pan/zoom.
            if isEventOverScrollableView(event) { return false }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            // Mouse+keyboard friendly controls:
            // - Option/Alt + scroll => zoom
            // - Otherwise scroll => pan
            let isOptionZoom = event.modifierFlags.contains(.option)

            DispatchQueue.main.async {
                self.markInteracting()
                if isOptionZoom {
                    let oldZ = self.zoomBinding.wrappedValue
                    // Tune sensitivity: ~0.001 feels good for most wheel deltas.
                    let proposed = oldZ * (1.0 + (-dy * 0.001))
                    let newZ = clamp(proposed, self.zoomRange.lowerBound, self.zoomRange.upperBound)
                    guard oldZ > 0, abs(newZ - oldZ) > 0.00001 else { return }

                    if let view = self.view {
                        let anchor = view.convert(event.locationInWindow, from: nil)
                        let s = newZ / oldZ
                        let p = self.panBinding.wrappedValue
                        let newPanW = (p.width * s) + ((1.0 - s) * anchor.x)
                        let newPanH = (p.height * s) + ((1.0 - s) * anchor.y)
                        self.zoomBinding.wrappedValue = newZ
                        self.panBinding.wrappedValue = CGSize(width: newPanW, height: newPanH)
                    } else {
                        self.zoomBinding.wrappedValue = newZ
                    }
                } else {
                    let p = self.panBinding.wrappedValue

                    // Basic mouse wheels often only provide dy; some mice provide dx.
                    // Support Shift+wheel horizontal pan implicitly through dx if present.
                    self.panBinding.wrappedValue = CGSize(width: p.width + dx, height: p.height + dy)
                }
            }
            return true
        }

        private func handleMagnify(_ event: NSEvent) -> Bool {
            guard isEventInsideView(event) else { return false }
            if isEventOverScrollableView(event) { return false }

            let delta = event.magnification // delta (e.g. 0.02)
            DispatchQueue.main.async {
                self.markInteracting()
                let oldZ = self.zoomBinding.wrappedValue
                let proposed = oldZ * (1.0 + delta)
                let newZ = clamp(proposed, self.zoomRange.lowerBound, self.zoomRange.upperBound)
                guard oldZ > 0, abs(newZ - oldZ) > 0.00001 else { return }

                if let view = self.view {
                    let anchor = view.convert(event.locationInWindow, from: nil)
                    let s = newZ / oldZ
                    let p = self.panBinding.wrappedValue
                    let newPanW = (p.width * s) + ((1.0 - s) * anchor.x)
                    let newPanH = (p.height * s) + ((1.0 - s) * anchor.y)
                    self.zoomBinding.wrappedValue = newZ
                    self.panBinding.wrappedValue = CGSize(width: newPanW, height: newPanH)
                } else {
                    self.zoomBinding.wrappedValue = newZ
                }
            }
            return true
        }
    }

    /// A view that does not participate in hit-testing; it only exists to define a bounds region.
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
private func clamp<T: Comparable>(_ value: T, _ lo: T, _ hi: T) -> T {
    min(max(value, lo), hi)
}

extension View {
    /// Adds a generic pan/zoom controller that updates external bindings.
    ///
    /// - Parameters:
    ///   - pan: The current pan offset in view-space.
    ///   - zoom: The current zoom factor.
    ///   - isEnabled: If false, the modifier is inert and controls are hidden.
    func viewportPanZoom(
        pan: Binding<CGSize>,
        zoom: Binding<CGFloat>,
        isInteracting: Binding<Bool> = .constant(false),
        isEnabled: Bool = true,
        showsControls: Bool = true,
        blocksOverScrollableViews: Bool = true,
        blocksOverWebViews: Bool = false
    ) -> some View {
        modifier(
            ViewportPanZoomModifier(
                pan: pan,
                zoom: zoom,
                isInteracting: isInteracting,
                isEnabled: isEnabled,
                showsControls: showsControls,
                blocksOverScrollableViews: blocksOverScrollableViews,
                blocksOverWebViews: blocksOverWebViews
            )
        )
    }
}
