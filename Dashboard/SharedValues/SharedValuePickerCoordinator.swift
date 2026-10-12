import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
protocol SharedValueInsertionTarget: AnyObject {
    func insertSharedValueToken(_ token: String) -> Bool
}

@MainActor
final class SharedValuePickerCoordinator {
    static let shared = SharedValuePickerCoordinator()

    enum Result: Equatable { case inserted, copied }

    weak var target: (any SharedValueInsertionTarget)?

    func insertOrCopy(name: String) -> Result {
        let normalizedName: String
        if let separator = name.firstIndex(of: ":") {
            let source = String(name[..<separator]).lowercased()
            let variableName = String(name[name.index(after: separator)...])
            if ["shared", "person", "graph"].contains(source) {
                normalizedName = "\(source):\(normalizeSharedValueName(variableName))"
            } else {
                normalizedName = normalizeSharedValueName(name)
            }
        } else {
            normalizedName = normalizeSharedValueName(name)
        }
        let token = "#{\(normalizedName)}"
        if target?.insertSharedValueToken(token) == true { return .inserted }
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
#endif
        return .copied
    }
}

/// Retained by an editor while the floating Variables window has focus.
@MainActor
final class SharedValueBindingInsertionTarget: SharedValueInsertionTarget {
    var onInsert: ((String) -> Bool)?

    func insertSharedValueToken(_ token: String) -> Bool {
        onInsert?(token) ?? false
    }
}
