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
        self.isInCaskroom(appBundleURL: appBundleURL) ||
            self.hasMatchingCaskArtifact(appBundleURL: appBundleURL, caskroomURLs: caskroomURLs)
    }

    private static func isInCaskroom(appBundleURL: URL) -> Bool {
        let resolved = appBundleURL.resolvingSymlinksInPath().standardizedFileURL
        let legacyCask = resolved.deletingLastPathComponent().deletingLastPathComponent()
        return resolved.lastPathComponent == "QuotaKit.app" &&
            legacyCask.lastPathComponent == "quotakit" &&
            legacyCask.deletingLastPathComponent().lastPathComponent == "Caskroom"
    }

    private static func hasMatchingCaskArtifact(appBundleURL: URL, caskroomURLs: [URL]) -> Bool {
        let resolved = appBundleURL.resolvingSymlinksInPath().standardizedFileURL
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        // Homebrew moves the bundle into Applications and leaves a symlink in Caskroom.
        return caskroomURLs.contains { caskroom in
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
        }
    }
}
