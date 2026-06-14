// Models/ProviderConfig.swift
import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case pixel = "Pixel API"
    case deepseek = "DeepSeek"
    case openai = "OpenAI"
    case anthropic = "Anthropic"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .pixel: return "p.circle.fill"
        case .deepseek: return "d.square.fill"
        case .openai: return "o.circle.fill"
        case .anthropic: return "a.square.fill"
        }
    }

    var tintColor: String {
        switch self {
        case .pixel: return "green"
        case .deepseek: return "blue"
        case .openai: return "green"
        case .anthropic: return "orange"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .pixel: return AppConstants.Pixel.baseURL
        case .deepseek: return AppConstants.DeepSeek.baseURL
        case .openai: return AppConstants.OpenAI.baseURL
        case .anthropic: return AppConstants.Anthropic.baseURL
        }
    }
}

struct ProviderConfig: Codable, Identifiable, Equatable {
    var id: String { provider.rawValue }
    let provider: AIProvider
    var apiKey: String = ""
    var baseURL: String
    var isEnabled: Bool = true
    var displayOrder: Int = 0

    init(provider: AIProvider, apiKey: String = "", baseURL: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL ?? provider.defaultBaseURL
    }
}
