//
//  DevicePairingStore.swift
//  Relay
//
//  Pure trust-map logic for device-approval pairing. Replaces the old shared
//  lan_pairing_code string with per-device trust, keyed by each peer's stable
//  deviceId (not endpointKey, which changes whenever a device's IP/port changes).
//
//  One boolean (isEnabled) covers three real states: no entry (never paired,
//  default-allowed-to-request), isEnabled true (paired/trusted), isEnabled false
//  (blocked — whether pre-blocked before ever pairing, or revoked afterward).
//  Flipping a device's switch on in Settings is itself a valid approval path
//  (the host owner acting locally) — equivalent to tapping Approve on the live
//  prompt — so setEnabled(true, ...) covers both cases.
//

import Foundation

public struct PairedDevice: Codable, Equatable {
    public let deviceId: String
    public var deviceName: String
    public var deviceKind: LANDeviceKind?
    public var isEnabled: Bool
    public var sharesVariables: Bool
    public let pairedAt: Date

    public init(deviceId: String, deviceName: String, deviceKind: LANDeviceKind?, isEnabled: Bool, pairedAt: Date, sharesVariables: Bool = true) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceKind = deviceKind
        self.isEnabled = isEnabled
        self.sharesVariables = sharesVariables
        self.pairedAt = pairedAt
    }

    private enum CodingKeys: String, CodingKey { case deviceId, deviceName, deviceKind, isEnabled, pairedAt, sharesVariables }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        deviceName = try c.decode(String.self, forKey: .deviceName)
        deviceKind = try c.decodeIfPresent(LANDeviceKind.self, forKey: .deviceKind)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        pairedAt = try c.decode(Date.self, forKey: .pairedAt)
        sharesVariables = try c.decodeIfPresent(Bool.self, forKey: .sharesVariables) ?? true
    }
}

public enum DevicePairingStatus: Equatable {
    case notPaired
    case paired
    case blocked
}

public enum DevicePairingStore {
    private static let userDefaultsKey = "lan_paired_devices"

    public static func load(from defaults: UserDefaults = .standard) -> [String: PairedDevice] {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: PairedDevice].self, from: data) else {
            return [:]
        }
        return decoded
    }

    public static func save(_ devices: [String: PairedDevice], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }

    public static func status(for deviceId: String, in devices: [String: PairedDevice]) -> DevicePairingStatus {
        guard let entry = devices[deviceId] else { return .notPaired }
        return entry.isEnabled ? .paired : .blocked
    }

    public static func isAuthorized(deviceId: String, in devices: [String: PairedDevice]) -> Bool {
        status(for: deviceId, in: devices) == .paired
    }

    public static func setSharesVariables(_ enabled: Bool, deviceId: String, in devices: [String: PairedDevice]) -> [String: PairedDevice] {
        var updated = devices
        guard var entry = updated[deviceId], entry.isEnabled else { return updated }
        entry.sharesVariables = enabled
        updated[deviceId] = entry
        return updated
    }

    public static func setEnabled(
        _ enabled: Bool,
        deviceId: String,
        deviceName: String,
        deviceKind: LANDeviceKind?,
        in devices: [String: PairedDevice]
    ) -> [String: PairedDevice] {
        var updated = devices
        if var existing = updated[deviceId] {
            existing.isEnabled = enabled
            existing.deviceName = deviceName
            existing.deviceKind = deviceKind
            updated[deviceId] = existing
        } else {
            updated[deviceId] = PairedDevice(
                deviceId: deviceId,
                deviceName: deviceName,
                deviceKind: deviceKind,
                isEnabled: enabled,
                pairedAt: Date()
            )
        }
        return updated
    }

    /// Fully forgets a device — distinct from setEnabled(false, ...), which keeps a blocked
    /// record so a future setEnabled(true, ...) can restore trust without re-pairing. This
    /// deletes the entry outright: reconnecting afterward requires a brand new handshake.
    public static func remove(deviceId: String, in devices: [String: PairedDevice]) -> [String: PairedDevice] {
        var updated = devices
        updated.removeValue(forKey: deviceId)
        return updated
    }

    /// Re-keys a legacy entry saved under a peer's display name onto its real deviceId.
    /// Builds that browsed without TXT records identified peers by Bonjour service name, so
    /// trust granted by the device that started pairing was keyed by the other computer's
    /// name — which never matches the `X-Relay-Device-Id` its requests actually carry.
    /// A legacy entry is one whose key and stored deviceId are both the name. If `deviceId`
    /// already has its own entry, that entry wins and the legacy duplicate is dropped.
    public static func migratingLegacyNameKeyedEntry(
        toDeviceId deviceId: String,
        deviceName: String,
        deviceKind: LANDeviceKind?,
        in devices: [String: PairedDevice]
    ) -> [String: PairedDevice] {
        guard deviceId != deviceName,
              let legacy = devices[deviceName],
              legacy.deviceId == deviceName else {
            return devices
        }
        var updated = devices
        updated.removeValue(forKey: deviceName)
        if updated[deviceId] == nil {
            updated[deviceId] = PairedDevice(
                deviceId: deviceId,
                deviceName: deviceName,
                deviceKind: deviceKind ?? legacy.deviceKind,
                isEnabled: legacy.isEnabled,
                pairedAt: legacy.pairedAt,
                sharesVariables: legacy.sharesVariables
            )
        }
        return updated
    }
}
