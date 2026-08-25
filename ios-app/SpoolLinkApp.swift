// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

@main
struct SpoolLinkApp: App {
    @State private var viewModel: SpoolmanViewModel

    init() {
        let storedURL = UserDefaults.standard.string(forKey: "spoolmanBaseURL") ?? "http://spoolman.local:7912"
        _viewModel = State(initialValue: SpoolmanViewModel(baseURL: storedURL))
    }

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
        }
    }
}
