import Foundation

/// Pure, UUID-addressed resolution and replacement for dashboard tabs and tiles.
///
/// Array offsets are never a safe identity for dashboard data: tabs reorder,
/// tiles are deleted, and SwiftUI bindings outlive the render pass that created
/// them. Everything here resolves the current index from a stable UUID at the
/// moment of the write, and reports `false` rather than guessing when the
/// target no longer exists.
enum DashboardTabIdentityMutation {
    static func index(of tabID: UUID, in tabs: [DashboardTab]) -> Int? {
        tabs.firstIndex { $0.id == tabID }
    }

    @discardableResult
    static func replaceTab(_ newValue: DashboardTab, withID tabID: UUID, in tabs: inout [DashboardTab]) -> Bool {
        guard let index = index(of: tabID, in: tabs) else { return false }
        tabs[index] = newValue
        return true
    }

    @discardableResult
    static func replaceTile(_ newValue: DashboardTileModel, tabID: UUID, tileID: UUID, in tabs: inout [DashboardTab]) -> Bool {
        guard let tabIndex = index(of: tabID, in: tabs),
              let tileIndex = tabs[tabIndex].tiles.firstIndex(where: { $0.id == tileID }) else { return false }
        tabs[tabIndex].tiles[tileIndex] = newValue
        return true
    }
}
