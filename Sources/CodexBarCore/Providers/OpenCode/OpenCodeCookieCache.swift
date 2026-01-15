import Foundation

public enum OpenCodeCookieCache {
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

    private static let log = CodexBarLog.logger("opencode-cookie-cache")
    private static let filename = "opencode-cookie.json"

    public static func load() -> Entry? {
        self.load(from: self.defaultURL())
    }

    public static func store(cookieHeader: String, sourceLabel: String, now: Date = Date()) {
        let trimmed = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, CookieHeaderNormalizer.normalize(trimmed) != nil else {
            self.clear()
            return
        }
        let entry = Entry(cookieHeader: trimmed, storedAt: now, sourceLabel: sourceLabel)
        self.store(entry, to: self.defaultURL())
    }

    public static func clear() {
        let url = self.defaultURL()
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            if (error as NSError).code != NSFileNoSuchFileError {
                Self.log.error("Failed to remove OpenCode cookie cache: \(error)")
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
            Self.log.error("Failed to persist OpenCode cookie cache: \(error)")
        }
    }

    private static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent(self.filename)
    }
}
