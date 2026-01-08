import Foundation
#if os(macOS)
import os.lock
import SweetCookieKit

/// Detects which browsers are likely to have usable profile data (and thus cookies) available.
///
/// Primary goal: avoid triggering unnecessary Keychain prompts (e.g. Chromium “Safe Storage”) by skipping
/// browsers that have no profile data on disk.
public final class BrowserDetection: Sendable {
    private let cache = OSAllocatedUnfairLock<[Browser: CachedResult]>(initialState: [:])
    private let homeDirectory: String
    private let cacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let fileExists: @Sendable (String) -> Bool
    private let directoryContents: @Sendable (String) -> [String]?

    private struct CachedResult {
        let isInstalled: Bool
        let timestamp: Date
    }

    public init(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        cacheTTL: TimeInterval = 60 * 10,
        now: @escaping @Sendable () -> Date = Date.init,
        fileExists: @escaping @Sendable (String) -> Bool = { path in FileManager.default.fileExists(atPath: path) },
        directoryContents: @escaping @Sendable (String) -> [String]? = { path in
            try? FileManager.default.contentsOfDirectory(atPath: path)
        })
    {
        self.homeDirectory = homeDirectory
        self.cacheTTL = cacheTTL
        self.now = now
        self.fileExists = fileExists
        self.directoryContents = directoryContents
    }

    public func isInstalled(_ browser: Browser) -> Bool {
        // Safari is always available on macOS
        if browser == .safari {
            return true
        }

        let now = self.now()
        if let cached = self.cache.withLock({ cache in cache[browser] }) {
            if now.timeIntervalSince(cached.timestamp) < self.cacheTTL {
                return cached.isInstalled
            }
        }

        let result = self.detectInstallation(for: browser)
        self.cache.withLock { cache in
            cache[browser] = CachedResult(isInstalled: result, timestamp: now)
        }
        return result
    }

    public func filterInstalled(_ browsers: [Browser]) -> [Browser] {
        browsers.filter { self.isInstalled($0) }
    }

    public func clearCache() {
        self.cache.withLock { cache in
            cache.removeAll()
        }
    }

    // MARK: - Detection Logic

    private func detectInstallation(for browser: Browser) -> Bool {
        guard let profilePath = self.profilePath(for: browser, homeDirectory: self.homeDirectory) else {
            return false
        }

        guard self.fileExists(profilePath) else {
            return false
        }

        // For Chromium-based browsers (and Firefox), verify actual profile data exists.
        if self.requiresProfileValidation(browser) {
            return self.hasValidProfile(at: profilePath)
        }

        return true
    }

    private func profilePath(for browser: Browser, homeDirectory: String) -> String? {
        switch browser {
        case .safari:
            return "\(homeDirectory)/Library/Cookies/Cookies.binarycookies"
        case .chrome:
            return "\(homeDirectory)/Library/Application Support/Google/Chrome"
        case .chromeBeta:
            return "\(homeDirectory)/Library/Application Support/Google/Chrome Beta"
        case .chromeCanary:
            return "\(homeDirectory)/Library/Application Support/Google/Chrome Canary"
        case .arc:
            return "\(homeDirectory)/Library/Application Support/Arc/User Data"
        case .arcBeta:
            return "\(homeDirectory)/Library/Application Support/Arc Beta/User Data"
        case .arcCanary:
            return "\(homeDirectory)/Library/Application Support/Arc Canary/User Data"
        case .brave:
            return "\(homeDirectory)/Library/Application Support/BraveSoftware/Brave-Browser"
        case .braveBeta:
            return "\(homeDirectory)/Library/Application Support/BraveSoftware/Brave-Browser-Beta"
        case .braveNightly:
            return "\(homeDirectory)/Library/Application Support/BraveSoftware/Brave-Browser-Nightly"
        case .edge:
            return "\(homeDirectory)/Library/Application Support/Microsoft Edge"
        case .edgeBeta:
            return "\(homeDirectory)/Library/Application Support/Microsoft Edge Beta"
        case .edgeCanary:
            return "\(homeDirectory)/Library/Application Support/Microsoft Edge Canary"
        case .vivaldi:
            return "\(homeDirectory)/Library/Application Support/Vivaldi"
        case .chromium:
            return "\(homeDirectory)/Library/Application Support/Chromium"
        case .firefox:
            return "\(homeDirectory)/Library/Application Support/Firefox/Profiles"
        case .chatgptAtlas:
            return "\(homeDirectory)/Library/Application Support/ChatGPT Atlas"
        case .helium:
            return "\(homeDirectory)/Library/Application Support/net.imput.helium"
        @unknown default:
            return nil
        }
    }

    private func requiresProfileValidation(_ browser: Browser) -> Bool {
        // Chromium-based browsers should have Default/ or Profile*/ subdirectories
        switch browser {
        case .chrome, .chromeBeta, .chromeCanary,
             .arc, .arcBeta, .arcCanary,
             .brave, .braveBeta, .braveNightly,
             .edge, .edgeBeta, .edgeCanary,
             .vivaldi, .chromium, .chatgptAtlas:
            return true
        case .firefox:
            // Firefox should have at least one *.default* directory
            return true
        case .helium:
            // Helium doesn't use the Default/Profile* pattern
            return false
        case .safari:
            return false
        @unknown default:
            return false
        }
    }

    private func hasValidProfile(at profilePath: String) -> Bool {
        guard let contents = self.directoryContents(profilePath) else { return false }

        // Check for Default/ or Profile*/ subdirectories for Chromium browsers
        let hasProfile = contents.contains { name in
            name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
        }

        // For Firefox, check for .default directories
        if !hasProfile {
            let hasFirefoxProfile = contents.contains { name in
                name.contains(".default")
            }
            return hasFirefoxProfile
        }

        return hasProfile
    }
}

#else

// MARK: - Non-macOS stub

public struct BrowserDetection: Sendable {
    public init() {}

    public func isInstalled(_ browser: Browser) -> Bool {
        false
    }

    public func filterInstalled(_ browsers: [Browser]) -> [Browser] {
        []
    }

    public func clearCache() {}
}

#endif
