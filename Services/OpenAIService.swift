// Services/OpenAIService.swift
import Foundation

final class OpenAIService: UsageServiceProtocol {
    let provider: AIProvider = .openai
    let config: ProviderConfig

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchBalance() async throws -> BalanceRecord {
        // S1: fetch subscription — get hard_limit_usd (monthly spending cap)
        let subURL = URL(string: "\(config.baseURL)\(AppConstants.OpenAI.balanceEndpoint)")!
        var subReq = URLRequest(url: subURL)
        subReq.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (subData, subResp) = try await session.data(for: subReq)
        try APIHelper.validateResponse(data: subData, response: subResp)

        let subscription = try decoder.decode(OpenAISubscriptionResponse.self, from: subData)
        guard let hardLimit = subscription.hardLimitUsd else {
            throw APIError(statusCode: 0, message: "OpenAI subscription response missing hard_limit_usd")
        }

        // S2: fetch current month usage to compute remaining balance
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let startOfMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        )!

        var components = URLComponents(string: "\(config.baseURL)\(AppConstants.OpenAI.usageEndpoint)")!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: df.string(from: startOfMonth)),
            URLQueryItem(name: "end_date", value: df.string(from: now))
        ]
        guard let usageURL = components.url else { throw URLError(.badURL) }

        var usageReq = URLRequest(url: usageURL)
        usageReq.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (usageData, usageResp) = try await session.data(for: usageReq)
        try APIHelper.validateResponse(data: usageData, response: usageResp)

        struct UsageTotal: Codable {
            let totalUsage: Double?

            enum CodingKeys: String, CodingKey {
                case totalUsage = "total_usage"
            }
        }
        let usage = try decoder.decode(UsageTotal.self, from: usageData)
        guard let totalUsage = usage.totalUsage else {
            throw APIError(statusCode: 0, message: "OpenAI usage response missing total_usage")
        }
        // OpenAI returns total_usage in cents → convert to dollars
        let totalUsed = totalUsage / 100.0

        return BalanceRecord(
            provider: .openai,
            totalBalance: max(0, hardLimit - totalUsed),
            grantAmount: hardLimit,
            totalUsed: totalUsed,
            currency: "USD"
        )
    }

    func fetchUsage(startDate: Date, endDate: Date) async throws -> [UsageRecord] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let start = df.string(from: startDate)
        let end = df.string(from: endDate)

        var components = URLComponents(string: "\(config.baseURL)\(AppConstants.OpenAI.usageEndpoint)")!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end)
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try APIHelper.validateResponse(data: data, response: response)

        struct OpenAIUsageResponse: Codable {
            struct DailyCost: Codable {
                let timestamp: Int
                let cost: Double?
                let lineItems: [LineItem]?

                enum CodingKeys: String, CodingKey {
                    case timestamp
                    case cost
                    case lineItems = "line_items"
                }
            }
            struct LineItem: Codable {
                let name: String?
                let cost: Double?
            }
            let dailyCosts: [DailyCost]?
            let totalUsage: Double?

            enum CodingKeys: String, CodingKey {
                case dailyCosts = "daily_costs"
                case totalUsage = "total_usage"
            }
        }

        let usageResp = try decoder.decode(OpenAIUsageResponse.self, from: data)
        return usageResp.dailyCosts?.map { daily in
            UsageRecord(
                provider: .openai,
                timestamp: Date(timeIntervalSince1970: TimeInterval(daily.timestamp)),
                promptTokens: 0,
                completionTokens: 0,
                cost: (daily.cost ?? 0) / 100.0,
                currency: "USD"
            )
        } ?? []
    }
}
