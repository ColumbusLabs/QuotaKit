import CodexBarCore
import Foundation
import Testing

struct OpenCodexRouteDispatcherTests {
    @Test(arguments: [
        ("openai", OpenCodexRouteTarget.subscription(.codex)),
        ("opencode-go", OpenCodexRouteTarget.subscription(.opencodego)),
        ("kimi-coding", OpenCodexRouteTarget.subscription(.kimi)),
        ("deepseek", OpenCodexRouteTarget.subscription(.deepseek)),
        ("opencode-free", OpenCodexRouteTarget.tokenOnly),
        ("unknown-vendor", OpenCodexRouteTarget.unknown),
    ])
    func `provider routes to the expected subscription target`(
        provider: String,
        expected: OpenCodexRouteTarget)
    {
        #expect(OpenCodexRouteDispatcher.route(provider: provider) == expected)
    }

    @Test(arguments: [
        ("gpt-5.6-sol", true),
        ("openai/gpt-5.6-sol", true),
        ("opencode-go/deepseek-v4-flash", false),
        ("kimi-coding/k2p5", false),
    ])
    func `codex subscription attribution respects model route prefixes`(
        modelName: String,
        expected: Bool)
    {
        #expect(OpenCodexRouteDispatcher.countsTowardCodexSubscription(modelName: modelName) == expected)
    }

    @Test
    func `model prefix wins over a mismatched provider label`() {
        #expect(
            OpenCodexRouteDispatcher.route(
                provider: "openai",
                modelName: "opencode-go/deepseek-v4-flash") == .subscription(.opencodego))
        #expect(
            OpenCodexRouteDispatcher.route(
                provider: "opencode-go",
                modelName: "gpt-5.2") == .subscription(.opencodego))
    }

    @Test
    func `router model namespace does not replace recorded provider`() {
        #expect(
            OpenCodexRouteDispatcher.route(
                provider: "openrouter",
                modelName: "openai/gpt-5.4") == .unknown)
        #expect(
            OpenCodexRouteDispatcher.route(
                provider: "openai",
                modelName: "opencode-go/gpt-5.4") == .subscription(.opencodego))
    }

    @Test
    func `missing provider retains legacy model route fallback`() {
        #expect(
            OpenCodexRouteDispatcher.route(
                provider: "  ",
                modelName: "gpt-5.4") == .subscription(.codex))
        #expect(
            OpenCodexRouteDispatcher.route(
                provider: "  ",
                modelName: "opencode-go/gpt-5.4") == .subscription(.opencodego))
    }
}
