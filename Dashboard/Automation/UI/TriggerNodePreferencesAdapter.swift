import Foundation

enum TriggerNodePreferencesAdapter {
    static func boolValue(in json: String, key: String, defaultValue: Bool) -> Bool {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
            return defaultValue
        }
        return obj[key] ?? defaultValue
    }

    static func settingBoolValue(in json: String, key: String, value: Bool) -> String {
        var dict: [String: Bool] = [:]
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
            dict = obj
        }
        dict[key] = value
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
