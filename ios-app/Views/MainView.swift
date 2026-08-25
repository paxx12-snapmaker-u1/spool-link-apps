// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

struct MainView: View {
    @Bindable var viewModel: SpoolmanViewModel

    var body: some View {
        TabView {
            ScanView(viewModel: viewModel)
                .tabItem {
                    Label("Scan", systemImage: "wave.3.right")
                }

            SpoolsView(viewModel: viewModel)
                .tabItem {
                    Label("Spools", systemImage: "list.bullet.rectangle")
                }

            HistoryView(viewModel: viewModel)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .badge(viewModel.scanHistory.isEmpty ? 0 : viewModel.scanHistory.count)

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    MainView(viewModel: SpoolmanViewModel())
}
