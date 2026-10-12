//
//  PairingWaitingOverlay.swift
//  Relay
//
//  Joiner-side "waiting for approval" state, shown while an outgoing pairing
//  request (LANSharedTabsService.activePairingRequest) is in flight.
//

import SwiftUI

struct PairingWaitingOverlay: View {
    let request: LANSharedTabsService.OutgoingPairingRequest
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            Text("Waiting for approval on \(request.peerDeviceName)…")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Requesting to \(request.reason) — approve the request on \(request.peerDeviceName) to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let code = request.shortAuthString {
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

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding(28)
        .frame(width: 320)
        .presentationSizing(.fitted)
    }
}
