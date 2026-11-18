//
//  LiveModeMenuBarController.swift
//  Relay
//
//  Hides the macOS menu bar (and Dock) while the dashboard is in full-screen Live Mode,
//  so touching or pointing at the top edge reaches Relay's live menu instead of
//  revealing the system's full-screen menu bar.
//

#if os(macOS)
import AppKit
import SwiftUI

enum LiveModeMenuBarPolicy {
    static func shouldHideMenuBar(isLiveMode: Bool, isFullScreen: Bool) -> Bool {
        isLiveMode && isFullScreen
    }

    /// `base` with the menu bar and Dock fully hidden instead of auto-hidden. Everything
    /// else (notably `.fullScreen`) is preserved. `.hideMenuBar` requires `.hideDock`,
    /// and the hide/auto-hide variants are mutually exclusive.
    static func hiddenOptions(from base: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        var options = base
        options.remove([.autoHideMenuBar, .autoHideDock])
        options.insert([.hideMenuBar, .hideDock])
        return options
    }
}

/// What the controller reads and writes; injectable so the window/full-screen logic is testable.
struct LiveModeMenuBarEnvironment {
    var presentationOptions: () -> NSApplication.PresentationOptions
    var setPresentationOptions: (NSApplication.PresentationOptions) -> Void
    var isFullScreen: (NSWindow) -> Bool

    @MainActor static var live: LiveModeMenuBarEnvironment {
        LiveModeMenuBarEnvironment(
            presentationOptions: { NSApp.presentationOptions },
            setPresentationOptions: { NSApp.presentationOptions = $0 },
            isFullScreen: { $0.styleMask.contains(.fullScreen) }
        )
    }
}

@MainActor
final class LiveModeMenuBarController {
    /// The presentation options in effect before we hid the menu bar; `nil` when not hiding.
    private(set) var savedBaseOptions: NSApplication.PresentationOptions?
    /// The dashboard's own window (never just whichever window is key).
    private(set) weak var window: NSWindow?

    private let environment: LiveModeMenuBarEnvironment
    private var isLiveMode = false
    private var observers: [NSObjectProtocol] = []

    /// `nil` uses the real `NSApp`/window state.
    init(environment: LiveModeMenuBarEnvironment? = nil) {
        self.environment = environment ?? .live
    }

    /// Pure option bookkeeping. Hiding saves the current options the first time;
    /// un-hiding returns the saved options and forgets them.
    func apply(hide: Bool, current: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        if hide {
            if savedBaseOptions == nil { savedBaseOptions = current }
            return LiveModeMenuBarPolicy.hiddenOptions(from: current)
        }
        guard let base = savedBaseOptions else { return current }
        savedBaseOptions = nil
        return base
    }

    /// Tracks the dashboard window whose full screen state matters. Switching windows while
    /// the menu bar is hidden restores it against the old window first.
    func setWindow(_ newWindow: NSWindow?) {
        guard newWindow !== window else { return }
        if savedBaseOptions != nil {
            let wasLive = isLiveMode
            isLiveMode = false
            applyCurrentState()
            isLiveMode = wasLive
        }
        stopObserving()
        window = newWindow
        if let newWindow { observe(newWindow) }
        applyCurrentState()
    }

    /// Call whenever Live Mode changes. Full-screen enter/exit of the tracked window is
    /// observed, so this also takes effect once an animated full-screen transition ends.
    func update(isLiveMode: Bool) {
        self.isLiveMode = isLiveMode
        applyCurrentState()
    }

    /// Called by the full-screen enter/exit observers.
    func windowFullScreenStateDidChange() {
        applyCurrentState()
    }

    /// Restores the menu bar (if hidden) and stops observing.
    func reset() {
        isLiveMode = false
        applyCurrentState()
        stopObserving()
        window = nil
    }

    private func applyCurrentState() {
        let current = environment.presentationOptions()
        // Full screen counts only once AppKit has switched to full-screen presentation
        // options; mid-transition, assigning a hidden set without `.fullScreen` (or
        // restoring one with it) would be invalid.
        let isFullScreen = (window.map(environment.isFullScreen) ?? false) && current.contains(.fullScreen)
        let hide = LiveModeMenuBarPolicy.shouldHideMenuBar(isLiveMode: isLiveMode, isFullScreen: isFullScreen)

        if hide {
            let hidden = apply(hide: true, current: current)
            if hidden != current { environment.setPresentationOptions(hidden) }
        } else if savedBaseOptions != nil {
            let base = apply(hide: false, current: current)
            // Once the window has left full screen, AppKit drops the full-screen
            // presentation options on its own; assigning the saved set (which contains
            // `.fullScreen`) outside full screen would be invalid.
            if isFullScreen {
                environment.setPresentationOptions(base)
            }
        }
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowFullScreenStateDidChange() }
            })
        }
    }

    private func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}

/// Reports the `NSWindow` hosting this view (and later changes), so Live Mode can act on
/// the dashboard's own window rather than `NSApp.keyWindow`.
struct HostingWindowReader: NSViewRepresentable {
    let onWindowChanged: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindowChanged = onWindowChanged
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onWindowChanged = onWindowChanged
    }

    final class ReaderView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChanged?(window)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
