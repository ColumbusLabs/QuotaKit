import Foundation

public enum CodexUsageDataSource: String, CaseIterable, Identifiable, Sendable {
    case oauth
    case cli

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .oauth: "OAuth API"
        case .cli: "CLI (RPC/PTY)"
        }
    }

    public var sourceLabel: String {
        switch self {
        case .oauth:
            "oauth"
        case .cli:
            "cli"
        }
    }
}
