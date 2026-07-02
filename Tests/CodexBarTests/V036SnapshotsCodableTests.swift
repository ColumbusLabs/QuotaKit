import CodexBarSync
import Foundation
import Testing

@Suite("CrossModel sync envelope")
struct V036SnapshotsCodableTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func sampleUsage() -> SyncCrossModelUsage {
        SyncCrossModelUsage(
            currency: "usd",
            balance: 8.059489,
            uncollected: 1.25,
            daily: SyncCrossModelUsageWindow(
                cost: 0.42,
                promptTokens: 8100,
                completionTokens: 4367,
                totalTokens: 12467,
                requestCount: 42,
                successCount: 40),
            weekly: nil,
            monthly: SyncCrossModelUsageWindow(
                cost: 5.368746,
                promptTokens: 410_000,
                completionTokens: 119_000,
                totalTokens: 529_000,
                requestCount: 3166,
                successCount: 3112),
            updatedAt: self.now)
    }

    @Test("SyncCrossModelUsage round-trips")
    func syncCrossModelUsageRoundTrips() throws {
        let source = Self.sampleUsage()
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncCrossModelUsage.self, from: data)

        #expect(decoded.currency == "USD")
        #expect(decoded.balance == 8.059489)
        #expect(decoded.daily?.totalTokens == 12467)
        #expect(decoded.monthly?.requestCount == 3166)
        #expect(decoded == source)
    }

    @Test("ProviderUsageSnapshot carries CrossModel usage through round-trip")
    func providerSnapshotCarriesCrossModelUsage() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: "crossmodel",
            providerName: "CrossModel",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API key",
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.now,
            crossModelUsage: Self.sampleUsage())

        let data = try Self.encoder.encode(snapshot)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.crossModelUsage?.balance == 8.059489)
        #expect(decoded.crossModelUsage?.monthly?.successCount == 3112)
    }

    @Test("Old payload without CrossModel usage decodes to nil")
    func oldPayloadDecodesCrossModelNil() throws {
        let json = """
        {"providerID": "crossmodel", "providerName": "CrossModel",
         "isError": false, "lastUpdated": "2023-11-14T22:13:20Z"}
        """

        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))

        #expect(decoded.crossModelUsage == nil)
        #expect(decoded.providerID == "crossmodel")
    }
}
