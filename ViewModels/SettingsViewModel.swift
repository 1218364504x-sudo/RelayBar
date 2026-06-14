// ViewModels/SettingsViewModel.swift
import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var refreshInterval: TimeInterval = AppConstants.defaultRefreshInterval
    @Published var showingAddProvider = false
    @Published var apiKeys: [AIProvider: String] = [:]

    var onIntervalChange: ((TimeInterval) -> Void)?

    init() {
        if UserDefaults.standard.bool(forKey: "manualRefreshEnabled") {
            refreshInterval = 0
        } else {
            let saved = UserDefaults.standard.double(forKey: "refreshInterval")
            refreshInterval = saved > 0 ? saved : AppConstants.defaultRefreshInterval
        }
    }

    func saveRefreshInterval() {
        UserDefaults.standard.set(refreshInterval == 0, forKey: "manualRefreshEnabled")
        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        onIntervalChange?(refreshInterval)
    }

    func loadAPIKey(for provider: AIProvider) -> String {
        (try? KeychainStorage().read(key: provider.rawValue)) ?? ""
    }
}
