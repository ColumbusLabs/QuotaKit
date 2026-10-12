import LiteCore
import Testing

struct ActivityRootsTests {
    private static let home = "/Users/test"

    private static func roots(_ environment: [String: String] = [:]) -> ActivityRoots {
        ActivityRoots(homeDirectory: self.home, environment: environment)
    }

    @Test
    func `default paths cover the five 068 section 5.1 locations`() {
        let roots = Self.roots()

        #expect(roots.watchPaths == [
            "/Users/test/.claude",
            "/Users/test/.codex",
            "/Users/test/.gemini/antigravity",
        ])
    }

    @Test
    func `session logs map to their provider at any depth`() {
        let roots = Self.roots()

        #expect(roots.provider(forEventPath: "/Users/test/.claude/projects/-Users-test-app") == .claude)
        #expect(roots.provider(forEventPath: "/Users/test/.codex/sessions/2026/10/11/") == .codex)
        #expect(roots.provider(forEventPath: "/Users/test/.gemini/antigravity/brain/abc") == .antigravity)
    }

    @Test
    func `a credential write maps through its directory`() {
        let roots = Self.roots()

        #expect(roots.provider(forEventPath: "/Users/test/.claude") == .claude)
        #expect(roots.provider(forEventPath: "/Users/test/.codex/") == .codex)
    }

    @Test
    func `other subdirectories of a credential directory are ignored`() {
        let roots = Self.roots()

        #expect(roots.provider(forEventPath: "/Users/test/.claude/statsig") == nil)
        #expect(roots.provider(forEventPath: "/Users/test/.codex/log") == nil)
    }

    @Test
    func `paths that merely share a prefix are ignored`() {
        let roots = Self.roots()

        #expect(roots.provider(forEventPath: "/Users/test/.claude-other/projects") == nil)
        #expect(roots.provider(forEventPath: "/Users/test/.codex/sessions-old") == nil)
        #expect(roots.provider(forEventPath: "/Users/test") == nil)
    }

    @Test
    func `CODEX_HOME moves the Codex roots`() {
        let roots = Self.roots(["CODEX_HOME": "/data/codex/"])

        #expect(roots.watchPaths.contains("/data/codex"))
        #expect(roots.provider(forEventPath: "/data/codex") == .codex)
        #expect(roots.provider(forEventPath: "/data/codex/sessions/2026") == .codex)
        #expect(roots.provider(forEventPath: "/Users/test/.codex/sessions/2026") == nil)
    }

    @Test
    func `CLAUDE_CONFIG_DIR moves the Claude roots and expands a tilde`() {
        let roots = Self.roots(["CLAUDE_CONFIG_DIR": "~/work/claude"])

        #expect(roots.provider(forEventPath: "/Users/test/work/claude") == .claude)
        #expect(roots.provider(forEventPath: "/Users/test/work/claude/projects/x") == .claude)
        #expect(roots.provider(forEventPath: "/Users/test/.claude/projects/x") == nil)
    }

    @Test
    func `blank environment values fall back to the defaults`() {
        let roots = Self.roots(["CODEX_HOME": "  ", "CLAUDE_CONFIG_DIR": ""])

        #expect(roots.provider(forEventPath: "/Users/test/.codex/sessions/x") == .codex)
        #expect(roots.provider(forEventPath: "/Users/test/.claude") == .claude)
    }

    @Test
    func `roots are resolved before matching`() {
        let roots = ActivityRoots(
            homeDirectory: Self.home,
            resolve: { $0.replacingOccurrences(of: "/Users/test/.claude", with: "/dotfiles/claude") })

        #expect(roots.watchPaths.contains("/dotfiles/claude"))
        #expect(roots.provider(forEventPath: "/dotfiles/claude/projects/x") == .claude)
        #expect(roots.provider(forEventPath: "/Users/test/.claude/projects/x") == nil)
    }

    @Test
    func `a batch of event paths reports each provider once, in order`() {
        let roots = Self.roots()

        let providers = roots.providers(forEventPaths: [
            "/Users/test/.codex/sessions/a",
            "/Users/test/.claude/projects/a",
            "/Users/test/.claude/projects/b",
            "/elsewhere",
        ])

        #expect(providers == [.claude, .codex])
    }
}
