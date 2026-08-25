// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation

enum FilamentNameStyle: String, CaseIterable, Sendable {
    case brandAndSubtype = "Brand + Subtype/Material"
    case brandMaterialSubtype = "Brand + Material + Subtype"
    case materialAndSubtype = "Material + Subtype"
    case subtypeOnly = "Subtype only"
    case brandColorSubtype = "Brand + Color + Subtype/Material"
    case brandMaterialColorSubtype = "Brand + Material + Color + Subtype"
    case colorMaterialSubtype = "Color + Material + Subtype"
    case colorOnly = "Color only"

    var id: String { rawValue }
}

/// Normalised filament data extracted from any NFC tag format.
/// Shared between the display layer (NFCTagPayload) and the Spoolman creation layer.
struct FilamentMetadata: Sendable {
    let brand: String?
    let material: String?
    let subtype: String?
    let colorHex: String?
    let diameter: Double?
    let weight: Double?
    let nozzleTemp: Int?
    let bedTemp: Int?
    let spoolId: Int?

    /// Human-readable title shown in the UI.
    var displayTitle: String {
        let parts = [brand, subtype ?? material].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
    }

    /// Name used when creating a filament in Spoolman.
    var filamentName: String {
        filamentName(style: .brandAndSubtype)
    }

    var colorName: String? {
        guard let hex = colorHex else { return nil }
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6,
              let rv = UInt8(h.prefix(2), radix: 16),
              let gv = UInt8(h.dropFirst(2).prefix(2), radix: 16),
              let bv = UInt8(h.dropFirst(4), radix: 16) else { return nil }
        let r = Double(rv) / 255, g = Double(gv) / 255, b = Double(bv) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        let l = (maxC + minC) / 2
        if delta < 0.12 {
            if l > 0.85 { return "White" }
            if l < 0.15 { return "Black" }
            return "Gray"
        }
        let s = l > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC)
        if s < 0.15 { return l > 0.7 ? "Silver" : "Gray" }
        var hue: Double
        if maxC == r {
            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            if hue < 0 { hue += 6 }
        } else if maxC == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue >= 10 && hue < 40 && l < 0.45 { return "Brown" }
        switch hue {
        case 0..<15:  return "Red"
        case 15..<40: return "Orange"
        case 40..<65: return "Yellow"
        case 65..<165: return "Green"
        case 165..<195: return "Cyan"
        case 195..<255: return "Blue"
        case 255..<285: return "Purple"
        case 285..<325: return "Magenta"
        case 325..<345: return "Pink"
        default:      return "Red"
        }
    }

    func filamentName(style: FilamentNameStyle) -> String {
        let cleanBrand = normalized(brand)
        let cleanMaterial = normalized(material)
        let cleanSubtype = normalized(subtype)
        let cleanColor = colorName

        let parts: [String]
        switch style {
        case .brandAndSubtype:
            parts = [cleanBrand, cleanSubtype ?? cleanMaterial].compactMap { $0 }
        case .brandMaterialSubtype:
            parts = [cleanBrand, cleanMaterial, cleanSubtype].compactMap { $0 }
        case .materialAndSubtype:
            parts = [cleanMaterial, cleanSubtype].compactMap { $0 }
        case .subtypeOnly:
            parts = [cleanSubtype].compactMap { $0 }
        case .brandColorSubtype:
            parts = [cleanBrand, cleanColor, cleanSubtype ?? cleanMaterial].compactMap { $0 }
        case .brandMaterialColorSubtype:
            parts = [cleanBrand, cleanMaterial, cleanColor, cleanSubtype].compactMap { $0 }
        case .colorMaterialSubtype:
            parts = [cleanColor, cleanMaterial, cleanSubtype].compactMap { $0 }
        case .colorOnly:
            parts = [cleanColor].compactMap { $0 }
        }

        let deduped = parts.reduce(into: [String]()) { acc, part in
            if acc.last?.caseInsensitiveCompare(part) != .orderedSame {
                acc.append(part)
            }
        }

        return deduped.isEmpty ? "Custom Filament" : deduped.joined(separator: " ")
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
