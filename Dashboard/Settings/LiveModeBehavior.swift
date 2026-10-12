//
//  LiveModeBehavior.swift
//  Relay
//

import Foundation

/// Backs the "Canvas" setting in General settings' "Live Mode" group.
/// Stored as a raw `String` under `@AppStorage("dashboard_live_mode_canvas_behavior")`
/// and read by `DashboardRootView` when `isLiveMode` changes.
enum LiveModeCanvasBehavior: String, CaseIterable {
    case fitToScreen
    case keepCurrentView

    var label: String {
        switch self {
        case .fitToScreen: return "Fit to Screen"
        case .keepCurrentView: return "Keep Current View"
        }
    }
}

/// Backs the "Window" setting in General settings' "Live Mode" group.
/// Stored as a raw `String` under `@AppStorage("dashboard_live_mode_window_behavior")`
/// and read by `DashboardRootView` when `isLiveMode` changes. macOS only.
enum LiveModeWindowBehavior: String, CaseIterable {
    case fullScreen
    case keepCurrentSize

    var label: String {
        switch self {
        case .fullScreen: return "Full Screen"
        case .keepCurrentSize: return "Keep Current Size"
        }
    }
}
