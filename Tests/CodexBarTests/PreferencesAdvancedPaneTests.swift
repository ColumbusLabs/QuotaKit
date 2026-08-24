import Testing
@testable import CodexBar

@MainActor
struct PreferencesAdvancedPaneTests {
    @Test
    func `cli install status prefers successful installs over unrelated failures`() {
        let status = AdvancedPane.cliInstallStatus(
            installed: ["Installed: /opt/homebrew/bin"],
            conflicts: [],
            failures: ["No write access: /usr/local/bin"])
        #expect(status == "Installed: /opt/homebrew/bin")
    }

    @Test
    func `cli install status keeps conflicts alongside a successful install`() {
        let status = AdvancedPane.cliInstallStatus(
            installed: ["Installed: /opt/homebrew/bin"],
            conflicts: ["Exists: /usr/local/bin"],
            failures: [])
        #expect(status == "Installed: /opt/homebrew/bin · Exists: /usr/local/bin")
    }

    @Test
    func `cli install status reports conflicts and failures when nothing installed`() {
        let status = AdvancedPane.cliInstallStatus(
            installed: [],
            conflicts: ["Exists: /opt/homebrew/bin"],
            failures: ["No write access: /usr/local/bin"])
        #expect(status == "Exists: /opt/homebrew/bin · No write access: /usr/local/bin")
    }

    @Test
    func `cli install status reports failures without writable destinations`() {
        let status = AdvancedPane.cliInstallStatus(
            installed: [],
            conflicts: [],
            failures: ["Failed: /opt/homebrew/bin", "No write access: /usr/local/bin"])
        #expect(status == "Failed: /opt/homebrew/bin · No write access: /usr/local/bin")
    }
}
