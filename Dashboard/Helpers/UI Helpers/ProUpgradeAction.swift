import SwiftUI

private struct ProUpgradeActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var proUpgradeAction: () -> Void {
        get { self[ProUpgradeActionKey.self] }
        set { self[ProUpgradeActionKey.self] = newValue }
    }
}
