import Foundation

public enum CCUsageError: LocalizedError, Sendable {
    case cliNotInstalled(binary: String, installCommand: String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .cliNotInstalled(binary, installCommand):
            "\(binary) is not installed. Install with `\(installCommand)` and restart CodexBar."
        case let .decodeFailed(details):
            "Could not parse ccusage output: \(details)"
        }
    }
}

public struct CCUsageFetcher: Sendable {
    public init() {}

    public enum CLI: String, Sendable {
        case ccusage
        case codex = "ccusage-codex"

        var installCommand: String {
            switch self {
            case .ccusage:
                "npm i -g ccusage"
            case .codex:
                "npm i -g @ccusage/codex"
            }
        }
    }

    public func loadTokenSnapshot(cli: CLI, now: Date = Date()) async throws -> CCUsageTokenSnapshot {
        guard let ccusagePath = TTYCommandRunner.which(cli.rawValue) else {
            throw CCUsageError.cliNotInstalled(binary: cli.rawValue, installCommand: cli.installCommand)
        }

        let env = TTYCommandRunner.enrichedEnvironment()
        let untilKey = Self.dayKey(from: now)
        // Rolling window: last 30 days (inclusive). Use -29 for inclusive boundaries.
        let dailySinceKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now)
        let daily = try await Self.runDaily(
            ccusagePath: ccusagePath,
            env: env,
            sinceKey: dailySinceKey,
            untilKey: untilKey)
        return Self.tokenSnapshot(from: daily, now: now)
    }

    static func tokenSnapshot(from daily: CCUsageDailyReport, now: Date) -> CCUsageTokenSnapshot {
        let currentDay = daily.data.max { lhs, rhs in
            let lDate = CCUsageDateParser.parse(lhs.date) ?? .distantPast
            let rDate = CCUsageDateParser.parse(rhs.date) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.date < rhs.date
        }
        let totalFromSummary = daily.summary?.totalCostUSD
        let totalFromEntries = daily.data.compactMap(\.costUSD).reduce(0, +)
        let last30DaysCostUSD = totalFromSummary ?? (totalFromEntries > 0 ? totalFromEntries : nil)

        return CCUsageTokenSnapshot(
            sessionTokens: currentDay?.totalTokens,
            sessionCostUSD: currentDay?.costUSD,
            last30DaysCostUSD: last30DaysCostUSD,
            daily: daily.data,
            updatedAt: now)
    }

    private static func runDaily(
        ccusagePath: String,
        env: [String: String],
        sinceKey: String,
        untilKey: String) async throws -> CCUsageDailyReport
    {
        let result = try await SubprocessRunner.run(
            binary: ccusagePath,
            arguments: ["daily", "--json", "--offline", "--since", sinceKey, "--until", untilKey],
            environment: env,
            timeout: 10 * 60,
            label: "ccusage daily")

        guard let data = result.stdout.data(using: .utf8) else {
            throw CCUsageError.decodeFailed("empty stdout")
        }
        do {
            return try JSONDecoder().decode(CCUsageDailyReport.self, from: data)
        } catch {
            throw CCUsageError.decodeFailed(error.localizedDescription)
        }
    }

    static func selectCurrentSession(from sessions: [CCUsageSessionReport.Entry])
        -> CCUsageSessionReport.Entry?
    {
        if sessions.isEmpty { return nil }
        return sessions.max { lhs, rhs in
            let lDate = CCUsageDateParser.parse(lhs.lastActivity) ?? .distantPast
            let rDate = CCUsageDateParser.parse(rhs.lastActivity) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.session < rhs.session
        }
    }

    static func selectMostRecentMonth(from months: [CCUsageMonthlyReport.Entry])
        -> CCUsageMonthlyReport.Entry?
    {
        if months.isEmpty { return nil }
        return months.max { lhs, rhs in
            let lDate = CCUsageDateParser.parseMonth(lhs.month) ?? .distantPast
            let rDate = CCUsageDateParser.parseMonth(rhs.month) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.month < rhs.month
        }
    }

    private static func dayKey(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        // ccusage expects YYYYMMDD (Claude); @ccusage/codex accepts both.
        df.dateFormat = "yyyyMMdd"
        return df.string(from: date)
    }
}
