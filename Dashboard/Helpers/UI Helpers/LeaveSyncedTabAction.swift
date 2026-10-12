import SwiftUI

private struct LeaveSyncedTabActionKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Stops syncing the tab with the given `syncGroupID`, keeping it as a local tab.
    var leaveSyncedTabAction: (String) -> Void {
        get { self[LeaveSyncedTabActionKey.self] }
        set { self[LeaveSyncedTabActionKey.self] = newValue }
    }
}
