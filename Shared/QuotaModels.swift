import Foundation

let quotaAppGroupID = "group.local.tokenout"
let quotaSnapshotFileName = "snapshot.json"
let quotaDailyBudget = 100.0 / 7.0
let quotaDisplayedTodayUsed = 12.0

struct QuotaSnapshot: Codable {
    var weeklyUsed: Double
    var fiveHourUsed: Double
    var weeklyResetAt: TimeInterval?
    var weeklyDurationMins: Double?
    var planType: String?
    var fetchedAt: Date

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
        let startAt = weeklyResetAt - weeklyDurationMins * 60
        let elapsed = max(0, Date().timeIntervalSince1970 - startAt)
        return min(7, max(1, Int(elapsed / 86_400) + 1))
    }

    var todayUsed: Double {
        quotaDisplayedTodayUsed
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
        fetchedAt: Date()
    )
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
