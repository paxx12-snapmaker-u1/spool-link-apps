// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

package dev.pages.paxx12.spoollink.utils

import dev.pages.paxx12.spoollink.model.FilamentMetadata
import dev.pages.paxx12.spoollink.model.FilamentNameStyle
import dev.pages.paxx12.spoollink.model.SpoolResponse
import dev.pages.paxx12.spoollink.model.TagStore
import org.junit.Assert.*
import org.junit.Test

class FilamentMetadataTest {

    @Test
    fun `filamentName brandAndSubtype style`() {
        val meta = FilamentMetadata("Bambu Lab", "PLA", "Basic", "FF0000", 1.75, 1000.0, 220, 60, null)
        assertEquals("Bambu Lab Basic", meta.filamentName(FilamentNameStyle.BRAND_AND_SUBTYPE))
    }

    @Test
    fun `filamentName returns Custom Filament when all fields empty`() {
        val meta = FilamentMetadata(null, null, null, null, null, null, null, null, null)
        assertEquals("Custom Filament", meta.filamentName(FilamentNameStyle.BRAND_AND_SUBTYPE))
    }

    @Test
    fun `colorName returns correct name for red`() {
        val meta = FilamentMetadata(null, null, null, "FF0000", null, null, null, null, null)
        assertEquals("Red", meta.colorName)
    }

    @Test
    fun `colorName returns White for ffffff`() {
        val meta = FilamentMetadata(null, null, null, "FFFFFF", null, null, null, null, null)
        assertEquals("White", meta.colorName)
    }

    @Test
    fun `colorName returns null for null colorHex`() {
        val meta = FilamentMetadata(null, null, null, null, null, null, null, null, null)
        assertNull(meta.colorName)
    }

    @Test
    fun `tagUIDs read only the selected store`() {
        val spool = SpoolResponse(
            id = 1,
            filament = SpoolResponse.FilamentResponse(1, null, null, null, null, null, null, null, null),
            remainingWeight = null, archived = false, registered = null, lastUsed = null,
            extra = SpoolResponse.ExtraData("\"AABBCCDD,11223344\""),
            tags = listOf(SpoolResponse.SpoolTag("04a1b2"))
        )
        assertEquals(listOf("AABBCCDD", "11223344"), spool.forStore(TagStore.CARD_UIDS).tagUIDs)
        assertEquals(2, spool.forStore(TagStore.CARD_UIDS).tagCount)
        assertEquals(listOf("04A1B2"), spool.forStore(TagStore.NATIVE).tagUIDs)
    }

    @Test
    fun `native tags need Spoolman 0_27_0`() {
        assertTrue(TagStore.supportsNativeTags("0.27.0"))
        assertTrue(TagStore.supportsNativeTags("v0.27.1-rc1"))
        assertTrue(TagStore.supportsNativeTags("1.0.0"))
        assertFalse(TagStore.supportsNativeTags("0.26.1"))
        assertFalse(TagStore.supportsNativeTags("dev"))
    }

    @Test
    fun `tag store defaults to card_uids`() {
        assertEquals(TagStore.CARD_UIDS, TagStore.fromName(null))
        assertEquals(TagStore.CARD_UIDS, TagStore.fromName("bogus"))
        assertEquals(TagStore.NATIVE, TagStore.fromName("NATIVE"))
    }
}
