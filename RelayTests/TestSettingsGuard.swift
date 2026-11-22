import Foundation
import XCTest

/// Loaded as the test bundle's principal class (`NSPrincipalClass` in the RelayTests
/// build settings), before any test runs.
///
/// Unit tests run inside a copy of Relay that shares the real app's `UserDefaults`
/// domain (`app.relay.Relay`). Several tests remove or overwrite keys there (LAN paired
/// devices and pairing code, transcription inputs, SPL logging), which used to wipe the
/// developer's real settings whenever the suite ran. This snapshots the whole domain when
/// the bundle loads and puts it back when the run finishes, so nothing a test writes
/// survives the run.
///
/// Limits: a test run that crashes skips the restore, and a real copy of Relay running
/// at the same time can see the temporary values while tests run.
final class TestSettingsGuard: NSObject, XCTestObservation {
    private let domainName: String
    private let snapshot: [String: Any]?

    override init() {
        domainName = Bundle.main.bundleIdentifier ?? "app.relay.Relay"
        snapshot = UserDefaults.standard.persistentDomain(forName: domainName)
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        restore()
    }

    private func restore() {
        let defaults = UserDefaults.standard
        if let snapshot {
            defaults.setPersistentDomain(snapshot, forName: domainName)
        } else {
            defaults.removePersistentDomain(forName: domainName)
        }
        defaults.synchronize()
    }
}
