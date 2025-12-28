import Foundation

public struct ProviderSettingsSnapshot: Sendable {
    public struct CodexProviderSettings: Sendable {
        public let usageDataSource: CodexUsageDataSource

        public init(usageDataSource: CodexUsageDataSource) {
            self.usageDataSource = usageDataSource
        }
    }

    public struct ClaudeProviderSettings: Sendable {
        public let usageDataSource: ClaudeUsageDataSource
        public let webExtrasEnabled: Bool

        public init(usageDataSource: ClaudeUsageDataSource, webExtrasEnabled: Bool) {
            self.usageDataSource = usageDataSource
            self.webExtrasEnabled = webExtrasEnabled
        }
    }

    public struct ZaiProviderSettings: Sendable {
        public init() {}
    }

    public struct CopilotProviderSettings: Sendable {
        public init() {}
    }

    public let debugMenuEnabled: Bool
    public let codex: CodexProviderSettings?
    public let claude: ClaudeProviderSettings?
    public let zai: ZaiProviderSettings?
    public let copilot: CopilotProviderSettings?

    public init(
        debugMenuEnabled: Bool,
        codex: CodexProviderSettings?,
        claude: ClaudeProviderSettings?,
        zai: ZaiProviderSettings?,
        copilot: CopilotProviderSettings?)
    {
        self.debugMenuEnabled = debugMenuEnabled
        self.codex = codex
        self.claude = claude
        self.zai = zai
        self.copilot = copilot
    }
}
