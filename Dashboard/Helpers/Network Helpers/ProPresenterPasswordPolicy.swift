import Foundation

/// Secrets stay in the Keychain on the device that owns them. They are not written to
/// `.relay` documents and not served over the (cleartext) LAN bundle endpoint.
enum ProPresenterPasswordPolicy {
    static func exportedPassword(_ stored: String) -> String { "" }
    static func shouldApplyImported(_ imported: String) -> Bool { !imported.isEmpty }
}
