// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

// MARK: - Sort

enum SpoolSort: String, CaseIterable, Identifiable {
    case dateAdded  = "Date Added"
    case lastUsed   = "Last Used"
    case name       = "Name"
    case material   = "Material"
    case remaining  = "Remaining"
    case tags       = "Tags"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dateAdded:  return "calendar.badge.plus"
        case .lastUsed:   return "clock"
        case .name:       return "textformat"
        case .material:   return "cube"
        case .remaining:  return "scalemass"
        case .tags:       return "wave.3.right"
        }
    }

    // Descending swaps the operands rather than negating, so ties stay unordered (a strict ordering, as sort requires).
    func compare(_ lhs: SpoolResponse, _ rhs: SpoolResponse, ascending: Bool) -> Bool {
        let (a, b) = ascending ? (lhs, rhs) : (rhs, lhs)
        switch self {
        case .dateAdded:
            return (a.registered ?? .distantPast) > (b.registered ?? .distantPast)
        case .lastUsed:
            return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast)
        case .name:
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        case .material:
            return (a.materialKey ?? "") < (b.materialKey ?? "")
        case .remaining:
            return (a.remainingWeight ?? 0) > (b.remainingWeight ?? 0)
        case .tags:
            return a.tagCount > b.tagCount
        }
    }

    func sectionHeader(for spool: SpoolResponse) -> String {
        let cal = Calendar.current
        let now = Date()
        func daysAgo(_ date: Date) -> Int {
            cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        }
        switch self {
        case .dateAdded:
            guard let d = spool.registered else { return "Unknown" }
            let days = daysAgo(d)
            if days == 0 { return "Today" }
            if days <= 3 { return "Last 3 Days" }
            if days <= 7 { return "This Week" }
            if days <= 30 { return "This Month" }
            return "Older"
        case .lastUsed:
            guard let d = spool.lastUsed else { return "Never Used" }
            let days = daysAgo(d)
            if days == 0 { return "Today" }
            if days <= 3 { return "Last 3 Days" }
            if days <= 7 { return "This Week" }
            if days <= 30 { return "This Month" }
            return "Older"
        case .name:
            let c = spool.displayName.first.map { Character($0.uppercased()) } ?? "#"
            switch c {
            case "A"..."E": return "A – E"
            case "F"..."J": return "F – J"
            case "K"..."O": return "K – O"
            case "P"..."T": return "P – T"
            case "U"..."Z": return "U – Z"
            default:        return "#"
            }
        case .material:
            return spool.materialKey ?? "Unknown"
        case .remaining:
            guard let w = spool.remainingWeight else { return "Unknown" }
            if w == 0      { return "Empty" }
            if w < 100     { return "< 100 g" }
            if w < 500     { return "100 – 500 g" }
            return "> 500 g"
        case .tags:
            switch spool.tagCount {
            case 0:  return "No Tags"
            case 1:  return "1 Tag"
            default: return "Multiple Tags"
            }
        }
    }

    func grouped(_ spools: [SpoolResponse], ascending: Bool) -> [(header: String, items: [SpoolResponse])] {
        let sorted = spools.sorted { compare($0, $1, ascending: ascending) }
        // Merge by header, not just adjacent runs: ties (e.g. nil vs 0 g remaining) can interleave headers,
        // and duplicate headers would collide as section IDs.
        var result: [(header: String, items: [SpoolResponse])] = []
        var indexByHeader: [String: Int] = [:]
        for spool in sorted {
            let h = sectionHeader(for: spool)
            if let i = indexByHeader[h] {
                result[i].items.append(spool)
            } else {
                indexByHeader[h] = result.count
                result.append((header: h, items: [spool]))
            }
        }
        return result
    }
}

// MARK: - Grouping & filtering

/// How the list is sectioned, independently of sort order. `matchSort` keeps the sort-derived sections.
enum SpoolGrouping: String, CaseIterable, Identifiable {
    case matchSort = "Match Sort"
    case ungrouped = "None"
    case material  = "Material"
    case vendor    = "Vendor"
    case tags      = "Tags"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .matchSort: return "arrow.up.arrow.down"
        case .ungrouped: return "list.bullet"
        case .material:  return "cube"
        case .vendor:    return "building.2"
        case .tags:      return "wave.3.right"
        }
    }

    func grouped(_ spools: [SpoolResponse], sort: SpoolSort, ascending: Bool) -> [(header: String, items: [SpoolResponse])] {
        switch self {
        case .matchSort:
            return sort.grouped(spools, ascending: ascending)
        case .ungrouped:
            let sorted = spools.sorted { sort.compare($0, $1, ascending: ascending) }
            return sorted.isEmpty ? [] : [(header: "", items: sorted)]
        case .material, .vendor, .tags:
            let sorted = spools.sorted { sort.compare($0, $1, ascending: ascending) }
            let buckets = Dictionary(grouping: sorted) { header(for: $0) }
            return buckets.keys
                .sorted { (rank($0), $0.localizedLowercase) < (rank($1), $1.localizedLowercase) }
                .map { (header: $0, items: buckets[$0] ?? []) }
        }
    }

    private static let unknownMaterial = "Unknown"
    private static let noVendor = "No Vendor"

    private func header(for spool: SpoolResponse) -> String {
        switch self {
        case .material:
            return spool.materialKey ?? Self.unknownMaterial
        case .vendor:
            let name = spool.filament.vendor?.name?.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? Self.noVendor : name
        case .tags:
            return SpoolSort.tags.sectionHeader(for: spool)
        case .matchSort, .ungrouped:
            return ""
        }
    }

    // Natural order for Tags; catch-all buckets after named ones.
    private func rank(_ header: String) -> Int {
        switch header {
        case "No Tags":                           return 0
        case "1 Tag":                             return 1
        case "Multiple Tags":                     return 2
        case Self.unknownMaterial, Self.noVendor: return 3
        default:                                  return 1
        }
    }
}

enum SpoolTagFilter: String, CaseIterable, Identifiable {
    case all      = "All"
    case tagged   = "Tagged"
    case untagged = "Untagged"

    var id: String { rawValue }

    func matches(_ spool: SpoolResponse) -> Bool {
        switch self {
        case .all:      return true
        case .tagged:   return spool.tagCount > 0
        case .untagged: return spool.tagCount == 0
        }
    }
}

extension SpoolResponse {
    /// Material normalised for filtering and grouping ("pla " and "PLA" are the same); nil when unset.
    var materialKey: String? {
        let m = filament.material?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return m.isEmpty ? nil : m
    }

    /// Name/vendor, material, or lot number substring; "#12" for an exact id; or part of a tag UID.
    func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if q.hasPrefix("#"), let n = Int(q.dropFirst()) { return id == n }
        if [displayName, filament.material, lotNr].compactMap({ $0 }).contains(where: { $0.localizedCaseInsensitiveContains(q) }) {
            return true
        }
        // Allow UIDs typed or pasted with separators, e.g. "04:A1:B2:C3". Only when the whole query looks
        // like a UID, otherwise the hex letters in a word ("Wood" -> "D") would match unrelated tags.
        guard q.allSatisfy({ $0.isHexDigit || ":- ".contains($0) }) else { return false }
        let hex = q.uppercased().filter { $0.isHexDigit }
        return !hex.isEmpty && tagUIDs.contains { $0.contains(hex) }
    }
}

// MARK: - SpoolsView

struct SpoolsView: View {
    @Bindable var viewModel: SpoolmanViewModel
    @State private var selectedSpool: SpoolResponse?
    @AppStorage("spoolsSortBy") private var sortByRaw: String = SpoolSort.dateAdded.rawValue
    @AppStorage("spoolsSortAscending") private var sortAscending = true
    @AppStorage("spoolsGroupBy") private var groupByRaw: String = SpoolGrouping.matchSort.rawValue
    @State private var searchText = ""
    @State private var materialFilter: Set<String> = []
    @State private var tagFilter: SpoolTagFilter = .all
    @Environment(\.scenePhase) private var scenePhase

    private var sortBy: SpoolSort { SpoolSort(rawValue: sortByRaw) ?? .dateAdded }
    private var groupBy: SpoolGrouping { SpoolGrouping(rawValue: groupByRaw) ?? .matchSort }

    private var isFiltering: Bool { !materialFilter.isEmpty || tagFilter != .all }

    // Includes selected materials no longer present after a refresh, so an active filter stays visible.
    private var availableMaterials: [String] {
        Set(viewModel.spools.compactMap(\.materialKey)).union(materialFilter)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var filteredSpools: [SpoolResponse] {
        viewModel.spools.filter { spool in
            tagFilter.matches(spool)
                && (materialFilter.isEmpty || spool.materialKey.map(materialFilter.contains) == true)
                && spool.matchesSearch(searchText)
        }
    }

    private var groupedSpools: [(header: String, items: [SpoolResponse])] {
        groupBy.grouped(filteredSpools, sort: sortBy, ascending: sortAscending)
    }

    private var duplicateTagUIDs: Set<String> {
        var counts: [String: Int] = [:]
        for s in viewModel.spools {
            for uid in s.tagUIDs { counts[uid, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    @ViewBuilder private var spoolsContent: some View {
        let duplicates = duplicateTagUIDs
        let groups = groupedSpools
        if viewModel.isFetchingSpools && viewModel.spools.isEmpty {
            ProgressView("Loading spools…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.spoolsErrorMessage, viewModel.spools.isEmpty {
            SpoolmanLoadErrorView(message: error) {
                viewModel.fetchSpools(reset: true)
            }
        } else if viewModel.spools.isEmpty {
            ContentUnavailableView(
                "No Spools",
                systemImage: "archivebox",
                description: Text("No spools found in Spoolman")
            )
        } else {
            List {
                ForEach(groups, id: \.header) { group in
                    Section {
                        ForEach(group.items) { spool in
                            SpoolRow(spool: spool, hasConflict: spool.tagUIDs.contains { duplicates.contains($0) })
                                .contentShape(Rectangle())
                                .onTapGesture { selectedSpool = spool }
                        }
                    } header: {
                        if !group.header.isEmpty {
                            Text("\(group.header) (\(group.items.count))")
                        }
                    }
                }

                if viewModel.hasMoreSpools {
                    HStack {
                        Spacer()
                        if viewModel.isFetchingSpools {
                            ProgressView()
                        } else {
                            Button("Load More") { viewModel.loadMoreSpools() }
                        }
                        Spacer()
                    }
                    .onAppear { viewModel.loadMoreSpools() }
                }
            }
            .refreshable { await viewModel.loadSpools(reset: true) }
            // An overlay rather than a separate branch keeps pull-to-refresh and "Load More" reachable.
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Spools", systemImage: "magnifyingglass")
                    } description: {
                        Text("No spools match the current search or filters.")
                    } actions: {
                        Button("Clear Search & Filters") {
                            searchText = ""
                            materialFilter = []
                            tagFilter = .all
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = viewModel.spoolsErrorMessage {
                    Label("Couldn't refresh: \(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            spoolsContent
                .searchable(text: $searchText, prompt: "Name, material, #id, or tag UID")
                .navigationTitle("Spools")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { viewModel.fetchSpools(reset: true) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isFetchingSpools)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        filterMenu
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu
                    }
                }
                .sheet(item: $selectedSpool) { spool in
                    SpoolDetailSheet(spool: spool, viewModel: viewModel)
                }
        }
        .onAppear { viewModel.refreshSpoolsIfStale() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshSpoolsIfStale() }
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Tags") {
                Picker("Tags", selection: $tagFilter) {
                    ForEach(SpoolTagFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            }
            if !availableMaterials.isEmpty {
                Section("Material") {
                    ForEach(availableMaterials, id: \.self) { material in
                        Toggle(material, isOn: Binding(
                            get: { materialFilter.contains(material) },
                            set: { isOn in
                                if isOn { materialFilter.insert(material) } else { materialFilter.remove(material) }
                            }
                        ))
                    }
                }
            }
            if isFiltering {
                Section {
                    Button("Clear Filters", role: .destructive) {
                        materialFilter = []
                        tagFilter = .all
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .symbolVariant(isFiltering ? .fill : .none)
        }
        // Keep the menu open so several materials can be toggled in one go.
        .menuActionDismissBehavior(.disabled)
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(SpoolSort.allCases) { sort in
                    Button {
                        if sortBy == sort {
                            sortAscending = !sortAscending
                        } else {
                            sortByRaw = sort.rawValue
                            sortAscending = true
                        }
                    } label: {
                        let active = sortBy == sort
                        Label(
                            active ? "\(sort.rawValue) \(sortAscending ? "↑" : "↓")" : sort.rawValue,
                            systemImage: sort.icon
                        )
                    }
                }
            }
            Section("Group by") {
                Picker("Group by", selection: $groupByRaw) {
                    ForEach(SpoolGrouping.allCases) { grouping in
                        Label(grouping.rawValue, systemImage: grouping.icon).tag(grouping.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .symbolVariant(sortBy != .dateAdded || !sortAscending ? .circle : .none)
        }
    }
}

// MARK: - List row

struct SpoolRow: View {
    let spool: SpoolResponse
    var hasConflict: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ColorSwatch(hex: spool.filament.colorHex, size: 44, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(spool.displayName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let material = spool.filament.material {
                        Text(material)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                        Text("·").foregroundStyle(.secondary)
                    }
                    Text("#\(spool.id)")
                        .foregroundStyle(.tertiary)
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

            if hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail sheet

struct SpoolDetailSheet: View {
    let spool: SpoolResponse
    @Bindable var viewModel: SpoolmanViewModel

    private var currentSpool: SpoolResponse {
        viewModel.spools.first { $0.id == spool.id } ?? spool
    }
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveConfirm = false
    @AppStorage("spoolmanBaseURL") private var savedBaseURL = "http://spoolman.local:7912"

    private var duplicateTagUIDs: Set<String> {
        var counts: [String: Int] = [:]
        for s in viewModel.spools {
            for uid in s.tagUIDs { counts[uid, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    private var spoolWebURL: URL? {
        var base = savedBaseURL
        if !base.hasSuffix("/") { base += "/" }
        return URL(string: "\(base)spool/show/\(spool.id)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header card
                    HStack(spacing: 16) {
                        ColorSwatch(hex: currentSpool.filament.colorHex, size: 64, cornerRadius: 14)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentSpool.displayName)
                                .font(.title3)
                                .fontWeight(.semibold)
                            HStack(spacing: 6) {
                                if let material = currentSpool.filament.material {
                                    Text(material)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.secondary.opacity(0.12), in: Capsule())
                                }
                                TagCountBadge(count: currentSpool.tagCount)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                    // Stats table
                    VStack(spacing: 0) {
                        DetailRow(label: "Spool ID", value: "#\(currentSpool.id)")
                        if let remaining = currentSpool.remainingWeight {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Remaining", value: "\(Int(remaining)) g")
                        }
                        if let hex = currentSpool.filament.colorHex {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Color") {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: hex) ?? .clear)
                                        .frame(width: 18, height: 18)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.15), lineWidth: 0.5))
                                    Text("#\(hex.uppercased())")
                                        .fontDesign(.monospaced)
                                }
                            }
                        }
                        if let diameter = currentSpool.filament.diameter {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Diameter", value: String(format: "%.2f mm", diameter))
                        }
                        if let weight = currentSpool.filament.weight {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Filament", value: "\(Int(weight)) g")
                        }
                        if let nozzle = currentSpool.filament.settingsExtruderTemp {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Nozzle", value: "\(nozzle) °C")
                        }
                        if let bed = currentSpool.filament.settingsBedTemp {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Bed", value: "\(bed) °C")
                        }
                        if let registered = currentSpool.registered {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Added", value: registered.formatted(date: .abbreviated, time: .omitted))
                        }
                        if let lastUsed = currentSpool.lastUsed {
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Last Used", value: lastUsed.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    // Assigned tags
                    VStack(spacing: 0) {
                        HStack {
                            Text("Assigned Tags")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            if !currentSpool.tagUIDs.isEmpty {
                                Button(role: .destructive) {
                                    showRemoveConfirm = true
                                } label: {
                                    Text("Remove All")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if currentSpool.tagUIDs.isEmpty {
                            Text("No tags assigned")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        } else {
                            ForEach(Array(currentSpool.tagUIDs.enumerated()), id: \.offset) { i, uid in
                                Divider().padding(.leading, 16)
                                HStack(spacing: 10) {
                                    Image(systemName: "wave.3.right")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                    Text(uid)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                    Spacer()
                                    if duplicateTagUIDs.contains(uid) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = uid
                                    } label: {
                                        Label("Copy UID", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }
                        if !duplicateTagUIDs.isEmpty {
                            Divider().padding(.leading, 16)
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("One or more tags are assigned to multiple spools. Scan the tag to fix.")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    Text("Tip: assign a tag from each side of the spool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    // Action buttons
                    let isAssigning = viewModel.pendingAssignSpool?.id == spool.id
                    VStack(spacing: 10) {
                        Button {
                            viewModel.startTagAssignment(for: spool)
                        } label: {
                            Group {
                                if isAssigning {
                                    HStack(spacing: 8) {
                                        ProgressView().tint(.white)
                                        Text("Scanning for tag…").fontWeight(.semibold)
                                    }
                                } else {
                                    Label("Assign NFC Tag", systemImage: "wave.3.right")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(isAssigning)

                        if let url = spoolWebURL {
                            Link(destination: url) {
                                Label("Open in Spoolman", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Spool Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove all \(currentSpool.tagCount) tag\(currentSpool.tagCount == 1 ? "" : "s") from \(currentSpool.displayName)?",
                isPresented: $showRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove All Tags", role: .destructive) {
                    Task { @MainActor in
                        await viewModel.removeAllTags(from: spool)
                    }
                }
            }
        }
    }
}

// MARK: - SpoolInfoRow (used in ScanView)

struct SpoolInfoRow: View {
    let spool: SpoolResponse

    var body: some View {
        HStack(spacing: 12) {
            ColorSwatch(hex: spool.filament.colorHex, size: 36, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(spool.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let material = spool.filament.material {
                        Text(material)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                    if let remaining = spool.remainingWeight {
                        Text("\(Int(remaining)) g left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TagCountBadge(count: spool.tagCount)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Shared sub-views

struct ColorSwatch: View {
    let hex: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    private var color: Color? { hex.flatMap { Color(hex: $0) } }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(color ?? Color.secondary.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.primary.opacity(0.12)))
            if color == nil {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                    .font(size > 40 ? .body : .caption)
            }
        }
    }
}

struct TagCountBadge: View {
    let count: Int

    var body: some View {
        Text("Tags \(count)")
            .font(.caption)
            .fontWeight(.medium)
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(count > 0 ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
            .foregroundStyle(count > 0 ? Color.blue : Color.secondary)
    }
}

struct SpoolmanLoadErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Spoolman Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(label: String, value: String) where Content == Text {
        self.label = label
        self.content = { Text(value).fontWeight(.medium) }
    }

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SpoolsView(viewModel: SpoolmanViewModel())
}
