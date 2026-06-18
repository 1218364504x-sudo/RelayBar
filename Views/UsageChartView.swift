// Views/UsageChartView.swift
import SwiftUI
import Charts

struct UsageChartView: View {
    let snapshot: PixelDashboardSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let snapshot {
                    metricGrid(snapshot)
                    codexQuotaSummary(snapshot)
                    tokenBreakdownChart(snapshot)
                    costSummary(snapshot)
                } else {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前使用概览")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("基于当前供应商最近一次刷新快照。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "暂无使用数据",
            systemImage: "chart.bar",
            description: Text("请先返回设置页或菜单栏刷新一次当前配置。")
        )
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func metricGrid(_ snapshot: PixelDashboardSnapshot) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            metricCard("余额", formatMoney(snapshot.balance, currency: snapshot.balanceCurrency), color: statusColor(snapshot))
            metricCard("今日消费", formatTodayCost(snapshot), color: .purple)
            metricCard("今日 Token", formatTokens(snapshot.todayTokenTotal), color: .orange)
            metricCard("累计 Token", formatTokens(snapshot.totalTokenTotal), color: .blue)
        }
    }

    private func metricCard(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func codexQuotaSummary(_ snapshot: PixelDashboardSnapshot) -> some View {
        if let quota = snapshot.codexQuota {
            GroupBox("Codex 额度") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    quotaCard(
                        title: "周额度",
                        value: formatQuota(remaining: quota.weeklyRemaining, total: quota.weeklyTotal, isPercentBased: quota.isPercentBased == true),
                        percent: formatQuotaPercent(remaining: quota.weeklyRemaining, total: quota.weeklyTotal),
                        color: .teal
                    )
                    quotaCard(
                        title: "5h 额度",
                        value: formatQuota(remaining: quota.fiveHourRemaining, total: quota.fiveHourTotal, isPercentBased: quota.isPercentBased == true),
                        percent: formatQuotaPercent(remaining: quota.fiveHourRemaining, total: quota.fiveHourTotal),
                        color: .indigo
                    )
                }
            }
        }
    }

    private func quotaCard(title: String, value: String, percent: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tokenBreakdownChart(_ snapshot: PixelDashboardSnapshot) -> some View {
        GroupBox("Token 分布") {
            let data = tokenChartData(snapshot)
            if data.allSatisfy({ $0.value <= 0 }) {
                Text("暂无 Token 分布数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("类型", item.label),
                        y: .value("Token", item.value)
                    )
                    .foregroundStyle(item.color)
                    .annotation(position: .top) {
                        Text(formatTokens(item.value))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatTokens(doubleValue))
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func costSummary(_ snapshot: PixelDashboardSnapshot) -> some View {
        GroupBox("刷新信息") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("供应商", snapshot.providerName)
                infoRow("Base URL", snapshot.baseURLHost ?? URL(string: snapshot.baseURL)?.host ?? snapshot.baseURL)
                infoRow("状态", statusText(snapshot))
                infoRow("最后刷新", formatTime(snapshot.updatedAt))
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }

    private struct TokenChartItem: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    private func tokenChartData(_ snapshot: PixelDashboardSnapshot) -> [TokenChartItem] {
        [
            TokenChartItem(label: "今日输入", value: snapshot.todayInputTokens ?? 0, color: .orange),
            TokenChartItem(label: "今日输出", value: snapshot.todayOutputTokens ?? 0, color: .pink),
            TokenChartItem(label: "累计输入", value: snapshot.totalInputTokens ?? 0, color: .blue),
            TokenChartItem(label: "累计输出", value: snapshot.totalOutputTokens ?? 0, color: .teal)
        ]
    }

    private func statusColor(_ snapshot: PixelDashboardSnapshot) -> Color {
        switch snapshot.status {
        case .normal:
            return .green
        case .lowBalance:
            return .orange
        case .cached, .notConfigured:
            return .secondary
        case .error, .unauthorized:
            return .red
        }
    }

    private func statusText(_ snapshot: PixelDashboardSnapshot) -> String {
        switch snapshot.status {
        case .normal:
            return "正常"
        case .lowBalance:
            return "余额低"
        case .cached:
            return "缓存"
        case .error:
            return "错误"
        case .unauthorized:
            return "未授权"
        case .notConfigured:
            return "未配置"
        }
    }

    private func formatMoney(_ value: Double?, currency: String?) -> String {
        guard let value else { return "--" }
        let symbol = (currency ?? "USD").uppercased() == "USD" ? "$" : ""
        if value > 0, value < 1 {
            return "\(symbol)\(String(format: "%.4f", value))"
        }
        return "\(symbol)\(String(format: "%.2f", value))"
    }

    private func formatTodayCost(_ snapshot: PixelDashboardSnapshot) -> String {
        let primary = formatMoney(snapshot.todayCostPrimary, currency: snapshot.balanceCurrency)
        guard snapshot.todayCostSecondary != nil else {
            return primary
        }
        let secondary = formatMoney(snapshot.todayCostSecondary, currency: snapshot.balanceCurrency)
        return "\(primary) / \(secondary)"
    }

    private func formatTokens(_ value: Double?) -> String {
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

    private func formatQuota(remaining: Double?, total: Double?, isPercentBased: Bool = false) -> String {
        guard let remaining else { return "--" }
        let safeRemaining = max(0, remaining)
        if isPercentBased {
            return String(format: "%.0f%%", min(100, safeRemaining))
        }
        guard let total, total > 0 else {
            return String(format: "%.0f", safeRemaining)
        }
        return "\(String(format: "%.0f", safeRemaining)) / \(String(format: "%.0f", total))"
    }

    private func formatQuotaPercent(remaining: Double?, total: Double?) -> String {
        guard let remaining, let total, total > 0 else { return "--" }
        let percent = max(0, min(1, remaining / total)) * 100
        return String(format: "%.0f%%", percent)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }
}
