import Foundation
import Testing
@testable import CodexBar

struct InstallOriginTests {
    @Test
    func `detects homebrew caskroom`() {
        #expect(
            InstallOrigin
                .isHomebrewCask(
                    appBundleURL: URL(fileURLWithPath: "/opt/homebrew/Caskroom/quotakit/1.0.0/QuotaKit.app")))
        #expect(
            InstallOrigin
                .isHomebrewCask(appBundleURL: URL(fileURLWithPath: "/usr/local/Caskroom/quotakit/1.0.0/QuotaKit.app")))
        #expect(!InstallOrigin.isHomebrewCask(appBundleURL: URL(fileURLWithPath: "/Applications/QuotaKit.app")))
    }
}
