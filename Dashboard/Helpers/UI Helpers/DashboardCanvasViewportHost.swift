import SwiftUI

/// Decides when a live (high-frequency) pan/zoom value should be committed
/// back to the external, `DashboardRootView`-owned source of truth.
///
/// Kept as a plain, clock-injectable value type (not tied to `DispatchQueue`
/// or `Date()` internally) so its throttling behavior can be unit tested
/// with synthetic timestamps instead of real wall-clock delays.
struct DashboardCanvasCommitScheduler {
    /// Minimum time between two throttled commits while a gesture is active.
    /// Chosen so dependent UI (the artboard outline, the selection action
    /// toolbar) stays visibly in sync during a drag without reintroducing
    /// the original per-pixel re-render cost -- ~8 commits/second instead of
    /// the 60-120 raw scroll events/second a trackpad can produce.
    let minimumInterval: TimeInterval

    private var lastCommitDate: Date?

    init(minimumInterval: TimeInterval = 0.12) {
        self.minimumInterval = minimumInterval
    }

    /// Call on every live pan/zoom update. Returns `true` if the caller
    /// should push the live value back to the external binding now.
    mutating func shouldCommit(now: Date, isInteracting: Bool, wasInteracting: Bool) -> Bool {
        // Always commit the instant a gesture ends, so nothing is left stale.
        if wasInteracting && !isInteracting {
            lastCommitDate = now
            return true
        }
        guard isInteracting else {
            // Not part of a gesture (e.g. a "Fit to Window" button tap or a
            // live-mode viewport change) -- nothing to throttle.
            lastCommitDate = now
            return true
        }
        if let last = lastCommitDate, now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        lastCommitDate = now
        return true
    }
}

/// Hosts pan/zoom-transformed canvas content without forcing that content to
/// be reconstructed on every pan/zoom tick.
///
/// `ViewportPanZoomModifier` (via `TrackpadPanZoomEventMonitor`) writes a new
/// pan/zoom value on every trackpad scroll/pinch delta -- potentially 60-120
/// times per second during a continuous drag. If that write lands directly
/// on a `@State` owned by a large parent view (as `canvasViewportPan`/`Zoom`
/// did on `DashboardRootView`), every one of those writes forces the
/// parent's entire `body` to re-execute, which reconstructs every tile on
/// the canvas from scratch. Confirmed via Time Profiler: hangs during a
/// canvas drag on a PCO-tile-heavy dashboard were 90%+ main-thread CPU
/// inside SwiftUI's own diffing/layout internals, with zero frames of
/// Relay's own code on the sampled stacks.
///
/// This view breaks that link: it owns its own local, high-frequency
/// `livePan`/`liveZoom` state, applies the `.scaleEffect`/`.offset`
/// transform to `content` itself (so only *this* small view's body re-runs
/// on every pan tick, not the whole canvas), and pushes the value back up to
/// the caller's `pan`/`zoom` bindings via `DashboardCanvasCommitScheduler` --
/// always the instant the gesture ends, and throttled while it's active.
struct DashboardCanvasViewportHost<Content: View>: View {
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat
    @Binding var isInteracting: Bool
    let contentSize: CGSize
    var isEnabled: Bool = true
    var blocksOverScrollableViews: Bool = true
    var blocksOverWebViews: Bool = false

    /// Padding applied to the published visible rect beyond the raw
    /// viewport, so a tile just outside the viewport is already mounted
    /// before it scrolls into view. Must stay comfortably larger than
    /// `visibleRectHysteresis` (chosen as 3x here) -- otherwise a tile could
    /// sit in the gap between "far enough to republish" and "close enough to
    /// need to already be mounted."
    ///
    /// Expressed in **screen-space-equivalent points at zoom 1.0**, not raw
    /// canvas points -- `maybeUpdateVisibleRect()` converts this via
    /// `DashboardCanvasVisibility.canvasMargin(nominalScreenPoints:zoom:)`
    /// before using it. A flat canvas-space constant would only represent
    /// the intended margin at zoom 1.0: `visibleCanvasRect` divides `pan` by
    /// `zoom`, so the same real (screen-space) pan produces `1/zoom` times
    /// more canvas-space drift as the user zooms out. At Relay's documented
    /// zoom floor of 0.25 (`ViewportPanZoomModifier.zoomRange`), a flat
    /// 600/200 pair tuned at zoom 1.0 would be exhausted by 4x less real
    /// panning than intended -- reachable from a single unclamped scroll or
    /// trackpad event (`ViewportPanZoomModifier.handleScroll` applies raw
    /// `NSEvent.scrollingDeltaX/Y` to `pan` with no per-event clamp), and
    /// exactly where culling matters most: a zoomed-out view of a large,
    /// tile-heavy dashboard.
    var visibleRectOverscan: CGFloat = 600

    /// How far the live viewport must drift before a new visible rect is
    /// published. Set well below `visibleRectOverscan` so a tile is always
    /// mounted before it can scroll into view. Republishing on every
    /// throttled commit (let alone every live pan/zoom tick) would rebuild
    /// the canvas -- exactly the cost `DashboardCanvasCommitScheduler` and
    /// this host exist to avoid. 200pt was chosen so a full-speed trackpad
    /// pan needs several ticks between republishes, while still being small
    /// enough (a third of the default overscan) that a tile can't drift from
    /// "just outside, about to be culled" to "on-screen" within a single
    /// un-republished gap.
    ///
    /// Also expressed in screen-space-equivalent points at zoom 1.0 -- see
    /// `visibleRectOverscan`'s doc comment for why a flat canvas-space value
    /// doesn't hold across Relay's 0.25...3.00 zoom range.
    var visibleRectHysteresis: CGFloat = 200

    @ViewBuilder let content: (CGRect) -> Content

    @State private var livePan: CGSize
    @State private var liveZoom: CGFloat
    @State private var liveIsInteracting = false
    @State private var wasLiveInteracting = false
    @State private var commitScheduler = DashboardCanvasCommitScheduler()

    /// The visible canvas rect last published to `content`. Starts as
    /// `.infinite` ("cull nothing") so a tile is never hidden before the
    /// first real geometry is known. Only reassigned when the live viewport
    /// has drifted past `visibleRectHysteresis`, or when culling is
    /// disabled -- see `maybeUpdateVisibleRect()`.
    @State private var publishedVisibleRect: CGRect = .infinite

    init(
        pan: Binding<CGSize>,
        zoom: Binding<CGFloat>,
        isInteracting: Binding<Bool>,
        contentSize: CGSize,
        isEnabled: Bool = true,
        blocksOverScrollableViews: Bool = true,
        blocksOverWebViews: Bool = false,
        visibleRectOverscan: CGFloat = 600,
        visibleRectHysteresis: CGFloat = 200,
        @ViewBuilder content: @escaping (CGRect) -> Content
    ) {
        self._pan = pan
        self._zoom = zoom
        self._isInteracting = isInteracting
        self.contentSize = contentSize
        self.isEnabled = isEnabled
        self.blocksOverScrollableViews = blocksOverScrollableViews
        self.blocksOverWebViews = blocksOverWebViews
        self.visibleRectOverscan = visibleRectOverscan
        self.visibleRectHysteresis = visibleRectHysteresis
        self.content = content
        self._livePan = State(initialValue: pan.wrappedValue)
        self._liveZoom = State(initialValue: zoom.wrappedValue)
    }

    var body: some View {
        content(publishedVisibleRect)
            .scaleEffect(liveZoom, anchor: .topLeading)
            .offset(livePan)
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            .clipped()
            .viewportPanZoom(
                pan: $livePan,
                zoom: $liveZoom,
                isInteracting: $liveIsInteracting,
                isEnabled: isEnabled,
                showsControls: false,
                blocksOverScrollableViews: blocksOverScrollableViews,
                blocksOverWebViews: blocksOverWebViews
            )
            .onChange(of: livePan, initial: false) { _, _ in
                maybeCommit()
                maybeUpdateVisibleRect()
            }
            .onChange(of: liveZoom, initial: false) { _, _ in
                maybeCommit()
                maybeUpdateVisibleRect()
            }
            .onChange(of: liveIsInteracting, initial: false) { _, active in
                isInteracting = active
                maybeCommit()
            }
            // Adopt external programmatic changes (toolbar buttons, live-mode
            // fit-to-viewport) -- but never while a live gesture is driving
            // the value, or the external (stale) value would fight it.
            .onChange(of: pan, initial: false) { _, newValue in
                guard !liveIsInteracting else { return }
                livePan = newValue
                maybeUpdateVisibleRect()
            }
            .onChange(of: zoom, initial: false) { _, newValue in
                guard !liveIsInteracting else { return }
                liveZoom = newValue
                maybeUpdateVisibleRect()
            }
            .onChange(of: contentSize, initial: false) { _, _ in maybeUpdateVisibleRect() }
            .onAppear { maybeUpdateVisibleRect() }
    }

    private func maybeCommit() {
        let now = Date()
        guard commitScheduler.shouldCommit(now: now, isInteracting: liveIsInteracting, wasInteracting: wasLiveInteracting) else {
            wasLiveInteracting = liveIsInteracting
            return
        }
        wasLiveInteracting = liveIsInteracting
        if pan != livePan { pan = livePan }
        if zoom != liveZoom { zoom = liveZoom }
    }

    /// Recomputes the candidate visible rect on every call (cheap arithmetic,
    /// no view invalidation) but only assigns to `publishedVisibleRect` --
    /// which *does* invalidate `content`'s body -- when
    /// `DashboardCanvasVisibility.shouldRepublishVisibleRect` says the drift
    /// exceeds the (zoom-scaled) hysteresis. This is what keeps culling from
    /// undoing the point of this host: republishing on every one of the
    /// 60-120 raw pan/zoom ticks per second would rebuild the canvas at that
    /// same frequency.
    ///
    /// `visibleRectOverscan`/`visibleRectHysteresis` are nominal
    /// screen-space-equivalent values (see their doc comments); both are
    /// converted to actual canvas points at the live zoom via
    /// `DashboardCanvasVisibility.canvasMargin` before use, so this behaves
    /// consistently across Relay's whole 0.25...3.00 zoom range rather than
    /// only near zoom 1.0.
    ///
    /// When the feature flag is off, this leaves `publishedVisibleRect`
    /// permanently `.infinite` (set once, if needed, and never touched
    /// again) instead of tracking the viewport for no reason -- disabled
    /// must mean zero added cost, not just "culling doesn't filter anything."
    private func maybeUpdateVisibleRect() {
        guard DashboardFeatureFlags.canvasViewportCulling else {
            if !publishedVisibleRect.isInfinite { publishedVisibleRect = .infinite }
            return
        }

        let overscan = DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: visibleRectOverscan, zoom: liveZoom)
        let candidate = DashboardCanvasVisibility.visibleCanvasRect(
            viewportSize: contentSize, pan: livePan, zoom: liveZoom, overscan: overscan
        )

        let hysteresis = DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: visibleRectHysteresis, zoom: liveZoom)
        if DashboardCanvasVisibility.shouldRepublishVisibleRect(
            candidate: candidate, published: publishedVisibleRect, hysteresis: hysteresis
        ) {
            publishedVisibleRect = candidate
        }
    }
}

/// Adapts `DashboardCanvasViewportHost` to `.modifier(...)` so it can wrap an
/// already-built view chain (needed because `DashboardCanvasViewportHost` is
/// generic over its content and SwiftUI can't infer that generic parameter
/// through a bare `.modifier(DashboardCanvasViewportHost(...))` call).
struct DashboardCanvasViewportHostModifier: ViewModifier {
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat
    @Binding var isInteracting: Bool
    let contentSize: CGSize
    var isEnabled: Bool = true
    var blocksOverScrollableViews: Bool = true
    var blocksOverWebViews: Bool = false

    func body(content: Content) -> some View {
        // `content` here is the already-built view being modified -- it can't
        // be re-parameterized by the visible rect after the fact, so this
        // adapter path always ignores it. Callers that need to thread the
        // visible rect into their content (viewport culling) must call
        // `DashboardCanvasViewportHost` directly with its `(CGRect) -> some View`
        // trailing closure instead of going through `.modifier(...)`.
        DashboardCanvasViewportHost(
            pan: $pan,
            zoom: $zoom,
            isInteracting: $isInteracting,
            contentSize: contentSize,
            isEnabled: isEnabled,
            blocksOverScrollableViews: blocksOverScrollableViews,
            blocksOverWebViews: blocksOverWebViews
        ) { _ in
            content
        }
    }
}
