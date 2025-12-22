import Foundation

public struct WidgetSnapshot: Codable, Sendable {
    public struct ProviderEntry: Codable, Sendable {
        public let provider: UsageProvider
        public let updatedAt: Date
        public let primary: RateWindow?
        public let secondary: RateWindow?
        public let tertiary: RateWindow?
        public let creditsRemaining: Double?
        public let codeReviewRemainingPercent: Double?
        public let tokenUsage: TokenUsageSummary?
        public let dailyUsage: [DailyUsagePoint]

        public init(
            provider: UsageProvider,
            updatedAt: Date,
            primary: RateWindow?,
            secondary: RateWindow?,
            tertiary: RateWindow?,
            creditsRemaining: Double?,
            codeReviewRemainingPercent: Double?,
            tokenUsage: TokenUsageSummary?,
            dailyUsage: [DailyUsagePoint])
        {
            self.provider = provider
            self.updatedAt = updatedAt
            self.primary = primary
            self.secondary = secondary
            self.tertiary = tertiary
            self.creditsRemaining = creditsRemaining
            self.codeReviewRemainingPercent = codeReviewRemainingPercent
            self.tokenUsage = tokenUsage
            self.dailyUsage = dailyUsage
        }
    }

    public struct TokenUsageSummary: Codable, Sendable {
        public let sessionCostUSD: Double?
        public let sessionTokens: Int?
        public let last30DaysCostUSD: Double?
        public let last30DaysTokens: Int?

        public init(
            sessionCostUSD: Double?,
            sessionTokens: Int?,
            last30DaysCostUSD: Double?,
            last30DaysTokens: Int?)
        {
            self.sessionCostUSD = sessionCostUSD
            self.sessionTokens = sessionTokens
            self.last30DaysCostUSD = last30DaysCostUSD
            self.last30DaysTokens = last30DaysTokens
        }
    }

    public struct DailyUsagePoint: Codable, Sendable {
        public let dayKey: String
        public let totalTokens: Int?
        public let costUSD: Double?

        public init(dayKey: String, totalTokens: Int?, costUSD: Double?) {
            self.dayKey = dayKey
            self.totalTokens = totalTokens
            self.costUSD = costUSD
        }
    }

    public let entries: [ProviderEntry]
    public let generatedAt: Date

    public init(entries: [ProviderEntry], generatedAt: Date) {
        self.entries = entries
        self.generatedAt = generatedAt
    }
}

public enum WidgetSnapshotStore {
    public static let appGroupID = "group.com.steipete.codexbar"
    private static let filename = "widget-snapshot.json"

    public static func load(bundleID: String? = Bundle.main.bundleIdentifier) -> WidgetSnapshot? {
        guard let url = self.snapshotURL(bundleID: bundleID) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetSnapshot, bundleID: String? = Bundle.main.bundleIdentifier) {
        guard let url = self.snapshotURL(bundleID: bundleID) else { return }
        do {
            let data = try self.encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private static func snapshotURL(bundleID: String?) -> URL? {
        let fm = FileManager.default
        let groupID = self.groupID(for: bundleID)
        if let groupID, let container = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return container.appendingPathComponent(self.filename, isDirectory: false)
        }

        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("CodexBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(self.filename, isDirectory: false)
    }

    private static func groupID(for bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return self.appGroupID }
        if bundleID.contains(".debug") {
            return "group.com.steipete.codexbar.debug"
        }
        return self.appGroupID
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
