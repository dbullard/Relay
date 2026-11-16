import Foundation

// Every UserDefaults write posts `didChangeNotification` and wakes every
// `@AppStorage` view in the app, even when the stored value is the same.
// These helpers skip the write when nothing would change.
extension UserDefaults {
    /// Stores `value` only when it differs from what is already stored.
    /// Passing nil removes the key if it is present.
    func setIfChanged(_ value: Any?, forKey key: String) {
        guard let value else {
            removeIfPresent(forKey: key)
            return
        }
        if let existing = object(forKey: key) as? NSObject,
           let incoming = value as? NSObject,
           existing.isEqual(incoming) {
            return
        }
        set(value, forKey: key)
    }

    /// Removes `key` only when it is present.
    func removeIfPresent(forKey key: String) {
        guard object(forKey: key) != nil else { return }
        removeObject(forKey: key)
    }
}

extension JSONEncoder {
    /// An encoder with sorted keys. JSONEncoder's key order otherwise varies
    /// between runs, so identical values would encode to different bytes and
    /// defeat `setIfChanged`.
    static func stableKeyOrder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
