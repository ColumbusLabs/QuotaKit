import Foundation
import Testing
@testable import CodexBarCore

struct ProviderPluginSnapshotContractTests {
    private static let engines: [ProviderPluginEngineKind] = {
        #if canImport(JavaScriptCore)
        [.javaScriptCore, .quickJS]
        #else
        [.quickJS]
        #endif
    }()

    @Test(arguments: Self.engines)
    func `explicit empty snapshots need no invented usage or identity`(engine: ProviderPluginEngineKind) async throws {
        for (body, expectedLoginMethod) in [
            ("{ empty: true }", nil as String?),
            ("{ empty: true, identity: { loginMethod: 'API' } }", "API"),
        ] {
            let runtime = try Self.runtime(engine: engine, body: body)
            let snapshot = try await runtime.fetchUsage()

            #expect(snapshot.primary == nil)
            #expect(snapshot.secondary == nil)
            #expect(snapshot.tertiary == nil)
            #expect(snapshot.extraRateWindows == nil)
            #expect(snapshot.providerCost == nil)
            #expect(snapshot.costUsage == nil)
            #expect(snapshot.details.isEmpty)
            #expect(snapshot.identity?.loginMethod == expectedLoginMethod)
        }
    }

    @Test(arguments: Self.engines)
    func `meaningful identity is valid snapshot data without invented usage`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine: engine, body: "{ identity: { loginMethod: 'API' } }")
        let snapshot = try await runtime.fetchUsage()

        #expect(snapshot.identity?.loginMethod == "API")
        #expect(snapshot.primary == nil && snapshot.secondary == nil && snapshot.tertiary == nil)
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.details.isEmpty)
    }

    @Test(arguments: Self.engines)
    func `empty marker does not bypass snapshot validation`(engine: ProviderPluginEngineKind) async throws {
        for body in [
            "{}",
            "{ empty: false }",
            "{ empty: 'true' }",
            "{ empty: 1 }",
            "{ empty: null }",
            "{ identity: {} }",
            "{ empty: true, primary: { usedPercent: 'wrong' } }",
            "{ empty: true, identity: [] }",
            "{ empty: true, identity: { loginMethod: 1 } }",
        ] {
            let runtime = try Self.runtime(engine: engine, body: body)
            await #expect(throws: ProviderPluginError.self) {
                _ = try await runtime.fetchUsage()
            }
        }
    }

    private static func runtime(engine: ProviderPluginEngineKind, body: String) throws -> ProviderPluginRuntime {
        let source = """
        defineProvider({
          id: "synthetic",
          name: "Snapshot Fixture",
          endpoints: ["https://api.synthetic.test"],
          settings: [],
          async fetchUsage() {
            return \(body);
          },
        });
        """
        return try ProviderPluginRuntime(
            source: source,
            transport: ProviderHTTPTransportHandler { _ in throw URLError(.badServerResponse) },
            engine: engine)
    }
}
