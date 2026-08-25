// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import SwiftUI

struct TagDetailView: View {
    let payload: any NFCTagPayload
    let uidHex: String

    var body: some View {
        VStack(spacing: 0) {
            TagRow(label: "Format") {
                Text(payload.formatName)
            }
            Divider().padding(.leading, 16)
            ForEach(Array(payload.fields.enumerated()), id: \.offset) { _, field in
                Divider().padding(.leading, 16)
                TagRow(label: field.label) {
                    if let hex = field.colorHex, let color = Color(hex: hex) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.primary.opacity(0.15), lineWidth: 0.5)
                                )
                            Text(field.value)
                                .fontDesign(.monospaced)
                        }
                    } else {
                        Text(field.value)
                    }
                }
            }
            Divider().padding(.leading, 16)
            TagRow(label: "Card UID") {
                Text(uidHex)
                    .fontDesign(.monospaced)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TagRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
