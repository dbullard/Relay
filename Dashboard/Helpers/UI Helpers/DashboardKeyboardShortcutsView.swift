import SwiftUI

struct DashboardKeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct SectionModel: Identifiable {
        let id = UUID()
        let title: String
        let items: [(keys: String, action: String, notes: String?)]
    }

    private let sections: [SectionModel] = [
        SectionModel(
            title: "Tabs",
            items: [
                ("Cmd + [", "Select Previous Tab", "Works in Live Mode"),
                ("Cmd + ]", "Select Next Tab", "Works in Live Mode"),
                ("Cmd + Option + [", "Select First Tab", "Works in Live Mode"),
                ("Cmd + Option + ]", "Select Last Tab", "Works in Live Mode")
            ]
        ),
        SectionModel(
            title: "View",
            items: [
                ("Cmd + L", "Toggle Live Mode", nil),
                ("Cmd + 1", "Switch to Canvas View", nil),
                ("Cmd + 2", "Switch to Automation View", nil),
                ("Cmd + ;", "Toggle Show Guides", nil),
                ("Cmd + Option + M", "Toggle Auto-Hide Menu", nil),
                ("Cmd + Option + G", "Toggle Snap to Grid", nil)
            ]
        ),
        SectionModel(
            title: "Editing",
            items: [
                ("Cmd + D", "Duplicate Selected Tile or Node", nil),
                ("Cmd + G", "Group Selected Tiles", nil),
                ("Delete", "Delete Selected Tiles", "Edit Mode only"),
                ("Cmd + Shift + H", "Hide or Show Selected", nil)
            ]
        ),
        SectionModel(
            title: "File",
            items: [
                ("Cmd + N", "New Dashboard", nil),
                ("Cmd + O", "Open Dashboard", nil),
                ("Cmd + S", "Save Dashboard", nil),
                ("Cmd + Shift + S", "Save Dashboard As", nil)
            ]
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.title2.bold())
                    Text("Quick reference for dashboard navigation and common actions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.headline)

                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    Text(item.keys)
                                        .font(.system(.body, design: .monospaced).weight(.semibold))
                                        .frame(width: 170, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.action)
                                            .foregroundStyle(.primary)
                                        if let notes = item.notes,
                                           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(notes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420, idealHeight: 560)
    }
}
