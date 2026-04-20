import CodexBarSync
import Foundation
import Testing

@Suite
struct PayloadCompressionTests {
    @Test
    func roundTripsRealisticPayload() throws {
        // Simulate the shape of a real per-provider envelope: repeated Date
        // strings + repeated doubles, which is what zlib exploits.
        let json =
            """
            {"entries":\(
                (0..<500).map { i in
                    "{\"capturedAt\":\"2026-04-\(String(format: "%02d", (i%28)+1))T10:00:00Z\",\"usedPercent\":\(Double(i%100))}"
                }.joined(separator: ",")
            )]}
            """
        let data = Data(json.utf8)

        let compressed = try PayloadCompression.compress(data)
        let decompressed = try PayloadCompression.decompress(compressed)

        #expect(decompressed == data)
        // Realistic compression ratio sanity: ≤ 25% of original.
        #expect(Double(compressed.count) / Double(data.count) < 0.25)
    }

    @Test
    func roundTripsEmpty() throws {
        let compressed = try PayloadCompression.compress(Data())
        let decompressed = try PayloadCompression.decompress(compressed)
        #expect(decompressed == Data())
    }

    @Test
    func decompressRejectsMalformedHeader() {
        let bogus = Data([0x00, 0x01]) // <4 bytes = malformed
        #expect(throws: PayloadCompression.Error.self) {
            _ = try PayloadCompression.decompress(bogus)
        }
    }

    @Test
    func decompressRejectsHeaderWithoutBody() {
        // Header says "10 bytes to follow" but nothing does.
        var header = UInt32(10).littleEndian
        let data = Data(bytes: &header, count: 4)
        #expect(throws: PayloadCompression.Error.self) {
            _ = try PayloadCompression.decompress(data)
        }
    }
}

@Suite
struct ProviderUsageEnvelopeTests {
    @Test
    func jsonRoundTrip() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: "oauth",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: nil)
        let envelope = ProviderUsageEnvelope(
            deviceID: "abc-123",
            deviceName: "Mac",
            appVersion: "0.20.1",
            mobileVersion: "1.3.0",
            syncTimestamp: Date(timeIntervalSince1970: 1_700_001_000),
            notificationPushEnabled: true,
            provider: provider)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(envelope)
        let decoded = try decoder.decode(ProviderUsageEnvelope.self, from: data)

        #expect(decoded == envelope)
    }
}
