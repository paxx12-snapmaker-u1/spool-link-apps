// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation

struct SpoolResponse: Codable, Identifiable {
    let id: Int
    let filament: FilamentResponse
    let lotNr: String?
    let remainingWeight: Double?
    let archived: Bool
    let registered: Date?
    let lastUsed: Date?
    let extra: ExtraData?

    struct FilamentResponse: Codable {
        let name: String?
        let vendor: VendorResponse?
        let material: String?
        let colorHex: String?
        let diameter: Double?
        let weight: Double?
        let settingsExtruderTemp: Int?
        let settingsBedTemp: Int?

        struct VendorResponse: Codable {
            let name: String?
        }
    }

    struct ExtraData: Codable {
        let cardUids: String?
    }

    var displayName: String {
        let parts = [filament.vendor?.name, filament.name]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Unnamed Spool" : parts.joined(separator: " – ")
    }

    var tagCount: Int { tagUIDs.count }

    var tagUIDs: [String] {
        guard let raw = extra?.cardUids, !raw.isEmpty else { return [] }
        let decoded: String
        if let data = raw.data(using: .utf8),
           let s = try? JSONDecoder().decode(String.self, from: data) {
            decoded = s
        } else {
            decoded = raw
        }
        return decoded
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
