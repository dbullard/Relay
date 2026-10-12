//
//  SyncedTabModels.swift
//  Relay
//
//  Manifest/snapshot types and LWW version comparator for Synced Tabs.
//  Additive: distinct from LANSharedTabManifest / LANSharedTabPayload, which remain unchanged.
//

import Foundation

/// Last-Writer-Wins version tuple for a synced tab.
/// Ordering: `revision` dominates; `editedAt` breaks revision ties; `editedByDeviceID`
/// breaks fully-simultaneous ties so ordering is total (never equal unless identical).
public struct SyncedTabVersion: Codable, Hashable, Comparable {
    public let revision: Int
    public let editedAt: TimeInterval
    public let editedByDeviceID: String

    public init(revision: Int, editedAt: TimeInterval, editedByDeviceID: String) {
        self.revision = revision
        self.editedAt = editedAt
        self.editedByDeviceID = editedByDeviceID
    }

    public static func < (lhs: SyncedTabVersion, rhs: SyncedTabVersion) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        if lhs.editedAt != rhs.editedAt {
            return lhs.editedAt < rhs.editedAt
        }
        return lhs.editedByDeviceID < rhs.editedByDeviceID
    }
}

/// Lightweight metadata for a synced tab, advertised via `GET /syncedTabs`.
/// Powers discovery (the ↻ pills in Plan 3) and the slow fallback poll.
public struct SyncedTabManifest: Codable, Identifiable, Hashable {
    public var id: String { groupID }

    public let groupID: String
    public let tabName: String
    public let deviceID: String
    public let deviceName: String
    public let version: SyncedTabVersion
    public let summary: Summary

    public struct Summary: Codable, Hashable {
        public let tileCount: Int
        public let moduleTypes: [String]

        public init(tileCount: Int, moduleTypes: [String]) {
            self.tileCount = tileCount
            self.moduleTypes = moduleTypes
        }
    }

    public init(
        groupID: String,
        tabName: String,
        deviceID: String,
        deviceName: String,
        version: SyncedTabVersion,
        summary: Summary
    ) {
        self.groupID = groupID
        self.tabName = tabName
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.version = version
        self.summary = summary
    }
}

/// Wrapper for `GET /syncedTabs` response that bundles manifests with the serving device's
/// current editing presence. Clients that poll an older server (which returns a bare array)
/// fall back to decoding `[SyncedTabManifest]` directly.
public struct SyncedTabsResponse: Codable {
    public let manifests: [SyncedTabManifest]
    public let localPresence: SyncedPresencePayload?
    /// groupID -> deviceIDs currently subscribed, as tracked by the serving device (meaningful
    /// only when the serving device is the host for that group). Optional so older peers that
    /// don't send this field still decode fine.
    public let liveSubscribersByGroupID: [String: Set<String>]?

    public init(manifests: [SyncedTabManifest], localPresence: SyncedPresencePayload?, liveSubscribersByGroupID: [String: Set<String>]? = nil) {
        self.manifests = manifests
        self.localPresence = localPresence
        self.liveSubscribersByGroupID = liveSubscribersByGroupID
    }
}

/// Lightweight presence payload: which tiles the serving device is editing or has selected,
/// grouped by synced-tab group ID so the polling device can highlight matching tiles.
public struct SyncedPresencePayload: Codable {
    public let deviceID: String
    public let deviceName: String
    /// groupID → [tileID strings] for tiles the device has open in its inspector.
    public let editingByGroup: [String: [String]]
    /// groupID → [tileID strings] for tiles the device has selected on the canvas (not editing).
    /// Optional so older builds that omit it still decode successfully.
    public let selectedByGroup: [String: [String]]?

    public init(deviceID: String, deviceName: String, editingByGroup: [String: [String]], selectedByGroup: [String: [String]]? = nil) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.editingByGroup = editingByGroup
        self.selectedByGroup = selectedByGroup
    }
}

/// Full snapshot of a synced tab. Used for `GET /syncedTab/<groupID>` (join + fallback resync)
/// and `POST /syncedTab/push` (debounced push-on-edit).
public struct SyncedTabSnapshot: Codable, Hashable {
    public var groupID: String
    public var tabName: String
    /// The encoded `DashboardTab`, including its synced fields.
    public var exportedTabJSON: Data
    public let schemaVersion: Int
    public let version: SyncedTabVersion
    public let lastEditedByDeviceName: String
    public let hash: String

    public init(
        groupID: String,
        tabName: String,
        exportedTabJSON: Data,
        schemaVersion: Int,
        version: SyncedTabVersion,
        lastEditedByDeviceName: String,
        hash: String
    ) {
        self.groupID = groupID
        self.tabName = tabName
        self.exportedTabJSON = exportedTabJSON
        self.schemaVersion = schemaVersion
        self.version = version
        self.lastEditedByDeviceName = lastEditedByDeviceName
        self.hash = hash
    }
}

/// Applies the stable, out-of-band sync identity and version to a decoded tab snapshot.
/// Older Relay versions may omit sync fields from `DashboardTab` JSON; the receiving tab's
/// group membership must survive those updates or the settings toggle appears to turn off.
enum SyncedTabSnapshotCompatibility {
    static func applying(_ snapshot: SyncedTabSnapshot, to incoming: DashboardTab, preserving current: DashboardTab) -> DashboardTab {
        var result = incoming
        result.id = current.id
        result.lanMirrorShareId = current.lanMirrorShareId
        result.syncGroupID = current.syncGroupID
        result.syncIsOwner = current.syncIsOwner
        result.syncOwnerDeviceID = current.syncOwnerDeviceID
        if !current.syncOwnerDeviceName.isEmpty {
            result.syncOwnerDeviceName = current.syncOwnerDeviceName
        }
        result.syncRevision = snapshot.version.revision
        result.syncLastEditedAt = snapshot.version.editedAt
        result.syncLastEditedByDeviceID = snapshot.version.editedByDeviceID
        result.syncLastEditedByDeviceName = snapshot.lastEditedByDeviceName
        return result
    }
}

/// Sent by the host via `POST /syncedTab/stop` to notify subscribers that a group is no longer syncing.
public struct SyncedTabStopPayload: Codable {
    public let groupID: String
    public let deviceID: String
    public let deviceName: String

    public init(groupID: String, deviceID: String, deviceName: String) {
        self.groupID = groupID
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}
