import SwiftUI

#if os(macOS)
struct ActivateLicenseSheet: View {
    @EnvironmentObject private var licenseCoordinator: LicenseCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var licenseKey: String = ""
    @State private var isActivating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activate License")
                .font(.title2.bold())

            Text("Enter the license key from your Lemon Squeezy purchase email.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("License Key", text: $licenseKey)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Link("Terms", destination: RelayLicensingConfig.termsURL)
                    .font(.caption)
                Link("Privacy", destination: RelayLicensingConfig.privacyPolicyURL)
                    .font(.caption)

                Spacer()

                Button(isActivating ? "Activating…" : "Activate") {
                    Task {
                        isActivating = true
                        await licenseCoordinator.activateLicense(licenseKey: licenseKey)
                        isActivating = false
                        if licenseCoordinator.isLicensed {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActivating)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}
#else
struct ActivateLicenseSheet: View {
    var body: some View { EmptyView() }
}
#endif
