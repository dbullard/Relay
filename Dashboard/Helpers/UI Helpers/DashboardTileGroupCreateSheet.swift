import SwiftUI

struct TileGroupCreateSheet: View {
    @Binding var name: String
    @Binding var color: Color
    let selectedCount: Int
    let isEditing: Bool
    let tab: DashboardTab
    let availableTiles: [DashboardTileModel]
    @Binding var selectedTileIDs: Set<UUID>
    let onCommit: () -> Void
    let onCancel: () -> Void

    private var titleText: String {
        isEditing ? "Edit Tile Group" : "Create Tile Group"
    }

    private var subtitleText: String {
        isEditing ? "Group includes \(selectedCount) tiles" : "Grouping \(selectedCount) tiles"
    }

    private var actionTitle: String {
        isEditing ? "Save" : "Create"
    }

    private func tileDisplayName(for tile: DashboardTileModel, index: Int) -> String {
        let trimmed = tile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Tile \(index + 1)" : trimmed
    }

    private func toggleTileSelection(_ id: UUID) {
        if selectedTileIDs.contains(id) {
            if selectedTileIDs.count > 1 {
                selectedTileIDs.remove(id)
            }
        } else {
            selectedTileIDs.insert(id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(titleText)
                .font(.headline)

            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Group name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(availableTiles.enumerated()), id: \.element.id) { index, tile in
                                let isSelected = selectedTileIDs.contains(tile.id)
                                Button {
                                    toggleTileSelection(tile.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tileDisplayName(for: tile, index: index))
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(tileSummaryStatic(for: tile, in: tab))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button(actionTitle) { onCommit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}
