import Foundation

public enum CookieHeaderCache {
    public struct Entry: Codable, Sendable {
        public let cookieHeader: String
        public let storedAt: Date
        public let sourceLabel: String

        public init(cookieHeader: String, storedAt: Date, sourceLabel: String) {
            self.cookieHeader = cookieHeader
            self.storedAt = storedAt
            self.sourceLabel = sourceLabel
        }
    }

    private static let log = CodexBarLog.logger("cookie-cache")

    public static func load(provider: UsageProvider) -> Entry? {
        self.load(from: self.defaultURL(for: provider))
    }

    public static func store(
        provider: UsageProvider,
        cookieHeader: String,
        sourceLabel: String,
        now: Date = Date())
    {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = CookieHeaderNormalizer.normalize(trimmed), !normalized.isEmpty else {
            self.clear(provider: provider)
            return
        }
        let entry = Entry(cookieHeader: normalized, storedAt: now, sourceLabel: sourceLabel)
        self.store(entry, to: self.defaultURL(for: provider))
    }

    public static func clear(provider: UsageProvider) {
        let url = self.defaultURL(for: provider)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            if (error as NSError).code != NSFileNoSuchFileError {
                Self.log.error("Failed to remove cookie cache (\(provider.rawValue)): \(error)")
            }
        }
    }

    public static func load(from url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Entry.self, from: data)
    }

    public static func store(_ entry: Entry, to url: URL) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            try data.write(to: url, options: [.atomic])
        } catch {
            self.log.error("Failed to persist cookie cache: \(error)")
        }
    }

    private static func defaultURL(for provider: UsageProvider) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("\(provider.rawValue)-cookie.json")
    }
}
