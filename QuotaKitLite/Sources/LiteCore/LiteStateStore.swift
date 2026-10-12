import Foundation

/// Persists provider state as one JSON file in Application Support, so a relaunch shows the last known
/// numbers immediately (068 §13 S2).
public struct LiteStateStore: Sendable {
    /// Bump when the file format changes incompatibly; older files are then ignored.
    static let formatVersion = 1

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/QuotaKit Lite/state.json`
    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("QuotaKit Lite", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    /// The saved states, or none when the file is missing, unreadable, or from another format version.
    public func load() -> [ProviderState] {
        guard let data = try? Data(contentsOf: self.fileURL),
              let file = try? Self.decoder.decode(StateFile.self, from: data),
              file.version == Self.formatVersion
        else { return [] }
        return file.providers
    }

    /// Writes the states atomically. Returns false, without touching the disk, when the file already
    /// holds exactly these states.
    @discardableResult
    public func save(_ providers: [ProviderState]) throws -> Bool {
        let data = try Self.encoder.encode(StateFile(version: Self.formatVersion, providers: providers))
        if let existing = try? Data(contentsOf: self.fileURL), existing == data {
            return false
        }
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: self.fileURL, options: .atomic)
        return true
    }

    private struct StateFile: Codable {
        let version: Int
        let providers: [ProviderState]
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Default (numeric) dates round-trip exactly; ISO 8601 would drop fractional seconds.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}
