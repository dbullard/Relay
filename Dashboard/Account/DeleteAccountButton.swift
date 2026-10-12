import SwiftUI

/// Destructive "Delete Account…" control with a confirmation step (App Store guideline 5.1.1(v)).
struct DeleteAccountButton: View {
    @ObservedObject var coordinator: RelayAccountCoordinator
    @State private var isConfirming = false

    var body: some View {
        Button("Delete Account…", role: .destructive) {
            isConfirming = true
        }
        .buttonStyle(.bordered)
        .disabled(!RelayAccountConfig.isAuthEnabled || coordinator.isBusy)
        .confirmationDialog(
            "Delete your Relay Account?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await coordinator.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Relay Account, linked licenses, and usage data. Cancel your subscription separately in the App Store or Lemon Squeezy first.")
        }
    }
}
