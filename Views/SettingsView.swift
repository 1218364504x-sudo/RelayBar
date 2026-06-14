// Views/SettingsView.swift
import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @StateObject private var settingsVM = SettingsViewModel()
    @State private var apiKeyInputs: [AIProvider: String] = [:]
    @State private var testingProvider: AIProvider?
    @State private var testResults: [AIProvider: String] = [:]
    @State private var editingProfileID: String?
    @State private var profileName = ""
    @State private var profileBaseURL = AppConstants.Pixel.baseURL
    @State private var profileType: APIProviderType = .pixelDashboard
    @State private var profileCredential = ""
    @State private var testingProfileID: String?
    @State private var profileTestResult: String?
    @State private var showLegacyAccountSettings = false

    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    profileSection
                    CCSwitchSettingsSection(selectDataSource: selectCCSwitchDataSource)
                        .environmentObject(dashboardVM)
                    legacyAccountSettingsSection
                    connectionSection
                    displaySection
                    refreshSection
                    aboutSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }

            UsageChartView(
                snapshot: dashboardVM.pixelDashboardSnapshot
            )
            .tabItem { Label("图表", systemImage: "chart.bar") }
            .padding()
        }
        .frame(width: 760, height: 760)
    }

    private var headerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("RelayBar 设置")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("多配置档中转站余额、今日消费和 Token 使用量显示设置。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var profileSection: some View {
        GroupBox("配置档管理") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(dashboardVM.sortedProviderProfiles) { profile in
                    providerProfileRow(profile)
                    Divider()
                }

                profileEditor
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func providerProfileRow(_ profile: APIProviderProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.displayName)
                            .font(.headline)
                        if profile.id == dashboardVM.activeProviderID {
                            Text("当前")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(profile.baseURLHost)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(profile.providerType.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(dashboardVM.profileStatusText(for: profile))
                    .font(.caption)
                    .foregroundColor(profile.id == dashboardVM.activeProviderID ? .green : .secondary)
            }

            HStack {
                Button("设为当前") {
                    Task { await dashboardVM.setActiveProvider(profileID: profile.id) }
                }
                .disabled(profile.id == dashboardVM.activeProviderID)

                Button("编辑") {
                    beginEditing(profile)
                }

                Button("测试连接") {
                    testProfile(profile)
                }
                .disabled(testingProfileID != nil || !dashboardVM.hasCredential(for: profile.id))

                Button("清除凭证") {
                    dashboardVM.clearProviderCredential(id: profile.id)
                    if editingProfileID == profile.id {
                        profileCredential = ""
                    }
                }
                .disabled(!dashboardVM.hasCredential(for: profile.id))

                Button("删除", role: .destructive) {
                    dashboardVM.deleteProviderProfile(id: profile.id)
                }
                .disabled(dashboardVM.providerProfiles.count <= 1)

                if testingProfileID == profile.id {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(editingProfileID == nil ? "新增配置档" : "编辑配置档")
                .font(.subheadline.weight(.semibold))

            TextField("配置名称，例如 Pixel Plus / Pixel Pro", text: $profileName)
                .textFieldStyle(.roundedBorder)

            Picker("Provider 类型", selection: $profileType) {
                ForEach(APIProviderType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            TextField("Base URL", text: $profileBaseURL)
                .textFieldStyle(.roundedBorder)

            SecureField("API Key / 访问凭证（留空则保留原凭证）", text: $profileCredential)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(editingProfileID == nil ? "保存配置档" : "保存修改") {
                    saveProfileForm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("测试连接") {
                    testProfileForm()
                }
                .disabled(profileCredential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testingProfileID != nil)

                Button("清空表单") {
                    resetProfileForm()
                }

                if testingProfileID == "form" {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if let profileTestResult {
                Text(profileTestResult)
                    .font(.caption)
                    .foregroundColor(profileTestResult.contains("成功") ? .green : .red)
            }

            Text("每个配置档的凭证独立保存在系统钥匙串；配置列表和 Widget 缓存不会保存凭证。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var legacyAccountSettingsSection: some View {
        GroupBox("高级账户配置") {
            DisclosureGroup(isExpanded: $showLegacyAccountSettings) {
                VStack(alignment: .leading, spacing: 12) {
                    if let saveError = dashboardVM.saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    ForEach(AIProvider.allCases) { provider in
                        legacyProviderRow(provider)
                        Divider()
                    }

                    Text("凭证已安全保存在系统钥匙串中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("旧版 Provider 凭证")
                        .font(.subheadline)
                    Text("通常只使用上方配置档管理；这里保留给 DeepSeek / OpenAI / Anthropic 旧入口。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func legacyProviderRow(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.rawValue)
                    .font(.headline)
                if provider == .pixel {
                    Text("Primary")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if provider == .pixel,
               let config = dashboardVM.providers.first(where: { $0.provider == .pixel }) {
                Text("Base URL  \(config.baseURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SecureField(provider == .pixel ? "登录凭证 / API Key" : "API Key", text: Binding(
                get: { apiKeyInputs[provider] ?? "" },
                set: {
                    apiKeyInputs[provider] = $0
                    testResults[provider] = nil
                }
            ))
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)

            Text(dashboardVM.providers.first(where: { $0.provider == provider })?.apiKey.isEmpty == false ? "已保存凭证；输入新值后可替换。" : "未保存凭证。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("保存") {
                    saveAPIKey(provider: provider)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if testingProvider == provider {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 60)
                } else {
                    Button("测试连接") {
                        testConnection(provider: provider)
                    }
                    .controlSize(.regular)
                    .disabled(apiKeyInputs[provider]?.isEmpty ?? true)
                }

                if let result = testResults[provider] {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(successResultMessages.contains(result) ? .green : .red)
                }

                Button("清除凭证") {
                    clearAPIKey(provider: provider)
                }
                .controlSize(.regular)
                .disabled(dashboardVM.providers.first(where: { $0.provider == provider })?.apiKey.isEmpty ?? true)
            }
        }
    }

    private var connectionSection: some View {
        GroupBox("连接状态") {
            let snapshot = dashboardVM.pixelDashboardSnapshot
            HStack {
                Label(dashboardVM.pixelStatusText, systemImage: "circle.fill")
                    .foregroundStyle(statusColor)
                Spacer()
                Text("最后刷新 \(dashboardVM.formatPixelTime(snapshot?.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displaySection: some View {
        GroupBox("显示设置") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { dashboardVM.showFloatingWindow },
                    set: { dashboardVM.showFloatingWindow = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("悬浮窗")
                            .font(.subheadline)
                        Text("小尺寸置顶显示余额和使用概览")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { dashboardVM.showBalanceInMenuBar },
                    set: { dashboardVM.showBalanceInMenuBar = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("菜单栏显示余额")
                            .font(.subheadline)
                        Text("关闭后菜单栏只显示当前配置和状态。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                TextField("余额提醒阈值", value: Binding(
                    get: { dashboardVM.lowBalanceThreshold },
                    set: { dashboardVM.lowBalanceThreshold = max(0, $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

                Picker(selection: Binding(
                    get: { dashboardVM.preferredCurrency },
                    set: { dashboardVM.preferredCurrency = $0 }
                )) {
                    Text("CNY ¥").tag(DashboardViewModel.CurrencyType.cny)
                    Text("USD $").tag(DashboardViewModel.CurrencyType.usd)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("显示模式")
                            .font(.subheadline)
                        Text("余额可按 CNY 或 USD 显示")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var refreshSection: some View {
        GroupBox("刷新设置") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("刷新间隔", selection: $settingsVM.refreshInterval) {
                    Text("1 分钟").tag(TimeInterval(60))
                    Text("5 分钟").tag(TimeInterval(300))
                    Text("15 分钟").tag(TimeInterval(900))
                    Text("30 分钟").tag(TimeInterval(1800))
                    Text("手动").tag(TimeInterval(0))
                }
                .pickerStyle(.menu)
                .onChange(of: settingsVM.refreshInterval) { _, _ in
                    settingsVM.saveRefreshInterval()
                }

                Text(settingsVM.refreshInterval == 0 ? "仅手动刷新" : "每 \(Int(settingsVM.refreshInterval / 60)) 分钟自动刷新")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            settingsVM.onIntervalChange = { newInterval in
                dashboardVM.startAutoRefresh(interval: newInterval)
            }
        }
    }

    private var aboutSection: some View {
        GroupBox("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func saveAPIKey(provider: AIProvider) {
        let key = apiKeyInputs[provider] ?? ""
        do {
            let saved = try dashboardVM.updateAPIKey(for: provider, key: key)
            if saved {
                dashboardVM.saveError = nil
                testResults[provider] = "Saved"
                apiKeyInputs[provider] = ""
            }
        } catch {
            testResults[provider] = "Save failed"
            dashboardVM.saveError = "Failed to save API key to Keychain: \(error.localizedDescription)"
        }
    }

    private var successResultMessages: Set<String> {
        ["Saved", "Success", "Cleared", "连接成功，已获取账户余额"]
    }

    private var statusColor: Color {
        switch dashboardVM.pixelStatusColorName {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .secondary
        }
    }

    private func clearAPIKey(provider: AIProvider) {
        apiKeyInputs[provider] = ""
        do {
            let saved = try dashboardVM.updateAPIKey(for: provider, key: "")
            if saved {
                dashboardVM.saveError = nil
                testResults[provider] = "Cleared"
                dashboardVM.errorMessages[provider] = nil
            }
        } catch {
            testResults[provider] = "Clear failed"
            dashboardVM.saveError = "Failed to clear API key from Keychain: \(error.localizedDescription)"
        }
    }

    private func beginEditing(_ profile: APIProviderProfile) {
        editingProfileID = profile.id
        profileName = profile.displayName
        profileBaseURL = profile.baseURL
        profileType = profile.providerType
        profileCredential = ""
        profileTestResult = nil
    }

    private func resetProfileForm() {
        editingProfileID = nil
        profileName = ""
        profileBaseURL = AppConstants.Pixel.baseURL
        profileType = .pixelDashboard
        profileCredential = ""
        profileTestResult = nil
    }

    private func selectCCSwitchDataSource() {
        let panel = NSOpenPanel()
        panel.title = "选择 CC Switch 数据源"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            dashboardVM.saveCCSwitchManualDataSource(url: url)
            Task { await dashboardVM.detectCCSwitchDataSource() }
        }
    }

    private func saveProfileForm() {
        do {
            let profile = try dashboardVM.saveProviderProfile(
                id: editingProfileID,
                displayName: profileName,
                baseURL: profileBaseURL,
                providerType: profileType,
                credential: profileCredential
            )
            profileTestResult = "已保存 \(profile.displayName)"
            editingProfileID = profile.id
            profileCredential = ""
            Task {
                await dashboardVM.setActiveProvider(profileID: profile.id)
            }
        } catch {
            profileTestResult = "保存失败：\(error.localizedDescription)"
        }
    }

    private func testProfileForm() {
        testingProfileID = "form"
        profileTestResult = nil
        let credential = profileCredential
        Task {
            defer { testingProfileID = nil }
            do {
                let snapshot = try await dashboardVM.testProviderProfile(
                    id: editingProfileID,
                    displayName: profileName,
                    baseURL: profileBaseURL,
                    providerType: profileType,
                    credential: credential
                )
                profileTestResult = "连接成功，余额 \(dashboardVM.formatPixelMoney(snapshot.balance, currency: snapshot.balanceCurrency ?? "USD"))"
            } catch {
                profileTestResult = "连接失败，请检查凭证或 Base URL"
            }
        }
    }

    private func testProfile(_ profile: APIProviderProfile) {
        testingProfileID = profile.id
        profileTestResult = nil
        let credential = dashboardVM.credential(for: profile.id)
        Task {
            defer { testingProfileID = nil }
            do {
                _ = try await dashboardVM.testProviderProfile(
                    id: profile.id,
                    displayName: profile.displayName,
                    baseURL: profile.baseURL,
                    providerType: profile.providerType,
                    credential: credential
                )
                if profile.id == dashboardVM.activeProviderID {
                    await dashboardVM.refreshAll()
                }
                profileTestResult = "\(profile.displayName) 连接成功"
            } catch {
                profileTestResult = "\(profile.displayName) 连接失败"
            }
        }
    }

    private func testConnection(provider: AIProvider) {
        testingProvider = provider
        testResults[provider] = nil
        dashboardVM.errorMessages[provider] = nil

        Task {
            defer { testingProvider = nil }

            let key = apiKeyInputs[provider] ?? ""
            guard !key.isEmpty else {
                testResults[provider] = "请先输入凭证"
                return
            }

            let config = ProviderConfig(provider: provider, apiKey: key)
            let service = UsageServiceFactory.makeService(for: config)

            do {
                if provider == .pixel,
                   let pixelService = service as? PixelUsageService {
                    _ = try await pixelService.fetchDashboardSnapshot(lowBalanceThreshold: dashboardVM.lowBalanceThreshold)
                    testResults[provider] = "连接成功，已获取账户余额"
                    if dashboardVM.providers.first(where: { $0.provider == .pixel })?.apiKey == key.trimmingCharacters(in: .whitespacesAndNewlines) {
                        await dashboardVM.refreshAll()
                    }
                } else {
                    try await service.verifyConnection()
                    testResults[provider] = "Success"
                }
                dashboardVM.errorMessages[provider] = nil
            } catch {
                let msg = error.localizedDescription
                testResults[provider] = provider == .pixel ? "连接失败，请检查登录状态、凭证或 Base URL" : msg
                dashboardVM.errorMessages[provider] = "Connection failed: \(msg)"
            }
        }
    }
}

private struct CCSwitchSettingsSection: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    let selectDataSource: () -> Void

    var body: some View {
        GroupBox("CC Switch 同步") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { dashboardVM.followCCSwitchCurrentProvider },
                    set: { dashboardVM.followCCSwitchCurrentProvider = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("跟随 CC Switch 当前供应商")
                            .font(.subheadline)
                        Text("关闭时继续使用上方手动选择的配置档。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Picker("同步模式", selection: Binding(
                    get: { dashboardVM.ccSwitchSyncMode },
                    set: { dashboardVM.ccSwitchSyncMode = $0 }
                )) {
                    ForEach(CCSwitchSyncMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(syncModeHint)
                    .font(.caption)
                    .foregroundColor(dashboardVM.ccSwitchSyncMode == .statusAndKey ? .orange : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("数据源", selection: Binding(
                    get: { dashboardVM.ccSwitchDataSourceSelectionMode },
                    set: { dashboardVM.ccSwitchDataSourceSelectionMode = $0 }
                )) {
                    ForEach(CCSwitchDataSourceSelectionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    SettingsInfoRow(label: "数据源", value: dashboardVM.ccSwitchDataSourceDescription)
                    SettingsInfoRow(label: "供应商", value: dashboardVM.ccSwitchLastSnapshot?.name ?? "--")
                    SettingsInfoRow(label: "Base URL", value: dashboardVM.ccSwitchLastSnapshot?.baseURL ?? "--")
                    SettingsInfoRow(label: "Key 状态", value: keyStatus)
                    SettingsInfoRow(label: "状态", value: statusText)
                }
                .font(.caption)

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("重新检测") {
                        Task { await dashboardVM.detectCCSwitchDataSource() }
                    }
                    .disabled(dashboardVM.isSyncingCCSwitch)

                    Button("立即同步") {
                        Task { await dashboardVM.syncWithCCSwitch(force: true) }
                    }
                    .disabled(dashboardVM.isSyncingCCSwitch)

                    Button("选择数据源") {
                        selectDataSource()
                    }

                    Button("清除同步状态") {
                        dashboardVM.clearCCSwitchSyncState()
                    }
                }
                .controlSize(.small)

                if dashboardVM.isSyncingCCSwitch {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("正在读取 CC Switch 当前供应商")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Widget 仍然只读取 App 写入的当前缓存，不读取 CC Switch、钥匙串或网络。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var syncModeHint: String {
        if dashboardVM.ccSwitchSyncMode == .statusAndKey {
            return "将读取 CC Switch 本地配置中的当前供应商和 API Key，并把 Key 安全保存到系统钥匙串。"
        }
        return "推荐模式：只读取当前供应商状态，并使用本 App 已保存到钥匙串的凭证。"
    }

    private var keyStatus: String {
        if dashboardVM.ccSwitchSyncMode == .statusOnly {
            return "不读取"
        }
        return dashboardVM.ccSwitchLastSnapshot?.maskedKeyPreview == nil ? "未检测" : "已检测"
    }

    private var statusText: String {
        if dashboardVM.ccSwitchStatusText.contains("Keychain error") {
            return "钥匙串保存失败"
        }
        return dashboardVM.ccSwitchStatusText
    }

    private var errorText: String? {
        guard let error = dashboardVM.ccSwitchErrorMessage, !error.isEmpty else { return nil }
        if error.contains("Keychain error") {
            return "钥匙串保存失败，请重新同步。"
        }
        return error
    }
}

private struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}
