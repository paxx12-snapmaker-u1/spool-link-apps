// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI
import UIKit

struct CreateSpoolSheet: View {
    let tagPayload: (any NFCTagPayload)?
    let uidHex: String
    var onCreated: ((SpoolResponse) -> Void)? = nil
    @Bindable var viewModel: SpoolmanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var brand = ""
    @State private var material = ""
    @State private var subtype = ""
    @State private var colorHex = ""
    @State private var selectedColor: Color = .white
    @State private var diameter = "1.75"
    @State private var weight = ""
    @State private var nozzleTemp = ""
    @State private var bedTemp = ""
    @State private var presets = FilamentPresets.load()
    @State private var selectedFilamentId: Int?
    @State private var showFilamentPicker = false

    init(tagPayload: (any NFCTagPayload)? = nil, uidHex: String = "", viewModel: SpoolmanViewModel,
         onCreated: ((SpoolResponse) -> Void)? = nil) {
        self.tagPayload = tagPayload
        self.uidHex = uidHex
        self.onCreated = onCreated
        self._viewModel = Bindable(viewModel)
        let meta = tagPayload?.filamentMetadata
        _brand = State(initialValue: meta?.brand ?? "")
        _material = State(initialValue: meta?.material ?? "")
        _subtype = State(initialValue: meta?.subtype ?? "")
        let initialHex = (meta?.colorHex ?? "FFFFFF").uppercased()
        _colorHex = State(initialValue: initialHex)
        _selectedColor = State(initialValue: Color(hex: initialHex) ?? .white)
        _diameter = State(initialValue: meta?.diameter.map { String(format: "%.2f", $0) } ?? "1.75")
        _weight = State(initialValue: meta?.weight.map { "\(Int($0))" } ?? "1000")
        _nozzleTemp = State(initialValue: meta?.nozzleTemp.map(String.init) ?? "")
        _bedTemp = State(initialValue: meta?.bedTemp.map(String.init) ?? "")
    }

    private var brandSuggestions: [String] {
        let spoolman = Set(viewModel.spools.compactMap { $0.filament.vendor?.name })
        return presets.brands + spoolman.subtracting(Set(presets.brands)).sorted()
    }

    private var materialSuggestions: [String] {
        let spoolman = Set(viewModel.spools.compactMap { $0.filament.material })
        return presets.materials + spoolman.subtracting(Set(presets.materials)).sorted()
    }

    private var variantSuggestions: [String] { [""] + presets.variants }

    private var weightSuggestions: [String] { presets.weights }

    private var selectedFilament: SpoolmanAPI.FilamentResponse? {
        guard let selectedFilamentId else { return nil }
        return viewModel.availableFilaments.first(where: { $0.id == selectedFilamentId })
    }

    private var selectedFilamentDisplayName: String {
        guard let f = selectedFilament else { return "Create New" }
        return "\(f.displayName) (#\(f.id))"
    }

    private var isUsingExistingFilament: Bool {
        selectedFilament != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        viewModel.loadFilamentsIfNeeded()
                        showFilamentPicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedFilamentDisplayName)
                                    .foregroundStyle(.primary)
                                if viewModel.isLoadingFilaments {
                                    Text("Loading filaments…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let error = viewModel.filamentsErrorMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            if viewModel.isLoadingFilaments {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(viewModel.isLoadingFilaments)
                }

                Section("Filament") {
                    PickableField(
                        label: "Brand",
                        text: $brand,
                        placeholder: "e.g. Bambu Lab",
                        suggestions: brandSuggestions,
                        locked: isUsingExistingFilament
                    )
                    PickableField(
                        label: "Material",
                        text: $material,
                        placeholder: "PLA, PETG, ASA…",
                        suggestions: materialSuggestions,
                        autocap: .characters,
                        locked: isUsingExistingFilament
                    )
                    PickableField(
                        label: "Variant",
                        text: $subtype,
                        placeholder: "Basic, Matte…",
                        suggestions: variantSuggestions,
                        locked: isUsingExistingFilament
                    )
                    colorRow
                }

                Section("Properties") {
                    SpoolField(
                        "Diameter (mm)",
                        text: $diameter,
                        placeholder: "1.75",
                        keyboard: .decimalPad,
                        locked: isUsingExistingFilament
                    )
                    PickableField(
                        label: "Weight (g)",
                        text: $weight,
                        placeholder: "1000",
                        suggestions: weightSuggestions,
                        keyboard: .numberPad,
                        autocap: .never,
                        locked: isUsingExistingFilament
                    )
                    SpoolField(
                        "Nozzle temp (°C)",
                        text: $nozzleTemp,
                        placeholder: "220",
                        keyboard: .numberPad,
                        locked: isUsingExistingFilament
                    )
                    SpoolField(
                        "Bed temp (°C)",
                        text: $bedTemp,
                        placeholder: "60",
                        keyboard: .numberPad,
                        locked: isUsingExistingFilament
                    )
                }

                if !uidHex.isEmpty {
                    Section {
                        HStack {
                            Text("Card UID")
                            Spacer()
                            Text(uidHex)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Tag")
                    }
                }
            }
            .navigationTitle("New Spool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: submit) {
                        if viewModel.isCreatingSpool {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Text("Create").fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isCreatingSpool)
                }
            }
            .task {
                viewModel.ensureSpoolsLoaded()
            }
            .sheet(isPresented: $showFilamentPicker) {
                FilamentPickerSheet(
                    items: viewModel.availableFilaments,
                    selectedId: $selectedFilamentId,
                    onRefresh: { viewModel.loadFilaments() }
                )
            }
            .onChange(of: selectedFilamentId) { applySelectedFilament() }
            .onChange(of: selectedColor) {
                if !isUsingExistingFilament {
                    colorHex = selectedColor.hexRGB
                }
            }
            .onChange(of: colorHex) {
                if let c = Color(hex: colorHex) { selectedColor = c }
            }
            .onChange(of: material) {
                if !isUsingExistingFilament {
                    applyDefaultTemperatures(for: material)
                }
            }
        }
    }

    private var colorRow: some View {
        SpoolField(
            "Color",
            text: $colorHex,
            placeholder: "FF5500",
            keyboard: .asciiCapable,
            autocap: .characters,
            mono: true,
            locked: isUsingExistingFilament
        ) {
            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .disabled(isUsingExistingFilament)
        }
    }

    private func applySelectedFilament() {
        guard let filament = selectedFilament else { return }
        brand = filament.vendor?.name ?? ""
        material = filament.material ?? ""
        subtype = filament.variantDecoded ?? ""
        colorHex = (filament.colorHex ?? "").uppercased()
        if let color = Color(hex: colorHex) {
            selectedColor = color
        }
        diameter = filament.diameter.map { String(format: "%.2f", $0) } ?? "1.75"
        weight = filament.weight.map { "\(Int($0))" } ?? ""
        nozzleTemp = filament.settingsExtruderTemp.map(String.init) ?? ""
        bedTemp = filament.settingsBedTemp.map(String.init) ?? ""
    }

    private func submit() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task {
            let newSpool = await viewModel.createSpoolFromTag(
                tagPayload: tagPayload,
                uidHex: uidHex,
                overrideMeta: FilamentMetadata(
                    brand: brand.trimmed,
                    material: material.trimmed,
                    subtype: subtype.trimmed,
                    colorHex: colorHex.trimmed,
                    diameter: Double(diameter) ?? 1.75,
                    weight: Double(weight),
                    nozzleTemp: Int(nozzleTemp),
                    bedTemp: Int(bedTemp),
                    spoolId: tagPayload?.filamentMetadata?.spoolId
                ),
                selectedFilamentId: selectedFilamentId
            )
            if let newSpool { onCreated?(newSpool) }
            dismiss()
        }
    }

    private func applyDefaultTemperatures(for material: String) {
        let key = material.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let defaults = materialTemperatureDefaults[key] else { return }
        if nozzleTemp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nozzleTemp = String(defaults.nozzle)
        }
        if bedTemp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bedTemp = String(defaults.bed)
        }
    }

    private var materialTemperatureDefaults: [String: (nozzle: Int, bed: Int)] {
        [
            "PLA": (220, 60),
            "PETG": (240, 80),
            "ABS": (250, 100),
            "ASA": (255, 100),
            "TPU": (230, 50),
            "NYLON": (260, 90),
            "PA": (260, 90),
            "PC": (270, 110)
        ]
    }
}

private struct PickableField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var suggestions: [String] = []
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .words
    var locked: Bool = false
    @State private var showPicker = false

    var body: some View {
        HStack {
            Text(label)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .disabled(locked)
            if locked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !suggestions.isEmpty {
                Button { showPicker = true } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .sheet(isPresented: $showPicker) {
                    PresetPickerSheet(title: label, items: suggestions, selected: $text)
                }
            }
        }
    }
}

private struct PresetPickerSheet: View {
    let title: String
    let items: [String]
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [String] {
        searchText.isEmpty ? items : items.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { item in
                Button {
                    selected = item
                    dismiss()
                } label: {
                    HStack {
                        if item.isEmpty {
                            Text("None").foregroundStyle(.secondary)
                        } else {
                            Text(item)
                        }
                        Spacer()
                        if selected == item {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SpoolField<Picker: View>: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .words
    var mono: Bool = false
    var locked: Bool = false
    var picker: Picker

    init(_ label: String, text: Binding<String>, placeholder: String = "",
         keyboard: UIKeyboardType = .default,
         autocap: TextInputAutocapitalization = .words,
         mono: Bool = false,
         locked: Bool = false) where Picker == EmptyView {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.keyboard = keyboard
        self.autocap = autocap
        self.mono = mono
        self.locked = locked
        self.picker = EmptyView()
    }

    init(_ label: String, text: Binding<String>, placeholder: String = "",
         keyboard: UIKeyboardType = .default,
         autocap: TextInputAutocapitalization = .words,
         mono: Bool = false,
         locked: Bool = false,
         @ViewBuilder picker: () -> Picker) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.keyboard = keyboard
        self.autocap = autocap
        self.mono = mono
        self.locked = locked
        self.picker = picker()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .disabled(locked)
                .if(mono) { $0.fontDesign(.monospaced) }
            picker
            if locked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    @ViewBuilder func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}

private extension String {
    var trimmed: String? {
        let s = trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

private struct FilamentPickerSheet: View {
    let items: [SpoolmanAPI.FilamentResponse]
    @Binding var selectedId: Int?
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [SpoolmanAPI.FilamentResponse] {
        if searchText.isEmpty { return items }
        return items.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.material?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        selectedId = nil
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                            Text("Create New")
                                .fontWeight(.semibold)
                            Spacer()
                            if selectedId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Section {
                    List {
                        ForEach(filtered) { filament in
                            Button {
                                selectedId = filament.id
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: filament.colorHex ?? "") ?? Color.secondary.opacity(0.15))
                                        .frame(width: 16, height: 16)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.1), lineWidth: 0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(filament.displayName)
                                        HStack(spacing: 6) {
                                            if let material = filament.material {
                                                Text(material)
                                            }
                                            if let hex = filament.colorHex {
                                                Text("#\(hex.uppercased())")
                                                    .fontDesign(.monospaced)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedId == filament.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search filament")
            .navigationTitle("Filament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", action: onRefresh)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension Color {
    var hexRGB: String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "FFFFFF"
        #endif
    }
}
