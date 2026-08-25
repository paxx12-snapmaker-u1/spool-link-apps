// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation
import CoreNFC

struct TagFormatParser {
    private static let decoder = JSONDecoder()

    static func parse(record: NFCNDEFPayload) -> (any NFCTagPayload)? {
        guard String(data: record.type, encoding: .utf8) == "application/json" else { return nil }
        guard let raw = try? decoder.decode(OpenSpoolPayload.self, from: record.payload),
              raw.protocol == "openspool" else { return nil }
        return OpenSpoolTagPayload(raw: raw)
    }
}

// MARK: - Raw JSON model (NDEF record payload)

struct OpenSpoolPayload: Codable, Sendable {
    let `protocol`: String
    let version: String
    let type: String
    let colorHex: String?
    let brand: String?
    let subtype: String?
    let minTemp: String?
    let maxTemp: String?
    let bedMinTemp: String?
    let bedMaxTemp: String?
    let alpha: String?
    let weight: Double?
    let diameter: Double?
    let spoolId: Int?

    enum CodingKeys: String, CodingKey {
        case `protocol`, version, type
        case colorHex = "color_hex"
        case brand, subtype
        case minTemp = "min_temp"
        case maxTemp = "max_temp"
        case bedMinTemp = "bed_min_temp"
        case bedMaxTemp = "bed_max_temp"
        case alpha, weight, diameter
        case spoolId = "spool_id"
    }
}

// MARK: - NFCTagPayload implementation

struct OpenSpoolTagPayload: NFCTagPayload {
    let raw: OpenSpoolPayload

    var formatName: String { "OpenSpool \(raw.version)" }

    var typeDescription: String? {
        let parts = [raw.type.capitalized, raw.subtype].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var colorHex: String? { raw.colorHex }
    var spoolId: Int? { raw.spoolId }

    var displayTitle: String {
        filamentMetadata?.displayTitle ?? raw.type.capitalized
    }

    var fields: [TagField] {
        var result: [TagField] = []
        result.append(TagField(label: "Type", value: raw.type.capitalized, icon: "square.stack.3d.up"))
        if let sub = raw.subtype {
            result.append(TagField(label: "Material", value: sub, icon: "cube"))
        }
        if let brand = raw.brand {
            result.append(TagField(label: "Brand", value: brand, icon: "tag"))
        }
        if let hex = raw.colorHex {
            result.append(TagField(label: "Color", value: "#\(hex.uppercased())", icon: "paintpalette", colorHex: hex))
        }
        if let lo = raw.minTemp, let hi = raw.maxTemp {
            result.append(TagField(label: "Nozzle", value: "\(lo)–\(hi) °C", icon: "thermometer.medium"))
        }
        if let lo = raw.bedMinTemp, let hi = raw.bedMaxTemp {
            result.append(TagField(label: "Bed", value: "\(lo)–\(hi) °C", icon: "square.bottomhalf.filled"))
        }
        if let w = raw.weight {
            result.append(TagField(label: "Weight", value: "\(Int(w)) g", icon: "scalemass"))
        }
        if let d = raw.diameter {
            result.append(TagField(label: "Diameter", value: "\(d) mm", icon: "circle"))
        }
        if let id = raw.spoolId {
            result.append(TagField(label: "Spool ID", value: "#\(id)", icon: "number"))
        }
        return result
    }

    var filamentMetadata: FilamentMetadata? {
        FilamentMetadata(
            brand: raw.brand,
            material: raw.type.uppercased(),
            subtype: raw.subtype,
            colorHex: raw.colorHex,
            diameter: raw.diameter,
            weight: raw.weight,
            nozzleTemp: Int(raw.maxTemp ?? ""),
            bedTemp: Int(raw.bedMaxTemp ?? ""),
            spoolId: raw.spoolId
        )
    }
}
