// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

package dev.pages.paxx12.spoollink.api

import dev.pages.paxx12.spoollink.model.SpoolResponse
import dev.pages.paxx12.spoollink.model.TagStore
import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.io.IOException
import java.util.concurrent.TimeUnit

class SpoolmanApi(baseUrl: String, var tagStore: TagStore = TagStore.CARD_UIDS) {
    private var normalizedUrl = normalizeUrl(baseUrl)
    private var nativeTagsConfirmed = false
    private val gson = Gson()
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .callTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()
    private var service: SpoolmanService = buildService(normalizedUrl)

    fun updateBaseUrl(newUrl: String) {
        normalizedUrl = normalizeUrl(newUrl)
        service = buildService(normalizedUrl)
        nativeTagsConfirmed = false
    }

    private fun buildService(url: String): SpoolmanService = Retrofit.Builder()
        .baseUrl(url)
        .client(httpClient)
        .addConverterFactory(GsonConverterFactory.create(gson))
        .build()
        .create(SpoolmanService::class.java)

    suspend fun fetchSpools(limit: Int = 20, offset: Int = 0): List<SpoolResponse> =
        withContext(Dispatchers.IO) { service.fetchSpools(limit, offset).map { it.forStore(tagStore) } }

    suspend fun getSpool(id: Int): SpoolResponse =
        withContext(Dispatchers.IO) { service.getSpool(id).forStore(tagStore) }

    suspend fun findSpoolsByCardUid(uid: String): List<SpoolResponse> = withContext(Dispatchers.IO) {
        val upper = uid.uppercase()
        val candidates = if (tagStore == TagStore.NATIVE) {
            service.findSpoolsByTag(upper, limit = 1000, allowArchived = true)
        } else {
            service.findSpoolsByCardUidCandidateSpools(limit = 1000, allowArchived = true)
        }
        // Filtered in both stores: Spoolman older than v0.27.0 ignores `tag` and returns every spool.
        candidates.map { it.forStore(tagStore) }.filter { it.tagUIDs.contains(upper) }
    }

    /** Throws when native tags are selected but this server has none. */
    suspend fun requireTagStoreSupport() = withContext(Dispatchers.IO) {
        if (tagStore == TagStore.NATIVE) requireNativeTags()
    }

    private suspend fun serverHasNativeTags(): Boolean {
        if (nativeTagsConfirmed) return true
        nativeTagsConfirmed = TagStore.supportsNativeTags(service.fetchInfo().version.orEmpty())
        return nativeTagsConfirmed
    }

    private suspend fun requireNativeTags() {
        if (!serverHasNativeTags()) {
            val version = service.fetchInfo().version.orEmpty().ifEmpty { "unknown" }
            throw IOException("Native tags need Spoolman v0.27.0 or newer (server is $version)")
        }
    }

    /** Links the tag to the spool. Returns the id of another spool it had to be taken from, if any. */
    suspend fun linkTag(spool: SpoolResponse, uid: String): Int? = withContext(Dispatchers.IO) {
        val upper = uid.uppercase()
        if (tagStore == TagStore.CARD_UIDS) {
            if (upper !in spool.tagUIDs) updateSpoolCardUids(spool.id, spool.tagUIDs + upper)
            return@withContext null
        }
        requireTagStoreSupport()
        val holder = postNativeTag(spool.id, upper) ?: return@withContext null
        deleteNativeTag(holder, upper)
        if (postNativeTag(spool.id, upper) != null) throw IOException("Tag $upper is already linked")
        holder
    }

    /** Links without moving. Returns the id of another spool already holding the tag, if any. */
    private suspend fun postNativeTag(spoolId: Int, uid: String): Int? {
        val body = gson.toJson(JsonObject().apply { addProperty("uid", uid) })
            .toRequestBody("application/json".toMediaType())
        try {
            service.linkTag(spoolId, body)
            return null
        } catch (e: HttpException) {
            if (e.code() != 409) throw e
            val conflict = runCatching {
                gson.fromJson(e.response()?.errorBody()?.string(), TagConflictResponse::class.java)
            }.getOrNull()
            val holder = conflict?.spoolId
            if (holder == null || holder == spoolId) {
                throw IOException(conflict?.message ?: "Tag $uid is already linked")
            }
            return holder
        }
    }

    /**
     * Moves every link into [target] and removes it from the other store, following the U1 firmware's
     * `spoollink_migrate.py`. A UID that cannot be moved stays where it was and is reported; running
     * this again retries it. Returns log lines, ending with a summary.
     */
    suspend fun migrateTags(target: TagStore): List<String> = withContext(Dispatchers.IO) {
        val logs = mutableListOf<String>()
        val (moved, failed) = if (target == TagStore.NATIVE) migrateToNative(logs) else migrateToCardUids(logs)
        val suffix = if (failed > 0) "; $failed left in place, see above" else ""
        logs.add("✓ Moved $moved card(s) to ${target.displayName}$suffix.")
        logs
    }

    // A UID listed on several spools is kept for the user to resolve; one already tagged on
    // another spool is dropped, as that tag is the newer link.
    private suspend fun migrateToNative(logs: MutableList<String>): Pair<Int, Int> {
        requireNativeTags()
        val spools = service.findSpoolsByCardUidCandidateSpools(limit = 1000, allowArchived = true)
        fun entries(spool: SpoolResponse) = spool.cardUidEntries.map { it.uppercase() }.distinct()
        val owners = mutableMapOf<String, MutableList<Int>>()
        for (spool in spools) for (uid in entries(spool)) owners.getOrPut(uid) { mutableListOf() }.add(spool.id)
        var moved = 0
        var failed = 0
        for (spool in spools) {
            val uids = entries(spool)
            if (uids.isEmpty()) continue
            val keep = mutableListOf<String>()
            for (uid in uids) {
                val holders = owners.getValue(uid)
                if (holders.size > 1) {
                    logs.add("⚠ Card $uid is on spools ${holders.joinToString { "#$it" }}, not moved")
                    keep.add(uid)
                    failed++
                    continue
                }
                if (uid !in spool.nativeTagUIDs) {
                    val holder = try {
                        postNativeTag(spool.id, uid)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        logs.add("⚠ Card $uid on spool #${spool.id}: ${e.message}")
                        keep.add(uid)
                        failed++
                        continue
                    }
                    if (holder != null) {
                        logs.add("Card $uid on spool #${spool.id} is already tagged on spool #$holder, dropping it")
                        continue
                    }
                }
                moved++
            }
            if (keep != uids) updateSpoolCardUids(spool.id, keep)
        }
        return moved to failed
    }

    // Any other spool still listing a UID in `card_uids` has it removed, as the tag was the newer link.
    private suspend fun migrateToCardUids(logs: MutableList<String>): Pair<Int, Int> {
        if (!serverHasNativeTags()) return 0 to 0
        ensureCardUidsField()
        val spools = service.findSpoolsByCardUidCandidateSpools(limit = 1000, allowArchived = true)
        val tagged = spools.flatMap { spool -> spool.nativeTagUIDs.map { it to spool.id } }.toMap()
        var moved = 0
        var failed = 0
        for (spool in spools) {
            val uids = spool.cardUidEntries.map { it.uppercase() }.distinct()
            val keep = uids.filter { (tagged[it] ?: spool.id) == spool.id }
            for (uid in uids - keep.toSet()) {
                logs.add("Card $uid on spool #${spool.id} is tagged on spool #${tagged[uid]}, dropping it")
            }
            val merged = keep + spool.nativeTagUIDs.filter { it !in keep }
            if (merged != spool.cardUidEntries) updateSpoolCardUids(spool.id, merged)
            for (uid in spool.nativeTagUIDs) {
                try {
                    deleteNativeTag(spool.id, uid)
                    moved++
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    logs.add("⚠ Unlinking tag $uid from spool #${spool.id}: ${e.message}")
                    failed++
                }
            }
        }
        return moved to failed
    }

    private suspend fun ensureCardUidsField() {
        if (service.fetchSpoolFields().any { it.key == "card_uids" }) return
        val body = JsonObject().apply {
            addProperty("name", "Card UIDs")
            addProperty("field_type", "text")
            addProperty("order", 1)
            addProperty("default_value", gson.toJson(""))
        }
        service.createCardUidsField(gson.toJson(body).toRequestBody("application/json".toMediaType()))
    }

    suspend fun unlinkTag(spool: SpoolResponse, uid: String) = withContext(Dispatchers.IO) {
        if (tagStore == TagStore.NATIVE) {
            deleteNativeTag(spool.id, uid.uppercase())
        } else {
            updateSpoolCardUids(spool.id, spool.tagUIDs.filter { !it.equals(uid, ignoreCase = true) })
        }
    }

    suspend fun unlinkAllTags(spool: SpoolResponse) = withContext(Dispatchers.IO) {
        if (tagStore == TagStore.NATIVE) {
            spool.tagUIDs.forEach { deleteNativeTag(spool.id, it) }
        } else {
            updateSpoolCardUids(spool.id, emptyList())
        }
    }

    private suspend fun deleteNativeTag(spoolId: Int, uid: String) {
        val response = service.unlinkTag(spoolId, uid)
        if (!response.isSuccessful && response.code() != 404) throw HttpException(response)
    }

    private suspend fun updateSpoolCardUids(id: Int, uids: List<String>) {
        val obj = JsonObject()
        val extra = JsonObject()
        extra.addProperty("card_uids", jsonEncodeString(uids.joinToString(",")))
        obj.add("extra", extra)
        val body = gson.toJson(obj).toRequestBody("application/json".toMediaType())
        service.updateSpool(id, body)
    }

    suspend fun findOrCreateVendor(name: String): Int = withContext(Dispatchers.IO) {
        val vendors = service.fetchVendors()
        vendors.firstOrNull { it.name?.equals(name, ignoreCase = true) == true }?.id
            ?: run {
                val obj = JsonObject().apply { addProperty("name", name) }
                service.createVendor(gson.toJson(obj).toRequestBody("application/json".toMediaType())).id
            }
    }

    suspend fun fetchFilaments(limit: Int = 1000, offset: Int = 0): List<SpoolResponse.FilamentResponse> =
        withContext(Dispatchers.IO) { service.fetchFilaments(limit, offset) }

    suspend fun createFilamentFromInfo(
        filamentName: String,
        vendorId: Int?,
        material: String?,
        colorHex: String?,
        diameter: Double,
        weight: Double?,
        nozzleTemp: Int?,
        bedTemp: Int?,
        variant: String? = null
    ): Int = withContext(Dispatchers.IO) {
        val density = material?.let { materialDensity[it] } ?: 1.24
        val filObj = JsonObject().apply {
            addProperty("name", filamentName)
            vendorId?.let { addProperty("vendor_id", it) }
            material?.let { addProperty("material", it) }
            colorHex?.let { addProperty("color_hex", it) }
            addProperty("diameter", diameter)
            weight?.let { addProperty("weight", it) }
            addProperty("density", density)
            nozzleTemp?.let { addProperty("settings_extruder_temp", it) }
            bedTemp?.let { addProperty("settings_bed_temp", it) }
            variant?.let {
                val extra = JsonObject()
                extra.addProperty("variant", jsonEncodeString(it))
                add("extra", extra)
            }
        }
        service.createFilament(
            gson.toJson(filObj).toRequestBody("application/json".toMediaType())
        ).id
    }

    suspend fun createSpoolFromInfo(
        filamentId: Int,
        cardUid: String?
    ): SpoolResponse = withContext(Dispatchers.IO) {
        val spoolObj = JsonObject().apply {
            addProperty("filament_id", filamentId)
            if (tagStore == TagStore.CARD_UIDS) {
                cardUid?.let {
                    val extra = JsonObject()
                    extra.addProperty("card_uids", jsonEncodeString(it))
                    add("extra", extra)
                }
            }
        }
        val created = service.createSpool(
            gson.toJson(spoolObj).toRequestBody("application/json".toMediaType())
        ).forStore(tagStore)
        if (tagStore == TagStore.NATIVE && cardUid != null) {
            linkTag(created, cardUid)
            getSpool(created.id)
        } else {
            created
        }
    }

    private fun jsonEncodeString(value: String): String = gson.toJson(value)

    companion object {
        const val REQUEST_TIMEOUT_SECONDS = 3L

        private val materialDensity = mapOf(
            "PLA" to 1.24, "PETG" to 1.27, "ABS" to 1.04, "ASA" to 1.07,
            "TPU" to 1.21, "Nylon" to 1.12, "PA" to 1.12, "PC" to 1.19,
            "PVA" to 1.19, "HIPS" to 1.04, "PP" to 0.9
        )

        fun normalizeUrl(url: String): String {
            var s = url.trim()
            if (!s.startsWith("http://") && !s.startsWith("https://")) s = "http://$s"
            if (!s.endsWith("/")) s += "/"
            return s
        }

        data class ConnectionTestResult(
            val logs: List<String>,
            val error: String?,
            val succeeded: Boolean
        )

        suspend fun testConnection(baseUrl: String, tagStore: TagStore): ConnectionTestResult = withContext(Dispatchers.IO) {
            val logs = mutableListOf<String>()
            val normalized = normalizeUrl(baseUrl)
            val infoUrl = "${normalized}api/v1/info"
            logs.add("GET $infoUrl")
            val client = OkHttpClient.Builder()
                .connectTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .readTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .writeTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .callTimeout(REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .build()
            try {
                val request = Request.Builder().url(infoUrl).build()
                val start = System.currentTimeMillis()
                val response = client.newCall(request).execute()
                val ms = System.currentTimeMillis() - start
                logs.add("${response.code} ${response.message} (${ms}ms)")
                if (!response.isSuccessful) {
                    return@withContext ConnectionTestResult(logs, "Server error: ${response.code}", false)
                }
                val body = response.body?.string() ?: ""
                val json = try { com.google.gson.JsonParser().parse(body) } catch (_: Exception) { null }
                val jsonObject = json?.takeIf { it.isJsonObject }?.asJsonObject
                val version = jsonObject?.get("version")
                    ?.takeIf { !it.isJsonNull && it.isJsonPrimitive }
                    ?.asString
                if (version == null) {
                    response.header("content-type")?.let { logs.add("Content-Type: $it") }
                    if (body.isBlank()) logs.add("Empty response body")
                    else logs.add("Body preview: ${body.replace(Regex("\\s+"), " ").take(160)}")
                    logs.add("✗ Missing top-level version")
                    return@withContext ConnectionTestResult(logs, "Missing top-level version", false)
                }
                var detail = "Spoolman v$version"
                jsonObject.get("db_type")
                    ?.takeIf { !it.isJsonNull && it.isJsonPrimitive }
                    ?.asString
                    ?.let { detail += " ($it)" }
                jsonObject.get("git_commit")
                    ?.takeIf { !it.isJsonNull && it.isJsonPrimitive }
                    ?.asString
                    ?.let { detail += " $it" }
                logs.add("✓ $detail")
                if (tagStore == TagStore.NATIVE && !TagStore.supportsNativeTags(version)) {
                    val message = "Native tags need Spoolman v0.27.0 or newer"
                    logs.add("✗ $message")
                    return@withContext ConnectionTestResult(logs, message, false)
                }
            } catch (e: Exception) {
                logs.add("✗ ${e.message ?: "Unknown error"}")
                return@withContext ConnectionTestResult(logs, e.message, false)
            }

            val gson = Gson()
            suspend fun ensureField(entityType: String, key: String, name: String) {
                val listUrl = "${normalized}api/v1/field/$entityType"
                val createUrl = "${normalized}api/v1/field/$entityType/$key"
                logs.add("GET $listUrl")
                try {
                    val listReq = Request.Builder().url(listUrl).build()
                    val listResp = client.newCall(listReq).execute()
                    if (!listResp.isSuccessful) {
                        logs.add("⚠ could not read custom fields for $entityType")
                        return
                    }
                    val listBody = listResp.body?.string() ?: "[]"
                    val fields = try { gson.fromJson(listBody, Array<FieldResponse>::class.java).toList() }
                    catch (_: Exception) { emptyList() }

                    if (fields.any { it.key == key }) {
                        logs.add("✓ field $key exists")
                    } else {
                        logs.add("POST $createUrl")
                        val obj = JsonObject().apply {
                            addProperty("key", key)
                            addProperty("name", name)
                            addProperty("entity_type", entityType)
                            addProperty("field_type", "text")
                            addProperty("order", 1)
                            addProperty("default_value", gson.toJson(""))
                        }
                        val createReq = Request.Builder()
                            .url(createUrl)
                            .post(gson.toJson(obj).toRequestBody("application/json".toMediaType()))
                            .build()
                        val createResp = client.newCall(createReq).execute()
                        if (createResp.isSuccessful) {
                            logs.add("✓ field $key created")
                        } else {
                            val errorBody = createResp.body?.string().orEmpty()
                            logs.add("⚠ could not create field $key: $errorBody")
                        }
                    }
                } catch (e: Exception) {
                    logs.add("⚠ custom fields check failed: ${e.message ?: "Unknown error"}")
                }
            }
            if (tagStore == TagStore.CARD_UIDS) ensureField("spool", "card_uids", "Card UIDs")
            ensureField("filament", "variant", "Variant")

            ConnectionTestResult(logs, null, true)
        }
    }
}
