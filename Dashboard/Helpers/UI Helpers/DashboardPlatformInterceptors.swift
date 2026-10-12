import Combine
import SwiftUI

#if os(macOS)
import AppKit
import WebKit

@MainActor
final class DashboardWindowCloseCoordinator: ObservableObject {
    weak var pendingWindowToClose: NSWindow?
    fileprivate weak var trackedWindow: NSWindow?

    func markPendingClose(window: NSWindow) {
        pendingWindowToClose = window
    }

    func clearPendingClose() {
        pendingWindowToClose = nil
    }

    func continuePendingClose() {
        guard let window = pendingWindowToClose else { return }
        pendingWindowToClose = nil
        // NSWindow.performClose(_:) silently refuses to close a window that still has an
        // attached sheet. This is normally called from inside a save-prompt alert's own
        // button action, and that alert is itself sheet-presented — its dismiss animation
        // hasn't necessarily finished by the time this line runs. A short delay lets it
        // fully detach first; confirmed necessary by direct testing (performClose returned
        // immediately with the window still visible and windowShouldClose never invoked
        // when called synchronously).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            window.performClose(nil)
        }
    }
}

struct WindowCloseInterceptor: NSViewRepresentable {
    @ObservedObject var coordinator: DashboardWindowCloseCoordinator
    let shouldInterceptClose: () -> Bool
    let onAttemptClose: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            coordinator: coordinator,
            shouldInterceptClose: shouldInterceptClose,
            onAttemptClose: onAttemptClose
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onWindowChanged = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldInterceptClose = shouldInterceptClose
        context.coordinator.onAttemptClose = onAttemptClose
        if let window = nsView.window {
            context.coordinator.attach(to: window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var coordinator: DashboardWindowCloseCoordinator
        var shouldInterceptClose: () -> Bool
        var onAttemptClose: (NSWindow) -> Void

        init(
            coordinator: DashboardWindowCloseCoordinator,
            shouldInterceptClose: @escaping () -> Bool,
            onAttemptClose: @escaping (NSWindow) -> Void
        ) {
            self.coordinator = coordinator
            self.shouldInterceptClose = shouldInterceptClose
            self.onAttemptClose = onAttemptClose
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            guard coordinator.trackedWindow !== window else { return }
            coordinator.trackedWindow = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldInterceptClose() else { return true }
            onAttemptClose(sender)
            return false
        }
    }

    private final class TrackingView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }
}

/// AppKit does not deliver clicks on the window's standard close button through the
/// normal `performClose:` → `windowShouldClose:` chain while a SwiftUI `.sheet()` is
/// presented, so `WindowCloseInterceptor` alone can silently do nothing. Retargeting the
/// button's `target`/`action` does NOT work either — the close button (`_NSThemeCloseWidget`)
/// doesn't route its click through standard target-action dispatch, confirmed by direct
/// testing (target/action were set correctly, but clicks never invoked the action).
/// Instead, this installs a local `NSEvent` mouseDown monitor that fires before AppKit's
/// own button click handling, checks whether the click landed on the close button's frame,
/// and if so calls `onCloseButtonClicked` directly and consumes the event — the same
/// approach already used for Cmd+Q/Cmd+W. `WindowCloseInterceptor` stays in place for the
/// final close step once no sheet remains (see `DashboardWindowCloseCoordinator.continuePendingClose()`).
struct WindowCloseButtonRetargeter: NSViewRepresentable {
    let onCloseButtonClicked: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCloseButtonClicked: onCloseButtonClicked)
    }

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onWindowChanged = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCloseButtonClicked = onCloseButtonClicked
        if let window = nsView.window {
            context.coordinator.attach(to: window)
        }
    }

    final class Coordinator: NSObject {
        var onCloseButtonClicked: (NSWindow) -> Void
        private weak var trackedWindow: NSWindow?
        private var mouseDownMonitor: Any?

        init(onCloseButtonClicked: @escaping (NSWindow) -> Void) {
            self.onCloseButtonClicked = onCloseButtonClicked
        }

        func attach(to window: NSWindow?) {
            guard let window, trackedWindow !== window else { return }
            trackedWindow = window
            if let mouseDownMonitor {
                NSEvent.removeMonitor(mouseDownMonitor)
            }
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self,
                      let trackedWindow = self.trackedWindow,
                      event.window === trackedWindow,
                      let button = trackedWindow.standardWindowButton(.closeButton),
                      !button.isHidden
                else {
                    return event
                }
                let locationInButton = button.convert(event.locationInWindow, from: nil)
                guard button.bounds.contains(locationInButton) else { return event }
                self.onCloseButtonClicked(trackedWindow)
                return nil
            }
        }

        deinit {
            if let mouseDownMonitor {
                NSEvent.removeMonitor(mouseDownMonitor)
            }
        }
    }

    private final class TrackingView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }
}

/// Invisible first-responder view that captures Delete / Forward Delete and arrow keys.
struct DeleteKeyCatcher: NSViewRepresentable {
    enum ArrowKey {
        case left
        case right
        case up
        case down
    }

    let isTutorialPresented: Bool
    let onTutorialArrow: (ArrowKey) -> Void
    let onTutorialEscape: () -> Void
    let onDelete: () -> Void
    let onSelectAll: () -> Void
    let onArrowKey: (ArrowKey, NSEvent.ModifierFlags) -> Void
    /// When true, we should NOT steal first responder (text fields are editing).
    let isTextInputActive: Bool

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        updateKeyCatcherView(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCatcherView else { return }
        updateKeyCatcherView(view)

        // Ensure we become first responder when possible, but NEVER while a text field is editing.
        guard !isTextInputActive else { return }
        DispatchQueue.main.async {
            view.requestFirstResponderIfAppropriate()
        }
    }

    private func updateKeyCatcherView(_ view: KeyCatcherView) {
        view.isTutorialPresented = isTutorialPresented
        view.onTutorialArrow = onTutorialArrow
        view.onTutorialEscape = onTutorialEscape
        view.onDelete = onDelete
        view.onSelectAll = onSelectAll
        view.onArrowKey = onArrowKey
        view.isTextInputActive = isTextInputActive
    }

    private final class KeyCatcherView: NSView {
        var isTutorialPresented: Bool = false
        var onTutorialArrow: ((ArrowKey) -> Void)?
        var onTutorialEscape: (() -> Void)?
        var onDelete: (() -> Void)?
        var onSelectAll: (() -> Void)?
        var onArrowKey: ((ArrowKey, NSEvent.ModifierFlags) -> Void)?
        var isTextInputActive: Bool = false

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.requestFirstResponderIfAppropriate()
            }
        }

        func requestFirstResponderIfAppropriate() {
            guard let window = self.window else { return }

            // Never steal focus while the app thinks text input is active.
            if isTextInputActive { return }

            // Also avoid stealing focus from AppKit text responders, and from a
            // WKWebView (or any view nested inside one) — e.g. a login form embedded
            // in a WebpageModule tile. WebKit's internal editing view isn't an
            // NSTextView/NSTextField, so it needs its own ancestor-chain check;
            // without this, every re-render of the root view stole focus back to this
            // key catcher mid-keystroke, making it impossible to type into the webview.
            if let firstResponder = window.firstResponder {
                if firstResponder is NSTextView { return }
                if firstResponder is NSTextField { return }
                if var view = firstResponder as? NSView {
                    while true {
                        if view is WKWebView { return }
                        guard let superview = view.superview else { break }
                        view = superview
                    }
                }
            }

            if window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
        }

        override func cancelOperation(_ sender: Any?) {
            if isTutorialPresented {
                onTutorialEscape?()
                return
            }
            super.cancelOperation(sender)
        }

        override func keyDown(with event: NSEvent) {
            if isTutorialPresented {
                if event.keyCode == 53 {
                    onTutorialEscape?()
                    return
                }
                switch event.keyCode {
                case 123:
                    onTutorialArrow?(.left)
                    return
                case 124:
                    onTutorialArrow?(.right)
                    return
                default:
                    break
                }
            }

            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "a" {
                onSelectAll?()
                return
            }
            // 51 = Delete (backspace), 117 = Forward Delete
            if event.keyCode == 51 || event.keyCode == 117 {
                onDelete?()
                return
            }
            // Arrow keys: 123 = Left, 124 = Right, 125 = Down, 126 = Up
            switch event.keyCode {
            case 123:
                onArrowKey?(.left, event.modifierFlags)
                return
            case 124:
                onArrowKey?(.right, event.modifierFlags)
                return
            case 125:
                onArrowKey?(.down, event.modifierFlags)
                return
            case 126:
                onArrowKey?(.up, event.modifierFlags)
                return
            default:
                break
            }
            super.keyDown(with: event)
        }
    }
}
#endif

#if os(iOS)
@MainActor
final class DashboardWindowCloseCoordinator: ObservableObject {
    func clearPendingClose() {}
    func continuePendingClose() {}
}

@MainActor
final class AppTerminationCoordinator {
    static let shared = AppTerminationCoordinator()

    func continueTermination() {}
    func cancelTermination() {}
}

extension Notification.Name {
    static let dashboardAppTerminateRequested = Notification.Name("Relay.AppTerminateRequested")
}
#endif
