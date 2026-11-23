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
    /// Optional button (e.g. "Review"). Without one the banner never takes clicks or taps.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    private var hasAction: Bool { actionTitle != nil && action != nil }

    private var minimumActionHitSize: CGFloat {
        #if os(macOS)
        28
        #else
        44
        #endif
    }

    var body: some View {
        if isVisible, let text {
            VStack {
                Spacer()

                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text(text)
                            .font(.headline)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let actionTitle, let action {
                        Button(action: action) {
                            Text(actionTitle)
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: minimumActionHitSize)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThickMaterial)
                .clipShape(.rect(cornerRadius: 12))
                .shadow(radius: 8)
                // Only an actionable banner takes input; the transparent space around it never does.
                .allowsHitTesting(hasAction)
                .accessibilityElement(children: hasAction ? .contain : .combine)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, bottomPadding)
            .transition(.opacity)
            .zIndex(10_000)
        }
    }
}
