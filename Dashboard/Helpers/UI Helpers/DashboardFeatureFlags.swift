import Foundation

/// Flags for dashboard behavior that is implemented and tested but not yet
/// trusted enough to run for every user by default. Unlike
/// `SmartLightFeatureFlags` (gated on build type -- beta/debug), these are
/// gated on an explicit `UserDefaults` toggle so a flag can ship disabled in
/// a full release build and be turned on selectively (e.g. for a specific
/// show or a support investigation) without a new build.
enum DashboardFeatureFlags {
    /// Cull off-screen, resource-free tiles from the canvas (Task 4 of the
    /// SwiftUI scale-hardening plan). Computed inside
    /// `DashboardCanvasViewportHost` from the live pan/zoom, published with
    /// hysteresis, and applied in `DashboardTileCanvas` -- modules that hold
    /// a live resource (`DashboardCanvasCullingPolicy.holdsLiveResource`)
    /// are always exempt.
    ///
    /// Defaults to **off**. Relay runs live events; a tile silently vanishing
    /// mid-service because it drifted out of a stale visible rect is a worse
    /// failure than a slow pan on a tile-heavy dashboard. This mainly helps
    /// dashboards with many static/PCO tiles -- a dashboard full of live
    /// modules (NDI, WebView, audio meters, ...) is exempt from culling
    /// almost entirely, so this flag does little for that case.
    static var canvasViewportCulling: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    private static let userDefaultsKey = "dashboard_feature_canvasViewportCulling"
}
