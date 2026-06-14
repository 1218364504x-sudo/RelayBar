// Services/UsageServiceProtocol.swift
import Foundation

protocol UsageServiceProtocol {
    var provider: AIProvider { get }
    var config: ProviderConfig { get }

    /// Fetch current balance for the provider
    func fetchBalance() async throws -> BalanceRecord

    /// Fetch usage for a given period
    func fetchUsage(startDate: Date, endDate: Date) async throws -> [UsageRecord]

    /// Verify that the API key is valid with a lightweight request
    func verifyConnection() async throws
}

extension UsageServiceProtocol {
    /// Default implementation: try fetching models endpoint
    func verifyConnection() async throws {
        guard let url = URL(string: "\(config.baseURL)/models") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try APIHelper.validateResponse(data: data, response: response)
    }
}
