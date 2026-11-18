// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

package dev.pages.paxx12.spoollink.api

import dev.pages.paxx12.spoollink.model.SpoolResponse
import com.google.gson.annotations.SerializedName
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.*

data class VendorResponse(val id: Int, val name: String?)
data class FilamentIdResponse(val id: Int)
data class FieldResponse(val key: String)
data class InfoResponse(val version: String?)
data class TagConflictResponse(
    val message: String?,
    @SerializedName("spool_id") val spoolId: Int?
)

interface SpoolmanService {
    @GET("api/v1/info")
    suspend fun fetchInfo(): InfoResponse

    @GET("api/v1/spool")
    suspend fun findSpoolsByTag(
        @Query("tag") uid: String,
        @Query("limit") limit: Int,
        @Query("allow_archived") allowArchived: Boolean
    ): List<SpoolResponse>

    @POST("api/v1/spool/{id}/tag")
    suspend fun linkTag(@Path("id") id: Int, @Body body: RequestBody): ResponseBody

    @DELETE("api/v1/spool/{id}/tag/{uid}")
    suspend fun unlinkTag(@Path("id") id: Int, @Path("uid") uid: String): Response<ResponseBody>

    @GET("api/v1/spool")
    suspend fun fetchSpools(
        @Query("limit") limit: Int,
        @Query("offset") offset: Int
    ): List<SpoolResponse>

    @GET("api/v1/spool/{id}")
    suspend fun getSpool(@Path("id") id: Int): SpoolResponse

    @GET("api/v1/spool")
    suspend fun findSpoolsByCardUidCandidateSpools(
        @Query("limit") limit: Int,
        @Query("allow_archived") allowArchived: Boolean
    ): List<SpoolResponse>

    @GET("api/v1/field/spool")
    suspend fun fetchSpoolFields(): List<FieldResponse>

    @POST("api/v1/field/spool/card_uids")
    suspend fun createCardUidsField(@Body body: RequestBody): ResponseBody

    @PATCH("api/v1/spool/{id}")
    suspend fun updateSpool(@Path("id") id: Int, @Body body: RequestBody): ResponseBody

    @GET("api/v1/vendor")
    suspend fun fetchVendors(): List<VendorResponse>

    @POST("api/v1/vendor")
    suspend fun createVendor(@Body body: RequestBody): VendorResponse

    @GET("api/v1/filament")
    suspend fun fetchFilaments(
        @Query("limit") limit: Int,
        @Query("offset") offset: Int
    ): List<SpoolResponse.FilamentResponse>

    @POST("api/v1/filament")
    suspend fun createFilament(@Body body: RequestBody): FilamentIdResponse

    @POST("api/v1/spool")
    suspend fun createSpool(@Body body: RequestBody): SpoolResponse
}
