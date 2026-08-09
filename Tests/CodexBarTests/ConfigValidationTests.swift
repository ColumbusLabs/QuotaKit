import CodexBarCore
import Foundation
import Testing

struct ConfigValidationTests {
    @Test
    func `hook configuration round trips through JSON`() throws {
        let original = CodexBarConfig(
            providers: [ProviderConfig(id: .codex)],
            hooks: HooksConfig(enabled: true, events: [
                HookRule(id: "quota", event: .quotaReached, provider: "codex", executable: "/bin/echo"),
            ]))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodexBarConfig.self, from: data)

        #expect(decoded.hooks == original.hooks)
    }

    @Test
    func `reports unsafe hook rule fields`() {
        let invalidRules = [
            HookRule(id: "duplicate", event: .quotaLow, provider: "unknown", threshold: 1.1, executable: "echo"),
            HookRule(
                id: "duplicate",
                event: .quotaReached,
                executable: "/bin/echo",
                timeoutSeconds: 301),
        ]
        let config = CodexBarConfig(
            providers: [ProviderConfig(id: .codex)],
            hooks: HooksConfig(enabled: true, events: invalidRules))
        let codes = Set(CodexBarConfigValidator.validate(config).map(\.code))

        #expect(codes.contains("invalid_hook_executable"))
        #expect(codes.contains("invalid_hook_provider"))
        #expect(codes.contains("invalid_hook_threshold"))
        #expect(codes.contains("invalid_hook_timeout"))
        #expect(codes.contains("duplicate_hook_id"))
    }

    @Test
    func `reports hook workload limits`() {
        let oversized = HookRule(
            id: String(repeating: "i", count: HookRule.maximumIDBytes + 1),
            event: .quotaReached,
            executable: "/bin/echo",
            arguments: Array(repeating: "x", count: HookRule.maximumArgumentCount + 1))
        let rules = Array(repeating: oversized, count: HooksConfig.maximumRuleCount + 1)
        let config = CodexBarConfig(providers: [], hooks: HooksConfig(enabled: true, events: rules))
        let codes = Set(CodexBarConfigValidator.validate(config).map(\.code))

        #expect(codes.contains("too_many_hook_rules"))
        #expect(codes.contains("invalid_hook_command_size"))
    }

    @Test
    func `fresh config contains exactly the supported providers`() {
        let config = CodexBarConfig.makeDefault()

        #expect(config.orderedProviders() == [.codex, .claude, .cursor, .grok])
        #expect(CodexBarConfigValidator.validate(config).isEmpty)
    }

    @Test
    func `normalization preserves unknown provider configuration and adds supported providers`() throws {
        let unknown = try #require(ProviderInstanceID(rawValue: "legacy-provider"))
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: unknown, enabled: true),
            ProviderConfig(id: .codex, enabled: false),
        ]).normalized()

        #expect(config.orderedProviders() == [unknown, .codex, .claude, .cursor, .grok])
        #expect(config.providerConfig(for: unknown)?.enabled == true)
        #expect(config.providerConfig(for: .codex)?.enabled == false)
    }

    @Test
    func `validator warns about preserved unknown provider without rejecting config`() throws {
        let data = Data("""
        {"version":1,"providers":[{"id":"legacy-provider","enabled":true}]}
        """.utf8)
        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data)
        let issue = try #require(CodexBarConfigValidator.validate(config).first)

        #expect(config.orderedProviders().map(\.rawValue) == ["legacy-provider"])
        #expect(issue.code == "unsupported_provider")
        #expect(issue.severity == .warning)
        #expect(issue.provider == nil)
        #expect(!CodexBarConfigValidator.validate(config).contains { $0.severity == .error })
    }

    @Test
    func `reports unsupported source for retained provider`() {
        var config = CodexBarConfig.makeDefault()
        config.setProviderConfig(ProviderConfig(id: .codex, source: .api))

        let codes = Set(CodexBarConfigValidator.validate(config).map(\.code))

        #expect(codes.contains("unsupported_source"))
        #expect(codes.contains("api_source_unsupported"))
    }

    @Test
    func `config store default url honors environment override`() {
        let url = CodexBarConfigStore.defaultURL(environment: [
            CodexBarConfigStore.pathEnvironmentKey: "~/tmp/codexbar-test-config.json",
        ])

        #expect(url.path.hasSuffix("/tmp/codexbar-test-config.json"))
    }

    @Test
    func `config store default url honors xdg config home`() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let xdgHome = home.appendingPathComponent("custom-config", isDirectory: true)

        let url = CodexBarConfigStore.defaultURL(
            home: home,
            environment: [
                CodexBarConfigStore.xdgConfigHomeEnvironmentKey: xdgHome.path,
            ],
            fileManager: fileManager)

        #expect(url == Self.configURL(in: xdgHome))
    }

    @Test
    func `config store default url ignores relative xdg config home`() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let legacy = Self.legacyConfigURL(in: home)
        try Self.touch(legacy, fileManager: fileManager)

        let url = CodexBarConfigStore.defaultURL(
            home: home,
            environment: [
                CodexBarConfigStore.xdgConfigHomeEnvironmentKey: "relative-config",
            ],
            fileManager: fileManager)

        #expect(url == Self.preferredConfigURL(in: home))
    }

    @Test
    func `config store default url creates in xdg default for new installs`() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }

        let url = CodexBarConfigStore.defaultURL(home: home, environment: [:], fileManager: fileManager)

        #expect(url == Self.preferredConfigURL(in: home))
    }

    @Test
    func `config store default url keeps existing legacy config`() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let legacy = Self.legacyConfigURL(in: home)
        try Self.touch(legacy, fileManager: fileManager)

        let url = CodexBarConfigStore.defaultURL(home: home, environment: [:], fileManager: fileManager)

        #expect(url == Self.preferredConfigURL(in: home))
    }

    @Test
    func `config store default url prefers existing xdg default over legacy config`() throws {
        let fileManager = FileManager.default
        let home = try Self.makeTemporaryHome()
        defer { try? fileManager.removeItem(at: home) }
        let xdgDefault = Self.configURL(in: home.appendingPathComponent(".config", isDirectory: true))
        let legacy = Self.legacyConfigURL(in: home)
        try Self.touch(legacy, fileManager: fileManager)
        try Self.touch(xdgDefault, fileManager: fileManager)

        let url = CodexBarConfigStore.defaultURL(home: home, environment: [:], fileManager: fileManager)

        #expect(url == xdgDefault)
    }

    private static func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarConfigStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func touch(_ url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private static func configURL(in directory: URL) -> URL {
        directory
            .appendingPathComponent("quotakit", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func preferredConfigURL(in home: URL) -> URL {
        home
            .appendingPathComponent(".quotakit", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func legacyConfigURL(in home: URL) -> URL {
        home
            .appendingPathComponent(".codexbar", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}
