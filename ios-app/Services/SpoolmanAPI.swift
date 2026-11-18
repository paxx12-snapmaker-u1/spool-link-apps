// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link-apps
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

import Foundation

enum SpoolmanError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int)
    case spoolNotFound(Int)
    case filamentRequired
    case nativeTagsUnsupported(String)
    case tagConflict(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .spoolNotFound(let id):
            return "Spool \(id) not found"
        case .filamentRequired:
            return "Filament ID required"
        case .nativeTagsUnsupported(let version):
            return "Native tags need Spoolman v0.27.0 or newer (server is \(version))"
        case .tagConflict(let message):
            return message
        }
    }
}

actor SpoolmanAPI {
    private static let requestTimeout: TimeInterval = 3

    private var baseURL: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let session: URLSession
    private var nativeTagsConfirmed = false

    init(baseURL: String) {
        self.baseURL = Self.normalizeURL(baseURL)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        self.session = URLSession(configuration: configuration)
    }

    func updateBaseURL(_ newURL: String) {
        self.baseURL = Self.normalizeURL(newURL)
        self.nativeTagsConfirmed = false
    }

    struct ServerInfo: Decodable {
        let version: String
        let dbType: String?
        let debugMode: Bool?
        let gitCommit: String?
    }

    struct ConnectionTestResult {
        let logs: [String]
        let error: Error?
        var succeeded: Bool { error == nil }
    }

    static func testConnection(baseURL: String, store: TagStore) async -> ConnectionTestResult {
        var logs: [String] = []
        let normalized = normalizeURL(baseURL)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        let session = URLSession(configuration: configuration)

        let infoURL = "\(normalized)api/v1/info"
        logs.append("GET \(infoURL)")

        guard let url = URL(string: infoURL) else {
            logs.append("✗ Invalid URL")
            return ConnectionTestResult(logs: logs, error: SpoolmanError.invalidURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout

        do {
            let start = Date()
            let (data, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)

            guard let http = response as? HTTPURLResponse else {
                logs.append("✗ No HTTP response")
                return ConnectionTestResult(logs: logs, error: SpoolmanError.networkError(
                    NSError(domain: "SpoolmanAPI", code: -1)))
            }

            logs.append("\(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode)) (\(ms)ms)")

            guard (200...299).contains(http.statusCode) else {
                logs.append("✗ \(SpoolmanError.serverError(http.statusCode).localizedDescription)")
                return ConnectionTestResult(logs: logs, error: SpoolmanError.serverError(http.statusCode))
            }

            let infoDecoder = JSONDecoder()
            infoDecoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let info = try? infoDecoder.decode(ServerInfo.self, from: data) else {
                let err = NSError(domain: "SpoolmanAPI", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Response is not a Spoolman server"])
                logs.append("✗ \(err.localizedDescription)")
                return ConnectionTestResult(logs: logs, error: err)
            }

            var detail = "Spoolman v\(info.version)"
            if let db = info.dbType { detail += " (\(db))" }
            if let commit = info.gitCommit { detail += " \(commit)" }
            logs.append("✓ \(detail)")

            if store == .native && !TagStore.supportsNativeTags(version: info.version) {
                let err = SpoolmanError.nativeTagsUnsupported(info.version)
                logs.append("✗ \(err.localizedDescription)")
                return ConnectionTestResult(logs: logs, error: err)
            }

        } catch {
            logs.append("✗ \(error.localizedDescription)")
            return ConnectionTestResult(logs: logs, error: error)
        }

        struct FieldDef: Decodable { let key: String }

        func ensureField(entityType: String, key: String, name: String) async {
            let listURL = "\(normalized)api/v1/field/\(entityType)"
            let createURL = "\(normalized)api/v1/field/\(entityType)/\(key)"
            logs.append("GET \(listURL)")
            do {
                guard let lurl = URL(string: listURL),
                      let curl = URL(string: createURL) else { return }
                let (fdata, fresp) = try await session.data(from: lurl)
                guard let fh = fresp as? HTTPURLResponse, (200...299).contains(fh.statusCode) else {
                    logs.append("⚠ could not read custom fields for \(entityType)")
                    return
                }
                let fields = (try? JSONDecoder().decode([FieldDef].self, from: fdata)) ?? []
                if fields.contains(where: { $0.key == key }) {
                    logs.append("✓ field \(key) exists")
                } else {
                    logs.append("POST \(createURL)")
                    var req = URLRequest(url: curl)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: [
                        "key": key,
                        "name": name,
                        "entity_type": entityType,
                        "field_type": "text",
                        "order": 1,
                        "default_value": "\"\"",
                    ] as [String: Any])
                    let (cdata, cresp) = try await session.data(for: req)
                    if let ch = cresp as? HTTPURLResponse, (200...299).contains(ch.statusCode) {
                        logs.append("✓ field \(key) created")
                    } else {
                        let body = String(data: cdata, encoding: .utf8) ?? ""
                        logs.append("⚠ could not create field \(key): \(body)")
                    }
                }
            } catch {
                logs.append("⚠ custom fields check failed: \(error.localizedDescription)")
            }
        }

        if store == .cardUids {
            await ensureField(entityType: "spool", key: "card_uids", name: "Card UIDs")
        }
        await ensureField(entityType: "filament", key: "variant", name: "Variant")

        return ConnectionTestResult(logs: logs, error: nil)
    }

    private static func jsonEncodeString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s),
              let result = String(data: data, encoding: .utf8) else {
            return "\"\(s)\""
        }
        return result
    }

    private static func normalizeURL(_ url: String) -> String {
        var s = url
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "http://" + s }
        if !s.hasSuffix("/") { s += "/" }
        return s
    }

    func fetchSpools(limit: Int = 20, offset: Int = 0) async throws -> [SpoolResponse] {
        var components = URLComponents(string: "\(baseURL)api/v1/spool")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
        ]
        guard let url = components.url else { throw SpoolmanError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpoolmanError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try decoder.decode([SpoolResponse].self, from: data)
        } catch {
            throw SpoolmanError.decodingError(error)
        }
    }

    func getSpool(id: Int) async throws -> SpoolResponse {
        guard let url = URL(string: "\(baseURL)api/v1/spool/\(id)") else {
            throw SpoolmanError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw SpoolmanError.networkError(NSError(domain: "SpoolmanAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }
        if http.statusCode == 404 { throw SpoolmanError.spoolNotFound(id) }
        guard http.statusCode == 200 else { throw SpoolmanError.serverError(http.statusCode) }
        do {
            return try decoder.decode(SpoolResponse.self, from: data)
        } catch {
            throw SpoolmanError.decodingError(error)
        }
    }

    func findSpoolsByCardUid(_ uid: String, store: TagStore) async throws -> [SpoolResponse] {
        let all = try await fetchCandidateSpools(tag: store == .native ? uid.uppercased() : nil)
        // Filtered in both stores: Spoolman older than v0.27.0 ignores `tag` and returns every spool.
        return all.filter { $0.tagUIDs.contains(uid.uppercased()) }
    }

    private func fetchCandidateSpools(tag: String? = nil) async throws -> [SpoolResponse] {
        var components = URLComponents(string: "\(baseURL)api/v1/spool")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "1000"),
            URLQueryItem(name: "allow_archived", value: "true"),
        ]
        if let tag {
            components.queryItems?.append(URLQueryItem(name: "tag", value: tag))
        }
        guard let url = components.url else { throw SpoolmanError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw SpoolmanError.networkError(NSError(domain: "SpoolmanAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
        }
        guard http.statusCode == 200 else { throw SpoolmanError.serverError(http.statusCode) }
        do {
            return try decoder.decode([SpoolResponse].self, from: data)
        } catch {
            throw SpoolmanError.decodingError(error)
        }
    }

    func requireTagStoreSupport(store: TagStore) async throws {
        guard store == .native && !nativeTagsConfirmed else { return }
        let version = try await fetchServerVersion()
        guard TagStore.supportsNativeTags(version: version) else {
            throw SpoolmanError.nativeTagsUnsupported(version)
        }
        nativeTagsConfirmed = true
    }

    private func fetchServerVersion() async throws -> String {
        guard let url = URL(string: "\(baseURL)api/v1/info") else { throw SpoolmanError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpoolmanError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try decoder.decode(ServerInfo.self, from: data).version
    }

    /// Links the tag to the spool. Returns the id of another spool it had to be taken from, if any.
    @discardableResult
    func linkTag(to spool: SpoolResponse, uid: String, store: TagStore) async throws -> Int? {
        let upper = uid.uppercased()
        if store == .cardUids {
            let current = spool.tagUIDs
            if !current.contains(upper) {
                try await updateSpoolCardUids(id: spool.id, uids: current + [upper])
            }
            return nil
        }
        try await requireTagStoreSupport(store: store)
        guard let holder = try await postNativeTag(spoolId: spool.id, uid: upper) else { return nil }
        try await deleteNativeTag(spoolId: holder, uid: upper)
        if try await postNativeTag(spoolId: spool.id, uid: upper) != nil {
            throw SpoolmanError.tagConflict("Tag \(upper) is already linked")
        }
        return holder
    }

    /// Moves every link into `target` and removes it from the other store, following the U1 firmware's
    /// `spoollink_migrate.py`. A UID that cannot be moved stays where it was and is reported; running
    /// this again retries it. Returns log lines, ending with a summary.
    func migrateTags(to target: TagStore) async throws -> [String] {
        var logs: [String] = []
        let moved: Int
        let failed: Int
        if target == .native {
            (moved, failed) = try await migrateToNative(logs: &logs)
        } else {
            (moved, failed) = try await migrateToCardUids(logs: &logs)
        }
        let suffix = failed > 0 ? "; \(failed) left in place, see above" : ""
        logs.append("✓ Moved \(moved) card(s) to \(target.displayName)\(suffix).")
        return logs
    }

    private func distinctCardUids(_ spool: SpoolResponse) -> [String] {
        var seen: [String] = []
        for uid in spool.cardUidEntries.map({ $0.uppercased() }) where !seen.contains(uid) {
            seen.append(uid)
        }
        return seen
    }

    // A UID listed on several spools is kept for the user to resolve; one already tagged on
    // another spool is dropped, as that tag is the newer link.
    private func migrateToNative(logs: inout [String]) async throws -> (Int, Int) {
        try await requireTagStoreSupport(store: .native)
        let spools = try await fetchCandidateSpools()
        var owners: [String: [Int]] = [:]
        for spool in spools {
            for uid in distinctCardUids(spool) { owners[uid, default: []].append(spool.id) }
        }
        var moved = 0
        var failed = 0
        for spool in spools {
            let uids = distinctCardUids(spool)
            if uids.isEmpty { continue }
            var keep: [String] = []
            for uid in uids {
                let holders = owners[uid] ?? []
                if holders.count > 1 {
                    let list = holders.map { "#\($0)" }.joined(separator: ", ")
                    logs.append("⚠ Card \(uid) is on spools \(list), not moved")
                    keep.append(uid)
                    failed += 1
                    continue
                }
                if !spool.nativeTagUIDs.contains(uid) {
                    do {
                        if let holder = try await postNativeTag(spoolId: spool.id, uid: uid) {
                            logs.append("Card \(uid) on spool #\(spool.id) is already tagged on spool #\(holder), dropping it")
                            continue
                        }
                    } catch {
                        logs.append("⚠ Card \(uid) on spool #\(spool.id): \(error.localizedDescription)")
                        keep.append(uid)
                        failed += 1
                        continue
                    }
                }
                moved += 1
            }
            if keep != uids { try await updateSpoolCardUids(id: spool.id, uids: keep) }
        }
        return (moved, failed)
    }

    // Any other spool still listing a UID in `card_uids` has it removed, as the tag was the newer link.
    private func migrateToCardUids(logs: inout [String]) async throws -> (Int, Int) {
        let version = try await fetchServerVersion()
        guard TagStore.supportsNativeTags(version: version) else { return (0, 0) }
        try await ensureCardUidsField()
        let spools = try await fetchCandidateSpools()
        var tagged: [String: Int] = [:]
        for spool in spools {
            for uid in spool.nativeTagUIDs { tagged[uid] = spool.id }
        }
        var moved = 0
        var failed = 0
        for spool in spools {
            let uids = distinctCardUids(spool)
            let keep = uids.filter { (tagged[$0] ?? spool.id) == spool.id }
            for uid in uids where !keep.contains(uid) {
                logs.append("Card \(uid) on spool #\(spool.id) is tagged on spool #\(tagged[uid] ?? 0), dropping it")
            }
            let merged = keep + spool.nativeTagUIDs.filter { !keep.contains($0) }
            if merged != spool.cardUidEntries { try await updateSpoolCardUids(id: spool.id, uids: merged) }
            for uid in spool.nativeTagUIDs {
                do {
                    try await deleteNativeTag(spoolId: spool.id, uid: uid)
                    moved += 1
                } catch {
                    logs.append("⚠ Unlinking tag \(uid) from spool #\(spool.id): \(error.localizedDescription)")
                    failed += 1
                }
            }
        }
        return (moved, failed)
    }

    private func ensureCardUidsField() async throws {
        struct FieldDef: Decodable { let key: String }
        guard let listURL = URL(string: "\(baseURL)api/v1/field/spool"),
              let createURL = URL(string: "\(baseURL)api/v1/field/spool/card_uids") else {
            throw SpoolmanError.invalidURL
        }
        let (data, response) = try await session.data(from: listURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpoolmanError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        if try JSONDecoder().decode([FieldDef].self, from: data).contains(where: { $0.key == "card_uids" }) {
            return
        }
        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": "Card UIDs",
            "field_type": "text",
            "order": 1,
            "default_value": "\"\"",
        ] as [String: Any])
        let (_, createResponse) = try await session.data(for: request)
        let status = (createResponse as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else { throw SpoolmanError.serverError(status) }
    }

    func unlinkTag(from spool: SpoolResponse, uid: String, store: TagStore) async throws {
        if store == .native {
            try await deleteNativeTag(spoolId: spool.id, uid: uid.uppercased())
        } else {
            let remaining = spool.tagUIDs.filter { $0.uppercased() != uid.uppercased() }
            try await updateSpoolCardUids(id: spool.id, uids: remaining)
        }
    }

    func unlinkAllTags(from spool: SpoolResponse, store: TagStore) async throws {
        if store == .native {
            for uid in spool.tagUIDs {
                try await deleteNativeTag(spoolId: spool.id, uid: uid)
            }
        } else {
            try await updateSpoolCardUids(id: spool.id, uids: [])
        }
    }

    private struct TagConflict: Decodable {
        let message: String?
        let spoolId: Int?
    }

    /// Links without moving. Returns the id of another spool already holding the tag, if any.
    private func postNativeTag(spoolId: Int, uid: String) async throws -> Int? {
        guard let url = URL(string: "\(baseURL)api/v1/spool/\(spoolId)/tag") else {
            throw SpoolmanError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["uid": uid])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if (200...299).contains(status) { return nil }
        guard status == 409 else { throw SpoolmanError.serverError(status) }
        let conflict = try? decoder.decode(TagConflict.self, from: data)
        guard let holder = conflict?.spoolId, holder != spoolId else {
            throw SpoolmanError.tagConflict(conflict?.message ?? "Tag \(uid) is already linked")
        }
        return holder
    }

    private func deleteNativeTag(spoolId: Int, uid: String) async throws {
        guard let url = URL(string: "\(baseURL)api/v1/spool/\(spoolId)/tag/\(uid)") else {
            throw SpoolmanError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) || status == 404 else {
            throw SpoolmanError.serverError(status)
        }
    }

    private func updateSpoolCardUids(id: Int, uids: [String]) async throws {
        guard let url = URL(string: "\(baseURL)api/v1/spool/\(id)") else {
            throw SpoolmanError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoded = Self.jsonEncodeString(uids.joined(separator: ","))
        request.httpBody = try encoder.encode(UpdateSpoolExtraBody(cardUids: encoded))
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 || http.statusCode == 204 else {
            throw SpoolmanError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - Creation helpers

    struct VendorResponse: Codable, Identifiable {
        let id: Int
        let name: String?
    }

    struct FilamentResponse: Codable, Identifiable {
        let id: Int
        let name: String?
        let vendor: VendorResponse?
        let material: String?
        let colorHex: String?
        let diameter: Double?
        let weight: Double?
        let settingsExtruderTemp: Int?
        let settingsBedTemp: Int?
        let extra: [String: String]?

        var displayName: String {
            let parts = [vendor?.name, name].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? "Unnamed Filament" : parts.joined(separator: " – ")
        }

        var variantDecoded: String? {
            guard let raw = extra?["variant"], !raw.isEmpty else { return nil }
            if let data = raw.data(using: .utf8),
               let s = try? JSONDecoder().decode(String.self, from: data),
               !s.isEmpty { return s }
            return raw.isEmpty ? nil : raw
        }
    }

    private struct CreateVendorBody: Encodable { let name: String }

    private struct CreateFilamentBody: Encodable {
        let name: String
        let vendorId: Int?
        let material: String?
        let colorHex: String?
        let diameter: Double
        let weight: Double?
        let density: Double
        let settingsExtruderTemp: Int?
        let settingsBedTemp: Int?
        let extra: [String: String]?
    }

    private struct CreateSpoolBody: Encodable {
        let filamentId: Int
        let extra: [String: String]?

        enum CodingKeys: String, CodingKey {
            case filamentId = "filament_id"
            case extra
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(filamentId, forKey: .filamentId)
            try container.encodeIfPresent(extra, forKey: .extra)
        }
    }

    private static let materialDensity: [String: Double] = [
        "PLA": 1.24, "PETG": 1.27, "ABS": 1.04, "ASA": 1.07,
        "TPU": 1.21, "Nylon": 1.12, "PA": 1.12, "PC": 1.19,
        "PVA": 1.19, "HIPS": 1.04, "PP": 0.9,
    ]

    func findVendorId(name: String) async throws -> Int? {
        guard let url = URL(string: "\(baseURL)api/v1/vendor") else { throw SpoolmanError.invalidURL }
        let (data, _) = try await session.data(from: url)
        let vendors = (try? decoder.decode([VendorResponse].self, from: data)) ?? []
        return vendors.first(where: { $0.name?.lowercased() == name.lowercased() })?.id
    }

    func findOrCreateVendor(name: String) async throws -> Int {
        if let existingId = try await findVendorId(name: name) {
            return existingId
        }
        guard let url = URL(string: "\(baseURL)api/v1/vendor") else { throw SpoolmanError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(CreateVendorBody(name: name))
        let (newData, _) = try await session.data(for: req)
        return try decoder.decode(VendorResponse.self, from: newData).id
    }

    func fetchFilaments(limit: Int = 1000, offset: Int = 0) async throws -> [FilamentResponse] {
        var components = URLComponents(string: "\(baseURL)api/v1/filament")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
        ]
        guard let url = components.url else { throw SpoolmanError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpoolmanError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try decoder.decode([FilamentResponse].self, from: data)
        } catch {
            throw SpoolmanError.decodingError(error)
        }
    }

    func createFilamentFromInfo(
        name: String,
        vendorId: Int?,
        material: String?,
        colorHex: String?,
        diameter: Double,
        weight: Double?,
        nozzleTemp: Int?,
        bedTemp: Int?,
        variant: String? = nil
    ) async throws -> Int {
        let density = material.flatMap { Self.materialDensity[$0] } ?? 1.24
        let extra: [String: String]? = variant.map { ["variant": Self.jsonEncodeString($0)] }
        guard let filUrl = URL(string: "\(baseURL)api/v1/filament") else { throw SpoolmanError.invalidURL }
        var filReq = URLRequest(url: filUrl)
        filReq.httpMethod = "POST"
        filReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        filReq.httpBody = try encoder.encode(CreateFilamentBody(
            name: name,
            vendorId: vendorId,
            material: material,
            colorHex: colorHex,
            diameter: diameter,
            weight: weight,
            density: density,
            settingsExtruderTemp: nozzleTemp,
            settingsBedTemp: bedTemp,
            extra: extra
        ))
        let (filData, filResp) = try await session.data(for: filReq)
        guard let fh = filResp as? HTTPURLResponse, (200...299).contains(fh.statusCode) else {
            throw SpoolmanError.serverError((filResp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        struct FilId: Decodable { let id: Int }
        return try decoder.decode(FilId.self, from: filData).id
    }

    func createSpoolFromInfo(
        filamentId: Int,
        cardUid: String?,
        store: TagStore
    ) async throws -> SpoolResponse {
        if filamentId <= 0 {
            throw SpoolmanError.filamentRequired
        }

        let extra: [String: String]? = store == .cardUids
            ? cardUid.map { ["card_uids": Self.jsonEncodeString($0)] }
            : nil
        guard let spoolUrl = URL(string: "\(baseURL)api/v1/spool") else { throw SpoolmanError.invalidURL }
        var spoolReq = URLRequest(url: spoolUrl)
        spoolReq.httpMethod = "POST"
        spoolReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        spoolReq.httpBody = try encoder.encode(CreateSpoolBody(filamentId: filamentId, extra: extra))
        let (spoolData, spoolResp) = try await session.data(for: spoolReq)
        guard let sh = spoolResp as? HTTPURLResponse, (200...299).contains(sh.statusCode) else {
            throw SpoolmanError.serverError((spoolResp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let created = try decoder.decode(SpoolResponse.self, from: spoolData)
        if store == .native, let cardUid {
            try await linkTag(to: created, uid: cardUid, store: store)
            return try await getSpool(id: created.id)
        }
        return created
    }

    private struct UpdateSpoolExtraBody: Encodable {
        let extra: [String: String]
        init(cardUids: String) { self.extra = ["card_uids": cardUids] }
    }
}
