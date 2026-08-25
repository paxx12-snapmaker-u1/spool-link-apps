// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation
import SwiftUI

@Observable
class SpoolmanViewModel: NFCManagerDelegate {
    var isScanning = false
    var statusMessage = "Ready to scan"
    var scanHistory: [ScanResult] = []
    var lastResult: ScanResult?
    var spools: [SpoolResponse] = []
    var isFetchingSpools = false
    var spoolsErrorMessage: String?
    var hasMoreSpools = false
    var pendingAssignSpool: SpoolResponse?
    var isCreatingSpool = false
    var availableFilaments: [SpoolmanAPI.FilamentResponse] = []
    var isLoadingFilaments = false
    var filamentsErrorMessage: String?
    private var spoolsOffset = 0
    private let spoolsPageSize = 20

    private let api: SpoolmanAPI
    let nfcManager: NFCManager

    init(baseURL: String = "http://spoolman.local:7912") {
        self.api = SpoolmanAPI(baseURL: baseURL)
        self.nfcManager = NFCManager()
        self.nfcManager.delegate = self
    }

    func updateBaseURL(_ url: String) {
        Task { await api.updateBaseURL(url) }
    }

    // MARK: - Spool list

    @MainActor
    func ensureSpoolsLoaded() {
        guard spools.isEmpty && !isFetchingSpools else { return }
        fetchSpools()
    }

    @MainActor
    func fetchSpools(reset: Bool = true) {
        guard !isFetchingSpools else { return }
        let offset = reset ? 0 : spoolsOffset
        isFetchingSpools = true
        spoolsErrorMessage = nil
        Task {
            do {
                let page = try await api.fetchSpools(limit: spoolsPageSize, offset: offset)
                let active = page.filter { !$0.archived }
                if reset {
                    spools = active
                } else {
                    spools += active
                }
                spoolsOffset = offset + page.count
                hasMoreSpools = page.count == spoolsPageSize
            } catch {
                spoolsErrorMessage = error.localizedDescription
                hasMoreSpools = false
            }
            isFetchingSpools = false
        }
    }

    @MainActor
    func loadMoreSpools() {
        guard hasMoreSpools && !isFetchingSpools else { return }
        fetchSpools(reset: false)
    }

    @MainActor
    @discardableResult
    func refreshSpool(id: Int) async -> SpoolResponse? {
        guard let updated = try? await api.getSpool(id: id) else { return nil }
        if let idx = spools.firstIndex(where: { $0.id == id }) {
            spools[idx] = updated
        }
        for i in scanHistory.indices where scanHistory[i].spoolId == id {
            scanHistory[i] = scanHistory[i].withSpoolResponse(updated)
        }
        if lastResult?.spoolId == id {
            lastResult = lastResult?.withSpoolResponse(updated)
        }
        return updated
    }

    // MARK: - Tag removal

    @MainActor
    func removeAllTags(from spool: SpoolResponse) async {
        try? await api.updateSpoolCardUids(id: spool.id, uids: [])
        await refreshSpool(id: spool.id)
        if let result = lastResult, result.spoolId == spool.id {
            lastResult = ScanResult(
                id: result.id, timestamp: result.timestamp,
                spoolId: nil, spoolName: result.spoolName,
                cardUid: result.cardUid, success: result.success,
                message: result.message, tagPayload: result.tagPayload,
                spoolResponse: nil
            )
            statusMessage = "Tag unlinked from \(spool.displayName)"
        }
    }

    @MainActor
    func removeTag(uidHex: String, from spool: SpoolResponse) async {
        let updatedUIDs = spool.tagUIDs.filter { $0.uppercased() != uidHex.uppercased() }
        try? await api.updateSpoolCardUids(id: spool.id, uids: updatedUIDs)
        await refreshSpool(id: spool.id)
        if let result = lastResult, result.spoolId == spool.id {
            lastResult = ScanResult(
                id: result.id, timestamp: result.timestamp,
                spoolId: nil, spoolName: result.spoolName,
                cardUid: result.cardUid, success: result.success,
                message: result.message, tagPayload: result.tagPayload,
                spoolResponse: nil
            )
            statusMessage = "Tag unlinked from \(spool.displayName)"
        }
    }

    // MARK: - Filament list

    @MainActor
    func loadFilamentsIfNeeded() {
        guard availableFilaments.isEmpty && !isLoadingFilaments else { return }
        loadFilaments()
    }

    @MainActor
    func loadFilaments() {
        guard !isLoadingFilaments else { return }
        isLoadingFilaments = true
        filamentsErrorMessage = nil
        Task {
            do {
                availableFilaments = try await api.fetchFilaments(limit: 1000, offset: 0)
            } catch {
                filamentsErrorMessage = error.localizedDescription
            }
            isLoadingFilaments = false
        }
    }

    // MARK: - Spool creation

    @MainActor
    @discardableResult
    func createSpoolFromTag(tagPayload: (any NFCTagPayload)? = nil, uidHex: String = "",
                            overrideMeta: FilamentMetadata? = nil,
                            selectedFilamentId: Int? = nil) async -> SpoolResponse? {
        isCreatingSpool = true
        statusMessage = "Creating spool…"
        defer { isCreatingSpool = false }
        do {
            let newSpool: SpoolResponse
            if let meta = overrideMeta ?? tagPayload?.filamentMetadata {
                let styleRaw = UserDefaults.standard.string(forKey: "filamentNameStyle") ?? ""
                let nameStyle = FilamentNameStyle(rawValue: styleRaw) ?? .brandAndSubtype
                let vendorId: Int?
                if let brand = meta.brand {
                    vendorId = try await api.findOrCreateVendor(name: brand)
                } else {
                    vendorId = nil
                }
                let filamentId: Int
                if let selectedFilamentId {
                    filamentId = selectedFilamentId
                } else {
                    filamentId = try await api.createFilamentFromInfo(
                        name: meta.filamentName(style: nameStyle),
                        vendorId: vendorId,
                        material: meta.material,
                        colorHex: meta.colorHex,
                        diameter: meta.diameter ?? 1.75,
                        weight: meta.weight,
                        nozzleTemp: meta.nozzleTemp,
                        bedTemp: meta.bedTemp,
                        variant: meta.subtype
                    )
                }
                newSpool = try await api.createSpoolFromInfo(
                    filamentId: filamentId,
                    cardUid: uidHex.isEmpty ? nil : uidHex
                )
            } else {
                statusMessage = "Missing filament details"
                return nil
            }
            statusMessage = "Spool created: \(newSpool.displayName)"
            if let idx = scanHistory.firstIndex(where: { $0.cardUid == uidHex }) {
                let old = scanHistory[idx]
                scanHistory[idx] = ScanResult(
                    id: old.id, timestamp: old.timestamp,
                    spoolId: newSpool.id, spoolName: newSpool.displayName,
                    cardUid: uidHex, success: true, message: "Spool created",
                    tagPayload: old.tagPayload, spoolResponse: newSpool
                )
                lastResult = scanHistory[idx]
            }
            fetchSpools(reset: true)
            return newSpool
        } catch {
            statusMessage = "Error creating spool: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - NFC delegate

    func startScanning() {
        lastResult = nil
        nfcManager.startScanning()
        isScanning = nfcManager.isScanning
        statusMessage = nfcManager.sessionMessage
    }

    func stopScanning() {
        nfcManager.stopScanning()
        isScanning = false
        statusMessage = nfcManager.sessionMessage
    }

    func startTagAssignment(for spool: SpoolResponse) {
        pendingAssignSpool = spool
        lastResult = nil
        nfcManager.startScanning()
        isScanning = nfcManager.isScanning
        statusMessage = "Scan tag to assign to \(spool.displayName)…"
    }

    func cancelTagAssignment() {
        pendingAssignSpool = nil
        nfcManager.stopScanning()
        isScanning = false
        statusMessage = "Ready to scan"
    }

    func nfcManager(_ manager: NFCManager, didReadTag payload: any NFCTagPayload, uidHex: String) {
        let pending = pendingAssignSpool
        pendingAssignSpool = nil
        isScanning = false
        statusMessage = "Tag detected"
        Task { @MainActor in
            if let spool = pending {
                await processAssignment(spool: spool, uidHex: uidHex, tagPayload: payload)
            } else {
                await processTag(payload: payload, uidHex: uidHex)
            }
        }
    }

    func nfcManager(_ manager: NFCManager, didFailWithError error: Error) {
        isScanning = false
        pendingAssignSpool = nil
        statusMessage = "Error: \(error.localizedDescription)"
    }

    func nfcManagerDidInvalidateSession(_ manager: NFCManager, error: Error?) {
        isScanning = false
        pendingAssignSpool = nil
        if let error { statusMessage = "Session ended: \(error.localizedDescription)" }
    }

    // MARK: - Tag processing

    @MainActor
    func processTag(payload: any NFCTagPayload, uidHex: String) async {
        guard let spoolId = payload.spoolId else {
            let foundSpool = try? await api.findSpoolsByCardUid(uidHex).first
            let result = ScanResult(
                spoolId: foundSpool?.id,
                spoolName: foundSpool?.displayName ?? payload.displayTitle,
                cardUid: uidHex,
                success: true,
                message: "Tag read (no Spoolman link)",
                tagPayload: payload,
                spoolResponse: foundSpool
            )
            statusMessage = "Tag read: \(payload.displayTitle)"
            scanHistory.insert(result, at: 0)
            lastResult = result
            return
        }

        statusMessage = "Fetching spool \(spoolId)…"

        do {
            let spool = try await api.getSpool(id: spoolId)
            let spoolName = spool.displayName

            let currentUIDs = spool.tagUIDs
            let updatedUIDs = currentUIDs.contains(uidHex) ? currentUIDs : currentUIDs + [uidHex]

            statusMessage = "Updating spool…"
            try await api.updateSpoolCardUids(id: spoolId, uids: updatedUIDs)

            statusMessage = "Cleaning up other spools…"
            let matchingSpools = try await api.findSpoolsByCardUid(uidHex)
            for otherSpool in matchingSpools where otherSpool.id != spoolId {
                let cleaned = otherSpool.tagUIDs.filter { $0 != uidHex }
                if cleaned.count != otherSpool.tagUIDs.count {
                    try await api.updateSpoolCardUids(id: otherSpool.id, uids: cleaned)
                    await refreshSpool(id: otherSpool.id)
                }
            }

            let updatedSpool = await refreshSpool(id: spoolId) ?? spool
            statusMessage = "Synced: \(spoolName)"
            let result = ScanResult(
                spoolId: spoolId,
                spoolName: spoolName,
                cardUid: uidHex,
                success: true,
                message: "Synced successfully",
                tagPayload: payload,
                spoolResponse: updatedSpool
            )
            scanHistory.insert(result, at: 0)
            lastResult = result

        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            let result = ScanResult(
                spoolId: spoolId,
                spoolName: payload.displayTitle,
                cardUid: uidHex,
                success: false,
                message: error.localizedDescription,
                tagPayload: payload
            )
            scanHistory.insert(result, at: 0)
            lastResult = result
        }
    }

    @MainActor
    func processAssignment(spool: SpoolResponse, uidHex: String, tagPayload: any NFCTagPayload) async {
        statusMessage = "Assigning tag to \(spool.displayName)…"

        do {
            let currentUIDs = spool.tagUIDs
            let updatedUIDs = currentUIDs.contains(uidHex) ? currentUIDs : currentUIDs + [uidHex]
            try await api.updateSpoolCardUids(id: spool.id, uids: updatedUIDs)

            let matchingSpools = try await api.findSpoolsByCardUid(uidHex)
            for otherSpool in matchingSpools where otherSpool.id != spool.id {
                let cleaned = otherSpool.tagUIDs.filter { $0 != uidHex }
                if cleaned.count != otherSpool.tagUIDs.count {
                    try await api.updateSpoolCardUids(id: otherSpool.id, uids: cleaned)
                    await refreshSpool(id: otherSpool.id)
                }
            }

            let updatedSpool = await refreshSpool(id: spool.id) ?? spool
            statusMessage = "Tag assigned to \(spool.displayName)"
            let result = ScanResult(
                spoolId: spool.id,
                spoolName: spool.displayName,
                cardUid: uidHex,
                success: true,
                message: "Tag assigned",
                tagPayload: tagPayload,
                spoolResponse: updatedSpool
            )
            scanHistory.insert(result, at: 0)
            lastResult = result

        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
