// Utils/Constants.swift
import Foundation

enum AppConstants {
    static let appName = "kx"
    static let defaultRefreshInterval: TimeInterval = 300 // 5 minutes
    static let minRefreshInterval: TimeInterval = 30
    static let maxRefreshInterval: TimeInterval = 3600

    enum Pixel {
        static let baseURL = "https://example.com"
        static let dashboardProfileEndpoint = "/api/v1/user/profile"
        static let dashboardStatsEndpoint = "/api/v1/usage/dashboard/stats"
        static let newAPITokenUsageEndpoint = "/api/usage/token/"
        static let newAPITokenUsageEndpointNoSlash = "/api/usage/token"
        static let sub2APIUsageEndpoint = "/v1/usage"
        static let openAICompatibleSubscriptionEndpoint = "/v1/dashboard/billing/subscription"
        static let defaultBalanceUnit: Double = 500_000
    }

    enum DeepSeek {
        static let baseURL = "https://api.deepseek.com"
        static let balanceEndpoint = "/user/balance"
        // DeepSeek does not expose a public usage history API
    }

    enum OpenAI {
        static let baseURL = "https://api.openai.com"
        static let balanceEndpoint = "/dashboard/billing/subscription"
        static let usageEndpoint = "/dashboard/billing/usage"
    }

    enum Anthropic {
        static let baseURL = "https://api.anthropic.com"
    }
}
