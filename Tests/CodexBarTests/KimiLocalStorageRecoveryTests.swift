#if os(macOS)
import Foundation
import Testing
@testable import CodexBarCore

struct KimiLocalStorageRecoveryTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let token = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE4MDAwMDM2MDB9.signature"

    @Test
    func `imports only valid unexpired regional access tokens and deduplicates`() {
        let expired = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.signature"
        let api = BrowserLocalStorageAPI { origin, browsers, _, _ in
            #expect(browsers == ChromiumLocalStorageDiscovery.defaultBrowsers)
            guard origin == "https://www.kimi.ai" else { return [] }
            return [
                .init(id: "chrome:Default", label: "Chrome Default", entries: [
                    .init(key: "refresh_token", value: Self.token),
                    .init(key: "access_token", value: expired),
                    .init(key: "access_token", value: "not-a-token"),
                    .init(key: "access_token", value: "a.b.c"),
                    .init(key: "access_token", value: Self.token + "; kimi-auth=x"),
                    .init(key: "access_token", value: " \(Self.token)\n"),
                ]),
                .init(id: "chrome:Profile 2", label: "Chrome Profile 2", entries: [
                    .init(key: "access_token", value: "\"\(Self.token)\""),
                ]),
            ]
        }

        #expect(KimiCookieImporter.localStorageTokens(
            region: .international,
            localStorage: api,
            now: Self.now) == [Self.token])
        #expect(KimiCookieImporter.localStorageTokens(
            region: .china,
            localStorage: api,
            now: Self.now).isEmpty)
        #expect(KimiCookieImporter.localStorageTokens(
            region: .international,
            localStorage: api,
            now: Self.now.addingTimeInterval(3600)).isEmpty)
    }

    @Test(arguments: ["replacement", "sign-in", "sign-out"], [KimiRegion.china, .international])
    func `imports only the current LevelDB session through the browser adapter`(
        operation: String, region: KimiRegion) throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kimi-current-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("Default/Local Storage/leveldb")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let origin = region.webBaseURL.absoluteString
        try Self.writeLog(
            origin: origin,
            value: operation == "sign-in" ? nil : Self.token + "-old",
            to: storage,
            sequence: 1,
            filename: "000003.log")
        try Self.writeLog(
            origin: origin,
            value: operation == "sign-out" ? nil : Self.token,
            to: storage,
            sequence: 2,
            filename: "000004.log")
        // Deliberately make the older sequence's file newer on disk.
        for (file, time) in [("000003.log", 200.0), ("000004.log", 100.0)] {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: time)],
                ofItemAtPath: storage.appendingPathComponent(file).path)
        }
        let api = BrowserLocalStorageAPI { origin, _, _, logger in
            BrowserLocalStorageAPI.loadProfiles(
                origin: origin, root: root, browserID: "fixture", labelPrefix: "Fixture", logger: logger)
        }
        #expect(KimiCookieImporter.localStorageTokens(
            region: region, localStorage: api, now: Self.now) ==
            (operation == "sign-out" ? [] : [Self.token]))
        let otherRegion: KimiRegion = region == .china ? .international : .china
        #expect(KimiCookieImporter.localStorageTokens(
            region: otherRegion, localStorage: api, now: Self.now).isEmpty)
    }

    private static func writeLog(
        origin: String,
        value: String?,
        to directory: URL,
        sequence: UInt64,
        filename: String) throws
    {
        let key = Data("_\(origin)\0access_token".utf8)
        var sequence = sequence.littleEndian
        var batch = withUnsafeBytes(of: &sequence) { Data($0) }
        batch.append(contentsOf: [1, 0, 0, 0])
        batch.append(value == nil ? 0 : 1)
        batch.append(UInt8(key.count))
        batch.append(key)
        if let value {
            let encoded = Data([1]) + Data(value.utf8)
            batch.append(UInt8(encoded.count))
            batch.append(encoded)
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in Data([1]) + batch {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0x82F6_3B78 : 0)
            }
        }
        crc = ~crc
        var masked = (((crc >> 15) | (crc << 17)) &+ 0xA282_EAD8).littleEndian
        var record = withUnsafeBytes(of: &masked) { Data($0) }
        let length = UInt16(batch.count).littleEndian
        withUnsafeBytes(of: length) { record.append(contentsOf: $0) }
        record.append(1)
        record.append(batch)
        try record.write(to: directory.appendingPathComponent(filename))
    }
}
#endif
