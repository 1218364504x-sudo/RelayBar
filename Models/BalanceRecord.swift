// Models/BalanceRecord.swift
import Foundation

struct BalanceRecord: Codable, Identifiable {
    let id: UUID
    let provider: AIProvider
    let timestamp: Date
    let totalBalance: Double
    let grantAmount: Double?
    let toppedUpAmount: Double?
    let totalUsed: Double
    let currency: String
    let endpointType: String?
    let isCached: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case timestamp
        case totalBalance
        case grantAmount
        case toppedUpAmount
        case totalUsed
        case currency
        case endpointType
        case isCached
    }

    init(
        provider: AIProvider,
        totalBalance: Double,
        grantAmount: Double? = nil,
        toppedUpAmount: Double? = nil,
        totalUsed: Double = 0,
        currency: String = "USD",
        endpointType: String? = nil,
        isCached: Bool = false
    ) {
        self.id = UUID()
        self.provider = provider
        self.timestamp = Date()
        self.totalBalance = totalBalance
        self.grantAmount = grantAmount
        self.toppedUpAmount = toppedUpAmount
        self.totalUsed = totalUsed
        self.currency = currency
        self.endpointType = endpointType
        self.isCached = isCached
    }

    private init(
        id: UUID,
        provider: AIProvider,
        timestamp: Date,
        totalBalance: Double,
        grantAmount: Double?,
        toppedUpAmount: Double?,
        totalUsed: Double,
        currency: String,
        endpointType: String?,
        isCached: Bool
    ) {
        self.id = id
        self.provider = provider
        self.timestamp = timestamp
        self.totalBalance = totalBalance
        self.grantAmount = grantAmount
        self.toppedUpAmount = toppedUpAmount
        self.totalUsed = totalUsed
        self.currency = currency
        self.endpointType = endpointType
        self.isCached = isCached
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try container.decode(AIProvider.self, forKey: .provider)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        totalBalance = try container.decode(Double.self, forKey: .totalBalance)
        grantAmount = try container.decodeIfPresent(Double.self, forKey: .grantAmount)
        toppedUpAmount = try container.decodeIfPresent(Double.self, forKey: .toppedUpAmount)
        totalUsed = try container.decodeIfPresent(Double.self, forKey: .totalUsed) ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        endpointType = try container.decodeIfPresent(String.self, forKey: .endpointType)
        isCached = try container.decodeIfPresent(Bool.self, forKey: .isCached) ?? false
    }

    func markedCached() -> BalanceRecord {
        BalanceRecord(
            id: id,
            provider: provider,
            timestamp: timestamp,
            totalBalance: totalBalance,
            grantAmount: grantAmount,
            toppedUpAmount: toppedUpAmount,
            totalUsed: totalUsed,
            currency: currency,
            endpointType: endpointType,
            isCached: true
        )
    }
}

enum PixelEndpointType: String, Codable {
    case newAPITokenUsage = "New API Token Usage"
    case sub2APIUsage = "sub2api /v1/usage"
    case openAICompatibleSubscription = "OpenAI-compatible subscription"
}

struct PixelTokenUsageResponse: Codable {
    let code: Bool?
    let success: Bool?
    let message: String?
    let data: PixelTokenUsageData?
}

struct PixelTokenUsageData: Codable {
    let object: String?
    let name: String?
    let grantedValue: Double?
    let usedValue: Double?
    let availableValue: Double?

    enum CodingKeys: String, CodingKey {
        case object
        case name
        case grantedValue = "total_granted"
        case usedValue = "total_used"
        case availableValue = "total_available"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        grantedValue = Self.decodeNumber(from: container, forKey: .grantedValue)
        usedValue = Self.decodeNumber(from: container, forKey: .usedValue)
        availableValue = Self.decodeNumber(from: container, forKey: .availableValue)
    }

    private static func decodeNumber(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let text = try? container.decode(String.self, forKey: key) {
            return Double(text)
        }
        return nil
    }
}

struct PixelV1UsageResponse: Codable {
    let mode: String?
    let planName: String?
    let balance: Double?
    let remaining: Double?
    let unit: String?
    let quota: PixelQuota?
    let usage: PixelUsageStats?
    let modelStats: [PixelModelUsage]?

    enum CodingKeys: String, CodingKey {
        case mode
        case planName
        case balance
        case remaining
        case unit
        case quota
        case usage
        case modelStats = "model_stats"
    }
}

struct PixelQuota: Codable {
    let limit: Double?
    let used: Double?
    let remaining: Double?
}

struct PixelUsageStats: Codable {
    let today: PixelUsageBucket?
    let total: PixelUsageBucket?
}

struct PixelUsageBucket: Codable {
    let requests: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let actualCost: Double?
    let cost: Double?

    enum CodingKeys: String, CodingKey {
        case requests
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case actualCost = "actual_cost"
        case cost
    }
}

struct PixelModelUsage: Codable {
    let model: String?
    let requests: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let actualCost: Double?
    let cost: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case requests
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case actualCost = "actual_cost"
        case cost
    }
}

struct PixelDashboardProfileResponse: Decodable {
    let success: Bool?
    let message: String?
    let data: PixelDashboardProfileData?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if let wrapped = try container.decodeIfPresent(PixelDashboardProfileData.self, forKey: .data) {
            data = wrapped
        } else {
            data = try? PixelDashboardProfileData(from: decoder)
        }
    }
}

struct PixelDashboardProfileData: Decodable {
    let balance: Double?
    let balanceCurrency: String?

    enum CodingKeys: String, CodingKey {
        case balance
        case quota
        case balanceCurrency = "balance_currency"
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balanceCurrency = try container.decodeIfPresent(String.self, forKey: .balanceCurrency)
            ?? container.decodeIfPresent(String.self, forKey: .currency)
            ?? "USD"

        if let explicitBalance = Self.decodeNumber(from: container, forKey: .balance) {
            balance = explicitBalance
        } else if let rawQuota = Self.decodeNumber(from: container, forKey: .quota) {
            // Internal compatibility fallback only. The 500000-to-1 conversion is a New API convention
            // and must be verified against the target relay site's live profile response before relying on it.
            balance = rawQuota / AppConstants.Pixel.defaultBalanceUnit
        } else {
            balance = nil
        }
    }

    private static func decodeNumber(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let text = try? container.decode(String.self, forKey: key) {
            return Double(text)
        }
        return nil
    }
}

struct PixelDashboardStatsResponse: Decodable {
    let success: Bool?
    let message: String?
    let data: PixelDashboardStatsData?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if let wrapped = try container.decodeIfPresent(PixelDashboardStatsData.self, forKey: .data) {
            data = wrapped
        } else {
            data = try? PixelDashboardStatsData(from: decoder)
        }
    }
}

struct PixelDashboardStatsData: Decodable {
    let todayCostPrimary: Double?
    let todayCostSecondary: Double?
    let todayTokenTotal: Double?
    let todayInputTokens: Double?
    let todayOutputTokens: Double?
    let totalTokenTotal: Double?
    let totalInputTokens: Double?
    let totalOutputTokens: Double?

    enum CodingKeys: String, CodingKey {
        case todayActualCost = "today_actual_cost"
        case todayCost = "today_cost"
        case todayTokens = "today_tokens"
        case todayInputTokens = "today_input_tokens"
        case todayOutputTokens = "today_output_tokens"
        case totalTokens = "total_tokens"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        todayCostPrimary = Self.decodeNumber(from: container, forKey: .todayActualCost)
        todayCostSecondary = Self.decodeNumber(from: container, forKey: .todayCost)
        todayTokenTotal = Self.decodeNumber(from: container, forKey: .todayTokens)
        todayInputTokens = Self.decodeNumber(from: container, forKey: .todayInputTokens)
        todayOutputTokens = Self.decodeNumber(from: container, forKey: .todayOutputTokens)
        totalTokenTotal = Self.decodeNumber(from: container, forKey: .totalTokens)
        totalInputTokens = Self.decodeNumber(from: container, forKey: .totalInputTokens)
        totalOutputTokens = Self.decodeNumber(from: container, forKey: .totalOutputTokens)
    }

    private static func decodeNumber(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let text = try? container.decode(String.self, forKey: key) {
            return Double(text)
        }
        return nil
    }
}

// MARK: - DeepSeek balance response
// GET https://api.deepseek.com/user/balance
// {
//   "is_available": true,
//   "balance_infos": [{
//     "currency": "CNY",
//     "total_balance": "10.50",
//     "granted_balance": "5.00",
//     "topped_up_balance": "5.50"
//   }]
// }
struct DeepSeekBalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    struct BalanceInfo: Codable {
        let currency: String
        let totalBalance: String?
        let grantedBalance: String?
        let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }

        // DeepSeek API may return numbers or strings for balance fields
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "CNY"

            totalBalance = Self.decodeDecimalString(from: container, forKey: .totalBalance)
            grantedBalance = Self.decodeDecimalString(from: container, forKey: .grantedBalance)
            toppedUpBalance = Self.decodeDecimalString(from: container, forKey: .toppedUpBalance)
        }

        private static func decodeDecimalString(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> String? {
            if let s = try? container.decode(String.self, forKey: key) {
                return s
            }
            if let d = try? container.decode(Double.self, forKey: key) {
                return String(d)
            }
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

// MARK: - OpenAI subscription response
// GET https://api.openai.com/dashboard/billing/subscription
// { "hard_limit_usd": 120, "soft_limit_usd": 100 }
struct OpenAISubscriptionResponse: Codable {
    let hardLimitUsd: Double?
    let softLimitUsd: Double?

    enum CodingKeys: String, CodingKey {
        case hardLimitUsd = "hard_limit_usd"
        case softLimitUsd = "soft_limit_usd"
    }
}
