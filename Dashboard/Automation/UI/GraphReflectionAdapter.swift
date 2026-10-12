import Foundation

enum GraphReflectionAdapter {
    static func reflectedAny(from root: Any, keys: [String]) -> Any? {
        let mirror = Mirror(reflecting: root)
        for child in mirror.children {
            guard let label = child.label else { continue }
            if keys.contains(label) {
                return child.value
            }
        }
        return nil
    }

    static func reflectedStringArray(from root: Any, keys: [String]) -> [String]? {
        guard let any = reflectedAny(from: root, keys: keys) else { return nil }
        if let arr = any as? [String] { return arr }
        if let arr = any as? [String?] { return arr.compactMap { $0 } }
        return nil
    }

    static func extractTitlesAndKeys(fromArrayAny any: Any) -> [(title: String, key: String?)] {
        let mirror = Mirror(reflecting: any)
        if mirror.displayStyle == .optional, let first = mirror.children.first {
            return extractTitlesAndKeys(fromArrayAny: first.value)
        }
        if let s = any as? [String] {
            return s.map { ($0, nil) }
        }
        if let s = any as? [String?] {
            return s.compactMap { $0 }.map { ($0, nil) }
        }
        if mirror.displayStyle == .collection {
            return mirror.children.compactMap { extractTitleAndKey(fromItemAny: $0.value) }
        }
        return []
    }

    static func extractTitles(fromArrayAny any: Any) -> [String] {
        let mirror = Mirror(reflecting: any)
        if mirror.displayStyle == .optional, let first = mirror.children.first {
            return extractTitles(fromArrayAny: first.value)
        }
        if let s = any as? [String] { return s }
        if let s = any as? [String?] { return s.compactMap { $0 } }
        if let seq = any as? AnySequence<Any> {
            return seq.compactMap { extractTitle(fromItemAny: $0) }
        }
        if mirror.displayStyle == .collection {
            return mirror.children.compactMap { extractTitle(fromItemAny: $0.value) }
        }
        return []
    }

    static func extractId(from dev: Any) -> UUID? {
        (Mirror(reflecting: dev).children.first { $0.label == "id" }?.value as? UUID)
        ?? ((dev as AnyObject).value(forKey: "id") as? UUID)
    }

    static func extractAssignmentsCount(from dev: Any) -> Int {
        if let dict = (Mirror(reflecting: dev).children.first { $0.label == "consoleChannelAssignments" }?.value as? [String: Int]) {
            return dict.count
        }
        if let dict = ((dev as AnyObject).value(forKey: "consoleChannelAssignments") as? [String: Int]) {
            return dict.count
        }
        if let dict = (Mirror(reflecting: dev).children.first { $0.label == "consolePositionChannelDefaults" }?.value as? [String: Int]) {
            return dict.count
        }
        if let dict = ((dev as AnyObject).value(forKey: "consolePositionChannelDefaults") as? [String: Int]) {
            return dict.count
        }
        return 0
    }

    private static func extractTitleAndKey(fromItemAny item: Any) -> (title: String, key: String?)? {
        let mirror = Mirror(reflecting: item)
        if mirror.displayStyle == .optional, let first = mirror.children.first {
            return extractTitleAndKey(fromItemAny: first.value)
        }
        if let s = item as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : (t, nil)
        }

        var foundTitle: String?
        var foundKey: String?
        for child in mirror.children {
            guard let label = child.label else { continue }
            if label == "title" || label == "name" {
                if let s = child.value as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { foundTitle = t }
                } else if let s = child.value as? String? {
                    let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { foundTitle = t }
                }
            }
            if label == "key" || label == "songKey" || label == "song_key" || label == "keyName" || label == "key_name" || label == "keyText" || label == "key_text" {
                if let s = child.value as? String {
                    let k = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty { foundKey = k }
                } else if let s = child.value as? String? {
                    let k = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty { foundKey = k }
                }
            }
        }
        guard let title = foundTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        let key = foundKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, (key?.isEmpty ?? true) ? nil : key)
    }

    private static func extractTitle(fromItemAny item: Any) -> String? {
        let mirror = Mirror(reflecting: item)
        if mirror.displayStyle == .optional, let first = mirror.children.first {
            return extractTitle(fromItemAny: first.value)
        }
        if let s = item as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        for child in mirror.children {
            guard let label = child.label else { continue }
            if label == "title" || label == "name" {
                if let s = child.value as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }
                if let s = child.value as? String? {
                    let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }
            }
        }
        return nil
    }
}
