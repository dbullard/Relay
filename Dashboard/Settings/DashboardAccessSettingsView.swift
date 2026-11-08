//
//  DashboardAccessSettingsView.swift
//  Relay
//
//  Created by Codex on 3/4/26.
//

import SwiftUI
import AVFoundation
import Speech
#if os(macOS)
import AppKit
#endif

struct DashboardAccessSettingsView: View {
    private struct PermissionRow: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let status: PermissionStatus
        let showsSettingsButton: Bool
        let showsStatusIcon: Bool
    }

    private enum PermissionStatus {
        case authorized
        case denied
        case restricted
        case notDetermined
        case requiresReview

        var label: String {
            switch self {
            case .authorized: return "Authorized"
            case .denied: return "Denied"
            case .restricted: return "Restricted"
            case .notDetermined: return "Not determined"
            case .requiresReview: return "Review in Settings"
            }
        }

        var color: Color {
            switch self {
            case .authorized: return .green
            case .denied: return .red
            case .restricted: return .orange
            case .notDetermined: return .secondary
            case .requiresReview: return .secondary
            }
        }

        var iconName: String {
            switch self {
            case .authorized: return "checkmark.circle.fill"
            case .denied: return "xmark.circle.fill"
            case .restricted: return "exclamationmark.triangle.fill"
            case .notDetermined: return "questionmark.circle.fill"
            case .requiresReview: return "questionmark.circle.fill"
            }
        }
    }

    @ObservedObject private var usageDiagnosticsPreferences = UsageDiagnosticsPreferences.shared
    @State private var rows: [PermissionRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Access")
                .font(.title2.bold())

            Text("Review permissions granted to Relay on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 32, height: 32)
                                Image(systemName: row.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }

                            Text(row.title)
                                .font(.body)

                            Spacer()

                            Text(row.status.label)
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            if row.showsStatusIcon {
                                Image(systemName: row.status.iconName)
                                    .foregroundStyle(row.status.color)
                                    .imageScale(.medium)
                            }

#if os(macOS)
                            if row.showsSettingsButton {
                                Button {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                                .buttonStyle(.borderless)
                                .help("Open Local Network Settings")
                            }
#endif
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            GroupBox("Crash and Usage Diagnostics") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Share Crash and Usage Diagnostics",
                        isOn: Binding(
                            get: { usageDiagnosticsPreferences.isEnabled },
                            set: { usageDiagnosticsPreferences.setEnabled($0) }
                        )
                    )

                    Text("Relay shares app version, platform, a random installation ID, active time, and technical crash details. It does not include dashboard content, connected-device data, location, audio, or Relay network addresses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)


                    HStack(spacing: 12) {
                        Link("Privacy Policy", destination: RelayBuildConfig.privacyPolicyURL)
                        Link("Terms & Conditions", destination: RelayBuildConfig.termsURL)
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 6)
            }

            Spacer()
        }
        .padding(24)
        .onAppear(perform: refreshPermissions)
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
#endif
    }

    private func refreshPermissions() {
        let micStatus = mapAudioStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        let speechStatus = mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
        rows = [
            PermissionRow(title: "Microphone", systemImage: "mic.fill", status: micStatus, showsSettingsButton: false, showsStatusIcon: true),
            PermissionRow(title: "Speech Recognition", systemImage: "waveform", status: speechStatus, showsSettingsButton: false, showsStatusIcon: true)
        ]
#if os(macOS)
        rows.append(
            PermissionRow(
                title: "Local Network",
                systemImage: "wifi",
                status: .requiresReview,
                showsSettingsButton: true,
                showsStatusIcon: false
            )
        )
#endif
    }

    private func mapAudioStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }



}
