import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum ClaudeDesktopProjectsLocator {
    private static let sessionDirectoryNames = [
        "local-agent-mode-sessions",
        "claude-code-sessions",
    ]

    private static let skippedDirectoryNames = Set([
        ".build",
        ".git",
        "build",
        "DerivedData",
        "node_modules",
        "outputs",
        "target",
    ])

    public static func roots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        includeAuditFiles: Bool = false,
        onDiscoveryError: ((Error) -> Void)? = nil) -> [URL]
    {
        var budget = DirectoryMetadataScanBudget(maxEntryCount: .max, maxDepth: 4, timeLimit: .infinity)
        return self.discoverRoots(
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            budget: &budget,
            includeAuditFiles: includeAuditFiles,
            onDiscoveryError: onDiscoveryError)
    }

    static func roots(
        homeDirectory: URL,
        fileManager: FileManager,
        budget: inout DirectoryMetadataScanBudget) -> [URL]
    {
        self.discoverRoots(
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            budget: &budget,
            includeAuditFiles: false,
            onDiscoveryError: nil)
    }

    private static func discoverRoots(
        homeDirectory: URL,
        fileManager: FileManager,
        budget: inout DirectoryMetadataScanBudget,
        includeAuditFiles: Bool,
        onDiscoveryError: ((Error) -> Void)?) -> [URL]
    {
        let claudeApplicationSupport = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
        let sessionRoots = self.sessionDirectoryNames.map {
            claudeApplicationSupport.appendingPathComponent($0, isDirectory: true)
        }

        var roots: [URL] = []
        var queue = sessionRoots.map { (url: $0, depth: 0) }
        var visited = Set(sessionRoots.map(\.standardizedFileURL.path))
        var nextIndex = 0
        while nextIndex < queue.count, budget.hasTimeRemaining() {
            let current = queue[nextIndex]
            nextIndex += 1
            if let projects = self.projectsRoot(
                under: current.url,
                fileManager: fileManager,
                onDiscoveryError: onDiscoveryError)
            {
                roots.append(projects)
            }

            // Cowork audit files are cost inputs, not project roots for live-session correlation.
            let audit = current.url.appendingPathComponent("audit.jsonl")
            if includeAuditFiles {
                do {
                    let values = try audit.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values.isRegularFile == true, values.isSymbolicLink != true {
                        roots.append(audit.standardizedFileURL)
                    }
                } catch {
                    if !self.isMissingPathError(error) { onDiscoveryError?(error) }
                }
            }

            guard current.depth < budget.maxDepth else { continue }
            let children: [URL] = if let onDiscoveryError {
                self.childDirectories(
                    at: current.url,
                    fileManager: fileManager,
                    onDiscoveryError: onDiscoveryError)
            } else {
                budget.childDirectories(in: current.url, fileManager: fileManager)
            }
            for child in children {
                guard !self.skippedDirectoryNames.contains(child.lastPathComponent),
                      (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false
                else { continue }
                let standardized = child.standardizedFileURL
                guard visited.insert(standardized.path).inserted else { continue }
                queue.append((standardized, current.depth + 1))
            }
        }
        return roots
    }

    private static func projectsRoot(
        under base: URL,
        fileManager: FileManager,
        onDiscoveryError: ((Error) -> Void)? = nil) -> URL?
    {
        let projects = base
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: projects.path)
        } catch {
            if !self.isMissingPathError(error) { onDiscoveryError?(error) }
            return nil
        }
        let type = attributes[.type] as? FileAttributeType
        if type == .typeSymbolicLink {
            // Claude Code can point `.claude/projects` at a shared history directory. Confirm
            // the target is a directory while keeping the symlink path for later traversal.
            let target = projects.resolvingSymlinksInPath()
            do {
                let targetAttributes = try fileManager.attributesOfItem(atPath: target.path)
                guard targetAttributes[.type] as? FileAttributeType == .typeDirectory else { return nil }
            } catch {
                if !self.isMissingPathError(error) { onDiscoveryError?(error) }
                return nil
            }
        } else if type != .typeDirectory {
            return nil
        }
        return projects.standardizedFileURL
    }

    private static func childDirectories(
        at url: URL,
        fileManager: FileManager,
        onDiscoveryError: ((Error) -> Void)? = nil) -> [URL]
    {
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        } catch {
            if !self.isMissingPathError(error) { onDiscoveryError?(error) }
            return []
        }

        return children.compactMap { child in
            guard !self.skippedDirectoryNames.contains(child.lastPathComponent) else { return nil }
            let values: URLResourceValues
            do {
                values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            } catch {
                if !self.isMissingPathError(error) { onDiscoveryError?(error) }
                return nil
            }
            guard values.isSymbolicLink != true, values.isDirectory == true else { return nil }
            return child
        }
    }

    private static func isMissingPathError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(ENOENT) || nsError.code == Int(ENOTDIR)
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        {
            return true
        }
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error else { return false }
        return self.isMissingPathError(underlying)
    }
}
