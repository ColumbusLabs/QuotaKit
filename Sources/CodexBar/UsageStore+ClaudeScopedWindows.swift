import CodexBarCore

extension UsageStore {
    static func isClaudeScopedWeeklyWindow(_ window: NamedRateWindow) -> Bool {
        window.usageKnown
            && window.id.hasPrefix("claude-weekly-scoped-")
            && window.window.windowMinutes == 7 * 24 * 60
    }
}
