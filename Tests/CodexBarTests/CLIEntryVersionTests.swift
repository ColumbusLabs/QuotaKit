import CodexBarCore
import Commander
import Foundation
import XCTest
@testable import CodexBarCLI

extension CLIEntryTests {
    func test_decodesFormatFromOptionsAndFlags() {
        let jsonOption = ParsedValues(positional: [], options: ["format": ["json"]], flags: [])
        XCTAssertEqual(CodexBarCLI._decodeFormatForTesting(from: jsonOption), .json)

        let jsonFlag = ParsedValues(positional: [], options: [:], flags: ["json"])
        XCTAssertEqual(CodexBarCLI._decodeFormatForTesting(from: jsonFlag), .json)

        let textDefault = ParsedValues(positional: [], options: [:], flags: [])
        XCTAssertEqual(CodexBarCLI._decodeFormatForTesting(from: textDefault), .text)
    }

    func test_providerSelectionPrefersOverride() {
        let selection = CodexBarCLI.providerSelection(rawOverride: "codex", enabled: [.claude, .gemini])
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

    func test_containingAppVersionTerminatesOutsideAppBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cli-version-noapp-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        let executableURL = binURL.appendingPathComponent("CodexBarCLI")
        try Data().write(to: executableURL)

        XCTAssertNil(CodexBarCLI.containingAppVersion(for: executableURL))
        XCTAssertNil(CodexBarCLI.containingAppVersion(for: URL(fileURLWithPath: "/")))
    }

    func test_nextAncestorRejectsNonDecreasingParents() {
        let current = URL(fileURLWithPath: "/synthetic/current")
        let candidates = [
            URL(fileURLWithPath: "/distinct/sibling"),
            URL(fileURLWithPath: "/synthetic/current/child"),
        ]

        for candidate in candidates {
            var calls = 0
            let ancestor = CodexBarCLI.nextAncestor(from: current) { _ in
                calls += 1
                return candidate
            }

            XCTAssertNil(ancestor)
            XCTAssertEqual(calls, 1)
        }
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

    static var cliExecutableURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/CodexBarCLI")
    }
}
