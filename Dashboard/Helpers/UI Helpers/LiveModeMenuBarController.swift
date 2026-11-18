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

@MainActor
final class LiveModeMenuBarController {
    /// The presentation options in effect before we hid the menu bar; `nil` when not hiding.
    private(set) var savedBaseOptions: NSApplication.PresentationOptions?

    private weak var window: NSWindow?
    private var isLiveMode = false
    private var observers: [NSObjectProtocol] = []

    /// Pure option bookkeeping (no `NSApp` access). Hiding saves the current options the
    /// first time; un-hiding returns the saved options and forgets them.
    func apply(hide: Bool, current: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        if hide {
            if savedBaseOptions == nil { savedBaseOptions = current }
            return LiveModeMenuBarPolicy.hiddenOptions(from: current)
        }
        guard let base = savedBaseOptions else { return current }
        savedBaseOptions = nil
        return base
    }

    /// Call whenever Live Mode changes. Full-screen enter/exit of `window` is observed
    /// automatically, so this also takes effect once an animated full-screen transition ends.
    func update(isLiveMode: Bool, window: NSWindow?) {
        self.isLiveMode = isLiveMode
        if let window, window !== self.window {
            observe(window)
        }
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
        let isFullScreen = window?.styleMask.contains(.fullScreen) ?? false
        let hide = LiveModeMenuBarPolicy.shouldHideMenuBar(isLiveMode: isLiveMode, isFullScreen: isFullScreen)

        if hide {
            NSApp.presentationOptions = apply(hide: true, current: NSApp.presentationOptions)
        } else if savedBaseOptions != nil {
            let base = apply(hide: false, current: NSApp.presentationOptions)
            // Once the window has left full screen, AppKit drops the full-screen
            // presentation options on its own; assigning the saved set (which contains
            // `.fullScreen`) outside full screen would be invalid.
            if isFullScreen {
                NSApp.presentationOptions = base
            }
        }
    }

    private func observe(_ window: NSWindow) {
        stopObserving()
        self.window = window
        let center = NotificationCenter.default
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyCurrentState() }
            })
        }
    }

    private func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}
#endif
