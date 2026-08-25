// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation

struct TagField {
    let label: String
    let value: String
    var icon: String?
    var colorHex: String?
}

protocol NFCTagPayload: Sendable {
    var formatName: String { get }
    var typeDescription: String? { get }
    var colorHex: String? { get }
    var spoolId: Int? { get }
    var displayTitle: String { get }
    var fields: [TagField] { get }
    /// Structured filament data for display and Spoolman creation.
    /// Returns nil for formats that carry no filament information.
    var filamentMetadata: FilamentMetadata? { get }
}

struct RawNDEFTagPayload: NFCTagPayload {
    let mimeType: String?
    let payloadSize: Int
    let recordCount: Int

    var formatName: String { "NDEF" }
    var typeDescription: String? { mimeType }
    var colorHex: String? { nil }
    var spoolId: Int? { nil }
    var displayTitle: String { mimeType.map { "MIME: \($0)" } ?? "Unknown Tag" }
    var filamentMetadata: FilamentMetadata? { nil }

    var fields: [TagField] {
        var result: [TagField] = []
        if let mime = mimeType {
            result.append(TagField(label: "MIME Type", value: mime, icon: "doc.text"))
        }
        if recordCount > 0 {
            result.append(TagField(label: "Records", value: "\(recordCount)", icon: "list.bullet"))
        }
        if payloadSize > 0 {
            result.append(TagField(label: "Payload", value: "\(payloadSize) B", icon: "memorychip"))
        }
        return result
    }
}
