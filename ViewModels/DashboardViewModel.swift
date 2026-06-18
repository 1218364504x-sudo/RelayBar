// ViewModels/DashboardViewModel.swift
import Foundation
import Combine
import WidgetKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var providers: [ProviderConfig] = []
    @Published var balances: [AIProvider: BalanceRecord] = [:]
    @Published var usageSummaries: [AIProvider: UsageSummary] = [:]
    @Published var usageHistory: [AIProvider: [UsageRecord]] = [:]
    @Published var pixelDashboardSnapshot: PixelDashboardSnapshot?
    @Published var providerProfiles: [APIProviderProfile] = []
    @Published var activeProviderID = "pixel_default"
    @Published var followCCSwitchCurrentProvider = false {
        didSet {
            UserDefaults.standard.set(followCCSwitchCurrentProvider, forKey: "followCCSwitchCurrentProvider")
            if followCCSwitchCurrentProvider {
                startCCSwitchMonitor()
                Task { await syncWithCCSwitch(force: true) }
            } else {
                stopCCSwitchMonitor()
            }
        }
    }
    @Published var ccSwitchSyncMode: CCSwitchSyncMode = .statusOnly {
        didSet {
            UserDefaults.standard.set(ccSwitchSyncMode.rawValue, forKey: "ccSwitchSyncMode")
        }
    }
    @Published var ccSwitchDataSourceSelectionMode: CCSwitchDataSourceSelectionMode = .automatic {
        didSet {
            UserDefaults.standard.set(ccSwitchDataSourceSelectionMode.rawValue, forKey: "ccSwitchDataSourceMode")
            ccSwitchService.dataSourceSelectionMode = ccSwitchDataSourceSelectionMode
            updateCCSwitchDataSourceDescription()
        }
    }
    @Published var ccSwitchLastSnapshot: CCSwitchProviderSnapshot?
    @Published var ccSwitchDataSourceDescription = "自动检测"
    @Published var ccSwitchStatusText = "未检测"
    @Published var ccSwitchErrorMessage: String?
    @Published var isSyncingCCSwitch = false
    @Published var isRefreshing = false
    @Published var lastRefreshDate: Date?
    @Published var errorMessages: [AIProvider: String] = [:]
    @Published var globalError: String?
    @Published var saveError: String?

    // Floating window & menu bar display
    @Published var showFloatingWindow = false {
        didSet {
            UserDefaults.standard.set(showFloatingWindow, forKey: "showFloatingWindow")
            if showFloatingWindow {
                floatingPanel?.show()
            } else {
                floatingPanel?.hide()
            }
        }
    }
    @Published var showBalanceInMenuBar = true {
        didSet {
            UserDefaults.standard.set(showBalanceInMenuBar, forKey: "showBalanceInMenuBar")
        }
    }
    @Published var preferredCurrency: CurrencyType = .cny {
        didSet {
            UserDefaults.standard.set(preferredCurrency.rawValue, forKey: "preferredCurrency")
            if preferredCurrency == .usd && exchangeRate == nil {
                fetchExchangeRate()
            }
        }
    }
    @Published var lowBalanceThreshold: Double = 10 {
        didSet {
            UserDefaults.standard.set(lowBalanceThreshold, forKey: "pixelLowBalanceThreshold")
            publishPixelDashboardSnapshotForCurrentState()
        }
    }
    @Published var codexQuotaEnabled = false {
        didSet { saveCodexQuotaSettingsAndPublish() }
    }
    @Published var codexQuotaAutoRefreshEnabled = false {
        didSet {
            saveCodexQuotaSettingsAndPublish()
            if codexQuotaAutoRefreshEnabled, oldValue != codexQuotaAutoRefreshEnabled, !isReadingCodexQuota {
                Task { await refreshCodexQuotaFromCLI() }
            }
        }
    }
    @Published var codexWeeklyRemaining: Double = 0 {
        didSet { saveCodexQuotaSettingsAndPublish() }
    }
    @Published var codexWeeklyTotal: Double = 0 {
        didSet { saveCodexQuotaSettingsAndPublish() }
    }
    @Published var codexFiveHourRemaining: Double = 0 {
        didSet { saveCodexQuotaSettingsAndPublish() }
    }
    @Published var codexFiveHourTotal: Double = 0 {
        didSet { saveCodexQuotaSettingsAndPublish() }
    }
    @Published private(set) var codexQuotaLastReadDate: Date?
    @Published private(set) var codexQuotaLastReadError: String?
    @Published private(set) var isReadingCodexQuota = false
    @Published var exchangeRate: Double?

    enum CurrencyType: String, CaseIterable, Identifiable {
        case cny = "CNY"
        case usd = "USD"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .cny: return "¥"
            case .usd: return "$"
            }
        }
    }

    var deepseekBalanceLabel: String {
        let (amount, currency) = displayDeepseekBalance
        guard let amount else { return "" }
        return String(format: "\(currency.symbol)%.1f", amount)
    }

    var displayDeepseekBalance: (amount: Double?, currency: CurrencyType) {
        guard let record = balances[.deepseek] else { return (nil, preferredCurrency) }
        let display = displayBalance(for: record)
        return (display.amount, display.currency)
    }

    var pixelBalance: BalanceRecord? {
        balances[.pixel]
    }

    var sortedProviderProfiles: [APIProviderProfile] {
        providerProfiles.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var activeProviderProfile: APIProviderProfile? {
        if let selected = providerProfiles.first(where: { $0.id == activeProviderID && $0.isEnabled }) {
            return selected
        }
        return sortedProviderProfiles.first(where: { $0.isEnabled })
    }

    var activeProviderDisplayName: String {
        activeProviderProfile?.displayName ?? "Pixel API"
    }

    var isActiveProviderConfigured: Bool {
        guard let profile = activeProviderProfile else { return false }
        guard let credential = try? keychain.readCredential(for: profile.id) else { return false }
        return !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pixelMenuBarLabel: String {
        let name = shortenedMenuName(activeProviderDisplayName)
        guard isActiveProviderConfigured else { return "\(name) Setup" }
        if let error = errorMessages[.pixel], pixelDashboardSnapshot?.balance == nil, balances[.pixel] == nil {
            if error.localizedCaseInsensitiveContains("API Key is empty") {
                return "\(name) Setup"
            }
            return "\(name) !"
        }
        guard showBalanceInMenuBar else {
            if pixelDashboardSnapshot?.status == .lowBalance {
                return "\(name) ⚠️"
            }
            return name
        }
        if let snapshot = pixelDashboardSnapshot,
           let balance = snapshot.balance {
            let prefix = snapshot.status == .lowBalance ? "\(name) ⚠️ " : "\(name) "
            return prefix + formatPixelMoney(balance, currency: snapshot.balanceCurrency ?? "USD")
        }
        guard let record = balances[.pixel] else {
            return isRefreshing ? "\(name) ..." : "\(name) !"
        }
        let lowBalance = record.totalBalance < lowBalanceThreshold
        let prefix = lowBalance ? "\(name) ⚠️ " : "\(name) "
        return prefix + formatPixelMoney(record.totalBalance, currency: record.currency)
    }

    var pixelStatusText: String {
        if pixelDashboardSnapshot?.status == .notConfigured {
            return "未配置"
        }
        if pixelDashboardSnapshot?.status == .unauthorized {
            return "未授权"
        }
        if let error = errorMessages[.pixel], pixelDashboardSnapshot == nil, balances[.pixel] == nil {
            return error
        }
        if pixelDashboardSnapshot?.status == .cached || balances[.pixel]?.isCached == true {
            return "缓存"
        }
        if isRefreshing {
            return "刷新中"
        }
        return pixelDashboardSnapshot == nil && balances[.pixel] == nil ? "未连接" : "正常"
    }

    var pixelStatusColorName: String {
        if errorMessages[.pixel] != nil && pixelDashboardSnapshot == nil && balances[.pixel] == nil {
            return "red"
        }
        if pixelDashboardSnapshot?.status == .unauthorized || pixelDashboardSnapshot?.status == .error {
            return "red"
        }
        if pixelDashboardSnapshot?.status == .cached || pixelDashboardSnapshot?.status == .notConfigured || balances[.pixel]?.isCached == true {
            return "gray"
        }
        if pixelDashboardSnapshot?.status == .lowBalance {
            return "yellow"
        }
        if let record = balances[.pixel], record.totalBalance < lowBalanceThreshold {
            return "yellow"
        }
        return pixelDashboardSnapshot == nil && balances[.pixel] == nil ? "gray" : "green"
    }

    func displayAmount(_ amount: Double, currency: String) -> (amount: Double, currency: CurrencyType) {
        let actualCurrency = currency.uppercased()
        if preferredCurrency == .usd, actualCurrency == "CNY", let rate = exchangeRate {
            return (amount / rate, .usd)
        }
        if preferredCurrency == .cny, actualCurrency == "USD", let rate = exchangeRate {
            return (amount * rate, .cny)
        }
        let type = CurrencyType(rawValue: actualCurrency) ?? preferredCurrency
        return (amount, type)
    }

    func displayBalance(for record: BalanceRecord) -> (amount: Double, currency: CurrencyType) {
        displayAmount(record.totalBalance, currency: record.currency)
    }

    func displayCost(_ amount: Double, currency: String) -> (amount: Double, currency: CurrencyType) {
        displayAmount(amount, currency: currency)
    }

    func formatPixelMoney(_ amount: Double?, currency: String = "USD") -> String {
        guard let amount else { return "--" }
        if currency.uppercased() == "USD" {
            if amount > 0, amount < 1 {
                return String(format: "$%.4f", amount)
            }
            return String(format: "$%.2f", amount)
        }
        if amount > 0, amount < 1 {
            return String(format: "%.4f %@", amount, currency)
        }
        return String(format: "%.2f %@", amount, currency)
    }

    func formatPixelTokens(_ value: Double?) -> String {
        guard let value else { return "--" }
        let absValue = abs(value)
        if absValue >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    func formatPixelTokenBreakdown(input: Double?, output: Double?) -> String {
        let inputText = formatPixelTokens(input)
        let outputText = formatPixelTokens(output)
        if inputText == "--", outputText == "--" {
            return "--"
        }
        return "\(inputText) / \(outputText)"
    }

    func formatPixelTodayCost(_ snapshot: PixelDashboardSnapshot?) -> String {
        guard let snapshot else { return "--" }
        let primary = formatPixelMoney(snapshot.todayCostPrimary, currency: snapshot.balanceCurrency ?? "USD")
        guard snapshot.todayCostSecondary != nil else { return primary }
        let secondary = formatPixelMoney(snapshot.todayCostSecondary, currency: snapshot.balanceCurrency ?? "USD")
        return "\(primary) / \(secondary)"
    }

    func formatPixelTime(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }

    func formatCodexQuota(remaining: Double?, total: Double?, isPercentBased: Bool = false) -> String {
        guard let remaining else { return "--" }
        let roundedRemaining = max(0, remaining)
        if isPercentBased {
            return String(format: "%.0f%%", min(100, roundedRemaining))
        }
        guard let total, total > 0 else {
            return String(format: "%.0f", roundedRemaining)
        }
        return "\(String(format: "%.0f", roundedRemaining)) / \(String(format: "%.0f", total))"
    }

    func formatCodexQuotaPercent(remaining: Double?, total: Double?, isPercentBased: Bool = false) -> String {
        guard let remaining, let total, total > 0 else { return "--" }
        let percent = max(0, min(1, remaining / total)) * 100
        return String(format: "%.0f%%", percent)
    }

    func formatCodexQuotaResetTime(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    func resetCodexQuotaToFull() {
        if codexWeeklyTotal > 0 {
            codexWeeklyRemaining = codexWeeklyTotal
        }
        if codexFiveHourTotal > 0 {
            codexFiveHourRemaining = codexFiveHourTotal
        }
    }

    private let keychain = KeychainStorage()
    private let cache = LocalCache()
    private var refreshTask: Task<Void, Never>?
    private var ccSwitchMonitorTask: Task<Void, Never>?
    private var lastCCSwitchDataSourceModifiedAt: Date?
    private var floatingPanel: FloatingPanelController?
    private let exchangeService = ExchangeRateService()
    private let ccSwitchService = CCSwitchIntegrationService()
    private let defaultProviderProfileID = "pixel_default"
    private let codexQuotaEnabledKey = "codexQuotaEnabled"
    private let codexQuotaAutoRefreshEnabledKey = "codexQuotaAutoRefreshEnabled"
    private let codexWeeklyRemainingKey = "codexWeeklyRemaining"
    private let codexWeeklyTotalKey = "codexWeeklyTotal"
    private let codexWeeklyResetAtKey = "codexWeeklyResetAt"
    private let codexFiveHourRemainingKey = "codexFiveHourRemaining"
    private let codexFiveHourTotalKey = "codexFiveHourTotal"
    private let codexFiveHourResetAtKey = "codexFiveHourResetAt"
    private let codexQuotaLastReadAtKey = "codexQuotaLastReadAt"
    private var isLoadingPreferences = false

    var totalCostThisMonth: Double {
        usageSummaries.values.reduce(0) { $0 + $1.totalCostThisMonth }
    }

    var activeProviderCount: Int {
        providers.filter { $0.isEnabled && !$0.apiKey.isEmpty }.count
    }

    var enabledProviders: [ProviderConfig] {
        providers.filter { $0.isEnabled }
    }

    private var savedRefreshInterval: TimeInterval {
        if UserDefaults.standard.bool(forKey: "manualRefreshEnabled") {
            return 0
        }
        let saved = UserDefaults.standard.double(forKey: "refreshInterval")
        return saved > 0 ? saved : AppConstants.defaultRefreshInterval
    }

    private var isPixelConfigured: Bool {
        isActiveProviderConfigured
    }

    init() {
        loadProviders()
        setupDefaultProviders()
        loadProviderProfiles()
        loadCachedData()
        loadPreferences()
        updateCCSwitchDataSourceDescription()
        publishPixelDashboardSnapshotForCurrentState()
        floatingPanel = FloatingPanelController(dashboardVM: self)
        if showFloatingWindow { floatingPanel?.show() }
        startAutoRefresh(interval: savedRefreshInterval)
        if followCCSwitchCurrentProvider {
            startCCSwitchMonitor()
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if followCCSwitchCurrentProvider {
                await syncWithCCSwitch(force: true)
            } else if isPixelConfigured {
                await refreshAll()
            }
        }
    }

    private func loadPreferences() {
        isLoadingPreferences = true
        defer { isLoadingPreferences = false }

        showFloatingWindow = UserDefaults.standard.bool(forKey: "showFloatingWindow")
        let didMigrateMenuBarBalanceDefaultKey = "didMigrateMenuBarBalanceDefaultV2"
        if !UserDefaults.standard.bool(forKey: didMigrateMenuBarBalanceDefaultKey) {
            showBalanceInMenuBar = true
            UserDefaults.standard.set(true, forKey: didMigrateMenuBarBalanceDefaultKey)
        } else if UserDefaults.standard.object(forKey: "showBalanceInMenuBar") != nil {
            showBalanceInMenuBar = UserDefaults.standard.bool(forKey: "showBalanceInMenuBar")
        } else {
            showBalanceInMenuBar = true
        }
        if let raw = UserDefaults.standard.string(forKey: "preferredCurrency"),
           let currency = CurrencyType(rawValue: raw) {
            preferredCurrency = currency
        }
        followCCSwitchCurrentProvider = UserDefaults.standard.bool(forKey: "followCCSwitchCurrentProvider")
        if let raw = UserDefaults.standard.string(forKey: "ccSwitchSyncMode"),
           let mode = CCSwitchSyncMode(rawValue: raw) {
            ccSwitchSyncMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "ccSwitchDataSourceMode"),
           let mode = CCSwitchDataSourceSelectionMode(rawValue: raw) {
            ccSwitchDataSourceSelectionMode = mode
        }
        let savedThreshold = UserDefaults.standard.double(forKey: "pixelLowBalanceThreshold")
        if savedThreshold > 0 {
            lowBalanceThreshold = savedThreshold
        }
        codexQuotaEnabled = UserDefaults.standard.bool(forKey: codexQuotaEnabledKey)
        codexQuotaAutoRefreshEnabled = UserDefaults.standard.bool(forKey: codexQuotaAutoRefreshEnabledKey)
        codexWeeklyRemaining = UserDefaults.standard.double(forKey: codexWeeklyRemainingKey)
        codexWeeklyTotal = UserDefaults.standard.double(forKey: codexWeeklyTotalKey)
        codexFiveHourRemaining = UserDefaults.standard.double(forKey: codexFiveHourRemainingKey)
        codexFiveHourTotal = UserDefaults.standard.double(forKey: codexFiveHourTotalKey)
        codexQuotaLastReadDate = UserDefaults.standard.object(forKey: codexQuotaLastReadAtKey) as? Date
    }

    func fetchExchangeRate() {
        Task {
            do {
                let snapshot = try await exchangeService.fetchUSDCNYRate()
                exchangeRate = snapshot.rate
            } catch {
                // Exchange rate unavailable — will show CNY
            }
        }
    }

    private func setupDefaultProviders() {
        guard providers.isEmpty else { return }
        providers = [
            ProviderConfig(provider: .pixel, baseURL: AppConstants.Pixel.baseURL),
            ProviderConfig(provider: .deepseek, baseURL: AppConstants.DeepSeek.baseURL),
            ProviderConfig(provider: .openai, baseURL: AppConstants.OpenAI.baseURL),
            ProviderConfig(provider: .anthropic, baseURL: AppConstants.Anthropic.baseURL)
        ]
        saveProviderConfigs()
    }

    private func loadProviderProfiles() {
        let loadedProfiles = (try? cache.loadProviderProfiles()) ?? []
        if loadedProfiles.isEmpty {
            providerProfiles = [makeDefaultPixelProfile()]
            saveProviderProfiles()
        } else {
            providerProfiles = loadedProfiles
            if !providerProfiles.contains(where: { $0.id == defaultProviderProfileID }) {
                providerProfiles.insert(makeDefaultPixelProfile(sortOrder: providerProfiles.count), at: 0)
                saveProviderProfiles()
            }
        }

        migrateLegacyPixelCredentialIfNeeded()

        if let savedSelection = try? PixelDashboardSnapshotStore.loadActiveSelection(),
           providerProfiles.contains(where: { $0.id == savedSelection.activeProviderID && $0.isEnabled }) {
            activeProviderID = savedSelection.activeProviderID
        } else if let first = sortedProviderProfiles.first(where: { $0.isEnabled }) {
            activeProviderID = first.id
            saveActiveProviderSelection()
        }
    }

    private func makeDefaultPixelProfile(sortOrder: Int = 0) -> APIProviderProfile {
        APIProviderProfile(
            id: defaultProviderProfileID,
            displayName: "Pixel API",
            baseURL: AppConstants.Pixel.baseURL,
            providerType: .pixelDashboard,
            isEnabled: true,
            sortOrder: sortOrder,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func migrateLegacyPixelCredentialIfNeeded() {
        guard (try? keychain.readCredential(for: defaultProviderProfileID)) == nil else { return }
        let legacyKey = providers.first(where: { $0.provider == .pixel })?.apiKey
            ?? (try? keychain.read(key: AIProvider.pixel.rawValue))
            ?? ""
        let trimmed = legacyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? keychain.saveCredential(for: defaultProviderProfileID, value: trimmed)
    }

    private func saveProviderProfiles() {
        try? cache.saveProviderProfiles(providerProfiles)
    }

    private func saveActiveProviderSelection() {
        try? PixelDashboardSnapshotStore.saveActiveSelection(
            ActiveProviderSelection(activeProviderID: activeProviderID, updatedAt: Date())
        )
    }

    private func publishWidgetSnapshot(_ snapshot: PixelDashboardSnapshot, saveProviderCopy: Bool = true) {
        let snapshotForWidget = snapshotWithCodexQuota(snapshot)
        do {
            if saveProviderCopy {
                try PixelDashboardSnapshotStore.save(snapshotForWidget)
            } else {
                try PixelDashboardSnapshotStore.saveCurrent(snapshotForWidget)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widget cache is best-effort; the main app UI remains authoritative.
        }
    }

    private func loadProviders() {
        do {
            let configs = try cache.loadConfig()
            if !configs.isEmpty {
                var loadedProviders = configs.map { cached in
                    var config = cached
                    config.apiKey = (try? keychain.read(key: cached.provider.rawValue)) ?? ""
                    // Preserve cached isEnabled instead of always resetting to true
                    return config
                }
                if !loadedProviders.contains(where: { $0.provider == .pixel }) {
                    var pixel = ProviderConfig(provider: .pixel, baseURL: AppConstants.Pixel.baseURL)
                    pixel.apiKey = (try? keychain.read(key: AIProvider.pixel.rawValue)) ?? ""
                    loadedProviders.insert(pixel, at: 0)
                    try? cache.saveConfig(loadedProviders)
                }
                self.providers = loadedProviders
            }
        } catch {
            globalError = "Failed to load provider configs"
        }
    }

    private func loadCachedData() {
        for provider in AIProvider.allCases {
            usageHistory[provider] = (try? cache.loadUsageHistory(for: provider)) ?? []
            if let cachedBalance = try? cache.loadBalance(for: provider) {
                balances[provider] = cachedBalance.markedCached()
            }
        }
        if let cachedSnapshot = try? PixelDashboardSnapshotStore.load() {
            pixelDashboardSnapshot = cachedSnapshot.withStatus(.cached)
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshDate = Date()
        }

        globalError = nil
        errorMessages = [:]

        if followCCSwitchCurrentProvider {
            await syncWithCCSwitch(force: true)
        } else {
            await refreshActiveProviderCore()
        }
        await refreshCodexQuotaIfNeeded()

        // Fetch exchange rate if USD display is preferred
        if preferredCurrency == .usd {
            do {
                let snapshot = try await exchangeService.fetchUSDCNYRate()
                exchangeRate = snapshot.rate
            } catch {
                // Will show CNY if rate unavailable
            }
        }

    }

    private func publishPixelDashboardSnapshotForCurrentState() {
        let snapshot: PixelDashboardSnapshot

        guard let profile = activeProviderProfile else {
            return
        }

        if !isPixelConfigured {
            snapshot = makePixelDashboardSnapshot(
                from: pixelDashboardSnapshot?.providerID == profile.id ? pixelDashboardSnapshot : nil,
                status: .notConfigured,
                errorMessage: "请先配置当前配置档凭证",
                useExistingTimestamp: false
            )
        } else if let error = errorMessages[.pixel], pixelDashboardSnapshot == nil {
            snapshot = makePixelDashboardSnapshot(
                from: nil,
                status: statusForErrorMessage(error),
                errorMessage: sanitizedWidgetErrorMessage(error),
                useExistingTimestamp: false
            )
        } else if let current = pixelDashboardSnapshot {
            if current.status == .cached,
               current.balance == nil,
               let record = balances[.pixel] {
                let status: PixelDashboardStatus = record.totalBalance < lowBalanceThreshold ? .lowBalance : .normal
                snapshot = PixelDashboardSnapshot(
                    providerName: profile.displayName,
                    baseURL: profile.baseURL,
                    balance: record.totalBalance,
                    balanceCurrency: record.currency,
                    todayCostPrimary: nil,
                    todayCostSecondary: nil,
                    todayTokenTotal: nil,
                    todayInputTokens: nil,
                    todayOutputTokens: nil,
                    totalTokenTotal: nil,
                    totalInputTokens: nil,
                    totalOutputTokens: nil,
                    updatedAt: record.timestamp,
                    status: status,
                    errorMessage: nil
                ).withProfile(profile)
            } else {
            let status: PixelDashboardStatus
            if current.status == .cached {
                status = .cached
            } else if let balance = current.balance, balance < lowBalanceThreshold {
                status = .lowBalance
            } else {
                status = .normal
            }
            snapshot = makePixelDashboardSnapshot(
                from: current,
                status: status,
                errorMessage: nil,
                useExistingTimestamp: true
            )
            }
        } else if let record = balances[.pixel] {
            let status: PixelDashboardStatus = record.totalBalance < lowBalanceThreshold ? .lowBalance : .normal
            snapshot = PixelDashboardSnapshot(
                providerName: profile.displayName,
                baseURL: profile.baseURL,
                balance: record.totalBalance,
                balanceCurrency: record.currency,
                todayCostPrimary: nil,
                todayCostSecondary: nil,
                todayTokenTotal: nil,
                todayInputTokens: nil,
                todayOutputTokens: nil,
                totalTokenTotal: nil,
                totalInputTokens: nil,
                totalOutputTokens: nil,
                updatedAt: record.timestamp,
                status: status,
                errorMessage: nil
            ).withProfile(profile)
        } else {
            snapshot = makePixelDashboardSnapshot(
                from: nil,
                status: .notConfigured,
                errorMessage: "请先刷新当前配置档",
                useExistingTimestamp: false
            )
        }

        let profiledSnapshot = snapshotWithCodexQuota(snapshot.withProfile(profile))
        pixelDashboardSnapshot = profiledSnapshot
        publishWidgetSnapshot(profiledSnapshot)
    }

    private func makePixelDashboardSnapshot(
        from current: PixelDashboardSnapshot?,
        status: PixelDashboardStatus,
        errorMessage: String?,
        useExistingTimestamp: Bool
    ) -> PixelDashboardSnapshot {
        let profile = activeProviderProfile
        let scopedCurrent = current?.providerID == nil || current?.providerID == profile?.id ? current : nil
        return PixelDashboardSnapshot(
            providerName: profile?.displayName ?? "Pixel API",
            baseURL: profile?.baseURL ?? AppConstants.Pixel.baseURL,
            balance: scopedCurrent?.balance,
            balanceCurrency: scopedCurrent?.balanceCurrency ?? "USD",
            todayCostPrimary: scopedCurrent?.todayCostPrimary,
            todayCostSecondary: scopedCurrent?.todayCostSecondary,
            todayTokenTotal: scopedCurrent?.todayTokenTotal,
            todayInputTokens: scopedCurrent?.todayInputTokens,
            todayOutputTokens: scopedCurrent?.todayOutputTokens,
            totalTokenTotal: scopedCurrent?.totalTokenTotal,
            totalInputTokens: scopedCurrent?.totalInputTokens,
            totalOutputTokens: scopedCurrent?.totalOutputTokens,
            updatedAt: useExistingTimestamp ? (scopedCurrent?.updatedAt ?? Date()) : Date(),
            status: status,
            errorMessage: errorMessage
        ).withProfile(profile ?? makeDefaultPixelProfile())
    }

    private func refreshActiveProviderCore() async {
        guard let profile = activeProviderProfile else {
            pixelDashboardSnapshot = nil
            return
        }

        let credential = (try? keychain.readCredential(for: profile.id))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !credential.isEmpty else {
            let snapshot = emptySnapshot(
                for: profile,
                status: .notConfigured,
                errorMessage: "请先配置当前配置档凭证"
            )
            pixelDashboardSnapshot = snapshot
            balances[.pixel] = nil
            errorMessages[.pixel] = nil
            publishWidgetSnapshot(snapshot, saveProviderCopy: false)
            return
        }

        do {
            let snapshot = try await fetchSnapshot(for: profile, credential: credential)
            let profiledSnapshot = snapshotWithCodexQuota(snapshot.withProfile(profile))
            pixelDashboardSnapshot = profiledSnapshot
            errorMessages[.pixel] = nil

            if let balance = profiledSnapshot.balance {
                let record = BalanceRecord(
                    provider: .pixel,
                    totalBalance: balance,
                    totalUsed: profiledSnapshot.todayCostPrimary ?? 0,
                    currency: profiledSnapshot.balanceCurrency ?? "USD",
                    endpointType: profile.providerType.displayName
                )
                balances[.pixel] = record
                try? cache.saveBalance(record, for: .pixel)
            }

            publishWidgetSnapshot(profiledSnapshot)
        } catch {
            let rawMessage = error.localizedDescription
            let safeMessage = sanitizedWidgetErrorMessage(rawMessage)
            errorMessages[.pixel] = safeMessage

            if let cachedSnapshot = try? PixelDashboardSnapshotStore.loadProviderSnapshot(providerID: profile.id) {
                let snapshot = cachedSnapshot
                    .withProfile(profile)
                    .withStatus(.cached, errorMessage: safeMessage)
                let snapshotWithQuota = snapshotWithCodexQuota(snapshot)
                pixelDashboardSnapshot = snapshotWithQuota
                publishWidgetSnapshot(snapshotWithQuota, saveProviderCopy: false)
            } else {
                let snapshot = emptySnapshot(
                    for: profile,
                    status: statusForErrorMessage(rawMessage),
                    errorMessage: safeMessage
                )
                let snapshotWithQuota = snapshotWithCodexQuota(snapshot)
                pixelDashboardSnapshot = snapshotWithQuota
                publishWidgetSnapshot(snapshotWithQuota, saveProviderCopy: false)
            }
        }
    }

    private func fetchSnapshot(for profile: APIProviderProfile, credential: String) async throws -> PixelDashboardSnapshot {
        switch profile.providerType {
        case .pixelDashboard, .newAPICompatible, .oneAPICompatible, .custom:
            let config = ProviderConfig(provider: .pixel, apiKey: credential, baseURL: normalizedBaseURL(profile.baseURL))
            let service = PixelUsageService(config: config)
            do {
                return try await service.fetchDashboardSnapshot(lowBalanceThreshold: lowBalanceThreshold)
            } catch {
                let record = try await service.fetchBalance()
                let status: PixelDashboardStatus = record.totalBalance < lowBalanceThreshold ? .lowBalance : .normal
                return PixelDashboardSnapshot(
                    providerName: profile.displayName,
                    baseURL: profile.baseURL,
                    balance: record.totalBalance,
                    balanceCurrency: record.currency,
                    todayCostPrimary: nil,
                    todayCostSecondary: nil,
                    todayTokenTotal: nil,
                    todayInputTokens: nil,
                    todayOutputTokens: nil,
                    totalTokenTotal: nil,
                    totalInputTokens: nil,
                    totalOutputTokens: nil,
                    updatedAt: Date(),
                    status: status,
                    errorMessage: nil
                )
            }
        case .deepSeekBalance:
            let config = ProviderConfig(provider: .deepseek, apiKey: credential, baseURL: normalizedBaseURL(profile.baseURL))
            let record = try await DeepSeekService(config: config).fetchBalance()
            let status: PixelDashboardStatus = record.totalBalance < lowBalanceThreshold ? .lowBalance : .normal
            return PixelDashboardSnapshot(
                providerName: profile.displayName,
                baseURL: profile.baseURL,
                balance: record.totalBalance,
                balanceCurrency: record.currency,
                todayCostPrimary: nil,
                todayCostSecondary: nil,
                todayTokenTotal: nil,
                todayInputTokens: nil,
                todayOutputTokens: nil,
                totalTokenTotal: nil,
                totalInputTokens: nil,
                totalOutputTokens: nil,
                updatedAt: Date(),
                status: status,
                errorMessage: nil
            )
        }
    }

    private func emptySnapshot(
        for profile: APIProviderProfile,
        status: PixelDashboardStatus,
        errorMessage: String?
    ) -> PixelDashboardSnapshot {
        PixelDashboardSnapshot(
            providerName: profile.displayName,
            baseURL: profile.baseURL,
            balance: nil,
            balanceCurrency: "USD",
            todayCostPrimary: nil,
            todayCostSecondary: nil,
            todayTokenTotal: nil,
            todayInputTokens: nil,
            todayOutputTokens: nil,
            totalTokenTotal: nil,
            totalInputTokens: nil,
            totalOutputTokens: nil,
            updatedAt: Date(),
            status: status,
            errorMessage: errorMessage
        ).withProfile(profile)
    }

    private var currentCodexQuotaSnapshot: CodexQuotaSnapshot? {
        guard codexQuotaEnabled else { return nil }
        let weeklyTotal = codexWeeklyTotal > 0 ? codexWeeklyTotal : nil
        let weeklyRemaining = quotaRemaining(codexWeeklyRemaining, total: weeklyTotal)
        let fiveHourTotal = codexFiveHourTotal > 0 ? codexFiveHourTotal : nil
        let fiveHourRemaining = quotaRemaining(codexFiveHourRemaining, total: fiveHourTotal)
        let weeklyResetAt = UserDefaults.standard.object(forKey: codexWeeklyResetAtKey) as? Date
        let fiveHourResetAt = UserDefaults.standard.object(forKey: codexFiveHourResetAtKey) as? Date

        guard weeklyRemaining != nil || weeklyTotal != nil || fiveHourRemaining != nil || fiveHourTotal != nil else {
            return nil
        }

        return CodexQuotaSnapshot(
            weeklyRemaining: weeklyRemaining,
            weeklyTotal: weeklyTotal,
            weeklyResetAt: weeklyResetAt,
            fiveHourRemaining: fiveHourRemaining,
            fiveHourTotal: fiveHourTotal,
            fiveHourResetAt: fiveHourResetAt,
            isPercentBased: codexQuotaAutoRefreshEnabled,
            updatedAt: Date()
        )
    }

    private func quotaRemaining(_ value: Double, total: Double?) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        if let total {
            return min(value, total)
        }
        return value > 0 ? value : nil
    }

    private func snapshotWithCodexQuota(_ snapshot: PixelDashboardSnapshot) -> PixelDashboardSnapshot {
        var snapshot = snapshot
        snapshot.codexQuota = currentCodexQuotaSnapshot
        return snapshot
    }

    private func saveCodexQuotaSettingsAndPublish() {
        guard !isLoadingPreferences else { return }
        UserDefaults.standard.set(codexQuotaEnabled, forKey: codexQuotaEnabledKey)
        UserDefaults.standard.set(codexQuotaAutoRefreshEnabled, forKey: codexQuotaAutoRefreshEnabledKey)
        UserDefaults.standard.set(max(0, codexWeeklyRemaining), forKey: codexWeeklyRemainingKey)
        UserDefaults.standard.set(max(0, codexWeeklyTotal), forKey: codexWeeklyTotalKey)
        UserDefaults.standard.set(max(0, codexFiveHourRemaining), forKey: codexFiveHourRemainingKey)
        UserDefaults.standard.set(max(0, codexFiveHourTotal), forKey: codexFiveHourTotalKey)
        publishPixelDashboardSnapshotForCurrentState()
    }

    func refreshCodexQuotaIfNeeded() async {
        guard codexQuotaEnabled, codexQuotaAutoRefreshEnabled else { return }
        await refreshCodexQuotaFromCLI()
    }

    func refreshCodexQuotaFromCLI() async {
        guard codexQuotaEnabled else { return }
        isReadingCodexQuota = true
        codexQuotaLastReadError = nil
        defer { isReadingCodexQuota = false }

        do {
            let reading = try await CodexQuotaCLIReader().fetchQuota()
            if let weekly = reading.weeklyRemainingPercent {
                codexWeeklyRemaining = weekly
                codexWeeklyTotal = 100
            }
            if let fiveHour = reading.fiveHourRemainingPercent {
                codexFiveHourRemaining = fiveHour
                codexFiveHourTotal = 100
            }
            if let date = reading.weeklyResetAt {
                UserDefaults.standard.set(date, forKey: codexWeeklyResetAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: codexWeeklyResetAtKey)
            }
            if let date = reading.fiveHourResetAt {
                UserDefaults.standard.set(date, forKey: codexFiveHourResetAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: codexFiveHourResetAtKey)
            }
            let now = Date()
            codexQuotaLastReadDate = now
            UserDefaults.standard.set(now, forKey: codexQuotaLastReadAtKey)
            codexQuotaAutoRefreshEnabled = true
            publishPixelDashboardSnapshotForCurrentState()
        } catch {
            codexQuotaLastReadError = error.localizedDescription
        }
    }

    private func normalizedBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func statusForErrorMessage(_ message: String) -> PixelDashboardStatus {
        let lowercased = message.lowercased()
        if lowercased.contains("401")
            || lowercased.contains("403")
            || lowercased.contains("unauthorized")
            || lowercased.contains("invalid api key")
            || lowercased.contains("凭证无效")
            || lowercased.contains("未授权") {
            return .unauthorized
        }
        return .error
    }

    private func sanitizedWidgetErrorMessage(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("key") || lowercased.contains("401") || lowercased.contains("403") {
            return "凭证无效或未授权"
        }
        if lowercased.contains("timeout") || lowercased.contains("timed out") {
            return "网络超时"
        }
        if lowercased.contains("404") || lowercased.contains("endpoint") {
            return "余额接口不可用"
        }
        return "Pixel API 刷新失败"
    }

    func startAutoRefresh(interval: TimeInterval = AppConstants.defaultRefreshInterval) {
        refreshTask?.cancel()
        guard interval > 0 else {
            refreshTask = nil
            return
        }
        refreshTask = Task {
            // Immediate first refresh
            await refreshAll()
            // Then periodic
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await refreshAll()
            }
        }
    }

    func handleMenuBarPopoverOpened() {
        guard followCCSwitchCurrentProvider else { return }
        Task { await syncWithCCSwitch(force: false) }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func startCCSwitchMonitor() {
        ccSwitchMonitorTask?.cancel()
        ccSwitchMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncWithCCSwitch(force: false)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopCCSwitchMonitor() {
        ccSwitchMonitorTask?.cancel()
        ccSwitchMonitorTask = nil
    }

    func detectCCSwitchDataSource() async {
        updateCCSwitchDataSourceDescription()
        await syncWithCCSwitch(force: true, refreshAfterSwitch: false)
    }

    func syncWithCCSwitch(force: Bool = true, refreshAfterSwitch: Bool = true) async {
        guard !isSyncingCCSwitch else { return }

        let source = ccSwitchService.locateCCSwitchDataSource()
        PixelDashboardSnapshotStore.saveSyncDiagnostic([
            "stage": "start",
            "source": source?.url.path ?? "nil",
            "mode": ccSwitchSyncMode.rawValue
        ])
        if let modifiedAt = source?.modifiedAt,
           !force,
           lastCCSwitchDataSourceModifiedAt == modifiedAt {
            PixelDashboardSnapshotStore.saveSyncDiagnostic([
                "stage": "skipped",
                "reason": "unchanged",
                "source": source?.url.path ?? "nil"
            ])
            return
        }

        isSyncingCCSwitch = true
        defer { isSyncingCCSwitch = false }

        do {
            guard source != nil else {
                throw CCSwitchIntegrationError.dataSourceNotFound
            }
            updateCCSwitchDataSourceDescription()
            let includeKey = ccSwitchSyncMode == .statusAndKey
            let snapshot = try await ccSwitchService.readActiveProvider(includeKey: includeKey)
            PixelDashboardSnapshotStore.saveSyncDiagnostic([
                "stage": "read_provider",
                "provider": snapshot.name,
                "baseURL": snapshot.baseURL ?? "nil",
                "keyStatus": snapshot.maskedKeyPreview == nil ? "none" : "detected"
            ])
            ccSwitchLastSnapshot = snapshot
            ccSwitchErrorMessage = nil
            ccSwitchStatusText = "已检测到 \(snapshot.name)"
            lastCCSwitchDataSourceModifiedAt = source?.modifiedAt

            let profile = try syncCCSwitchSnapshotToProfile(snapshot, includeKey: includeKey)
            PixelDashboardSnapshotStore.saveSyncDiagnostic([
                "stage": "profile_synced",
                "provider": profile.displayName,
                "providerID": profile.id,
                "baseURL": profile.baseURL,
                "hasCredential": hasCredential(for: profile.id) ? "true" : "false"
            ])
            if activeProviderID != profile.id {
                activeProviderID = profile.id
                saveActiveProviderSelection()
            }
            saveProviderProfiles()

            if refreshAfterSwitch {
                await refreshActiveProviderCore()
            } else if let cached = try? PixelDashboardSnapshotStore.loadProviderSnapshot(providerID: profile.id) {
                pixelDashboardSnapshot = cached.withProfile(profile).withStatus(.cached)
                publishWidgetSnapshot(pixelDashboardSnapshot!, saveProviderCopy: false)
            } else {
                let snapshot = emptySnapshot(
                    for: profile,
                    status: hasCredential(for: profile.id) ? .cached : .notConfigured,
                    errorMessage: hasCredential(for: profile.id) ? "已同步当前供应商，等待刷新" : "已同步当前供应商，请配置凭证"
                )
                pixelDashboardSnapshot = snapshot
                publishWidgetSnapshot(snapshot, saveProviderCopy: false)
            }
        } catch {
            ccSwitchErrorMessage = error.localizedDescription
            ccSwitchStatusText = error.localizedDescription
            PixelDashboardSnapshotStore.saveSyncDiagnostic([
                "stage": "error",
                "message": sanitizedWidgetErrorMessage(error.localizedDescription),
                "rawType": String(describing: type(of: error)),
                "errorName": ccSwitchErrorName(error),
                "source": source?.url.path ?? "nil"
            ])
            if refreshAfterSwitch {
                publishPixelDashboardSnapshotForCurrentState()
            }
        }
    }

    func clearCCSwitchSyncState() {
        followCCSwitchCurrentProvider = false
        ccSwitchLastSnapshot = nil
        ccSwitchErrorMessage = nil
        ccSwitchStatusText = "未检测"
        lastCCSwitchDataSourceModifiedAt = nil
    }

    func saveCCSwitchManualDataSource(url: URL) {
        do {
            try ccSwitchService.saveManualDataSourceBookmark(url: url)
            ccSwitchDataSourceSelectionMode = .manual
            updateCCSwitchDataSourceDescription()
        } catch {
            ccSwitchErrorMessage = "无法保存数据源位置"
        }
    }

    func clearCCSwitchManualDataSource() {
        ccSwitchService.clearManualDataSourceBookmark()
        ccSwitchDataSourceSelectionMode = .automatic
        updateCCSwitchDataSourceDescription()
    }

    private func syncCCSwitchSnapshotToProfile(
        _ snapshot: CCSwitchProviderSnapshot,
        includeKey: Bool
    ) throws -> APIProviderProfile {
        guard let baseURL = snapshot.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            if let existing = findProfile(for: snapshot) {
                if includeKey, let rawAPIKey = snapshot.rawAPIKey, !rawAPIKey.isEmpty {
                    try keychain.saveCredential(for: existing.id, value: rawAPIKey)
                }
                return existing
            }
            throw CCSwitchIntegrationError.missingBaseURL
        }

        let providerType = providerTypeForCCSwitch(snapshot: snapshot)
        if let existing = findProfile(for: snapshot) {
            let updated = try saveProviderProfile(
                id: existing.id,
                displayName: snapshot.name,
                baseURL: baseURL,
                providerType: providerType,
                credential: includeKey ? snapshot.rawAPIKey : nil,
                externalID: snapshot.externalID
            )
            return updated
        }

        if includeKey, snapshot.rawAPIKey?.isEmpty != false {
            throw CCSwitchIntegrationError.missingAPIKey
        }

        return try saveProviderProfile(
            id: nil,
            displayName: snapshot.name,
            baseURL: baseURL,
            providerType: providerType,
            credential: includeKey ? snapshot.rawAPIKey : nil,
            externalID: snapshot.externalID
        )
    }

    private func ccSwitchErrorName(_ error: Error) -> String {
        guard let error = error as? CCSwitchIntegrationError else {
            return String(describing: type(of: error))
        }
        switch error {
        case .dataSourceNotFound:
            return "dataSourceNotFound"
        case .dataSourceUnavailable:
            return "dataSourceUnavailable"
        case .unsupportedSchema:
            return "unsupportedSchema"
        case .activeProviderNotFound:
            return "activeProviderNotFound"
        case .missingBaseURL:
            return "missingBaseURL"
        case .missingAPIKey:
            return "missingAPIKey"
        case .databaseBusy:
            return "databaseBusy"
        }
    }

    private func findProfile(for snapshot: CCSwitchProviderSnapshot) -> APIProviderProfile? {
        if let externalID = snapshot.externalID,
           let profile = providerProfiles.first(where: { $0.externalID == externalID }) {
            return profile
        }

        let normalizedName = snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let snapshotBaseURL = snapshot.baseURL.map(normalizedBaseURL)
        if let snapshotBaseURL {
            return providerProfiles.first {
                $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
                    && normalizedBaseURL($0.baseURL) == snapshotBaseURL
            }
        }

        return providerProfiles.first {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
    }

    private func providerTypeForCCSwitch(snapshot: CCSwitchProviderSnapshot) -> APIProviderType {
        let joined = [
            snapshot.providerType,
            snapshot.baseURL,
            snapshot.name
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if joined.contains("deepseek") {
            return .deepSeekBalance
        }
        if joined.contains("one-api") || joined.contains("oneapi") {
            return .oneAPICompatible
        }
        return .newAPICompatible
    }

    private func updateCCSwitchDataSourceDescription() {
        ccSwitchService.dataSourceSelectionMode = ccSwitchDataSourceSelectionMode
        if let source = ccSwitchService.locateCCSwitchDataSource() {
            ccSwitchDataSourceDescription = "\(source.type)：\(source.url.path)"
        } else if ccSwitchDataSourceSelectionMode == .manual {
            ccSwitchDataSourceDescription = ccSwitchService.manualDataSourcePath ?? "未选择"
        } else {
            ccSwitchDataSourceDescription = "自动检测"
        }
    }

    /// Saves the API key to Keychain. Throws an error on Keychain failure so the UI can show the error.
    /// Returns true on success, false if the provider was not found.
    @discardableResult
    func updateAPIKey(for provider: AIProvider, key: String) throws -> Bool {
        guard let index = providers.firstIndex(where: { $0.provider == provider }) else { return false }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try keychain.save(key: provider.rawValue, value: trimmedKey)
        providers[index].apiKey = trimmedKey
        saveProviderConfigs()
        if provider == .pixel {
            if let defaultIndex = providerProfiles.firstIndex(where: { $0.id == defaultProviderProfileID }) {
                providerProfiles[defaultIndex].updatedAt = Date()
                try keychain.saveCredential(for: defaultProviderProfileID, value: trimmedKey)
                saveProviderProfiles()
            }
            publishPixelDashboardSnapshotForCurrentState()
        }
        return true
    }

    func credential(for profileID: String) -> String {
        (try? keychain.readCredential(for: profileID)) ?? ""
    }

    func hasCredential(for profileID: String) -> Bool {
        !credential(for: profileID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func saveProviderProfile(
        id: String?,
        displayName: String,
        baseURL: String,
        providerType: APIProviderType,
        credential: String?,
        externalID: String? = nil
    ) throws -> APIProviderProfile {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = normalizedBaseURL(baseURL)
        let finalName = trimmedName.isEmpty ? "未命名配置" : trimmedName
        let finalBaseURL = trimmedBaseURL.isEmpty ? AppConstants.Pixel.baseURL : trimmedBaseURL
        let now = Date()

        var savedProfile: APIProviderProfile
        if let id, let index = providerProfiles.firstIndex(where: { $0.id == id }) {
            providerProfiles[index].displayName = finalName
            providerProfiles[index].baseURL = finalBaseURL
            providerProfiles[index].providerType = providerType
            providerProfiles[index].isEnabled = true
            providerProfiles[index].updatedAt = now
            if let externalID {
                providerProfiles[index].externalID = externalID
            }
            savedProfile = providerProfiles[index]
        } else {
            let profile = APIProviderProfile(
                id: makeUniqueProfileID(from: finalName),
                displayName: finalName,
                baseURL: finalBaseURL,
                providerType: providerType,
                isEnabled: true,
                sortOrder: (providerProfiles.map(\.sortOrder).max() ?? -1) + 1,
                createdAt: now,
                updatedAt: now,
                externalID: externalID
            )
            providerProfiles.append(profile)
            savedProfile = profile
        }

        if let credential {
            let trimmedCredential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCredential.isEmpty {
                try keychain.saveCredential(for: savedProfile.id, value: trimmedCredential)
            }
        }

        saveProviderProfiles()
        return savedProfile
    }

    func deleteProviderProfile(id: String) {
        guard providerProfiles.count > 1 else { return }
        let wasActive = activeProviderID == id
        providerProfiles.removeAll { $0.id == id }
        try? keychain.deleteCredential(for: id)
        try? PixelDashboardSnapshotStore.deleteProviderSnapshot(providerID: id)
        saveProviderProfiles()

        if wasActive,
           let next = sortedProviderProfiles.first(where: { $0.isEnabled }) {
            activeProviderID = next.id
            saveActiveProviderSelection()
            Task { await refreshAll() }
        }
    }

    func clearProviderCredential(id: String) {
        try? keychain.deleteCredential(for: id)
        try? PixelDashboardSnapshotStore.deleteProviderSnapshot(providerID: id)
        if activeProviderID == id {
            guard let profile = activeProviderProfile else { return }
            let snapshot = emptySnapshot(
                for: profile,
                status: .notConfigured,
                errorMessage: "请先配置当前配置档凭证"
            )
            pixelDashboardSnapshot = snapshot
            balances[.pixel] = nil
            errorMessages[.pixel] = nil
            publishWidgetSnapshot(snapshot, saveProviderCopy: false)
        }
    }

    func setActiveProvider(profileID: String) async {
        guard providerProfiles.contains(where: { $0.id == profileID && $0.isEnabled }) else { return }
        activeProviderID = profileID
        saveActiveProviderSelection()

        if let cached = try? PixelDashboardSnapshotStore.loadProviderSnapshot(providerID: profileID) {
            pixelDashboardSnapshot = cached.withStatus(.cached)
            publishWidgetSnapshot(pixelDashboardSnapshot!, saveProviderCopy: false)
        } else {
            publishPixelDashboardSnapshotForCurrentState()
        }

        if hasCredential(for: profileID) {
            await refreshAll()
        }
    }

    func testProviderProfile(
        id: String?,
        displayName: String,
        baseURL: String,
        providerType: APIProviderType,
        credential: String
    ) async throws -> PixelDashboardSnapshot {
        let profile = APIProviderProfile(
            id: id ?? "test_profile",
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "测试配置" : displayName,
            baseURL: normalizedBaseURL(baseURL),
            providerType: providerType,
            isEnabled: true,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
        return try await fetchSnapshot(for: profile, credential: credential).withProfile(profile)
    }

    func profileStatusText(for profile: APIProviderProfile) -> String {
        if profile.id == activeProviderID {
            return "当前"
        }
        return hasCredential(for: profile.id) ? "可用" : "未配置"
    }

    private func makeUniqueProfileID(from displayName: String) -> String {
        let lowercased = displayName.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let asciiScalars = lowercased.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let base = String(asciiScalars).split(separator: "_").joined(separator: "_")
        let normalizedBase = base.isEmpty ? "provider" : String(base.prefix(32))
        var candidate = normalizedBase
        var suffix = 2
        while providerProfiles.contains(where: { $0.id == candidate }) {
            candidate = "\(normalizedBase)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func shortenedMenuName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Pixel" }
        if trimmed == "Pixel API" { return "Pixel" }
        if trimmed.count <= 10 { return trimmed }
        return String(trimmed.prefix(10))
    }

    private func saveProviderConfigs() {
        try? cache.saveConfig(providers)
    }

    deinit {
        refreshTask?.cancel()
    }
}

private struct CodexQuotaReading {
    let weeklyRemainingPercent: Double?
    let weeklyResetAt: Date?
    let fiveHourRemainingPercent: Double?
    let fiveHourResetAt: Date?
}

private struct CodexQuotaCLIReader {
    func fetchQuota(timeout: TimeInterval = 8) async throws -> CodexQuotaReading {
        try await Task.detached(priority: .utility) {
            try self.fetchQuotaSynchronously(timeout: timeout)
        }.value
    }

    private func fetchQuotaSynchronously(timeout: TimeInterval) throws -> CodexQuotaReading {
        let process = Process()
        if let codexURL = codexExecutableURL() {
            process.executableURL = codexURL
            process.arguments = ["app-server"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "app-server"]
        }

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        let lock = NSLock()
        var buffer = Data()
        var capturedError = Data()
        var result: Result<CodexQuotaReading, Error>?
        let semaphore = DispatchSemaphore(value: 0)

        func finish(_ value: Result<CodexQuotaReading, Error>) {
            lock.lock()
            if result == nil {
                result = value
                semaphore.signal()
            }
            lock.unlock()
        }

        func send(_ object: [String: Any]) {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([0x0A]))
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            lock.lock()
            buffer.append(data)
            var completeLines: [Data] = []
            while let newline = buffer.firstRange(of: Data([0x0A])) {
                let line = buffer[..<newline.lowerBound]
                if !line.isEmpty {
                    completeLines.append(Data(line))
                }
                buffer.removeSubrange(..<newline.upperBound)
            }
            lock.unlock()

            for line in completeLines {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    continue
                }
                if object["id"] as? Int == 1 {
                    send(["method": "initialized"])
                    send(["method": "account/rateLimits/read", "id": 2])
                } else if object["id"] as? Int == 2 {
                    do {
                        finish(.success(try parseQuotaResponse(object)))
                    } catch {
                        finish(.failure(error))
                    }
                }
            }
        }

        error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            capturedError.append(data)
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw CodexQuotaCLIError.launchFailed
        }

        send([
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": "RelayBar",
                    "version": "1.0"
                ],
                "capabilities": [:]
            ]
        ])

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }

        if waitResult == .timedOut {
            throw CodexQuotaCLIError.timeout
        }

        lock.lock()
        let finalResult = result
        let stderrText = String(data: capturedError, encoding: .utf8)
        lock.unlock()

        if let finalResult {
            return try finalResult.get()
        }
        if let stderrText, stderrText.localizedCaseInsensitiveContains("login") {
            throw CodexQuotaCLIError.notLoggedIn
        }
        throw CodexQuotaCLIError.invalidResponse
    }

    private func parseQuotaResponse(_ response: [String: Any]) throws -> CodexQuotaReading {
        guard response["error"] == nil,
              let result = response["result"] as? [String: Any] else {
            throw CodexQuotaCLIError.invalidResponse
        }

        let rateLimits = (result["rateLimits"] as? [String: Any])
            ?? ((result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any])
        guard let rateLimits else {
            throw CodexQuotaCLIError.invalidResponse
        }

        let windows = [
            rateLimits["primary"] as? [String: Any],
            rateLimits["secondary"] as? [String: Any]
        ].compactMap { $0 }.map(parseWindow)

        let fiveHour = windows.first { $0.durationMinutes == 300 } ?? windows.first
        let weekly = windows.first { $0.durationMinutes >= 10_080 } ?? windows.dropFirst().first

        return CodexQuotaReading(
            weeklyRemainingPercent: weekly?.remainingPercent,
            weeklyResetAt: weekly?.resetAt,
            fiveHourRemainingPercent: fiveHour?.remainingPercent,
            fiveHourResetAt: fiveHour?.resetAt
        )
    }

    private func parseWindow(_ object: [String: Any]) -> CodexQuotaWindow {
        let used = numericValue(object["usedPercent"]) ?? 0
        let duration = Int(numericValue(object["windowDurationMins"]) ?? 0)
        let resetSeconds = numericValue(object["resetsAt"])
        return CodexQuotaWindow(
            remainingPercent: max(0, min(100, 100 - used)),
            durationMinutes: duration,
            resetAt: resetSeconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func numericValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func codexExecutableURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(NSHomeDirectory())/Applications/Codex.app/Contents/Resources/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

private struct CodexQuotaWindow {
    let remainingPercent: Double
    let durationMinutes: Int
    let resetAt: Date?
}

private enum CodexQuotaCLIError: LocalizedError {
    case launchFailed
    case timeout
    case notLoggedIn
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "未找到 Codex CLI，或无法启动 codex app-server。"
        case .timeout:
            return "读取 Codex 额度超时。"
        case .notLoggedIn:
            return "Codex CLI 尚未登录。"
        case .invalidResponse:
            return "Codex 额度返回格式无法识别。"
        }
    }
}
