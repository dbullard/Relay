//
//  DashboardExportKey.swift
//  Relay
//
//  Created by David Bullard on 11/21/25.
//


// DashboardFocusedValues.swift

import SwiftUI

private struct DashboardExportKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var isExportingDashboard: Binding<Bool>? {
        get { self[DashboardExportKey.self] }
        set { self[DashboardExportKey.self] = newValue }
    }
}

private struct DashboardTextInputActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct DashboardLANSnapshotRenderingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct DashboardPCOConfigOpenKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct DashboardWebpageViewportBypassActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct DashboardSetWebpageViewportBypassKey: EnvironmentKey {
    static let defaultValue: (UUID?, Bool) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var dashboardIsTextInputActive: Bool {
        get { self[DashboardTextInputActiveKey.self] }
        set { self[DashboardTextInputActiveKey.self] = newValue }
    }

    var dashboardIsLANSnapshotRendering: Bool {
        get { self[DashboardLANSnapshotRenderingKey.self] }
        set { self[DashboardLANSnapshotRenderingKey.self] = newValue }
    }

    var dashboardIsPCOConfigOpen: Bool {
        get { self[DashboardPCOConfigOpenKey.self] }
        set { self[DashboardPCOConfigOpenKey.self] = newValue }
    }

    var dashboardIsWebpageViewportBypassActive: Bool {
        get { self[DashboardWebpageViewportBypassActiveKey.self] }
        set { self[DashboardWebpageViewportBypassActiveKey.self] = newValue }
    }

    var dashboardSetWebpageViewportBypass: (UUID?, Bool) -> Void {
        get { self[DashboardSetWebpageViewportBypassKey.self] }
        set { self[DashboardSetWebpageViewportBypassKey.self] = newValue }
    }
}
