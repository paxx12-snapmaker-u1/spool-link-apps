// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

package dev.pages.paxx12.spoollink.model

/** Where tag links live in Spoolman. Must match `tag_store` on the printer, which reads only one store. */
enum class TagStore(val displayName: String) {
    CARD_UIDS("Card UIDs"),
    NATIVE("Spoolman native tags");

    companion object {
        fun fromName(name: String?): TagStore = entries.firstOrNull { it.name == name } ?: CARD_UIDS

        fun supportsNativeTags(version: String): Boolean {
            val match = Regex("^v?(\\d+)\\.(\\d+)\\.(\\d+)").find(version) ?: return false
            val (major, minor) = match.destructured
            return major.toInt() > 0 || minor.toInt() >= 27
        }
    }
}
