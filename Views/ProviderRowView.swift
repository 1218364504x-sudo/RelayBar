// Views/ProviderRowView.swift
import SwiftUI

struct ProviderRowView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    let config: ProviderConfig

    private var isNotSupported: Bool {
        guard let err = dashboardVM.errorMessages[config.provider] else { return false }
        return err.contains("not support")
    }

    private var hasData: Bool {
        dashboardVM.balances[config.provider] != nil || dashboardVM.usageSummaries[config.provider] != nil
    }

    private var isLoading: Bool {
        dashboardVM.balances[config.provider] == nil
            && dashboardVM.errorMessages[config.provider] == nil
            && dashboardVM.isRefreshing
    }

    private var needsAPIKey: Bool {
        config.apiKey.isEmpty
    }

    var body: some View {
        if config.provider == .pixel {
            pixelRow
        } else {
            defaultRow
        }
    }

    private var pixelRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: config.provider.iconName)
                .font(.title3)
                .foregroundColor(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Pixel API")
                        .font(.subheadline.weight(.medium))
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    if dashboardVM.pixelBalance?.isCached == true {
                        Text("Cached")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Base URL: \(config.baseURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if needsAPIKey {
                    Text("API Key is empty")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if let snapshot = dashboardVM.pixelDashboardSnapshot {
                    Text("余额: \(dashboardVM.formatPixelMoney(snapshot.balance, currency: snapshot.balanceCurrency ?? "USD"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("今日 Token: \(dashboardVM.formatPixelTokens(snapshot.todayTokenTotal))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("累计 Token: \(dashboardVM.formatPixelTokens(snapshot.totalTokenTotal))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = dashboardVM.errorMessages[.pixel], !needsAPIKey {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if let snapshot = dashboardVM.pixelDashboardSnapshot {
                    Text(dashboardVM.formatPixelMoney(snapshot.balance, currency: snapshot.balanceCurrency ?? "USD"))
                        .font(.caption.weight(.semibold))
                    Text(dashboardVM.pixelStatusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text(needsAPIKey ? "Setup" : "No data")
                        .font(.caption)
                        .foregroundColor(needsAPIKey ? .orange : .secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private var defaultRow: some View {
        HStack(spacing: 12) {
            Image(systemName: config.provider.iconName)
                .font(.title3)
                .foregroundColor(colorFromString(config.provider.tintColor))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.provider.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if isNotSupported {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }

                if needsAPIKey {
                    Text("API key not configured")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if let balance = dashboardVM.balances[config.provider] {
                    let display = dashboardVM.displayBalance(for: balance)
                    Text("Balance: \(String(format: "%.2f", display.amount)) \(display.currency.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let summary = dashboardVM.usageSummaries[config.provider] {
                    Text("This month: \(String(format: "%.2f", summary.totalCostThisMonth)) \(summary.currency)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if isNotSupported {
                    Text("Connected — usage data not available via API")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = dashboardVM.errorMessages[config.provider] {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if !hasData && !isNotSupported && !isLoading && !needsAPIKey {
                    Text("No data yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            } else if needsAPIKey {
                Text("Add Key")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if let balance = dashboardVM.balances[config.provider] {
                VStack(alignment: .trailing, spacing: 1) {
                    let display = dashboardVM.displayBalance(for: balance)
                    Text("\(String(format: "%.2f", display.amount))")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(display.currency.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
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

    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        default: return .gray
        }
    }
}
