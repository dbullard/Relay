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
#else
import UIKit
#endif

struct DashboardAccessSettingsView: View {
    private struct PermissionRow: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let status: PermissionStatus
        let showsSettingsButton: Bool
        let showsStatusIcon: Bool
        /// macOS System Settings privacy pane for this permission.
        var privacyPane: String? = nil

        /// A denied permission can only be re-granted in System Settings, so the row
        /// offers a way there. Local Network has no readable status, so it always does.
        var offersSettingsButton: Bool {
            showsSettingsButton || status == .denied
        }
    }

    @Environment(\.openURL) private var openURL

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
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 32, height: 32)
                                Image(systemName: row.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.9))
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

                            if row.offersSettingsButton, let url = settingsURL(for: row) {
                                Button("Open System Settings") {
                                    openURL(url)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityHint("Opens the \(row.title) privacy settings, where you can allow Relay.")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
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
            PermissionRow(title: "Microphone", systemImage: "mic.fill", status: micStatus, showsSettingsButton: false, showsStatusIcon: true, privacyPane: "Privacy_Microphone"),
            PermissionRow(title: "Speech Recognition", systemImage: "waveform", status: speechStatus, showsSettingsButton: false, showsStatusIcon: true, privacyPane: "Privacy_SpeechRecognition")
        ]
#if os(macOS)
        rows.append(
            PermissionRow(
                title: "Local Network",
                systemImage: "wifi",
                status: .requiresReview,
                showsSettingsButton: true,
                showsStatusIcon: false,
                privacyPane: "Privacy_LocalNetwork"
            )
        )
#endif
    }

    /// macOS opens the permission's privacy pane; iOS can only open Relay's own page in
    /// the Settings app, which lists its permissions.
    private func settingsURL(for row: PermissionRow) -> URL? {
#if os(macOS)
        guard let pane = row.privacyPane else { return nil }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
#else
        return URL(string: UIApplication.openSettingsURLString)
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
