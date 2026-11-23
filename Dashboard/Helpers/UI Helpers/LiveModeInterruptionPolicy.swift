//
//  LiveModeInterruptionPolicy.swift
//  Relay
//
//  Decides how interruptions (lost connections, pairing requests) reach the operator.
//  Outside Live Mode a modal is fine. During a live show nothing may block the dashboard:
//  interruptions become non-blocking banners, and anything that needs a decision waits
//  until the operator asks for it or leaves Live Mode. Nothing is ever approved or
//  denied on the operator's behalf.
//

import Foundation

enum LiveModeInterruptionPolicy {
    enum Presentation: Equatable {
        /// A blocking alert or sheet.
        case modal
        /// A non-blocking banner over the dashboard.
        case banner
    }

    /// How long the "Connection Lost" banner stays up in Live Mode.
    static let connectionLostBannerDuration: Double = 8

    /// "Connection Lost" (a mirrored LAN tab went away).
    static func connectionLostPresentation(isLiveMode: Bool) -> Presentation {
        isLiveMode ? .banner : .modal
    }

    /// Whether the pairing approval sheet may be on screen. In Live Mode a request stays
    /// queued until the operator taps Review; leaving Live Mode presents it.
    static func mayPresentPairingApproval(isLiveMode: Bool, reviewRequested: Bool) -> Bool {
        !isLiveMode || reviewRequested
    }

    /// Whether to show the non-blocking "Review" banner for a queued pairing request.
    static func showsPairingReviewBanner(
        isLiveMode: Bool,
        hasQueuedRequest: Bool,
        reviewRequested: Bool
    ) -> Bool {
        hasQueuedRequest && !mayPresentPairingApproval(isLiveMode: isLiveMode, reviewRequested: reviewRequested)
    }

    static func pairingBannerTitle(queuedCount: Int) -> String {
        queuedCount > 1 ? "\(queuedCount) pairing requests waiting" : "Pairing request waiting"
    }

    static func pairingBannerSubtitle(deviceName: String) -> String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "A device" : "\u{201C}\(trimmed)\u{201D}"
        return "\(name) wants to pair. Nothing is allowed until you review it."
    }
}
