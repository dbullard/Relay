import SwiftUI

/// Compact scope segment for the automation-mode toolbar.
/// "All tabs" = shared/universal, "This tab" = private/per-tab.
struct AutomationScopeControl: View {
    let mode: DashboardTab.AutomationMode
    let onTapAllTabs: () -> Void
    let onTapThisTab: () -> Void
    let onOpenPopover: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                segment(title: "All tabs", isOn: mode == .universal, tint: Color.accentColor) {
                    onTapAllTabs()
                }
                segment(title: "This tab", isOn: mode == .perTab, tint: Color.orange) {
                    onTapThisTab()
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.35))
            )
            Button(action: onOpenPopover) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Automation scope details")
        }
    }

    private func segment(title: String, isOn: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isOn ? tint : Color.clear)
                .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
