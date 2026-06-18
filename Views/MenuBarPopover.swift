// Views/MenuBarPopover.swift
import AppKit
import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        let snapshot = dashboardVM.pixelDashboardSnapshot

        VStack(spacing: 12) {
            popoverHeader
            if dashboardVM.followCCSwitchCurrentProvider {
                ccSwitchFollowBanner
            }
            profilePicker
            VStack(alignment: .leading, spacing: 8) {
                PopoverMetricRow(label: "余额", value: dashboardVM.formatPixelMoney(snapshot?.balance, currency: snapshot?.balanceCurrency ?? "USD"), color: statusColor)
                PopoverMetricRow(label: "今日消费", value: dashboardVM.formatPixelTodayCost(snapshot), color: .purple)
                PopoverMetricRow(label: "今日 Token", value: dashboardVM.formatPixelTokens(snapshot?.todayTokenTotal), color: .orange)
                PopoverMetricRow(label: "累计 Token", value: dashboardVM.formatPixelTokens(snapshot?.totalTokenTotal), color: .blue)
                if let quota = snapshot?.codexQuota {
                    Divider()
                    PopoverMetricRow(
                        label: "Codex 周额度",
                        value: dashboardVM.formatCodexQuota(remaining: quota.weeklyRemaining, total: quota.weeklyTotal, isPercentBased: quota.isPercentBased == true),
                        color: .teal
                    )
                    PopoverMetricRow(
                        label: "Codex 5h",
                        value: dashboardVM.formatCodexQuota(remaining: quota.fiveHourRemaining, total: quota.fiveHourTotal, isPercentBased: quota.isPercentBased == true),
                        color: .indigo
                    )
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text("最后刷新  \(dashboardVM.formatPixelTime(snapshot?.updatedAt))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button {
                    Task { await dashboardVM.refreshAll() }
                } label: {
                    if dashboardVM.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.58)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .disabled(dashboardVM.isRefreshing)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)

            if !dashboardVM.isActiveProviderConfigured {
                Text("请先配置当前配置档的访问凭证")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = snapshot?.errorMessage ?? dashboardVM.errorMessages[.pixel], !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(statusColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(name: .relayBarShowSettingsWindow, object: nil)
                } label: {
                    Label("打开设置", systemImage: "gearshape")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    NotificationCenter.default.post(name: .relayBarQuit, object: nil)
                } label: {
                    Label("退出", systemImage: "power")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            dashboardVM.handleMenuBarPopoverOpened()
        }
    }

    private var popoverHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(dashboardVM.activeProviderDisplayName)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            statusChip
        }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("当前配置")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { dashboardVM.activeProviderID },
                    set: { newValue in
                        Task { await dashboardVM.setActiveProvider(profileID: newValue) }
                    }
                )) {
                    ForEach(dashboardVM.sortedProviderProfiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                Spacer(minLength: 0)
            }

            if dashboardVM.followCCSwitchCurrentProvider {
                Text("当前由 CC Switch 控制")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var ccSwitchFollowBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("跟随 CC Switch：\(dashboardVM.ccSwitchLastSnapshot?.name ?? dashboardVM.activeProviderDisplayName)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(dashboardVM.ccSwitchStatusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button("暂停") {
                dashboardVM.followCCSwitchCurrentProvider = false
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch dashboardVM.pixelStatusColorName {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .secondary
        }
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(conciseStatusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.14), in: Capsule())
    }

    private var conciseStatusText: String {
        let text = dashboardVM.pixelStatusText
        if ["正常", "缓存", "未配置", "刷新中"].contains(text) {
            return text
        }
        return dashboardVM.pixelStatusColorName == "red" ? "错误" : text
    }

}

struct PopoverMetricRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
