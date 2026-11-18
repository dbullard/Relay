//
//  TouchInputDiagnostics.swift
//  Relay
//
//  Opt-in logging of the scroll/gesture events the canvas viewport receives, so a
//  touch monitor (e.g. UPDD) that doesn't pinch-zoom can be diagnosed from one run.
//
//  Enable:  defaults write <bundle id> RelayTouchInputDiagnostics -bool YES  (then relaunch)
//  Read:    Console.app, subsystem "Relay", category "touch-input"
//

#if os(macOS)
import AppKit
import os

enum TouchInputDiagnostics {
    static let defaultsKey = "RelayTouchInputDiagnostics"

    private static let logger = Logger(subsystem: "Relay", category: "touch-input")

    /// Read once per launch: scroll events arrive at a high rate, so the hot path
    /// shouldn't hit UserDefaults for every event.
    static let isEnabledForThisLaunch: Bool = isEnabled()

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    /// Logs `event` with the handling `outcome` (e.g. "handled", "dropped:outside").
    /// No-op unless diagnostics are enabled.
    static func log(_ event: NSEvent, outcome: String) {
        guard isEnabledForThisLaunch else { return }

        var detail = ""
        switch event.type {
        case .scrollWheel:
            detail = "dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY) precise=\(event.hasPreciseScrollingDeltas)"
        case .magnify:
            detail = "magnification=\(event.magnification)"
        case .rotate:
            detail = "rotation=\(event.rotation)"
        default:
            break
        }

        let type = String(describing: event.type)
        let phase = event.phase.rawValue
        let momentum = event.momentumPhase.rawValue
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let windowless = event.window == nil

        logger.info(
            "type=\(type, privacy: .public) phase=\(phase, privacy: .public) momentum=\(momentum, privacy: .public) \(detail, privacy: .public) modifiers=\(modifiers, privacy: .public) windowless=\(windowless, privacy: .public) outcome=\(outcome, privacy: .public)"
        )
    }
}
#endif
