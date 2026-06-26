import CodexBarSync
import Foundation
import XCTest
@testable import CodexBarMobile

@MainActor
final class RemoteConfigTests: XCTestCase {
    func testDecodesSupportedConfigAndIgnoresUnknownFields() throws {
        let data = Data("""
        {
          "schemaVersion": 1,
          "configVersion": "test.1",
          "minimumSupportedBuild": 100,
          "recommendedBuild": 200,
          "macSetupURL": "https://example.com/setup",
          "disabledFeatureIDs": ["shareCards"],
          "announcements": [
            {
              "id": "hello",
              "title": "Hello",
              "body": "World",
              "isEnabled": true
            }
          ],
          "futureField": "ignored"
        }
        """.utf8)

        let config = try RemoteConfigStore.decodeSupportedConfig(data)

        XCTAssertEqual(config.configVersion, "test.1")
        XCTAssertEqual(config.minimumSupportedBuild, 100)
        XCTAssertEqual(config.recommendedBuild, 200)
        XCTAssertEqual(config.effectiveMacSetupURL.absoluteString, "https://example.com/setup")
        XCTAssertTrue(config.disables(.shareCards))
        XCTAssertEqual(config.activeAnnouncements.first?.id, "hello")
    }

    func testUnsupportedFutureSchemaIsRejected() {
        let data = Data("""
        {
          "schemaVersion": 99,
          "configVersion": "future",
          "disabledFeatureIDs": []
        }
        """.utf8)

        XCTAssertThrowsError(try RemoteConfigStore.decodeSupportedConfig(data)) { error in
            XCTAssertEqual(error as? RemoteConfigStore.Error, .unsupportedSchema(99))
        }
    }

    func testInvalidSetupURLFallsBackToProductDefault() {
        let config = RemoteConfig(
            schemaVersion: 1,
            configVersion: "bad-url",
            macSetupURL: "http://example.com/not-https")

        XCTAssertEqual(config.effectiveMacSetupURL, ProductConfig.macSetupURL)
        XCTAssertEqual(config.effectiveMacSetupDisplayURL, ProductConfig.macSetupDisplayURL)
    }

    func testRefreshCachesLastValidConfigAndFailedRefreshKeepsCache() async throws {
        let defaults = Self.makeDefaults()
        defer { defaults.clear() }

        let first = try RemoteConfigStore(
            defaults: defaults.store,
            fetcher: FakeRemoteConfigFetcher(result: .success(Self.configData(version: "remote.1"))),
            configURL: XCTUnwrap(URL(string: "https://example.com/config.json")))

        await first.refresh()

        XCTAssertEqual(first.source, .remote)
        XCTAssertEqual(first.config.configVersion, "remote.1")

        let second = try RemoteConfigStore(
            defaults: defaults.store,
            fetcher: FakeRemoteConfigFetcher(result: .invalidResponse),
            configURL: XCTUnwrap(URL(string: "https://example.com/config.json")))

        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(second.config.configVersion, "remote.1")

        await second.refresh()

        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(second.config.configVersion, "remote.1")
        XCTAssertEqual(second.lastError, String(localized: "Invalid remote config response"))
    }

    func testBundledDefaultsPreserveSetupURLAndNoDisabledFeatures() throws {
        let store = try RemoteConfigStore(
            defaults: Self.makeDefaults().store,
            fetcher: FakeRemoteConfigFetcher(result: .invalidResponse),
            configURL: XCTUnwrap(URL(string: "https://example.com/config.json")))

        XCTAssertEqual(store.source, .bundled)
        XCTAssertEqual(store.setupURL, ProductConfig.macSetupURL)
        XCTAssertFalse(store.isDisabled(.fullCostDashboard))
    }

    func testDisabledFeatureLookupUsesKnownRawValues() {
        let config = RemoteConfig(
            schemaVersion: 1,
            configVersion: "disabled",
            disabledFeatureIDs: ["usageHistory", "unknownFutureFeature"])

        XCTAssertTrue(config.disables(.usageHistory))
        XCTAssertFalse(config.disables(.shareCards))
    }

    private static func configData(version: String) -> Data {
        Data("""
        {
          "schemaVersion": 1,
          "configVersion": "\(version)",
          "minimumSupportedBuild": 1,
          "recommendedBuild": 159,
          "macSetupURL": "https://columbus-labs.com/quotakit/mac",
          "disabledFeatureIDs": [],
          "announcements": []
        }
        """.utf8)
    }

    private static func makeDefaults() -> TestDefaults {
        let suiteName = "quotakit.remote-config.tests.\(UUID().uuidString)"
        return TestDefaults(
            suiteName: suiteName,
            store: UserDefaults(suiteName: suiteName)!)
    }
}

private struct TestDefaults {
    let suiteName: String
    let store: UserDefaults

    func clear() {
        self.store.removePersistentDomain(forName: self.suiteName)
    }
}

private enum FakeRemoteConfigResult: Sendable {
    case success(Data)
    case invalidResponse
}

private struct FakeRemoteConfigFetcher: RemoteConfigFetching {
    let result: FakeRemoteConfigResult

    func data(from _: URL) async throws -> Data {
        switch self.result {
        case let .success(data):
            data
        case .invalidResponse:
            throw RemoteConfigStore.Error.invalidResponse
        }
    }
}
