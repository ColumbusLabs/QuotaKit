import CodexBarSync
import SwiftUI
import WidgetKit
import XCTest

@testable import CodexBarMobile

@MainActor
final class QuotaKitWidgetTests: XCTestCase {

    override func tearDown() {
        WidgetSnapshotPublisher.resetPublishedDataForTests()
        super.tearDown()
    }

    func testWidgetSnapshotRoundTripsWithProjectJSONCodec() throws {
        let snapshot = QuotaKitWidgetSnapshotBuilder.makeSnapshot(
            from: PreviewData.sampleSnapshot,
            generatedAt: Date(timeIntervalSince1970: 1_803_000_000))

        let data = try CloudSyncConstants.makeJSONEncoder().encode(snapshot)
        let decoded = try CloudSyncConstants.makeJSONDecoder()
            .decode(QuotaKitWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, QuotaKitWidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(
            decoded.generatedAt.timeIntervalSince1970,
            snapshot.generatedAt.timeIntervalSince1970,
            accuracy: 0.001)
        XCTAssertEqual(decoded.providers.count, snapshot.providers.count)
        XCTAssertEqual(decoded.primaryProvider?.providerName, "z.ai")
        XCTAssertTrue(decoded.providers.contains { $0.providerName == "Claude" })
        XCTAssertEqual(
            decoded.providers.first(where: { $0.providerName == "Claude" })?
                .primaryWindow?.title,
            "Session")
    }

    func testWidgetSnapshotDoesNotEncodeAccountEmailsOrCredentialLikeFields() throws {
        let snapshot = QuotaKitWidgetSnapshotBuilder.makeSnapshot(
            from: PreviewData.sampleSnapshot,
            generatedAt: Date(timeIntervalSince1970: 1_803_000_000))
        let data = try CloudSyncConstants.makeJSONEncoder().encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("user@example.com"))
        XCTAssertFalse(json.contains("primary-mock@antigravity.test"))
        XCTAssertFalse(json.contains("alt-mock@antigravity.test"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("accountEmail"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("accessToken"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("refreshToken"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("cookie"))
    }

    func testWidgetSnapshotRedactsEmailLikeStatusMessages() throws {
        let base = PreviewData.sampleSnapshot.providers[0]
        let provider = ProviderUsageSnapshot(
            providerID: base.providerID,
            providerName: base.providerName,
            primary: base.primary,
            secondary: base.secondary,
            accountEmail: base.accountEmail,
            loginMethod: base.loginMethod,
            statusMessage: "Error for user@example.com",
            isError: true,
            lastUpdated: base.lastUpdated,
            costSummary: base.costSummary,
            budget: base.budget,
            rateWindows: base.rateWindows,
            utilizationHistory: base.utilizationHistory,
            accountIdentities: base.accountIdentities)

        let synced = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: PreviewData.sampleSnapshot.syncTimestamp,
            deviceName: PreviewData.sampleSnapshot.deviceName)
        let widgetSnapshot = QuotaKitWidgetSnapshotBuilder.makeSnapshot(
            from: synced,
            generatedAt: Date(timeIntervalSince1970: 1_803_000_000))
        let data = try CloudSyncConstants.makeJSONEncoder().encode(widgetSnapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("user@example.com"))
        XCTAssertNil(widgetSnapshot.providers.first?.statusMessage)
    }

    func testProEntitlementCacheAcceptsOnlyQuotaKitProductID() {
        let defaults = Self.makeDefaults()
        defer { ProEntitlementCacheStore.clear(defaults: defaults) }
        let cache = ProEntitlementCache(
            productID: ProductConfig.storeKitLifetimeProductID,
            verifiedAt: Date(timeIntervalSince1970: 1_803_000_000))

        ProEntitlementCacheStore.save(cache, defaults: defaults)

        XCTAssertEqual(ProEntitlementCacheStore.load(defaults: defaults), cache)

        ProEntitlementCacheStore.save(
            ProEntitlementCache(
                productID: "com.example.other",
                verifiedAt: Date()),
            defaults: defaults)

        XCTAssertNil(ProEntitlementCacheStore.load(defaults: defaults))
    }

    func testProEntitlementCacheMigratesFromLegacyWidgetProCacheKey() {
        let defaults = Self.makeDefaults()
        defer {
            defaults.removeObject(forKey: ProEntitlementCacheStore.key)
            defaults.removeObject(forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey)
        }

        let legacyPayload = """
        {"isProUnlocked":true,"productID":"\(ProductConfig.storeKitLifetimeProductID)","verifiedAt":1803000000}
        """.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey)

        let loaded = ProEntitlementCacheStore.load(defaults: defaults)
        XCTAssertEqual(loaded?.productID, ProductConfig.storeKitLifetimeProductID)
        XCTAssertNil(defaults.data(forKey: ProEntitlementCacheStore.legacyWidgetProCacheKey))
    }

    func testWidgetSnapshotStoreRoundTripsThroughTempDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotakit-widget-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = QuotaKitWidgetPreviewData.snapshot
        let fileURL = tempDir.appendingPathComponent(QuotaKitWidgetSnapshotStore.filename)
        let fileManager = FileManager.default

        QuotaKitWidgetSnapshotStore.saveForTesting(
            snapshot,
            at: tempDir,
            fileManager: fileManager)

        guard let loaded = QuotaKitWidgetSnapshotStore.loadForTesting(
            at: tempDir,
            fileManager: fileManager)
        else {
            XCTFail("Expected widget snapshot to load from temp directory")
            return
        }

        XCTAssertEqual(loaded.schemaVersion, snapshot.schemaVersion)
        XCTAssertEqual(loaded.providers.count, snapshot.providers.count)
        XCTAssertEqual(loaded.primaryProvider?.providerName, snapshot.primaryProvider?.providerName)
        QuotaKitWidgetSnapshotStore.clearForTesting(
            at: tempDir,
            fileManager: fileManager)
        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path))
    }

    func testWidgetSnapshotStoreUsesQuotaKitAppGroupConstant() {
        XCTAssertEqual(ProductConfig.appGroupIdentifier, "group.com.columbuslabs.quotakit")
        XCTAssertEqual(QuotaKitWidgetSnapshotStore.filename, "quotakit-widget-snapshot.json")
    }

    func testLockedWidgetPlaceholderRendersForAllFamilies() {
        for family in Self.widgetFamilies {
            let view = QuotaKitWidgetView(entry: .init(
                date: Date(),
                snapshot: QuotaKitWidgetPreviewData.snapshot,
                isUnlocked: false,
                isPreview: false),
                overrideFamily: family)
            XCTAssertNotNil(self.renderToImage(view), "Expected locked widget to render for \(family)")
        }
    }

    func testUnlockedWidgetRendersForAllFamilies() {
        for family in Self.widgetFamilies {
            let view = QuotaKitWidgetView(entry: .init(
                date: Date(),
                snapshot: QuotaKitWidgetPreviewData.snapshot,
                isUnlocked: true,
                isPreview: false),
                overrideFamily: family)
            XCTAssertNotNil(self.renderToImage(view), "Expected unlocked widget to render for \(family)")
        }
    }

    func testEmptyWidgetRendersWithoutCrashing() {
        for family in Self.widgetFamilies {
            let view = QuotaKitWidgetView(entry: .init(
                date: Date(),
                snapshot: nil,
                isUnlocked: true,
                isPreview: false),
                overrideFamily: family)
            XCTAssertNotNil(self.renderToImage(view), "Expected empty widget to render for \(family)")
        }
    }

    private static let widgetFamilies: [WidgetFamily] = [
        .systemSmall,
        .systemMedium,
        .accessoryRectangular,
        .accessoryCircular,
    ]

    private func renderToImage<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 360, height: 180))
        renderer.scale = 2.0
        return renderer.uiImage
    }

    private static func makeDefaults(
        file: StaticString = #filePath,
        line: UInt = #line) -> UserDefaults
    {
        let suiteName = "quotakit.widget.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test UserDefaults suite", file: file, line: line)
            return .standard
        }
        return defaults
    }
}
