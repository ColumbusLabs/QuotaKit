import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeSwapCostRootsLinuxTests {
    @Test
    func `XDG and legacy swap homes contribute only numbered project slots`() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(
            "claude-swap-cost-roots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let xdg = home.appendingPathComponent("custom-data", isDirectory: true)
        let xdgProjects = xdg.appendingPathComponent("claude-swap/sessions/2-second/projects", isDirectory: true)
        let legacyProjects = home.appendingPathComponent(
            ".claude-swap-backup/sessions/1-first/projects", isDirectory: true)
        let decoyProjects = xdg.appendingPathComponent(
            "claude-swap/sessions/invalid/projects", isDirectory: true)
        for projects in [xdgProjects, legacyProjects, decoyProjects] {
            try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        }

        let roots = ClaudeConfigPaths.costProjectsRoots(
            environment: ["XDG_DATA_HOME": xdg.path], homeDirectory: home)
        #expect(roots.contains(xdgProjects.standardizedFileURL))
        #expect(roots.contains(legacyProjects.standardizedFileURL))
        #expect(!roots.contains(decoyProjects.standardizedFileURL))
    }

    @Test
    func `relative XDG data home falls back to the Linux default`() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(
            "claude-swap-cost-default-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let projects = home.appendingPathComponent(
            ".local/share/claude-swap/sessions/3-third/projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

        let roots = ClaudeConfigPaths.costProjectsRoots(
            environment: ["XDG_DATA_HOME": "relative-data"], homeDirectory: home)
        #expect(roots.contains(projects.standardizedFileURL))
    }
}
