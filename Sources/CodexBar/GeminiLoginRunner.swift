import AppKit
import CodexBarCore
import Foundation

enum GeminiLoginRunner {
    struct Result {
        enum Outcome {
            case success
            case missingBinary
            case launchFailed(String)
        }

        let outcome: Outcome
    }

    static func run() async -> Result {
        await Task(priority: .userInitiated) {
            let env = ProcessInfo.processInfo.environment
            guard let binary = BinaryLocator.resolveGeminiBinary(
                env: env,
                loginPATH: LoginShellPathCache.shared.current)
            else {
                return Result(outcome: .missingBinary)
            }

            // Create a temporary shell script that runs gemini (UUID avoids filename collisions)
            let scriptContent = """
            #!/bin/bash
            cd ~
            "\(binary)"
            """

            let tempDir = FileManager.default.temporaryDirectory
            let scriptURL = tempDir.appendingPathComponent("gemini_login_\(UUID().uuidString).command")

            do {
                try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                try await NSWorkspace.shared.open(scriptURL, configuration: config)

                // Clean up script after Terminal has time to read it
                let scriptPath = scriptURL.path
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    try? FileManager.default.removeItem(atPath: scriptPath)
                }

                return Result(outcome: .success)
            } catch {
                return Result(outcome: .launchFailed(error.localizedDescription))
            }
        }.value
    }
}
