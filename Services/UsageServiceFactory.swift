// Services/UsageServiceFactory.swift
import Foundation

enum UsageServiceFactory {
    static func makeService(for config: ProviderConfig) -> UsageServiceProtocol {
        switch config.provider {
        case .pixel:
            return PixelUsageService(config: config)
        case .deepseek:
            return DeepSeekService(config: config)
        case .openai:
            return OpenAIService(config: config)
        case .anthropic:
            return AnthropicService(config: config)
        }
    }
}

final class PixelUsageService: UsageServiceProtocol {
    let provider: AIProvider = .pixel
    let config: ProviderConfig

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchBalance() async throws -> BalanceRecord {
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PixelUsageError.emptyAPIKey
        }

        let candidates: [(PixelEndpointType, String)] = [
            (.sub2APIUsage, AppConstants.Pixel.sub2APIUsageEndpoint),
            (.newAPITokenUsage, AppConstants.Pixel.newAPITokenUsageEndpointNoSlash),
            (.newAPITokenUsage, AppConstants.Pixel.newAPITokenUsageEndpoint),
            (.openAICompatibleSubscription, AppConstants.Pixel.openAICompatibleSubscriptionEndpoint)
        ]

        var lastError: Error?
        for (type, path) in candidates {
            do {
                return try await fetchBalance(endpointType: type, path: path)
            } catch {
                lastError = error
                if !shouldTryFallback(after: error, endpointType: type) {
                    throw error
                }
            }
        }

        throw lastError ?? PixelUsageError.unrecognizedEndpoint
    }

    func fetchDashboardSnapshot(lowBalanceThreshold: Double = 10) async throws -> PixelDashboardSnapshot {
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PixelUsageError.emptyAPIKey
        }

        do {
            return try await fetchV1UsageDashboardSnapshot(lowBalanceThreshold: lowBalanceThreshold)
        } catch {
            if !shouldTryFallback(after: error, endpointType: .sub2APIUsage) {
                throw error
            }
        }

        var profileValue: PixelDashboardProfile?
        var statsValue: PixelDashboardStatsSnapshot?
        var firstError: Error?

        async let profileResult: PixelDashboardProfile = fetchDashboardProfile()
        async let statsResult: PixelDashboardStatsSnapshot = fetchDashboardStats()

        do {
            profileValue = try await profileResult
        } catch {
            firstError = error
        }

        do {
            statsValue = try await statsResult
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        if profileValue == nil && statsValue == nil {
            throw firstError ?? PixelUsageError.unrecognizedEndpoint
        }

        let balance = profileValue?.balance
        let status: PixelDashboardStatus = {
            guard let balance else { return .normal }
            return balance < lowBalanceThreshold ? .lowBalance : .normal
        }()

        return PixelDashboardSnapshot(
            providerName: "Pixel API",
            baseURL: config.baseURL,
            balance: balance,
            balanceCurrency: profileValue?.currency ?? "USD",
            todayCostPrimary: statsValue?.todayCostPrimary,
            todayCostSecondary: statsValue?.todayCostSecondary,
            todayTokenTotal: statsValue?.todayTokenTotal,
            todayInputTokens: statsValue?.todayInputTokens,
            todayOutputTokens: statsValue?.todayOutputTokens,
            totalTokenTotal: statsValue?.totalTokenTotal,
            totalInputTokens: statsValue?.totalInputTokens,
            totalOutputTokens: statsValue?.totalOutputTokens,
            updatedAt: Date(),
            status: status,
            errorMessage: nil
        )
    }

    func fetchUsage(startDate: Date, endDate: Date) async throws -> [UsageRecord] {
        let response = try await fetchV1Usage(startDate: startDate, endDate: endDate)

        if let modelStats = response.modelStats, !modelStats.isEmpty {
            return modelStats.map { stat in
                UsageRecord(
                    provider: .pixel,
                    timestamp: Date(),
                    promptTokens: stat.inputTokens ?? 0,
                    completionTokens: stat.outputTokens ?? 0,
                    cost: stat.actualCost ?? stat.cost ?? 0,
                    currency: "USD"
                )
            }
        }

        if let total = response.usage?.total {
            return [
                UsageRecord(
                    provider: .pixel,
                    timestamp: Date(),
                    promptTokens: total.inputTokens ?? 0,
                    completionTokens: total.outputTokens ?? 0,
                    cost: total.actualCost ?? 0,
                    currency: "USD"
                )
            ]
        }

        throw UsageError.usageNotSupported
    }

    func verifyConnection() async throws {
        _ = try await fetchDashboardSnapshot()
    }

    func detectPixelAPIEndpoint(apiKey: String? = nil) async -> PixelEndpointType? {
        let key = apiKey ?? config.apiKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let detectorConfig = ProviderConfig(provider: .pixel, apiKey: key, baseURL: config.baseURL)
        let detector = PixelUsageService(config: detectorConfig, session: session)
        let candidates: [(PixelEndpointType, String)] = [
            (.sub2APIUsage, AppConstants.Pixel.sub2APIUsageEndpoint),
            (.newAPITokenUsage, AppConstants.Pixel.newAPITokenUsageEndpointNoSlash),
            (.newAPITokenUsage, AppConstants.Pixel.newAPITokenUsageEndpoint),
            (.openAICompatibleSubscription, AppConstants.Pixel.openAICompatibleSubscriptionEndpoint)
        ]

        for (type, path) in candidates {
            if (try? await detector.fetchBalance(endpointType: type, path: path)) != nil {
                return type
            }
        }
        return nil
    }

    private func fetchBalance(endpointType: PixelEndpointType, path: String) async throws -> BalanceRecord {
        switch endpointType {
        case .newAPITokenUsage:
            return try await fetchNewAPITokenUsage(path: path)
        case .sub2APIUsage:
            let now = Date()
            let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            let payload = try await fetchV1Usage(startDate: start, endDate: now)
            return try mapV1UsageToBalance(payload)
        case .openAICompatibleSubscription:
            return try await fetchOpenAICompatibleSubscription()
        }
    }

    private func fetchNewAPITokenUsage(path: String) async throws -> BalanceRecord {
        let url = try buildURL(path: path)
        let (data, response) = try await sendAuthorizedRequest(url: url)
        try validatePixelResponse(data: data, response: response)

        let payload = try decoder.decode(PixelTokenUsageResponse.self, from: data)
        guard payload.code == true || payload.success == true else {
            throw PixelUsageError.invalidAPIKey(payload.message ?? "Pixel API token usage query failed")
        }
        guard let usage = payload.data,
              let availableValue = usage.availableValue,
              let usedValue = usage.usedValue else {
            throw PixelUsageError.unexpectedResponse
        }

        let grantedValue = usage.grantedValue ?? availableValue + usedValue

        return BalanceRecord(
            provider: .pixel,
            totalBalance: availableValue,
            grantAmount: grantedValue,
            totalUsed: usedValue,
            currency: "credits",
            endpointType: PixelEndpointType.newAPITokenUsage.rawValue
        )
    }

    private func fetchDashboardProfile() async throws -> PixelDashboardProfile {
        let url = try buildURL(path: AppConstants.Pixel.dashboardProfileEndpoint)
        let (data, response) = try await sendAuthorizedRequest(url: url)
        try validatePixelResponse(data: data, response: response)
        let payload = try decoder.decode(PixelDashboardProfileResponse.self, from: data)
        guard payload.success != false else {
            throw PixelUsageError.invalidAPIKey(payload.message ?? "Pixel API profile query failed")
        }

        guard let data = payload.data else {
            throw PixelUsageError.unexpectedResponse
        }

        return PixelDashboardProfile(
            balance: data.balance,
            currency: data.balanceCurrency ?? "USD"
        )
    }

    private func fetchDashboardStats() async throws -> PixelDashboardStatsSnapshot {
        let url = try buildURL(path: AppConstants.Pixel.dashboardStatsEndpoint)
        let (data, response) = try await sendAuthorizedRequest(url: url)
        try validatePixelResponse(data: data, response: response)
        let payload = try decoder.decode(PixelDashboardStatsResponse.self, from: data)
        guard payload.success != false else {
            throw PixelUsageError.invalidAPIKey(payload.message ?? "Pixel API dashboard stats query failed")
        }

        guard let data = payload.data else {
            throw PixelUsageError.unexpectedResponse
        }

        return PixelDashboardStatsSnapshot(
            todayCostPrimary: data.todayCostPrimary,
            todayCostSecondary: data.todayCostSecondary,
            todayTokenTotal: data.todayTokenTotal,
            todayInputTokens: data.todayInputTokens,
            todayOutputTokens: data.todayOutputTokens,
            totalTokenTotal: data.totalTokenTotal,
            totalInputTokens: data.totalInputTokens,
            totalOutputTokens: data.totalOutputTokens
        )
    }

    private func fetchV1UsageDashboardSnapshot(lowBalanceThreshold: Double) async throws -> PixelDashboardSnapshot {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let payload = try await fetchV1Usage(startDate: start, endDate: now)
        guard let balance = payload.balance ?? payload.remaining else {
            throw PixelUsageError.unexpectedResponse
        }
        let status: PixelDashboardStatus = balance < lowBalanceThreshold ? .lowBalance : .normal

        return PixelDashboardSnapshot(
            providerName: "Pixel API",
            baseURL: config.baseURL,
            balance: balance,
            balanceCurrency: payload.unit ?? "USD",
            todayCostPrimary: payload.usage?.today?.actualCost ?? payload.usage?.today?.cost,
            todayCostSecondary: payload.usage?.today?.cost,
            todayTokenTotal: payload.usage?.today?.totalTokens.map(Double.init),
            todayInputTokens: payload.usage?.today?.inputTokens.map(Double.init),
            todayOutputTokens: payload.usage?.today?.outputTokens.map(Double.init),
            totalTokenTotal: payload.usage?.total?.totalTokens.map(Double.init),
            totalInputTokens: payload.usage?.total?.inputTokens.map(Double.init),
            totalOutputTokens: payload.usage?.total?.outputTokens.map(Double.init),
            updatedAt: Date(),
            status: status,
            errorMessage: nil
        )
    }

    private func fetchV1Usage(startDate: Date, endDate: Date) async throws -> PixelV1UsageResponse {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"

        var components = try buildURLComponents(path: AppConstants.Pixel.sub2APIUsageEndpoint)
        components.queryItems = [
            URLQueryItem(name: "start_date", value: df.string(from: startDate)),
            URLQueryItem(name: "end_date", value: df.string(from: endDate))
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await sendAuthorizedRequest(url: url)
        try validatePixelResponse(data: data, response: response)
        return try decoder.decode(PixelV1UsageResponse.self, from: data)
    }

    private func mapV1UsageToBalance(_ payload: PixelV1UsageResponse) throws -> BalanceRecord {
        if let quota = payload.quota,
           let remaining = quota.remaining,
           let used = quota.used {
            let total = quota.limit ?? remaining + used
            return BalanceRecord(
                provider: .pixel,
                totalBalance: remaining,
                grantAmount: total,
                totalUsed: used,
                currency: payload.unit ?? "USD",
                endpointType: PixelEndpointType.sub2APIUsage.rawValue
            )
        }

        if let remaining = payload.remaining ?? payload.balance {
            let used = payload.usage?.total?.actualCost ?? 0
            return BalanceRecord(
                provider: .pixel,
                totalBalance: remaining,
                grantAmount: nil,
                totalUsed: payload.usage?.total?.actualCost ?? payload.usage?.total?.cost ?? used,
                currency: payload.unit ?? "USD",
                endpointType: PixelEndpointType.sub2APIUsage.rawValue
            )
        }

        throw PixelUsageError.unexpectedResponse
    }

    private func fetchOpenAICompatibleSubscription() async throws -> BalanceRecord {
        let url = try buildURL(path: AppConstants.Pixel.openAICompatibleSubscriptionEndpoint)
        let (data, response) = try await sendAuthorizedRequest(url: url)
        try validatePixelResponse(data: data, response: response)

        let subscription = try decoder.decode(OpenAISubscriptionResponse.self, from: data)
        guard let total = subscription.hardLimitUsd ?? subscription.softLimitUsd else {
            throw PixelUsageError.unexpectedResponse
        }

        return BalanceRecord(
            provider: .pixel,
            totalBalance: total,
            grantAmount: total,
            totalUsed: 0,
            currency: "USD",
            endpointType: PixelEndpointType.openAICompatibleSubscription.rawValue
        )
    }

    private func buildURL(path: String) throws -> URL {
        guard let url = try buildURLComponents(path: path).url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func buildURLComponents(path: String) throws -> URLComponents {
        guard var components = URLComponents(string: config.baseURL) else {
            throw URLError(.badURL)
        }
        components.path = path
        return components
    }

    private func sendAuthorizedRequest(url: URL) async throws -> (Data, URLResponse) {
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw PixelUsageError.emptyAPIKey
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        return try await session.data(for: request)
    }

    private func validatePixelResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw PixelUsageError.invalidAPIKey(extractErrorMessage(from: data) ?? "Invalid API key")
            }
            if httpResponse.statusCode == 404 {
                throw PixelUsageError.endpointUnavailable
            }
            throw APIError(
                statusCode: httpResponse.statusCode,
                message: extractErrorMessage(from: data) ?? "Pixel API request failed"
            )
        }
    }

    private func shouldTryFallback(after error: Error, endpointType: PixelEndpointType) -> Bool {
        switch error {
        case PixelUsageError.endpointUnavailable,
             PixelUsageError.unexpectedResponse:
            return true
        case PixelUsageError.invalidAPIKey:
            return endpointType == .newAPITokenUsage
        case let apiError as APIError:
            return apiError.statusCode == 404 || apiError.statusCode == 401
        default:
            return false
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = object["message"] as? String {
                return message
            }
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct PixelDashboardProfile {
    let balance: Double?
    let currency: String
}

private struct PixelDashboardStatsSnapshot {
    let todayCostPrimary: Double?
    let todayCostSecondary: Double?
    let todayTokenTotal: Double?
    let todayInputTokens: Double?
    let todayOutputTokens: Double?
    let totalTokenTotal: Double?
    let totalInputTokens: Double?
    let totalOutputTokens: Double?
}

enum PixelUsageError: LocalizedError {
    case emptyAPIKey
    case invalidAPIKey(String)
    case endpointUnavailable
    case unexpectedResponse
    case unrecognizedEndpoint

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "API Key is empty"
        case .invalidAPIKey(let message):
            return message
        case .endpointUnavailable:
            return "Pixel API balance endpoint is unavailable"
        case .unexpectedResponse:
            return "Pixel API response structure changed"
        case .unrecognizedEndpoint:
            return "Cannot identify Pixel API balance endpoint. The site may have changed, or Cookie login may be required."
        }
    }
}
