import SwiftUI

struct PurchaseErrorNotice: View {
    let message: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)

            Button("Contact Support") {
                RelaySupportContact.openSupportEmail(context: "Purchase error: \(message)")
            }
            .dashboardLinkButtonStyle()
            .font(.caption2)
        }
    }
}
