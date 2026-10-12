// Dashboard/Helpers/UI Helpers/SFSymbolPickerView.swift
import SwiftUI

struct SFSymbolPickerView: View {
    @Binding var selectedSymbolName: String
    var onSelect: (String) -> Void

    @State private var query = ""

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [String] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        return SFSymbolLibrary.categories.flatMap(\.symbols).filter { name in
            name.contains(q) && seen.insert(name).inserted
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if trimmedQuery.isEmpty {
                categoryBrowser
            } else {
                searchResultsGrid
            }
        }
        .frame(width: 320, height: 400)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search symbols", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var categoryBrowser: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(SFSymbolLibrary.categories, id: \.name) { category in
                    Section {
                        symbolGrid(symbols: category.symbols)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    } header: {
                        Text(category.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial)
                    }
                }
            }
        }
    }

    private var searchResultsGrid: some View {
        ScrollView {
            if searchResults.isEmpty {
                Text("No symbols match \"\(trimmedQuery)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                symbolGrid(symbols: searchResults)
                    .padding(12)
            }
        }
    }

    private func symbolGrid(symbols: [String]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(symbols, id: \.self) { name in
                Button {
                    onSelect(name)
                } label: {
                    Image(systemName: name)
                        .font(.system(size: 22))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedSymbolName == name
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(name)
                .accessibilityLabel(name)
            }
        }
    }
}
