import CodexBarSync
import Foundation
import os

struct QuotaKitWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 4

    struct Provider: Codable, Equatable, Identifiable, Sendable {
        struct Window: Codable, Equatable, Sendable {
            let title: String
            let usedPercent: Double
            let remainingPercent: Double
            let resetsAt: Date?
            let pace: SyncUsagePace?
            let identity: SyncRateWindowIdentity?

            private enum CodingKeys: String, CodingKey {
                case title
                case usedPercent
                case remainingPercent
                case resetsAt
                case pace
                case identity
            }

            init(
                title: String,
                usedPercent: Double,
                remainingPercent: Double,
                resetsAt: Date?,
                pace: SyncUsagePace?,
                identity: SyncRateWindowIdentity? = nil)
            {
                self.title = title
                self.usedPercent = usedPercent
                self.remainingPercent = remainingPercent
                self.resetsAt = resetsAt
                self.pace = pace
                self.identity = identity
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.title = try container.decode(String.self, forKey: .title)
                self.usedPercent = try container.decode(Double.self, forKey: .usedPercent)
                self.remainingPercent = try container.decode(Double.self, forKey: .remainingPercent)
                self.resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
                self.pace = try container.decodeIfPresent(SyncUsagePace.self, forKey: .pace)
                let rawIdentity = try container.decodeIfPresent(String.self, forKey: .identity)
                self.identity = rawIdentity.flatMap(SyncRateWindowIdentity.init(rawValue:))
            }
        }

        let id: String
        let providerName: String
        let lastUpdated: Date
        let statusMessage: String?
        let isError: Bool
        let windows: [Window]

        var primaryWindow: Window? {
            self.windows.first
        }
    }

    let schemaVersion: Int
    let generatedAt: Date
    let lastSyncedAt: Date
    let providers: [Provider]

    init(
        schemaVersion: Int = QuotaKitWidgetSnapshot.currentSchemaVersion,
        generatedAt: Date,
        lastSyncedAt: Date? = nil,
        providers: [Provider])
    {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.lastSyncedAt = lastSyncedAt ?? generatedAt
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
            ?? self.generatedAt
        self.providers = try container.decode([Provider].self, forKey: .providers)
    }

    var primaryProvider: Provider? {
        self.providers.first
    }

    func applyingProviderPreferences(
        _ preferences: QuotaKitWidgetProviderPreferences) -> QuotaKitWidgetSnapshot
    {
        let orderedProviders = QuotaKitWidgetProviderPreferencesStore.orderedItems(
            self.providers,
            preferences: preferences,
            providerID: \.id,
            providerName: \.providerName)
        let selectedProviders = QuotaKitWidgetProviderPreferencesStore.moveSelectedProviderFirst(
            orderedProviders,
            preferences: preferences,
            providerID: \.id)
        return QuotaKitWidgetSnapshot(
            schemaVersion: self.schemaVersion,
            generatedAt: self.generatedAt,
            lastSyncedAt: self.lastSyncedAt,
            providers: selectedProviders)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case lastSyncedAt
        case providers
    }
}

enum QuotaKitWidgetSnapshotBuilder {
    static func makeSnapshot(
        from snapshot: SyncedUsageSnapshot,
        generatedAt: Date = Date(),
        providerPreferences: QuotaKitWidgetProviderPreferences = QuotaKitWidgetProviderPreferencesStore.load())
        -> QuotaKitWidgetSnapshot
    {
        let snapshotProviders = snapshot.providers
            .sorted {
                if $0.lastUpdated != $1.lastUpdated {
                    return $0.lastUpdated > $1.lastUpdated
                }
                return $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending
            }
            .map { Self.makeProvider($0) }
        let orderedProviders = QuotaKitWidgetProviderPreferencesStore.orderedItems(
            snapshotProviders,
            preferences: providerPreferences,
            providerID: \.id,
            providerName: \.providerName)
        let providers = QuotaKitWidgetProviderPreferencesStore.moveSelectedProviderFirst(
            orderedProviders,
            preferences: providerPreferences,
            providerID: \.id)

        return QuotaKitWidgetSnapshot(
            generatedAt: generatedAt,
            lastSyncedAt: snapshot.syncTimestamp,
            providers: providers)
    }

    private static func makeProvider(
        _ provider: ProviderUsageSnapshot) -> QuotaKitWidgetSnapshot.Provider
    {
        QuotaKitWidgetSnapshot.Provider(
            id: provider.providerID,
            providerName: provider.providerName,
            lastUpdated: provider.lastUpdated,
            statusMessage: self.sanitizedStatusMessage(provider.statusMessage),
            isError: provider.isError,
            windows: provider.allRateWindows.prefix(3).map { window in
                QuotaKitWidgetSnapshot.Provider.Window(
                    title: window.label ?? String(localized: "Quota"),
                    usedPercent: window.usedPercent,
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt,
                    pace: window.pace,
                    identity: window.identity ?? self.legacyIdentity(for: window))
            })
    }

    private static func legacyIdentity(for window: SyncRateWindow) -> SyncRateWindowIdentity? {
        guard let title = window.label?.localizedLowercase else { return nil }
        if title.contains("session")
            || title.contains("hour")
            || title.contains(String(localized: "Session").localizedLowercase)
        {
            return .session
        }
        if title.contains("week")
            || title.contains(String(localized: "Weekly").localizedLowercase)
            || Self.hasWeeklyDayCountLabel(title)
        {
            return .weekly
        }
        return nil
    }

    /// Day-count titles only mean "weekly" near seven days; "1 day" (daily)
    /// and "30 days" (monthly) windows must not claim the weekly lane.
    private static let weeklyDayCountRange = 5...9

    private static func hasWeeklyDayCountLabel(_ title: String) -> Bool {
        self.numericDayCount(in: title).map(self.weeklyDayCountRange.contains) ?? false
    }

    private static func numericDayCount(in title: String) -> Int? {
        let normalized = title
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let tokens = normalized.split { character in
            !character.isLetter && !character.isNumber
        }

        var previousToken: Substring?
        for token in tokens {
            let tokenText = String(token)
            if tokenText == "day" || tokenText == "days",
               previousToken?.allSatisfy(\.isNumber) == true,
               let count = previousToken.flatMap({ Int($0) })
            {
                return count
            }

            if tokenText.hasSuffix("day") {
                let prefix = tokenText.dropLast(3)
                if !prefix.isEmpty,
                   prefix.allSatisfy(\.isNumber),
                   let count = Int(prefix)
                {
                    return count
                }
            }

            if tokenText.hasSuffix("days") {
                let prefix = tokenText.dropLast(4)
                if !prefix.isEmpty,
                   prefix.allSatisfy(\.isNumber),
                   let count = Int(prefix)
                {
                    return count
                }
            }

            previousToken = token
        }
        return nil
    }

    private static func sanitizedStatusMessage(_ message: String?) -> String? {
        guard let message, !message.isEmpty else { return nil }

        if message.range(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            options: [.regularExpression, .caseInsensitive]) != nil
        {
            return nil
        }

        let lower = message.lowercased()
        let blocked = ["accountemail", "accesstoken", "refreshtoken", "apikey", "cookie"]
        if blocked.contains(where: { lower.contains($0) }) {
            return nil
        }

        return message
    }
}

enum QuotaKitWidgetTimelineSchedule {
    static let refreshInterval: TimeInterval = 15 * 60
    static let staleThreshold: TimeInterval = 60 * 60

    static func nextRefreshDate(after date: Date, lastSyncedAt: Date?) -> Date {
        let regularRefresh = date.addingTimeInterval(Self.refreshInterval)
        guard let lastSyncedAt else {
            return regularRefresh
        }

        let staleTransition = lastSyncedAt.addingTimeInterval(Self.staleThreshold + 1)
        guard staleTransition > date, staleTransition < regularRefresh else {
            return regularRefresh
        }
        return staleTransition
    }
}

enum QuotaKitWidgetSnapshotStore {
    static let filename = "quotakit-widget-snapshot.json"

    private static let logger = Logger(
        subsystem: ProductConfig.logSubsystem,
        category: "WidgetSnapshotStore")

    static func load(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier) -> QuotaKitWidgetSnapshot?
    {
        guard let url = snapshotURL(
            fileManager: fileManager,
            appGroupIdentifier: appGroupIdentifier),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? Self.decoder.decode(QuotaKitWidgetSnapshot.self, from: data)
    }

    static func save(
        _ snapshot: QuotaKitWidgetSnapshot,
        fileManager: FileManager = .default,
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier)
    {
        guard let url = snapshotURL(
            fileManager: fileManager,
            appGroupIdentifier: appGroupIdentifier)
        else {
            self.logger.error("Widget snapshot save failed: app group container unavailable")
            return
        }
        Self.write(snapshot, to: url, fileManager: fileManager)
    }

    static func clear(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier)
    {
        guard let url = snapshotURL(
            fileManager: fileManager,
            appGroupIdentifier: appGroupIdentifier)
        else {
            return
        }
        Self.removeItem(at: url, fileManager: fileManager)
    }

    static func snapshotURL(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier) -> URL?
    {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(self.filename, isDirectory: false)
    }

    private static func write(
        _ snapshot: QuotaKitWidgetSnapshot,
        to url: URL,
        fileManager: FileManager)
    {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try Self.encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            self.logger.error("Widget snapshot save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func removeItem(at url: URL, fileManager: FileManager) {
        do {
            try fileManager.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 4 {
            return
        } catch {
            Self.logger.error("Widget snapshot clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var encoder: JSONEncoder {
        CloudSyncConstants.makeJSONEncoder()
    }

    private static var decoder: JSONDecoder {
        CloudSyncConstants.makeJSONDecoder()
    }
}

#if DEBUG
extension QuotaKitWidgetSnapshotStore {
    static func saveForTesting(
        _ snapshot: QuotaKitWidgetSnapshot,
        at directory: URL,
        fileManager: FileManager = .default)
    {
        let url = directory.appendingPathComponent(Self.filename, isDirectory: false)
        Self.write(snapshot, to: url, fileManager: fileManager)
    }

    static func loadForTesting(
        at directory: URL,
        fileManager: FileManager = .default) -> QuotaKitWidgetSnapshot?
    {
        let url = directory.appendingPathComponent(Self.filename, isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(QuotaKitWidgetSnapshot.self, from: data)
    }

    static func clearForTesting(
        at directory: URL,
        fileManager: FileManager = .default)
    {
        let url = directory.appendingPathComponent(Self.filename, isDirectory: false)
        Self.removeItem(at: url, fileManager: fileManager)
    }
}
#endif
