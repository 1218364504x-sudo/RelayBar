// Services/AnthropicService.swift
import Foundation

final class AnthropicService: UsageServiceProtocol {
    let provider: AIProvider = .anthropic
    let config: ProviderConfig

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func fetchBalance() async throws -> BalanceRecord {
        throw UsageError.balanceNotSupported
    }

    func verifyConnection() async throws {
        guard let url = URL(string: "\(config.baseURL)/v1/models") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("\(config.apiKey)", forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await session.data(for: request)
        try APIHelper.validateResponse(data: data, response: response)
    }

    func fetchUsage(startDate: Date, endDate: Date) async throws -> [UsageRecord] {
        throw UsageError.usageNotSupported
    }
}

enum UsageError: LocalizedError {
    case balanceNotSupported
    case usageNotSupported

    var errorDescription: String? {
        switch self {
        case .balanceNotSupported: return "This provider does not support balance queries"
        case .usageNotSupported: return "This provider does not support usage history"
        }
    }
}
