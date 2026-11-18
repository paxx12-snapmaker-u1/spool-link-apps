// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation

/// Where tag links live in Spoolman. Must match `tag_store` on the printer, which reads only one store.
enum TagStore: String, CaseIterable, Sendable {
    case cardUids = "card_uids"
    case native

    static let defaultsKey = "tagStore"

    static var current: TagStore {
        TagStore(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .cardUids
    }

    var displayName: String {
        switch self {
        case .cardUids: return "Card UIDs"
        case .native: return "Spoolman native tags"
        }
    }

    static func supportsNativeTags(version: String) -> Bool {
        guard let match = version.range(of: #"^v?\d+\.\d+\.\d+"#, options: .regularExpression) else {
            return false
        }
        let parts = version[match].drop { $0 == "v" }.split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 && (parts[0] > 0 || parts[1] >= 27)
    }
}

struct SpoolResponse: Codable, Identifiable {
    let id: Int
    let filament: FilamentResponse
    let lotNr: String?
    let remainingWeight: Double?
    let archived: Bool
    let registered: Date?
    let lastUsed: Date?
    let extra: ExtraData?
    let tags: [SpoolTag]?

    struct SpoolTag: Codable {
        let uid: String?
    }

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
        TagStore.current == .native ? nativeTagUIDs : cardUidEntries
    }

    var nativeTagUIDs: [String] {
        (tags ?? []).compactMap { $0.uid?.uppercased() }
    }

    var cardUidEntries: [String] {
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
