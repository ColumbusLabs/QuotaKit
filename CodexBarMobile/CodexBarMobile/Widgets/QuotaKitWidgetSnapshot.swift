import CodexBarSync
import Foundation
import os

struct QuotaKitWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    struct Provider: Codable, Equatable, Identifiable, Sendable {
        struct Window: Codable, Equatable, Sendable {
            let title: String
            let usedPercent: Double
            let remainingPercent: Double
            let resetsAt: Date?
            let pace: SyncUsagePace?
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
    let providers: [Provider]

    init(
        schemaVersion: Int = QuotaKitWidgetSnapshot.currentSchemaVersion,
        generatedAt: Date,
        providers: [Provider])
    {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.providers = try container.decode([Provider].self, forKey: .providers)
    }

    var primaryProvider: Provider? {
        self.providers.first
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case providers
    }
}

enum QuotaKitWidgetSnapshotBuilder {
    static func makeSnapshot(
        from snapshot: SyncedUsageSnapshot,
        generatedAt: Date = Date()) -> QuotaKitWidgetSnapshot
    {
        let providers = snapshot.providers
            .sorted {
                if $0.lastUpdated != $1.lastUpdated {
                    return $0.lastUpdated > $1.lastUpdated
                }
                return $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending
            }
            .map { Self.makeProvider($0) }

        return QuotaKitWidgetSnapshot(
            generatedAt: generatedAt,
            providers: providers)
    }

    private static func makeProvider(
        _ provider: ProviderUsageSnapshot) -> QuotaKitWidgetSnapshot.Provider
    {
        QuotaKitWidgetSnapshot.Provider(
            id: provider.providerID,
            providerName: provider.providerName,
            lastUpdated: provider.lastUpdated,
            statusMessage: Self.sanitizedStatusMessage(provider.statusMessage),
            isError: provider.isError,
            windows: provider.allRateWindows.prefix(3).map { window in
                QuotaKitWidgetSnapshot.Provider.Window(
                    title: window.label ?? String(localized: "Quota"),
                    usedPercent: window.usedPercent,
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt,
                    pace: window.pace)
            })
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

enum QuotaKitWidgetSnapshotStore {
    static let filename = "quotakit-widget-snapshot.json"

    private static let logger = Logger(
        subsystem: ProductConfig.logSubsystem,
        category: "WidgetSnapshotStore")

    static func load(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier) -> QuotaKitWidgetSnapshot?
    {
        guard let url = Self.snapshotURL(
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
        guard let url = Self.snapshotURL(
            fileManager: fileManager,
            appGroupIdentifier: appGroupIdentifier)
        else {
            Self.logger.error("Widget snapshot save failed: app group container unavailable")
            return
        }
        Self.write(snapshot, to: url, fileManager: fileManager)
    }

    static func clear(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = ProductConfig.appGroupIdentifier)
    {
        guard let url = Self.snapshotURL(
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
            .appendingPathComponent(Self.filename, isDirectory: false)
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
            Self.logger.error("Widget snapshot save failed: \(error.localizedDescription, privacy: .public)")
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
