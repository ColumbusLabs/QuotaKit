import CodexBarCore
import Foundation
import Testing

#if os(macOS)
import SweetCookieKit

@Suite
struct BrowserDetectionTests {
    @Test
    func safariAlwaysInstalled() {
        #expect(BrowserDetection().isInstalled(.safari) == true)
    }

    @Test
    func filterInstalledIncludesSafari() {
        let browsers: [Browser] = [.safari, .chrome, .firefox]
        #expect(BrowserDetection().filterInstalled(browsers).contains(.safari))
    }

    @Test
    func filterPreservesOrder() {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let chromeProfile = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Google")
            .appendingPathComponent("Chrome")
            .appendingPathComponent("Default")
        try? FileManager.default.createDirectory(at: chromeProfile, withIntermediateDirectories: true)

        let firefoxProfile = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Firefox")
            .appendingPathComponent("Profiles")
            .appendingPathComponent("abc.default-release")
        try? FileManager.default.createDirectory(at: firefoxProfile, withIntermediateDirectories: true)

        let detection = BrowserDetection(homeDirectory: temp.path, cacheTTL: 0)
        let browsers: [Browser] = [.firefox, .safari, .chrome]
        #expect(detection.filterInstalled(browsers) == browsers)
    }

    @Test
    func chromeRequiresProfileData() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let detection = BrowserDetection(homeDirectory: temp.path, cacheTTL: 0)
        #expect(detection.isInstalled(.chrome) == false)

        let profile = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Google")
            .appendingPathComponent("Chrome")
            .appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        #expect(detection.isInstalled(.chrome) == true)
    }

    @Test
    func firefoxRequiresDefaultProfileDir() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let profiles = temp
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Firefox")
            .appendingPathComponent("Profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

        let detection = BrowserDetection(homeDirectory: temp.path, cacheTTL: 0)
        #expect(detection.isInstalled(.firefox) == false)

        let profile = profiles.appendingPathComponent("abc.default-release")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        #expect(detection.isInstalled(.firefox) == true)
    }
}

#else

@Suite
struct BrowserDetectionTests {
    @Test
    func nonMacOSReturnsNoBrowsers() {
        #expect(BrowserDetection().isInstalled(Browser()) == false)
    }

    @Test
    func nonMacOSFilterReturnsEmpty() {
        let browsers = [Browser(), Browser()]
        #expect(BrowserDetection().filterInstalled(browsers).isEmpty == true)
    }
}

#endif
