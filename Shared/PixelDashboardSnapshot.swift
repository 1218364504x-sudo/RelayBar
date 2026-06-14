import Foundation

enum APIProviderType: String, Codable, CaseIterable, Identifiable {
    case pixelDashboard
    case newAPICompatible
    case oneAPICompatible
    case deepSeekBalance
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pixelDashboard:
            return "Pixel Dashboard"
        case .newAPICompatible:
            return "New API Compatible"
        case .oneAPICompatible:
            return "One API Compatible"
        case .deepSeekBalance:
            return "DeepSeek Balance"
        case .custom:
            return "Custom"
        }
    }
}

struct APIProviderProfile: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    var baseURL: String
    var providerType: APIProviderType
    var isEnabled: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var externalID: String? = nil

    var baseURLHost: String {
        URL(string: baseURL)?.host ?? baseURL
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case baseURL
        case providerType
        case isEnabled
        case sortOrder
        case createdAt
        case updatedAt
        case externalID
    }

    init(
        id: String,
        displayName: String,
        baseURL: String,
        providerType: APIProviderType,
        isEnabled: Bool,
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date,
        externalID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.providerType = providerType
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.externalID = externalID
    }
}

struct ActiveProviderSelection: Codable, Equatable {
    let activeProviderID: String
    let updatedAt: Date
}

struct PixelDashboardSnapshot: Codable {
    let providerName: String
    let baseURL: String
    let balance: Double?
    let balanceCurrency: String?
    let todayCostPrimary: Double?
    let todayCostSecondary: Double?
    let todayTokenTotal: Double?
    let todayInputTokens: Double?
    let todayOutputTokens: Double?
    let totalTokenTotal: Double?
    let totalInputTokens: Double?
    let totalOutputTokens: Double?
    let updatedAt: Date
    let status: PixelDashboardStatus
    let errorMessage: String?
    var providerID: String? = nil
    var providerType: APIProviderType? = nil
    var baseURLHost: String? = nil

    func withStatus(_ status: PixelDashboardStatus, errorMessage: String? = nil, updatedAt: Date? = nil) -> PixelDashboardSnapshot {
        var snapshot = PixelDashboardSnapshot(
            providerName: providerName,
            baseURL: baseURL,
            balance: balance,
            balanceCurrency: balanceCurrency,
            todayCostPrimary: todayCostPrimary,
            todayCostSecondary: todayCostSecondary,
            todayTokenTotal: todayTokenTotal,
            todayInputTokens: todayInputTokens,
            todayOutputTokens: todayOutputTokens,
            totalTokenTotal: totalTokenTotal,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            updatedAt: updatedAt ?? self.updatedAt,
            status: status,
            errorMessage: errorMessage
        )
        snapshot.providerID = providerID
        snapshot.providerType = providerType
        snapshot.baseURLHost = baseURLHost
        return snapshot
    }

    func withProfile(_ profile: APIProviderProfile) -> PixelDashboardSnapshot {
        var snapshot = PixelDashboardSnapshot(
            providerName: profile.displayName,
            baseURL: profile.baseURL,
            balance: balance,
            balanceCurrency: balanceCurrency,
            todayCostPrimary: todayCostPrimary,
            todayCostSecondary: todayCostSecondary,
            todayTokenTotal: todayTokenTotal,
            todayInputTokens: todayInputTokens,
            todayOutputTokens: todayOutputTokens,
            totalTokenTotal: totalTokenTotal,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            updatedAt: updatedAt,
            status: status,
            errorMessage: errorMessage
        )
        snapshot.providerID = profile.id
        snapshot.providerType = profile.providerType
        snapshot.baseURLHost = profile.baseURLHost
        return snapshot
    }
}

enum PixelDashboardStatus: String, Codable {
    case normal
    case lowBalance
    case cached
    case error
    case notConfigured
    case unauthorized
}

enum PixelDashboardSnapshotStore {
    static var appGroupIdentifier: String {
        let fallback = "YOURTEAMID.com.example.relaybar.widget"
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RelayBarAppGroupIdentifier") as? String else {
            return fallback
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") {
            return fallback
        }
        return trimmed
    }

    static let fileName = "current_dashboard_snapshot.json"
    static let legacyFileName = "pixel_dashboard_snapshot_v2.json"
    static let defaultsKey = "currentDashboardSnapshot"
    static let legacyDefaultsKey = "pixelDashboardSnapshotV2"
    static let activeSelectionFileName = "active_provider_selection.json"
    static let activeSelectionDefaultsKey = "activeProviderSelection"
    static let syncDiagnosticFileName = "sync_diagnostic.json"
    static let staleInterval: TimeInterval = 60 * 30

    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func providerSnapshotURL(providerID: String, fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("provider_\(sanitizedFileComponent(providerID))_dashboard_snapshot.json")
    }

    static func activeSelectionURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(activeSelectionFileName)
    }

    static func syncDiagnosticURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(syncDiagnosticFileName)
    }

    static func load(fileManager: FileManager = .default) throws -> PixelDashboardSnapshot? {
        guard let url = snapshotURL(fileManager: fileManager),
              fileManager.fileExists(atPath: url.path) else {
            if let legacy = try loadLegacy(fileManager: fileManager) {
                return legacy
            }
            return try loadFromDefaults()
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            if let snapshot = try loadFromDefaults() {
                return snapshot
            }
            throw error
        }
    }

    static func loadProviderSnapshot(providerID: String, fileManager: FileManager = .default) throws -> PixelDashboardSnapshot? {
        guard let url = providerSnapshotURL(providerID: providerID, fileManager: fileManager),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decode(Data(contentsOf: url))
    }

    static func loadDiagnostic(fileManager: FileManager = .default) -> String? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return "共享容器不可用"
        }

        let url = containerURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: defaultsKey) == nil
                ? "未找到缓存"
                : nil
        }

        do {
            _ = try decode(Data(contentsOf: url))
            return nil
        } catch DecodingError.dataCorrupted {
            return "缓存格式无法解析"
        } catch DecodingError.keyNotFound {
            return "缓存字段不完整"
        } catch {
            if (try? loadFromDefaults()) != nil {
                return nil
            }
            return "缓存读取失败"
        }
    }

    static func save(_ snapshot: PixelDashboardSnapshot, fileManager: FileManager = .default) throws {
        try saveCurrent(snapshot, fileManager: fileManager)
        if let providerID = snapshot.providerID {
            try saveProvider(snapshot, providerID: providerID, fileManager: fileManager)
        }
    }

    static func saveCurrent(_ snapshot: PixelDashboardSnapshot, fileManager: FileManager = .default) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        guard let url = snapshotURL(fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: defaultsKey)
        UserDefaults(suiteName: appGroupIdentifier)?.synchronize()
    }

    static func saveProvider(_ snapshot: PixelDashboardSnapshot, providerID: String, fileManager: FileManager = .default) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        guard let url = providerSnapshotURL(providerID: providerID, fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func deleteProviderSnapshot(providerID: String, fileManager: FileManager = .default) throws {
        guard let url = providerSnapshotURL(providerID: providerID, fileManager: fileManager),
              fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    static func saveActiveSelection(_ selection: ActiveProviderSelection, fileManager: FileManager = .default) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(selection)

        guard let url = activeSelectionURL(fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: activeSelectionDefaultsKey)
        UserDefaults(suiteName: appGroupIdentifier)?.synchronize()
    }

    static func saveSyncDiagnostic(_ diagnostic: [String: String], fileManager: FileManager = .default) {
        guard let url = syncDiagnosticURL(fileManager: fileManager) else { return }
        var payload = diagnostic
        payload["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    static func loadActiveSelection(fileManager: FileManager = .default) throws -> ActiveProviderSelection? {
        if let url = activeSelectionURL(fileManager: fileManager),
           fileManager.fileExists(atPath: url.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ActiveProviderSelection.self, from: Data(contentsOf: url))
        }
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: activeSelectionDefaultsKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActiveProviderSelection.self, from: data)
    }

    static func isStale(_ snapshot: PixelDashboardSnapshot, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.updatedAt) > staleInterval
    }

    private static func loadFromDefaults() throws -> PixelDashboardSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: defaultsKey) else {
            return nil
        }
        return try decode(data)
    }

    private static func loadLegacy(fileManager: FileManager) throws -> PixelDashboardSnapshot? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let url = containerURL.appendingPathComponent(legacyFileName)
        if fileManager.fileExists(atPath: url.path) {
            return try decode(Data(contentsOf: url))
        }
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: legacyDefaultsKey) else {
            return nil
        }
        return try decode(data)
    }

    private static func decode(_ data: Data) throws -> PixelDashboardSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PixelDashboardSnapshot.self, from: data)
    }

    private static func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
