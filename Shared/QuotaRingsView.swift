import SwiftUI

struct QuotaRingsView: View {
    let snapshot: QuotaSnapshot

    var body: some View {
        HStack(spacing: 10) {
            MetricRing(title: "本周剩余", value: snapshot.weeklyRemaining, total: 100, symbol: "calendar", healthValue: snapshot.weeklyRemaining)
            MetricRing(title: "5小时剩余", value: snapshot.fiveHourRemaining, total: 100, symbol: "clock", healthValue: snapshot.fiveHourRemaining)
            MetricRing(title: "今日已用", value: snapshot.todayUsed, total: quotaDailyBudget, symbol: "flame", healthValue: snapshot.todayRemaining / max(1, quotaDailyBudget) * 100)
            MetricRing(title: "今日未用", value: snapshot.todayRemaining, total: quotaDailyBudget, symbol: "gauge.medium", healthValue: snapshot.todayRemaining / max(1, quotaDailyBudget) * 100)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct MetricRing: View {
    let title: String
    let value: Double
    let total: Double
    let symbol: String
    let healthValue: Double

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.13), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0, min(1, value / total)))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .frame(width: 56, height: 56)

            Text(format(value))
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.top, -3)
        }
        .frame(maxWidth: .infinity)
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
