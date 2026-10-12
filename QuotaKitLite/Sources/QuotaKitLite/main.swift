import AppKit
import Foundation

// Diagnostic: run one Claude CLI login refresh (068 §4.1) and print whether Claude Code rewrote its Keychain item.
if CommandLine.arguments.contains("--check-claude-cli-refresh") {
    let started = Date()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        var refresher = ClaudeCLIRefresher(keychainMetadata: ClaudeKeychainMetadataReader())
        if let seconds = ProcessInfo.processInfo.environment["LITE_CLAUDE_CLI_TIMEOUT"].flatMap(TimeInterval.init) {
            refresher.timeout = seconds
        }
        let refreshed = await refresher.refresh()
        print("refreshed: \(refreshed) after \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        done.signal()
    }
    done.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
