// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

struct AssignSpoolSheet: View {
    let tagPayload: any NFCTagPayload
    let uidHex: String
    @Bindable var viewModel: SpoolmanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isAssigning = false

    private var filteredSpools: [SpoolResponse] {
        guard !searchText.isEmpty else { return viewModel.spools }
        return viewModel.spools.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            ($0.filament.material?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.filament.vendor?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isFetchingSpools && viewModel.spools.isEmpty {
                    ProgressView("Loading spools…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.spoolsErrorMessage, viewModel.spools.isEmpty {
                    SpoolmanLoadErrorView(message: error) {
                        viewModel.fetchSpools(reset: true)
                    }
                } else if filteredSpools.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredSpools) { spool in
                        Button {
                            Task {
                                isAssigning = true
                                await viewModel.processAssignment(
                                    spool: spool, uidHex: uidHex, tagPayload: tagPayload)
                                isAssigning = false
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ColorSwatch(hex: spool.filament.colorHex, size: 40, cornerRadius: 8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(spool.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    HStack(spacing: 6) {
                                        Text("#\(spool.id)").foregroundStyle(.tertiary)
                                        if let material = spool.filament.material {
                                            Text("·").foregroundStyle(.secondary)
                                            Text(material).foregroundStyle(.secondary)
                                        }
                                        if let remaining = spool.remainingWeight {
                                            Text("·").foregroundStyle(.secondary)
                                            Text("\(Int(remaining)) g").foregroundStyle(.secondary)
                                        }
                                        Text("·").foregroundStyle(.secondary)
                                        TagCountBadge(count: spool.tagCount)
                                    }
                                    .font(.caption)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAssigning)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search spools")
            .navigationTitle("Assign to Spool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isAssigning)
                }
            }
            .overlay {
                if isAssigning {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Assigning…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear {
            if viewModel.spools.isEmpty { viewModel.fetchSpools() }
        }
    }
}
