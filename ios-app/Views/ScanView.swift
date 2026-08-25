// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

struct ScanView: View {
    @Bindable var viewModel: SpoolmanViewModel
    @State private var selectedSpool: SpoolResponse?
    @State private var showCreateSheet = false
    @State private var showAssignSheet = false
    @State private var showChangeSpoolSheet = false
    @State private var showDetachConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 8)

                    ZStack {
                        Circle()
                            .fill(viewModel.isScanning ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                            .frame(width: 160, height: 160)
                        Circle()
                            .stroke(viewModel.isScanning ? Color.green : Color.gray, lineWidth: 3)
                            .frame(width: 140, height: 140)

                        if viewModel.isScanning {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(2.2)
                                .tint(.green)
                        } else {
                            Image(systemName: "wave.3.right.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.gray)
                        }
                    }

                    Text(viewModel.statusMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: viewModel.isScanning ? viewModel.stopScanning : viewModel.startScanning) {
                        HStack {
                            Image(systemName: viewModel.isScanning ? "stop.circle.fill" : "play.circle.fill")
                            Text(viewModel.isScanning ? "Stop Scanning" : "Start Scanning")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isScanning ? Color.red : Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    .padding(.horizontal)

                    if let result = viewModel.lastResult {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? .green : .red)
                                Text(result.success ? "Tag read" : "Error")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(result.success ? .green : .red)
                                Spacer()
                                Text(result.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            TagDetailView(payload: result.tagPayload, uidHex: result.cardUid)

                            if let spool = result.spoolResponse {
                                spoolmanSection {
                                    VStack(spacing: 8) {
                                        SpoolInfoRow(spool: spool)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedSpool = spool }
                                        if !viewModel.spools.isEmpty {
                                            Button { showChangeSpoolSheet = true } label: {
                                                Label("Change Spool", systemImage: "arrow.triangle.2.circlepath")
                                                    .fontWeight(.medium)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                                    .padding(.horizontal)
                                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                        Button { showDetachConfirm = true } label: {
                                            Label("Unlink from Spool", systemImage: "minus.circle.fill")
                                                .fontWeight(.medium)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal)
                                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        }
                                        .foregroundStyle(.red)
                                        .confirmationDialog(
                                            "Unlink \(result.cardUid) from \(spool.displayName)?",
                                            isPresented: $showDetachConfirm,
                                            titleVisibility: .visible
                                        ) {
                                            Button("Unlink", role: .destructive) {
                                                Task { await viewModel.removeTag(uidHex: result.cardUid, from: spool) }
                                            }
                                        }
                                    }
                                }
                                .sheet(isPresented: $showChangeSpoolSheet) {
                                    AssignSpoolSheet(
                                        tagPayload: result.tagPayload,
                                        uidHex: result.cardUid,
                                        viewModel: viewModel
                                    )
                                }
                            } else if result.success {
                                spoolmanSection {
                                    VStack(spacing: 8) {
                                        Button { showAssignSheet = true } label: {
                                            Label("Assign to Existing Spool", systemImage: "link")
                                                .fontWeight(.medium)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal)
                                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        }
                                        Button { showCreateSheet = true } label: {
                                            Label("Create New Spool", systemImage: "plus.circle.fill")
                                                .fontWeight(.medium)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal)
                                                .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .sheet(isPresented: $showAssignSheet) {
                                    AssignSpoolSheet(
                                        tagPayload: result.tagPayload,
                                        uidHex: result.cardUid,
                                        viewModel: viewModel
                                    )
                                }
                                .sheet(isPresented: $showCreateSheet) {
                                    CreateSpoolSheet(
                                        tagPayload: result.tagPayload,
                                        uidHex: result.cardUid,
                                        viewModel: viewModel
                                    )
                                }
                                .onChange(of: showCreateSheet) {
                                    if !showCreateSheet, let spool = viewModel.lastResult?.spoolResponse {
                                        selectedSpool = spool
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer().frame(height: 8)
                }
            }
            .task { viewModel.ensureSpoolsLoaded() }
            .animation(.easeInOut(duration: 0.3), value: viewModel.lastResult?.id)
            .sheet(item: $selectedSpool) { spool in
                SpoolDetailSheet(spool: spool, viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func spoolmanSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Spoolman", systemImage: "server.rack")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
    }
}

#Preview {
    ScanView(viewModel: SpoolmanViewModel())
}
