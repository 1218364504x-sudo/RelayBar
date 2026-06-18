import AppKit
import SwiftUI
import WidgetKit

struct PixelAPIWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PixelDashboardSnapshot?
    let isStale: Bool
    let diagnosticMessage: String?
}

struct PixelAPIWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PixelAPIWidgetEntry {
        var snapshot = PixelDashboardSnapshot(
            providerName: "Pixel API",
            baseURL: "",
            balance: 44.69,
            balanceCurrency: "USD",
            todayCostPrimary: 0.2453,
            todayCostSecondary: 1.2267,
            todayTokenTotal: 700_500,
            todayInputTokens: 103_800,
            todayOutputTokens: 13_900,
            totalTokenTotal: 422_100_000,
            totalInputTokens: 43_000_000,
            totalOutputTokens: 3_400_000,
            updatedAt: Date(),
            status: .normal,
            errorMessage: nil
        )
        snapshot.codexQuota = CodexQuotaSnapshot(
            weeklyRemaining: 72,
            weeklyTotal: 100,
            weeklyResetAt: Date().addingTimeInterval(60 * 60 * 24 * 2),
            fiveHourRemaining: 18,
            fiveHourTotal: 25,
            fiveHourResetAt: Date().addingTimeInterval(60 * 90),
            isPercentBased: false,
            updatedAt: Date()
        )
        return PixelAPIWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            isStale: false,
            diagnosticMessage: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PixelAPIWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PixelAPIWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> PixelAPIWidgetEntry {
        let snapshot = try? PixelDashboardSnapshotStore.load()
        return PixelAPIWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            isStale: snapshot.map { PixelDashboardSnapshotStore.isStale($0) } ?? false,
            diagnosticMessage: snapshot == nil ? PixelDashboardSnapshotStore.loadDiagnostic() : nil
        )
    }
}

struct PixelAPIWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let entry: PixelAPIWidgetEntry

    private enum Layout {
        static let cornerRadiusLarge: CGFloat = 26
        static let cornerRadiusCard: CGFloat = 18
        static let outerPaddingSmall: CGFloat = 18
        static let outerPaddingMedium: CGFloat = 10
        static let outerPaddingLarge: CGFloat = 16
        static let cardPadding: CGFloat = 12
        static let cardSpacing: CGFloat = 10
        static let sectionSpacing: CGFloat = 14
    }

    private enum Palette {
        static let panel = Color(red: 0.965, green: 0.975, blue: 0.982)
        static let card = Color.white.opacity(0.97)
        static let cardSubtle = Color.white.opacity(0.93)
        static let title = Color(red: 0.12, green: 0.15, blue: 0.19)
        static let label = Color(red: 0.36, green: 0.41, blue: 0.48)
        static let muted = Color(red: 0.50, green: 0.56, blue: 0.64)
        static let border = Color(red: 0.48, green: 0.55, blue: 0.63).opacity(0.20)
        static let divider = Color(red: 0.48, green: 0.55, blue: 0.63).opacity(0.24)
        static let green = Color(red: 0.02, green: 0.58, blue: 0.39)
        static let orange = Color(red: 0.86, green: 0.37, blue: 0.02)
        static let purple = Color(red: 0.35, green: 0.32, blue: 0.80)
        static let blue = Color(red: 0.04, green: 0.35, blue: 0.78)
        static let teal = Color(red: 0.02, green: 0.49, blue: 0.55)
        static let red = Color(red: 0.82, green: 0.10, blue: 0.16)
        static let gray = Color(red: 0.44, green: 0.49, blue: 0.56)
    }

    var body: some View {
        GeometryReader { proxy in
            if shouldUseFullColorRasterFallback, proxy.size.width > 0, proxy.size.height > 0 {
                fullColorRasterView(size: proxy.size)
            } else {
                widgetContent
            }
        }
        .background(Palette.panel)
        .containerBackground(for: .widget) {
            RoundedRectangle(cornerRadius: Layout.cornerRadiusLarge, style: .continuous)
                .fill(Palette.panel)
        }
    }

    private var shouldUseFullColorRasterFallback: Bool {
        if #available(macOS 15.0, *) {
            return widgetRenderingMode != .fullColor
        }
        return false
    }

    @ViewBuilder
    private var widgetContent: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall:
                    smallView(snapshot)
                case .systemMedium:
                    mediumView(snapshot)
                default:
                    largeView(snapshot)
                }
            } else {
                emptyView
            }
        }
    }

    @ViewBuilder
    private func fullColorRasterView(size: CGSize) -> some View {
        if #available(macOS 15.0, *) {
            Image(nsImage: renderedWidgetImage(size: size))
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: size.width, height: size.height)
        } else {
            widgetContent
        }
    }

    @MainActor
    private func renderedWidgetImage(size: CGSize) -> NSImage {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let renderer = ImageRenderer(
            content: widgetContent
                .frame(width: width, height: height)
                .background(Palette.panel)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: width, height: height))
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RelayBar")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("请先打开 RelayBar 并刷新一次")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.label)
                .fixedSize(horizontal: false, vertical: true)
            if let diagnostic = entry.diagnosticMessage {
                Text(diagnostic)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Layout.outerPaddingSmall)
    }

    private func smallView(_ snapshot: PixelDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(snapshot, compact: true)
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text(shouldPrioritizeCodexQuota(snapshot) ? "5h 额度" : "余额")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                    .widgetAccentable(false)

                Text(smallPrimaryValue(snapshot))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(shouldPrioritizeCodexQuota(snapshot) ? Palette.teal : metricColor(.balance, snapshot: snapshot))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .widgetAccentable(false)

                if let quota = snapshot.codexQuota {
                    Text(shouldPrioritizeCodexQuota(snapshot) ? "周 \(formatQuotaShort(remaining: quota.weeklyRemaining, total: quota.weeklyTotal, isPercentBased: quota.isPercentBased == true))" : "周 \(formatQuotaShort(remaining: quota.weeklyRemaining, total: quota.weeklyTotal, isPercentBased: quota.isPercentBased == true))  5h \(formatQuotaShort(remaining: quota.fiveHourRemaining, total: quota.fiveHourTotal, isPercentBased: quota.isPercentBased == true))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.teal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .widgetAccentable(false)
                }
            }

            Spacer(minLength: 0)

            lastUpdatedBar(snapshot, compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Layout.outerPaddingSmall)
    }

    private func mediumView(_ snapshot: PixelDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(snapshot)
            Spacer(minLength: 2)
            HStack(spacing: Layout.cardSpacing) {
                if shouldPrioritizeCodexQuota(snapshot), let quota = snapshot.codexQuota {
                    quotaMetricCard(
                        "5h 额度",
                        formatQuotaShort(remaining: quota.fiveHourRemaining, total: quota.fiveHourTotal, isPercentBased: quota.isPercentBased == true),
                        subtitle: "剩余",
                        size: .medium
                    )
                    quotaMetricCard(
                        "周额度",
                        formatQuotaShort(remaining: quota.weeklyRemaining, total: quota.weeklyTotal, isPercentBased: quota.isPercentBased == true),
                        subtitle: "剩余",
                        size: .medium
                    )
                } else {
                    metricCardView(
                        "余额",
                        formatMoney(snapshot.balance, currency: snapshot.balanceCurrency),
                        subtitle: "可用",
                        kind: .balance,
                        snapshot: snapshot,
                        size: .medium
                    )
                    metricCardView(
                        "今日 Token",
                        formatTokens(snapshot.todayTokenTotal),
                        subtitle: "今日",
                        kind: .todayToken,
                        snapshot: snapshot,
                        size: .medium
                    )
                }
            }
            Spacer(minLength: 0)
            if let quota = snapshot.codexQuota, !shouldPrioritizeCodexQuota(snapshot) {
                codexQuotaStrip(quota, compact: true)
                Spacer(minLength: 0)
            }
            lastUpdatedBar(snapshot, compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Layout.outerPaddingMedium)
    }

    private func largeView(_ snapshot: PixelDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(snapshot)
            Spacer(minLength: 8)

            largePrimaryGrid(snapshot)
            .layoutPriority(1)

            Spacer(minLength: 8)
            if let quota = snapshot.codexQuota, !shouldPrioritizeCodexQuota(snapshot) {
                codexQuotaStrip(quota, compact: false)
                Spacer(minLength: 6)
            }
            if shouldPrioritizeCodexQuota(snapshot) {
                codexQuotaStrip(snapshot.codexQuota!, compact: false)
            } else {
                tokenBreakdownSummary(snapshot)
            }
            Spacer(minLength: 4)
            lastUpdatedBar(snapshot, compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Layout.outerPaddingLarge)
    }

    private func widgetHeader(_ snapshot: PixelDashboardSnapshot, compact: Bool = false) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Circle()
                .fill(statusColor(for: snapshot))
                .frame(width: compact ? 8 : 9, height: compact ? 8 : 9)
            Text(widgetTitle(for: snapshot))
                .font(.system(size: compact ? 15 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.title)
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.65 : 0.78)
                .layoutPriority(1)
                .widgetAccentable(false)
            Spacer(minLength: compact ? 4 : 8)
            statusChip(snapshot, compact: compact)
        }
    }

    private func statusChip(_ snapshot: PixelDashboardSnapshot, compact: Bool = false) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            Circle()
                .fill(statusColor(for: snapshot))
                .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
            Text(compact ? compactStatusText(for: snapshot) : statusText(for: snapshot))
                .font(.system(size: compact ? 11 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(statusColor(for: snapshot))
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.72 : 0.8)
                .widgetAccentable(false)
        }
        .padding(.horizontal, compact ? 8 : 11)
        .padding(.vertical, compact ? 5 : 6)
        .frame(width: compact ? 58 : nil, alignment: .center)
        .background(statusColor(for: snapshot).opacity(0.14), in: Capsule())
        .overlay(
            Capsule()
                .stroke(statusColor(for: snapshot).opacity(0.16), lineWidth: 1)
        )
        .fixedSize(horizontal: compact, vertical: false)
        .layoutPriority(2)
        .widgetAccentable(false)
    }

    private enum MetricKind {
        case balance
        case todayCost
        case todayToken
        case totalToken
    }

    private enum MetricSize {
        case medium
        case large
    }

    private func metricCardView(
        _ title: String,
        _ value: String,
        subtitle: String,
        kind: MetricKind,
        snapshot: PixelDashboardSnapshot,
        size: MetricSize
    ) -> some View {
        let color = metricColor(kind, snapshot: snapshot)
        let valueSize: CGFloat = size == .medium ? 22 : 24
        let minHeight: CGFloat = size == .medium ? 68 : 98

        return VStack(alignment: .leading, spacing: size == .medium ? 2 : 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
                .widgetAccentable(false)

            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .widgetAccentable(false)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable(false)
        }
        .padding(size == .medium ? 8 : Layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Layout.cornerRadiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadiusCard, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.08), radius: 12, y: 5)
    }

    private func largeMetricCard(
        _ title: String,
        _ value: String,
        subtitle: String,
        kind: MetricKind,
        snapshot: PixelDashboardSnapshot,
        icon: String
    ) -> some View {
        let color = metricColor(kind, snapshot: snapshot)

        return VStack(alignment: .leading, spacing: 2) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 20, height: 20)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .widgetAccentable(false)
            }

            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .widgetAccentable(false)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .widgetAccentable(false)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .widgetAccentable(false)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Layout.cornerRadiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadiusCard, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.08), radius: 12, y: 5)
    }

    @ViewBuilder
    private func largePrimaryGrid(_ snapshot: PixelDashboardSnapshot) -> some View {
        if shouldPrioritizeCodexQuota(snapshot), let quota = snapshot.codexQuota {
            VStack(spacing: Layout.cardSpacing) {
                HStack(spacing: Layout.cardSpacing) {
                    quotaMetricCard(
                        "5h 额度",
                        formatQuotaShort(remaining: quota.fiveHourRemaining, total: quota.fiveHourTotal, isPercentBased: quota.isPercentBased == true),
                        subtitle: "剩余",
                        size: .large
                    )
                    quotaMetricCard(
                        "周额度",
                        formatQuotaShort(remaining: quota.weeklyRemaining, total: quota.weeklyTotal, isPercentBased: quota.isPercentBased == true),
                        subtitle: "剩余",
                        size: .large
                    )
                }
            }
        } else {
            VStack(spacing: Layout.cardSpacing) {
                HStack(spacing: Layout.cardSpacing) {
                    largeMetricCard(
                        "余额",
                        formatMoney(snapshot.balance, currency: snapshot.balanceCurrency),
                        subtitle: "可用",
                        kind: .balance,
                        snapshot: snapshot,
                        icon: "wallet.pass"
                    )
                    largeMetricCard(
                        "今日消费",
                        formatTodayCost(snapshot),
                        subtitle: "实际 / 计费",
                        kind: .todayCost,
                        snapshot: snapshot,
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }

                HStack(spacing: Layout.cardSpacing) {
                    largeMetricCard(
                        "今日 Token",
                        formatTokens(snapshot.todayTokenTotal),
                        subtitle: "今日",
                        kind: .todayToken,
                        snapshot: snapshot,
                        icon: "flame"
                    )
                    largeMetricCard(
                        "累计 Token",
                        formatTokens(snapshot.totalTokenTotal),
                        subtitle: "累计",
                        kind: .totalToken,
                        snapshot: snapshot,
                        icon: "square.stack.3d.up"
                    )
                }
            }
        }
    }

    private func quotaMetricCard(
        _ title: String,
        _ value: String,
        subtitle: String,
        size: MetricSize
    ) -> some View {
        let valueSize: CGFloat = size == .medium ? 24 : 30
        let minHeight: CGFloat = size == .medium ? 68 : 98

        return VStack(alignment: .leading, spacing: size == .medium ? 2 : 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
                .widgetAccentable(false)

            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.teal)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .widgetAccentable(false)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable(false)
        }
        .padding(size == .medium ? 8 : Layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Layout.cornerRadiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadiusCard, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.08), radius: 12, y: 5)
    }

    private func codexQuotaStrip(_ quota: CodexQuotaSnapshot, compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            quotaPill(
                title: "周",
                value: formatQuotaShort(remaining: quota.weeklyRemaining, total: quota.weeklyTotal, isPercentBased: quota.isPercentBased == true),
                compact: compact
            )
            quotaPill(
                title: "5h",
                value: formatQuotaShort(remaining: quota.fiveHourRemaining, total: quota.fiveHourTotal, isPercentBased: quota.isPercentBased == true),
                compact: compact
            )
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 7 : 10)
        .background(Palette.cardSubtle, in: RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
    }

    private func quotaPill(title: String, value: String, compact: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(Palette.label)
            Text(value)
                .foregroundStyle(Palette.teal)
        }
        .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable(false)
    }

    private func tokenBreakdownSummary(_ snapshot: PixelDashboardSnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今日")
                    .foregroundStyle(Palette.orange)
                Text("累计")
                    .foregroundStyle(Palette.blue)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .widgetAccentable(false)

            VStack(alignment: .leading, spacing: 6) {
                Text("输入 \(formatTokens(snapshot.todayInputTokens))")
                    .foregroundStyle(Palette.orange)
                Text("输入 \(formatTokens(snapshot.totalInputTokens))")
                    .foregroundStyle(Palette.blue)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .widgetAccentable(false)

            Divider()
                .frame(height: 34)
                .opacity(0.55)
                .overlay(Palette.divider)

            VStack(alignment: .leading, spacing: 6) {
                Text("输出 \(formatTokens(snapshot.todayOutputTokens))")
                    .foregroundStyle(Palette.orange)
                Text("输出 \(formatTokens(snapshot.totalOutputTokens))")
                    .foregroundStyle(Palette.blue)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .widgetAccentable(false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.cardSubtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
    }

    private func lastUpdatedBar(_ snapshot: PixelDashboardSnapshot, compact: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.55)
                .overlay(Palette.divider)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: compact ? 10 : 12, weight: .medium, design: .rounded))
                Text("最后刷新  \(formatTime(snapshot.updatedAt))")
                    .font(.system(size: compact ? 11 : 13, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.muted)
            .widgetAccentable(false)
            .padding(.top, compact ? 4 : 10)
        }
    }

    private func shouldPrioritizeCodexQuota(_ snapshot: PixelDashboardSnapshot) -> Bool {
        guard snapshot.codexQuota != nil else { return false }
        let hasPrimaryMetrics = snapshot.balance != nil
            || snapshot.todayCostPrimary != nil
            || snapshot.todayTokenTotal != nil
            || snapshot.totalTokenTotal != nil
        return !hasPrimaryMetrics
    }

    private func widgetTitle(for snapshot: PixelDashboardSnapshot) -> String {
        shouldPrioritizeCodexQuota(snapshot) ? "Codex 额度" : snapshot.providerName
    }

    private func smallPrimaryValue(_ snapshot: PixelDashboardSnapshot) -> String {
        guard shouldPrioritizeCodexQuota(snapshot), let quota = snapshot.codexQuota else {
            return formatMoney(snapshot.balance, currency: snapshot.balanceCurrency)
        }
        return formatQuotaShort(
            remaining: quota.fiveHourRemaining,
            total: quota.fiveHourTotal,
            isPercentBased: quota.isPercentBased == true
        )
    }

    private func statusColor(for snapshot: PixelDashboardSnapshot) -> Color {
        if entry.isStale {
            return .gray
        }
        if shouldPrioritizeCodexQuota(snapshot) {
            return Palette.teal
        }
        switch snapshot.status {
        case .normal:
            return Palette.green
        case .lowBalance:
            return Palette.orange
        case .cached, .notConfigured:
            return Palette.gray
        case .error, .unauthorized:
            return Palette.red
        }
    }

    private func metricColor(_ kind: MetricKind, snapshot: PixelDashboardSnapshot) -> Color {
        switch kind {
        case .balance:
            return statusColor(for: snapshot)
        case .todayCost:
            return Palette.purple
        case .todayToken:
            return Palette.orange
        case .totalToken:
            return Palette.blue
        }
    }

    private func statusText(for snapshot: PixelDashboardSnapshot) -> String {
        if entry.isStale {
            return "缓存"
        }
        if shouldPrioritizeCodexQuota(snapshot) {
            return "同步"
        }
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

    private func compactStatusText(for snapshot: PixelDashboardSnapshot) -> String {
        if entry.isStale {
            return "缓存"
        }
        if shouldPrioritizeCodexQuota(snapshot) {
            return "同步"
        }
        switch snapshot.status {
        case .normal:
            return "正常"
        case .lowBalance:
            return "低"
        case .cached:
            return "缓存"
        case .error:
            return "错误"
        case .unauthorized:
            return "未授权"
        case .notConfigured:
            return "配置"
        }
    }

    private func statusDescription(for snapshot: PixelDashboardSnapshot) -> String {
        if entry.isStale {
            return "缓存数据"
        }
        if let error = snapshot.errorMessage, !error.isEmpty {
            return error
        }
        return statusText(for: snapshot)
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

    private func formatQuotaShort(remaining: Double?, total: Double?, isPercentBased: Bool = false) -> String {
        guard let remaining else { return "--" }
        let safeRemaining = max(0, remaining)
        if isPercentBased {
            return String(format: "%.0f%%", min(100, safeRemaining))
        }
        guard let total, total > 0 else {
            return String(format: "%.0f", safeRemaining)
        }
        return "\(String(format: "%.0f", safeRemaining))/\(String(format: "%.0f", total))"
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

struct PixelAPIWidget: Widget {
    let kind = "PixelAPIWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PixelAPIWidgetProvider()) { entry in
            PixelAPIWidgetView(entry: entry)
        }
        .configurationDisplayName("RelayBar")
        .description("显示当前中转站的余额和使用概览。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
