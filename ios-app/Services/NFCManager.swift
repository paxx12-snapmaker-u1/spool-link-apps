// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation
import CoreNFC

protocol NFCManagerDelegate: AnyObject {
    func nfcManager(_ manager: NFCManager, didReadTag payload: any NFCTagPayload, uidHex: String)
    func nfcManager(_ manager: NFCManager, didFailWithError error: Error)
    func nfcManagerDidInvalidateSession(_ manager: NFCManager, error: Error?)
}

class NFCManager: NSObject, ObservableObject {
    weak var delegate: NFCManagerDelegate?

    @Published var isScanning = false
    @Published var sessionMessage = "Ready to scan"

    private var session: NFCTagReaderSession?

    func startScanning() {
        guard NFCTagReaderSession.readingAvailable else {
            sessionMessage = "NFC not available on this device"
            return
        }

        guard session == nil else {
            sessionMessage = "Session already active"
            return
        }

        session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self)
        session?.alertMessage = "Hold your device near an NFC tag"
        session?.begin()
        isScanning = true
        sessionMessage = "Scanning for NFC tags..."
    }

    func stopScanning() {
        session?.invalidate()
        session = nil
        isScanning = false
        sessionMessage = "Scanning stopped"
    }

    func invalidateSession(errorMessage: String) {
        session?.invalidate(errorMessage: errorMessage)
        session = nil
        isScanning = false
    }
}

extension NFCManager: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        sessionMessage = "Session active. Hold device near NFC tag."
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        isScanning = false

        if let nfcError = error as? NFCReaderError, nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            sessionMessage = "Scanning stopped"
        } else {
            sessionMessage = "Session invalidated: \(error.localizedDescription)"
            delegate?.nfcManagerDidInvalidateSession(self, error: error)
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        Task {
            do {
                guard let firstTag = tags.first else {
                    session.invalidate(errorMessage: "No tag detected")
                    return
                }

                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    session.connect(to: firstTag) { error in
                        if let error { cont.resume(throwing: error) } else { cont.resume() }
                    }
                }

                let uidHex: String
                let ndefTag: NFCNDEFTag

                switch firstTag {
                case .miFare(let tag):
                    uidHex = tag.identifier.map { String(format: "%02X", $0) }.joined()
                    ndefTag = tag
                case .iso7816(let tag):
                    uidHex = tag.identifier.map { String(format: "%02X", $0) }.joined()
                    ndefTag = tag
                case .iso15693(let tag):
                    uidHex = tag.identifier.map { String(format: "%02X", $0) }.joined()
                    ndefTag = tag
                case .feliCa(let tag):
                    uidHex = tag.currentIDm.map { String(format: "%02X", $0) }.joined()
                    ndefTag = tag
                @unknown default:
                    session.invalidate(errorMessage: "Unsupported tag type")
                    return
                }

                let ndefStatus = await withCheckedContinuation { (cont: CheckedContinuation<NFCNDEFStatus, Never>) in
                    ndefTag.queryNDEFStatus { status, _, _ in cont.resume(returning: status) }
                }

                let ndefMessage: NFCNDEFMessage? = ndefStatus != .notSupported
                    ? await withCheckedContinuation { (cont: CheckedContinuation<NFCNDEFMessage?, Never>) in
                        ndefTag.readNDEF { message, _ in cont.resume(returning: message) }
                    }
                    : nil

                let payload = ndefMessage.map { parsePayload(from: $0) }
                    ?? RawNDEFTagPayload(mimeType: nil, payloadSize: 0, recordCount: 0)

                session.invalidate()
                self.session = nil
                isScanning = false
                sessionMessage = "Tag read successfully"
                delegate?.nfcManager(self, didReadTag: payload, uidHex: uidHex)

            } catch {
                session.invalidate(errorMessage: "Error reading tag: \(error.localizedDescription)")
                self.session = nil
                isScanning = false
                delegate?.nfcManager(self, didFailWithError: error)
            }
        }
    }

    private func parsePayload(from message: NFCNDEFMessage) -> any NFCTagPayload {
        for record in message.records {
            if let parsed = TagFormatParser.parse(record: record) {
                return parsed
            }
        }

        let first = message.records.first
        return RawNDEFTagPayload(
            mimeType: first.flatMap { String(data: $0.type, encoding: .utf8) },
            payloadSize: first?.payload.count ?? 0,
            recordCount: message.records.count
        )
    }
}

extension NFCTag {
    var uidHex: String {
        switch self {
        case .miFare(let tag): return tag.identifier.map { String(format: "%02X", $0) }.joined()
        case .iso7816(let tag): return tag.identifier.map { String(format: "%02X", $0) }.joined()
        case .iso15693(let tag): return tag.identifier.map { String(format: "%02X", $0) }.joined()
        case .feliCa(let tag): return tag.currentIDm.map { String(format: "%02X", $0) }.joined()
        @unknown default: return "UNKNOWN"
        }
    }
}
