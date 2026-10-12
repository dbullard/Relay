import SwiftUI

struct AutomationScopePopover: View {
    struct TabRow: Identifiable {
        let id: UUID
        let name: String
        let mode: DashboardTab.AutomationMode
        let isCurrent: Bool
    }

    let currentTabName: String
    let currentMode: DashboardTab.AutomationMode
    let rows: [TabRow]
    let showPrimer: Bool
    let onSelectRow: (UUID) -> Void
    let onContextualAction: () -> Void
    let onShowPrimer: () -> Void

    @State private var primerVisible: Bool

    init(
        currentTabName: String,
        currentMode: DashboardTab.AutomationMode,
        rows: [TabRow],
        showPrimer: Bool,
        onSelectRow: @escaping (UUID) -> Void,
        onContextualAction: @escaping () -> Void,
        onShowPrimer: @escaping () -> Void
    ) {
        self.currentTabName = currentTabName
        self.currentMode = currentMode
        self.rows = rows
        self.showPrimer = showPrimer
        self.onSelectRow = onSelectRow
        self.onContextualAction = onContextualAction
        self.onShowPrimer = onShowPrimer
        _primerVisible = State(initialValue: showPrimer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if primerVisible {
                Text("Automation can be shared across all tabs, or kept private to one tab.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }

            header
            Divider()
            overviewList
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: currentMode == .universal ? "link" : "lock")
                    .foregroundStyle(currentMode == .universal ? Color.accentColor : Color.orange)
                Text(currentMode == .universal ? "Shared by all tabs" : "Private to \u{201C}\(currentTabName)\u{201D}")
                    .font(.system(size: 13.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(currentMode == .universal
                 ? "Every tab runs this same automation. Edits here change it everywhere."
                 : "Only this tab runs this automation. Other tabs are unaffected.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private var overviewList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tabs using automation")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ForEach(rows) { row in
                Button {
                    onSelectRow(row.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: row.mode == .universal ? "link" : "lock")
                            .font(.system(size: 12))
                            .foregroundStyle(row.mode == .universal ? Color.accentColor : Color.orange)
                        Text(row.name)
                            .font(.system(size: 13, weight: row.isCurrent ? .medium : .regular))
                        Spacer()
                        Text(row.mode == .universal ? "Shared" : "This tab")
                            .font(.system(size: 11))
                            .foregroundStyle(row.mode == .universal ? Color.accentColor : Color.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(row.isCurrent ? Color.primary.opacity(0.06) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onContextualAction) {
                Label(
                    currentMode == .universal ? "Make this tab private" : "Share with all tabs",
                    systemImage: currentMode == .universal ? "lock" : "link"
                )
                .font(.system(size: 12.5))
                .frame(maxWidth: .infinity)
            }
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    primerVisible.toggle()
                }
            }) {
                Image(systemName: primerVisible ? "questionmark.circle.fill" : "questionmark.circle")
            }
            .accessibilityLabel(primerVisible ? "Hide explanation" : "What does this mean?")
        }
        .padding(12)
    }
}
