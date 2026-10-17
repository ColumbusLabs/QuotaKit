import Foundation

/// The external tool QuotaKit runs to list Claude accounts.
///
/// Each source prints claude-swap's list schema v1, so one parser and projection serve them all; a source fixes
/// the argument array, account identity prefix and label shown on cards.
public enum ClaudeSwapAccountSource: String, CaseIterable, Sendable {
    /// claude-swap (`cswap --list --json`), github.com/realiti4/claude-swap.
    case claudeSwap = "claude-swap"
    /// tcr (`tcr list --json`), the teamclaude-rs pooling proxy. tcr routes each request to a pooled account,
    /// so its list reports no active account and `supportsAccountSwitching: false`.
    case tcr

    /// Identity prefix (`<source>:<slot>`) and card label.
    public var label: String {
        self.rawValue
    }

    /// Fixed list arguments. This is never a shell command or a config-defined argument list.
    public var listArguments: [String] {
        switch self {
        case .claudeSwap: ["--list", "--json"]
        case .tcr: ["list", "--json"]
        }
    }

    public init?(identitySource: String) {
        self.init(rawValue: identitySource)
    }
}
