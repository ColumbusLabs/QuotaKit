import Foundation
import Logging

struct JSONStderrLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .info

    private let label: String
    private let encoder: JSONEncoder

    init(label: String) {
        self.label = label
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { self.metadata[metadataKey] }
        set { self.metadata[metadataKey] = newValue }
    }

    // swiftlint:disable:next function_parameter_count
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt)
    {
        let ts = Date()
        var combined = self.metadata
        if let metadata { combined.merge(metadata, uniquingKeysWith: { _, new in new }) }

        let payload = JSONLogLine(
            timestamp: ts,
            level: level.rawValue,
            label: self.label,
            message: message.description,
            source: source,
            file: file,
            function: function,
            line: line,
            metadata: combined.isEmpty ? nil : combined.mapValues(\.description))

        guard let data = try? self.encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else { return }
        fputs(text + "\n", stderr)
    }
}

private struct JSONLogLine: Encodable {
    let timestamp: Date
    let level: String
    let label: String
    let message: String
    let source: String
    let file: String
    let function: String
    let line: UInt
    let metadata: [String: String]?
}
