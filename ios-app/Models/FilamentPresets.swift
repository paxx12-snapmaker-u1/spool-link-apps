// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation

struct FilamentPresets: Codable {
    var brands: [String] = []
    var materials: [String] = ["PLA", "PETG", "ABS", "ASA", "TPU", "Nylon", "PC", "PA"]
    var variants: [String] = ["Basic", "Matte", "Silk", "Glossy", "Carbon Fiber"]
    var weights: [String] = ["250", "500", "1000", "2000"]

    private static let key = "filamentPresets"

    static func load() -> FilamentPresets {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode(FilamentPresets.self, from: data)
        else { return FilamentPresets() }
        return presets
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
