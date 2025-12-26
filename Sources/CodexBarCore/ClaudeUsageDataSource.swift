import Foundation

public enum ClaudeUsageDataSource: String, CaseIterable, Identifiable, Sendable {
    case oauth
    case web
    case cli

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .oauth: "OAuth API"
        case .web: "Web API (cookies)"
        case .cli: "CLI (PTY)"
        }
    }
}
