import Testing
@testable import CodexBar

@Suite
struct UsageFetcherPATHTests {
    @Test
    func appendsDefaultsWhenMissing() {
        let seeded = UsageFetcher.seededPATH(from: [:])
        #expect(seeded.contains("/opt/homebrew/bin"))
        #expect(seeded.contains("/usr/local/bin"))
        #expect(seeded.contains("/.bun/bin"))
        #expect(seeded.contains("/.nvm/versions/node/current/bin"))
        #expect(seeded.contains("/.npm-global/bin"))
        #expect(seeded.contains("/.local/share/fnm"))
        #expect(seeded.contains("/.fnm"))
    }

    @Test
    func preservesExistingPATH() {
        let existing = "/custom/bin"
        let seeded = UsageFetcher.seededPATH(from: ["PATH": existing])
        #expect(seeded.hasPrefix(existing))
        #expect(seeded.contains("/opt/homebrew/bin"))
    }
}
