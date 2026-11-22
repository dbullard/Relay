//
//  ViewportZoomMath.swift
//  Relay
//
//  Pure, platform-neutral helpers shared by the viewport pan/zoom event handling.
//

import Foundation
import CoreGraphics

/// What a scroll-wheel/trackpad scroll event should do to the viewport.
enum ViewportScrollIntent: Equatable {
    case pan
    case zoom
}

enum ViewportZoomMath {
    /// Zooms toward `proposedZoom` (clamped to `range`) while keeping the view-space
    /// point `anchorInView` stationary on screen.
    ///
    /// Returns `nil` when nothing should change: a non-positive current zoom, or a
    /// clamped zoom equal to the current one (e.g. pinching past a limit). Returning
    /// `nil` there keeps the pan from drifting at the limits.
    static func anchoredZoom(
        currentZoom: CGFloat,
        currentPan: CGSize,
        proposedZoom: CGFloat,
        anchorInView: CGPoint,
        range: ClosedRange<CGFloat>
    ) -> (zoom: CGFloat, pan: CGSize)? {
        let clamped = min(max(proposedZoom, range.lowerBound), range.upperBound)
        guard currentZoom > 0, abs(clamped - currentZoom) > 0.00001 else { return nil }

        let s = clamped / currentZoom
        let pan = CGSize(
            width: (currentPan.width * s) + ((1.0 - s) * anchorInView.x),
            height: (currentPan.height * s) + ((1.0 - s) * anchorInView.y)
        )
        return (clamped, pan)
    }

    /// Zoom and pan that show the whole `contentSize` centered in `viewportSize`,
    /// scaling up or down as needed (clamped to `range`). Backs both the "Fit to Window"
    /// toolbar button and Live Mode's "Fit to Screen".
    ///
    /// Returns `nil` when either size is empty (e.g. before the first layout pass).
    static func fitToViewport(
        contentSize: CGSize,
        viewportSize: CGSize,
        range: ClosedRange<CGFloat>
    ) -> (zoom: CGFloat, pan: CGSize)? {
        guard contentSize.width > 0, contentSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return nil }

        let raw = min(viewportSize.width / contentSize.width, viewportSize.height / contentSize.height)
        let zoom = min(max(raw, range.lowerBound), range.upperBound)
        let pan = CGSize(
            width: (viewportSize.width - contentSize.width * zoom) * 0.5,
            height: (viewportSize.height - contentSize.height * zoom) * 0.5
        )
        return (zoom, pan)
    }

    /// Multiplicative zoom factor for a modifier+scroll zoom.
    static func scrollZoomFactor(deltaY: CGFloat) -> CGFloat {
        1.0 + (-deltaY * 0.001)
    }

    /// Option, Command, or Control + scroll zooms (touch drivers such as UPDD may send
    /// pinch as Cmd/Ctrl+scroll); anything else pans.
    static func scrollIntent(option: Bool, command: Bool, control: Bool) -> ViewportScrollIntent {
        (option || command || control) ? .zoom : .pan
    }

    /// Whether an event that arrived with no window (as synthetic gesture events from
    /// touch drivers can) should be handled by a viewport whose on-screen frame is
    /// `viewFrameOnScreen`, given the cursor's `screenPoint`.
    ///
    /// Relay must be the active app and the viewport's window must be the topmost window
    /// under the cursor, so a pinch over a floating Relay window (Variables), a sheet, or
    /// another app's window never zooms the canvas beneath it. The viewport's window does
    /// not need to be key: clicking the Variables window last shouldn't disable pinch on
    /// the dashboard.
    static func acceptsWindowlessEvent(
        screenPoint: CGPoint,
        viewFrameOnScreen: CGRect,
        isAppActive: Bool,
        isViewWindowTopmostUnderCursor: Bool
    ) -> Bool {
        isAppActive && isViewWindowTopmostUnderCursor && viewFrameOnScreen.contains(screenPoint)
    }
}
