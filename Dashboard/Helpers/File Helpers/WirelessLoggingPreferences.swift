//
//  WirelessLoggingPreferences.swift
//  Relay
//
//  Gates verbose Shure / Sennheiser diagnostic logging by device family.
//  Builds with Preview features enabled default to ON for the families we're actively
//  developing against; builds without Preview features suppress all verbose logging
//  unconditionally to keep the main thread free from RelayDiagnosticsStore
//  pressure on busy dashboards.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class WirelessLoggingPreferences: ObservableObject {
    static let shared = WirelessLoggingPreferences()

    enum ShureFamily: String, CaseIterable, Identifiable {
        case anx4 = "ANX4"
        case adtq = "ADTQ"
        case adtd = "ADTD"
        case ad4Series = "AD4 Series"
        case ulxd = "ULX-D"
        case qlxd = "QLX-D"
        case slxd = "SLX-D"
        case psm1000 = "PSM 1000"
        case other = "Other / Unknown"

        nonisolated var id: String { rawValue }

        nonisolated var defaultEnabled: Bool {
            switch self {
            case .anx4, .adtq, .adtd:
                return true
            default:
                return false
            }
        }

        fileprivate nonisolated var storageKey: String { "wireless_log_shure_\(rawValue)" }
    }

    enum SennheiserFamily: String, CaseIterable, Identifiable {
        case ewdx = "EW-DX"
        case digital6000 = "Digital 6000"
        case spectera = "Spectera"
        case ewdAndIem = "EW-D / IEM"
        case other = "Other / Unknown"

        nonisolated var id: String { rawValue }

        nonisolated var defaultEnabled: Bool { true }

        fileprivate nonisolated var storageKey: String { "wireless_log_sennheiser_\(rawValue)" }
    }

    fileprivate nonisolated static let masterShureKey = "wireless_log_shure_master"
    fileprivate nonisolated static let masterSennheiserKey = "wireless_log_sennheiser_master"

    @Published var shureMasterEnabled: Bool {
        didSet { UserDefaults.standard.set(shureMasterEnabled, forKey: Self.masterShureKey) }
    }

    @Published var sennheiserMasterEnabled: Bool {
        didSet { UserDefaults.standard.set(sennheiserMasterEnabled, forKey: Self.masterSennheiserKey) }
    }

    @Published private var shureFamilyState: [ShureFamily: Bool]
    @Published private var sennheiserFamilyState: [SennheiserFamily: Bool]

    private init() {
        let defaults = UserDefaults.standard
        let isBetaOrDebug = Self.isBetaOrDebugBuild

        if defaults.object(forKey: Self.masterShureKey) == nil {
            defaults.set(isBetaOrDebug, forKey: Self.masterShureKey)
        }
        if defaults.object(forKey: Self.masterSennheiserKey) == nil {
            defaults.set(isBetaOrDebug, forKey: Self.masterSennheiserKey)
        }

        self.shureMasterEnabled = defaults.bool(forKey: Self.masterShureKey)
        self.sennheiserMasterEnabled = defaults.bool(forKey: Self.masterSennheiserKey)

        var shureMap: [ShureFamily: Bool] = [:]
        for family in ShureFamily.allCases {
            if defaults.object(forKey: family.storageKey) == nil {
                defaults.set(family.defaultEnabled, forKey: family.storageKey)
            }
            shureMap[family] = defaults.bool(forKey: family.storageKey)
        }
        self.shureFamilyState = shureMap

        var sennMap: [SennheiserFamily: Bool] = [:]
        for family in SennheiserFamily.allCases {
            if defaults.object(forKey: family.storageKey) == nil {
                defaults.set(family.defaultEnabled, forKey: family.storageKey)
            }
            sennMap[family] = defaults.bool(forKey: family.storageKey)
        }
        self.sennheiserFamilyState = sennMap
    }

    // MARK: - Nonisolated hot-path queries
    //
    // These read straight from `UserDefaults` (thread-safe) so they can be
    // invoked from NWConnection callbacks and other off-main contexts
    // without crossing the MainActor boundary on every packet.

    /// True when verbose Shure logging is enabled for this device's family.
    /// Always false in release builds.
    nonisolated static func isVerboseShure(forModel identifier: String?) -> Bool {
        guard isBetaOrDebugBuild else { return false }
        let defaults = UserDefaults.standard
        let masterStored = defaults.object(forKey: masterShureKey) as? Bool ?? true
        guard masterStored else { return false }
        let family = resolveShureFamily(from: identifier)
        return defaults.object(forKey: family.storageKey) as? Bool ?? family.defaultEnabled
    }

    /// True when verbose Sennheiser logging is enabled for this device's family.
    nonisolated static func isVerboseSennheiser(forModel identifier: String?) -> Bool {
        guard isBetaOrDebugBuild else { return false }
        let defaults = UserDefaults.standard
        let masterStored = defaults.object(forKey: masterSennheiserKey) as? Bool ?? true
        guard masterStored else { return false }
        let family = resolveSennheiserFamily(from: identifier)
        return defaults.object(forKey: family.storageKey) as? Bool ?? family.defaultEnabled
    }

    /// Master-only check for sites with no device in scope.
    nonisolated static var shureMasterVerbose: Bool {
        guard isBetaOrDebugBuild else { return false }
        return UserDefaults.standard.object(forKey: masterShureKey) as? Bool ?? true
    }

    nonisolated static var sennheiserMasterVerbose: Bool {
        guard isBetaOrDebugBuild else { return false }
        return UserDefaults.standard.object(forKey: masterSennheiserKey) as? Bool ?? true
    }

    // Computed once at launch: verbose wireless logging requires the Preview switch (restart required).
    // The key below deliberately duplicates RelayBuildConfig.previewFeaturesKey because this
    // nonisolated helper cannot reference the MainActor-isolated config type. A test pins them equal.
    nonisolated static let isBetaOrDebugBuild: Bool = {
        UserDefaults.standard.bool(forKey: "relay_preview_features_enabled")
    }()

    // MARK: - UI helpers (MainActor)

    func isFamilyEnabled(_ family: ShureFamily) -> Bool {
        shureFamilyState[family] ?? family.defaultEnabled
    }

    func setFamilyEnabled(_ family: ShureFamily, _ enabled: Bool) {
        shureFamilyState[family] = enabled
        UserDefaults.standard.set(enabled, forKey: family.storageKey)
    }

    func isFamilyEnabled(_ family: SennheiserFamily) -> Bool {
        sennheiserFamilyState[family] ?? family.defaultEnabled
    }

    func setFamilyEnabled(_ family: SennheiserFamily, _ enabled: Bool) {
        sennheiserFamilyState[family] = enabled
        UserDefaults.standard.set(enabled, forKey: family.storageKey)
    }

    func resetShureToDefaults() {
        for family in ShureFamily.allCases {
            setFamilyEnabled(family, family.defaultEnabled)
        }
    }

    func resetSennheiserToDefaults() {
        for family in SennheiserFamily.allCases {
            setFamilyEnabled(family, family.defaultEnabled)
        }
    }

    // MARK: - Family resolution

    nonisolated static func resolveShureFamily(from identifier: String?) -> ShureFamily {
        let model = (identifier ?? "").uppercased()
        // Order matters: ANX4 / ADTQ / ADTD checked before broader AD4 match.
        if model.contains("ANX4") { return .anx4 }
        if model.contains("ADTQ") { return .adtq }
        if model.contains("ADTD") { return .adtd }
        if model.contains("AD4") { return .ad4Series }
        if model.contains("ULXD") { return .ulxd }
        if model.contains("QLXD") { return .qlxd }
        if model.contains("SLXD") { return .slxd }
        if model.contains("P10T") || model.contains("PSM1000") { return .psm1000 }
        return .other
    }

    nonisolated static func resolveSennheiserFamily(from identifier: String?) -> SennheiserFamily {
        let model = (identifier ?? "").uppercased()
        if model.contains("EW-DX") || model.contains("EWDX") { return .ewdx }
        if model.contains("EM 6000") || model.contains("EM6000") || model.contains("DIGITAL 6000") {
            return .digital6000
        }
        if model.contains("SPECTERA") { return .spectera }
        if model.contains("EW G") || model.contains("EW-G") || model.contains("IEM") {
            return .ewdAndIem
        }
        return .other
    }
}
