//
//  ColorSchemePreference.swift
//  Relay
//

import SwiftUI

/// Backs the "Appearance" setting in General settings (`GeneralDashboardSettingsPane`)
/// and is read directly by `RelayDashboardApp` to apply `.preferredColorScheme(_:)`
/// app-wide. Stored as a raw `String` under `@AppStorage("dashboard_colorSchemePreference")`.
enum ColorSchemePreference: String, CaseIterable {
    case light
    case dark
    case system

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}
