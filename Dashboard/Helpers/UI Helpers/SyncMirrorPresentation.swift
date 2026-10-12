//
//  SyncMirrorPresentation.swift
//  Relay
//
//  Centralizes the icon/color vocabulary shared between Synced Tabs (editable,
//  cross-device canvas) and LAN Mirror (read-only broadcast), so the toolbar pills,
//  inline tab badges, and settings screen all draw from one source instead of
//  picking glyphs and colors ad hoc.
//

import SwiftUI

enum SyncMirrorPresentation {

    /// Violet — reserved for anything related to Synced Tabs (editable).
    static let syncColor = Color(red: 0.56, green: 0.51, blue: 0.95)

    /// Teal — reserved for anything related to LAN Mirror (read-only broadcast).
    static let mirrorColor = Color(red: 0.18, green: 0.79, blue: 0.84)

    enum SyncBadgeState: Equatable {
        case owner
        case subscriber
        case orphaned
        case stale
    }

    /// Orphaned (actively disconnected) always wins over stale (merely unverified) —
    /// a tab that's both must still show the red "disconnected" treatment.
    static func syncBadgeState(isOwner: Bool, isOrphaned: Bool, isStale: Bool) -> SyncBadgeState {
        if isOrphaned { return .orphaned }
        if isStale { return .stale }
        return isOwner ? .owner : .subscriber
    }

    /// Icon reflects ownership (owner vs. subscriber) directly — independent of
    /// connection health. An orphaned or stale *subscriber* tab still shows the
    /// subscriber glyph (just recolored by `syncBadgeColor`), never the owner glyph.
    static func syncIconName(isSubscriber: Bool) -> String {
        isSubscriber ? "link" : "arrow.triangle.2.circlepath"
    }

    static func syncBadgeColor(for state: SyncBadgeState, toolbarForeground: Color, isSelected: Bool) -> Color {
        switch state {
        case .orphaned: return .red
        case .stale: return toolbarForeground.opacity(0.35)
        case .owner, .subscriber: return syncColor.opacity(isSelected ? 1.0 : 0.75)
        }
    }

    static let mirrorIconName = "wifi"

    static func mirrorBadgeColor(isSelected: Bool) -> Color {
        mirrorColor.opacity(isSelected ? 1.0 : 0.75)
    }
}
