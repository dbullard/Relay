//
//  LANSharedTabsService.swift
//  Relay
//
//  Created by David Bullard on 12/22/25.
//


import Foundation
import Network
import Combine

#if canImport(Darwin)
import Darwin
#endif

// Uses ExternalDevicesStore snapshot for Import Bundle


#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

#if canImport(CryptoKit)
import CryptoKit
#endif


// MARK: - Public Models

/// Granular device kind for UI (iPhone, iPad, MacBook, Mac, Windows PC).
public enum LANDeviceKind: String, Codable, Hashable {
    case iphone
    case ipad
    case macbook
    case mac
    case windowsPC
    case unknown

    public static func iconName(for kind: LANDeviceKind?, fallbackDeviceName: String) -> String {
        if let kind {
            switch kind {
            case .iphone: return "iphone"
            case .ipad: return "ipad"
            case .macbook: return "laptopcomputer"
            case .mac: return "desktopcomputer"
            case .windowsPC: return "pc"
            case .unknown: break
            }
        }
        let lower = fallbackDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("macbook") { return "laptopcomputer" }
        if lower.contains("imac") || lower.contains("mac") { return "desktopcomputer" }
        if lower.contains("windows") || lower.contains("pc") { return "pc" }
        return "questionmark.circle"
    }
}

public struct PairingRequestPayload: Codable, Equatable {
    public let requestId: String
    public let deviceId: String
    public let deviceName: String
    public let deviceKind: LANDeviceKind?
    public let reason: String
    public var publicKey: String? = nil
}

public enum PairingOutcome: String, Codable {
    case pending
    case approved
    case denied
}

public struct PendingPairingRequest: Identifiable, Equatable {
    public var id: String { payload.requestId }
    public let payload: PairingRequestPayload
    public let receivedAt: Date
}

/// Lightweight metadata shown as an ephemeral "network tab".
public struct LANSharedTabManifest: Codable, Identifiable, Hashable {
public var id: String { shareId }

    /// A short, stable identifier for the source device (derived from deviceId).
    /// Useful for a small badge next to the device name in the UI.
    public var deviceShortID: String {
        let cleaned = deviceId.replacingOccurrences(of: "-", with: "")
        let suffixCount = min(4, cleaned.count)
        return String(cleaned.suffix(suffixCount)).uppercased()
    }

    /// Recommended UI label, e.g. "Booth iPad • 7C3A".
    public var deviceDisplayLabel: String {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.isEmpty ? "Device" : name
        return "\(resolvedName) • \(deviceShortID)"
    }
public let shareId: String
public let deviceId: String
public let deviceName: String
/// Granular device type for UI (iPhone, iPad, MacBook, Mac, Windows PC).
public let deviceKind: LANDeviceKind?

    /// Reference canvas size of the source device when the tab was exported.
    /// Optional for backward compatibility with older peers.
    public let referenceCanvasWidth: Double?
    public let referenceCanvasHeight: Double?

    /// Convenience computed size (nil if not present).
    public var referenceCanvasSize: CGSize? {
        guard let w = referenceCanvasWidth, let h = referenceCanvasHeight else { return nil }
        return CGSize(width: w, height: h)
    }

public let updatedAt: TimeInterval
public var tabName: String
public let summary: Summary
public let hash: String

public struct Summary: Codable, Hashable {
    public let tileCount: Int
    public let moduleTypes: [String]
}

    public init(
        shareId: String,
        deviceId: String,
        deviceName: String,
        deviceKind: LANDeviceKind?,
        referenceCanvasWidth: Double?,
        referenceCanvasHeight: Double?,
        updatedAt: TimeInterval,
        tabName: String,
        summary: Summary,
        hash: String
    ) {
        self.shareId = shareId
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceKind = deviceKind
        self.referenceCanvasWidth = referenceCanvasWidth
        self.referenceCanvasHeight = referenceCanvasHeight
        self.updatedAt = updatedAt
        self.tabName = tabName
        self.summary = summary
        self.hash = hash
    }

    enum CodingKeys: String, CodingKey {
        case shareId
        case deviceId
        case deviceName
        case deviceKind
        case referenceCanvasWidth
        case referenceCanvasHeight
        case updatedAt
        case tabName
        // Back-compat alternate names used by older peers
        case name
        case title
        case summary
        case hash
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.shareId = try c.decode(String.self, forKey: .shareId)
        self.deviceId = try c.decode(String.self, forKey: .deviceId)
        self.deviceName = try c.decode(String.self, forKey: .deviceName)
        self.deviceKind = try c.decodeIfPresent(LANDeviceKind.self, forKey: .deviceKind)

        self.referenceCanvasWidth = try c.decodeIfPresent(Double.self, forKey: .referenceCanvasWidth)
        self.referenceCanvasHeight = try c.decodeIfPresent(Double.self, forKey: .referenceCanvasHeight)

        self.updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0

        // Back-compat: some peers publish the tab label under `name` or `title` instead of `tabName`.
        let t1 = try c.decodeIfPresent(String.self, forKey: .tabName)
        let t2 = try c.decodeIfPresent(String.self, forKey: .name)
        let t3 = try c.decodeIfPresent(String.self, forKey: .title)
        self.tabName = (t1 ?? t2 ?? t3 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        self.summary = try c.decode(Summary.self, forKey: .summary)
        self.hash = try c.decode(String.self, forKey: .hash)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shareId, forKey: .shareId)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(deviceName, forKey: .deviceName)
        try c.encode(deviceKind, forKey: .deviceKind)
        try c.encode(referenceCanvasWidth, forKey: .referenceCanvasWidth)
        try c.encode(referenceCanvasHeight, forKey: .referenceCanvasHeight)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(tabName, forKey: .tabName)
        try c.encode(summary, forKey: .summary)
        try c.encode(hash, forKey: .hash)
    }
}

/// Payload returned by the peer for import.
/// Keep this as raw Data for now so DashboardRootView can decode into its real types later.
public struct LANSharedTabPayload: Codable, Hashable {
    public var shareId: String
    public var tabName: String
    public var exportedTabJSON: Data // your exported DashboardTab data
    public let schemaVersion: Int
    public let hash: String

    enum CodingKeys: String, CodingKey {
        case shareId
        case tabName
        case exportedTabJSON
        // Back-compat alternate names used by older peers
        case tabJSON
        case exportedTabData
        case tabData
        case schemaVersion
        case hash
    }

    public init(shareId: String, tabName: String, exportedTabJSON: Data, schemaVersion: Int, hash: String) {
        self.shareId = shareId
        self.tabName = tabName
        self.exportedTabJSON = exportedTabJSON
        self.schemaVersion = schemaVersion
        self.hash = hash
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Back-compat: some peers/versions may omit shareId in the payload response.
        // The caller already knows the shareId from the request path.
        self.shareId = try c.decodeIfPresent(String.self, forKey: .shareId) ?? ""

        // Back-compat: some peers may omit tabName; caller can fall back to manifest.tabName.
        self.tabName = try c.decodeIfPresent(String.self, forKey: .tabName) ?? ""

        // Back-compat: exported tab may be encoded as base64 Data OR as a raw JSON String.
        func decodeTabData(for key: CodingKeys) throws -> Data? {
            if let d = try c.decodeIfPresent(Data.self, forKey: key) {
                return d
            }
            if let s = try c.decodeIfPresent(String.self, forKey: key) {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return trimmed.data(using: .utf8)
            }
            return nil
        }

        let d1 = try decodeTabData(for: .exportedTabJSON)
        let d2 = try decodeTabData(for: .tabJSON)
        let d3 = try decodeTabData(for: .exportedTabData)
        let d4 = try decodeTabData(for: .tabData)
        self.exportedTabJSON = d1 ?? d2 ?? d3 ?? d4 ?? Data()
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.hash = try c.decodeIfPresent(String.self, forKey: .hash) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shareId, forKey: .shareId)
        try c.encode(tabName, forKey: .tabName)
        try c.encode(exportedTabJSON, forKey: .exportedTabJSON)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(hash, forKey: .hash)
    }
}

/// Bundle used for "Import Tab". Includes the tab payload plus host external-device configuration and other settings.
public struct LANSharedTabImportBundle: Codable, Hashable {
public let payload: LANSharedTabPayload

/// JSON-encoded snapshot returned by `ExternalDevicesStore.shared.currentSnapshot()`.
public let externalDevicesJSON: Data?

/// JSON blob containing ProPresenter profiles + active selection + global keys.
public let proPresenterSettingsJSON: Data?

/// JSON blob containing Resolume profiles store persisted data.
public let resolumeSettingsJSON: Data?

/// Optional: Planning Center service/cache snapshot for quicker first render.
/// (No auth tokens; the importing device must login to PCO.)
public let planningCenterServiceJSON: Data?

enum CodingKeys: String, CodingKey {
    case payload
    case externalDevicesJSON
    case proPresenterSettingsJSON
    case resolumeSettingsJSON
    case planningCenterServiceJSON
}

public init(
    payload: LANSharedTabPayload,
    externalDevicesJSON: Data?,
    proPresenterSettingsJSON: Data?,
    resolumeSettingsJSON: Data?,
    planningCenterServiceJSON: Data?
) {
    self.payload = payload
    self.externalDevicesJSON = externalDevicesJSON
    self.proPresenterSettingsJSON = proPresenterSettingsJSON
    self.resolumeSettingsJSON = resolumeSettingsJSON
    self.planningCenterServiceJSON = planningCenterServiceJSON
}

public init(from decoder: Decoder) throws {
    if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.payload) {
        self.payload = try c.decode(LANSharedTabPayload.self, forKey: .payload)
        self.externalDevicesJSON = try c.decodeIfPresent(Data.self, forKey: .externalDevicesJSON)
        self.proPresenterSettingsJSON = try c.decodeIfPresent(Data.self, forKey: .proPresenterSettingsJSON)
        self.resolumeSettingsJSON = try c.decodeIfPresent(Data.self, forKey: .resolumeSettingsJSON)
        self.planningCenterServiceJSON = try c.decodeIfPresent(Data.self, forKey: .planningCenterServiceJSON)
        return
    }

    // Back-compat: some peers return just the payload instead of a bundle wrapper.
    self.payload = try LANSharedTabPayload(from: decoder)

    if let c = try? decoder.container(keyedBy: CodingKeys.self) {
        self.externalDevicesJSON = try c.decodeIfPresent(Data.self, forKey: .externalDevicesJSON)
        self.proPresenterSettingsJSON = try c.decodeIfPresent(Data.self, forKey: .proPresenterSettingsJSON)
        self.resolumeSettingsJSON = try c.decodeIfPresent(Data.self, forKey: .resolumeSettingsJSON)
        self.planningCenterServiceJSON = try c.decodeIfPresent(Data.self, forKey: .planningCenterServiceJSON)
    } else {
        self.externalDevicesJSON = nil
        self.proPresenterSettingsJSON = nil
        self.resolumeSettingsJSON = nil
        self.planningCenterServiceJSON = nil
    }
}

public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(payload, forKey: .payload)
    try c.encodeIfPresent(externalDevicesJSON, forKey: .externalDevicesJSON)
    try c.encodeIfPresent(proPresenterSettingsJSON, forKey: .proPresenterSettingsJSON)
    try c.encodeIfPresent(resolumeSettingsJSON, forKey: .resolumeSettingsJSON)
    try c.encodeIfPresent(planningCenterServiceJSON, forKey: .planningCenterServiceJSON)
}
}

public struct LANPeerNotificationRequest: Codable, Hashable {
    public let title: String
    public let message: String
    public let durationSeconds: Double
    public let sourceDeviceId: String
    public let sourceDeviceName: String
}

public struct BrowserViewerNotificationState: Codable, Hashable {
    public let id: String
    public let title: String
    public let message: String
    public let durationSeconds: Double
}

/// Settings snapshot shared with paired devices. Credentials are never included.
private struct ProPresenterLANSettingsSnapshot: Codable, Hashable {
var globalHost: String
var globalPort: Int
var globalPassword: String
var pollInterval: Double

var profilesJSON: Data?
var activeProfileID: String?

static func loadFromUserDefaults(_ defaults: UserDefaults = .standard) -> ProPresenterLANSettingsSnapshot {
    let globalHost = defaults.string(forKey: "propresenter_host") ?? ""
    let globalPort = defaults.object(forKey: "propresenter_port") as? Int ?? 1025
    let globalPassword = ProPresenterPasswordPolicy.exportedPassword(ProPresenterKeychainStore.shared.password)
    let pollInterval = defaults.object(forKey: "propresenter_pollInterval") as? Double ?? 0.5

    let profilesJSON = defaults.data(forKey: "propresenter_profiles")
    let activeProfileID = defaults.string(forKey: "propresenter_activeProfileID")

    return .init(
        globalHost: globalHost,
        globalPort: globalPort,
        globalPassword: globalPassword,
        pollInterval: pollInterval,
        profilesJSON: profilesJSON,
        activeProfileID: activeProfileID
    )
}
}

// MARK: - Bonjour TXT Keys

private enum LANKeys {
static let deviceId = "deviceId"
static let deviceName = "deviceName"
static let deviceKind = "deviceKind"
static let proto = "proto"
static let pairing = "pairing"
static let enabled = "enabled"
}

// MARK: - Service

/// Bonjour + minimal HTTP server for sharing tabs on LAN.
///
/// MVP: Poll peers every few seconds for their `sharedTabs` manifests.
/// Later: upgrade to WebSocket push without changing consumer API.
@MainActor
public final class LANSharedTabsService: ObservableObject {

// Published list of all remote shared tabs discovered on LAN (minus dismissed).
@Published public private(set) var remoteTabs: [LANSharedTabManifest] = []
@Published public private(set) var localTabs: [LANSharedTabManifest] = []
@Published public private(set) var activeListenPort: UInt16? = nil
private var activeBrowserViewShareId: String? = nil
private var browserViewerNotification: ActiveBrowserViewerNotification? = nil

// Optional: show discovered devices for diagnostics
@Published public private(set) var peers: [Peer] = []
@Published public private(set) var disabledPeerEndpointKeys: Set<String> = []
@Published public private(set) var authFailedPeerEndpointKeys: Set<String> = []
@Published public private(set) var pendingPairingRequests: [PendingPairingRequest] = []
@Published public private(set) var pairedDevices: [String: PairedDevice] = DevicePairingStore.load()
private var linkedVariableLocalTabIDs: Set<UUID> = []
private var linkedVariableLocalPeople: [LinkedDeviceVariable] = []

func setLinkedVariableSourceTabs(_ tabs: [DashboardTab]) {
    linkedVariableLocalTabIDs = Set(tabs.filter { $0.syncGroupID == nil || $0.syncIsOwner }.map(\.id))
    linkedVariableLocalPeople = LinkedDeviceVariableSnapshot.localPeople(in: tabs)
}

public func setVariableSharing(_ enabled: Bool, for peer: Peer) {
    pairedDevices = DevicePairingStore.setSharesVariables(enabled, deviceId: peer.deviceId, in: pairedDevices)
    DevicePairingStore.save(pairedDevices)
    if !enabled { LinkedDeviceVariableStore.shared.clear(deviceID: peer.deviceId) }
}

public struct OutgoingPairingRequest: Equatable {
    public let peerDeviceName: String
    public let reason: String
    public let shortAuthString: String?
}

@Published public private(set) var activePairingRequest: OutgoingPairingRequest? = nil

    /// Set when a pairing attempt fails because the peer 404s on /pair/request — i.e. it's
    /// running a build from before this pairing handshake existed. Surfaced as a root-level
    /// alert since the joiner-side waiting overlay simply disappears on any failure otherwise.
    @Published public private(set) var lastPairingFailureMessage: String? = nil

    public func clearPairingFailure() {
        lastPairingFailureMessage = nil
    }

    /// Clears any discovered peers/tabs immediately (used when LAN sharing is turned off).
    public func clearDiscoveredState() {
        remoteTabs.removeAll()
        peers.removeAll()
        peerManifests.removeAll()
        shareIdOwnerEndpointKey = [:]
        renderRequestLastSeenByShareId.removeAll()
        authFailedPeerEndpointKeys.removeAll()
        for entry in LinkedDeviceVariableStore.shared.entries { LinkedDeviceVariableStore.shared.disconnected(deviceID: entry.deviceID) }
    }

    public func isPeerEnabled(_ peer: Peer) -> Bool {
        !disabledPeerEndpointKeys.contains(peer.endpointKey)
    }

    /// True when the peer hosting `groupID` is currently failing auth (e.g. this device's
    /// trust was revoked). Used so "Joined" tabs in Settings don't imply a healthy connection
    /// when every request to the host is actually being rejected with 401.
    public func isSyncGroupAuthFailed(_ groupID: String) -> Bool {
        guard let ownerKey = syncedGroupOwnerEndpointKey[groupID] else { return false }
        return authFailedPeerEndpointKeys.contains(ownerKey)
    }

    /// True when this device trusts `peer` but `peer` is rejecting our requests (401/403 on the
    /// presence poll). Typical cause: an older Relay build started pairing and saved this device
    /// under its name instead of its deviceId. Reconnect sends a fresh request that the peer
    /// prompts for and then trusts correctly — no update needed on the other computer.
    public func peerNeedsReconnect(_ peer: Peer) -> Bool {
        DevicePairingStore.isAuthorized(deviceId: peer.deviceId, in: pairedDevices)
            && authFailedPeerEndpointKeys.contains(peer.endpointKey)
    }

    #if DEBUG
    /// Test-only hook: simulates recording an auth failure the way the /syncedPresence poll
    /// would, without needing a real peer or network round-trip.
    func recordAuthFailureForTesting(endpointKey: String) {
        authFailedPeerEndpointKeys.insert(endpointKey)
    }

    /// Test-only hook: reads current auth-failure state for a given endpoint key.
    func isAuthFailedForTesting(endpointKey: String) -> Bool {
        authFailedPeerEndpointKeys.contains(endpointKey)
    }
    #endif

    /// Returns shareIds that have requested a render recently (acts as a proxy for active viewers).
    public func activeRenderShareIds(within seconds: TimeInterval = 6.0) -> Set<String> {
        let cutoff = Date().addingTimeInterval(-seconds)
        return Set(renderRequestLastSeenByShareId.compactMap { key, value in
            value >= cutoff ? key : nil
        })
    }

    public func setPeerEnabled(_ enabled: Bool, for peer: Peer) {
        var updated = disabledPeerEndpointKeys
        if enabled {
            updated.remove(peer.endpointKey)
        } else {
            updated.insert(peer.endpointKey)
        }
        disabledPeerEndpointKeys = updated
        UserDefaults.standard.set(Array(updated), forKey: "lan.disabledPeers")

        if !enabled {
            peerManifests.removeValue(forKey: peer.endpointKey)
        }
        authFailedPeerEndpointKeys.remove(peer.endpointKey)
        rebuildRemoteTabs()
    }

    public func hasPairingSecret(for deviceId: String) -> Bool { pairingSecretStore.secret(for: deviceId) != nil }

    private func consumeNonce(_ key: String) -> Bool {
        let now = Date()
        if seenNonces.count > 2048 { seenNonces = seenNonces.filter { now.timeIntervalSince($0.value) < 120 } }
        if let seen = seenNonces[key], now.timeIntervalSince(seen) < 120 { return false }
        seenNonces[key] = now
        return true
    }

    private func recordPairingOutcome(_ outcome: PairingOutcome, for requestId: String) {
        let now = Date()
        pairingOutcomesByRequestId[requestId] = (outcome, now)
        // Prune entries older than 60s so this dictionary doesn't grow unbounded.
        pairingOutcomesByRequestId = pairingOutcomesByRequestId.filter { now.timeIntervalSince($0.value.recordedAt) < 60 }
        pairingHostKeysByRequestId = pairingHostKeysByRequestId.filter { now.timeIntervalSince($0.value.createdAt) < 60 }
    }

    /// The 8-digit code the host user compares with the joiner's screen before approving.
    public func shortAuthString(for request: PendingPairingRequest) -> String? {
        guard let joinerKey = request.payload.publicKey,
              let host = pairingHostKeysByRequestId[request.payload.requestId],
              let secret = try? LANPairingKeyAgreement.deriveSecret(
                  privateKey: host.key.privateKey, peerPublicBase64: joinerKey, requestId: request.payload.requestId)
        else { return nil }
        return LANPairingKeyAgreement.shortAuthString(
            joinerPublicBase64: joinerKey, hostPublicBase64: host.key.publicBase64, secret: secret)
    }

    /// Drops any pending request that's been sitting unresolved for over 60s — a device
    /// that never got approved/denied (e.g. host app was closed) shouldn't linger forever.
    /// A per-device dedup already prevents unbounded growth from retries by one device;
    /// this bounds growth from distinct (including spoofed) deviceIds that are never resolved.
    private func pruneStalePendingPairingRequests() {
        let now = Date()
        pendingPairingRequests.removeAll { now.timeIntervalSince($0.receivedAt) >= 60 }
    }

    /// Approves a pending pairing request: persists trust for the requesting device,
    /// records the outcome so the joiner's GET /pair/status poll picks it up, and
    /// removes the request from the pending list.
    public func approvePairingRequest(_ request: PendingPairingRequest) {
        pairedDevices = DevicePairingStore.setEnabled(
            true,
            deviceId: request.payload.deviceId,
            deviceName: request.payload.deviceName,
            deviceKind: request.payload.deviceKind,
            in: pairedDevices
        )
        DevicePairingStore.save(pairedDevices)
        if let joinerKey = request.payload.publicKey,
           let host = pairingHostKeysByRequestId[request.payload.requestId],
           let secret = try? LANPairingKeyAgreement.deriveSecret(
               privateKey: host.key.privateKey, peerPublicBase64: joinerKey, requestId: request.payload.requestId) {
            pairingSecretStore.setSecret(secret, for: request.payload.deviceId)
        }
        recordPairingOutcome(.approved, for: request.payload.requestId)
        pendingPairingRequests.removeAll { $0.id == request.id }
    }

    /// Denies a pending pairing request and starts a short cooldown so the same
    /// device can't immediately re-trigger another approval prompt.
    public func denyPairingRequest(_ request: PendingPairingRequest) {
        recordPairingOutcome(.denied, for: request.payload.requestId)
        pairingCooldownByDeviceId[request.payload.deviceId] = Date().addingTimeInterval(10)
        // A manual Connect is an explicit request to establish trust from scratch.
        // If the host retained an older trust entry, denying this request must revoke it
        // so the requester does not appear connected on the next attempt.
        if request.payload.reason == "connect" {
            pairedDevices = DevicePairingStore.setEnabled(
                false,
                deviceId: request.payload.deviceId,
                deviceName: request.payload.deviceName,
                deviceKind: request.payload.deviceKind,
                in: pairedDevices
            )
            DevicePairingStore.save(pairedDevices)
        }
        pendingPairingRequests.removeAll { $0.id == request.id }
    }

    /// Manually sets a device's trust from Settings — flipping the switch on is
    /// itself a valid approval (the host owner acting locally), equivalent to
    /// tapping Approve on the live prompt; flipping it off blocks/revokes.
    public func setDeviceEnabled(_ enabled: Bool, for peer: Peer) {
        pairedDevices = DevicePairingStore.setEnabled(
            enabled,
            deviceId: peer.deviceId,
            deviceName: peer.deviceName ?? "Device",
            deviceKind: peer.deviceKind,
            in: pairedDevices
        )
        DevicePairingStore.save(pairedDevices)
        if !enabled { LinkedDeviceVariableStore.shared.clear(deviceID: peer.deviceId) }

        // Resolve any live handshake this device has in flight so the two grant paths
        // (Settings toggle vs. the approval sheet) stay consistent — approving/blocking
        // here shouldn't leave a stale prompt hanging in pendingPairingRequests, and the
        // joiner's own GET /pair/status poll should reflect this decision immediately
        // rather than timing out despite already being trusted.
        for request in pendingPairingRequests where request.payload.deviceId == peer.deviceId {
            recordPairingOutcome(enabled ? .approved : .denied, for: request.payload.requestId)
        }
        pendingPairingRequests.removeAll { $0.payload.deviceId == peer.deviceId }
    }

    /// Fully forgets a device — distinct from setDeviceEnabled(false, ...), which keeps a
    /// blocked record so trust can be restored later without re-pairing. This deletes the
    /// trust entry outright; reconnecting afterward requires a brand new handshake, same as
    /// a device that's never been paired.
    public func forgetDevice(_ peer: Peer) {
        pairedDevices = DevicePairingStore.remove(deviceId: peer.deviceId, in: pairedDevices)
        DevicePairingStore.save(pairedDevices)
        pairingSecretStore.setSecret(nil, for: peer.deviceId)
        LinkedDeviceVariableStore.shared.clear(deviceID: peer.deviceId)
        authFailedPeerEndpointKeys.remove(peer.endpointKey)

        for request in pendingPairingRequests where request.payload.deviceId == peer.deviceId {
            recordPairingOutcome(.denied, for: request.payload.requestId)
        }
        pendingPairingRequests.removeAll { $0.payload.deviceId == peer.deviceId }
    }

    /// Manually initiates a pairing request to `peer` from Settings — lets a user connect
    /// proactively instead of only being able to start pairing by tapping Join/Import on a
    /// tab they've already discovered from that device. Reuses the exact same handshake,
    /// joiner-side waiting overlay, and host-side approval sheet as that tab-triggered flow;
    /// returns true if the peer approved, false if denied/timed out.
    @discardableResult
    public func connectToDevice(_ peer: Peer) async -> Bool {
        await ensurePaired(with: peer, reason: "connect")
    }

    /// Forces a fresh pairing handshake even if local state already shows this peer as
    /// paired -- used to recover from a host-side trust revocation the local device
    /// isn't aware of (see hasAuthFailedSyncedTab in DashboardLANSettingsView.swift).
    /// Unlike connectToDevice, this always calls requestPairing and never short-circuits
    /// on DevicePairingStore.isAuthorized, since that would just return true without
    /// ever contacting the host.
    public func reconnectDevice(_ peer: Peer) async -> Bool {
        await requestPairing(with: peer, reason: "reconnect")
    }

// MARK: - Synced Tabs (published state)

// Manifests discovered from peers for synced tabs this device has NOT joined (discovery pills).
@Published public private(set) var syncedRemoteManifests: [SyncedTabManifest] = []

/// Groups this device **joined** from a remote host (not locally created via makeSyncedTab).
/// Used to distinguish orphan-eligible tabs from host-owned tabs.
@Published public private(set) var joinedSyncGroupIDs: Set<String> = []

/// Groups previously joined that the host has explicitly stopped syncing (or gone offline long enough).
@Published public private(set) var orphanedSyncGroupIDs: Set<String> = []

/// Groups that were orphaned and whose host just reappeared. DashboardRootView observes this
/// to force-fetch the host's authoritative snapshot, bypassing LWW.
@Published public private(set) var reconnectedSyncGroupIDs: Set<String> = []

/// Groups where the host explicitly sent a stop signal (vs. just going offline).
/// DashboardRootView shows a "host stopped syncing" warning instead of a generic orphan banner.
@Published public private(set) var hostStoppedGroupIDs: Set<String> = []

// groupIDs this device currently holds a local copy of.
@Published public private(set) var localSyncedGroupIDs: Set<String> = []

/// The version the host peer is currently advertising for each joined group.
/// DashboardRootView compares this against the local tab revision; if local is newer
/// (push failed due to a network blip), it re-schedules the push automatically.
@Published public private(set) var peerVersionsForJoinedGroups: [String: SyncedTabVersion] = [:]

// Snapshots received via push or poll fallback that DashboardRootView has not yet applied.
@Published public private(set) var pendingSyncedSnapshots: [SyncedTabSnapshot] = []

// Diagnostics (helps confirm the service is actively running)
@Published public private(set) var lastBrowseUpdateAt: Date? = nil
@Published public private(set) var lastPollAt: Date? = nil
@Published public private(set) var pollCount: Int = 0

// When false, the service will keep browsing/advertising, but will not poll peers.
@Published public private(set) var pollingEnabled: Bool = true
@Published public private(set) var pollingOverrideDisabled: Bool = false

// Browse state diagnostics (helps on iOS when Local Network / Bonjour perms block discovery)
@Published public private(set) var browseStateText: String = ""
@Published public private(set) var lastBrowseErrorText: String = ""
public var debugLoggingEnabled: Bool = false
private var lastPollLogAtByKey: [String: Date] = [:]
private let pollLogIntervalSeconds: TimeInterval = 20

private var refreshTask: Task<Void, Never>?
private var isStarted: Bool = false
private var defaultsObserver: AnyCancellable?
private var settingsObserverTask: Task<Void, Never>?
private var hostingAllowedByEntitlement: Bool = true
private var discoveryAllowedByEntitlement: Bool = true
private func startPollingTasks() {
    // Avoid duplicate tasks
    pollTask?.cancel()
    pollTask = nil

    refreshTask?.cancel()
    refreshTask = nil

    // Periodic refresh: re-browse every ~10s in case the network stack misses updates.
    refreshTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
            if !self.pollingEnabled { break }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !self.pollingEnabled { break }
            await MainActor.run {
                self.browser?.cancel()
                self.browser = nil
                self.startBrowse()
            }
        }
    }

    // Poll peers periodically
    pollTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
            if !self.pollingEnabled || self.pollingOverrideDisabled { break }
            await self.pollPeersOnce()
            await self.pollSyncedPeersOnce()
            await self.pollLinkedVariablesOnce()
            await self.pollSyncedVariablesOnce()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

private func stopPollingTasks() {
    pollTask?.cancel()
    pollTask = nil

    refreshTask?.cancel()
    refreshTask = nil
}
/// Enable or disable LAN polling without tearing down browsing/advertising.
/// Useful for pausing background churn while in Graph view.
    public func setPollingOverrideDisabled(_ disabled: Bool) {
        if pollingOverrideDisabled == disabled { return }
        pollingOverrideDisabled = disabled

        if disabled {
            stopPollingTasks()
        } else if pollingEnabled {
            setPollingEnabled(true)
        }
    }

    public func setPollingEnabled(_ enabled: Bool) {
        if pollingEnabled == enabled { return }
        pollingEnabled = enabled

        if enabled {
            guard !pollingOverrideDisabled else { return }
            // Resume polling only if the service is already started.
            guard isStarted else { return }
            guard discoveryAllowedByEntitlement else {
                stopPollingTasks()
                return
            }

            // Ensure we are browsing AND that the current browse results get processed immediately.
            // If a browser already exists (from when polling was paused), restart it to re-emit results.
            if browser == nil {
                startBrowse()
            } else {
                browser?.cancel()
                browser = nil
                startBrowse()
            }

            // Start periodic polling tasks.
            startPollingTasks()

            // Kick a fast "catch-up" poll: now and again shortly after.
            // This helps the UI recover quickly from stale LAN tabs and synced tabs.
            Task { [weak self] in
                guard let self else { return }
                guard self.pollingEnabled, !self.pollingOverrideDisabled else { return }
                await self.pollPeersOnce()
                await self.pollSyncedPeersOnce()
                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
                guard self.pollingEnabled, !self.pollingOverrideDisabled else { return }
                await self.pollPeersOnce()
                await self.pollSyncedPeersOnce()
            }
        } else {
            stopPollingTasks()
        }
    }
    /// Guess a default reference canvas size if none is provided.
    private static var defaultReferenceCanvasSizeGuess: CGSize? {
        #if os(iOS)
        // `UIScreen.main` is deprecated (iOS 16+); resolve the screen through the
        // active window scene instead. This service has no SwiftUI container of its
        // own to measure (it's a plain network service, not a view), so a physical
        // screen size remains the best available guess when the caller didn't
        // supply an actual canvas size.
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            return scene.screen.bounds.size
        }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.screen.bounds.size
        }
        return nil
        #elseif os(macOS)
        // Best-effort: main screen pixel-space size. (Not perfect, but better than nil.)
        return NSScreen.main?.frame.size
        #else
        return nil
        #endif
    }

    /// Apply the settings blobs from an imported LAN bundle to THIS device.
        /// Writes only configuration (host/port/profile selections). Does not transfer OAuth tokens.
        public func applyImportedSettings(from bundle: LANSharedTabImportBundle) {
            let defaults = UserDefaults.standard

            // ProPresenter
            if let data = bundle.proPresenterSettingsJSON,
               let snap = try? JSONDecoder().decode(ProPresenterLANSettingsSnapshot.self, from: data) {

                defaults.set(snap.globalHost, forKey: "propresenter_host")
                defaults.set(snap.globalPort, forKey: "propresenter_port")
                if ProPresenterPasswordPolicy.shouldApplyImported(snap.globalPassword) { ProPresenterKeychainStore.shared.password = snap.globalPassword }
                defaults.set(snap.pollInterval, forKey: "propresenter_pollInterval")

                if let profilesJSON = snap.profilesJSON {
                    defaults.set(profilesJSON, forKey: "propresenter_profiles")
                }
                if let active = snap.activeProfileID {
                    defaults.set(active, forKey: "propresenter_activeProfileID")
                }
            }

            // Resolume
            if let data = bundle.resolumeSettingsJSON {
                defaults.set(data, forKey: "Relay.ResolumeProfilesStore.v1")
            }

            // Planning Center (optional for now)
            _ = bundle.planningCenterServiceJSON
            // Settings changed; refresh cached values.
            refreshSettingsCache(force: true)
        }

    public func importedSettingsHasChanges(from bundle: LANSharedTabImportBundle) -> Bool {
        let defaults = UserDefaults.standard

        if let data = bundle.proPresenterSettingsJSON,
           let imported = try? JSONDecoder().decode(ProPresenterLANSettingsSnapshot.self, from: data) {
            let current = ProPresenterLANSettingsSnapshot.loadFromUserDefaults(defaults)
            if current != imported {
                return true
            }
        }

        let currentResolumeSettings = defaults.data(forKey: "Relay.ResolumeProfilesStore.v1")
        if currentResolumeSettings != bundle.resolumeSettingsJSON {
            if currentResolumeSettings != nil || bundle.resolumeSettingsJSON != nil {
                return true
            }
        }

        return false
    }
    // MARK: - Settings (UserDefaults)

    private enum SettingsKeys {
        nonisolated static let sharingEnabled = "lan_sharing_enabled"
        nonisolated static let browserViewOnlyEnabled = "lan_browser_view_only_enabled"
        nonisolated static let browserListenPort = "lan_browser_listen_port"
        nonisolated static let allowUnpairedRead = "lan_allow_unpaired_read"
    }
    private struct LANSettingsSnapshot: Equatable {
        let sharingEnabled: Bool
        let browserViewOnlyEnabled: Bool
        let browserListenPort: UInt16
        let allowUnpairedRead: Bool
    }

    private nonisolated static let defaultBrowserListenPort: UInt16 = 38475

    private nonisolated static func normalizedBrowserListenPort(from defaults: UserDefaults) -> UInt16 {
        let rawValue = defaults.object(forKey: SettingsKeys.browserListenPort) as? Int ?? Int(defaultBrowserListenPort)
        let clampedValue = min(max(rawValue, 1024), 65_535)
        return UInt16(clampedValue)
    }

    private nonisolated static func readLANSettings(from defaults: UserDefaults) -> LANSettingsSnapshot {
        let sharing = defaults.object(forKey: SettingsKeys.sharingEnabled) as? Bool ?? true
        let browserOnly = defaults.object(forKey: SettingsKeys.browserViewOnlyEnabled) as? Bool ?? false
        let browserListenPort = normalizedBrowserListenPort(from: defaults)
        let allow = defaults.object(forKey: SettingsKeys.allowUnpairedRead) as? Bool ?? false

        return .init(
            sharingEnabled: sharing,
            browserViewOnlyEnabled: browserOnly,
            browserListenPort: browserListenPort,
            allowUnpairedRead: allow
        )
    }

    // Cache UserDefaults-backed settings to avoid reading CFPreferences in hot paths.
    private var cachedSharingEnabled: Bool = true
    private var cachedBrowserViewOnlyEnabled: Bool = false
    private var cachedBrowserListenPort: UInt16 = 38475
    private var cachedAllowUnpairedRead: Bool = false
    private var didLoadSettingsCache: Bool = false
    private var lastSettingsReadTime: TimeInterval = 0
    private let minSettingsReadInterval: TimeInterval = 1.0

    private func refreshSettingsCache(force: Bool = false) {
        let snap = Self.readLANSettings(from: UserDefaults.standard)
        cachedSharingEnabled = snap.sharingEnabled
        cachedBrowserViewOnlyEnabled = snap.browserViewOnlyEnabled
        cachedBrowserListenPort = snap.browserListenPort
        cachedAllowUnpairedRead = snap.allowUnpairedRead
        config.listenPort = snap.browserListenPort
        didLoadSettingsCache = true
    }

    private func ensureSettingsCacheLoaded() {
        if !didLoadSettingsCache {
            refreshSettingsCache(force: true)
        }
    }

    private var sharingEnabled: Bool {
        ensureSettingsCacheLoaded()
        return cachedSharingEnabled
    }

    private var fullRelaySharingEnabled: Bool {
        sharingEnabled && hostingAllowedByEntitlement
    }

    private var browserViewOnlyEnabled: Bool {
        ensureSettingsCacheLoaded()
        return cachedBrowserViewOnlyEnabled
    }

    private var browserViewerHostingEnabled: Bool {
        browserViewOnlyEnabled || fullRelaySharingEnabled
    }

    private var configuredListenPort: UInt16 {
        ensureSettingsCacheLoaded()
        return cachedBrowserListenPort
    }

    private var allowUnpairedRead: Bool {
        ensureSettingsCacheLoaded()
        return cachedAllowUnpairedRead
    }

    private var allowsUnauthenticatedViewOnlyAccess: Bool {
        allowUnpairedRead
    }

    public func setHostingAllowed(_ allowed: Bool) {
        if hostingAllowedByEntitlement == allowed { return }
        hostingAllowedByEntitlement = allowed
        guard isStarted else { return }
        updateServerState()
    }

    public func setDiscoveryAllowed(_ allowed: Bool) {
        if discoveryAllowedByEntitlement == allowed { return }
        discoveryAllowedByEntitlement = allowed
        guard isStarted else { return }
        updateDiscoveryState()
    }

    public func browserBaseURL() -> URL? {
        refreshSettingsCache(force: true)
        guard browserViewOnlyEnabled, let port = activeListenPort, let host = currentBrowserHost() else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/"
        return components.url
    }

    public func browserViewerURL(for shareId: String) -> URL? {
        guard let base = browserBaseURL() else { return nil }
        return base.appending(path: "view").appending(path: shareId)
    }

    public func setBrowserViewShareId(_ shareId: String?) {
        activeBrowserViewShareId = shareId
    }

    private func currentIPv4(preferWiFi: Bool = true) -> String? {
        #if canImport(Darwin)
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var wifiCandidate: String?
        var firstPrivate: String?
        var firstUsable: String?

        var pointer = first
        while true {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, Int32(address.pointee.sa_family) == AF_INET else {
                if let next = interface.ifa_next {
                    pointer = next
                } else {
                    break
                }
                continue
            }

            guard let interfaceName = interface.ifa_name else {
                if let next = interface.ifa_next {
                    pointer = next
                } else {
                    break
                }
                continue
            }

            let name = String(cString: interfaceName)
            let flags = Int32(interface.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isRunning = (flags & IFF_UP) != 0

            guard isRunning, !isLoopback else {
                if let next = interface.ifa_next {
                    pointer = next
                } else {
                    break
                }
                continue
            }

            var addressIn = unsafeBitCast(address.pointee, to: sockaddr_in.self)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let addressPointer = withUnsafePointer(to: &addressIn.sin_addr) {
                $0.withMemoryRebound(to: in_addr.self, capacity: 1) { $0 }
            }
            inet_ntop(AF_INET, addressPointer, &buffer, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buffer)

            if firstUsable == nil {
                firstUsable = ip
            }

            if isPrivateIPv4(ip) {
                if preferWiFi, (name == "en0" || name == "en1") {
                    wifiCandidate = ip
                }
                if firstPrivate == nil {
                    firstPrivate = ip
                }
            }

            if let next = interface.ifa_next {
                pointer = next
            } else {
                break
            }
        }

        return wifiCandidate ?? firstPrivate ?? firstUsable
        #else
        return nil
        #endif
    }

    private func currentBrowserHost() -> String? {
        currentIPv4()
    }

    private func isPrivateIPv4(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let components = ip.split(separator: ".")
            if components.count >= 2, let second = Int(components[1]), (16...31).contains(second) {
                return true
            }
        }
        if ip.hasPrefix("192.168.") { return true }
        return false
    }

public struct Peer: Identifiable, Hashable {
    public var id: String { endpointKey }
    public let endpointKey: String
    public let deviceId: String
    public let deviceName: String?
    public let deviceKind: LANDeviceKind?
    public let requiresPairing: Bool
    public let host: NWEndpoint.Host
    public let port: NWEndpoint.Port
    public let lastSeen: Date

    /// True when a persisted peer reference (e.g. a Notify node's target) points at this peer.
    /// Accepts the display name too: builds that browsed without TXT records stored the
    /// computer's name as its deviceId, and those saved targets must keep resolving.
    public func matchesSavedTarget(_ savedID: String) -> Bool {
        guard !savedID.isEmpty else { return false }
        return deviceId == savedID || endpointKey == savedID || deviceName == savedID
    }
}

// MARK: Config

public struct Config {
    public var serviceType: String = "_relay._tcp"
    public var serviceDomain: String = "local."
    public var protocolVersion: String = "1"
    public var pollInterval: TimeInterval = 1.0
    public var peerStaleSeconds: TimeInterval = 20.0
    public var listenPort: UInt16 = 0 // 0 = choose automatically
    public var maxPeers: Int = 32
    public init() {}
}

private var config: Config

// MARK: Identity

private let deviceId: String
private let deviceName: String

// MARK: Server

private var listener: NWListener?
private var listenPort: NWEndpoint.Port?
private var listenerConsecutiveFailures = 0
private var listenerRestartTask: Task<Void, Never>?

// Tabs this device is sharing (manifests + payload).
// DashboardRootView (or model) calls setSharedTabs(...) to update these.
private var localManifests: [LANSharedTabManifest] = []
private var localPayloadsByShareId: [String: LANSharedTabPayload] = [:]
private var localRenderImagesByShareId: [String: Data] = [:]

// Synced Tabs: manifests + snapshots this device is sharing (via setSyncedTabs).
// Published so the LAN settings UI can show which tabs this device is hosting.
@Published public private(set) var hostedSyncedManifests: [SyncedTabManifest] = []
private var localSyncedManifests: [SyncedTabManifest] = [] {
    didSet { hostedSyncedManifests = localSyncedManifests.filter { $0.deviceID == deviceId } }
}
private var localSyncedSnapshotsByGroupID: [String: SyncedTabSnapshot] = [:]

// Synced Tabs: tabs this device has joined as a subscriber (via setJoinedSyncedTabs).
// Published so the LAN settings UI can show which tabs this device is currently subscribed to —
// distinct from hostedSyncedManifests (tabs this device owns) and syncedRemoteManifests
// (tabs advertised by peers that are available to join but not yet joined).
@Published public private(set) var joinedSyncedManifests: [SyncedTabManifest] = []

public func setJoinedSyncedTabs(_ manifests: [SyncedTabManifest]) {
    joinedSyncedManifests = manifests
}

// Synced Tabs: cache of last-polled manifests per peer, for discovery.
private var peerSyncedManifests: [String: [SyncedTabManifest]] = [:]

private var consecutiveGroupMisses: [String: Int] = [:]

// Groups resumed from an autosaved document at launch, not yet confirmed live by a poll.
// See markGroupAsRestoredJoined — these use a much shorter orphan-detection miss threshold.
// Published so the tab pill can show a "stale, reconnecting" indicator until cleared.
@Published public private(set) var unverifiedSyncGroupIDs: Set<String> = []

// Synced Tabs: per-peer presence (endpointKey → payload). Updated on every poll cycle.
@Published public private(set) var peerPresence: [String: SyncedPresencePayload] = [:]

// Synced Tabs: push-based presence from joiner devices (deviceID → payload, expires after TTL).
@Published public private(set) var pushedPresence: [String: SyncedPresencePayload] = [:]
private var pushedPresenceExpiryTasks: [String: Task<Void, Never>] = [:]

/// groupID -> deviceIDs currently polling this host with that group in their `joined` list on
/// GET /syncedTabs — i.e. genuine live subscribers, not just paired devices. Populated by
/// route()'s /syncedTabs handler; entries expire automatically via liveSubscriberExpiryTasks if
/// a peer stops polling (goes offline, disables the peer, etc.).
@Published public private(set) var liveSubscribersByGroupID: [String: Set<String>] = [:]
private var liveSubscriberExpiryTasks: [String: Task<Void, Never>] = [:]

public func liveSubscriberDeviceIDs(for groupID: String) -> Set<String> {
    liveSubscribersByGroupID[groupID] ?? []
}

/// Records that `deviceId` is currently subscribed to `groupID`, refreshing its expiry timer.
/// Only called for callers that already passed isAuthorized() — see route()'s /syncedTabs
/// handler — so an unpaired device can't claim subscriber status just by including a `joined`
/// query param.
private func recordLiveSubscriber(deviceId: String, groupID: String) {
    let key = "\(groupID)|\(deviceId)"
    liveSubscriberExpiryTasks[key]?.cancel()
    liveSubscribersByGroupID[groupID, default: []].insert(deviceId)
    liveSubscriberExpiryTasks[key] = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard !Task.isCancelled else { return }
        guard let self else { return }
        self.liveSubscribersByGroupID[groupID]?.remove(deviceId)
        if self.liveSubscribersByGroupID[groupID]?.isEmpty == true {
            self.liveSubscribersByGroupID.removeValue(forKey: groupID)
        }
        self.liveSubscriberExpiryTasks.removeValue(forKey: key)
    }
}

// What tile this device is currently editing and which tiles are selected (set via setLocalPresence).
private var localPresenceTileID: String? = nil
private var localPresenceGroupID: String? = nil
private var localPresenceSelectedTileIDs: [String] = []

// Synced Tabs: which peer endpoint currently "owns" a given groupID (fetch routing for join).
private var syncedGroupOwnerEndpointKey: [String: String] = [:]

// File proxy registry: hash → local file path.
private var localFileRegistry: [String: String] = [:]
private var localPersonImageFolderPath: String = ""

// MARK: Discovery

private var browser: NWBrowser?
private var pollTask: Task<Void, Never>?

// Dismissed remote shareId -> hash (so it reappears if updated)
private var dismissed: [String: String] = [:]

// Cache of last manifests per peer to reduce churn
private var peerManifests: [String: [LANSharedTabManifest]] = [:]

// requestId -> outcome, for GET /pair/status to answer against. Entries older than
// 60s are pruned opportunistically on each write (see recordPairingOutcome).
private var pairingOutcomesByRequestId: [String: (outcome: PairingOutcome, recordedAt: Date)] = [:]

// requestId -> denial/timeout cooldown expiry, keyed by deviceId, so a denied device
// can't immediately re-trigger the host's approval sheet.
private var pairingCooldownByDeviceId: [String: Date] = [:]

let pairingSecretStore: PairingSecretStoring
private var seenNonces: [String: Date] = [:]
private var pairingHostKeysByRequestId: [String: (key: LANPairingKeyAgreement.KeyPair, createdAt: Date)] = [:]

// Track which peer currently "owns" a shareId (used for import routing)
private var shareIdOwnerEndpointKey: [String: String] = [:]

// Track which shareIds are actively being requested for renders.
private var renderRequestLastSeenByShareId: [String: Date] = [:]

private struct ActiveBrowserViewerNotification {
    let id: String
    let title: String
    let message: String
    let durationSeconds: Double
    let expiresAt: Date
}

// MARK: - Synced Tabs (identity accessors)

/// This device's stable per-install identifier (matches `SyncedTabVersion.editedByDeviceID`
/// when this device makes a local edit).
public var localDeviceID: String { deviceId }

/// This device's display name (matches `SyncedTabManifest.deviceName`).
public var localDeviceName: String { deviceName }

public init(config: Config? = nil, pairingSecretStore: PairingSecretStoring = KeychainPairingSecretStore()) {
    self.pairingSecretStore = pairingSecretStore
    self.config = config ?? Config()

    // Stable per-install id (store in UserDefaults; you can swap to Keychain later)
    let defaults = UserDefaults.standard
    if let existing = defaults.string(forKey: "prodlink.deviceId") {
        deviceId = existing
    } else {
        let new = UUID().uuidString
        defaults.set(new, forKey: "prodlink.deviceId")
        deviceId = new
    }

    #if os(macOS)
    deviceName = Host.current().localizedName ?? "Mac"
    #else
    deviceName = UIDevice.current.name
    #endif

    if let disabled = defaults.array(forKey: "lan.disabledPeers") as? [String] {
        disabledPeerEndpointKeys = Set(disabled)
    }
    // Watch for Settings changes so toggling LAN sharing takes effect immediately.
    defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
        .debounce(for: .milliseconds(750), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }

            // Coalesce bursts of defaults writes (window state, etc.)
            self.settingsObserverTask?.cancel()
            self.settingsObserverTask = Task { [weak self] in
                guard let self else { return }

                let now = CFAbsoluteTimeGetCurrent()
                let elapsed = now - self.lastSettingsReadTime
                if elapsed < self.minSettingsReadInterval {
                    let delay = self.minSettingsReadInterval - elapsed
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                // Read UserDefaults off-main to avoid CFPreferences work on UI thread
                let newSnap = await Task.detached(priority: .utility) {
                    Self.readLANSettings(from: UserDefaults.standard)
                }.value

                await MainActor.run {
                    let oldSnap = LANSettingsSnapshot(
                        sharingEnabled: self.cachedSharingEnabled,
                        browserViewOnlyEnabled: self.cachedBrowserViewOnlyEnabled,
                        browserListenPort: self.cachedBrowserListenPort,
                        allowUnpairedRead: self.cachedAllowUnpairedRead
                    )

                    guard newSnap != oldSnap else { return }

                    self.cachedSharingEnabled = newSnap.sharingEnabled
                    self.cachedBrowserViewOnlyEnabled = newSnap.browserViewOnlyEnabled
                    self.cachedBrowserListenPort = newSnap.browserListenPort
                    self.cachedAllowUnpairedRead = newSnap.allowUnpairedRead
                    self.config.listenPort = newSnap.browserListenPort
                    self.didLoadSettingsCache = true
                    self.lastSettingsReadTime = CFAbsoluteTimeGetCurrent()

                    if !self.isStarted {
                        self.start()
                        return
                    }

                    if newSnap.browserListenPort != oldSnap.browserListenPort {
                        self.restartServer()
                    } else {
                        self.updateServerState()
                    }
                    self.updateDiscoveryState()
                }
            }
        }
}

// MARK: Public lifecycle

public func start() {
    // Idempotent start: don't tear down and clear peers/tabs every time.
    if isStarted { return }
    isStarted = true
    // Load cached settings once at startup (prevents CFPreferences churn).
    refreshSettingsCache(force: true)

    print("🟦 LAN start (pairing=on polling=\(pollingEnabled ? "on" : "off") relay=\(fullRelaySharingEnabled ? "on" : "off") browser=\(browserViewerHostingEnabled ? "on" : "off"))")
    updateServerState()
    updateDiscoveryState()
}

public func stop() {
    settingsObserverTask?.cancel()
    settingsObserverTask = nil
    isStarted = false
    stopPollingTasks()

    browser?.cancel()
    browser = nil

    listenerRestartTask?.cancel()
    listenerRestartTask = nil
    listener?.cancel()
    listener = nil
    listenPort = nil
    activeListenPort = nil

    clearDiscoveredState()
    peerManifests = [:]
    shareIdOwnerEndpointKey = [:]
    print("🟦 LAN stopped")
}

// MARK: Sharing API (called by your dashboard model)

/// Provide the tabs you want to share from THIS device.
/// - Important: `exportedTabJSON` should be your encoded DashboardTab.
public func setSharedTabs(
    _ tabs: [(shareId: String, tabName: String, exportedTabJSON: Data, tileCount: Int, moduleTypes: [String], schemaVersion: Int)],
    canvasSize: CGSize? = nil,
    referenceCanvasSizes: [String: CGSize]? = nil
) {
    refreshSettingsCache(force: true)
    guard browserViewerHostingEnabled else {
        localManifests = []
        localPayloadsByShareId = [:]
        localTabs = []
#if DEBUG
        print("🟦 LAN share skipped (browser hosting disabled)")
#endif
        return
    }

    let now = Date().timeIntervalSince1970

    let effectiveCanvasSize = canvasSize ?? Self.defaultReferenceCanvasSizeGuess

#if DEBUG
    if let canvasSize {
        print("🟦 LAN share: source canvasSize=\(canvasSize.width)x\(canvasSize.height)")
    } else if let effectiveCanvasSize {
        print("🟦 LAN share: source canvasSize=nil; using fallback=\(effectiveCanvasSize.width)x\(effectiveCanvasSize.height)")
    } else {
        print("🟦 LAN share: source canvasSize=nil; no fallback available")
    }
#endif

    var manifests: [LANSharedTabManifest] = []
    var payloads: [String: LANSharedTabPayload] = [:]

    for t in tabs {
        let hash = Self.sha256Hex(t.exportedTabJSON)

        // Prefer the tab’s stored reference canvas size (prevents clipping on mirrors).
        // Priority: explicit per-tab map override -> extracted from exported JSON -> canvasSize -> fallback guess.
        let extractedRefSize = Self.extractReferenceCanvasSize(from: t.exportedTabJSON)
        let tabCanvasSize = referenceCanvasSizes?[t.shareId] ?? extractedRefSize ?? effectiveCanvasSize
        let refW = tabCanvasSize.map { Double($0.width) }
        let refH = tabCanvasSize.map { Double($0.height) }

        let manifest = LANSharedTabManifest(
            shareId: t.shareId,
            deviceId: deviceId,
            deviceName: deviceName,
            deviceKind: Self.currentDeviceKind,
            referenceCanvasWidth: refW,
            referenceCanvasHeight: refH,
            updatedAt: now,
            tabName: t.tabName,
            summary: LANSharedTabManifest.Summary(tileCount: t.tileCount, moduleTypes: t.moduleTypes),
            hash: hash
        )

#if DEBUG
        let src: String
        if referenceCanvasSizes?[t.shareId] != nil {
            src = "tabRef"
        } else if extractedRefSize != nil {
            src = "jsonRef"
        } else if canvasSize != nil {
            src = "canvasSize"
        } else {
            src = "fallback"
        }
        print("🟦 LAN manifest built: device=\(deviceName) tab=\(t.tabName) shareId=\(t.shareId) ref=\(manifest.referenceCanvasWidth ?? -1)x\(manifest.referenceCanvasHeight ?? -1) src=\(src)")
#endif

        let payload = LANSharedTabPayload(
            shareId: t.shareId,
            tabName: t.tabName,
            exportedTabJSON: t.exportedTabJSON,
            schemaVersion: t.schemaVersion,
            hash: hash
        )

        manifests.append(manifest)
        payloads[t.shareId] = payload
    }

    localManifests = manifests
    localPayloadsByShareId = payloads
    localTabs = manifests
    // No need to push; peers poll us. (Later: broadcast “changed” via WS)
}

/// Provide the synced tabs this device currently holds local copies of.
/// Called by DashboardRootView whenever `tabs` changes, debounced.
public func setSyncedTabs(
    _ tabs: [(groupID: String, tabName: String, exportedTabJSON: Data, version: SyncedTabVersion, lastEditedByDeviceName: String, tileCount: Int, moduleTypes: [String], schemaVersion: Int)]
) {
    refreshSettingsCache(force: true)
    guard fullRelaySharingEnabled else {
        localSyncedManifests = []
        localSyncedSnapshotsByGroupID = [:]
        localSyncedGroupIDs = []
        return
    }

    var manifests: [SyncedTabManifest] = []
    var snapshots: [String: SyncedTabSnapshot] = [:]
    var groupIDs: Set<String> = []

    for t in tabs {
        let hash = Self.sha256Hex(t.exportedTabJSON)
        manifests.append(SyncedTabManifest(
            groupID: t.groupID,
            tabName: t.tabName,
            deviceID: deviceId,
            deviceName: deviceName,
            version: t.version,
            summary: SyncedTabManifest.Summary(tileCount: t.tileCount, moduleTypes: t.moduleTypes)
        ))
        snapshots[t.groupID] = SyncedTabSnapshot(
            groupID: t.groupID,
            tabName: t.tabName,
            exportedTabJSON: t.exportedTabJSON,
            schemaVersion: t.schemaVersion,
            version: t.version,
            lastEditedByDeviceName: t.lastEditedByDeviceName,
            hash: hash
        )
        groupIDs.insert(t.groupID)
    }

    localSyncedManifests = manifests
    localSyncedSnapshotsByGroupID = snapshots
    localSyncedGroupIDs = groupIDs
    rebuildSyncedRemoteManifests()
}

/// Updates which tile this device is editing and which tiles are currently selected.
/// Call whenever editingTileID, selectedTileIDs, or the active tab changes.
/// Pass `nil`/empty when inspector closes or tab switches.
public func setLocalPresence(tileID: UUID?, groupID: String?, selectedTileIDs: [UUID] = []) {
    localPresenceTileID = tileID?.uuidString
    localPresenceGroupID = groupID
    localPresenceSelectedTileIDs = selectedTileIDs.map { $0.uuidString }
}

/// Records that this device joined a tab from a remote host.
/// Call this from joinSyncedTab (not from makeSyncedTab).
public func markGroupAsJoined(_ groupID: String) {
    joinedSyncGroupIDs.insert(groupID)
    orphanedSyncGroupIDs.remove(groupID)
    consecutiveGroupMisses[groupID] = 0
    unverifiedSyncGroupIDs.remove(groupID)
}

/// Records that this device is resuming a previously-joined group after an app restart, whose
/// last-known content was loaded from an autosaved document rather than a live fetch. Until the
/// next poll confirms the host is still advertising this group, it's treated as "unverified" and
/// orphaned much faster than a normal live connection — so a host that's genuinely gone (app was
/// closed, quit, or crashed while this device was linked) doesn't leave stale content displayed
/// under a "still synced" icon for a full ~8s miss window before the user finds out.
public func markGroupAsRestoredJoined(_ groupID: String) {
    joinedSyncGroupIDs.insert(groupID)
    orphanedSyncGroupIDs.remove(groupID)
    consecutiveGroupMisses[groupID] = 0
    unverifiedSyncGroupIDs.insert(groupID)
}

/// Clears only the orphan flag for a group, keeping the join state intact so the subscriber
/// can attempt to reconnect without fully leaving the sync group.
public func clearOrphanState(for groupID: String) {
    orphanedSyncGroupIDs.remove(groupID)
    consecutiveGroupMisses[groupID] = 0
}

/// Clears orphan + join state for a group (call when the tab is removed or stops syncing locally).
public func clearGroupJoinState(_ groupID: String) {
    SyncedTabVariableStore.shared.clear(groupID: groupID)
    joinedSyncGroupIDs.remove(groupID)
    orphanedSyncGroupIDs.remove(groupID)
    reconnectedSyncGroupIDs.remove(groupID)
    hostStoppedGroupIDs.remove(groupID)
    consecutiveGroupMisses.removeValue(forKey: groupID)
    unverifiedSyncGroupIDs.remove(groupID)
    // Remove stale manifest entries so the group doesn't re-appear in discovery
    // until the host genuinely re-advertises it on the next poll.
    for key in peerSyncedManifests.keys {
        peerSyncedManifests[key]?.removeAll { $0.groupID == groupID }
    }
    rebuildSyncedRemoteManifests()
}

/// Called by DashboardRootView after it has handled the reconnect for a group.
public func clearReconnectSignal(for groupID: String) {
    reconnectedSyncGroupIDs.remove(groupID)
}

/// Removes and returns all pending incoming synced-tab snapshots for the consumer to apply.
public func consumePendingSyncedSnapshots() -> [SyncedTabSnapshot] {
    let pending = pendingSyncedSnapshots
    pendingSyncedSnapshots = []
    return pending
}

/// Computes the content hash, builds a `SyncedTabSnapshot`, stores it locally (so this
/// device serves it via `GET /syncedTab/<groupID>`), and pushes it to every known peer.
/// Called debounced (~600ms after the last local edit) by DashboardRootView.
public func pushSyncedSnapshot(
    groupID: String,
    tabName: String,
    exportedTabJSON: Data,
    version: SyncedTabVersion,
    lastEditedByDeviceName: String,
    schemaVersion: Int = 1,
    presenceTileID: String? = nil,
    presenceGroupID: String? = nil
) async {
    refreshSettingsCache(force: true)
    // Joined (subscriber) groups can push edits back to the host even when local sharing is
    // disabled — pushing is an outgoing HTTP call, not a hosting operation.
    let isJoined = joinedSyncGroupIDs.contains(groupID)
    guard fullRelaySharingEnabled || isJoined else {
        print("🟢 pushSyncedSnapshot(\(groupID)): SKIPPED — sharing disabled and not a joined group")
        return
    }
    print("🟢 pushSyncedSnapshot(\(groupID)): attempting push to \(peers.count) peer(s), rev\(version.revision)")

    let hash = Self.sha256Hex(exportedTabJSON)
    let snapshot = SyncedTabSnapshot(
        groupID: groupID,
        tabName: tabName,
        exportedTabJSON: exportedTabJSON,
        schemaVersion: schemaVersion,
        version: version,
        lastEditedByDeviceName: lastEditedByDeviceName,
        hash: hash
    )

    localSyncedSnapshotsByGroupID[groupID] = snapshot
    if let idx = localSyncedManifests.firstIndex(where: { $0.groupID == groupID }) {
        localSyncedManifests[idx] = SyncedTabManifest(
            groupID: groupID,
            tabName: tabName,
            deviceID: deviceId,
            deviceName: deviceName,
            version: version,
            summary: localSyncedManifests[idx].summary
        )
    }

    guard let body = try? JSONEncoder().encode(snapshot) else { return }

    for p in peers {
        if disabledPeerEndpointKeys.contains(p.endpointKey) {
            print("🟢 pushSyncedSnapshot(\(groupID)): SKIPPED peer \(p.endpointKey) — disabled")
            continue
        }
        var pushPath = "/syncedTab/push"
        if let tid = presenceTileID, let gid = presenceGroupID {
            pushPath += "?presenceTileID=\(tid)&presenceGroupID=\(gid)"
        }
        guard let url = makePeerURL(host: p.host, port: p.port, path: pushPath) else { continue }
        let req = makePeerRequest(url: url, method: "POST", body: body, contentType: "application/json")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let bodyText = String(decoding: data, as: UTF8.self)
            print("🟢 pushSyncedSnapshot(\(groupID)) → \(p.endpointKey): status=\(status) body=\(bodyText)")
        } catch {
            print("🟢 pushSyncedSnapshot(\(groupID)) → \(p.endpointKey): ERROR \(error)")
        }
    }
}

/// Pushes a lightweight presence payload to all known peers via `POST /syncedPresence`.
/// Used by joiner devices (no Bonjour server) to advertise their selection/editing state.
public func pushPresence(_ payload: SyncedPresencePayload) async {
    refreshSettingsCache(force: true)
    let hasJoinedGroups = !joinedSyncGroupIDs.isEmpty
    guard fullRelaySharingEnabled || hasJoinedGroups else { return }
    guard let body = try? JSONEncoder().encode(payload) else { return }
    for p in peers {
        if disabledPeerEndpointKeys.contains(p.endpointKey) { continue }
        guard let url = makePeerURL(host: p.host, port: p.port, path: "/syncedPresence") else { continue }
        let req = makePeerRequest(url: url, method: "POST", body: body, contentType: "application/json")
        _ = try? await URLSession.shared.data(for: req)
    }
}

/// Pushes a stop signal to all known peers, notifying them that `groupID` is no longer syncing.
/// Call this before removing the tab locally in stopSyncingTab.
public func registerLocalFile(at path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    localFileRegistry[hash] = path
    return hash
}

public func setPersonImageFolderPath(_ path: String) {
    localPersonImageFolderPath = path
}

public func clearFileRegistry() {
    localFileRegistry.removeAll()
}

public func peerBaseURL(for groupID: String) -> URL? {
    guard let endpointKey = syncedGroupOwnerEndpointKey[groupID],
          let peer = peers.first(where: { $0.endpointKey == endpointKey })
    else { return nil }
    return makePeerURL(host: peer.host, port: peer.port, path: "")
}

public func pushSyncStop(groupID: String) async {
    refreshSettingsCache(force: true)
    guard fullRelaySharingEnabled else { return }
    let payload = SyncedTabStopPayload(groupID: groupID, deviceID: deviceId, deviceName: deviceName)
    guard let body = try? JSONEncoder().encode(payload) else { return }
    for p in peers {
        if disabledPeerEndpointKeys.contains(p.endpointKey) { continue }
        guard let url = makePeerURL(host: p.host, port: p.port, path: "/syncedTab/stop") else { continue }
        let req = makePeerRequest(url: url, method: "POST", body: body, contentType: "application/json")
        _ = try? await URLSession.shared.data(for: req)
    }
}

// Serializes concurrent pairing handshakes. activePairingRequest is a single-slot
// published property (by design — the joiner-side UI shows one waiting overlay at
// a time), so two requestPairing calls running concurrently (e.g. two orphaned
// synced tabs reconnecting to two different untrusted peers around the same time)
// would otherwise overwrite each other's published state and silently drop one
// caller's activePairingRequest to nil while the other is still in flight. This
// queue makes concurrent callers wait their turn instead of racing.
private var isPairingHandshakeInFlight = false
private var pairingHandshakeWaiters: [CheckedContinuation<Void, Never>] = []

private func acquirePairingHandshakeSlot() async {
    if !isPairingHandshakeInFlight {
        isPairingHandshakeInFlight = true
        return
    }
    await withCheckedContinuation { continuation in
        pairingHandshakeWaiters.append(continuation)
    }
}

private func releasePairingHandshakeSlot() {
    if pairingHandshakeWaiters.isEmpty {
        isPairingHandshakeInFlight = false
    } else {
        pairingHandshakeWaiters.removeFirst().resume()
    }
}

/// Sends a pairing request to `peer` and polls for the outcome (approved/denied),
/// up to a 30s timeout. Publishes `activePairingRequest` for the duration so the
/// joiner-side waiting UI can observe it. Persists trust locally on approval —
/// pairing is symmetric: both sides record trust for each other's deviceId.
///
/// Key agreement: the joiner sends an ephemeral X25519 `publicKey`; the host replies with its
/// own `hostPublicKey`. Both derive the same 32-byte secret (HKDF, salted with the requestId)
/// and the same 8-digit confirmation code, which both people compare before the host taps
/// Approve. The host stores the secret on approve; the joiner stores it when polling returns
/// `approved`. Hosts without `hostPublicKey` are legacy: no secret is stored.
///
/// Only one handshake runs at a time (see acquirePairingHandshakeSlot) — this
/// class is @MainActor-isolated throughout, so the slot bookkeeping itself needs
/// no additional locking.
private func requestPairing(with peer: Peer, reason: String) async -> Bool {
    await acquirePairingHandshakeSlot()
    defer { releasePairingHandshakeSlot() }
    lastPairingFailureMessage = nil

    guard let requestURL = makePeerURL(host: peer.host, port: peer.port, path: "/pair/request") else {
        lastPairingFailureMessage = "Could not build a connection to \(peer.deviceName ?? "the other computer"). Try rediscovering it on the same network."
        return false
    }
    let requestId = UUID().uuidString
    let keyPair = LANPairingKeyAgreement.makeKeyPair()
    let payload = PairingRequestPayload(
        requestId: requestId,
        deviceId: deviceId,
        deviceName: deviceName,
        deviceKind: Self.currentDeviceKind,
        reason: reason,
        publicKey: keyPair.publicBase64
    )
    guard let body = try? JSONEncoder().encode(payload) else { return false }

    activePairingRequest = OutgoingPairingRequest(peerDeviceName: peer.deviceName ?? "device", reason: reason, shortAuthString: nil)
    defer { activePairingRequest = nil }

    let req = makePeerRequest(url: requestURL, method: "POST", body: body, contentType: "application/json")
    let response: URLResponse
    let requestData: Data
    do {
        let (data, receivedResponse) = try await URLSession.shared.data(for: req)
        response = receivedResponse
        requestData = data
    } catch {
        guard !Task.isCancelled else { return false }
        lastPairingFailureMessage = "Could not reach \(peer.deviceName ?? "the other computer"). Check that Relay is open and both computers are on the same network."
        return false
    }
    let statusCode = (response as? HTTPURLResponse)?.statusCode
    if statusCode == 404,
       let legacyCode = UserDefaults.standard.string(forKey: "lan_pairing_code"),
       !legacyCode.isEmpty,
       let legacyProbeURL = makePeerURL(host: peer.host, port: peer.port, path: "/syncedTabs") {
        // Older releases predate /pair/request and authorize /syncedTabs with the shared
        // pairing code. A successful authenticated manifest read is the compatibility
        // handshake; newer servers still require modern per-device trust for gated routes.
        let probe = makePeerRequest(url: legacyProbeURL)
        if let (_, probeResponse) = try? await URLSession.shared.data(for: probe),
           (probeResponse as? HTTPURLResponse)?.statusCode == 200 {
            pairedDevices = DevicePairingStore.setEnabled(
                true,
                deviceId: peer.deviceId,
                deviceName: peer.deviceName ?? "Device",
                deviceKind: peer.deviceKind,
                in: pairedDevices
            )
            DevicePairingStore.save(pairedDevices)
            return true
        }
    }
    guard statusCode == 202 else {
        let name = peer.deviceName ?? "The other computer"
        if statusCode == 404 {
            lastPairingFailureMessage = "\(name) is not accepting Relay connections. Make sure Sync & Mirror is enabled and Relay is up to date."
        } else {
            lastPairingFailureMessage = "Could not connect to \(name) (response \(statusCode.map(String.init) ?? "unknown")). Check its Sync & Mirror settings and try again."
        }
        return false
    }

    guard let statusURL = makePeerURL(host: peer.host, port: peer.port, path: "/pair/status?requestId=\(requestId)") else {
        lastPairingFailureMessage = "The connection to \(peer.deviceName ?? "the other computer") could not be checked. Try again."
        return false
    }

    // Host's ephemeral key (absent from older hosts): derive the shared secret and show the
    // confirmation code so both people can verify they are talking to each other.
    var pairingSecret: Data? = nil
    let hostPublicKey = (try? JSONSerialization.jsonObject(with: requestData) as? [String: Any])?["hostPublicKey"] as? String
    if let hostPublicKey,
       let secret = try? LANPairingKeyAgreement.deriveSecret(privateKey: keyPair.privateKey, peerPublicBase64: hostPublicKey, requestId: requestId) {
        pairingSecret = secret
        activePairingRequest = OutgoingPairingRequest(
            peerDeviceName: peer.deviceName ?? "device",
            reason: reason,
            shortAuthString: LANPairingKeyAgreement.shortAuthString(
                joinerPublicBase64: keyPair.publicBase64, hostPublicBase64: hostPublicKey, secret: secret))
    }

    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
        if Task.isCancelled { return false }

        if let (data, resp) = try? await URLSession.shared.data(for: URLRequest(url: statusURL)),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let decoded = try? JSONDecoder().decode([String: String].self, from: data),
           let status = decoded["status"] {
            if status == "approved" {
                pairedDevices = DevicePairingStore.setEnabled(
                    true,
                    deviceId: peer.deviceId,
                    deviceName: peer.deviceName ?? "Device",
                    deviceKind: peer.deviceKind,
                    in: pairedDevices
                )
                DevicePairingStore.save(pairedDevices)
                if let pairingSecret { pairingSecretStore.setSecret(pairingSecret, for: peer.deviceId) }
                return true
            }
            if status == "denied" {
                lastPairingFailureMessage = "The connection request was declined or blocked on \(peer.deviceName ?? "the other computer")."
                return false
            }
        }

        if Task.isCancelled { return false }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
    guard !Task.isCancelled else { return false }
    lastPairingFailureMessage = "No approval response came back from \(peer.deviceName ?? "the other computer"). Keep Relay open there and try again."
    return false
}

/// Returns true if `peer` is already trusted, or becomes trusted after a live
/// pairing request. Call before any gated request to a peer.
private func ensurePaired(with peer: Peer, reason: String) async -> Bool {
    if DevicePairingStore.isAuthorized(deviceId: peer.deviceId, in: pairedDevices) {
        return true
    }
    return await requestPairing(with: peer, reason: reason)
}

/// Fetches the full snapshot for `groupID` from a peer — used for "Join" and for fallback
/// resync when polling discovers a newer manifest for a group we already hold.
public func fetchSyncedTabSnapshot(groupID: String) async -> SyncedTabSnapshot? {
    var candidates = peers
    if let ownerKey = syncedGroupOwnerEndpointKey[groupID],
       let owner = peers.first(where: { $0.endpointKey == ownerKey }) {
        candidates.removeAll { $0.endpointKey == ownerKey }
        candidates.insert(owner, at: 0)
    }

    let tabName = syncedRemoteManifests.first(where: { $0.groupID == groupID })?.tabName
        ?? hostedSyncedManifests.first(where: { $0.groupID == groupID })?.tabName
    let reason = tabName.map { "join \"\($0)\"" } ?? "join a Synced Tab"

    for p in candidates {
        if disabledPeerEndpointKeys.contains(p.endpointKey) { continue }
        guard await ensurePaired(with: p, reason: reason) else { continue }
        guard let url = makePeerURL(host: p.host, port: p.port, path: "/syncedTab/\(groupID)") else { continue }
        let req = makePeerRequest(url: url)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            if let snapshot = try? JSONDecoder().decode(SyncedTabSnapshot.self, from: data) {
                return snapshot
            }
        } catch {
            continue
        }
    }
    return nil
}

/// Provide rendered snapshot images for shared tabs (JPEG/PNG bytes).
public func setSharedTabRenders(_ renders: [String: Data]) {
    refreshSettingsCache(force: true)
    localRenderImagesByShareId = browserViewerHostingEnabled ? renders : [:]
}

/// Update a single shared tab render without rebuilding the whole dictionary.
public func setSharedTabRender(shareId: String, data: Data?) {
    refreshSettingsCache(force: true)
    guard browserViewerHostingEnabled else {
        localRenderImagesByShareId.removeAll()
        return
    }
    if let data {
        localRenderImagesByShareId[shareId] = data
    } else {
        localRenderImagesByShareId.removeValue(forKey: shareId)
    }
}

// MARK: Dismiss / Undismiss

public func dismissRemoteTab(shareId: String, hash: String) {
    dismissed[shareId] = hash
    rebuildRemoteTabs()
}

public func clearDismissed() {
    dismissed.removeAll()
    rebuildRemoteTabs()
}
// MARK: Fetch payload for import

/// Resolve which discovered peer most recently advertised the given shareId.
/// DashboardRootView can use this to import a remote tab without knowing peer topology.
@MainActor
public func peerForShareId(_ shareId: String) -> Peer? {
    if let ownerKey = shareIdOwnerEndpointKey[shareId] {
        if disabledPeerEndpointKeys.contains(ownerKey) {
            return nil
        }
        return peers.first(where: { $0.endpointKey == ownerKey })
    }
    return nil
}
// MARK: Fetch payload for import

public func fetchSharedTabPayload(shareId: String, from peer: Peer) async throws -> LANSharedTabPayload {
    guard let url = makePeerURL(host: peer.host, port: peer.port, path: "/sharedTab/\(shareId)") else {
        throw NSError(domain: "Relay.LAN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid peer URL for \(peer.host):\(peer.port)"])
    }
    let req = makePeerRequest(url: url)
    let (data, resp) = try await URLSession.shared.data(for: req)

    let statusCode: Int = (resp as? HTTPURLResponse)?.statusCode ?? -1

    #if DEBUG
    if let s = String(data: data, encoding: .utf8) {
        let preview = String(s.prefix(220)).replacingOccurrences(of: "\n", with: " ")
        print("🟦 LAN /sharedTab status=\(statusCode) preview (shareId=\(shareId)): \(preview)")
    } else {
        print("🟦 LAN /sharedTab status=\(statusCode) received \(data.count) bytes (non-utf8) shareId=\(shareId)")
    }
    #endif

    if statusCode == 401 {
        throw NSError(
            domain: "Relay.LAN",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Unauthorized (401). This device hasn't been approved by the sharing device. Try again to send a new pairing request, or check Settings → Sync & Mirror on the sharing device."]
        )
    }

    // Primary: wrapper payload
    var payload: LANSharedTabPayload
    if let decoded = try? JSONDecoder().decode(LANSharedTabPayload.self, from: data) {
        payload = decoded
    } else {
        // Back-compat: some peers may return the DashboardTab JSON directly.
        payload = LANSharedTabPayload(shareId: shareId, tabName: "", exportedTabJSON: data, schemaVersion: 1, hash: "")
    }

    if payload.shareId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        payload.shareId = shareId
    }

    // If wrapper decoded but didn't include the tab blob, treat entire response as the tab JSON if it looks like JSON.
    if payload.exportedTabJSON.isEmpty {
        let prefix = String(data: data.prefix(64), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if prefix.hasPrefix("{") || prefix.hasPrefix("[") {
            payload.exportedTabJSON = data
        }
    }

    if payload.tabName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        // Back-compat: older peers may omit tabName in payload; caller can override with manifest.tabName.
        payload.tabName = ""
    }

    #if DEBUG
    if payload.exportedTabJSON.isEmpty {
        print("❌ LAN payload missing exported tab data: shareId=\(shareId)")
    }
    #endif

    return payload
}

public func fetchSharedTabImportBundle(shareId: String, from peer: Peer) async throws -> LANSharedTabImportBundle {
    let tabName = remoteTabs.first(where: { $0.shareId == shareId })?.tabName
    let reason = tabName.map { "import \"\($0)\"" } ?? "import a shared tab"
    guard await ensurePaired(with: peer, reason: reason) else {
        throw NSError(
            domain: "Relay.LAN",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Pairing request was denied or timed out. Try again, or check Settings → Sync & Mirror on the sharing device."]
        )
    }
    guard let url = makePeerURL(host: peer.host, port: peer.port, path: "/sharedTabBundle/\(shareId)") else {
        throw NSError(domain: "Relay.LAN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid peer URL for \(peer.host):\(peer.port)"])
    }
    let req = makePeerRequest(url: url)
    let (data, resp) = try await URLSession.shared.data(for: req)

    let statusCode: Int = (resp as? HTTPURLResponse)?.statusCode ?? -1

    #if DEBUG
    if let s = String(data: data, encoding: .utf8) {
        let preview = String(s.prefix(220)).replacingOccurrences(of: "\n", with: " ")
        print("🟦 LAN /sharedTabBundle status=\(statusCode) preview (shareId=\(shareId)): \(preview)")
    } else {
        print("🟦 LAN /sharedTabBundle status=\(statusCode) received \(data.count) bytes (non-utf8) shareId=\(shareId)")
    }
    #endif

    if statusCode == 401 {
        throw NSError(
            domain: "Relay.LAN",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Unauthorized (401). This device hasn't been approved by the sharing device. Try again to send a new pairing request, or check Settings → Sync & Mirror on the sharing device."]
        )
    }

    if let bundle = try? JSONDecoder().decode(LANSharedTabImportBundle.self, from: data) {
        return bundle
    }

    if let payload = try? JSONDecoder().decode(LANSharedTabPayload.self, from: data) {
        return LANSharedTabImportBundle(
            payload: payload,
            externalDevicesJSON: nil,
            proPresenterSettingsJSON: nil,
            resolumeSettingsJSON: nil,
            planningCenterServiceJSON: nil
        )
    }

    let prefix = String(data: data.prefix(64), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if prefix.hasPrefix("{") || prefix.hasPrefix("[") {
        let payload = LANSharedTabPayload(
            shareId: shareId,
            tabName: "",
            exportedTabJSON: data,
            schemaVersion: 1,
            hash: ""
        )
        return LANSharedTabImportBundle(
            payload: payload,
            externalDevicesJSON: nil,
            proPresenterSettingsJSON: nil,
            resolumeSettingsJSON: nil,
            planningCenterServiceJSON: nil
        )
    }

    throw NSError(
        domain: "Relay.LAN",
        code: statusCode,
        userInfo: [NSLocalizedDescriptionKey: "Failed to decode LAN tab bundle (status \(statusCode)). The response was empty or not valid JSON."]
    )
}

public func fetchSharedTabRender(shareId: String, from peer: Peer, attemptPairingIfNeeded: Bool = false) async throws -> Data {
    // Viewing a Mirror tab is gated the same way as importing one — without this,
    // selecting a tab from an unpaired device just 401s silently (the server has no
    // "allow unpaired view" carve-out active by default) and nothing ever prompts the
    // host for approval, since only fetchSharedTabImportBundle used to call ensurePaired.
    //
    // attemptPairingIfNeeded defaults to false because this function is also called on a
    // ~1s poll loop (refreshLANRenderOnce) to keep the live image updating for an already
    // -selected tab. If that loop also attempted pairing on every tick, a denied/timed-out
    // device would trigger a brand new 30s handshake roughly every 30 seconds forever,
    // repeatedly popping the waiting overlay. Only the one-time "user selected this tab"
    // call site (openLANMirror) opts in; if that attempt fails, it clears the selection,
    // which stops the poll loop from running at all (its guard requires a selection).
    if attemptPairingIfNeeded {
        let tabName = remoteTabs.first(where: { $0.shareId == shareId })?.tabName
        let reason = tabName.map { "view \"\($0)\"" } ?? "view a shared tab"
        guard await ensurePaired(with: peer, reason: reason) else {
            throw NSError(
                domain: "Relay.LAN",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Pairing request was denied or timed out. Try again, or check Settings → Sync & Mirror on the sharing device."]
            )
        }
    }
    guard let url = makePeerURL(host: peer.host, port: peer.port, path: "/sharedTabRender/\(shareId)") else {
        throw NSError(domain: "Relay.LAN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid peer URL for \(peer.host):\(peer.port)"])
    }
    let req = makePeerRequest(url: url)
    let (data, resp) = try await URLSession.shared.data(for: req)
    let statusCode: Int = (resp as? HTTPURLResponse)?.statusCode ?? -1

    if statusCode == 401 {
        throw NSError(
            domain: "Relay.LAN",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Unauthorized (401). This device hasn't been approved by the sharing device. Try again to send a new pairing request, or check Settings → Sync & Mirror on the sharing device."]
        )
    }

    guard statusCode == 200, !data.isEmpty else {
        throw NSError(domain: "Relay.LAN", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch LAN render (status \(statusCode))."])
    }

    return data
}

public func sendPeerNotification(_ notification: LANPeerNotificationRequest, to peer: Peer) async throws {
    guard let url = makePeerURL(host: peer.host, port: peer.port, path: "/notify") else {
        throw NSError(domain: "Relay.LAN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid peer URL for \(peer.host):\(peer.port)"])
    }

    let body = try JSONEncoder().encode(notification)
    let req = makePeerRequest(url: url, method: "POST", body: body, contentType: "application/json")
    let (data, resp) = try await URLSession.shared.data(for: req)
    let statusCode: Int = (resp as? HTTPURLResponse)?.statusCode ?? -1

    if statusCode == 401 {
        throw NSError(
            domain: "Relay.LAN",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Unauthorized (401). This device hasn't been approved by the sharing device. Try again to send a new pairing request, or check Settings → Sync & Mirror on the sharing device."]
        )
    }

    guard (200...299).contains(statusCode) else {
        let responseText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let description = responseText?.isEmpty == false
            ? "Failed to send LAN notification (status \(statusCode)): \(responseText!)"
            : "Failed to send LAN notification (status \(statusCode))."
        throw NSError(domain: "Relay.LAN", code: statusCode, userInfo: [NSLocalizedDescriptionKey: description])
    }
}

public func postBrowserViewerNotification(
    title: String,
    message: String,
    durationSeconds: Double
) {
    let safeDuration = max(0.5, min(30, durationSeconds))
    browserViewerNotification = ActiveBrowserViewerNotification(
        id: UUID().uuidString,
        title: title,
        message: message,
        durationSeconds: safeDuration,
        expiresAt: Date().addingTimeInterval(safeDuration)
    )
}

// MARK: - Server
private func updateServerState() {
    if browserViewerHostingEnabled {
        if listener == nil {
            startServer()
        } else if activeListenPort != configuredListenPort {
            restartServer()
        } else {
            listener?.service = fullRelaySharingEnabled
                ? NWListener.Service(
                    name: deviceName,
                    type: config.serviceType,
                    domain: config.serviceDomain,
                    txtRecord: makeTXTRecord()
                )
                : nil
        }
    } else {
        listener?.cancel()
        listener = nil
        listenPort = nil
        activeListenPort = nil
    }
}

private func restartServer() {
    listener?.cancel()
    listener = nil
    listenPort = nil
    activeListenPort = nil
    guard browserViewerHostingEnabled else { return }
    startServer()
}

private func updateDiscoveryState() {
    guard discoveryAllowedByEntitlement else {
        stopPollingTasks()
        browser?.cancel()
        browser = nil
        clearDiscoveredState()
        return
    }
    if browser == nil {
        startBrowse()
    }
    if pollingEnabled {
        startPollingTasks()
    }
}

private func startServer() {
    guard browserViewerHostingEnabled else { return }
    do {
        let port: NWEndpoint.Port = (config.listenPort == 0) ? .any : NWEndpoint.Port(rawValue: config.listenPort)!
        listener = try NWListener(using: .tcp, on: port)

        listener?.service = fullRelaySharingEnabled
            ? NWListener.Service(
                name: deviceName,
                type: config.serviceType,
                domain: config.serviceDomain,
                txtRecord: makeTXTRecord()
            )
            : nil

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleIncoming(connection)
            }
        }

        let startedListener = listener
        listener?.stateUpdateHandler = { [weak self, weak startedListener] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.listenPort = self.listener?.port
                    self.activeListenPort = self.listener?.port?.rawValue
                    self.listenerConsecutiveFailures = 0
                }
            case .failed(let error):
                Task { @MainActor in
                    // Ignore failures from a listener that has already been replaced.
                    guard let startedListener, self.listener === startedListener else { return }
                    self.handleListenerFailure(error)
                }
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    } catch {
        print("❌ LANSharedTabsService server failed: \(error)")
    }
}

/// A failed listener never recovers on its own — after sleep/wake, a network change, or the
/// port being taken, this device silently stopped advertising and serving until the app was
/// relaunched. Tear it down and start a fresh one after a backoff delay.
private func handleListenerFailure(_ error: NWError) {
    listenerConsecutiveFailures += 1
    let delay = Self.listenerRestartDelay(afterConsecutiveFailures: listenerConsecutiveFailures)
    print("❌ LAN listener failed: \(error) — restarting in \(Int(delay))s")

    listener?.cancel()
    listener = nil
    listenPort = nil
    activeListenPort = nil

    listenerRestartTask?.cancel()
    listenerRestartTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled, let self, self.isStarted, self.listener == nil else { return }
        self.updateServerState()
    }
}

/// Capped exponential backoff (2s, 4s, 8s … 30s) so a persistent failure can't spin.
nonisolated static func listenerRestartDelay(afterConsecutiveFailures failures: Int) -> TimeInterval {
    let exponent = min(max(failures, 1), 5)
    return min(pow(2, Double(exponent)), 30)
}

private func makeTXTRecord() -> NWTXTRecord {
    var record = NWTXTRecord()

    // NWTXTRecord expects String values; this is advertised over Bonjour.
    record[LANKeys.deviceId] = deviceId
    record[LANKeys.deviceName] = deviceName
    record[LANKeys.deviceKind] = Self.currentDeviceKind.rawValue
    record[LANKeys.proto] = config.protocolVersion
    record[LANKeys.pairing] = "1"
    record[LANKeys.enabled] = fullRelaySharingEnabled ? "1" : "0"

    return record
}

private func handleIncoming(_ connection: NWConnection) {
    connection.start(queue: .global(qos: .userInitiated))
    receiveHTTP(connection)
}

/// Reads the request line-by-line into `buffer` until the full HTTP request (headers + declared
/// Content-Length body) has arrived, then dispatches once to `route(request:)`.
///
/// A single `connection.receive()` call only returns whatever happened to be in the socket buffer
/// at that moment — for larger POST bodies (e.g. a synced-tab snapshot) sent over a real Wi-Fi hop
/// (Mac<->iPad) rather than loopback/same-machine testing, the headers and body frequently arrive
/// as separate TCP reads. Calling `route(request:)` as soon as "\r\n\r\n" is seen — without waiting
/// for Content-Length bytes to actually arrive — silently truncates the body, producing intermittent
/// "bodyBytes=0" / 400 invalid-payload failures that vary by network timing rather than any real
/// client or server bug.
private func receiveHTTP(_ connection: NWConnection, buffer: Data = Data(), idleTimer: DispatchWorkItem? = nil) {
    idleTimer?.cancel()
    let timer = DispatchWorkItem { connection.cancel() }
    DispatchQueue.global().asyncAfter(deadline: .now() + HTTPRequestLimits.idleTimeout, execute: timer)

    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
        Task { @MainActor [weak self] in
            guard let self else { timer.cancel(); return }
            var buffer = buffer
            if let data, !data.isEmpty { buffer.append(data) }

            switch HTTPRequestLimits.evaluate(buffer: buffer) {
            case .needMore:
                if isComplete || error != nil {
                    timer.cancel()
                    connection.cancel()
                } else {
                    self.receiveHTTP(connection, buffer: buffer, idleTimer: timer)
                }
            case .headersTooLarge:
                timer.cancel()
                connection.send(content: httpStatusOnly(431, "Request Header Fields Too Large"),
                                completion: .contentProcessed { _ in connection.cancel() })
            case .bodyTooLarge:
                timer.cancel()
                connection.send(content: httpStatusOnly(413, "Payload Too Large"),
                                completion: .contentProcessed { _ in connection.cancel() })
            case .malformed:
                timer.cancel()
                connection.send(content: httpStatusOnly(400, "Bad Request"),
                                completion: .contentProcessed { _ in connection.cancel() })
            case .ready:
                timer.cancel()
                let request = String(decoding: buffer, as: UTF8.self)
                let response = self.route(request: request)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}

func route(request: String) -> Data {
    // Force a fresh read of sharing settings before evaluating auth. The debounced
    // UserDefaults observer (750ms) keeps the cache current for the common case, but incoming
    // requests must never authorize against a stale cached sharing/view-only setting — a race
    // or missed notification there would make a settings change silently not take effect for
    // inbound traffic (outbound pushes already force-refresh before sending; this matches that
    // guarantee). Device trust itself (pairedDevices) isn't cached at all — isAuthorized() reads
    // it directly, so it's always current.
    refreshSettingsCache(force: true)

    // Minimal HTTP parser for GET/POST requests.
    // Parse request line + headers so we can enforce pairing.
    let requestParts = request.components(separatedBy: "\r\n\r\n")
    let headerBlock = requestParts.first ?? request
    let bodyData = Data(requestParts.dropFirst().joined(separator: "\r\n\r\n").utf8)
    let rawLines = headerBlock.split(separator: "\r\n", omittingEmptySubsequences: false)
    guard let first = rawLines.first else { return http404() }

    let requestLineParts = first.split(separator: " ")
    guard requestLineParts.count >= 2 else { return http404() }

    let method = requestLineParts[0]
    let requestTarget = String(requestLineParts[1])
    let targetParts = requestTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let path = String(targetParts.first ?? "")
    let queryItems = URLComponents(string: "http://relay.local\(requestTarget)")?.queryItems ?? []

    // Collect headers
    var headers: [String: String] = [:]
    if rawLines.count > 1 {
        for line in rawLines.dropFirst() {
            if line.isEmpty { break }
            if let idx = line.firstIndex(of: ":") {
                let key = line[..<idx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                headers[key] = value
            }
        }
    }

    // If browser hosting is disabled, act like endpoints don't exist.
    guard browserViewerHostingEnabled else { return http404() }

    // Authorization check — is the deviceId on this request a trusted paired device?
    // Memoized per request: verifying a signature consumes its nonce, so a second evaluation
    // within the same request must not be treated as a replay.
    var authorizedMemo: Bool? = nil
    func isAuthorized() -> Bool {
        if let memo = authorizedMemo { return memo }
        let result = evaluateAuthorization()
        authorizedMemo = result
        return result
    }
    func evaluateAuthorization() -> Bool {
        if let requestDeviceId = headers["x-relay-device-id"] {
            guard DevicePairingStore.isAuthorized(deviceId: requestDeviceId, in: pairedDevices) else { return false }
            if let secret = pairingSecretStore.secret(for: requestDeviceId) {
                guard let ts = headers["x-relay-timestamp"].flatMap(Int.init),
                      let nonce = headers["x-relay-nonce"], !nonce.isEmpty, nonce.count <= 64,
                      let sig = headers["x-relay-signature"] else { return false }
                guard LANRequestSigner.verify(secret: secret, signature: sig, method: String(method),
                                              target: requestTarget, timestamp: ts, nonce: nonce,
                                              body: bodyData, now: Date()) else { return false }
                return consumeNonce("\(requestDeviceId)|\(nonce)")
            }
            // Pair established by an older build: no secret to check. Allowed during the
            // transition release; devices that hold a secret are always enforced above.
            return UserDefaults.standard.object(forKey: "lan_allow_legacy_unsigned") as? Bool ?? true
        }

        // Compatibility with older Relay releases that authenticated requests using a
        // shared pairing code. Never use this fallback when a modern device ID is present:
        // that prevents an untrusted modern peer from bypassing per-device approval.
        guard let configuredCode = UserDefaults.standard.string(forKey: "lan_pairing_code"),
              !configuredCode.isEmpty else {
            print("🟠 isAuthorized[\(method) \(path)]: FAIL — no device ID or legacy code configured")
            return false
        }
        let bearer = headers["authorization"].flatMap { value -> String? in
            guard value.lowercased().hasPrefix("bearer ") else { return nil }
            return String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let legacyCode = headers["x-relay-pairing"] ?? headers["x-prodlink-pairing"]
        return bearer == configuredCode || legacyCode == configuredCode
    }

    if method == "GET", path == "/linkedVariables/v1" {
        guard SubscriptionManager.shared.hasPro, fullRelaySharingEnabled,
              isAuthorized(),
              let requesterID = headers["x-relay-device-id"] else { return http401() }
        guard pairedDevices[requesterID]?.sharesVariables == true else { return http403() }
        let values = LinkedDeviceVariableSnapshot.outbound(
            from: SharedValueStore.shared.snapshot.values,
            localTabIDs: linkedVariableLocalTabIDs,
            people: linkedVariableLocalPeople,
            hasPro: SubscriptionManager.shared.hasPro
        )
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return http200(json: data)
    }

    if method == "GET", path == "/syncedVariables/v1" {
        guard SubscriptionManager.shared.hasPro, fullRelaySharingEnabled, isAuthorized(),
              let requesterID = headers["x-relay-device-id"] else { return http401() }
        guard let groupID = queryItems.first(where: { $0.name == "groupID" })?.value,
              localSyncedGroupIDs.contains(groupID),
              liveSubscribersByGroupID[groupID]?.contains(requesterID) == true,
              let snapshot = localSyncedSnapshotsByGroupID[groupID] else { return http404() }
        let values = SyncedTabVariableSnapshot.referenced(
            in: snapshot.exportedTabJSON,
            values: SharedValueStore.shared.snapshot.values,
            hasPro: SubscriptionManager.shared.hasPro
        )
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return http200(json: data)
    }

    if method == "GET", path == "/sharedTabs" {
        // Discovery is intentionally NOT gated on isAuthorized() — same reasoning as
        // /syncedTabs below: a device must be able to see that a Mirror tab exists before it
        // can ever request pairing to import it. This route returns manifest metadata only
        // (names, device names), not actual content; the "allow view-only without pairing"
        // toggle governs actual content routes (/sharedTabRender/, /localFile/,
        // /localPersonPhoto/), not this listing.
        guard fullRelaySharingEnabled else { return http404() }
        let data = (try? JSONEncoder().encode(localManifests)) ?? Data()
        return http200(json: data)
    }

    if method == "GET", (path == "/" || path == "/index.html") {
        guard browserViewOnlyEnabled else { return http404() }
        return http200HTML(browserViewerHTML())
    }

    if method == "GET", path == "/browserState" {
        guard browserViewOnlyEnabled else { return http404() }
        let shareId = queryItems.first(where: { $0.name == "shareId" })?.value
        let data = (try? JSONEncoder().encode(currentBrowserViewerState(for: shareId))) ?? Data()
        return http200(json: data)
    }

    if method == "GET", path.hasPrefix("/view/") {
        guard browserViewOnlyEnabled else { return http404() }
        let shareId = path.replacingOccurrences(of: "/view/", with: "")
        guard let manifest = localManifests.first(where: { $0.shareId == shareId }) else {
            return http404()
        }
        renderRequestLastSeenByShareId[shareId] = Date()
        return http200HTML(browserViewerHTML(lockedShareId: manifest.shareId))
    }

    if method == "GET", path.hasPrefix("/sharedTab/") {
        guard fullRelaySharingEnabled else { return http404() }
        // Payload is always protected.
        if !isAuthorized() {
            return http401()
        }
        let shareId = path.replacingOccurrences(of: "/sharedTab/", with: "")
        if let payload = localPayloadsByShareId[shareId],
           let data = try? JSONEncoder().encode(payload) {
            return http200(json: data)
        }
        return http404()
    }

    if method == "GET", path.hasPrefix("/sharedTabBundle/") {
        guard fullRelaySharingEnabled else { return http404() }
        // Bundle is always protected.
        if !isAuthorized() {
            return http401()
        }

        let shareId = path.replacingOccurrences(of: "/sharedTabBundle/", with: "")
        guard let payload = localPayloadsByShareId[shareId] else {
            return http404()
        }

        // Encode the host's external devices snapshot (so the importing device can connect).
        var externalDevicesJSON: Data? = nil
        do {
            let encoder = JSONEncoder()
            externalDevicesJSON = try encoder.encode(ExternalDevicesStore.shared.currentSnapshot())
        } catch {
            externalDevicesJSON = nil
        }

        // ProPresenter settings snapshot (profiles + active selection + global keys)
        var proPresenterSettingsJSON: Data? = nil
        do {
            let snap = ProPresenterLANSettingsSnapshot.loadFromUserDefaults(.standard)
            proPresenterSettingsJSON = try JSONEncoder().encode(snap)
        } catch {
            proPresenterSettingsJSON = nil
        }

        // Resolume profiles store persisted blob (matches ResolumeProfilesStore.storageKey)
        let resolumeSettingsJSON: Data? = UserDefaults.standard.data(forKey: "Relay.ResolumeProfilesStore.v1")

        // Planning Center snapshot: this is optional and may already be present in exportedTabJSON.
        // If you later add a safe persisted cache key for service data, wire it here.
        let planningCenterServiceJSON: Data? = nil

        let bundle = LANSharedTabImportBundle(
            payload: payload,
            externalDevicesJSON: externalDevicesJSON,
            proPresenterSettingsJSON: proPresenterSettingsJSON,
            resolumeSettingsJSON: resolumeSettingsJSON,
            planningCenterServiceJSON: planningCenterServiceJSON
        )
        if let data = try? JSONEncoder().encode(bundle) {
            return http200(json: data)
        }
        return http404()
    }

    if method == "GET", path.hasPrefix("/sharedTabRender/") {
        // View-only render access can be opened without pairing, while imports remain protected.
        if !browserViewOnlyEnabled && !isAuthorized() && !allowsUnauthenticatedViewOnlyAccess {
            return http401()
        }

        let shareId = path.replacingOccurrences(of: "/sharedTabRender/", with: "")
        renderRequestLastSeenByShareId[shareId] = Date()
        guard let imageData = localRenderImagesByShareId[shareId] else {
            return http404()
        }
        return http200Image(data: imageData)
    }

    if method == "POST", path == "/notify" {
        guard fullRelaySharingEnabled else { return http404() }
        if !isAuthorized() {
            return http401()
        }
        guard let payload = try? JSONDecoder().decode(LANPeerNotificationRequest.self, from: bodyData) else {
            return http400(message: "invalid_notification_payload")
        }

        NotificationCenter.default.post(
            name: ActionNodeNotifications.notify,
            object: nil,
            userInfo: [
                ActionNodeUserInfoKeys.title: payload.title,
                ActionNodeUserInfoKeys.message: payload.message,
                ActionNodeUserInfoKeys.durationSeconds: payload.durationSeconds
            ]
        )

        return http202(json: Data("{\"ok\":true}".utf8))
    }

    if method == "GET", path == "/syncedTabs" {
        // Discovery is intentionally NOT gated on isAuthorized(): a device has to be able to
        // see that a Synced Tab exists before it can ever request pairing to join it. Gating
        // this would be a chicken-and-egg deadlock — the only way to initiate pairing (tapping
        // Join on a discovered manifest) requires already seeing a manifest that discovery
        // refuses to return. Matches this codebase's own LAN threat model (same-LAN presence
        // is the trust boundary for *visibility*; explicit approval is only required for
        // actions that persist a relationship — joining, importing). The actual full snapshot
        // (/syncedTab/{groupID}, tile content) and pushes (/syncedTab/push) remain gated.
        guard fullRelaySharingEnabled else {
            return http404()
        }

        // Live subscriber tracking piggybacks on this same poll: the caller (if paired) reports
        // which groups it currently holds via `?joined=`, recorded against groups we host. Only
        // recorded for authorized callers — see recordLiveSubscriber's doc comment for why.
        if isAuthorized(), let callerDeviceId = headers["x-relay-device-id"] {
            let joinedGroupIDs = (queryItems.first(where: { $0.name == "joined" })?.value ?? "")
                .split(separator: ",")
                .map(String.init)
            for groupID in joinedGroupIDs where localSyncedGroupIDs.contains(groupID) {
                recordLiveSubscriber(deviceId: callerDeviceId, groupID: groupID)
            }
        }

        // Subscriber device IDs are only for paired peers; strangers just see the groups.
        let liveForResponse = isAuthorized()
            ? liveSubscribersByGroupID
            : liveSubscribersByGroupID.mapValues { _ in Set<String>() }
        let response = SyncedTabsResponse(
            manifests: localSyncedManifests,
            localPresence: nil,
            liveSubscribersByGroupID: liveForResponse
        )
        let data = (try? JSONEncoder().encode(response)) ?? Data()
        return http200(json: data)
    }

    if method == "GET", path == "/syncedPresence" {
        guard fullRelaySharingEnabled else { return http404() }
        if !isAuthorized() {
            return http401()
        }
        guard let gid = localPresenceGroupID,
              (localPresenceTileID != nil || !localPresenceSelectedTileIDs.isEmpty) else {
            return http204()
        }
        var editingByGroup: [String: [String]] = [:]
        if let tid = localPresenceTileID { editingByGroup[gid] = [tid] }
        let selectedByGroup: [String: [String]] = localPresenceSelectedTileIDs.isEmpty
            ? [:] : [gid: localPresenceSelectedTileIDs]
        let payload = SyncedPresencePayload(
            deviceID: deviceId,
            deviceName: deviceName,
            editingByGroup: editingByGroup,
            selectedByGroup: selectedByGroup
        )
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return http200(json: data)
    }

    if method == "POST", path == "/syncedPresence" {
        guard fullRelaySharingEnabled else { return http404() }
        if !isAuthorized() {
            return http401()
        }
        guard let payload = try? JSONDecoder().decode(SyncedPresencePayload.self, from: bodyData) else {
            return http400(message: "invalid_presence")
        }
        let senderID = payload.deviceID
        let isEmpty = payload.editingByGroup.isEmpty && (payload.selectedByGroup?.isEmpty ?? true)
        pushedPresenceExpiryTasks[senderID]?.cancel()
        if isEmpty {
            pushedPresence.removeValue(forKey: senderID)
            pushedPresenceExpiryTasks[senderID] = nil
        } else {
            pushedPresence[senderID] = payload
            pushedPresenceExpiryTasks[senderID] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.pushedPresence.removeValue(forKey: senderID)
                self?.pushedPresenceExpiryTasks.removeValue(forKey: senderID)
            }
        }
        return http200(json: Data("{\"ok\":true}".utf8))
    }

    if method == "GET", path.hasPrefix("/syncedTab/") {
        guard fullRelaySharingEnabled else { return http404() }
        if !isAuthorized() {
            return http401()
        }
        let groupID = path.replacingOccurrences(of: "/syncedTab/", with: "")
        if let snapshot = localSyncedSnapshotsByGroupID[groupID],
           let data = try? JSONEncoder().encode(snapshot) {
            return http200(json: data)
        }
        return http404()
    }

    if method == "GET", path.hasPrefix("/localFile/") {
        guard fullRelaySharingEnabled else { return http404() }
        if !isAuthorized() && !allowsUnauthenticatedViewOnlyAccess { return http401() }
        let hash = (String(path.dropFirst("/localFile/".count)).removingPercentEncoding ?? String(path.dropFirst("/localFile/".count)))
        guard !hash.isEmpty, let filePath = localFileRegistry[hash] else { return http404() }
        guard let data = FileManager.default.contents(atPath: filePath) else { return http404() }
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Content-Type: application/octet-stream\r\n"
        header += "Connection: close\r\n\r\n"
        return header.data(using: .utf8)! + data
    }

    if method == "GET", path.hasPrefix("/localPersonPhoto/") {
        guard fullRelaySharingEnabled else { return http404() }
        if !isAuthorized() && !allowsUnauthenticatedViewOnlyAccess { return http401() }
        let rawFilename = String(path.dropFirst("/localPersonPhoto/".count))
        // URL-decode the filename — appendingPathComponent percent-encodes spaces and special chars.
        let filename = rawFilename.removingPercentEncoding ?? rawFilename
        guard !localPersonImageFolderPath.isEmpty,
              let filePath = SafeFilePath.resolve(filename: filename, inFolder: localPersonImageFolderPath),
              let data = FileManager.default.contents(atPath: filePath) else { return http404() }
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Content-Type: image/jpeg\r\n"
        header += "Connection: close\r\n\r\n"
        return header.data(using: .utf8)! + data
    }

    if method == "POST", path == "/syncedTab/push" {
        print("🟢 POST /syncedTab/push received, bodyBytes=\(bodyData.count)")
        guard fullRelaySharingEnabled else {
            print("🟢 POST /syncedTab/push → 404 (sharing disabled)")
            return http404()
        }
        if !isAuthorized() {
            print("🟢 POST /syncedTab/push → 401 (unauthorized)")
            return http401()
        }
        guard let incoming = try? JSONDecoder().decode(SyncedTabSnapshot.self, from: bodyData) else {
            print("🟢 POST /syncedTab/push → 400 (invalid payload)")
            return http400(message: "invalid_synced_tab_snapshot")
        }

        // Only accept pushes for groups this device hosts or has already joined.
        // Pushes for unknown groups would incorrectly mark this device as a host and
        // suppress LAN discovery of the real host.
        let isKnownGroup = localSyncedGroupIDs.contains(incoming.groupID) || joinedSyncGroupIDs.contains(incoming.groupID)
        guard isKnownGroup else {
            print("🟢 POST /syncedTab/push → applied=false (unknown groupID=\(incoming.groupID))")
            return http200(json: Data("{\"ok\":true,\"applied\":false}".utf8))
        }

        if let existing = localSyncedSnapshotsByGroupID[incoming.groupID], !(incoming.version > existing.version) {
            print("🟢 POST /syncedTab/push → applied=false (incoming rev\(incoming.version.revision) not newer than existing rev\(existing.version.revision))")
            return http200(json: Data("{\"ok\":true,\"applied\":false}".utf8))
        }
        print("🟢 POST /syncedTab/push → applied=true (groupID=\(incoming.groupID), rev\(incoming.version.revision))")

        localSyncedSnapshotsByGroupID[incoming.groupID] = incoming
        if let idx = localSyncedManifests.firstIndex(where: { $0.groupID == incoming.groupID }) {
            localSyncedManifests[idx] = SyncedTabManifest(
                groupID: incoming.groupID,
                tabName: incoming.tabName,
                deviceID: localSyncedManifests[idx].deviceID,
                deviceName: localSyncedManifests[idx].deviceName,
                version: incoming.version,
                summary: localSyncedManifests[idx].summary
            )
        }
        pendingSyncedSnapshots.append(incoming)

        // If the pusher piggybacked their editing presence, record it with a 5-second TTL.
        let presenceTileID = queryItems.first(where: { $0.name == "presenceTileID" })?.value
        let presenceGroupID = queryItems.first(where: { $0.name == "presenceGroupID" })?.value
        if let tid = presenceTileID, let gid = presenceGroupID {
            let senderID = incoming.version.editedByDeviceID
            let payload = SyncedPresencePayload(
                deviceID: senderID,
                deviceName: incoming.lastEditedByDeviceName,
                editingByGroup: [gid: [tid]]
            )
            pushedPresence[senderID] = payload
            pushedPresenceExpiryTasks[senderID]?.cancel()
            pushedPresenceExpiryTasks[senderID] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.pushedPresence.removeValue(forKey: senderID)
                self?.pushedPresenceExpiryTasks.removeValue(forKey: senderID)
            }
        }

        return http200(json: Data("{\"ok\":true,\"applied\":true}".utf8))
    }

    if method == "POST", path == "/syncedTab/stop" {
        guard fullRelaySharingEnabled else { return http404() }
        if !isAuthorized() { return http401() }
        guard let payload = try? JSONDecoder().decode(SyncedTabStopPayload.self, from: bodyData) else {
            return http400(message: "invalid_stop_payload")
        }
        // Only mark orphaned if we actually joined this group (not the host or an unrelated device).
        if joinedSyncGroupIDs.contains(payload.groupID) {
            orphanedSyncGroupIDs.insert(payload.groupID)
            hostStoppedGroupIDs.insert(payload.groupID)
        }
        return http200(json: Data("{\"ok\":true}".utf8))
    }

    if method == "POST", path == "/pair/request" {
        guard fullRelaySharingEnabled else { return http404() }
        guard let decoded = try? JSONDecoder().decode(PairingRequestPayload.self, from: bodyData) else {
            return http400(message: "invalid_pairing_request")
        }
        guard decoded.requestId.count <= 64, decoded.deviceId.count <= 64 else {
            return http400(message: "invalid_pairing_request")
        }
        let payload = PairingRequestPayload(
            requestId: decoded.requestId,
            deviceId: decoded.deviceId,
            deviceName: PairingInputSanitizer.deviceName(decoded.deviceName),
            deviceKind: decoded.deviceKind,
            reason: decoded.reason,
            publicKey: decoded.publicKey
        )

        // Existing trust is enough for an operation-triggered request such as Join or
        // Import. A manual Connect is different: the requester has no local trust entry,
        // so require an explicit approval even if this computer retained stale trust.
        let hasSecret = pairingSecretStore.secret(for: payload.deviceId) != nil
        if DevicePairingStore.isAuthorized(deviceId: payload.deviceId, in: pairedDevices),
           payload.reason != "connect", (!hasSecret || isAuthorized()) {
            recordPairingOutcome(.approved, for: payload.requestId)
            return http202(json: Data("{\"status\":\"approved\"}".utf8))
        }

        // Explicitly blocked — silently reject, never surface a prompt.
        if DevicePairingStore.status(for: payload.deviceId, in: pairedDevices) == .blocked {
            recordPairingOutcome(.denied, for: payload.requestId)
            return http202(json: Data("{\"status\":\"denied\"}".utf8))
        }

        // Cooldown after a recent denial/timeout for this device — reject without prompting.
        if let cooldownUntil = pairingCooldownByDeviceId[payload.deviceId], cooldownUntil > Date() {
            recordPairingOutcome(.denied, for: payload.requestId)
            return http202(json: Data("{\"status\":\"denied\"}".utf8))
        }

        pruneStalePendingPairingRequests()

        // Bound the approval queue so a stranger can't flood the host with prompts.
        guard pendingPairingRequests.count < PairingInputSanitizer.maxPendingRequests
                || pendingPairingRequests.contains(where: { $0.payload.deviceId == payload.deviceId }) else {
            recordPairingOutcome(.denied, for: payload.requestId)
            return http202(json: Data("{\"status\":\"denied\"}".utf8))
        }

        // Replace any still-pending request from this same device rather than piling up
        // duplicates (e.g. a retry after a client-side timeout) — only the latest request
        // per device should ever be waiting for a decision.
        pendingPairingRequests.removeAll { $0.payload.deviceId == payload.deviceId }
        recordPairingOutcome(.pending, for: payload.requestId)
        pendingPairingRequests.append(PendingPairingRequest(payload: payload, receivedAt: Date()))
        var pendingBody: [String: Any] = ["status": "pending"]
        if payload.publicKey != nil {
            let hostKey = LANPairingKeyAgreement.makeKeyPair()
            pairingHostKeysByRequestId[payload.requestId] = (hostKey, Date())
            pendingBody["hostPublicKey"] = hostKey.publicBase64
        }
        return http202(json: (try? JSONSerialization.data(withJSONObject: pendingBody)) ?? Data("{\"status\":\"pending\"}".utf8))
    }

    if method == "GET", path == "/pair/status" {
        guard fullRelaySharingEnabled else { return http404() }
        guard let requestId = queryItems.first(where: { $0.name == "requestId" })?.value else {
            return http400(message: "missing_requestId")
        }
        let outcome = pairingOutcomesByRequestId[requestId]?.outcome ?? .pending
        var statusBody: [String: Any] = ["status": outcome.rawValue]
        if outcome == .approved, let host = pairingHostKeysByRequestId[requestId] {
            statusBody["hostPublicKey"] = host.key.publicBase64
        }
        return http200(json: (try? JSONSerialization.data(withJSONObject: statusBody)) ?? Data("{\"status\":\"\(outcome.rawValue)\"}".utf8))
    }

    if method != "GET" && method != "POST" {
        return http405()
    }

    return http404()
}

private func http200(json: Data) -> Data {
    var header = "HTTP/1.1 200 OK\r\n"
    header += "Content-Type: application/json\r\n"
    header += "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n"
    header += "Pragma: no-cache\r\n"
    header += "Expires: 0\r\n"
    header += "Content-Length: \(json.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(json)
    return out
}

private func http202(json: Data) -> Data {
    var header = "HTTP/1.1 202 Accepted\r\n"
    header += "Content-Type: application/json\r\n"
    header += "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n"
    header += "Pragma: no-cache\r\n"
    header += "Expires: 0\r\n"
    header += "Content-Length: \(json.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(json)
    return out
}

private func http200HTML(_ html: String) -> Data {
    let data = Data(html.utf8)
    var header = "HTTP/1.1 200 OK\r\n"
    header += "Content-Type: text/html; charset=utf-8\r\n"
    header += "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n"
    header += "Pragma: no-cache\r\n"
    header += "Expires: 0\r\n"
    header += "Content-Length: \(data.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(data)
    return out
}

private func http200Image(data: Data) -> Data {
    var header = "HTTP/1.1 200 OK\r\n"
    header += "Content-Type: image/jpeg\r\n"
    header += "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n"
    header += "Pragma: no-cache\r\n"
    header += "Expires: 0\r\n"
    header += "Content-Length: \(data.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(data)
    return out
}

private func http401() -> Data {
    let body = Data("{\"error\":\"unauthorized\"}".utf8)
    var header = "HTTP/1.1 401 Unauthorized\r\n"
    header += "Content-Type: application/json\r\n"
    header += "Content-Length: \(body.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(body)
    return out
}

private func http403() -> Data {
    let body = Data("{\"error\":\"variable_sharing_disabled\"}".utf8)
    var header = "HTTP/1.1 403 Forbidden\r\n"
    header += "Content-Type: application/json\r\n"
    header += "Content-Length: \(body.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(body)
    return out
}

private func http400(message: String) -> Data {
    let body = Data("{\"error\":\"\(message)\"}".utf8)
    var header = "HTTP/1.1 400 Bad Request\r\n"
    header += "Content-Type: application/json\r\n"
    header += "Content-Length: \(body.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(body)
    return out
}

private func httpStatusOnly(_ code: Int, _ reason: String) -> Data {
    Data("HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
}

private func http404() -> Data {
    let body = Data("{\"error\":\"not_found\"}".utf8)
    var header = "HTTP/1.1 404 Not Found\r\n"
    header += "Content-Type: application/json\r\n"
    header += "Content-Length: \(body.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(body)
    return out
}

private func http204() -> Data {
    var header = "HTTP/1.1 204 No Content\r\n"
    header += "Content-Length: 0\r\n"
    header += "Connection: close\r\n\r\n"
    return Data(header.utf8)
}

private func http405() -> Data {
    let body = Data("{\"error\":\"method_not_allowed\"}".utf8)
    var header = "HTTP/1.1 405 Method Not Allowed\r\n"
    header += "Content-Type: application/json\r\n"
    header += "Content-Length: \(body.count)\r\n"
    header += "Connection: close\r\n\r\n"
    var out = Data(header.utf8)
    out.append(body)
    return out
}

private struct BrowserViewerState: Codable {
    let shareId: String?
    let tabTitle: String
    let deviceLabel: String
    let imagePath: String?
    let hasContent: Bool
    let notification: BrowserViewerNotificationState?
}

private func browserViewerHTML(lockedShareId: String? = nil) -> String {
    let statePath: String
    if let lockedShareId {
        statePath = "/browserState?shareId=\(lockedShareId)"
    } else {
        statePath = "/browserState"
    }

    return """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
      <title>Relay Viewer</title>
      <style>
        :root { color-scheme: dark; --bg:#05070a; --panel:#11161d; --line:#273142; --text:#f5f7fa; --muted:#94a3b8; }
        * { box-sizing:border-box; }
        body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; color:var(--text); background:radial-gradient(circle at top, #18212d 0%, #0b0f14 45%, #05070a 100%); }
        .shell { min-height:100vh; display:flex; flex-direction:column; }
        .topbar { display:flex; justify-content:space-between; gap:12px; align-items:center; padding:14px 18px; background:rgba(10,14,20,0.82); border-bottom:1px solid var(--line); backdrop-filter: blur(18px); position:sticky; top:0; transition:transform 180ms ease, opacity 180ms ease; }
        body.chrome-hidden .topbar { transform:translateY(-100%); opacity:0; pointer-events:none; position:fixed; left:0; right:0; }
        .title { font-size:17px; font-weight:700; }
        .meta { color:var(--muted); font-size:12px; }
        .controls { display:flex; gap:8px; align-items:center; }
        .control-btn { width:40px; height:40px; display:inline-flex; align-items:center; justify-content:center; border:1px solid var(--line); background:rgba(17,22,29,0.94); color:var(--text); border-radius:999px; padding:0; font-size:18px; line-height:1; cursor:pointer; }
        .control-btn svg { width:18px; height:18px; display:block; }
        .control-btn.exit-mode { font-size:20px; }
        .floating-exit { position:fixed; top:16px; right:16px; z-index:30; box-shadow:0 10px 30px rgba(0,0,0,0.28); }
        body:not(.chrome-hidden) .floating-exit { display:none; }
        .viewer { flex:1; display:flex; align-items:center; justify-content:center; padding:14px; transition:padding-top 180ms ease; }
        body.chrome-hidden .viewer { padding-top:0; }
        .stage { position:relative; width:100%; height:100%; display:flex; align-items:center; justify-content:center; }
        img { max-width:100%; max-height:calc(100vh - 92px); object-fit:contain; border-radius:20px; border:1px solid rgba(255,255,255,0.08); background:#000; }
        body.chrome-hidden img { max-height:100vh; }
        .empty { max-width:520px; margin:24px; padding:24px; border-radius:20px; background:rgba(17,22,29,0.94); border:1px solid var(--line); }
        .overlay { position:absolute; inset:0; display:flex; align-items:center; justify-content:center; pointer-events:none; }
        .spinner-shell, .warning-shell { max-width:520px; margin:24px; padding:24px; border-radius:20px; background:rgba(17,22,29,0.94); border:1px solid var(--line); text-align:center; }
        .spinner { width:42px; height:42px; margin:0 auto 14px; border-radius:50%; border:4px solid rgba(148,163,184,0.22); border-top-color:#f5f7fa; animation:spin 0.9s linear infinite; }
        .warning-shell { border-color:#7f1d1d; background:rgba(69,10,10,0.88); }
        .warning-title { font-size:20px; font-weight:700; margin-bottom:8px; }
        .warning-meta, .spinner-meta { color:var(--muted); font-size:14px; }
        .status { position:fixed; right:16px; bottom:16px; padding:8px 12px; border-radius:999px; background:rgba(17,22,29,0.9); border:1px solid var(--line); color:var(--muted); font-size:12px; }
        .banner { position:fixed; left:50%; bottom:18px; transform:translateX(-50%); max-width:min(720px, calc(100vw - 32px)); padding:14px 18px; border-radius:18px; background:rgba(17,22,29,0.94); border:1px solid rgba(96,165,250,0.32); box-shadow:0 18px 46px rgba(0,0,0,0.28); backdrop-filter: blur(18px); z-index:40; }
        .banner-title { font-size:15px; font-weight:700; margin-bottom:4px; }
        .banner-message { color:var(--muted); font-size:13px; }
        body.chrome-hidden .status { display:none; }
        [hidden] { display:none !important; }
        @keyframes spin { to { transform:rotate(360deg); } }
      </style>
    </head>
    <body>
      <div class="shell">
        <div class="topbar" id="topbar">
          <div>
            <div class="title" id="tab-title">Relay Viewer</div>
            <div class="meta" id="tab-meta">Waiting for source device…</div>
          </div>
          <div class="controls">
            <button class="control-btn" id="toggle-fullscreen" type="button" aria-label="Enter fullscreen">
              <svg id="fullscreen-enter-icon" viewBox="0 0 24 24" aria-hidden="true">
                <path fill="currentColor" d="M5 9V5h4v2H7v2H5Zm10-4h4v4h-2V7h-2V5ZM5 19v-4h2v2h2v2H5Zm12-2v-2h2v4h-4v-2h2Z"/>
              </svg>
              <span id="fullscreen-exit-icon" hidden>×</span>
            </button>
          </div>
        </div>
        <div class="viewer" id="viewer">
          <div class="stage">
            <img id="tab-image" alt="Relay Viewer" hidden>
            <div class="empty" id="empty-state">No active tab selected on the source device.</div>
            <div class="overlay" id="loading-overlay">
              <div class="spinner-shell">
                <div class="spinner"></div>
                <div class="spinner-meta" id="loading-label">Connecting to source device…</div>
              </div>
            </div>
            <div class="overlay" id="disconnect-overlay" hidden>
              <div class="warning-shell">
                <div class="warning-title">Source Disconnected</div>
                <div class="warning-meta">The source Relay device is unavailable. Reconnect the source or refresh this page once it returns.</div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <button class="control-btn floating-exit" id="exit-viewer-mode" type="button" aria-label="Exit fullscreen" hidden>×</button>
      <div class="banner" id="viewer-banner" hidden>
        <div class="banner-title" id="viewer-banner-title"></div>
        <div class="banner-message" id="viewer-banner-message"></div>
      </div>
      <div class="status" id="status">Connecting…</div>
      <script>
        const image = document.getElementById('tab-image');
        const status = document.getElementById('status');
        const title = document.getElementById('tab-title');
        const meta = document.getElementById('tab-meta');
        const emptyState = document.getElementById('empty-state');
        const loadingOverlay = document.getElementById('loading-overlay');
        const loadingLabel = document.getElementById('loading-label');
        const disconnectOverlay = document.getElementById('disconnect-overlay');
        const fullscreenButton = document.getElementById('toggle-fullscreen');
        const exitViewerModeButton = document.getElementById('exit-viewer-mode');
        const fullscreenEnterIcon = document.getElementById('fullscreen-enter-icon');
        const fullscreenExitIcon = document.getElementById('fullscreen-exit-icon');
        const banner = document.getElementById('viewer-banner');
        const bannerTitle = document.getElementById('viewer-banner-title');
        const bannerMessage = document.getElementById('viewer-banner-message');
        let currentShareId = null;
        let currentImagePath = null;
        let currentNotificationId = null;
        let bannerHideTimeout = null;
        let hasEverConnected = false;
        let hasLoadedImageOnce = false;
        let isLoadingImage = false;
        let chromeHidden = false;

        function setChromeHidden(hidden) {
          chromeHidden = hidden;
          document.body.classList.toggle('chrome-hidden', hidden);
          fullscreenButton.classList.toggle('exit-mode', hidden);
          fullscreenEnterIcon.hidden = hidden;
          fullscreenExitIcon.hidden = !hidden;
          exitViewerModeButton.hidden = !hidden;
          fullscreenButton.setAttribute('aria-label', hidden ? 'Exit fullscreen' : 'Enter fullscreen');
        }

        function showLoading(message) {
          if (hasLoadedImageOnce) {
            loadingOverlay.hidden = true;
            return;
          }
          loadingLabel.textContent = message;
          loadingOverlay.hidden = false;
        }

        function hideLoading() {
          loadingOverlay.hidden = true;
        }

        function showDisconnectWarning(show) {
          disconnectOverlay.hidden = !show;
        }

        function showBanner(notification) {
          if (!notification || !notification.id) {
            if (bannerHideTimeout) {
              clearTimeout(bannerHideTimeout);
              bannerHideTimeout = null;
            }
            currentNotificationId = null;
            banner.hidden = true;
            return;
          }
          if (notification.id === currentNotificationId) {
            return;
          }
          currentNotificationId = notification.id;
          bannerTitle.textContent = notification.title || 'Automation';
          bannerMessage.textContent = notification.message || '';
          banner.hidden = false;
          if (bannerHideTimeout) {
            clearTimeout(bannerHideTimeout);
          }
          bannerHideTimeout = setTimeout(() => {
            banner.hidden = true;
          }, Math.max(500, (notification.durationSeconds || 3) * 1000));
        }

        function beginImageLoad(imagePath, loadingMessage) {
          if (!imagePath || isLoadingImage) {
            return;
          }

          isLoadingImage = true;
          const nextURL = `${imagePath}?t=${Date.now()}`;
          if (loadingMessage) {
            showLoading(loadingMessage);
          }

          const loader = new Image();
          loader.onload = () => {
            hasLoadedImageOnce = true;
            isLoadingImage = false;
            image.src = nextURL;
            hideLoading();
            showDisconnectWarning(false);
            status.textContent = 'Updated ' + new Date().toLocaleTimeString();
          };
          loader.onerror = () => {
            isLoadingImage = false;
            if (!hasLoadedImageOnce) {
              showLoading('Waiting for first render…');
              status.textContent = 'Waiting for first render…';
            } else {
              hideLoading();
              status.textContent = 'Waiting for updated render…';
            }
          };
          loader.src = nextURL;
        }

        setChromeHidden(false);

        fullscreenButton.addEventListener('click', async () => {
          const shouldHideChrome = !chromeHidden;
          setChromeHidden(shouldHideChrome);

          try {
            if (shouldHideChrome && !document.fullscreenElement && document.documentElement.requestFullscreen) {
              await document.documentElement.requestFullscreen();
            } else if (!shouldHideChrome && document.fullscreenElement) {
              await document.exitFullscreen();
            }
          } catch (_) {}
        });

        exitViewerModeButton.addEventListener('click', async () => {
          setChromeHidden(false);
          try {
            if (document.fullscreenElement) {
              await document.exitFullscreen();
            }
          } catch (_) {}
        });

        document.addEventListener('fullscreenchange', () => {
          if (!document.fullscreenElement && chromeHidden) {
            setChromeHidden(false);
          }
        });

        async function fetchState() {
          const response = await fetch('\(statePath)', { cache: 'no-store' });
          if (!response.ok) {
            throw new Error('state request failed');
          }
          return await response.json();
        }

        function applyState(state) {
          hasEverConnected = true;
          showDisconnectWarning(false);
          showBanner(state.notification);
          title.textContent = state.tabTitle;
          meta.textContent = state.deviceLabel;
          document.title = state.hasContent ? `${state.tabTitle} • Relay Viewer` : 'Relay Viewer';
          if (!state.hasContent || !state.imagePath) {
            currentShareId = null;
            currentImagePath = null;
            isLoadingImage = false;
            image.hidden = true;
            emptyState.hidden = false;
            hideLoading();
            status.textContent = 'Waiting for source tab…';
            return;
          }

          emptyState.hidden = true;
          image.hidden = false;
          image.alt = state.tabTitle;

          const imageChanged = state.shareId !== currentShareId || state.imagePath !== currentImagePath;
          currentShareId = state.shareId;
          currentImagePath = state.imagePath;
          if (imageChanged) {
            beginImageLoad(state.imagePath, hasLoadedImageOnce ? null : 'Loading current tab…');
          }
        }

        async function refreshViewer() {
          try {
            const state = await fetchState();
            applyState(state);
            if (state.hasContent && state.imagePath && !isLoadingImage) {
              beginImageLoad(state.imagePath, null);
            }
          } catch (_) {
            if (hasEverConnected) {
              showDisconnectWarning(true);
              hideLoading();
              status.textContent = 'Source disconnected';
            } else {
              showLoading('Connecting to source device…');
              status.textContent = 'Waiting for source device…';
            }
          }
        }
        refreshViewer();
        setInterval(refreshViewer, 1200);
      </script>
    </body>
    </html>
    """
}

private func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private func activeBrowserManifest() -> LANSharedTabManifest? {
    if let shareId = activeBrowserViewShareId,
       let match = localManifests.first(where: { $0.shareId == shareId }) {
        return match
    }
    return localManifests.first
}

private func currentBrowserViewerState(for shareId: String? = nil) -> BrowserViewerState {
    let manifest: LANSharedTabManifest?
    if let shareId,
       let exact = localManifests.first(where: { $0.shareId == shareId }) {
        manifest = exact
    } else {
        manifest = activeBrowserManifest()
    }

    guard let manifest else {
        return BrowserViewerState(
            shareId: nil,
            tabTitle: "Relay Viewer",
            deviceLabel: "No active tab selected",
            imagePath: nil,
            hasContent: false,
            notification: currentBrowserViewerNotificationState()
        )
    }

    return BrowserViewerState(
        shareId: manifest.shareId,
        tabTitle: manifest.tabName.isEmpty ? "Untitled Tab" : manifest.tabName,
        deviceLabel: manifest.deviceDisplayLabel,
        imagePath: "/sharedTabRender/\(manifest.shareId)",
        hasContent: true,
        notification: currentBrowserViewerNotificationState()
    )
}

private func currentBrowserViewerNotificationState() -> BrowserViewerNotificationState? {
    guard let active = browserViewerNotification else { return nil }
    if active.expiresAt <= Date() {
        browserViewerNotification = nil
        return nil
    }
    return BrowserViewerNotificationState(
        id: active.id,
        title: active.title,
        message: active.message,
        durationSeconds: active.durationSeconds
    )
}

// MARK: - Discovery

private func startBrowse() {
    let params = NWParameters.tcp
    params.includePeerToPeer = true

    let descriptor = Self.makeBrowseDescriptor(serviceType: config.serviceType, domain: config.serviceDomain)

    browser = NWBrowser(for: descriptor, using: params)

    browser?.stateUpdateHandler = { [weak self] state in
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .setup:
                self.browseStateText = "setup"
            case .ready:
                self.browseStateText = "ready"
                self.lastBrowseErrorText = ""
            case .waiting(let error):
                self.browseStateText = "waiting"
                self.lastBrowseErrorText = String(describing: error)
            case .failed(let error):
                self.browseStateText = "failed"
                self.lastBrowseErrorText = String(describing: error)
            case .cancelled:
                self.browseStateText = "cancelled"
            @unknown default:
                self.browseStateText = "unknown"
            }
        }
    }

    browser?.browseResultsChangedHandler = { [weak self] results, _ in
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastBrowseUpdateAt = Date()
            self.updatePeers(from: results)
        }
    }

    browser?.start(queue: .global(qos: .userInitiated))
}

/// Must request TXT records: plain `.bonjour` browsing always reports `metadata == .none`,
/// which silently made every peer's deviceId fall back to its Bonjour service name (the
/// computer's display name). Pairing trust was then saved under that name and never matched
/// the `X-Relay-Device-Id` the peer's requests actually carry.
nonisolated static func makeBrowseDescriptor(serviceType: String, domain: String) -> NWBrowser.Descriptor {
    .bonjourWithTXTRecord(type: serviceType, domain: domain)
}

private func updatePeers(from results: Set<NWBrowser.Result>) {
    for r in results {
        guard case let .service(name: serviceName, type: _, domain: _, interface: _) = r.endpoint else { continue }

        // Pull TXT record values if present.
        var txtDeviceId: String? = nil
        var txtDeviceName: String? = nil
        var txtEnabled: Bool? = nil
        var txtDeviceKind: LANDeviceKind? = nil
        var txtPairingRequired: Bool? = nil

        switch r.metadata {
        case .bonjour(let bonjour):
            // In this SDK, the associated value is the TXT record itself.
            txtDeviceId = bonjour[LANKeys.deviceId]
            txtDeviceName = bonjour[LANKeys.deviceName]
            if let v = bonjour[LANKeys.enabled] {
                txtEnabled = (v == "1" || v.lowercased() == "true")
            }
            if let v = bonjour[LANKeys.pairing] {
                txtPairingRequired = (v == "1" || v.lowercased() == "true")
            }
            if let raw = bonjour[LANKeys.deviceKind] {
                txtDeviceKind = LANDeviceKind(rawValue: raw)
            }
        default:
            break
        }

        // Filter out self (this is why a single device can show "Peers: 1")
        if let txtDeviceId, txtDeviceId == self.deviceId {
            continue
        }

        // Fallback: some OS versions do not expose TXT metadata for browse results.
        // If we can't read deviceId, still avoid counting our own advertised service.
        if txtDeviceId == nil {
            // Our listener advertises with name = deviceName.
            if serviceName == self.deviceName {
                continue
            }
        }

        // If the advertiser is explicitly disabled, ignore it.
        if let txtEnabled, txtEnabled == false {
            continue
        }

        let peerRequiresPairing = txtPairingRequired == true

        // Resolve service -> host/port
        let conn = NWConnection(to: r.endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                if let path = conn.currentPath,
                   let remote = path.remoteEndpoint,
                   case let .hostPort(host: host, port: port) = remote {

                    Task { @MainActor in
                        let peer = Peer(
                            endpointKey: "\(host):\(port)",
                            deviceId: txtDeviceId ?? serviceName,
                            deviceName: (txtDeviceName?.isEmpty == false ? txtDeviceName : serviceName),
                            deviceKind: txtDeviceKind,
                            requiresPairing: peerRequiresPairing,
                            host: host,
                            port: port,
                            lastSeen: Date()
                        )
                        self.mergePeer(peer)
                    }
                }
                conn.cancel()
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }
}

private func mergePeer(_ peer: Peer) {
    // Carry over trust saved by older builds under this peer's name rather than its deviceId.
    if let name = peer.deviceName {
        let migrated = DevicePairingStore.migratingLegacyNameKeyedEntry(
            toDeviceId: peer.deviceId,
            deviceName: name,
            deviceKind: peer.deviceKind,
            in: pairedDevices
        )
        if migrated != pairedDevices {
            pairedDevices = migrated
            DevicePairingStore.save(migrated)
        }
    }

    // Update or append
    if let idx = peers.firstIndex(where: { $0.endpointKey == peer.endpointKey }) {
        peers[idx] = peer
    } else {
        if peers.count < config.maxPeers {
            peers.append(peer)
        }
    }
    // New/updated peer — poll both endpoints so LAN and synced tabs appear quickly.
    guard pollingEnabled else { return }
    Task { [weak self] in
        await self?.pollPeersOnce()
        await self?.pollSyncedPeersOnce()
    }
}

// MARK: - Polling

private func pollPeersOnce() async {
    guard pollingEnabled else { return }
    guard !pollingOverrideDisabled else { return }
    // Snapshot peers to avoid main-thread mutation mid-loop
    let peersSnapshot = await MainActor.run { self.peers }

    // If polling was disabled while we awaited the snapshot, bail out.
    guard pollingEnabled else { return }

    await MainActor.run {
        guard self.pollingEnabled else { return }
        self.lastPollAt = Date()
        self.pollCount += 1

        let activeEndpointKeys = Set(peersSnapshot.map { $0.endpointKey })
        if !activeEndpointKeys.isEmpty {
            self.peerManifests = self.peerManifests.filter { activeEndpointKeys.contains($0.key) }
        }

        // Drop stale peers that haven’t been seen recently, along with their cached manifests
        // (mirror and synced), presence, and any auth-failure flag (so a different peer that
        // later reuses this same host:port endpointKey doesn't inherit a stale "Not authorized"
        // warning). Leaving synced manifests behind kept a gone host's groups "visible", so
        // joined tabs never orphaned. Pulled out into a pure function so this cleanup can be
        // tested directly without a live poll cycle.
        let cutoff = Date().addingTimeInterval(-self.config.peerStaleSeconds)
        let cleanup = Self.applyingStalePeerCleanup(
            peers: self.peers,
            peerManifests: self.peerManifests,
            peerSyncedManifests: self.peerSyncedManifests,
            peerPresence: self.peerPresence,
            authFailedPeerEndpointKeys: self.authFailedPeerEndpointKeys,
            cutoff: cutoff
        )
        self.peers = cleanup.peers
        self.peerManifests = cleanup.peerManifests
        self.authFailedPeerEndpointKeys = cleanup.authFailedPeerEndpointKeys
        if cleanup.removedAny {
            self.peerSyncedManifests = cleanup.peerSyncedManifests
            self.peerPresence = cleanup.peerPresence
            self.rebuildSyncedRemoteManifests()
        }

        if cleanup.removedAny || (!activeEndpointKeys.isEmpty && self.peerManifests.count < peersSnapshot.count) {
            self.rebuildRemoteTabs()
        }
    }

    for p in peersSnapshot {
        if disabledPeerEndpointKeys.contains(p.endpointKey) {
            continue
        }
        // Skip if port isn’t resolved yet
        guard let url = makePeerURL(host: p.host, port: p.port, path: "/sharedTabs") else {
            continue
        }
        let req = makePeerRequest(url: url)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let statusCode: Int = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode != 200 {
#if DEBUG
                if shouldLogPoll(for: p.endpointKey, isError: true) {
                    if let s = String(data: data, encoding: .utf8) {
                        let preview = String(s.prefix(220)).replacingOccurrences(of: "\n", with: " ")
                        print("🟥 LAN poll: \(p.endpointKey) /sharedTabs status=\(statusCode) preview: \(preview)")
                    } else {
                        print("🟥 LAN poll: \(p.endpointKey) /sharedTabs status=\(statusCode) received \(data.count) bytes")
                    }
                }
#endif
                await MainActor.run {
                    guard self.pollingEnabled else { return }
                    self.peerManifests.removeValue(forKey: p.endpointKey)
                    self.rebuildRemoteTabs()
                }
                continue
            }
            let manifests = try JSONDecoder().decode([LANSharedTabManifest].self, from: data)

#if DEBUG
            if shouldLogPoll(for: p.endpointKey, isError: false) {
                if manifests.isEmpty {
                    print("🟩 LAN poll: \(p.endpointKey) returned 0 manifests")
                } else {
                    let sample = manifests.prefix(3)
                    for m in sample {
                        let wStr = m.referenceCanvasWidth.map { String($0) } ?? "nil"
                        let hStr = m.referenceCanvasHeight.map { String($0) } ?? "nil"
                        print("🟩 LAN poll: \(p.endpointKey) device=\(m.deviceName) tab=\(m.tabName) shareId=\(m.shareId) ref=\(wStr)x\(hStr)")
                    }
                    let missing = manifests.filter { $0.referenceCanvasWidth == nil || $0.referenceCanvasHeight == nil }.count
                    if missing > 0 {
                        print("🟩 LAN poll: \(p.endpointKey) manifests missing ref canvas size: \(missing)/\(manifests.count)")
                    }
                }
            }
#endif

            await MainActor.run {
                guard self.pollingEnabled else { return }
                self.peerManifests[p.endpointKey] = manifests
                self.rebuildRemoteTabs()
            }
        } catch {
#if DEBUG
            if shouldLogPoll(for: p.endpointKey, isError: true) {
                print("🟥 LAN poll failed for \(p.endpointKey): \(error)")
            }
#endif
            await MainActor.run {
                guard self.pollingEnabled else { return }
                self.peerManifests.removeValue(forKey: p.endpointKey)
                self.rebuildRemoteTabs()
            }
        }
    }
}

private func pollSyncedPeersOnce() async {
    guard pollingEnabled else { return }
    guard !pollingOverrideDisabled else { return }
    let peersSnapshot = peers

    for p in peersSnapshot {
        if disabledPeerEndpointKeys.contains(p.endpointKey) { continue }
        let syncedTabsPath = joinedSyncGroupIDs.isEmpty
            ? "/syncedTabs"
            : "/syncedTabs?joined=\(joinedSyncGroupIDs.joined(separator: ","))"
        guard let url = makePeerURL(host: p.host, port: p.port, path: syncedTabsPath) else { continue }
        let req = makePeerRequest(url: url)

        let manifests: [SyncedTabManifest]
        var remoteLiveSubscribers: [String: Set<String>] = [:]
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else {
                peerSyncedManifests.removeValue(forKey: p.endpointKey)
                peerPresence.removeValue(forKey: p.endpointKey)
                rebuildSyncedRemoteManifests()
                continue
            }
            if let wrapped = try? JSONDecoder().decode(SyncedTabsResponse.self, from: data) {
                manifests = wrapped.manifests
                remoteLiveSubscribers = wrapped.liveSubscribersByGroupID ?? [:]
            } else {
                manifests = try JSONDecoder().decode([SyncedTabManifest].self, from: data)
            }
        } catch {
            peerSyncedManifests.removeValue(forKey: p.endpointKey)
            peerPresence.removeValue(forKey: p.endpointKey)
            rebuildSyncedRemoteManifests()
            continue
        }

        guard pollingEnabled else { return }
        peerSyncedManifests[p.endpointKey] = manifests
        rebuildSyncedRemoteManifests()

        // Adopt the host's live-subscriber report for any group we've joined — this is how a
        // subscriber device (not just the host) sees an accurate "who's here" list, since the
        // host is the only device that can actually observe inbound /syncedTabs polls.
        for (groupID, deviceIDs) in remoteLiveSubscribers where joinedSyncGroupIDs.contains(groupID) {
            liveSubscribersByGroupID[groupID] = deviceIDs
        }

        // Best-effort presence poll (separate endpoint, fails silently for peers without
        // support). Also serves as the auth-failure heartbeat for this peer: it's the only
        // gated route hit unconditionally on every fixed-interval poll cycle (not just when
        // local edits happen), so its status code is what drives authFailedPeerEndpointKeys /
        // hasAuthFailedSyncedTab now that /sharedTabs is intentionally un-gated (see
        // authFailureState's doc comment).
        if let presenceURL = makePeerURL(host: p.host, port: p.port, path: "/syncedPresence") {
            let presenceReq = makePeerRequest(url: presenceURL)
            if let (presenceData, presenceResp) = try? await URLSession.shared.data(for: presenceReq) {
                let presenceStatus = (presenceResp as? HTTPURLResponse)?.statusCode ?? -1
                switch Self.authFailureState(forPresencePollStatusCode: presenceStatus) {
                case true:
                    authFailedPeerEndpointKeys.insert(p.endpointKey)
                case false:
                    authFailedPeerEndpointKeys.remove(p.endpointKey)
                case nil:
                    break
                }
                if presenceStatus == 200, let payload = try? JSONDecoder().decode(SyncedPresencePayload.self, from: presenceData) {
                    peerPresence[p.endpointKey] = payload
                } else {
                    peerPresence.removeValue(forKey: p.endpointKey)
                }
            } else {
                peerPresence.removeValue(forKey: p.endpointKey)
            }
        }

        // Fallback resync: if this peer has a newer revision for a group we already hold
        // (either as host or as a joiner), fetch the full snapshot and queue it for DashboardRootView to apply.
        for m in manifests {
            guard localSyncedGroupIDs.contains(m.groupID) || joinedSyncGroupIDs.contains(m.groupID) else { continue }
            let localVersion = localSyncedSnapshotsByGroupID[m.groupID]?.version
            guard localVersion == nil || m.version > localVersion! else { continue }

            guard let snapshotURL = makePeerURL(host: p.host, port: p.port, path: "/syncedTab/\(m.groupID)") else { continue }
            let snapshotReq = makePeerRequest(url: snapshotURL)
            guard let (snapData, snapResp) = try? await URLSession.shared.data(for: snapshotReq),
                  (snapResp as? HTTPURLResponse)?.statusCode == 200,
                  let snapshot = try? JSONDecoder().decode(SyncedTabSnapshot.self, from: snapData)
            else { continue }

            guard pollingEnabled else { return }
            localSyncedSnapshotsByGroupID[m.groupID] = snapshot
            pendingSyncedSnapshots.append(snapshot)
        }
    }

    // Orphan detection: if a joined group disappears from all peers for enough consecutive polls,
    // mark orphaned. Groups just resumed from an autosaved document (unverifiedSyncGroupIDs) use a
    // much shorter threshold (~2 polls) since their displayed content hasn't been confirmed live
    // since the app restarted — a genuinely-gone host should surface the orphan banner quickly
    // instead of leaving stale content on screen under a "still synced" icon.
    let allVisibleGroupIDs = Set(peerSyncedManifests.values.flatMap { $0.map(\.groupID) })
    for groupID in joinedSyncGroupIDs {
        if allVisibleGroupIDs.contains(groupID) {
            let wasOrphaned = orphanedSyncGroupIDs.contains(groupID)
            let wasUnverified = unverifiedSyncGroupIDs.contains(groupID)
            consecutiveGroupMisses[groupID] = 0
            orphanedSyncGroupIDs.remove(groupID)
            unverifiedSyncGroupIDs.remove(groupID)
            if wasOrphaned || wasUnverified {
                // Host reappeared after being orphaned, OR this is the first live confirmation
                // after an app restart — either way the currently-displayed content may be stale
                // (an old autosaved snapshot, not what the host actually has now), so signal
                // DashboardRootView to force-fetch the authoritative snapshot rather than silently
                // leaving the outdated content on screen just because the "stale" badge cleared.
                reconnectedSyncGroupIDs.insert(groupID)
            }
        } else {
            let misses = (consecutiveGroupMisses[groupID] ?? 0) + 1
            consecutiveGroupMisses[groupID] = misses
            reconnectedSyncGroupIDs.remove(groupID)
            let missThreshold = unverifiedSyncGroupIDs.contains(groupID) ? 2 : 8
            if misses >= missThreshold {
                orphanedSyncGroupIDs.insert(groupID)
                unverifiedSyncGroupIDs.remove(groupID)
            }
        }
    }
}

private func pollLinkedVariablesOnce() async {
    guard pollingEnabled, !pollingOverrideDisabled else { return }
    let availableIDs = Set(peers.map(\.deviceId))
    for entry in LinkedDeviceVariableStore.shared.entries where !availableIDs.contains(entry.deviceID) {
        LinkedDeviceVariableStore.shared.disconnected(deviceID: entry.deviceID)
    }
    for peer in peers {
        guard !disabledPeerEndpointKeys.contains(peer.endpointKey),
              let pair = pairedDevices[peer.deviceId], pair.isEnabled, pair.sharesVariables else {
            LinkedDeviceVariableStore.shared.clear(deviceID: peer.deviceId)
            continue
        }
        guard let url = makePeerURL(host: peer.host, port: peer.port, path: "/linkedVariables/v1") else { continue }
        do {
            let (data, response) = try await URLSession.shared.data(for: makePeerRequest(url: url))
            guard pollingEnabled else { return }
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200:
                guard data.count <= 2_000_000,
                      let values = try? JSONDecoder().decode([LinkedDeviceVariable].self, from: data),
                      values.count <= 2_000 else {
                    LinkedDeviceVariableStore.shared.disconnected(deviceID: peer.deviceId)
                    continue
                }
                LinkedDeviceVariableStore.shared.receive(values, deviceID: peer.deviceId, deviceName: peer.deviceName ?? pair.deviceName)
            case 401, 403, 404:
                LinkedDeviceVariableStore.shared.clear(deviceID: peer.deviceId)
            default:
                LinkedDeviceVariableStore.shared.disconnected(deviceID: peer.deviceId)
            }
        } catch {
            LinkedDeviceVariableStore.shared.disconnected(deviceID: peer.deviceId)
        }
    }
}

private func pollSyncedVariablesOnce() async {
    guard pollingEnabled, !pollingOverrideDisabled else { return }
    for manifest in joinedSyncedManifests where joinedSyncGroupIDs.contains(manifest.groupID) {
        guard let peer = peers.first(where: { $0.deviceId == manifest.deviceID && !disabledPeerEndpointKeys.contains($0.endpointKey) }) else {
            SyncedTabVariableStore.shared.disconnected(groupID: manifest.groupID)
            continue
        }
        guard let baseURL = makePeerURL(host: peer.host, port: peer.port, path: "/syncedVariables/v1"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { continue }
        components.queryItems = [URLQueryItem(name: "groupID", value: manifest.groupID)]
        guard let url = components.url else { continue }
        do {
            let (data, response) = try await URLSession.shared.data(for: makePeerRequest(url: url))
            guard pollingEnabled else { return }
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200:
                guard data.count <= 1_000_000,
                      let values = try? JSONDecoder().decode([LinkedDeviceVariable].self, from: data),
                      values.count <= 500 else {
                    SyncedTabVariableStore.shared.disconnected(groupID: manifest.groupID)
                    continue
                }
                SyncedTabVariableStore.shared.receive(values, groupID: manifest.groupID, tabName: manifest.tabName, deviceName: manifest.deviceName)
            case 401, 403, 404:
                SyncedTabVariableStore.shared.clear(groupID: manifest.groupID)
            default:
                SyncedTabVariableStore.shared.disconnected(groupID: manifest.groupID)
            }
        } catch {
            SyncedTabVariableStore.shared.disconnected(groupID: manifest.groupID)
        }
    }
}

private func shouldLogPoll(for endpointKey: String, isError: Bool) -> Bool {
    guard debugLoggingEnabled else { return false }
    let key = endpointKey + (isError ? "|err" : "|ok")
    let now = Date()
    if let last = lastPollLogAtByKey[key], now.timeIntervalSince(last) < pollLogIntervalSeconds {
        return false
    }
    lastPollLogAtByKey[key] = now
    return true
}

// MARK: - Peer Networking Helper

private func makePeerURL(host: NWEndpoint.Host, port: NWEndpoint.Port, path: String) -> URL? {
    var hostString = String(describing: host)

    // If the host is IPv6, it must be wrapped in brackets for a valid URL.
    if hostString.contains(":") && !hostString.hasPrefix("[") {
        hostString = "[\(hostString)]"
    }

    // Ensure path begins with '/'
    let normalizedPath = path.hasPrefix("/") ? path : "/" + path
    return URL(string: "http://\(hostString):\(port)\(normalizedPath)")
}

nonisolated static func signingTarget(for url: URL) -> String {
    guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
    return c.percentEncodedPath + (c.percentEncodedQuery.map { "?\($0)" } ?? "")
}

/// Finds which discovered peer a request URL targets, so the right pairing secret is used.
private func peerDeviceId(for url: URL) -> String? {
    guard let host = url.host, let port = url.port else { return nil }
    let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    return peers.first { String(describing: $0.host) == bare && Int($0.port.rawValue) == port }?.deviceId
}

private func makePeerRequest(
    url: URL,
    method: String = "GET",
    body: Data? = nil,
    contentType: String? = nil
) -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.httpBody = body
    if let contentType {
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }

    // Identify ourselves so the peer can check our deviceId against its trusted device list.
    req.setValue(deviceId, forHTTPHeaderField: "X-Relay-Device-Id")

    if let peerId = peerDeviceId(for: url), let secret = pairingSecretStore.secret(for: peerId) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let nonce = UUID().uuidString
        let target = Self.signingTarget(for: url)
        let sig = LANRequestSigner.signature(secret: secret, method: method, target: target,
                                             timestamp: timestamp, nonce: nonce, body: body ?? Data())
        req.setValue(String(timestamp), forHTTPHeaderField: "X-Relay-Timestamp")
        req.setValue(nonce, forHTTPHeaderField: "X-Relay-Nonce")
        req.setValue(sig, forHTTPHeaderField: "X-Relay-Signature")
    }

    // Older Relay hosts do not understand per-device trust headers. Retain the legacy
    // shared-code headers when the user has configured a code for mixed-version networks.
    if let code = UserDefaults.standard.string(forKey: "lan_pairing_code"), !code.isEmpty {
        req.setValue(code, forHTTPHeaderField: "X-Relay-Pairing")
        req.setValue(code, forHTTPHeaderField: "X-Prodlink-Pairing")
        req.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
    }

    return req
}

private func rebuildRemoteTabs() {
    // Flatten all peer manifests, but de-duplicate by (deviceId + tabName).
    // This prevents repeated polls or changing shareIds from creating multiple “LAN tabs”
    // for the same logical dashboard tab.
    var bestByCanonicalKey: [String: LANSharedTabManifest] = [:]
    var ownerByShareId: [String: String] = [:]

    func canonicalKey(for m: LANSharedTabManifest) -> String {
        "\(m.deviceId)|\(m.tabName)"
    }

    for (endpointKey, list) in peerManifests {
        if disabledPeerEndpointKeys.contains(endpointKey) { continue }
        for m in list {
            // Filter dismissed: hide only if hash matches what we dismissed for this shareId.
            if let h = dismissed[m.shareId], h == m.hash {
                continue
            }

            let key = canonicalKey(for: m)

            if let existing = bestByCanonicalKey[key] {
                if m.updatedAt >= existing.updatedAt {
                    bestByCanonicalKey[key] = m
                    ownerByShareId[m.shareId] = endpointKey
                }
            } else {
                bestByCanonicalKey[key] = m
                ownerByShareId[m.shareId] = endpointKey
            }
        }
    }

    // Publish owner map for imports (by the *current* shareId for each canonical tab)
    // Rebuild it from the chosen manifests so stale shareIds don’t stick around.
    var chosenOwners: [String: String] = [:]
    for (endpointKey, list) in peerManifests {
        if disabledPeerEndpointKeys.contains(endpointKey) { continue }
        for m in list {
            let key = canonicalKey(for: m)
            guard let chosen = bestByCanonicalKey[key], chosen.shareId == m.shareId else { continue }
            chosenOwners[m.shareId] = endpointKey
        }
    }
    shareIdOwnerEndpointKey = chosenOwners

    // Sort stable: by device then tabName
    var all = Array(bestByCanonicalKey.values)
    all.sort {
        if $0.deviceName != $1.deviceName { return $0.deviceName < $1.deviceName }
        return $0.tabName < $1.tabName
    }

    remoteTabs = all
}

private func rebuildSyncedRemoteManifests() {
    // Flatten all peer-advertised synced-tab manifests, keeping the newest version per groupID.
    // ownerByGroupID is populated for ALL remote groups (including already-joined ones) so that
    // peerBaseURL(for:) can resolve the host URL for file proxy fetches.
    var bestByGroupID: [String: SyncedTabManifest] = [:]
    var ownerByGroupID: [String: String] = [:]

    for (endpointKey, list) in peerSyncedManifests {
        if disabledPeerEndpointKeys.contains(endpointKey) { continue }
        for m in list {
            if localSyncedGroupIDs.contains(m.groupID) { continue }
            if m.deviceID == deviceId { continue }  // never show our own tabs as joinable
            if let existing = bestByGroupID[m.groupID] {
                if m.version > existing.version {
                    bestByGroupID[m.groupID] = m
                    ownerByGroupID[m.groupID] = endpointKey
                }
            } else {
                bestByGroupID[m.groupID] = m
                ownerByGroupID[m.groupID] = endpointKey
            }
        }
    }

    syncedGroupOwnerEndpointKey = ownerByGroupID

    // Track what version the host is advertising for each joined group (for missed-push detection).
    var joinedPeerVersions: [String: SyncedTabVersion] = [:]
    for (_, list) in peerSyncedManifests {
        for m in list {
            guard joinedSyncGroupIDs.contains(m.groupID) else { continue }
            if let existing = joinedPeerVersions[m.groupID] {
                if m.version > existing { joinedPeerVersions[m.groupID] = m.version }
            } else {
                joinedPeerVersions[m.groupID] = m.version
            }
        }
    }
    peerVersionsForJoinedGroups = joinedPeerVersions

    // Exclude already-joined groups from the "available to join" list — EXCEPT orphaned ones,
    // which should reappear in the sync button so the user can reconnect.
    var all = Array(bestByGroupID.values.filter {
        !joinedSyncGroupIDs.contains($0.groupID) || orphanedSyncGroupIDs.contains($0.groupID)
    })
    all.sort {
        if $0.deviceName != $1.deviceName { return $0.deviceName < $1.deviceName }
        return $0.tabName < $1.tabName
    }
    syncedRemoteManifests = all
}


// MARK: - Exported Tab JSON Helpers

/// Best-effort extraction of a reference canvas size from the exported tab JSON.
/// This allows LAN manifests to advertise the same coordinate space the tab was authored/exported with,
/// preventing mirror clipping when the peer's window/screen size differs.
private static func extractReferenceCanvasSize(from exportedTabJSON: Data) -> CGSize? {
    // We intentionally use JSONSerialization to avoid depending on DashboardTab types.
    guard
        let obj = try? JSONSerialization.jsonObject(with: exportedTabJSON, options: []),
        let dict = obj as? [String: Any]
    else {
        return nil
    }

    func cgSizeFrom(width: Any?, height: Any?) -> CGSize? {
        let w = (width as? NSNumber)?.doubleValue ?? (width as? Double) ?? (width as? Int).map(Double.init)
        let h = (height as? NSNumber)?.doubleValue ?? (height as? Double) ?? (height as? Int).map(Double.init)
        guard let w, let h, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    // 1) Direct numeric fields
    if let s = cgSizeFrom(width: dict["referenceCanvasWidth"], height: dict["referenceCanvasHeight"]) { return s }
    if let s = cgSizeFrom(width: dict["canvasWidth"], height: dict["canvasHeight"]) { return s }

    // 2) Nested objects like { referenceCanvasSize: { width, height } }
    if let rc = dict["referenceCanvasSize"] as? [String: Any] {
        if let s = cgSizeFrom(width: rc["width"], height: rc["height"]) { return s }
    }
    if let cs = dict["canvasSize"] as? [String: Any] {
        if let s = cgSizeFrom(width: cs["width"], height: cs["height"]) { return s }
    }

    // 3) Some encoders may store as an array [w, h]
    if let arr = dict["referenceCanvasSize"] as? [Any], arr.count >= 2 {
        if let s = cgSizeFrom(width: arr[0], height: arr[1]) { return s }
    }
    if let arr = dict["canvasSize"] as? [Any], arr.count >= 2 {
        if let s = cgSizeFrom(width: arr[0], height: arr[1]) { return s }
    }

    return nil
}

// MARK: - Hash helper

private static func sha256Hex(_ data: Data) -> String {
    #if canImport(CryptoKit)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
    #else
    return data.base64EncodedString()
    #endif
}

// MARK: - Auth-failure classification

/// Classifies a /syncedPresence poll's response status for auth-failure purposes. This is
/// the only route still gated by isAuthorized() that's hit on every fixed-interval poll cycle
/// for a peer with joined synced groups (see pollSyncedPeersOnce), which makes it the right
/// signal for detecting a host-side trust revocation independent of local activity -- unlike
/// the routes /syncedTab/{groupID} and /syncedTab/push, which only fire when there's actually
/// something to fetch or push.
///
/// Returns true if the peer is rejecting us (401/403), false if it accepts us (200, or 204
/// meaning "authorized but nothing to report"), or nil if inconclusive (any other status, or
/// the request didn't complete) -- callers should leave authFailedPeerEndpointKeys unchanged
/// on nil, so a transient network blip doesn't flip the "Not authorized" warning on and off.
static func authFailureState(forPresencePollStatusCode statusCode: Int) -> Bool? {
    if statusCode == 401 || statusCode == 403 { return true }
    if statusCode == 200 || statusCode == 204 { return false }
    return nil
}

// MARK: - Stale-peer cleanup

/// Computes updated peers/peerManifests/authFailedPeerEndpointKeys after dropping any peer
/// not seen since `cutoff`. Pure and side-effect-free so pollPeersOnce()'s stale-peer cleanup
/// -- removing a stale peer, its cached manifest, and its auth-failure flag together -- can be
/// tested directly without needing a live polling cycle.
static func applyingStalePeerCleanup(
    peers: [Peer],
    peerManifests: [String: [LANSharedTabManifest]],
    peerSyncedManifests: [String: [SyncedTabManifest]] = [:],
    peerPresence: [String: SyncedPresencePayload] = [:],
    authFailedPeerEndpointKeys: Set<String>,
    cutoff: Date
) -> (
    peers: [Peer],
    peerManifests: [String: [LANSharedTabManifest]],
    peerSyncedManifests: [String: [SyncedTabManifest]],
    peerPresence: [String: SyncedPresencePayload],
    authFailedPeerEndpointKeys: Set<String>,
    removedAny: Bool
) {
    let stale = peers.filter { $0.lastSeen < cutoff }
    guard !stale.isEmpty else {
        return (peers, peerManifests, peerSyncedManifests, peerPresence, authFailedPeerEndpointKeys, false)
    }

    var newPeers = peers
    newPeers.removeAll { $0.lastSeen < cutoff }

    var newManifests = peerManifests
    var newSyncedManifests = peerSyncedManifests
    var newPresence = peerPresence
    var newAuthFailed = authFailedPeerEndpointKeys
    for dead in stale {
        newManifests.removeValue(forKey: dead.endpointKey)
        newSyncedManifests.removeValue(forKey: dead.endpointKey)
        newPresence.removeValue(forKey: dead.endpointKey)
        newAuthFailed.remove(dead.endpointKey)
    }

    return (newPeers, newManifests, newSyncedManifests, newPresence, newAuthFailed, true)
}

    // MARK: - Device Kind Helper

    private static var currentDeviceKind: LANDeviceKind {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return .iphone
        case .pad: return .ipad
        default: return .unknown
        }
        #elseif os(macOS)
        // Heuristic: if the device name contains "MacBook", treat as laptop
        let name = Host.current().localizedName?.lowercased() ?? ""
        if name.contains("macbook") { return .macbook }
        return .mac
        #else
        return .unknown
        #endif
    }
}

// MARK: - URLRequest Helper

private extension URLRequest {
    func withJSONBody(_ body: Data, method: String) -> URLRequest {
        var req = self
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }
}
