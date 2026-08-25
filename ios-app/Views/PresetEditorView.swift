// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

struct PresetEditorView: View {
    let title: String
    @Binding var items: [String]
    var placeholder: String = "Add…"
    var spoolmanSuggestions: [String] = []

    @State private var newItem = ""
    @FocusState private var fieldFocused: Bool

    private var unusedSuggestions: [String] {
        let existing = Set(items.map { normalized($0) })
        var seen = Set<String>()
        return spoolmanSuggestions.filter { suggestion in
            let key = normalized(suggestion)
            guard !key.isEmpty, !existing.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(items, id: \.self) { item in
                    Text(item)
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { items.remove(atOffsets: $0) }

                HStack {
                    TextField(placeholder, text: $newItem)
                        .focused($fieldFocused)
                        .onSubmit(addItem)
                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(newItem.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .blue)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Your presets")
            } footer: {
                Text("Drag to reorder. Presets appear first in the picker when creating a spool.")
            }

            if !unusedSuggestions.isEmpty {
                Section("From Spoolman") {
                    ForEach(unusedSuggestions, id: \.self) { suggestion in
                        Button {
                            addSuggestion(suggestion)
                        } label: {
                            HStack {
                                Text(suggestion)
                                Spacer()
                                Image(systemName: "plus")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }

    private func addItem() {
        let trimmed = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalized(trimmed)
        let existing = Set(items.map { normalized($0) })
        guard !key.isEmpty, !existing.contains(key) else { return }
        items.append(trimmed)
        newItem = ""
    }

    private func addSuggestion(_ suggestion: String) {
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalized(trimmed)
        let existing = Set(items.map { normalized($0) })
        guard !key.isEmpty, !existing.contains(key) else { return }
        items.append(trimmed)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
