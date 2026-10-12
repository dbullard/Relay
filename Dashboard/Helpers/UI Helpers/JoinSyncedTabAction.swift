import SwiftUI

private struct JoinSyncedTabActionKey: EnvironmentKey {
    static let defaultValue: (SyncedTabManifest) -> Void = { _ in }
}

extension EnvironmentValues {
    var joinSyncedTabAction: (SyncedTabManifest) -> Void {
        get { self[JoinSyncedTabActionKey.self] }
        set { self[JoinSyncedTabActionKey.self] = newValue }
    }
}
