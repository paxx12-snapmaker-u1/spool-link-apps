// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI
import UIKit

struct SettingsView: View {
    var viewModel: SpoolmanViewModel? = nil

    @AppStorage("spoolmanBaseURL") private var savedURL = "http://spoolman.local:7912"
    @AppStorage("filamentNameStyle") private var nameStyle: FilamentNameStyle = .brandAndSubtype
    @State private var tempURL = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var testLogs: [String] = []
    @State private var showSavedFeedback = false
    @State private var presets = FilamentPresets.load()

    private enum TestResult {
        case success
        case failure(String)
    }

    private var testPassed: Bool {
        if case .success = testResult { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $tempURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: tempURL) {
                            testResult = nil
                            testLogs = []
                        }

                    Button(action: runTest) {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .padding(.trailing, 4)
                                Text("Testing…")
                                    .fontWeight(.semibold)
                            } else {
                                Image(systemName: "network")
                                    .padding(.trailing, 4)
                                Text("Test Connection")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isTesting || tempURL.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !testLogs.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(testLogs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(
                                        line.hasPrefix("✗") ? Color.red :
                                        line.hasPrefix("✓") ? Color.green :
                                        Color.secondary
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    if testPassed {
                        Button(action: saveURL) {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .padding(.trailing, 4)
                                Text("Save")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } header: {
                    Text("Spoolman Server")
                } footer: {
                    Text("Enter the base URL of your Spoolman server (e.g., http://192.168.1.100:7912)")
                }

                Section {
                    HStack {
                        Text("Saved URL")
                        Spacer()
                        Text(savedURL)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Current Configuration")
                }

                Section {
                    Picker("Filament name", selection: $nameStyle) {
                        ForEach(FilamentNameStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                } header: {
                    Text("Spool Creation")
                } footer: {
                    Text("Pattern used for the filament name when creating a new spool.")
                }

                Section {
                    NavigationLink("Brands") {
                        PresetEditorView(
                            title: "Brands",
                            items: $presets.brands,
                            placeholder: "Add brand…",
                            spoolmanSuggestions: spoolmanBrands
                        )
                        .onChange(of: presets.brands) { presets.save() }
                    }
                    NavigationLink("Materials") {
                        PresetEditorView(
                            title: "Materials",
                            items: $presets.materials,
                            placeholder: "Add material…",
                            spoolmanSuggestions: spoolmanMaterials
                        )
                        .onChange(of: presets.materials) { presets.save() }
                    }
                    NavigationLink("Variants") {
                        PresetEditorView(
                            title: "Variants",
                            items: $presets.variants,
                            placeholder: "Add variant…"
                        )
                        .onChange(of: presets.variants) { presets.save() }
                    }
                    NavigationLink("Weights") {
                        PresetEditorView(
                            title: "Weights",
                            items: $presets.weights,
                            placeholder: "Add weight (g)…"
                        )
                        .onChange(of: presets.weights) { presets.save() }
                    }
                } header: {
                    Text("Filament Presets")
                } footer: {
                    Text("Presets appear as quick-pick suggestions when creating a spool.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                tempURL = savedURL
                presets = FilamentPresets.load()
                viewModel?.ensureSpoolsLoaded()
            }
            .overlay {
                if showSavedFeedback {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("URL saved")
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: showSavedFeedback)
            .animation(.easeInOut, value: testResult != nil)
        }
    }

    private var spoolmanBrands: [String] {
        Array(Set((viewModel?.spools ?? []).compactMap { $0.filament.vendor?.name })).sorted()
    }

    private var spoolmanMaterials: [String] {
        Array(Set((viewModel?.spools ?? []).compactMap { $0.filament.material })).sorted()
    }

    private func runTest() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isTesting = true
        testResult = nil
        testLogs = []
        Task {
            let result = await SpoolmanAPI.testConnection(baseURL: tempURL)
            testLogs = result.logs
            testResult = result.succeeded ? .success : .failure(result.error?.localizedDescription ?? "Unknown error")
            isTesting = false
        }
    }

    private func saveURL() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        savedURL = tempURL
        viewModel?.updateBaseURL(tempURL)
        testResult = nil
        showSavedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showSavedFeedback = false
        }
    }
}

#Preview {
    SettingsView()
}
