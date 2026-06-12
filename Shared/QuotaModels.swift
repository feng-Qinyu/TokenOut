import Foundation

let quotaAppGroupID = "group.local.tokenout"
let quotaSnapshotFileName = "snapshot.json"
let quotaDailyBudget = 100.0 / 7.0

struct QuotaSnapshot: Codable {
    var weeklyUsed: Double
    var fiveHourUsed: Double
    var weeklyResetAt: TimeInterval?
    var weeklyDurationMins: Double?
    var planType: String?
    var fetchedAt: Date
    var dayKey: String?
    var todayStartWeeklyUsed: Double?

    var weeklyRemaining: Double {
        max(0, 100 - weeklyUsed)
    }

    var fiveHourRemaining: Double {
        max(0, 100 - fiveHourUsed)
    }

    var dayIndex: Int {
        guard let weeklyResetAt, let weeklyDurationMins else {
            let weekday = Calendar.current.component(.weekday, from: Date())
            return weekday == 1 ? 7 : weekday - 1
        }
        let resetAtSeconds = weeklyResetAt > 1e11 ? weeklyResetAt / 1000 : weeklyResetAt
        let startAt = resetAtSeconds - weeklyDurationMins * 60
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: Date(timeIntervalSince1970: startAt))
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        return min(7, max(1, days + 1))
    }

    var todayUsed: Double {
        max(0, weeklyUsed - effectiveTodayStartWeeklyUsed)
    }

    var todayRemaining: Double {
        let targetThroughToday = Double(dayIndex) * quotaDailyBudget
        return max(0, min(weeklyRemaining, targetThroughToday - weeklyUsed))
    }

    static let placeholder = QuotaSnapshot(
        weeklyUsed: 26,
        fiveHourUsed: 12,
        weeklyResetAt: nil,
        weeklyDurationMins: nil,
        planType: "codex",
        fetchedAt: Date(),
        dayKey: nil,
        todayStartWeeklyUsed: nil
    )

    func withDailyBaseline(previous: QuotaSnapshot?) -> QuotaSnapshot {
        var snapshot = self
        let currentDayKey = Self.localDayKey()

        if previous?.dayKey == currentDayKey,
           let baseline = previous?.todayStartWeeklyUsed {
            snapshot.todayStartWeeklyUsed = weeklyUsed < baseline ? weeklyUsed : baseline
        } else if previous.map({ Self.localDayKey(for: $0.fetchedAt) }) == currentDayKey {
            snapshot.todayStartWeeklyUsed = previous?.weeklyUsed ?? weeklyUsed
        } else {
            snapshot.todayStartWeeklyUsed = weeklyUsed
        }
        snapshot.dayKey = currentDayKey
        return snapshot
    }

    private var effectiveTodayStartWeeklyUsed: Double {
        if dayKey == Self.localDayKey(), let todayStartWeeklyUsed {
            return min(todayStartWeeklyUsed, weeklyUsed)
        }

        let previousDaysTarget = Double(max(0, dayIndex - 1)) * quotaDailyBudget
        return previousDaysTarget
    }

    private static func localDayKey(for date: Date = Date()) -> String {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum QuotaStore {
    static var fileURL: URL? {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "appex" {
            let hostResourceURL = bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent(quotaSnapshotFileName)
            if FileManager.default.fileExists(atPath: hostResourceURL.path) {
                return hostResourceURL
            }
        }

        let installedResourceURL = URL(fileURLWithPath: "/Applications/TokenOut.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent(quotaSnapshotFileName)
        if FileManager.default.fileExists(atPath: installedResourceURL.path) {
            return installedResourceURL
        }

        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(quotaSnapshotFileName),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        return installedResourceURL
    }

    static func save(_ snapshot: QuotaSnapshot) {
        guard let fileURL else { return }
        do {
            let snapshot = snapshot.withDailyBaseline(previous: load())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("TokenOut save failed: \(error.localizedDescription)")
        }
    }

    static func load() -> QuotaSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(QuotaSnapshot.self, from: data)
    }
}
