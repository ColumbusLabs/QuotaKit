import Foundation
import Testing
@testable import CodexBar

@Suite
struct InstallOriginTests {
    @Test
    func detectsHomebrewCaskroom() {
        #expect(
            InstallOrigin
                .isHomebrewCask(
                    appBundleURL: URL(fileURLWithPath: "/opt/homebrew/Caskroom/codexbar/1.0.0/CodexBar.app")))
        #expect(
            InstallOrigin
                .isHomebrewCask(appBundleURL: URL(fileURLWithPath: "/usr/local/Caskroom/codexbar/1.0.0/CodexBar.app")))
        #expect(!InstallOrigin.isHomebrewCask(appBundleURL: URL(fileURLWithPath: "/Applications/CodexBar.app")))
    }
}
