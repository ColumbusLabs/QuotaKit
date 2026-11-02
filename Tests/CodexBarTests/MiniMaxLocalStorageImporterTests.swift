import Foundation
import SweetCookieKit
import Testing
@testable import CodexBarCore

struct MiniMaxLocalStorageImporterTests {
    @Test(arguments: ChromiumLocalStorageDiscovery.defaultBrowsers)
    func `discovers each storage fallback across the Chromium catalog`(browser: Browser) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-storage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = try #require(ChromiumProfileLocator.roots(for: [browser], homeDirectories: [home]).first)
        let profile = root.url.appendingPathComponent("Default")
        let databaseName = "https_platform.minimax.io_0.indexeddb.leveldb"
        for path in ["Local Storage/leveldb", "Session Storage", "IndexedDB/\(databaseName)"] {
            try FileManager.default.createDirectory(
                at: profile.appendingPathComponent(path),
                withIntermediateDirectories: true)
        }
        let detection = BrowserDetection(homeDirectory: home.path)
        let fixtures: [(ChromiumLocalStorageDiscovery.Storage, String, String)] = [
            (.localStorage, "Local Storage/leveldb", ""),
            (.sessionStorage, "Session Storage", " (Session Storage)"),
            (MiniMaxLocalStorageImporter.indexedDBStorage, "IndexedDB/\(databaseName)", " (IndexedDB)"),
        ]
        for (storage, path, suffix) in fixtures {
            let candidates = MiniMaxLocalStorageImporter.storageCandidates(
                browserDetection: detection,
                storage: storage,
                homeDirectories: [home])
            #expect(candidates.map { $0.url.resolvingSymlinksInPath().path } == [
                profile.appendingPathComponent(path).resolvingSymlinksInPath().path,
            ])
            #expect(candidates.map(\.label) == ["\(root.labelPrefix) Default\(suffix)"])
        }
    }

    @Test
    func `IndexedDB discovery keeps only MiniMax origins in supported profiles`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-indexeddb-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let allowed = [
            "https_platform.minimax.io_0", "https_www.minimax.io_0", "https_minimax.io_0",
            "https_platform.minimax.cn_0", "https_www.minimax.cn_0", "https_minimax.cn_0",
            "https_platform.minimaxi.com_0", "https_www.minimaxi.com_0", "https_minimaxi.com_0",
        ].map { "\($0).indexeddb.leveldb" }
        let excluded = [
            "https_other.example_0.indexeddb.leveldb",
            "https_minimax.io.evil_0.indexeddb.leveldb",
            "https_minimax.io_0.indexeddb.blob",
            ".https_minimax.io_0.indexeddb.leveldb",
        ]
        for profile in ["Default", "Profile 2", "user-work", "Guest Profile", ".hidden"] {
            for database in allowed + excluded {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("\(profile)/IndexedDB/\(database)"),
                    withIntermediateDirectories: true)
            }
        }
        let nonDirectory = root.appendingPathComponent("Default/IndexedDB/https_minimax.io_1.indexeddb.leveldb")
        try Data().write(to: nonDirectory)
        let candidates = ChromiumLocalStorageDiscovery.profileCandidates(
            root: root,
            labelPrefix: "Fixture",
            storage: MiniMaxLocalStorageImporter.indexedDBStorage)
        #expect(candidates.count == 27)
        #expect(Set(candidates.map(\.url.lastPathComponent)) == Set(allowed))
        #expect(candidates.map(\.label) == ["Default", "Profile 2", "user-work"].flatMap { profile in
            Array(repeating: "Fixture \(profile) (IndexedDB)", count: allowed.count)
        })
    }

    @Test
    func `IndexedDB origin names reject nondefault ports and suffix confusion`() {
        #expect(MiniMaxLocalStorageImporter.isAllowedIndexedDBName("https_minimax.cn_0.indexeddb.leveldb"))
        #expect(MiniMaxLocalStorageImporter.isAllowedIndexedDBName("https_platform.minimax.io_443.indexeddb.leveldb"))
        #expect(!MiniMaxLocalStorageImporter.isAllowedIndexedDBName("https_minimax.cn_8443.indexeddb.leveldb"))
        #expect(!MiniMaxLocalStorageImporter
            .isAllowedIndexedDBName("https_minimax.cn_0.indexeddb.leveldb.evil.indexeddb.leveldb"))
        #expect(!MiniMaxLocalStorageImporter
            .isAllowedIndexedDBName("https_minimax.cn.attacker.example_0.indexeddb.leveldb"))
    }

    @Test
    func `browser cookie groups retain region and host ownership`() throws {
        func cookie(_ value: String, domain: String, hostOnly: Bool) -> ProviderPluginCookieRecord {
            ProviderPluginCookieRecord(
                name: "HERTZ-SESSION",
                value: value,
                domain: domain,
                hostOnly: hostOnly,
                path: "/",
                secure: true,
                expires: nil)
        }
        let records = [
            cookie("global", domain: "platform.minimax.io", hostOnly: true),
            cookie("china-platform", domain: "platform.minimax.cn", hostOnly: true),
            cookie("china-web", domain: "www.minimax.cn", hostOnly: true),
            cookie("china-parent", domain: "minimax.cn", hostOnly: false),
            cookie("legacy-china", domain: "platform.minimaxi.com", hostOnly: true),
            cookie("foreign", domain: "minimax.cn.attacker.example", hostOnly: true),
        ]
        let global = MiniMaxCookieImporter.scopedGroups(records, region: .global)
        #expect(global.count == 1)
        #expect(global[0].map(\.value) == ["global"])
        let china = MiniMaxCookieImporter.scopedGroups(records, region: .chinaMainland)
        #expect(china.count == 4)
        #expect(china.allSatisfy { Set($0.map(\.domain)).count == 1 && Set($0.map(\.hostOnly)).count == 1 })
        let platform = try #require(china.first { $0.first?.domain == "platform.minimax.cn" })
        #expect(try ProviderPluginCookieRecord
            .header(platform, for: #require(URL(string: "https://www.minimax.cn/"))) == nil)
        #expect(try ProviderPluginCookieRecord.header(
            platform,
            for: #require(URL(string: "https://platform.minimax.cn/"))) ==
            "HERTZ-SESSION=china-platform")
        let parent = try #require(china.first { $0.first?.domain == "minimax.cn" })
        #expect(try ProviderPluginCookieRecord.header(parent, for: #require(URL(string: "https://www.minimax.cn/"))) ==
            "HERTZ-SESSION=china-parent")
    }

    @Test
    func `browser storage tokens require proof of the cookie account`() {
        let origin = "https://platform.minimax.cn"
        let records = [
            ProviderPluginCookieRecord(
                name: "HERTZ-SESSION",
                value: "account-a",
                domain: "platform.minimax.cn",
                hostOnly: true,
                path: "/",
                secure: true,
                expires: nil),
            ProviderPluginCookieRecord(
                name: "group_id",
                value: "12345",
                domain: "platform.minimax.cn",
                hostOnly: true,
                path: "/",
                secure: true,
                expires: nil),
        ]
        #expect(MiniMaxCodingPlanFetchStrategy.matchesCookieAccount(
            token: "account-a",
            groupID: nil,
            origin: origin,
            records: records))
        #expect(MiniMaxCodingPlanFetchStrategy.matchesCookieAccount(
            token: nil,
            groupID: "12345",
            origin: origin,
            records: records))
        #expect(!MiniMaxCodingPlanFetchStrategy.matchesCookieAccount(
            token: "other-account",
            groupID: "12345",
            origin: origin,
            records: records))
        #expect(!MiniMaxCodingPlanFetchStrategy.matchesCookieAccount(
            token: "other-account",
            groupID: "67890",
            origin: origin,
            records: records))
        #expect(!MiniMaxCodingPlanFetchStrategy.matchesCookieAccount(
            token: "unproved-bearer",
            groupID: nil,
            origin: origin,
            records: records))
        #expect(!MiniMaxCodingPlanFetchStrategy.matchesCookieAccount(
            token: "account-a",
            groupID: nil,
            origin: "https://www.minimax.cn",
            records: records))
    }

    @Test
    func `scoped browser cache rejects old headers and cross region credentials`() throws {
        let record = ProviderPluginCookieRecord(
            name: "HERTZ-SESSION",
            value: "fixture",
            domain: "www.minimax.cn",
            hostOnly: true,
            path: "/",
            secure: true,
            expires: nil)
        let cache = MiniMaxCodingPlanFetchStrategy.ScopedBrowserCache(
            authority: "minimax.cn",
            scopeDomain: "www.minimax.cn",
            hostOnly: true,
            sourceLabel: "Fixture",
            records: [record],
            authorizationToken: "fixture",
            authorizationOrigin: "https://www.minimax.cn",
            groupID: nil,
            useSessionBearer: false)
        let encoded = try JSONEncoder().encode(cache).base64EncodedString()
        let entry = CookieHeaderCacheEntry(cookieHeader: "scoped=" + encoded, storedAt: .now, sourceLabel: "Fixture")
        #expect(MiniMaxCodingPlanFetchStrategy.decodeScopedCache(entry, region: .chinaMainland)?.scopeDomain ==
            "www.minimax.cn")
        #expect(MiniMaxCodingPlanFetchStrategy.decodeScopedCache(entry, region: .global) == nil)
        let mismatchedGroup = MiniMaxCodingPlanFetchStrategy.ScopedBrowserCache(
            authority: "minimax.cn",
            scopeDomain: "www.minimax.cn",
            hostOnly: true,
            sourceLabel: "Fixture",
            records: [record],
            authorizationToken: "fixture",
            authorizationOrigin: "https://www.minimax.cn",
            groupID: "98765",
            useSessionBearer: false)
        let badData = try JSONEncoder().encode(mismatchedGroup).base64EncodedString()
        let badEntry = CookieHeaderCacheEntry(cookieHeader: "scoped=" + badData, storedAt: .now, sourceLabel: "Fixture")
        #expect(MiniMaxCodingPlanFetchStrategy.decodeScopedCache(badEntry, region: .chinaMainland) == nil)
        let legacy = CookieHeaderCacheEntry(cookieHeader: "HERTZ-SESSION=legacy", storedAt: .now, sourceLabel: "Old")
        #expect(MiniMaxCodingPlanFetchStrategy.decodeScopedCache(legacy, region: .chinaMainland) == nil)
    }

    @Test
    func `session storage map discovery accepts only complete MiniMax origins`() {
        let entries = [
            ChromiumLevelDBTextEntry(key: "namespace-a-https://minimax.cn", value: "1"),
            ChromiumLevelDBTextEntry(key: "namespace-b-https://PLATFORM.MINIMAX.IO:443/", value: "2"),
            ChromiumLevelDBTextEntry(key: "namespace-c-https://www.minimaxi.com", value: "3"),
            ChromiumLevelDBTextEntry(key: "namespace-d-https://minimax.cn.attacker.example", value: "4"),
            ChromiumLevelDBTextEntry(key: "namespace-e-https://attacker.example/https://minimax.cn", value: "5"),
            ChromiumLevelDBTextEntry(key: "namespace-f-https://minimax.cn:8443", value: "6"),
            ChromiumLevelDBTextEntry(key: "namespace-g-http://minimax.cn", value: "7"),
            ChromiumLevelDBTextEntry(key: "namespace-h-https://minimax.cn@attacker.example", value: "8"),
            ChromiumLevelDBTextEntry(key: "namespace-i-https://minimax.cn?next=attacker", value: "9"),
            ChromiumLevelDBTextEntry(key: "namespace--https://minimax.cn", value: "10"),
        ]
        #expect(MiniMaxLocalStorageImporter.sessionStorageMapIDs(in: entries) == Set([1, 2, 3]))
    }

    @Test
    func `extracts access tokens from JSON preferring long tokens`() {
        let shortToken = String(repeating: "b", count: 24)
        let longToken = String(repeating: "a", count: 72)
        let payload = """
        {"access_token":"\(shortToken)","nested":{"token":"\(longToken)"}}
        """

        let tokens = MiniMaxLocalStorageImporter._extractAccessTokensForTesting(payload)

        #expect(tokens.contains(longToken))
        #expect(tokens.contains(shortToken) == false)
    }

    @Test
    func `extracts group ID from JSON string`() {
        let payload = """
        {"user":{"groupId":"98765"}}
        """

        let groupID = MiniMaxLocalStorageImporter._extractGroupIDForTesting(payload)

        #expect(groupID == "98765")
    }

    @Test
    func `resolves group ID from JWT claims`() {
        let token = Self.makeJWT(payload: [
            "iss": "minimax",
            "group_id": "12345",
            "pad": String(repeating: "x", count: 80),
        ])

        #expect(MiniMaxLocalStorageImporter._isMiniMaxJWTForTesting(token))
        #expect(MiniMaxLocalStorageImporter._groupIDFromJWTForTesting(token) == "12345")
    }

    @Test
    func `rejects non mini max JW ts without signal`() {
        let token = Self.makeJWT(payload: [
            "iss": "other",
            "pad": String(repeating: "y", count: 80),
        ])

        #expect(MiniMaxLocalStorageImporter._isMiniMaxJWTForTesting(token) == false)
    }

    private static func makeJWT(payload: [String: Any]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try? JSONSerialization.data(withJSONObject: header)
        let payloadData = try? JSONSerialization.data(withJSONObject: payload)
        let headerPart = self.base64URL(headerData ?? Data())
        let payloadPart = self.base64URL(payloadData ?? Data())
        let signature = String(repeating: "s", count: 32)
        return "\(headerPart).\(payloadPart).\(signature)"
    }

    private static func base64URL(_ data: Data) -> String {
        let raw = data.base64EncodedString()
        return raw
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
