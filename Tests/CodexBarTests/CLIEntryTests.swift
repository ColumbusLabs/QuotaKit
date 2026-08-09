import CodexBarCore
import Commander
import Foundation
import XCTest
@testable import CodexBarCLI

final class CLIEntryTests: XCTestCase {
    func test_effectiveArgvDefaultsToUsage() {
        XCTAssertEqual(CodexBarCLI.effectiveArgv([]), ["usage"])
        XCTAssertEqual(CodexBarCLI.effectiveArgv(["--json"]), ["usage", "--json"])
        XCTAssertEqual(CodexBarCLI.effectiveArgv(["usage", "--json"]), ["usage", "--json"])
    }

    func test_rootHelpAdvertisesDashboardSnapshotCommand() {
        let help = CodexBarCLI.rootHelp(version: "0.0.0")

        XCTAssertTrue(help.contains("quotakit dashboard [--pretty] [--timeout <seconds>]"))
        XCTAssertTrue(help.contains("[--identity <redacted|full>] [--output <path>]"))
    }

    func test_dashboardCommandIsRegisteredAndParsesOptions() throws {
        let program = Program(descriptors: CodexBarCLI.commandDescriptors())
        let invocation = try program.resolve(
            argv: ["dashboard", "--pretty", "--timeout", "45", "--output", "/tmp/snapshot.json"])

        XCTAssertEqual(invocation.path, ["dashboard"])
        XCTAssertTrue(invocation.parsedValues.flags.contains("pretty"))
        XCTAssertEqual(invocation.parsedValues.options["timeout"], ["45"])
        XCTAssertEqual(invocation.parsedValues.options["output"], ["/tmp/snapshot.json"])
    }

    func test_dashboardTimeoutIsBoundedAndCanBeDisabled() {
        XCTAssertEqual(
            CodexBarCLI.decodeDashboardTimeout(from: ParsedValues(positional: [], options: [:], flags: [])),
            30)
        XCTAssertEqual(
            CodexBarCLI.decodeDashboardTimeout(
                from: ParsedValues(positional: [], options: ["timeout": ["0"]], flags: [])),
            0)
        XCTAssertEqual(
            CodexBarCLI.decodeDashboardTimeout(
                from: ParsedValues(positional: [], options: ["timeout": ["86400"]], flags: [])),
            86400)

        for value in ["-1", "nan", "inf", "86401"] {
            XCTAssertNil(CodexBarCLI.decodeDashboardTimeout(
                from: ParsedValues(positional: [], options: ["timeout": [value]], flags: [])))
        }
    }

    func test_dashboardCommanderErrorsStayOffStdout() throws {
        let result = try Self.runCLI(arguments: ["dashboard", "--json"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertFalse(result.stderr.isEmpty)
    }

    func test_dashboardCommandPrintsOneSnapshotAndExits() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-dashboard-command-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var config = CodexBarConfig.makeDefault()
        config.providers = config.providers.map { provider in
            var disabled = provider
            disabled.enabled = false
            return disabled
        }
        let configURL = root.appendingPathComponent("config.json")
        try CodexBarConfigStore(fileURL: configURL).save(config)

        let result = try Self.runCLI(
            arguments: ["dashboard"],
            environment: [CodexBarConfigStore.pathEnvironmentKey: configURL.path])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.last, 0x0A)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        let providers = try XCTUnwrap(object["providers"] as? [[String: Any]])
        XCTAssertTrue(providers.isEmpty)
        let host = try XCTUnwrap(object["host"] as? [String: Any])
        XCTAssertEqual(host["refreshIntervalSeconds"] as? Int, 0)
    }

    func test_dashboardOutputWritesSnapshotFileAndKeepsStdoutSilent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-dashboard-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var config = CodexBarConfig.makeDefault()
        config.providers = config.providers.map { provider in
            var disabled = provider
            disabled.enabled = false
            return disabled
        }
        let configURL = root.appendingPathComponent("config.json")
        try CodexBarConfigStore(fileURL: configURL).save(config)

        let snapshotURL = root.appendingPathComponent("snapshot.json")
        // Pre-existing content must be atomically replaced, not appended to.
        try Data("stale".utf8).write(to: snapshotURL)

        let result = try Self.runCLI(
            arguments: ["dashboard", "--output", snapshotURL.path],
            environment: [CodexBarConfigStore.pathEnvironmentKey: configURL.path])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.isEmpty)

        let written = try Data(contentsOf: snapshotURL)
        XCTAssertEqual(written.last, 0x0A)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o644)

        // The staged temp file must not survive a successful publish.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains("quotakit-dashboard-") }
        XCTAssertEqual(leftovers, [])
    }

    func test_dashboardOutputRejectsEmptyPathAsArgsError() throws {
        let result = try Self.runCLI(arguments: ["dashboard", "--output", ""])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        let stderrText = try XCTUnwrap(String(bytes: result.stderr, encoding: .utf8))
        XCTAssertTrue(stderrText.contains("--output requires a non-empty file path."))
    }

    func test_dashboardAtomicWriteFailsWhenDirectoryIsMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("snapshot.json")

        XCTAssertThrowsError(
            try CodexBarCLI.writeDashboardSnapshotAtomically(Data("{}".utf8), toPath: missing.path))
        { error in
            XCTAssertTrue(error.localizedDescription.contains("does not exist"))
        }
    }

    func test_dashboardAtomicWriteReplacesExistingFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-atomic-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("snapshot.json")
        try Data("old".utf8).write(to: target)

        try CodexBarCLI.writeDashboardSnapshotAtomically(Data("new".utf8), toPath: target.path)

        XCTAssertEqual(try Data(contentsOf: target), Data("new".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o644)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["snapshot.json"])
    }

    func test_decodesFormatFromOptionsAndFlags() {
        let jsonOption = ParsedValues(positional: [], options: ["format": ["json"]], flags: [])
        XCTAssertEqual(CodexBarCLI._decodeFormatForTesting(from: jsonOption), .json)

        let jsonFlag = ParsedValues(positional: [], options: [:], flags: ["json"])
        XCTAssertEqual(CodexBarCLI._decodeFormatForTesting(from: jsonFlag), .json)

        let textDefault = ParsedValues(positional: [], options: [:], flags: [])
        XCTAssertEqual(CodexBarCLI._decodeFormatForTesting(from: textDefault), .text)
    }

    func test_providerSelectionPrefersOverride() {
        let selection = CodexBarCLI.providerSelection(rawOverride: "codex", enabled: [.claude, .grok])
        XCTAssertEqual(selection.asList, [.codex])
    }

    func test_normalizeVersionExtractsNumeric() {
        XCTAssertEqual(CodexBarCLI.normalizeVersion(raw: "codex 1.2.3 (build 4)"), "1.2.3")
        XCTAssertEqual(CodexBarCLI.normalizeVersion(raw: "  v2.0  "), "2.0")
    }

    func test_makeHeaderIncludesVersionWhenAvailable() {
        let header = CodexBarCLI.makeHeader(provider: .codex, version: "1.2.3", source: "cli")
        XCTAssertTrue(header.contains("Codex"))
        XCTAssertTrue(header.contains("1.2.3"))
        XCTAssertTrue(header.contains("cli"))
    }

    func test_cliVersionFallsBackToContainingAppBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-cli-version-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("QuotaKit.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let helpersURL = contentsURL.appendingPathComponent("Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpersURL, withIntermediateDirectories: true)

        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = ["CFBundleShortVersionString": "9.8.7"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoURL)

        let helperURL = helpersURL.appendingPathComponent("QuotaKitCLI")
        try Data().write(to: helperURL)

        XCTAssertEqual(CodexBarCLI.containingAppVersion(for: helperURL), "9.8.7")
    }

    func test_cliVersionFollowsSymlinkedHelper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-cli-version-symlink-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("QuotaKit.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let helpersURL = contentsURL.appendingPathComponent("Helpers", isDirectory: true)
        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: helpersURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let plist: [String: Any] = ["CFBundleShortVersionString": "2.4.6"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: infoURL)

        let helperURL = helpersURL.appendingPathComponent("QuotaKitCLI")
        try Data().write(to: helperURL)

        let symlinkURL = binURL.appendingPathComponent("quotakit")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: helperURL)

        XCTAssertEqual(CodexBarCLI.currentVersion(bundleVersion: nil, executablePath: symlinkURL.path), "2.4.6")
    }

    func test_cliVersionFallsBackToAdjacentVersionFile() throws {
        try self.expectAdjacentVersionFile(raw: "v3.2.1\n", expected: "3.2.1")
        try self.expectAdjacentVersionFile(raw: "3.2.2\n", expected: "3.2.2")
        try self.expectAdjacentVersionFile(raw: "version-3.2.3\n", expected: "version-3.2.3")
    }

    func test_cliVersionFindsAdjacentVersionWhenInvokedViaRelativePathAndSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-cli-version-invocation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installURL = root.appendingPathComponent("install/bin", isDirectory: true)
        let linksURL = root.appendingPathComponent("links", isDirectory: true)
        let workingDirectoryURL = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: installURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linksURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)

        let executableURL = installURL.appendingPathComponent("QuotaKitCLI")
        try FileManager.default.copyItem(at: Self.cliExecutableURL, to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try "8.7.6\n".write(
            to: installURL.appendingPathComponent("VERSION"),
            atomically: false,
            encoding: .utf8)

        XCTAssertEqual(
            try Self.runVersionCommand(
                executableURL: executableURL,
                argv0: "install/bin/QuotaKitCLI",
                currentDirectoryURL: workingDirectoryURL),
            "QuotaKit 8.7.6\n")

        let symlinkURL = linksURL.appendingPathComponent("quotakit")
        try FileManager.default.createSymbolicLink(
            atPath: symlinkURL.path,
            withDestinationPath: "../install/bin/QuotaKitCLI")
        XCTAssertEqual(
            try Self.runVersionCommand(
                executableURL: symlinkURL,
                argv0: "quotakit",
                currentDirectoryURL: workingDirectoryURL),
            "QuotaKit 8.7.6\n")
    }

    func test_cliVersionPrefersAdjacentVersionOverStandaloneBundleName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-cli-version-bundle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        let helperURL = binURL.appendingPathComponent("QuotaKitCLI")
        try Data().write(to: helperURL)
        try "4.5.6\n".write(
            to: binURL.appendingPathComponent("VERSION"),
            atomically: false,
            encoding: .utf8)

        XCTAssertEqual(
            CodexBarCLI.currentVersion(bundleVersion: "CodexBar", executablePath: helperURL.path),
            "4.5.6")
    }

    private func expectAdjacentVersionFile(raw: String, expected: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-cli-version-file-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        let helperURL = binURL.appendingPathComponent("QuotaKitCLI")
        try Data().write(to: helperURL)
        try raw.write(
            to: binURL.appendingPathComponent("VERSION"),
            atomically: false,
            encoding: .utf8)

        XCTAssertEqual(CodexBarCLI.currentVersion(bundleVersion: nil, executablePath: helperURL.path), expected)
    }

    private static func runVersionCommand(
        executableURL: URL,
        argv0: String,
        currentDirectoryURL: URL) throws -> String
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            "exec -a \"$1\" \"$2\" --version",
            "codexbar-version-test",
            argv0,
            executableURL.path,
        ]
        process.currentDirectoryURL = currentDirectoryURL
        // Spawned CLI binaries match no test-process name pattern; make the
        // keychain suppression explicit instead of relying on env inheritance.
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1"]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(bytes: errorOutput, encoding: .utf8)
                ?? "CodexBarCLI exited without an error message"
            throw NSError(domain: "CLIEntryTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
        guard let text = String(bytes: output, encoding: .utf8) else {
            throw NSError(domain: "CLIEntryTests", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "CodexBarCLI produced non-UTF-8 output",
            ])
        }
        return text
    }

    private static var cliExecutableURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/CodexBarCLI")
    }

    func test_renderOpenAIWebDashboardTextIncludesSummary() {
        let event = CreditEvent(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            service: "codex",
            creditsUsed: 10)
        let snapshot = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: 45,
            codeReviewLimit: RateWindow(
                usedPercent: 55,
                windowMinutes: nil,
                resetsAt: Date().addingTimeInterval(3600),
                resetDescription: nil),
            creditEvents: [event],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        let text = CodexBarCLI.renderOpenAIWebDashboardText(snapshot)

        XCTAssertTrue(text.contains("Web session: user@example.com"))
        XCTAssertTrue(text.contains("Code review: 45% remaining (Resets in "))
        XCTAssertTrue(text.contains("Web history: 1 events"))
    }

    func test_mapsErrorsToExitCodes() {
        XCTAssertEqual(CodexBarCLI.mapError(CodexStatusProbeError.codexNotInstalled), ExitCode(2))
        XCTAssertEqual(CodexBarCLI.mapError(CodexStatusProbeError.timedOut), ExitCode(4))
        XCTAssertEqual(CodexBarCLI.mapError(ClaudeWebFetchStrategyError.timedOut(seconds: 1)), ExitCode(4))
        XCTAssertEqual(CodexBarCLI.mapError(UsageError.noRateLimitsFound), ExitCode(3))
    }

    func test_missingCodexBinaryErrorPayloadUsesInstallGuidance() {
        let payload = CodexBarCLI.makeErrorPayload(CodexStatusProbeError.codexNotInstalled, kind: .provider)

        XCTAssertEqual(payload.code, ExitCode.binaryNotFound.rawValue)
        XCTAssertTrue(payload.message.contains("Codex CLI missing"))
        XCTAssertFalse(payload.message.contains("Codex not running"))
    }

    func test_providerSelectionFallsBackToBothForPrimaryPair() {
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: [.codex, .claude])
        switch selection {
        case .both:
            break
        default:
            XCTFail("Expected both selection")
        }
    }

    func test_providerSelectionFallsBackToCustomWhenNonPrimary() {
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: [.codex, .grok])
        switch selection {
        case let .custom(providers):
            XCTAssertEqual(providers, [.codex, .grok])
        default:
            XCTFail("Expected custom selection")
        }
    }

    func test_providerSelectionHonorsEmptyEnabledSet() {
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: [])
        switch selection {
        case let .custom(providers):
            XCTAssertEqual(providers, [])
        default:
            XCTFail("Expected empty custom selection")
        }
    }

    func test_decodesSourceAndTimeoutOptions() throws {
        let signature = CodexBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--web-timeout", "45", "--source", "oauth"])
        XCTAssertEqual(try CodexBarCLI._decodeWebTimeoutForTesting(from: parsed), 45)
        XCTAssertEqual(CodexBarCLI._decodeSourceModeForTesting(from: parsed), .oauth)
    }

    func test_rejectsUnsafeWebTimeoutOptions() throws {
        for value in ["-1", "nan", "inf", "1e300"] {
            let parsed = ParsedValues(positional: [], options: ["webTimeout": [value]], flags: [])
            XCTAssertThrowsError(try CodexBarCLI._decodeWebTimeoutForTesting(from: parsed))
        }
    }

    func test_shouldUseColorRespectsFormatAndFlags() {
        XCTAssertFalse(CodexBarCLI.shouldUseColor(noColor: true, format: .text))
        XCTAssertFalse(CodexBarCLI.shouldUseColor(noColor: false, format: .json))
    }

    func test_sourceModeRequiresWebSupportIsProviderAware() {
        XCTAssertFalse(CodexBarCLI.sourceModeRequiresWebSupport(.auto, provider: .codex))
        XCTAssertFalse(CodexBarCLI.sourceModeRequiresWebSupport(.auto, provider: .claude))
        XCTAssertTrue(CodexBarCLI.sourceModeRequiresWebSupport(.web, provider: .claude))
        XCTAssertFalse(CodexBarCLI.sourceModeRequiresWebSupport(.auto, provider: .grok))
        XCTAssertFalse(CodexBarCLI.sourceModeRequiresWebSupport(.web, provider: .grok))
        XCTAssertTrue(CodexBarCLI.sourceModeRequiresWebSupport(.auto, provider: .cursor))
        XCTAssertTrue(CodexBarCLI.sourceModeRequiresWebSupport(.web, provider: .cursor))
    }

    private static func runCLI(
        arguments: [String],
        environment: [String: String] = [:]) throws -> (status: Int32, stdout: Data, stderr: Data)

    {
        let process = Process()
        process.executableURL = Self.cliExecutableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr.fileHandleForReading.readDataToEndOfFile())
    }
}
