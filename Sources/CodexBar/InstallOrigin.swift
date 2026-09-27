import Foundation

enum InstallOrigin {
    static let caskroomURLs = [
        URL(fileURLWithPath: "/opt/homebrew/Caskroom"),
        URL(fileURLWithPath: "/usr/local/Caskroom"),
    ]

    static func isHomebrewCask(
        appBundleURL: URL,
        caskroomURLs: [URL] = Self.caskroomURLs) -> Bool
    {
        !self.homebrewPrefixes(appBundleURL: appBundleURL, caskroomURLs: caskroomURLs).isEmpty
    }

    static func homebrewPrefix(
        appBundleURL: URL,
        caskroomURLs: [URL] = Self.caskroomURLs) -> URL?
    {
        let prefixes = self.homebrewPrefixes(appBundleURL: appBundleURL, caskroomURLs: caskroomURLs)
        return prefixes.count == 1 ? prefixes[0] : nil
    }

    private static func homebrewPrefixes(appBundleURL: URL, caskroomURLs: [URL]) -> [URL] {
        let resolved = appBundleURL.resolvingSymlinksInPath().standardizedFileURL
        var prefixes: [URL] = []
        let legacyCask = resolved.deletingLastPathComponent().deletingLastPathComponent()
        if resolved.lastPathComponent == "QuotaKit.app", legacyCask.lastPathComponent == "quotakit",
           legacyCask.deletingLastPathComponent().lastPathComponent == "Caskroom"
        {
            prefixes.append(legacyCask.deletingLastPathComponent().deletingLastPathComponent())
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return prefixes
        }

        // Homebrew moves the bundle into Applications and leaves a symlink in Caskroom.
        let linkedPrefixes = caskroomURLs.filter { caskroom in
            let caskURL = caskroom.appendingPathComponent("quotakit", isDirectory: true)
            guard let versions = try? fileManager.contentsOfDirectory(
                at: caskURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]) else { return false }
            return versions.contains { version in
                let artifact = version.appendingPathComponent("QuotaKit.app")
                return (try? fileManager.destinationOfSymbolicLink(atPath: artifact.path)) != nil &&
                    artifact.resolvingSymlinksInPath().standardizedFileURL == resolved
            }
        }.map { $0.deletingLastPathComponent() }
        return Array(Set((prefixes + linkedPrefixes).map { $0.resolvingSymlinksInPath().standardizedFileURL }))
    }
}
