// Models/UsageRecord.swift
import Foundation

struct UsageRecord: Codable, Identifiable {
    let id: UUID
    let provider: AIProvider
    let timestamp: Date
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let cost: Double
    let currency: String

    init(
        provider: AIProvider,
        timestamp: Date = Date(),
        promptTokens: Int,
        completionTokens: Int,
        cost: Double,
        currency: String = "USD"
    ) {
        self.id = UUID()
        self.provider = provider
        self.timestamp = timestamp
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
        self.cost = cost
        self.currency = currency
    }
}

struct UsageSummary: Codable {
    let provider: AIProvider
    let totalTokensThisMonth: Int
    let totalCostThisMonth: Double
    let currency: String
    let lastUpdated: Date
}
