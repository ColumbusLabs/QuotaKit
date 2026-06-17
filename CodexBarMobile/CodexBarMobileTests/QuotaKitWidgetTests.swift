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
        XCTAssertEqual(
            decoded.lastSyncedAt.timeIntervalSince1970,
            PreviewData.sampleSnapshot.syncTimestamp.timeIntervalSince1970,
            accuracy: 1.0)
        XCTAssertEqual(decoded.providers.count, snapshot.providers.count)
        XCTAssertEqual(decoded.primaryProvider?.providerName, "z.ai")
        XCTAssertTrue(decoded.providers.contains { $0.providerName == "Claude" })
        XCTAssertEqual(
            decoded.providers.first(where: { $0.providerName == "Claude" })?
                .primaryWindow?.title,
            "Session")
    }

    func testWidgetSnapshotV1PayloadDecodesWithNilPace() throws {
        let json = """
        {
            "schemaVersion": 1,
            "generatedAt": "2026-02-21T00:00:00Z",
            "providers": [
                {
                    "id": "codex",
                    "providerName": "Codex",
                    "lastUpdated": "2026-02-21T00:00:00Z",
                    "isError": false,
                    "windows": [
                        {
                            "title": "Weekly",
                            "usedPercent": 42,
                            "remainingPercent": 58
                        }
                    ]
                }
            ]
        }
        """

        let decoded = try CloudSyncConstants.makeJSONDecoder()
            .decode(QuotaKitWidgetSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.lastSyncedAt, decoded.generatedAt)
        XCTAssertNil(decoded.primaryProvider?.primaryWindow?.pace)
    }

    func testWidgetSnapshotV4PreservesPaceIdentityAndLastSyncedAt() throws {
        let pace = SyncUsagePace(
            stage: .behind,
            deltaPercent: -8,
            expectedUsedPercent: 50,
            actualUsedPercent: 42,
            leftLabel: "8% in reserve",
            rightLabel: "Lasts until reset")
        let snapshot = QuotaKitWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_803_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_802_999_900),
            providers: [
                .init(
                    id: "codex",
                    providerName: "Codex",
                    lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                    statusMessage: nil,
                    isError: false,
                    windows: [
                        .init(
                            title: "Weekly",
                            usedPercent: 42,
                            remainingPercent: 58,
                            resetsAt: nil,
                            pace: pace,
                            identity: .weekly),
                    ]),
            ])

        let data = try CloudSyncConstants.makeJSONEncoder().encode(snapshot)
        let decoded = try CloudSyncConstants.makeJSONDecoder()
            .decode(QuotaKitWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, QuotaKitWidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.lastSyncedAt, Date(timeIntervalSince1970: 1_802_999_900))
        XCTAssertEqual(decoded.primaryProvider?.primaryWindow?.pace, pace)
        XCTAssertEqual(decoded.primaryProvider?.primaryWindow?.identity, .weekly)
    }

    func testWidgetSnapshotMovesSelectedProviderFirst() throws {
        let snapshot = QuotaKitWidgetSnapshotBuilder.makeSnapshot(
            from: PreviewData.sampleSnapshot,
            generatedAt: Date(timeIntervalSince1970: 1_803_000_000),
            providerPreferences: QuotaKitWidgetProviderPreferences(
                providerOrderIDs: [],
                selectedProviderID: "claude"))

        XCTAssertEqual(snapshot.primaryProvider?.id, "claude")
        XCTAssertEqual(snapshot.primaryProvider?.providerName, "Claude")
    }

    func testWidgetSnapshotUsesProviderOrderWhenSelectionIsMissing() throws {
        let snapshot = QuotaKitWidgetSnapshotBuilder.makeSnapshot(
            from: PreviewData.sampleSnapshot,
            generatedAt: Date(timeIntervalSince1970: 1_803_000_000),
            providerPreferences: QuotaKitWidgetProviderPreferences(
                providerOrderIDs: ["codex", "claude"],
                selectedProviderID: nil))

        XCTAssertEqual(snapshot.primaryProvider?.id, "codex")
        XCTAssertEqual(snapshot.providers.dropFirst().first?.id, "claude")
    }

    func testStoredWidgetSnapshotAppliesProviderPreferencesAtReadTime() throws {
        let now = Date(timeIntervalSince1970: 1_803_000_000)
        let snapshot = QuotaKitWidgetSnapshot(
            generatedAt: now,
            providers: [
                .init(
                    id: "zai",
                    providerName: "z.ai",
                    lastUpdated: now,
                    statusMessage: nil,
                    isError: false,
                    windows: []),
                .init(
                    id: "claude",
                    providerName: "Claude",
                    lastUpdated: now,
                    statusMessage: nil,
                    isError: false,
                    windows: []),
            ])

        let reordered = snapshot.applyingProviderPreferences(
            QuotaKitWidgetProviderPreferences(
                providerOrderIDs: [],
                selectedProviderID: "claude"))

        XCTAssertEqual(reordered.primaryProvider?.id, "claude")
        XCTAssertEqual(snapshot.primaryProvider?.id, "zai")
    }

    func testWidgetSnapshotUnknownWindowIdentityDecodesAsNil() throws {
        let json = """
        {
            "schemaVersion": 4,
            "generatedAt": "2026-02-21T00:00:00Z",
            "lastSyncedAt": "2026-02-21T00:01:00Z",
            "providers": [
                {
                    "id": "codex",
                    "providerName": "Codex",
                    "lastUpdated": "2026-02-21T00:00:00Z",
                    "isError": false,
                    "windows": [
                        {
                            "title": "Monthly",
                            "usedPercent": 37,
                            "remainingPercent": 63,
                            "resetsAt": "2023-11-14T22:13:20Z",
                            "identity": "monthly"
                        }
                    ]
                }
            ]
        }
        """

        let decoded = try CloudSyncConstants.makeJSONDecoder()
            .decode(QuotaKitWidgetSnapshot.self, from: Data(json.utf8))
        let window = try XCTUnwrap(decoded.primaryProvider?.primaryWindow)

        XCTAssertEqual(window.title, "Monthly")
        XCTAssertEqual(window.usedPercent, 37)
        XCTAssertEqual(window.remainingPercent, 63)
        XCTAssertEqual(window.resetsAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(window.identity)
        XCTAssertEqual(decoded.lastSyncedAt, Date(timeIntervalSince1970: 1_771_632_060))
    }

    func testWidgetSnapshotV2PayloadFallsBackToGeneratedAtForLastSyncedAt() throws {
        let json = """
        {
            "schemaVersion": 2,
            "generatedAt": "2026-02-21T00:00:00Z",
            "providers": [
                {
                    "id": "codex",
                    "providerName": "Codex",
                    "lastUpdated": "2026-02-21T00:00:00Z",
                    "isError": false,
                    "windows": [
                        {
                            "title": "Weekly",
                            "usedPercent": 42,
                            "remainingPercent": 58
                        }
                    ]
                }
            ]
        }
        """

        let decoded = try CloudSyncConstants.makeJSONDecoder()
            .decode(QuotaKitWidgetSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.lastSyncedAt, decoded.generatedAt)
    }

    func testPreviewDemoSnapshotIncludesVisiblePace() {
        let claude = PreviewData.sampleSnapshot.providers.first { $0.providerID == "claude" }
        let codex = PreviewData.sampleSnapshot.providers.first { $0.providerID == "codex" }

        XCTAssertEqual(claude?.primary?.pace?.leftLabel, "27% in reserve")
        XCTAssertEqual(claude?.secondary?.pace?.rightLabel, "Lasts until reset")
        XCTAssertEqual(codex?.primary?.pace?.leftLabel, "18% in deficit")
        XCTAssertEqual(codex?.primary?.pace?.rightLabel, "Projected empty in 45m")
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

    func testWidgetPublisherReloadsWhenSyncTimestampChanges() {
        let generatedAt = Date(timeIntervalSince1970: 1_803_000_300)
        let firstSync = Date(timeIntervalSince1970: 1_803_000_000)
        let secondSync = Date(timeIntervalSince1970: 1_803_000_120)
        let first = SyncedUsageSnapshot(
            providers: PreviewData.sampleSnapshot.providers,
            syncTimestamp: firstSync,
            deviceName: PreviewData.sampleSnapshot.deviceName)
        let second = SyncedUsageSnapshot(
            providers: PreviewData.sampleSnapshot.providers,
            syncTimestamp: secondSync,
            deviceName: PreviewData.sampleSnapshot.deviceName)
        var savedSnapshots: [QuotaKitWidgetSnapshot] = []
        var reloadCount = 0

        WidgetSnapshotPublisher.publish(
            from: first,
            generatedAt: generatedAt,
            isProUnlocked: true,
            saveSnapshot: { savedSnapshots.append($0) },
            reloadTimelines: { reloadCount += 1 })
        WidgetSnapshotPublisher.publish(
            from: first,
            generatedAt: generatedAt.addingTimeInterval(60),
            isProUnlocked: true,
            saveSnapshot: { savedSnapshots.append($0) },
            reloadTimelines: { reloadCount += 1 })
        WidgetSnapshotPublisher.publish(
            from: second,
            generatedAt: generatedAt.addingTimeInterval(120),
            isProUnlocked: true,
            saveSnapshot: { savedSnapshots.append($0) },
            reloadTimelines: { reloadCount += 1 })

        XCTAssertEqual(reloadCount, 2)
        XCTAssertEqual(savedSnapshots.map(\.lastSyncedAt), [firstSync, firstSync, secondSync])
    }

    func testWidgetTimelineScheduleRefreshesEveryFifteenMinutesByDefault() {
        let now = Date(timeIntervalSince1970: 1_803_000_000)

        XCTAssertEqual(
            QuotaKitWidgetTimelineSchedule.nextRefreshDate(after: now, lastSyncedAt: nil),
            now.addingTimeInterval(15 * 60))
    }

    func testWidgetTimelineScheduleRefreshesAtStaleBoundaryWhenSooner() {
        let lastSyncedAt = Date(timeIntervalSince1970: 1_803_000_000)
        let now = lastSyncedAt.addingTimeInterval(59 * 60)

        XCTAssertEqual(
            QuotaKitWidgetTimelineSchedule.nextRefreshDate(after: now, lastSyncedAt: lastSyncedAt),
            lastSyncedAt.addingTimeInterval(60 * 60 + 1))
    }

    func testWidgetTimelineScheduleUsesRegularRefreshAfterStaleBoundary() {
        let lastSyncedAt = Date(timeIntervalSince1970: 1_803_000_000)
        let now = lastSyncedAt.addingTimeInterval(61 * 60)

        XCTAssertEqual(
            QuotaKitWidgetTimelineSchedule.nextRefreshDate(after: now, lastSyncedAt: lastSyncedAt),
            now.addingTimeInterval(15 * 60))
    }

    func testWidgetFreshnessThresholdMatchesAppFreshnessThreshold() {
        XCTAssertEqual(
            QuotaKitWidgetTimelineSchedule.staleThreshold,
            SyncFreshnessState.staleThreshold)
    }

    func testWidgetSyncBadgeFreshnessUsesStrictStaleThreshold() {
        let syncedAt = Date(timeIntervalSince1970: 1_803_000_000)

        XCTAssertFalse(WidgetSyncBadgeFreshness.isStale(
            lastSynced: syncedAt,
            now: syncedAt.addingTimeInterval(QuotaKitWidgetTimelineSchedule.staleThreshold)))
        XCTAssertTrue(WidgetSyncBadgeFreshness.isStale(
            lastSynced: syncedAt,
            now: syncedAt.addingTimeInterval(QuotaKitWidgetTimelineSchedule.staleThreshold + 1)))
    }

    func testWidgetSyncBadgeRelativePhraseHasTranslatedCatalogKey() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CodexBarMobile/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: data)
        let entry = try XCTUnwrap(catalog.strings["Synced %@ ago"])

        for locale in ["en", "ja", "zh-Hans", "zh-Hant"] {
            let localization = try XCTUnwrap(entry.localizations[locale])
            XCTAssertEqual(localization.stringUnit.state, "translated")
            XCTAssertFalse(localization.stringUnit.value.isEmpty)
        }
    }

    func testWidgetDisplayModeStoreDefaultsToBothForMissingAndInvalidValues() {
        let defaults = Self.makeDefaults()
        defer { defaults.removeObject(forKey: QuotaKitWidgetDisplayModeStore.key) }

        XCTAssertEqual(QuotaKitWidgetDisplayModeStore.load(defaults: defaults), .both)

        defaults.set("daily", forKey: QuotaKitWidgetDisplayModeStore.key)

        XCTAssertEqual(QuotaKitWidgetDisplayModeStore.load(defaults: defaults), .both)
    }

    func testWidgetDisplayModeStoreRoundTripsAllModes() {
        let defaults = Self.makeDefaults()
        defer { defaults.removeObject(forKey: QuotaKitWidgetDisplayModeStore.key) }

        for mode in QuotaKitWidgetDisplayMode.allCases {
            QuotaKitWidgetDisplayModeStore.save(mode, defaults: defaults)

            XCTAssertEqual(defaults.string(forKey: QuotaKitWidgetDisplayModeStore.key), mode.rawValue)
            XCTAssertEqual(QuotaKitWidgetDisplayModeStore.load(defaults: defaults), mode)
        }
    }

    func testWidgetDisplayModeStoreDoesNotFallBackToStandardDefaults() {
        UserDefaults.standard.set(
            QuotaKitWidgetDisplayMode.weekly.rawValue,
            forKey: QuotaKitWidgetDisplayModeStore.key)
        defer { UserDefaults.standard.removeObject(forKey: QuotaKitWidgetDisplayModeStore.key) }

        XCTAssertEqual(
            QuotaKitWidgetDisplayModeStore.load(appGroupDefaults: { nil }),
            .both)

        UserDefaults.standard.removeObject(forKey: QuotaKitWidgetDisplayModeStore.key)
        QuotaKitWidgetDisplayModeStore.save(.weekly, appGroupDefaults: { nil })

        XCTAssertNil(UserDefaults.standard.string(forKey: QuotaKitWidgetDisplayModeStore.key))
    }

    func testWidgetProviderPreferencesStoreRoundTripsProviderOrderAndSelection() {
        let defaults = Self.makeDefaults()
        defer {
            defaults.removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.providerOrderKey)
            defaults.removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.selectedProviderKey)
        }

        QuotaKitWidgetProviderPreferencesStore.saveProviderOrderIDs(
            ["claude", " ", "codex", "claude"],
            defaults: defaults)
        QuotaKitWidgetProviderPreferencesStore.saveSelectedProviderID(" codex ", defaults: defaults)

        XCTAssertEqual(
            QuotaKitWidgetProviderPreferencesStore.loadProviderOrderIDs(defaults: defaults),
            ["claude", "codex"])
        XCTAssertEqual(
            QuotaKitWidgetProviderPreferencesStore.loadSelectedProviderID(defaults: defaults),
            "codex")
        XCTAssertEqual(
            QuotaKitWidgetProviderPreferencesStore.load(defaults: defaults),
            QuotaKitWidgetProviderPreferences(
                providerOrderIDs: ["claude", "codex"],
                selectedProviderID: "codex"))
    }

    func testWidgetProviderPreferencesStoreDoesNotFallBackToStandardDefaults() {
        UserDefaults.standard.set(
            ["claude"],
            forKey: QuotaKitWidgetProviderPreferencesStore.providerOrderKey)
        UserDefaults.standard.set(
            "claude",
            forKey: QuotaKitWidgetProviderPreferencesStore.selectedProviderKey)
        defer {
            UserDefaults.standard.removeObject(
                forKey: QuotaKitWidgetProviderPreferencesStore.providerOrderKey)
            UserDefaults.standard.removeObject(
                forKey: QuotaKitWidgetProviderPreferencesStore.selectedProviderKey)
        }

        XCTAssertEqual(
            QuotaKitWidgetProviderPreferencesStore.load(appGroupDefaults: { nil }),
            .empty)

        QuotaKitWidgetProviderPreferencesStore.saveProviderOrderIDs(
            ["codex"],
            appGroupDefaults: { nil })
        QuotaKitWidgetProviderPreferencesStore.saveSelectedProviderID(
            "codex",
            appGroupDefaults: { nil })

        XCTAssertEqual(
            UserDefaults.standard.stringArray(
                forKey: QuotaKitWidgetProviderPreferencesStore.providerOrderKey),
            ["claude"])
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: QuotaKitWidgetProviderPreferencesStore.selectedProviderKey),
            "claude")
    }

    func testWidgetProviderPreferencesOrderingHonorsSavedOrderAndAppendsNewProvidersByName() {
        let items = [
            WidgetProviderPreferenceTestItem(id: "zai", name: "z.ai"),
            WidgetProviderPreferenceTestItem(id: "claude", name: "Claude"),
            WidgetProviderPreferenceTestItem(id: "gemini", name: "Gemini"),
            WidgetProviderPreferenceTestItem(id: "codex", name: "Codex"),
        ]

        let ordered = QuotaKitWidgetProviderPreferencesStore.orderedItems(
            items,
            preferences: QuotaKitWidgetProviderPreferences(
                providerOrderIDs: ["codex", "claude"],
                selectedProviderID: nil),
            providerID: \.id,
            providerName: \.name)

        XCTAssertEqual(ordered.map(\.id), ["codex", "claude", "gemini", "zai"])
    }

    func testWidgetProviderPreferencesEmptyOrderPreservesInputOrder() {
        let items = [
            WidgetProviderPreferenceTestItem(id: "zai", name: "z.ai"),
            WidgetProviderPreferenceTestItem(id: "claude", name: "Claude"),
            WidgetProviderPreferenceTestItem(id: "codex", name: "Codex"),
        ]

        let ordered = QuotaKitWidgetProviderPreferencesStore.orderedItems(
            items,
            preferences: .empty,
            providerID: \.id,
            providerName: \.name)

        XCTAssertEqual(ordered.map(\.id), ["zai", "claude", "codex"])
    }

    func testWidgetProviderPreferencesSelectionFallsBackToOrderedProvider() {
        let selected = QuotaKitWidgetProviderPreferencesStore.selectedProviderID(
            availableProviderIDs: ["zai", "claude", "codex"],
            preferences: QuotaKitWidgetProviderPreferences(
                providerOrderIDs: ["codex", "claude"],
                selectedProviderID: "missing"))

        XCTAssertEqual(selected, "codex")
    }

    func testWidgetEntryDisplayModeResolverUsesBothForPreviewEntries() {
        let defaults = Self.makeDefaults()
        defaults.set(
            QuotaKitWidgetDisplayMode.weekly.rawValue,
            forKey: QuotaKitWidgetDisplayModeStore.key)

        XCTAssertEqual(
            QuotaKitWidgetEntryDisplayModeResolver.resolve(
                isPreview: true,
                defaults: defaults),
            .both)
    }

    func testWidgetEntryDisplayModeResolverLoadsStoredModeForNonPreviewEntries() {
        let defaults = Self.makeDefaults()
        defaults.set(
            QuotaKitWidgetDisplayMode.session.rawValue,
            forKey: QuotaKitWidgetDisplayModeStore.key)

        XCTAssertEqual(
            QuotaKitWidgetEntryDisplayModeResolver.resolve(
                isPreview: false,
                defaults: defaults),
            .session)
    }

    func testWidgetEntryDisplayModeResolverDefaultsInvalidNonPreviewModeToBoth() {
        let defaults = Self.makeDefaults()
        defaults.set("daily", forKey: QuotaKitWidgetDisplayModeStore.key)

        XCTAssertEqual(
            QuotaKitWidgetEntryDisplayModeResolver.resolve(
                isPreview: false,
                defaults: defaults),
            .both)
    }

    func testWidgetUsageWindowResolvesNonSessionLabelsByStableSlot() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "5-hour",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "7-day",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .session)?.title, "5-hour")
        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .weekly)?.title, "7-day")
    }

    func testWidgetUsageWindowTypedIdentityBeatsMisleadingLabels() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "7-day",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil,
                    identity: .session),
                .init(
                    title: "5-hour",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil,
                    identity: .weekly),
            ])

        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .session)?.title, "7-day")
        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .weekly)?.title, "5-hour")
    }

    func testWidgetBothModeTypedIdentityBeatsSlotOrder() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Weekly quota",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil,
                    identity: .weekly),
                .init(
                    title: "Session quota",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil,
                    identity: .session),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.map(\.mode), [.session, .weekly])
        XCTAssertEqual(windows.map(\.window.title), ["Session quota", "Weekly quota"])
    }

    func testWidgetUsageWindowPrefersFirstExplicitWeeklyLane() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "5-hour",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "Weekly Sonnet",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "Weekly Opus",
                    usedPercent: 35,
                    remainingPercent: 65,
                    resetsAt: nil,
                    pace: nil),
            ])

        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .weekly)?.title, "Weekly Sonnet")
    }

    func testWidgetWeeklyResolutionSkipsDailyAndMonthlyDayCounts() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "1 day",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "30 days",
                    usedPercent: 45,
                    remainingPercent: 55,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "7-day",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .weekly)?.title, "7-day")
    }

    func testWidgetBothModeReturnsDistinctWindowsOnly() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Session",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "Weekly",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.map(\.mode), [.session, .weekly])
        XCTAssertEqual(windows.map(\.window.title), ["Session", "Weekly"])
    }

    func testWidgetBothModeDoesNotDuplicateSingleAvailableWindow() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Session",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.mode, .session)
        XCTAssertEqual(windows.first?.window.title, "Session")
    }

    func testWidgetBothModeUsesStableSlotsForNonSessionLabels() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "5-hour",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "7-day",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.map(\.mode), [.session, .weekly])
        XCTAssertEqual(windows.map(\.window.title), ["5-hour", "7-day"])
    }

    func testWidgetBothModeLabelsUseResolvedDisplayModes() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "5-hour",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "7-day",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.map(\.title), ["Session", "Weekly"])
    }

    func testAccessoryRectangularBothModeDetailTextUsesResolvedDisplayModes() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "5-hour",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "7-day",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        let detailText = QuotaKitWidgetPresentation.accessoryDetailText(
            for: provider,
            displayMode: .both)

        XCTAssertEqual(detailText, "Session 39% · Weekly 80%")
        XCTAssertFalse(detailText.contains("5-hour"))
        XCTAssertFalse(detailText.contains("7-day"))
    }

    func testWidgetBothModeKeepsPrimaryWindowWhenWeeklyIsExplicitSecondWindow() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Quota",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "Weekly",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.map(\.mode), [.session, .weekly])
        XCTAssertEqual(windows.map(\.window.title), ["Quota", "Weekly"])
    }

    func testWidgetBothModePreservesWeeklyOnlyWindowMode() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Weekly",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.mode, .weekly)
        XCTAssertEqual(windows.first?.window.title, "Weekly")
    }

    func testWidgetBothModeDoesNotTreatDailyWindowAsWeekly() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Daily",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.mode, .session)
        XCTAssertEqual(windows.first?.window.title, "Daily")
    }

    func testWidgetBothModeTreatsSevenDayWindowAsWeekly() {
        for title in ["7-day", "7 days"] {
            let provider = QuotaKitWidgetSnapshot.Provider(
                id: "claude",
                providerName: "Claude",
                lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                statusMessage: nil,
                isError: false,
                windows: [
                    .init(
                        title: "5-hour",
                        usedPercent: 61,
                        remainingPercent: 39,
                        resetsAt: nil,
                        pace: nil),
                    .init(
                        title: title,
                        usedPercent: 20,
                        remainingPercent: 80,
                        resetsAt: nil,
                        pace: nil),
                ])

            let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

            XCTAssertEqual(windows.map(\.mode), [.session, .weekly])
            XCTAssertEqual(windows.map(\.window.title), ["5-hour", title])
        }
    }

    func testWidgetBothModeDoesNotTreatNumericNonWeeklyDayWindowsAsWeekly() {
        for title in ["1day", "1 day", "14 days", "30-day", "30 days"] {
            let provider = QuotaKitWidgetSnapshot.Provider(
                id: "claude",
                providerName: "Claude",
                lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                statusMessage: nil,
                isError: false,
                windows: [
                    .init(
                        title: "5-hour",
                        usedPercent: 61,
                        remainingPercent: 39,
                        resetsAt: nil,
                        pace: nil),
                    .init(
                        title: title,
                        usedPercent: 20,
                        remainingPercent: 80,
                        resetsAt: nil,
                        pace: nil),
                ])

            let windows = QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both)

            XCTAssertEqual(windows.count, 1)
            XCTAssertEqual(windows.first?.mode, .session)
            XCTAssertEqual(windows.first?.window.title, "5-hour")
        }
    }

    func testWidgetCircularBothModeUsesSessionOrPrimaryFallback() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "5-hour",
                    usedPercent: 61,
                    remainingPercent: 39,
                    resetsAt: nil,
                    pace: nil),
                .init(
                    title: "7-day",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .both)?.title, "5-hour")
    }

    func testWidgetCircularBothModeFallsBackToWeeklyOnlyWindow() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: nil,
            isError: false,
            windows: [
                .init(
                    title: "Weekly",
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: nil,
                    pace: nil),
            ])

        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .both)?.title, "Weekly")
    }

    func testWidgetBothModeReturnsNoWindowsWhenProviderHasNoWindows() {
        let provider = QuotaKitWidgetSnapshot.Provider(
            id: "claude",
            providerName: "Claude",
            lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
            statusMessage: "Waiting for sync",
            isError: false,
            windows: [])

        XCTAssertTrue(QuotaKitWidgetPresentation.displayWindows(for: provider, displayMode: .both).isEmpty)
    }

    func testLockedWidgetPlaceholderRendersForAllFamilies() {
        for family in Self.widgetFamilies {
            let view = QuotaKitWidgetView(
                entry: .init(
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
            let view = QuotaKitWidgetView(
                entry: .init(
                    date: Date(),
                    snapshot: QuotaKitWidgetPreviewData.snapshot,
                    isUnlocked: true,
                    isPreview: false),
                overrideFamily: family)
            XCTAssertNotNil(self.renderToImage(view), "Expected unlocked widget to render for \(family)")
        }
    }

    func testUnlockedBothModeWidgetRendersForAllFamilies() {
        for family in Self.widgetFamilies {
            let view = QuotaKitWidgetView(
                entry: .init(
                    date: Date(),
                    snapshot: QuotaKitWidgetPreviewData.snapshot,
                    isUnlocked: true,
                    isPreview: false,
                    displayMode: .both),
                overrideFamily: family)
            XCTAssertNotNil(self.renderToImage(view), "Expected both-mode widget to render for \(family)")
        }
    }

    func testWidgetFreshnessRendersForVisibleTimestampFamilies() {
        let snapshot = QuotaKitWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_803_000_300),
            lastSyncedAt: Date(timeIntervalSince1970: 1_803_000_000),
            providers: QuotaKitWidgetPreviewData.snapshot.providers)

        for family in Self.timestampWidgetFamilies {
            let view = QuotaKitWidgetView(
                entry: .init(
                    date: Date(timeIntervalSince1970: 1_803_000_300),
                    snapshot: snapshot,
                    isUnlocked: true,
                    isPreview: false,
                    displayMode: .both),
                overrideFamily: family)

            XCTAssertNotNil(
                self.renderToImage(view),
                "Expected synced timestamp widget to render for \(family)")
        }
    }

    func testAccessoryRectangularFreshnessRendersInConstrainedFrame() throws {
        let snapshot = QuotaKitWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_803_000_300),
            lastSyncedAt: Date(timeIntervalSince1970: 1_803_000_000),
            providers: QuotaKitWidgetPreviewData.snapshot.providers)
        let view = QuotaKitWidgetView(
            entry: .init(
                date: Date(timeIntervalSince1970: 1_803_000_300),
                snapshot: snapshot,
                isUnlocked: true,
                isPreview: false,
                displayMode: .session),
            overrideFamily: .accessoryRectangular)

        let image = try XCTUnwrap(
            self.renderAccessoryRectangularWidgetToImage(view),
            "Expected accessory rectangular widget freshness to render in a constrained frame")
        self.assertAccessoryRectangularWidgetRowsAreVisible(in: image)
    }

    func testAccessoryRectangularBothModeFreshnessRendersInConstrainedFrame() throws {
        let snapshot = QuotaKitWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_803_000_300),
            lastSyncedAt: Date(timeIntervalSince1970: 1_803_000_000),
            providers: [
                .init(
                    id: "claude",
                    providerName: "Claude Enterprise",
                    lastUpdated: Date(timeIntervalSince1970: 1_803_000_000),
                    statusMessage: nil,
                    isError: false,
                    windows: [
                        .init(
                            title: "5-hour",
                            usedPercent: 61,
                            remainingPercent: 39,
                            resetsAt: nil,
                            pace: nil),
                        .init(
                            title: "7-day",
                            usedPercent: 20,
                            remainingPercent: 80,
                            resetsAt: nil,
                            pace: nil),
                    ]),
            ])
        let view = QuotaKitWidgetView(
            entry: .init(
                date: Date(timeIntervalSince1970: 1_803_000_300),
                snapshot: snapshot,
                isUnlocked: true,
                isPreview: false,
                displayMode: .both),
            overrideFamily: .accessoryRectangular)

        let image = try XCTUnwrap(
            self.renderAccessoryRectangularWidgetToImage(view),
            "Expected both-mode accessory rectangular widget freshness to render in a constrained frame")
        self.assertAccessoryRectangularWidgetRowsAreVisible(in: image)
    }

    func testUnlockedSmallWidgetRendersCleanGlanceLayout() {
        let provider = QuotaKitWidgetPreviewData.snapshot.providers[0]
        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .session)?.title, "Session")

        let view = QuotaKitWidgetView(
            entry: .init(
                date: Date(),
                snapshot: QuotaKitWidgetPreviewData.snapshot,
                isUnlocked: true,
                isPreview: false,
                displayMode: .session),
            overrideFamily: .systemSmall)

        XCTAssertNotNil(
            self.renderSmallWidgetToImage(view),
            "Expected paid small widget glance layout to render")
    }

    func testUnlockedSmallWidgetRendersWeeklyConfiguration() {
        let provider = QuotaKitWidgetPreviewData.snapshot.providers[0]
        XCTAssertEqual(QuotaKitWidgetPresentation.primaryWindow(for: provider, displayMode: .weekly)?.title, "Weekly")

        let view = QuotaKitWidgetView(
            entry: .init(
                date: Date(),
                snapshot: QuotaKitWidgetPreviewData.snapshot,
                isUnlocked: true,
                isPreview: false,
                displayMode: .weekly),
            overrideFamily: .systemSmall)

        XCTAssertNotNil(
            self.renderSmallWidgetToImage(view),
            "Expected paid small widget weekly configuration to render")
    }

    func testEmptyWidgetRendersWithoutCrashing() {
        for family in Self.widgetFamilies {
            let view = QuotaKitWidgetView(
                entry: .init(
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

    private static let timestampWidgetFamilies: [WidgetFamily] = [
        .systemSmall,
        .systemMedium,
        .accessoryRectangular,
    ]

    private func renderToImage(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 360, height: 180))
        renderer.scale = 2.0
        return renderer.uiImage
    }

    private func renderSmallWidgetToImage(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 170, height: 170))
        renderer.scale = 2.0
        return renderer.uiImage
    }

    private func renderAccessoryRectangularWidgetToImage(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 160, height: 50))
        renderer.scale = 2.0
        return renderer.uiImage
    }

    private func assertAccessoryRectangularWidgetRowsAreVisible(
        in image: UIImage,
        file: StaticString = #filePath,
        line: UInt = #line)
    {
        let visibleRows = [
            ("provider row", 0..<22, 45),
            ("quota row", 18..<36, 30),
            ("sync row", 34..<50, 16),
        ].map { name, yRange, minimumVisiblePixels in
            (name, self.visiblePixelCount(in: image, yPointRange: yRange), minimumVisiblePixels)
        }

        for (name, visiblePixels, minimumVisiblePixels) in visibleRows {
            XCTAssertGreaterThan(
                visiblePixels,
                minimumVisiblePixels,
                "Expected \(name) to have visible rendered content in accessory rectangular widget",
                file: file,
                line: line)
        }
    }

    private func visiblePixelCount(in image: UIImage, yPointRange: Range<CGFloat>) -> Int {
        guard let cgImage = image.cgImage else { return 0 }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo)
        else {
            return 0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let scale = image.scale > 0
            ? image.scale
            : CGFloat(width) / max(image.size.width, 1)
        let yStart = max(0, Int((yPointRange.lowerBound * scale).rounded(.down)))
        let yEnd = min(height, Int((yPointRange.upperBound * scale).rounded(.up)))
        guard yStart < yEnd else { return 0 }

        var visiblePixels = 0
        for y in yStart..<yEnd {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = bytes[offset]
                let green = bytes[offset + 1]
                let blue = bytes[offset + 2]
                let alpha = bytes[offset + 3]
                if alpha > 8, max(red, green, blue) > 24 {
                    visiblePixels += 1
                }
            }
        }
        return visiblePixels
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

private struct StringCatalog: Decodable {
    let strings: [String: Entry]

    struct Entry: Decodable {
        let localizations: [String: Localization]
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit
    }

    struct StringUnit: Decodable {
        let state: String
        let value: String
    }
}

private struct WidgetProviderPreferenceTestItem {
    let id: String
    let name: String
}
