import Darwin
import SwiftUI
import WidgetKit

@main
struct TokenOutApp: App {
    @StateObject private var model = QuotaViewModel()

    init() {
        if CommandLine.arguments.contains("--reload-widget") {
            WidgetCenter.shared.reloadAllTimelines()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("TokenOut") {
            ContentView()
                .environmentObject(model)
                .task {
                    await model.refresh()
                }
        }
        .defaultSize(width: 620, height: 280)

        Settings {
            EmptyView()
        }
    }
}

final class QuotaViewModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var status = "正在读取 Codex CLI..."

    @MainActor
    func refresh() async {
        if let snapshot = QuotaStore.load() {
            self.snapshot = snapshot
            self.status = "已更新 \(Self.time(snapshot.fetchedAt))"
        } else {
            self.status = "后台服务尚未写入数据"
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TokenOut")
                        .font(.system(size: 30, weight: .bold))
                    Text("Codex Token 额度监控")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") {
                    Task { await model.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }

            if let snapshot = model.snapshot ?? QuotaStore.load() {
                TokenOutDashboard(snapshot: snapshot)
            } else {
                TokenOutDashboard(snapshot: .placeholder)
                    .redacted(reason: .placeholder)
            }

            HStack(spacing: 12) {
                Text(model.status)
                Text("后台每 1 分钟更新")
                Spacer()
                Text("低于 20% 显示红色")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 360, idealHeight: 390)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct TokenOutDashboard: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        HStack(spacing: 14) {
            AppMetricCard(
                title: "本周剩余",
                detail: "本周总额度还剩多少",
                value: snapshot.weeklyRemaining,
                total: 100,
                symbol: "calendar",
                healthValue: snapshot.weeklyRemaining
            )
            AppMetricCard(
                title: "5小时剩余",
                detail: "短周期额度还剩多少",
                value: snapshot.fiveHourRemaining,
                total: 100,
                symbol: "clock",
                healthValue: snapshot.fiveHourRemaining
            )
            AppMetricCard(
                title: "今日已用",
                detail: "今天已使用的目标额度",
                value: snapshot.todayUsed,
                total: quotaDailyBudget,
                symbol: "flame",
                healthValue: snapshot.todayRemaining / max(1, quotaDailyBudget) * 100
            )
            AppMetricCard(
                title: "今日未用",
                detail: "今天建议继续用掉的额度",
                value: snapshot.todayRemaining,
                total: 100,
                symbol: "gauge.medium",
                healthValue: snapshot.todayRemaining / max(1, quotaDailyBudget) * 100
            )
        }
    }
}

struct AppMetricCard: View {
    let title: String
    let detail: String
    let value: Double
    let total: Double
    let symbol: String
    let healthValue: Double

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0, min(1, value / total)))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .frame(width: 86, height: 86)

            Text(format(value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func format(_ value: Double) -> String {
        if value >= 99.95 { return "100%" }
        if abs(value.rounded() - value) < 0.05 { return "\(Int(value.rounded()))%" }
        return String(format: "%.1f%%", value)
    }

    private var ringColor: Color {
        healthValue < 20
            ? Color(red: 1.0, green: 0.24, blue: 0.26)
            : Color(red: 0.20, green: 0.84, blue: 0.34)
    }
}
