import CodexBarCore
import Foundation

enum ProviderImplementationRegistry {
    private static let implementations = ProviderImplementationManifest.makeImplementations.map { $0() }
    private static let byID: [UsageProvider: any ProviderImplementation] = Dictionary(
        uniqueKeysWithValues: implementations.map { ($0.id, $0) })

    static var all: [any ProviderImplementation] {
        self.implementations
    }

    static func implementation(for id: UsageProvider) -> (any ProviderImplementation)? {
        self.byID[id]
    }
}
