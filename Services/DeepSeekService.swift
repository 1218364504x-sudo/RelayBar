// Services/DeepSeekService.swift
import Foundation

final class DeepSeekService: UsageServiceProtocol {
    let provider: AIProvider = .deepseek
    let config: ProviderConfig

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchBalance() async throws -> BalanceRecord {
        guard let url = URL(string: "\(config.baseURL)/user/balance") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        try APIHelper.validateResponse(data: data, response: response)

        let payload = try decoder.decode(DeepSeekBalanceResponse.self, from: data)
        guard payload.isAvailable else {
            throw APIError(statusCode: 0, message: "DeepSeek balance is currently unavailable")
        }

        guard let info = payload.balanceInfos.first else {
            throw APIError(statusCode: 0, message: "DeepSeek returned empty balance info")
        }

        guard let totalBalanceText = info.totalBalance,
              let totalBalance = Double(totalBalanceText) else {
            throw APIError(statusCode: 0, message: "Invalid or missing DeepSeek balance value")
        }

        return BalanceRecord(
            provider: .deepseek,
            totalBalance: totalBalance,
            grantAmount: info.grantedBalance.flatMap(Double.init),
            toppedUpAmount: info.toppedUpBalance.flatMap(Double.init),
            currency: info.currency
        )
    }

    func fetchUsage(startDate: Date, endDate: Date) async throws -> [UsageRecord] {
        // DeepSeek does not provide a usage history API.
        // Usage tracking must be done locally.
        throw UsageError.usageNotSupported
    }

    func verifyConnection() async throws {
        guard let url = URL(string: "\(config.baseURL)/models") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        try APIHelper.validateResponse(data: data, response: response)
    }
}
