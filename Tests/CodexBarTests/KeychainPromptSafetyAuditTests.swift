import Foundation
import Testing

struct KeychainPromptSafetyAuditTests {
    @Test
    func `agent instructions forbid keychain prompt validation`() throws {
        let agents = try Self.readRepoFile("AGENTS.md")

        #expect(agents.contains("Never run tests/checks or ad-hoc validation that can display macOS Keychain prompts"))
        #expect(agents.contains("use parser tests, stubs, test stores, or `KeychainNoUIQuery`"))
    }

    @Test
    func `live TTY integration tests are opt in`() throws {
        let ttyTests = try Self.readRepoFile("Tests/CodexBarTests/TTYIntegrationTests.swift")

        #expect(ttyTests.contains("LIVE_CODEX_TTY"))
        #expect(ttyTests.contains("LIVE_CLAUDE_TTY"))
        #expect(ttyTests.contains("guard ProcessInfo.processInfo.environment[\"LIVE_CODEX_TTY\"] == \"1\""))
        #expect(ttyTests.contains("guard ProcessInfo.processInfo.environment[\"LIVE_CLAUDE_TTY\"] == \"1\""))
    }

    @Test
    func `interactive keychain prompt test paths use test doubles`() throws {
        let promptLiteral = "allowKeychainPrompt: true"
        let testFiles = try Self.swiftTestFiles(excludingSelf: true)
        let promptCallSites = try testFiles.flatMap { file in
            try Self.lines(in: file)
                .enumerated()
                .filter { _, line in line.contains(promptLiteral) }
                .map { lineNumber, _ in PromptCallSite(file: file, lineNumber: lineNumber + 1) }
        }

        #expect(promptCallSites.isEmpty == false)
        for callSite in promptCallSites {
            let lines = try Self.lines(in: callSite.file)
            let usesScopedKeychainDouble = Self.hasOpenKeychainTestDouble(lines: lines, before: callSite.lineNumber)
            let failureMessage = "\(callSite.file.path):\(callSite.lineNumber) has \(promptLiteral) "
                + "without an enclosing keychain test double"
            #expect(usesScopedKeychainDouble, "\(failureMessage)")
        }
    }

    @Test
    func `tests do not call SecItemCopyMatching except no UI query coverage`() throws {
        let offenders = try Self.swiftTestFiles().filter { file in
            let text = try Self.readFile(file)
            return text.contains("SecItemCopyMatching")
                && !file.path.hasSuffix("Tests/CodexBarTests/KeychainNoUIQueryTests.swift")
                && !file.path.hasSuffix("Tests/CodexBarTests/KeychainPromptSafetyAuditTests.swift")
        }

        #expect(offenders.isEmpty, "Unexpected direct SecItemCopyMatching in tests: \(offenders.map(\.path))")
    }

    @Test
    func `legacy migration stores read and delete with no UI keychain queries`() throws {
        let files = [
            "Sources/CodexBar/CookieHeaderStore.swift",
            "Sources/CodexBar/CopilotTokenStore.swift",
            "Sources/CodexBar/KimiK2TokenStore.swift",
            "Sources/CodexBar/KimiTokenStore.swift",
            "Sources/CodexBar/MiniMaxAPITokenStore.swift",
            "Sources/CodexBar/MiniMaxCookieStore.swift",
            "Sources/CodexBar/SyntheticTokenStore.swift",
            "Sources/CodexBar/ZaiTokenStore.swift",
        ]

        for file in files {
            let lines = try Self.readRepoFile(file).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated()
                where line.contains("SecItemCopyMatching") || line.contains("SecItemDelete")
            {
                let window = Self.window(lines: lines, endingAt: index, maxDistance: 8)
                #expect(
                    window.contains("KeychainNoUIQuery.apply"),
                    "\(file):\(index + 1) must apply KeychainNoUIQuery before \(line)")
                #expect(
                    !window.contains("KeychainPromptHandler"),
                    "\(file):\(index + 1) must not show a pre-alert before legacy migration reads")
            }
        }
    }

    @Test
    func `keychain migration injected security client remains no UI`() throws {
        let migration = try Self.readRepoFile("Sources/CodexBar/KeychainMigration.swift")

        #expect(migration.contains("KeychainNoUIQuery.apply(to: &query)\n\n        let status = client.copyMatching"))
        #expect(migration
            .contains("KeychainNoUIQuery.apply(to: &updateQuery)\n\n        let attributes: [String: Any]"))
        #expect(migration.contains("let updateStatus = client.update(updateQuery, attributes)"))
        #expect(!migration.contains("SecItemDelete"))
        #expect(!migration.contains("SecItemAdd"))
    }

    @Test
    func `claude background startup prompt bootstrap is explicitly gated`() throws {
        let fetcher = try Self.readRepoFile("Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift")
        let descriptor = try Self.readRepoFile(
            "Sources/CodexBarCore/Providers/Claude/ClaudeProviderDescriptor.swift")
        let credentialsStore = try Self.readRepoFile(
            "Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift")
        let securityCLIReader = try Self.readRepoFile(
            "Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials+SecurityCLIReader.swift")

        #expect(fetcher.contains("guard self.fetcher.allowStartupBootstrapPrompt else { return false }"))
        #expect(fetcher.contains("guard !hasCache else { return false }"))
        #expect(fetcher.contains("securityFrameworkFallbackMode() == .onlyOnUserAction"))
        #expect(fetcher.contains("guard policy.interaction == .background else { return false }"))
        #expect(fetcher.contains("return ProviderRefreshContext.current == .startup"))
        #expect(descriptor.contains("allowStartupBootstrapPrompt: context.runtime == .app &&"))
        #expect(descriptor.contains("(context.sourceMode == .auto || context.sourceMode == .oauth)"))
        #expect(credentialsStore.contains("@TaskLocal static var allowBackgroundPromptBootstrap: Bool = false"))
        #expect(securityCLIReader.contains("guard interaction == .userInitiated else"))
    }

    @Test
    func `alibaba safe storage password read uses no UI query`() throws {
        let importer = try Self.readRepoFile(
            "Sources/CodexBarCore/Providers/Alibaba/AlibabaCodingPlanCookieImporter.swift")
        let lines = importer.split(separator: "\n", omittingEmptySubsequences: false)
        guard let readIndex = lines.firstIndex(where: { $0.contains("SecItemCopyMatching") }) else {
            Issue.record("Expected Alibaba importer to contain a Safe Storage keychain read")
            return
        }

        let window = Self.window(lines: lines, endingAt: readIndex, maxDistance: 8)
        #expect(window.contains("KeychainNoUIQuery.apply"))
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func readRepoFile(_ relativePath: String) throws -> String {
        try self.readFile(self.repoRoot().appendingPathComponent(relativePath))
    }

    private static func readFile(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private static func lines(in url: URL) throws -> [Substring] {
        try self.readFile(url).split(separator: "\n", omittingEmptySubsequences: false)
    }

    private static func swiftTestFiles(excludingSelf: Bool = false) throws -> [URL] {
        let testsRoot = self.repoRoot().appendingPathComponent("Tests/CodexBarTests", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: testsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                if excludingSelf, file.path.hasSuffix("Tests/CodexBarTests/KeychainPromptSafetyAuditTests.swift") {
                    continue
                }
                files.append(file)
            }
        }
        return files
    }

    private static func window(lines: [Substring], endingAt index: Int, maxDistance: Int) -> String {
        let start = max(0, index - maxDistance)
        return lines[start...index].joined(separator: "\n")
    }

    private static func hasOpenKeychainTestDouble(lines: [Substring], before oneBasedLineNumber: Int) -> Bool {
        let helperNames = [
            "withClaudeKeychainOverridesForTesting",
            "withSecurityCLIReadOverrideForTesting",
            "KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting",
        ]
        let targetIndex = oneBasedLineNumber - 1
        let lineRange = lines.indices.prefix(through: targetIndex)
        return lineRange.contains { index in
            helperNames.contains { lines[index].contains($0) }
                && self.hasOpenBraceScope(lines: lines, from: index, through: targetIndex)
        }
    }

    private static func hasOpenBraceScope(lines: [Substring], from startIndex: Int, through endIndex: Int) -> Bool {
        var balance = 0
        var sawOpeningBrace = false
        for line in lines[startIndex...endIndex] {
            for character in line {
                switch character {
                case "{":
                    balance += 1
                    sawOpeningBrace = true
                case "}":
                    balance -= 1
                default:
                    continue
                }
            }
        }
        return sawOpeningBrace && balance > 0
    }

    private struct PromptCallSite {
        let file: URL
        let lineNumber: Int
    }
}
