import Foundation

enum QuotaFetchError: LocalizedError {
    case codexNotFound
    case launchFailed
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "找不到 Codex CLI"
        case .launchFailed: return "无法启动 Codex CLI"
        case .timeout: return "读取超时"
        case .invalidResponse: return "返回格式不符合预期"
        }
    }
}

enum QuotaFetcher {
    static func fetch() async throws -> QuotaSnapshot {
        try await Task.detached(priority: .utility) {
            try fetchSync()
        }.value
    }

    private static func fetchSync() throws -> QuotaSnapshot {
        let codexPath = "/Applications/Codex.app/Contents/Resources/codex"
        guard FileManager.default.fileExists(atPath: codexPath) else {
            throw QuotaFetchError.codexNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            NSLog("TokenOut launch failed: \(error.localizedDescription)")
            throw QuotaFetchError.launchFailed
        }

        let messages: [[String: Any?]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "codex-quota-app", "version": "0.1"],
                    "capabilities": [:]
                ]
            ],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read", "params": nil]
        ]

        for message in messages {
            guard let data = try? JSONSerialization.data(withJSONObject: message.compactMapValues { $0 }) else { continue }
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([10]))
        }

        var buffer = Data()
        var parsed: QuotaSnapshot?
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            buffer.append(data)
            if parsed == nil {
                parsed = parseSnapshot(from: buffer)
                if parsed != nil { done.signal() }
            }
            lock.unlock()
        }

        let result = done.wait(timeout: .now() + 10)
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        process.terminate()

        if result == .timedOut {
            let stderr = String(data: error.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            NSLog("TokenOut fetch timed out. stderr: \(stderr)")
            throw QuotaFetchError.timeout
        }

        guard let parsed else {
            let text = String(data: buffer, encoding: .utf8) ?? ""
            NSLog("TokenOut invalid response: \(text)")
            throw QuotaFetchError.invalidResponse
        }
        return parsed
    }

    private static func parseSnapshot(from data: Data) -> QuotaSnapshot? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = root["id"] as? Int,
                  id == 2,
                  let result = root["result"] as? [String: Any] else {
                continue
            }

            let byId = result["rateLimitsByLimitId"] as? [String: Any]
            let codex = byId?["codex"] as? [String: Any]
            let selected = codex ?? result["rateLimits"] as? [String: Any]
            guard let selected else { return nil }

            let weekly = selected["secondary"] as? [String: Any]
            let short = selected["primary"] as? [String: Any]

            return QuotaSnapshot(
                weeklyUsed: number(weekly?["usedPercent"]) ?? 0,
                fiveHourUsed: number(short?["usedPercent"]) ?? 0,
                weeklyResetAt: number(weekly?["resetsAt"]),
                weeklyDurationMins: number(weekly?["windowDurationMins"]),
                planType: selected["planType"] as? String,
                fetchedAt: Date()
            )
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let int = value as? Int { return Double(int) }
        if let double = value as? Double { return double }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
