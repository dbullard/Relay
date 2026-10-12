import Foundation

enum ConsoleDeviceDataAdapter {
    static func syncedChannelNamesByChannel(deviceId: UUID) -> [Int: String] {
        let defaultsKeys = [
            "prodlink.x32sync.map.\(deviceId.uuidString)",
            "prodlink.ah.sync.map.\(deviceId.uuidString)",
            "prodlink.dlive.sync.map.\(deviceId.uuidString)"
        ]
        for defaultsKey in defaultsKeys {
            if let data = UserDefaults.standard.data(forKey: defaultsKey),
               let decoded = try? JSONDecoder().decode([Int: String].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
        }
        return [:]
    }

    static func syncedChannelNamesByChannel(for device: ExternalDeviceConfig) -> [Int: String] {
        let persisted = syncedChannelNamesByChannel(deviceId: device.id)
        if !persisted.isEmpty {
            return persisted
        }

        let mirror = Mirror(reflecting: device)

        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            let looksRelevant = (label.contains("sync") || label.contains("synced")) &&
                (label.contains("channel") || label.contains("ch")) &&
                (label.contains("name") || label.contains("names") || label.contains("map"))
            if looksRelevant, let map = normalizeChannelNameMap(child.value) {
                return map
            }
        }

        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            let looksRelevant = label.contains("x32") && (label.contains("name") || label.contains("map"))
            if looksRelevant, let map = normalizeChannelNameMap(child.value) {
                return map
            }
        }

        return [:]
    }

    private static func normalizeChannelNameMap(_ any: Any) -> [Int: String]? {
        if let d = any as? [Int: String] { return d }
        if let d = any as? [String: String] {
            var out: [Int: String] = [:]
            for (k, v) in d {
                if let i = Int(k) { out[i] = v }
            }
            return out.isEmpty ? nil : out
        }
        if let d = any as? [Int: String?] {
            var out: [Int: String] = [:]
            for (k, v) in d {
                if let v, !v.isEmpty { out[k] = v }
            }
            return out.isEmpty ? nil : out
        }
        if let d = any as? [String: String?] {
            var out: [Int: String] = [:]
            for (k, v) in d {
                if let i = Int(k), let v, !v.isEmpty { out[i] = v }
            }
            return out.isEmpty ? nil : out
        }
        return nil
    }
}
