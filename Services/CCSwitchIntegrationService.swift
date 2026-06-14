import Foundation
import Darwin
import SQLite3

enum CCSwitchSyncMode: String, Codable, CaseIterable, Identifiable {
    case statusOnly
    case statusAndKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .statusOnly:
            return "只读取当前状态"
        case .statusAndKey:
            return "读取状态和 Key"
        }
    }
}

enum CCSwitchDataSourceSelectionMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "自动检测"
        case .manual:
            return "手动选择"
        }
    }
}

struct CCSwitchDataSource: Equatable {
    let url: URL
    let type: String
    let modifiedAt: Date?
}

struct CCSwitchProviderSnapshot: Codable, Equatable {
    let externalID: String?
    let appType: String?
    let name: String
    let baseURL: String?
    let providerType: String?
    let maskedKeyPreview: String?
    let rawAPIKey: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case externalID
        case appType
        case name
        case baseURL
        case providerType
        case maskedKeyPreview
        case updatedAt
    }

    init(
        externalID: String?,
        appType: String?,
        name: String,
        baseURL: String?,
        providerType: String?,
        maskedKeyPreview: String?,
        rawAPIKey: String?,
        updatedAt: Date?
    ) {
        self.externalID = externalID
        self.appType = appType
        self.name = name
        self.baseURL = baseURL
        self.providerType = providerType
        self.maskedKeyPreview = maskedKeyPreview
        self.rawAPIKey = rawAPIKey
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        appType = try container.decodeIfPresent(String.self, forKey: .appType)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        providerType = try container.decodeIfPresent(String.self, forKey: .providerType)
        maskedKeyPreview = try container.decodeIfPresent(String.self, forKey: .maskedKeyPreview)
        rawAPIKey = nil
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

enum CCSwitchIntegrationError: LocalizedError {
    case dataSourceNotFound
    case dataSourceUnavailable
    case unsupportedSchema
    case activeProviderNotFound
    case missingBaseURL
    case missingAPIKey
    case databaseBusy

    var errorDescription: String? {
        switch self {
        case .dataSourceNotFound:
            return "未检测到 CC Switch"
        case .dataSourceUnavailable:
            return "请在设置页手动选择 CC Switch 数据源"
        case .unsupportedSchema:
            return "CC Switch 数据结构不支持"
        case .activeProviderNotFound:
            return "未找到当前供应商"
        case .missingBaseURL:
            return "当前供应商缺少 Base URL"
        case .missingAPIKey:
            return "当前供应商缺少 API Key"
        case .databaseBusy:
            return "CC Switch 数据库被占用"
        }
    }
}

final class CCSwitchIntegrationService {
    private enum DefaultsKey {
        static let dataSourceMode = "ccSwitchDataSourceMode"
        static let manualDataSourcePath = "ccSwitchManualDataSourcePath"
        static let manualDataSourceBookmark = "ccSwitchManualDataSourceBookmark"
    }

    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(userDefaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func locateCCSwitchDataSource() -> CCSwitchDataSource? {
        if dataSourceSelectionMode == .manual,
           let url = manualDataSourceURL(),
           fileManager.fileExists(atPath: url.path) {
            return makeDataSource(url: url)
        }

        let candidates = automaticDataSourceCandidates()

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            return makeDataSource(url: url)
        }
        return nil
    }

    func readActiveProvider(includeKey: Bool, appType: String = "codex") async throws -> CCSwitchProviderSnapshot {
        guard let source = locateCCSwitchDataSource() else {
            throw CCSwitchIntegrationError.dataSourceNotFound
        }
        return try await Task.detached(priority: .utility) {
            try self.readActiveProvider(from: source.url, includeKey: includeKey, appType: appType)
        }.value
    }

    func saveManualDataSourceBookmark(url: URL) throws {
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        userDefaults.set(bookmark, forKey: DefaultsKey.manualDataSourceBookmark)
        userDefaults.set(url.path, forKey: DefaultsKey.manualDataSourcePath)
        dataSourceSelectionMode = .manual
    }

    func clearManualDataSourceBookmark() {
        userDefaults.removeObject(forKey: DefaultsKey.manualDataSourceBookmark)
        userDefaults.removeObject(forKey: DefaultsKey.manualDataSourcePath)
    }

    var dataSourceSelectionMode: CCSwitchDataSourceSelectionMode {
        get {
            guard let raw = userDefaults.string(forKey: DefaultsKey.dataSourceMode),
                  let mode = CCSwitchDataSourceSelectionMode(rawValue: raw) else {
                return .automatic
            }
            return mode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: DefaultsKey.dataSourceMode)
        }
    }

    var manualDataSourcePath: String? {
        userDefaults.string(forKey: DefaultsKey.manualDataSourcePath)
    }

    private func makeDataSource(url: URL) -> CCSwitchDataSource {
        let modifiedAt = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        return CCSwitchDataSource(url: url, type: "SQLite", modifiedAt: modifiedAt)
    }

    private func automaticDataSourceCandidates() -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []

        func append(_ homeURL: URL?) {
            guard let homeURL else { return }
            let url = homeURL
                .appendingPathComponent(".cc-switch")
                .appendingPathComponent("cc-switch.db")
            guard !seen.contains(url.path) else { return }
            seen.insert(url.path)
            urls.append(url)
        }

        append(realUserHomeDirectory())
        append(fileManager.homeDirectoryForCurrentUser)
        append(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
        return urls
    }

    private func realUserHomeDirectory() -> URL? {
        guard let passwd = getpwuid(getuid()),
              let home = passwd.pointee.pw_dir else {
            return nil
        }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
    }

    private func manualDataSourceURL() -> URL? {
        if let bookmark = userDefaults.data(forKey: DefaultsKey.manualDataSourceBookmark) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }

        guard let path = manualDataSourcePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func readActiveProvider(from url: URL, includeKey: Bool, appType: String) throws -> CCSwitchProviderSnapshot {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &database, flags, nil)
        guard status == SQLITE_OK, let database else {
            if status == SQLITE_BUSY || status == SQLITE_LOCKED {
                throw CCSwitchIntegrationError.databaseBusy
            }
            throw CCSwitchIntegrationError.dataSourceUnavailable
        }
        defer { sqlite3_close(database) }

        try assertSupportedSchema(database)

        let query = """
        SELECT id, app_type, name, website_url, provider_type,
               settings_config,
               meta,
               created_at
        FROM providers
        WHERE is_current = 1
        ORDER BY CASE WHEN app_type = ? THEN 0 ELSE 1 END, sort_index
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CCSwitchIntegrationError.unsupportedSchema
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, appType, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CCSwitchIntegrationError.activeProviderNotFound
        }

        let id = columnText(statement, 0)
        let appTypeValue = columnText(statement, 1)
        let name = columnText(statement, 2) ?? "CC Switch"
        let websiteURL = columnText(statement, 3)
        let providerType = columnText(statement, 4)
        let settingsConfigText = columnText(statement, 5)
        let configText = parseProviderConfigText(fromSettingsConfig: settingsConfigText)
        let metaText = columnText(statement, 6)
        let createdAt = columnInt64(statement, 7).flatMap(makeDate(fromMillisecondsOrSeconds:))

        let baseURL = firstNonEmpty([
            parseBaseURL(fromConfigText: configText),
            parseUsageBaseURL(fromMetaText: metaText),
            websiteURL
        ]).map(normalizedBaseURL)

        let rawAPIKey = includeKey ? parseAPIKey(fromSettingsConfig: settingsConfigText) : nil
        let masked = rawAPIKey.map(maskKey)

        return CCSwitchProviderSnapshot(
            externalID: id,
            appType: appTypeValue,
            name: name,
            baseURL: baseURL,
            providerType: providerType,
            maskedKeyPreview: masked,
            rawAPIKey: rawAPIKey,
            updatedAt: createdAt
        )
    }

    private func assertSupportedSchema(_ database: OpaquePointer) throws {
        let requiredTables = ["providers"]
        for table in requiredTables {
            var statement: OpaquePointer?
            let query = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw CCSwitchIntegrationError.unsupportedSchema
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, table, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw CCSwitchIntegrationError.unsupportedSchema
            }
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func columnInt64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    private func parseBaseURL(fromConfigText text: String?) -> String? {
        guard let text else { return nil }
        let patterns = [
            #"(?im)^\s*base_url\s*=\s*["']([^"']+)["']"#,
            #"(?im)^\s*baseUrl\s*=\s*["']([^"']+)["']"#,
            #"(?im)^\s*apiEndpoint\s*=\s*["']([^"']+)["']"#,
            #"(?im)^\s*endpoint\s*=\s*["']([^"']+)["']"#,
            #"(?im)^\s*url\s*=\s*["']([^"']+)["']"#
        ]
        return firstRegexCapture(in: text, patterns: patterns)
    }

    private func parseProviderConfigText(fromSettingsConfig text: String?) -> String? {
        guard let object = parseJSONObject(from: text) as? [String: Any] else {
            return nil
        }
        return object["config"] as? String
    }

    private func parseUsageBaseURL(fromMetaText text: String?) -> String? {
        guard let text,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usageScript = object["usage_script"] as? [String: Any] else {
            return nil
        }
        return usageScript["baseUrl"] as? String
            ?? usageScript["base_url"] as? String
            ?? usageScript["usageBaseUrl"] as? String
    }

    private func parseAPIKey(fromAuthJSON text: String?) -> String? {
        guard let text,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return findAPIKey(in: object)
    }

    private func parseAPIKey(fromSettingsConfig text: String?) -> String? {
        guard let object = parseJSONObject(from: text) as? [String: Any] else {
            return nil
        }
        if let auth = object["auth"] {
            return findAPIKey(in: auth)
        }
        return findAPIKey(in: object)
    }

    private func parseJSONObject(from text: String?) -> Any? {
        guard let text,
              let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func findAPIKey(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            let preferredKeys = [
                "OPENAI_API_KEY",
                "apiKey",
                "api_key",
                "authToken",
                "auth_token",
                "accessToken",
                "access_token",
                "key"
            ]
            for key in preferredKeys {
                if let text = dictionary[key] as? String, !text.isEmpty {
                    return text
                }
            }
            for (_, nested) in dictionary {
                if let found = findAPIKey(in: nested) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let found = findAPIKey(in: item) {
                    return found
                }
            }
        }
        return nil
    }

    private func firstRegexCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func normalizedBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private func makeDate(fromMillisecondsOrSeconds value: Int64) -> Date? {
        guard value > 0 else { return nil }
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
        }
        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    private func maskKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "***" }
        return "\(trimmed.prefix(4))***\(trimmed.suffix(4))"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
