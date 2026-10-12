//
//  DashboardModeBannerOverlay.swift
//  Relay
//
//  Reusable overlay banner for showing mode/status messages.
//

import SwiftUI

struct DashboardModeBannerOverlay: View {
    let isVisible: Bool
    let text: String?
    let subtitle: String?
    var bottomPadding: CGFloat = 86

    var body: some View {
        if isVisible, let text {
            VStack {
                Spacer()

                VStack(spacing: 4) {
                    Text(text)
                        .font(.headline)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThickMaterial)
                .clipShape(.rect(cornerRadius: 12))
                .shadow(radius: 8)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, bottomPadding)
            .allowsHitTesting(false)
            .transition(.opacity)
            .zIndex(10_000)
        }
    }
}
