import SwiftUI

/// Thin wrapper around DashboardCanvasSizePromptView for use from the launch screen.
struct LaunchNewDashboardSheet: View {
    let onCreate: (CGSize) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DashboardCanvasBoundsStore.shared
    @State private var isPresented = true

    var body: some View {
        DashboardCanvasSizePromptView(
            store: store,
            isPresented: $isPresented,
            purpose: .newDashboard,
            onResetToDocumentDefault: nil
        ) { size in
            onCreate(size)
        }
        .onAppear {
            store.seedPromptFromCurrentCanvas(
                width: 1920,
                height: 1080,
                defaultPresetID: "builtin:p1920x1080"
            )
        }
        .onChange(of: isPresented) { _, shown in
            if !shown { dismiss() }
        }
    }
}
