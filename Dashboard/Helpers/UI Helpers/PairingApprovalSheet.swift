//
//  PairingApprovalSheet.swift
//  Relay
//
//  Host-side approval prompt for an incoming device-pairing request. Presented
//  at the root view level (see DashboardRootView) so it appears regardless of
//  what screen the host is currently on, matching the existing orphan-banner
//  pattern.
//

import SwiftUI

struct PairingApprovalSheet: View {
    let request: PendingPairingRequest
    var shortAuthString: String? = nil
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: LANDeviceKind.iconName(for: request.payload.deviceKind, fallbackDeviceName: request.payload.deviceName))
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\"\(request.payload.deviceName)\" wants to pair")
                        .font(.headline)
                    Text("Requesting to \(request.payload.reason).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Review this device before allowing Relay sharing.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let code = shortAuthString {
                VStack(spacing: 4) {
                    Text("Confirm this code matches the other computer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    onDeny()
                } label: {
                    Text("Deny").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onApprove()
                } label: {
                    Text("Approve").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
        .interactiveDismissDisabled()
        .presentationSizing(.fitted)
    }
}
