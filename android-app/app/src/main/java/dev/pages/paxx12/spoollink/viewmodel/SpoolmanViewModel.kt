// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

package dev.pages.paxx12.spoollink.viewmodel

import android.app.Application
import android.content.Context
import android.nfc.NdefMessage
import android.nfc.Tag
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dev.pages.paxx12.spoollink.api.SpoolmanApi
import dev.pages.paxx12.spoollink.formats.MifareClassicReader
import dev.pages.paxx12.spoollink.formats.NtagReader
import dev.pages.paxx12.spoollink.formats.SnapmakerFormat
import dev.pages.paxx12.spoollink.formats.SnapmakerTagPayload
import dev.pages.paxx12.spoollink.formats.TagFormatParser
import dev.pages.paxx12.spoollink.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class SpoolmanViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("spoolman_prefs", Context.MODE_PRIVATE)
    private val defaultBaseUrl = "http://spoolman.local:7912"

    var baseUrl by mutableStateOf(
        SpoolmanApi.normalizeUrl(prefs.getString("base_url", defaultBaseUrl) ?: defaultBaseUrl)
    )
        private set

    private var api = SpoolmanApi(baseUrl)

    var isScanning by mutableStateOf(false)
        private set
    var statusMessage by mutableStateOf("Ready to scan")
        private set
    val scanHistory = mutableStateListOf<ScanResult>()
    var lastResult by mutableStateOf<ScanResult?>(null)
        private set
    /** Outcome of the most recent tag assignment, shown where it was started. */
    var lastAssignmentResult by mutableStateOf<ScanResult?>(null)
        private set
    /** Set when an assignment would take a tag from another spool; the UI must confirm or decline it. */
    var pendingTagMove by mutableStateOf<PendingTagMove?>(null)
        private set
    /** An assignment error to present as a dialog. */
    var assignmentError by mutableStateOf<TagAssignmentError?>(null)
        private set
    val spools = mutableStateListOf<SpoolResponse>()
    var isFetchingSpools by mutableStateOf(false)
        private set
    var hasMoreSpools by mutableStateOf(false)
        private set
    var spoolsError by mutableStateOf<String?>(null)
        private set
    var pendingAssignSpool by mutableStateOf<SpoolResponse?>(null)
        private set
    var isCreatingSpool by mutableStateOf(false)
        private set
    val availableFilaments = mutableStateListOf<SpoolResponse.FilamentResponse>()
    var isLoadingFilaments by mutableStateOf(false)
        private set
    var filamentsErrorMessage by mutableStateOf<String?>(null)
        private set
    var filamentPresets by mutableStateOf(FilamentPresets.load(prefs))

    private var spoolsOffset = 0
    private val spoolsPageSize = 20

    fun savedBaseUrl(): String = baseUrl

    fun updateBaseUrl(url: String) {
        val normalized = SpoolmanApi.normalizeUrl(url)
        baseUrl = normalized
        prefs.edit().putString("base_url", normalized).apply()
        api.updateBaseUrl(normalized)
    }

    fun savedNameStyle(): FilamentNameStyle =
        FilamentNameStyle.fromName(prefs.getString("filamentNameStyle", null))

    fun saveNameStyle(style: FilamentNameStyle) {
        prefs.edit().putString("filamentNameStyle", style.name).apply()
    }

    fun updatePresets(presets: FilamentPresets) {
        filamentPresets = presets
        presets.save(prefs)
    }

    fun savedStoreRawTags(): Boolean = prefs.getBoolean("store_raw_tags", false)

    fun saveStoreRawTags(enabled: Boolean) {
        prefs.edit().putBoolean("store_raw_tags", enabled).apply()
    }

    fun ensureSpoolsLoaded() {
        if (spools.isEmpty() && !isFetchingSpools) fetchSpools()
    }

    fun fetchSpools(reset: Boolean = true) {
        if (isFetchingSpools) return
        val offset = if (reset) 0 else spoolsOffset
        isFetchingSpools = true
        viewModelScope.launch {
            try {
                spoolsError = null
                val page = api.fetchSpools(limit = spoolsPageSize, offset = offset)
                val active = page.filter { !it.archived }
                if (reset) {
                    spools.clear()
                    spools.addAll(active)
                } else {
                    spools.addAll(active)
                }
                spoolsOffset = offset + page.size
                hasMoreSpools = page.size == spoolsPageSize
            } catch (e: Exception) {
                spoolsError = e.message ?: "Unable to load spools"
                hasMoreSpools = false
            }
            isFetchingSpools = false
        }
    }

    fun loadMoreSpools() {
        if (hasMoreSpools && !isFetchingSpools) fetchSpools(reset = false)
    }

    suspend fun refreshSpool(id: Int): SpoolResponse? {
        val updated = try { api.getSpool(id) } catch (_: Exception) { return null }
        val idx = spools.indexOfFirst { it.id == id }
        if (idx >= 0) spools[idx] = updated
        for (i in 0 until scanHistory.size) {
            if (scanHistory[i].spoolId == id) scanHistory[i] = scanHistory[i].withSpoolResponse(updated)
        }
        if (lastResult?.spoolId == id) lastResult = lastResult?.withSpoolResponse(updated)
        return updated
    }

    fun removeTag(uidHex: String, spool: SpoolResponse) {
        viewModelScope.launch {
            try {
                // The caller's spool may be a stale snapshot; filtering it would drop tags assigned since.
                val currentUIDs = runCatching { api.getSpool(spool.id).tagUIDs }.getOrDefault(spool.tagUIDs)
                val updatedUIDs = currentUIDs.filter { it.uppercase() != uidHex.uppercase() }
                api.updateSpoolCardUids(spool.id, updatedUIDs)
                refreshSpool(spool.id)
                if (lastResult?.spoolId == spool.id) {
                    lastResult = lastResult?.let {
                        ScanResult(it.id, it.timestamp, null, it.spoolName,
                            it.cardUid, it.success, it.message, it.tagPayload, null)
                    }
                    statusMessage = "Tag unlinked from ${spool.displayName}"
                }
            } catch (_: Exception) { }
        }
    }

    fun removeAllTags(spool: SpoolResponse) {
        viewModelScope.launch {
            try {
                api.updateSpoolCardUids(spool.id, emptyList())
                refreshSpool(spool.id)
                if (lastResult?.spoolId == spool.id) {
                    lastResult = lastResult?.let {
                        ScanResult(
                            it.id,
                            it.timestamp,
                            null,
                            it.spoolName,
                            it.cardUid,
                            it.success,
                            it.message,
                            it.tagPayload,
                            null
                        )
                    }
                    statusMessage = "Tag unlinked from ${spool.displayName}"
                }
            } catch (_: Exception) { }
        }
    }

    fun startScanning() {
        lastResult = null
        isScanning = true
        statusMessage = "Scanning for NFC tags…"
    }

    fun stopScanning() {
        isScanning = false
        statusMessage = "Ready to scan"
    }

    fun startTagAssignment(spool: SpoolResponse) {
        pendingAssignSpool = spool
        lastResult = null
        lastAssignmentResult = null
        isScanning = true
        statusMessage = "Scan tag to assign to ${spool.displayName}…"
    }

    fun cancelTagAssignment() {
        pendingAssignSpool = null
        isScanning = false
        statusMessage = "Ready to scan"
    }

    private enum class TagKind { MIFARE, NTAG, OTHER }

    private fun tagKind(tag: Tag): TagKind {
        val techs = tag.techList
        return when {
            techs.contains("android.nfc.tech.MifareClassic") -> TagKind.MIFARE
            techs.contains("android.nfc.tech.MifareUltralight") ||
                techs.contains("android.nfc.tech.NfcA") -> TagKind.NTAG
            else -> TagKind.OTHER
        }
    }

    fun processNfcTag(tag: Tag, ndefMessage: NdefMessage?) {
        val activeSession = isScanning || pendingAssignSpool != null
        val storeRaw = savedStoreRawTags()
        if (!activeSession && !storeRaw) return
        val uidHex = tag.id.joinToString("") { "%02X".format(it) }
        if (activeSession) {
            isScanning = false
            statusMessage = "Tag detected"
        }
        val pending = pendingAssignSpool
        if (activeSession) pendingAssignSpool = null
        val kind = tagKind(tag)
        viewModelScope.launch {
            var rawBytes: ByteArray? = null
            val payload: NFCTagPayload
            if (kind == TagKind.MIFARE) {
                val snapmakerResult = withContext(Dispatchers.IO) {
                    SnapmakerFormat.tryReadWithRaw(tag)
                }
                if (snapmakerResult != null) {
                    val (snapmakerPayload, snapmakerRaw) = snapmakerResult
                    rawBytes = snapmakerRaw
                    payload = snapmakerPayload
                    if (storeRaw) withContext(Dispatchers.IO) { saveSnapmakerTag(snapmakerPayload) }
                } else {
                    val mifareRaw = withContext(Dispatchers.IO) { MifareClassicReader.tryReadRaw(tag) }
                    rawBytes = mifareRaw
                    val resolvedNdef = mifareRaw?.let(MifareClassicReader::parseNdefTlvPublic)
                        ?: ndefMessage
                    payload = TagFormatParser.parse(resolvedNdef, tag)
                }
            } else {
                if (kind == TagKind.NTAG) {
                    rawBytes = withContext(Dispatchers.IO) { NtagReader.tryReadRaw(tag) }
                }
                payload = TagFormatParser.parse(ndefMessage, tag)
            }
            if (storeRaw) {
                rawBytes?.let { bytes -> withContext(Dispatchers.IO) { saveRawTag(kind, uidHex, bytes) } }
            }
            if (activeSession) {
                if (pending != null) {
                    processAssignment(pending, uidHex, payload)
                } else {
                    processTag(payload, uidHex)
                }
            }
        }
    }

    private fun saveSnapmakerTag(payload: SnapmakerTagPayload) {
        try {
            val dir = getApplication<android.app.Application>()
                .getExternalFilesDir("snapmaker") ?: return
            dir.mkdirs()
            File(dir, "${payload.uid}.json").writeText(payload.toJson())
        } catch (_: Exception) { }
    }

    private fun saveRawTag(kind: TagKind, uidHex: String, raw: ByteArray) {
        val subdir = when (kind) {
            TagKind.MIFARE -> "tags/mifare"
            TagKind.NTAG -> "tags/ntag"
            TagKind.OTHER -> return
        }
        try {
            val dir = getApplication<android.app.Application>()
                .getExternalFilesDir(subdir) ?: return
            dir.mkdirs()
            File(dir, "$uidHex.bin").writeBytes(raw)
        } catch (_: Exception) { }
    }

    suspend fun processTag(payload: NFCTagPayload, uidHex: String) {
        if (payload.spoolId == null) {
            val foundSpool = try { api.findSpoolsByCardUid(uidHex).firstOrNull() } catch (_: Exception) { null }
            val result = ScanResult(
                spoolId = foundSpool?.id,
                spoolName = foundSpool?.displayName ?: payload.displayTitle,
                cardUid = uidHex,
                success = true,
                message = "Tag read (no Spoolman link)",
                tagPayload = payload,
                spoolResponse = foundSpool
            )
            statusMessage = "Tag read: ${payload.displayTitle}"
            scanHistory.add(0, result)
            lastResult = result
            return
        }

        val spoolId = payload.spoolId ?: return
        statusMessage = "Fetching spool $spoolId…"
        try {
            val spool = api.getSpool(spoolId)
            val currentUIDs = spool.tagUIDs
            val updatedUIDs = if (currentUIDs.contains(uidHex)) currentUIDs else currentUIDs + uidHex

            statusMessage = "Updating spool…"
            api.updateSpoolCardUids(spoolId, updatedUIDs)

            statusMessage = "Cleaning up other spools…"
            val matching = api.findSpoolsByCardUid(uidHex)
            for (other in matching) {
                if (other.id == spoolId) continue
                val cleaned = other.tagUIDs.filter { it != uidHex }
                if (cleaned.size != other.tagUIDs.size) {
                    api.updateSpoolCardUids(other.id, cleaned)
                    refreshSpool(other.id)
                }
            }

            val updatedSpool = refreshSpool(spoolId) ?: spool
            statusMessage = "Synced: ${spool.displayName}"
            val result = ScanResult(
                spoolId = spoolId,
                spoolName = spool.displayName,
                cardUid = uidHex,
                success = true,
                message = "Synced successfully",
                tagPayload = payload,
                spoolResponse = updatedSpool
            )
            scanHistory.add(0, result)
            lastResult = result
        } catch (e: Exception) {
            statusMessage = "Error: ${e.message}"
            val result = ScanResult(
                spoolId = spoolId,
                spoolName = payload.displayTitle,
                cardUid = uidHex,
                success = false,
                message = e.message ?: "Unknown error",
                tagPayload = payload,
                spoolResponse = null
            )
            scanHistory.add(0, result)
            lastResult = result
        }
    }

    /**
     * Assigns a scanned tag to [spool]. Rejects a tag the spool already has. Before taking a tag away from
     * another spool it asks for confirmation (via [pendingTagMove]), unless [confirmMove] is false because the
     * user already saw where the tag was when choosing the spool.
     */
    suspend fun processAssignment(
        spool: SpoolResponse,
        uidHex: String,
        tagPayload: NFCTagPayload,
        confirmMove: Boolean = true
    ): TagAssignmentOutcome {
        statusMessage = "Assigning tag to ${spool.displayName}…"
        return try {
            // The caller's spool may be a stale snapshot; building on it would drop tags assigned since.
            val freshSpool = api.getSpool(spool.id)
            val otherOwners = api.findSpoolsByCardUid(uidHex).filter { it.id != spool.id }
            when {
                otherOwners.isNotEmpty() && !confirmMove ->
                    confirmTagMove(PendingTagMove(freshSpool, uidHex, tagPayload, otherOwners))
                otherOwners.isNotEmpty() -> {
                    pendingTagMove = PendingTagMove(freshSpool, uidHex, tagPayload, otherOwners)
                    statusMessage = "Confirm moving tag to ${spool.displayName}"
                    TagAssignmentOutcome.NEEDS_CONFIRMATION
                }
                freshSpool.tagUIDs.contains(uidHex) -> {
                    recordAssignmentFailure(freshSpool, uidHex, tagPayload, "Tag Already Assigned",
                        "This tag is already assigned to ${spool.displayName} (#${spool.id}).")
                    TagAssignmentOutcome.ALREADY_ASSIGNED
                }
                else -> {
                    api.updateSpoolCardUids(spool.id, freshSpool.tagUIDs + uidHex)
                    recordAssignmentSuccess(freshSpool, uidHex, tagPayload, "Tag assigned")
                    TagAssignmentOutcome.ASSIGNED
                }
            }
        } catch (e: Exception) {
            recordAssignmentFailure(spool, uidHex, tagPayload, "Couldn't Assign Tag", e.message ?: "Unknown error")
            TagAssignmentOutcome.FAILED
        }
    }

    /** Completes a move the user confirmed: adds the tag to the target spool and removes it from all others. */
    suspend fun confirmTagMove(move: PendingTagMove): TagAssignmentOutcome {
        if (pendingTagMove?.id == move.id) pendingTagMove = null
        statusMessage = "Moving tag to ${move.spool.displayName}…"
        return try {
            // Re-read both sides: the confirmation may have been open for a while.
            val target = api.getSpool(move.spool.id)
            if (!target.tagUIDs.contains(move.uidHex)) {
                api.updateSpoolCardUids(target.id, target.tagUIDs + move.uidHex)
            }
            for (other in api.findSpoolsByCardUid(move.uidHex)) {
                if (other.id == target.id) continue
                api.updateSpoolCardUids(other.id, other.tagUIDs.filter { it != move.uidHex })
                refreshSpool(other.id)
            }
            recordAssignmentSuccess(target, move.uidHex, move.tagPayload, "Tag moved from ${move.ownersDescription}")
            TagAssignmentOutcome.MOVED
        } catch (e: Exception) {
            recordAssignmentFailure(move.spool, move.uidHex, move.tagPayload, "Couldn't Move Tag",
                e.message ?: "Unknown error")
            TagAssignmentOutcome.FAILED
        }
    }

    /** The user declined the move; nothing was written. */
    fun declineTagMove() {
        val move = pendingTagMove ?: return
        pendingTagMove = null
        statusMessage = "Tag not moved"
        lastAssignmentResult = ScanResult(
            spoolId = move.spool.id,
            spoolName = move.spool.displayName,
            cardUid = move.uidHex,
            success = false,
            message = "Tag not moved — still on ${move.ownersDescription}",
            tagPayload = move.tagPayload,
            spoolResponse = move.spool
        )
    }

    fun dismissAssignmentError() {
        assignmentError = null
    }

    private suspend fun recordAssignmentSuccess(spool: SpoolResponse, uidHex: String, tagPayload: NFCTagPayload,
                                                message: String) {
        val updatedSpool = refreshSpool(spool.id) ?: spool
        statusMessage = "$message — ${spool.displayName}"
        val result = ScanResult(
            spoolId = spool.id,
            spoolName = spool.displayName,
            cardUid = uidHex,
            success = true,
            message = message,
            tagPayload = tagPayload,
            spoolResponse = updatedSpool
        )
        scanHistory.add(0, result)
        lastResult = result
        lastAssignmentResult = result
    }

    private fun recordAssignmentFailure(spool: SpoolResponse, uidHex: String, tagPayload: NFCTagPayload,
                                        title: String, message: String) {
        statusMessage = "$title: $message"
        val result = ScanResult(
            spoolId = spool.id,
            spoolName = spool.displayName,
            cardUid = uidHex,
            success = false,
            message = title,
            tagPayload = tagPayload,
            spoolResponse = spool
        )
        scanHistory.add(0, result)
        lastResult = result
        lastAssignmentResult = result
        assignmentError = TagAssignmentError(title, message)
    }

    fun loadFilamentsIfNeeded() {
        if (availableFilaments.isNotEmpty() || isLoadingFilaments) return
        loadFilaments()
    }

    fun loadFilaments() {
        if (isLoadingFilaments) return
        isLoadingFilaments = true
        filamentsErrorMessage = null
        viewModelScope.launch {
            try {
                val filaments = api.fetchFilaments(limit = 1000, offset = 0)
                availableFilaments.clear()
                availableFilaments.addAll(filaments)
            } catch (e: Exception) {
                filamentsErrorMessage = e.message
            } finally {
                isLoadingFilaments = false
            }
        }
    }

    suspend fun createSpoolFromTag(
        tagPayload: NFCTagPayload,
        uidHex: String,
        overrideMeta: FilamentMetadata? = null,
        selectedFilamentId: Int? = null
    ) {
        isCreatingSpool = true
        statusMessage = "Creating spool…"
        try {
            val meta = overrideMeta ?: tagPayload.filamentMetadata
            val nameStyle = savedNameStyle()
            val filamentId = if (selectedFilamentId != null) {
                selectedFilamentId
            } else {
                if (meta == null) {
                    statusMessage = "Missing filament details"
                    isCreatingSpool = false
                    return
                }
                val vendorId = meta.brand?.let {
                    try { api.findOrCreateVendor(it) } catch (_: Exception) { null }
                }
                api.createFilamentFromInfo(
                    filamentName = meta.filamentName(nameStyle),
                    vendorId = vendorId,
                    material = meta.material,
                    colorHex = meta.colorHex,
                    diameter = meta.diameter ?: 1.75,
                    weight = meta.weight,
                    nozzleTemp = meta.nozzleTemp,
                    bedTemp = meta.bedTemp,
                    variant = meta.subtype
                )
            }
            val newSpool = api.createSpoolFromInfo(
                filamentId = filamentId,
                cardUid = uidHex
            )
            statusMessage = "Spool created: ${newSpool.displayName}"
            val idx = scanHistory.indexOfFirst { it.cardUid == uidHex }
            if (idx >= 0) {
                val old = scanHistory[idx]
                val updated = ScanResult(
                    old.id,
                    old.timestamp,
                    newSpool.id,
                    newSpool.displayName,
                    uidHex,
                    true,
                    "Spool created",
                    old.tagPayload,
                    newSpool
                )
                scanHistory[idx] = updated
                lastResult = updated
            }
            if (spools.isNotEmpty()) refreshSpool(newSpool.id)
        } catch (e: Exception) {
            statusMessage = "Error creating spool: ${e.message}"
        }
        isCreatingSpool = false
    }
}

/** Lets the caller decide what to do next, e.g. close the picker once the tag is assigned or moved. */
enum class TagAssignmentOutcome { ASSIGNED, MOVED, ALREADY_ASSIGNED, NEEDS_CONFIRMATION, FAILED }

/** A scanned tag that belongs to other spools, awaiting the user's OK to move it to [spool]. */
data class PendingTagMove(
    val spool: SpoolResponse,
    val uidHex: String,
    val tagPayload: NFCTagPayload,
    val currentOwners: List<SpoolResponse>,
    val id: String = java.util.UUID.randomUUID().toString()
) {
    val ownersDescription: String
        get() = currentOwners.joinToString(", ") { "${it.displayName} (#${it.id})" }
}

data class TagAssignmentError(val title: String, val message: String)
