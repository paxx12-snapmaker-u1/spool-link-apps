// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation

struct ScanResult: Identifiable {
    let id: UUID
    let timestamp: Date
    let spoolId: Int?
    let spoolName: String
    let cardUid: String
    let success: Bool
    let message: String
    let tagPayload: any NFCTagPayload
    let spoolResponse: SpoolResponse?

    func withSpoolResponse(_ newSpool: SpoolResponse?) -> ScanResult {
        ScanResult(id: id, timestamp: timestamp, spoolId: spoolId, spoolName: spoolName,
                   cardUid: cardUid, success: success, message: message,
                   tagPayload: tagPayload, spoolResponse: newSpool)
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        spoolId: Int? = nil,
        spoolName: String,
        cardUid: String,
        success: Bool,
        message: String,
        tagPayload: any NFCTagPayload,
        spoolResponse: SpoolResponse? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.spoolId = spoolId
        self.spoolName = spoolName
        self.cardUid = cardUid
        self.success = success
        self.message = message
        self.tagPayload = tagPayload
        self.spoolResponse = spoolResponse
    }
}
