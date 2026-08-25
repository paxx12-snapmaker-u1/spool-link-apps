// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

struct HistoryView: View {
    @Bindable var viewModel: SpoolmanViewModel
    @State private var selectedResult: ScanResult?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.scanHistory.isEmpty {
                    ContentUnavailableView(
                        "No Scan History",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Scanned NFC tags will appear here")
                    )
                } else {
                    List(viewModel.scanHistory) { result in
                        Button {
                            selectedResult = result
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(result.success ? .green : .red)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(result.spoolName)
                                            .font(.headline)
                                        Text(result.tagPayload.formatName)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }

                                    HStack(spacing: 8) {
                                        if let spoolId = result.spoolId {
                                            Label("#\(spoolId)", systemImage: "tag")
                                        }
                                        Label(result.cardUid, systemImage: "creditcard")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fontDesign(.monospaced)

                                    Text(Self.dateFormatter.string(from: result.timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !viewModel.scanHistory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            viewModel.scanHistory.removeAll()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                    }
                }
            }
            .sheet(item: $selectedResult) { result in
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            if !result.success {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(result.message)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal)
                            }
                            TagDetailView(payload: result.tagPayload, uidHex: result.cardUid)
                                .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    .navigationTitle(result.spoolName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedResult = nil }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    HistoryView(viewModel: SpoolmanViewModel())
}
