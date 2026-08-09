import AppKit
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct ProviderArchitectureGatekeeperTests {
    private static let supportedProviders: [UsageProvider] = [
        .codex,
        .claude,
        .cursor,
        .grok,
    ]

    @Test
    func `provider catalog contains exactly the supported four in display order`() {
        #expect(UsageProvider.allCases == Self.supportedProviders)
    }

    @Test
    func `descriptor and implementation manifests match the supported catalog`() {
        let expected = Self.supportedProviders
        #expect(ProviderDescriptorRegistry.all.map(\.id) == expected)
        #expect(ProviderImplementationRegistry.all.map(\.id) == expected)
    }

    @Test
    func `each supported provider has one descriptor and implementation`() {
        for provider in Self.supportedProviders {
            #expect(ProviderDescriptorRegistry.descriptor(for: provider).id == provider)
            #expect(ProviderImplementationRegistry.implementation(for: provider)?.id == provider)
        }
    }

    @Test
    func `each supported provider has a loadable SVG icon`() throws {
        let resources = try Self.repoRoot()
            .appending(path: "Sources/CodexBar/Resources", directoryHint: .isDirectory)

        for descriptor in ProviderDescriptorRegistry.all {
            let resourceName = descriptor.branding.iconResourceName
            let url = resources.appending(path: "\(resourceName).svg")
            #expect(
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                "Missing SVG for \(descriptor.id.rawValue): \(resourceName).svg")
            #expect(NSImage(contentsOf: url) != nil, "Could not load \(resourceName).svg as NSImage")
        }
    }

    private static func repoRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appending(path: "Package.swift").path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
