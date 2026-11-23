//
//  LiveDataStatus.swift
//  Relay
//
//  One way for every live tile to say its data can't be trusted right now: the device
//  is offline, reconnecting, or has gone quiet. The tile is dimmed and greyed, and a
//  badge says what happened and how long ago the last update arrived, in words and an
//  icon, never colour alone.
//

import SwiftUI

/// How current a tile's data is.
enum LiveDataStatus: Equatable {
    case live
    /// Never connected yet and no error so far.
    case connecting
    case reconnecting(lastUpdate: Date?)
    /// Connected, but nothing new arrived within the stale threshold.
    case stale(lastUpdate: Date?)
    case offline(lastUpdate: Date?, reason: String?)

    /// Works out the status from what a connection service already tracks.
    /// - Parameters:
    ///   - lastUpdate: when data last arrived (nil if never this session).
    ///   - staleAfter: seconds without data before connected data counts as stale;
    ///     nil when the source has no regular update rhythm.
    ///   - reason: the last error, if any. A failure before the first update is
    ///     offline, not connecting.
    static func resolve(
        isConnected: Bool,
        isReconnecting: Bool,
        lastUpdate: Date?,
        staleAfter: TimeInterval?,
        reason: String? = nil,
        now: Date = Date()
    ) -> LiveDataStatus {
        if !isConnected {
            if isReconnecting { return .reconnecting(lastUpdate: lastUpdate) }
            if lastUpdate == nil, reason == nil { return .connecting }
            return .offline(lastUpdate: lastUpdate, reason: reason)
        }
        if let staleAfter, let lastUpdate, now.timeIntervalSince(lastUpdate) > staleAfter {
            return .stale(lastUpdate: lastUpdate)
        }
        return .live
    }

    var isLive: Bool { self == .live }

    var title: String {
        switch self {
        case .live: return "Live"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .stale: return "No new data"
        case .offline: return "Offline"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .stale: return "clock.badge.exclamationmark"
        case .offline: return "bolt.horizontal.circle"
        }
    }

    var tint: Color {
        switch self {
        case .live: return .green
        case .connecting: return .secondary
        case .reconnecting, .stale: return .orange
        case .offline: return .red
        }
    }

    var lastUpdate: Date? {
        switch self {
        case .live, .connecting: return nil
        case .reconnecting(let date), .stale(let date), .offline(let date, _): return date
        }
    }

    var reason: String? {
        if case .offline(_, let reason) = self { return reason }
        return nil
    }

    /// Short age for the badge: "12s ago", "4m ago", "2h ago".
    static func ageText(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    /// Full sentence for VoiceOver and the tooltip.
    func spokenDescription(now: Date) -> String {
        var parts = [title]
        if let lastUpdate {
            parts.append("last update \(Self.ageText(since: lastUpdate, now: now))")
        }
        if let reason, !reason.isEmpty {
            parts.append(reason)
        }
        return parts.joined(separator: ", ")
    }
}

/// The badge: icon + word + age. Its age ticks once a second without redrawing the tile.
struct LiveDataStatusBadge: View {
    let status: LiveDataStatus
    var font: Font = .caption

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.tint)
                Text(status.title)
                    .fontWeight(.semibold)
                if let lastUpdate = status.lastUpdate {
                    Text(LiveDataStatus.ageText(since: lastUpdate, now: context.date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thickMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(status.tint.opacity(0.7), lineWidth: 1))
            .help(status.spokenDescription(now: context.date))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.spokenDescription(now: context.date))
        }
    }
}

private struct LiveDataStatusModifier: ViewModifier {
    let isConnected: Bool
    let isReconnecting: Bool
    let lastUpdate: Date?
    let staleAfter: TimeInterval?
    let reason: String?
    let badgeFont: Font
    let badgeAlignment: Alignment

    /// Moves forward only when the data is due to go stale, so the tile isn't redrawn every second.
    @State private var now = Date()

    private struct StaleDeadlineKey: Equatable {
        let isConnected: Bool
        let lastUpdate: Date?
        let staleAfter: TimeInterval?
    }

    func body(content: Content) -> some View {
        let status = LiveDataStatus.resolve(
            isConnected: isConnected,
            isReconnecting: isReconnecting,
            lastUpdate: lastUpdate,
            staleAfter: staleAfter,
            reason: reason,
            now: now
        )
        content
            .opacity(status.isLive ? 1 : 0.5)
            .saturation(status.isLive ? 1 : 0)
            .overlay(alignment: badgeAlignment) {
                if !status.isLive {
                    LiveDataStatusBadge(status: status, font: badgeFont)
                        .padding(6)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: status.isLive)
            .task(id: StaleDeadlineKey(isConnected: isConnected, lastUpdate: lastUpdate, staleAfter: staleAfter)) {
                now = Date()
                guard isConnected, let lastUpdate, let staleAfter else { return }
                let wait = lastUpdate.addingTimeInterval(staleAfter).timeIntervalSinceNow
                guard wait > 0 else { return }
                try? await Task.sleep(for: .seconds(wait + 0.05))
                guard !Task.isCancelled else { return }
                now = Date()
            }
    }
}

extension View {
    /// Dims and greys this view and shows a status badge whenever its live data is
    /// offline, reconnecting or stale. Pass what the connection service already tracks.
    func liveDataStatus(
        isConnected: Bool,
        isReconnecting: Bool = false,
        lastUpdate: Date?,
        staleAfter: TimeInterval?,
        reason: String? = nil,
        badgeFont: Font = .caption,
        badgeAlignment: Alignment = .topTrailing
    ) -> some View {
        modifier(
            LiveDataStatusModifier(
                isConnected: isConnected,
                isReconnecting: isReconnecting,
                lastUpdate: lastUpdate,
                staleAfter: staleAfter,
                reason: reason,
                badgeFont: badgeFont,
                badgeAlignment: badgeAlignment
            )
        )
    }
}
