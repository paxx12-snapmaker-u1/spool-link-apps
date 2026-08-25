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

    func compare(_ a: SpoolResponse, _ b: SpoolResponse, ascending: Bool) -> Bool {
        let flip: (Bool) -> Bool = { ascending ? $0 : !$0 }
        switch self {
        case .dateAdded:
            return flip((a.registered ?? .distantPast) > (b.registered ?? .distantPast))
        case .lastUsed:
            return flip((a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast))
        case .name:
            return flip(a.displayName < b.displayName)
        case .material:
            return flip((a.filament.material ?? "") < (b.filament.material ?? ""))
        case .remaining:
            return flip((a.remainingWeight ?? 0) > (b.remainingWeight ?? 0))
        case .tags:
            return flip(a.tagCount > b.tagCount)
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
            return spool.filament.material ?? "Unknown"
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
        var result: [(String, [SpoolResponse])] = []
        for spool in sorted {
            let h = sectionHeader(for: spool)
            if result.last?.0 == h {
                result[result.count - 1].1.append(spool)
            } else {
                result.append((h, [spool]))
            }
        }
        return result.map { (header: $0.0, items: $0.1) }
    }
}

// MARK: - SpoolsView

struct SpoolsView: View {
    @Bindable var viewModel: SpoolmanViewModel
    @State private var selectedSpool: SpoolResponse?
    @AppStorage("spoolsSortBy") private var sortByRaw: String = SpoolSort.dateAdded.rawValue
    @AppStorage("spoolsSortAscending") private var sortAscending = true

    private var sortBy: SpoolSort { SpoolSort(rawValue: sortByRaw) ?? .dateAdded }

    private var groupedSpools: [(header: String, items: [SpoolResponse])] {
        sortBy.grouped(viewModel.spools, ascending: sortAscending)
    }

    private var duplicateTagUIDs: Set<String> {
        var counts: [String: Int] = [:]
        for s in viewModel.spools {
            for uid in s.tagUIDs { counts[uid, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    @ViewBuilder private var spoolsContent: some View {
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
                ForEach(groupedSpools, id: \.header) { group in
                    Section(group.header) {
                        ForEach(group.items) { spool in
                            SpoolRow(spool: spool, hasConflict: spool.tagUIDs.contains { duplicateTagUIDs.contains($0) })
                                .contentShape(Rectangle())
                                .onTapGesture { selectedSpool = spool }
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
            .refreshable { viewModel.fetchSpools(reset: true) }
        }
    }

    var body: some View {
        NavigationStack {
            spoolsContent
                .navigationTitle("Spools")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { viewModel.fetchSpools(reset: true) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isFetchingSpools)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu
                    }
                }
                .sheet(item: $selectedSpool) { spool in
                    SpoolDetailSheet(spool: spool, viewModel: viewModel)
                }
        }
        .onAppear {
            if viewModel.spools.isEmpty { viewModel.fetchSpools() }
        }
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
