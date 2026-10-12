import SwiftUI

#if os(macOS)
import AppKit

private struct CursorAutoHideTrackingView: NSViewRepresentable {
    let onMouseEvent: () -> Void
    let onWindowChanged: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        TrackingView(onMouseEvent: onMouseEvent, onWindowChanged: onWindowChanged)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let trackingView = nsView as? TrackingView else { return }
        trackingView.onMouseEvent = onMouseEvent
        trackingView.onWindowChanged = onWindowChanged
    }

    private final class TrackingView: NSView {
        var onMouseEvent: () -> Void
        var onWindowChanged: (NSWindow?) -> Void
        private var trackingAreaRef: NSTrackingArea?

        init(
            onMouseEvent: @escaping () -> Void,
            onWindowChanged: @escaping (NSWindow?) -> Void
        ) {
            self.onMouseEvent = onMouseEvent
            self.onWindowChanged = onWindowChanged
            super.init(frame: .zero)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            onWindowChanged(window)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }

            let options: NSTrackingArea.Options = [
                .mouseMoved,
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect
            ]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingAreaRef = area
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            onMouseEvent()
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onMouseEvent()
        }
    }
}

private struct CursorAutoHideModifier: ViewModifier {
    let isEnabled: Bool
    let delay: TimeInterval

    @State private var isHidden: Bool = false
    @State private var hideTask: Task<Void, Never>?
    @State private var trackedWindowNumber: Int?

    func body(content: Content) -> some View {
        content
            .background(
                CursorAutoHideTrackingView {
                    handleMouseEvent()
                } onWindowChanged: { window in
                    handleWindowChanged(window)
                }
            )
            .onAppear {
                if isEnabled {
                    scheduleHide()
                } else {
                    showCursorIfNeeded()
                }
            }
            .onChange(of: isEnabled) { _, newValue in
                if newValue {
                    scheduleHide()
                } else {
                    cancelHide()
                    showCursorIfNeeded()
                }
            }
            .onDisappear {
                cancelHide()
                showCursorIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                handleKeyWindowNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
                handleKeyWindowNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                cancelHide()
                showCursorIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard isEnabled else { return }
                if NSApp.keyWindow?.windowNumber == trackedWindowNumber {
                    scheduleHide()
                } else {
                    showCursorIfNeeded()
                }
            }
    }

    private func handleMouseEvent() {
        guard isEnabled else { return }
        guard NSApp.keyWindow?.windowNumber == trackedWindowNumber else {
            cancelHide()
            showCursorIfNeeded()
            return
        }
        showCursorIfNeeded()
        scheduleHide()
    }

    private func handleWindowChanged(_ window: NSWindow?) {
        trackedWindowNumber = window?.windowNumber
        guard isEnabled else {
            cancelHide()
            showCursorIfNeeded()
            return
        }

        if NSApp.keyWindow?.windowNumber == trackedWindowNumber {
            scheduleHide()
        } else {
            cancelHide()
            showCursorIfNeeded()
        }
    }

    private func handleKeyWindowNotification(_ notification: Notification) {
        guard isEnabled else {
            cancelHide()
            showCursorIfNeeded()
            return
        }

        guard let window = notification.object as? NSWindow else { return }
        if window.windowNumber == trackedWindowNumber {
            if window.isKeyWindow {
                scheduleHide()
            } else {
                cancelHide()
                showCursorIfNeeded()
            }
            return
        }

        cancelHide()
        showCursorIfNeeded()
    }

    private func scheduleHide() {
        guard isEnabled else { return }
        guard NSApp.keyWindow?.windowNumber == trackedWindowNumber else {
            cancelHide()
            showCursorIfNeeded()
            return
        }
        cancelHide()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if isEnabled, NSApp.keyWindow?.windowNumber == trackedWindowNumber {
                hideCursorIfNeeded()
            }
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func hideCursorIfNeeded() {
        guard !isHidden else { return }
        NSCursor.hide()
        isHidden = true
    }

    private func showCursorIfNeeded() {
        guard isHidden else { return }
        NSCursor.unhide()
        isHidden = false
    }
}

extension View {
    func autoHideCursorInLiveMode(_ isEnabled: Bool, delay: TimeInterval = 2.0) -> some View {
        modifier(CursorAutoHideModifier(isEnabled: isEnabled, delay: delay))
    }
}

#else

extension View {
    func autoHideCursorInLiveMode(_ isEnabled: Bool, delay: TimeInterval = 2.0) -> some View {
        self
    }
}

#endif
