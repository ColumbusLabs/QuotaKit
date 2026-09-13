import Foundation
import Testing
@testable import CodexBarCore

struct GrokWebBillingFetcherParsingRegressionTests {
    @Test
    func `malformed protobuf tag cannot turn period-only billing into zero usage`() {
        let reset = UInt64(1_800_000_001)
        let period = Data([0x08]) + Self.varint(reset)
        let periodMessage = Data([0x32, UInt8(period.count)]) + period
        var payload = Data([0x0A, UInt8(periodMessage.count)]) + periodMessage
        payload.append(0x00) // Invalid protobuf field tag after an otherwise valid period.

        #expect {
            _ = try GrokWebBillingFetcher.parseGRPCWebResponse(
                Self.grpcFrame(payload), now: Date(timeIntervalSince1970: 1_700_000_000))
        } throws: { error in
            guard case GrokWebBillingError.parseFailed = error else { return false }
            return true
        }
    }

    private static func grpcFrame(_ payload: Data) -> Data {
        var data = Data([0x00])
        let length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: length) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    private static func varint(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while remaining != 0
        return bytes
    }
}
