import AppKit
import SwiftUI

struct FloatingBalanceView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    private var balanceText: String {
        let snapshot = dashboardVM.pixelDashboardSnapshot
        return dashboardVM.formatPixelMoney(snapshot?.balance, currency: snapshot?.balanceCurrency ?? "USD")
    }

    private var isAvailable: Bool {
        dashboardVM.pixelDashboardSnapshot != nil && dashboardVM.errorMessages[.pixel] == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(dashboardVM.activeProviderDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if dashboardVM.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
                Button {
                    NotificationCenter.default.post(name: .relayBarQuit, object: nil)
                } label: {
                    Image(systemName: "power")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("退出 RelayBar")
            }

            Text(balanceText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            if let snapshot = dashboardVM.pixelDashboardSnapshot {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    compactLine("今日消费", dashboardVM.formatPixelTodayCost(snapshot))
                    compactLine("今日 Token", dashboardVM.formatPixelTokens(snapshot.todayTokenTotal))
                    compactLine("累计 Token", dashboardVM.formatPixelTokens(snapshot.totalTokenTotal))
                    compactLine("更新", dashboardVM.formatPixelTime(snapshot.updatedAt))
                }
            }

            if let error = dashboardVM.pixelDashboardSnapshot?.errorMessage ?? dashboardVM.errorMessages[.pixel], !error.contains("not support") {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if dashboardVM.pixelDashboardSnapshot?.status == .cached {
                Text("缓存数据")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch dashboardVM.pixelStatusColorName {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return isAvailable ? .green : .secondary
        }
    }

    private func compactLine(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
